import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { effectSceneAdapter, projectileSceneAdapter, weaponSceneAdapter } from '../../lib/scene-conversion/combat-entities.mjs';
import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const unitKeys = [
  'weapon:basic-spear', 'weapon:basic-sword', 'weapon:goo-gauntlet', 'weapon:pickaxe', 'weapon:slam-hammer',
  'weapon:stone-axe', 'weapon:stone-pickaxe', 'weapon:stone-spear', 'weapon:wooden-axe', 'weapon:wooden-spear',
  'projectile:worm-arrow',
  'effect:basic-spear-impact', 'effect:basic-sword-impact', 'effect:slam-hammer-impact', 'effect:stone-impact', 'effect:wood-impact',
];

async function createRunner() {
  const productionLedger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const selected = new Set(unitKeys);
  const ledger = { ...productionLedger, rows: productionLedger.rows.map((row) => selected.has(row.key) ? { ...row, writerState: 'legacy' } : row) };
  const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
  return new ConversionRunner({
    repositoryRoot,
    ledger,
    adapters: { weapon: weaponSceneAdapter, projectile: projectileSceneAdapter, effect: effectSceneAdapter },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'combat-scene-conversion-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
  });
}

test('combat entity conversion is deterministic and accounts for every selected unit', async () => {
  const runner = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const replay = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(replay.outputs, first.outputs);
  assert.deepEqual(first.units, [...unitKeys].sort());
  assert.equal(first.outputs.length, unitKeys.length);
});

test('converted combat scenes own timelines, collision geometry, and runtime script identity', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));

  const sword = await load('weapons/basic-sword.scene.json');
  assert.equal(sword.nodes.filter((node) => node.type === 'AnimationPlayer').length, 1);
  assert.equal(sword.nodes.find((node) => node.scriptId === 'game.weapon').properties.baseDamage, 20);
  assert.ok(sword.nodes.some((node) => node.name === 'right--primary' && node.type === 'CollisionShape2D'));
  assert.ok(sword.nodes.filter((node) => node.type === 'CollisionShape2D').every((node) => node.properties.rotation === 0));
  assert.ok(sword.subresources.find((resource) => resource.resourceId === 'weapon.basic-sword.animations').animations['attack-right']);
  assert.deepEqual(sword.connections, [{ source: { nodeId: 'attack-area' }, signal: 'area_entered', target: { nodeId: 'script' }, handler: 'on_area_entered' }]);

  const hammer = await load('weapons/slam-hammer.scene.json');
  assert.ok(hammer.nodes.filter((node) => node.type === 'CollisionShape2D').every((node) => node.properties.rotation === 0));
  assert.equal(hammer.nodes.find((node) => node.scriptId === 'game.weapon').properties.attackPlans.right.hitboxSpans[0].knockbackMultiplier, 1.35);
  for (const key of unitKeys.filter((candidate) => candidate.startsWith('weapon:'))) {
    const weaponId = key.slice('weapon:'.length);
    assert.deepEqual(
      JSON.parse(await readFile(path.join(repositoryRoot, `src/game/content/scenes/authored/weapons/${weaponId}.scene.json`), 'utf8')),
      await load(`weapons/${weaponId}.scene.json`),
      `${weaponId} authored scene must match deterministic conversion`,
    );
  }

  const arrow = await load('projectiles/worm-arrow.scene.json');
  assert.equal(arrow.rootNodeId, 'body');
  assert.equal(arrow.nodes.find((node) => node.scriptId === 'game.projectile').properties.lifetimeMs, 3000);
  assert.equal(arrow.nodes.filter((node) => node.type === 'AnimationPlayer').length, 1);
  assert.ok(arrow.nodes.some((node) => node.id === 'attack-area'));
  assert.deepEqual(arrow.connections, [{ source: { nodeId: 'attack-area' }, signal: 'area_entered', target: { nodeId: 'script' }, handler: 'on_area_entered' }]);
  assert.deepEqual(
    JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/scenes/authored/projectiles/worm-arrow.scene.json'), 'utf8')),
    arrow,
  );

  const impact = await load('effects/basic-sword-impact.scene.json');
  assert.equal(impact.nodes.find((node) => node.scriptId === 'game.effect').properties.effectId, 'basic-sword-impact');
  assert.equal(impact.nodes.filter((node) => node.type === 'AnimationPlayer').length, 1);
  assert.deepEqual(Object.keys(impact.subresources.find((resource) => resource.kind === 'animation-library').animations), ['right', 'left', 'up', 'down']);
});
