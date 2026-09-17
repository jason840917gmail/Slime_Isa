import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');

function loadedMap(mapId) {
  return {
    map: { version: 1, mapId },
    dimensions: { columns: 1, rows: 1, tileSize: 64, width: 64, height: 64 },
  };
}

function packedScene(sceneId) {
  return { definition: { sourceSceneId: sceneId } };
}

test('world loading publishes one result only after map and packed scene resolve', async () => {
  const calls = [];
  let finishScene;
  const loader = new t.WorldSceneLoader(
    { load: async (mapId) => { calls.push(`map:${mapId}`); return loadedMap(mapId); } },
    { ensure: (sceneId) => new Promise((resolve) => { calls.push(`scene:${sceneId}`); finishScene = () => resolve(packedScene(sceneId)); }) },
  );
  let settled = false;
  const pending = loader.load('level-1').then((value) => { settled = true; return value; });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(settled, false);
  assert.deepEqual(calls, ['map:level-1', 'scene:world.level-1']);
  finishScene();
  const result = await pending;
  assert.equal(result.mapId, 'level-1');
  assert.equal(result.sceneId, 'world.level-1');
  assert.equal(result.loadedMap.map.mapId, 'level-1');
  assert.equal(result.packedScene.definition.sourceSceneId, 'world.level-1');
});

test('missing maps and mismatched packed scenes never produce a partial world result', async () => {
  let sceneLoads = 0;
  const missing = new t.WorldSceneLoader(
    { load: async () => null },
    { ensure: async (sceneId) => { sceneLoads += 1; return packedScene(sceneId); } },
  );
  await assert.rejects(missing.load('missing'), /Required authored map 'missing'/);
  assert.equal(sceneLoads, 0);

  const mismatched = new t.WorldSceneLoader(
    { load: async (mapId) => loadedMap(mapId) },
    { ensure: async () => packedScene('world.somewhere-else') },
  );
  await assert.rejects(mismatched.load('level-1'), /requested scene 'world.level-1' but resolved 'world.somewhere-else'/);
});

test('world loading forwards cancellation through both source boundaries', async () => {
  const controller = new AbortController();
  let observedSignal;
  let finishMap;
  const loader = new t.WorldSceneLoader(
    {
      load: (_mapId, signal) => new Promise((resolve) => {
        observedSignal = signal;
        finishMap = () => resolve(loadedMap('level-1'));
      }),
    },
    { ensure: async (sceneId) => packedScene(sceneId) },
  );
  const pending = loader.load('level-1', controller.signal);
  controller.abort();
  finishMap();
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(observedSignal, controller.signal);
});

test('prepared content can add a validated world scene lazily and releases it on dispose', async () => {
  const document = {
    version: 1,
    sceneId: 'world.lazy',
    rootNodeId: 'root',
    nodes: [{ id: 'root', name: 'LazyWorld', type: 'Node2D', parentId: null, order: 0, properties: {} }],
    instances: [],
  };
  const content = await t.PreparedSceneContent.prepare({
    scenes: [document],
    resources: [],
    registry: t.createCoreDescriptorRegistry(),
    sceneIds: [],
  });
  assert.throws(() => content.get('world.lazy'), /was not prepared/);
  const packed = await content.ensure('world.lazy');
  assert.equal(content.get('world.lazy'), packed);
  assert.equal(content.documents.activeLeaseCount(), 1);
  content.dispose();
  assert.equal(content.documents.activeLeaseCount(), 0);
});
