import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { mapSceneAdapter } from '../../lib/scene-conversion/maps.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const unitKeys = ['map:level-1', 'map:test-rectangle'];

async function createRunner() {
  const productionLedger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const selected = new Set(unitKeys);
  const ledger = { ...productionLedger, rows: productionLedger.rows.map((row) => selected.has(row.key) ? { ...row, writerState: 'legacy' } : row) };
  const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
  return new ConversionRunner({
    repositoryRoot,
    ledger,
    adapters: { map: mapSceneAdapter },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'map-scene-conversion-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
  });
}

test('map terrain conversion is deterministic and externalizes stable tile cells', async () => {
  const runner = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const replay = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(replay.outputs, first.outputs);
  assert.equal(first.outputs.length, 6);

  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const world = await load('worlds/test-rectangle.scene.json');
  const data = await load('resources/tiles/test-rectangle.ground.tile-data.resource.json');
  const set = await load('resources/tiles/test-rectangle.ground.tile-set.resource.json');

  assert.equal(world.sceneId, 'world.test-rectangle');
  assert.deepEqual(world.nodes.find((node) => node.type === 'TileMapLayer2D').properties, {
    position: [0, 0], tileData: { resourceId: 'tiles.test-rectangle.ground.data' }, tileSize: 64,
    seed: 2455619060, depth: 0, collisionLayer: 1, collisionMask: 2, collisionEnabled: true, editorLocked: false,
  });
  assert.deepEqual({ columns: data.columns, rows: data.rows }, { columns: 8, rows: 5 });
  assert.equal(data.cells.length, 40);
  assert.deepEqual(data.cells[19], { x: 3, y: 2, tileId: 'water' });
  assert.deepEqual(Object.keys(set.tiles), ['grass-a', 'water']);
  assert.deepEqual(set.tiles['grass-a'].assetIds, ['sheet.grounds.19x19.highland-green']);
  assert.deepEqual(set.tiles['grass-a'].transition, {
    group: 'natural-ground', material: 'highland', priority: 10, edgeWidth: 12, style: 'noisy-feather',
  });
});

test('converted world terrain matches checked-in authored resources', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  for (const relativePath of [
    'worlds/test-rectangle.scene.json',
    'resources/tiles/test-rectangle.ground.tile-data.resource.json',
    'resources/tiles/test-rectangle.ground.tile-set.resource.json',
  ]) {
    assert.deepEqual(
      JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/scenes/authored', relativePath), 'utf8')),
      JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8')),
    );
  }
});
