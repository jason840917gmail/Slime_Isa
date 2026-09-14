import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { visualSceneAdapter } from '../../lib/scene-conversion/animations.mjs';
import { bossCampSceneAdapter } from '../../lib/scene-conversion/boss-camps.mjs';
import { characterSceneAdapter, enemySceneAdapter } from '../../lib/scene-conversion/characters.mjs';
import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { objectSceneAdapter } from '../../lib/scene-conversion/objects.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const unitKeys = [
  'visual:enemy.worm.brawler',
  'visual:boss.fatty-one-eye',
  'character:worm-brawler',
  'character:fatty-one-eye',
  'enemy:worm-brawler',
  'boss:fatty-one-eye',
  'object:chest.wooden',
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
      boss: bossCampSceneAdapter,
      object: objectSceneAdapter,
    },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'universal-scene-slice-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
  });
}

test('vertical-slice converters are byte-stable across two dry runs', async () => {
  const runner = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const second = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(second.outputs, first.outputs);
  assert.deepEqual(first.units, [...unitKeys].sort());
  assert.ok(first.outputs.some((output) => output.path === 'characters/worm-brawler.scene.json'));
  assert.ok(first.outputs.some((output) => output.path === 'characters/fatty-one-eye.scene.json'));
  assert.ok(first.outputs.some((output) => output.path === 'encounters/level-1-fatty-camp.scene.json'));
  assert.ok(first.outputs.some((output) => output.path === 'objects/chest-wooden.scene.json'));
});

test('isolated apply and replay preserve IDs, balance, camp placement, and chest save key', async () => {
  const runner = await createRunner();
  const applied = await runner.run({ unitKeys, mode: 'apply' });
  const replay = await runner.run({ unitKeys, mode: 'check' });
  assert.deepEqual(replay.outputs, applied.outputs);

  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const worm = await load('characters/worm-brawler.scene.json');
  const fatty = await load('characters/fatty-one-eye.scene.json');
  const camp = await load('encounters/level-1-fatty-camp.scene.json');
  const chest = await load('objects/chest-wooden.scene.json');
  assert.equal(worm.nodes.find((node) => node.scriptId === 'game.enemy').properties.maxHealth, 55);
  assert.equal(fatty.nodes.find((node) => node.scriptId === 'game.fatty').properties.maxHealth, 140);
  assert.equal(camp.nodes.find((node) => node.id === 'root').properties.position[0], 2528);
  assert.equal(camp.nodes.find((node) => node.scriptId === 'game.boss-camp').properties.guardedChestInstanceId, 'level-1-fatty-guarded-chest');
  assert.equal(chest.sceneId, 'object.chest-wooden');
});
