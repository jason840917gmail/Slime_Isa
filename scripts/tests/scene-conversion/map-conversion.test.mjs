import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { mapSceneAdapter } from '../../lib/scene-conversion/maps.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const unitKeys = ['map:level-1', 'map:test-rectangle'];

async function discoverDocuments(directory, suffix) {
  const discoverFiles = async (current) => {
    const entries = await readdir(current, { withFileTypes: true });
    return (await Promise.all(entries.map(async (entry) => {
      const candidate = path.join(current, entry.name);
      return entry.isDirectory() ? discoverFiles(candidate) : entry.isFile() && entry.name.endsWith(suffix) ? [candidate] : [];
    }))).flat();
  };
  const files = (await discoverFiles(directory)).sort();
  return Promise.all(files.map(async (file) => JSON.parse(await readFile(file, 'utf8'))));
}

async function createRunner() {
  const productionLedger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const selected = new Set(unitKeys);
  const ledger = { ...productionLedger, rows: productionLedger.rows.map((row) => selected.has(row.key) ? { ...row, writerState: 'legacy' } : row) };
  const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
  const authoredRoot = path.join(repositoryRoot, 'src/game/content/scenes/authored');
  const [existingScenes, existingResources] = await Promise.all([
    discoverDocuments(authoredRoot, '.scene.json'),
    discoverDocuments(authoredRoot, '.resource.json'),
  ]);
  return new ConversionRunner({
    repositoryRoot,
    ledger,
    adapters: { map: mapSceneAdapter },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'map-scene-conversion-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, {
      hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId), existingScenes, existingResources,
    }),
  });
}

test('map terrain conversion is deterministic and externalizes stable tile cells', async () => {
  const runner = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const replay = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(replay.outputs, first.outputs);
  assert.equal(first.outputs.length, 8);

  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const world = await load('worlds/test-rectangle.scene.json');
  const data = await load('resources/tiles/test-rectangle.ground.tile-data.resource.json');
  const set = await load('resources/tiles/test-rectangle.ground.tile-set.resource.json');
  const report = await load('reports/worlds/test-rectangle.mapping.json');

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
  assert.deepEqual(world.instances, [{
    instanceId: 'amber-rock-001', name: 'amber-rock-001', sceneId: 'object.rock-amber-ore-mineable',
    parentNodeId: 'world', order: 1, persistenceKey: 'test-rectangle.amber-rock-001',
    overrides: [
      { sourceInstancePath: [], sourceNodeId: 'body', property: 'position', value: [288, 192] },
      { sourceInstancePath: [], sourceNodeId: 'script', property: 'mapId', value: 'test-rectangle' },
      { sourceInstancePath: [], sourceNodeId: 'script', property: 'instanceId', value: 'amber-rock-001' },
      { sourceInstancePath: [], sourceNodeId: 'script', property: 'initialHealth', value: 30 },
    ],
  }]);
  assert.deepEqual(report.sourceCounts, { objects: 1, bossCamps: 0 });
  assert.equal(report.placements[0].sourceId, 'amber-rock-001');
  assert.equal(report.placements[0].ownership, 'world-instance');

  const levelOne = await load('worlds/level-1.scene.json');
  const levelOneReport = await load('reports/worlds/level-1.mapping.json');
  assert.equal(levelOneReport.placements.length, levelOneReport.sourceCounts.objects + levelOneReport.sourceCounts.bossCamps);
  assert.equal(levelOne.instances.some((instance) => instance.instanceId === 'level-1-fatty-guarded-chest'), false);
  assert.equal(levelOne.instances.find((instance) => instance.instanceId === 'level-1-fatty-one-eye-camp').sceneId, 'encounter.level-1-fatty-camp');
  assert.equal(levelOneReport.placements.find((placement) => placement.sourceId === 'level-1-fatty-guarded-chest').ownership, 'encounter-instance');
});

test('converted world terrain matches checked-in authored resources', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  for (const relativePath of [
    'worlds/test-rectangle.scene.json',
    'resources/tiles/test-rectangle.ground.tile-data.resource.json',
    'resources/tiles/test-rectangle.ground.tile-set.resource.json',
    'reports/worlds/test-rectangle.mapping.json',
  ]) {
    assert.deepEqual(
      JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/scenes/authored', relativePath), 'utf8')),
      JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8')),
    );
  }
});
