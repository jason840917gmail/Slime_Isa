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
  'visual:character.player.slime',
  'visual:character.npc.lili',
  'visual:character.npc.mossy-scout',
  'visual:character.npc.red-slime-boy',
  'visual:character.npc.village-elder-plop',
  'visual:character.npc.yellow-blond-slime-girl',
  'visual:enemy.slime.spider',
  'visual:enemy.worm.archer',
  'visual:enemy.worm.swordsman',
  'character:slime-spider',
  'character:player-slime',
  'character:lili',
  'character:mossy-scout',
  'character:red-slime-boy',
  'character:village-elder-plop',
  'character:yellow-blond-slime-girl',
  'character:worm-archer',
  'character:worm-swordsman',
  'enemy:worm-archer',
  'enemy:worm-swordsman',
];

async function createRunner() {
  const productionLedger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const replayUnitKeys = new Set(unitKeys);
  const ledger = {
    ...productionLedger,
    rows: productionLedger.rows.map((row) => replayUnitKeys.has(row.key) ? { ...row, writerState: 'legacy' } : row),
  };
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

/** Single-owner shapes, sprite sheets, and animation libraries are embedded in their scene. */
function subresource(scene, resourceId) {
  const resource = (scene.subresources ?? []).find((candidate) => candidate.resourceId === resourceId);
  assert.ok(resource, `scene '${scene.sceneId}' should embed '${resourceId}'`);
  return resource;
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

  const spiderScene = await load('characters/slime-spider.scene.json');
  const spider = scriptProperties(spiderScene);
  assert.equal(spider.attributes.behavior, 'slime-spider');
  assert.equal(spider.attributes.isRanged, true);
  assert.equal(spider.projectile.damage, 50);
  assert.deepEqual(subresource(spiderScene, 'slime-spider.body-shape').value, {
    shape: 'ellipse', radiusX: 15, radiusY: 12,
  });

  const player = await load('characters/player-slime.scene.json');
  const playerScript = player.nodes.find((node) => node.scriptId === 'game.player').properties;
  assert.equal(playerScript.playerName, 'bob');
  assert.equal(Object.hasOwn(playerScript, 'movementSpeed'), false);
  assert.deepEqual(player.nodes.find((node) => node.id === 'visual').properties.scale, [0.28125, 0.28125]);
  assert.deepEqual(player.nodes.find((node) => node.id === 'pickup-area').properties, {
    collisionLayer: 32,
    collisionMask: 64,
    monitoring: true,
    monitorable: true,
  });
  assert.equal(player.nodes.find((node) => node.id === 'pickup-shape').properties.shape.resourceId, 'player-slime.body-shape');
  assert.deepEqual(subresource(player, 'player-slime.body-shape').value, {
    shape: 'rectangle', width: 30, height: 26,
  });

  const elder = await load('characters/village-elder-plop.scene.json');
  const elderScript = elder.nodes.find((node) => node.scriptId === 'game.npc').properties;
  assert.equal(elderScript.characterId, 'village-elder-plop');
  assert.equal(elderScript.wanderSpeed, 18);
  assert.equal(elderScript.pauseMinMs, 3000);
  assert.equal(elderScript.pauseMaxMs, 50000);
  assert.deepEqual(elder.nodes.find((node) => node.id === 'visual').properties.scale, [0.32, 0.32]);
  assert.equal(
    subresource(elder, 'character.npc.village-elder-plop.animations').animations.idle.loopMode,
    'ping-pong',
  );
  assert.equal(subresource(elder, 'character.npc.village-elder-plop.sprite').kind, 'sprite-sheet');
  assert.deepEqual(applied.outputs.filter((output) => output.path.startsWith('resources/')).map((output) => output.path), [],
    'character shapes, sprite sheets, and animation libraries are not written as standalone resources');
  const archerOutput = applied.outputs.find((output) => output.path === 'characters/worm-archer.scene.json');
  assert.deepEqual(archerOutput.contributions.map((entry) => entry.unitKey), ['character:worm-archer', 'visual:enemy.worm.archer'],
    'units whose resources were embedded are attributed to the owning scene');
});
