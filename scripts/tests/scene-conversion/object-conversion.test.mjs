import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { objectSceneAdapter } from '../../lib/scene-conversion/objects.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const unitKeys = ['object:resource.stone-node'];

async function createRunner() {
  const productionLedger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const selected = new Set(unitKeys);
  const ledger = { ...productionLedger, rows: productionLedger.rows.map((row) => selected.has(row.key) ? { ...row, writerState: 'legacy' } : row) };
  const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
  return new ConversionRunner({
    repositoryRoot,
    ledger,
    adapters: { object: objectSceneAdapter },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'object-scene-conversion-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
  });
}

test('resource object conversion is deterministic and emits every visual variant', async () => {
  const runner = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const replay = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(replay.outputs, first.outputs);
  assert.deepEqual(first.outputs.map((output) => output.path), [
    'objects/resource-stone-node--big-stone-mine.scene.json',
    'objects/resource-stone-node.scene.json',
  ]);
});

test('stone resource scenes preserve visual, collision, harvest, drop, and script data', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const base = await load('objects/resource-stone-node.scene.json');
  const alternate = await load('objects/resource-stone-node--big-stone-mine.scene.json');

  assert.equal(base.sceneId, 'object.resource-stone-node');
  assert.equal(alternate.sceneId, 'object.resource-stone-node.big-stone-mine');
  assert.equal(base.nodes.find((node) => node.id === 'visual').properties.frame, 1);
  assert.equal(base.nodes.find((node) => node.id === 'damage-area').properties.collisionLayer, 8);
  assert.equal(base.nodes.find((node) => node.id === 'damage-shape').properties.shape.resourceId, 'resource-stone-node.stone-node.shape');
  const script = base.nodes.find((node) => node.scriptId === 'game.resource-node');
  assert.equal(script.properties.maxHealth, 80);
  assert.deepEqual(script.properties.drop, { objectId: 'collectible.stone-pile', visualId: 'stone-pile', pieces: 3 });
  assert.deepEqual(script.properties.harvestRequirement, { targetTag: 'stone', minimumTier: 1, failureMessage: 'Requires a Pickaxe' });
  assert.equal(script.properties.persistHealth, false);

  for (const relativePath of ['resource-stone-node.scene.json', 'resource-stone-node--big-stone-mine.scene.json']) {
    assert.deepEqual(
      JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/scenes/authored/objects', relativePath), 'utf8')),
      await load(`objects/${relativePath}`),
    );
  }
});
