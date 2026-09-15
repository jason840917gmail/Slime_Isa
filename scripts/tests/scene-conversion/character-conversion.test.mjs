import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { visualSceneAdapter } from '../../lib/scene-conversion/animations.mjs';
import { characterSceneAdapter, enemySceneAdapter } from '../../lib/scene-conversion/characters.mjs';
import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const unitKeys = [
  'visual:enemy.slime.spider',
  'visual:enemy.worm.archer',
  'visual:enemy.worm.swordsman',
  'character:slime-spider',
  'character:worm-archer',
  'character:worm-swordsman',
  'enemy:worm-archer',
  'enemy:worm-swordsman',
];

async function createRunner() {
  const ledger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
  return new ConversionRunner({
    repositoryRoot,
    ledger,
    adapters: {
      visual: visualSceneAdapter,
      character: characterSceneAdapter,
      enemy: enemySceneAdapter,
    },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'universal-character-slice-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
  });
}

function scriptProperties(scene) {
  return scene.nodes.find((node) => node.scriptId === 'game.enemy').properties;
}

test('remaining enemy converters are byte-stable and preserve authored combat semantics', async () => {
  const runner = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const second = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(second.outputs, first.outputs);

  const applied = await runner.run({ unitKeys, mode: 'apply' });
  assert.deepEqual((await runner.run({ unitKeys, mode: 'check' })).outputs, applied.outputs);
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));

  const archer = scriptProperties(await load('characters/worm-archer.scene.json'));
  assert.equal(archer.maxHealth, 40);
  assert.equal(archer.attributes.fleeRange, 120);
  assert.equal(archer.attributes.projectileSpeed, 180);
  assert.equal(archer.projectile.damage, 22);

  const swordsman = scriptProperties(await load('characters/worm-swordsman.scene.json'));
  assert.equal(swordsman.maxHealth, 90);
  assert.equal(swordsman.attackRange, 38);
  assert.equal(swordsman.movementSpeed, 75);
  assert.equal(swordsman.attributes.contactDamage, 37);

  const spider = scriptProperties(await load('characters/slime-spider.scene.json'));
  assert.equal(spider.attributes.behavior, 'slime-spider');
  assert.equal(spider.attributes.isRanged, true);
  assert.equal(spider.projectile.damage, 50);
  assert.deepEqual((await load('resources/characters/slime-spider.body-shape.resource.json')).value, {
    shape: 'ellipse', radiusX: 15, radiusY: 12,
  });
});
