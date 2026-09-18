import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');

function packedScene(sceneId) {
  const mapId = sceneId.replace('world.', '');
  return { definition: {
    sourceSceneId: sceneId,
    nodes: [
      { authoredNodeId: 'world-definition', scriptId: 'game.world-definition', properties: {
        mapId, tileSize: 64, columns: 1, rows: 1,
        metadata: { objects: [], player: { spawn: { x: 32, y: 32 }, entries: {} } },
      } },
      { authoredNodeId: 'ground', name: 'ground', type: 'TileMapLayer2D', order: 0, properties: { tileData: { resourceId: 'tiles.test.data' } } },
      { authoredNodeId: 'player-spawn', name: 'player-spawn', type: 'Node2D', order: 1, properties: { position: [32, 32] } },
    ],
    resources: [{ version: 1, resourceId: 'tiles.test.data', kind: 'tile-data', tileSet: 'tiles.test.set', columns: 1, rows: 1, cells: [{ x: 0, y: 0, tileId: 'grass' }] }],
  } };
}

test('world loading publishes one result only after the packed scene resolves', async () => {
  const calls = [];
  let finishScene;
  const loader = new t.WorldSceneLoader(
    { ensure: (sceneId) => new Promise((resolve) => { calls.push(`scene:${sceneId}`); finishScene = () => resolve(packedScene(sceneId)); }) },
  );
  let settled = false;
  const pending = loader.load('level-1').then((value) => { settled = true; return value; });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(settled, false);
  assert.deepEqual(calls, ['scene:world.level-1']);
  finishScene();
  const result = await pending;
  assert.equal(result.mapId, 'level-1');
  assert.equal(result.sceneId, 'world.level-1');
  assert.equal(result.loadedMap.map.mapId, 'level-1');
  assert.equal(result.packedScene.definition.sourceSceneId, 'world.level-1');
});

test('mismatched or incomplete packed scenes never produce a partial world result', async () => {
  const mismatched = new t.WorldSceneLoader(
    { ensure: async () => packedScene('world.somewhere-else') },
  );
  await assert.rejects(mismatched.load('level-1'), /requested scene 'world.level-1' but resolved 'world.somewhere-else'/);

  const incomplete = new t.WorldSceneLoader({ ensure: async (sceneId) => ({ definition: { sourceSceneId: sceneId, nodes: [], resources: [] } }) });
  await assert.rejects(incomplete.load('level-1'), /requires a game.world-definition/);
});

test('world loading forwards cancellation through the scene source boundary', async () => {
  const controller = new AbortController();
  let observedSignal;
  let finishScene;
  const loader = new t.WorldSceneLoader(
    { ensure: (_sceneId, signal) => new Promise((resolve) => {
        observedSignal = signal;
        finishScene = () => resolve(packedScene('world.level-1'));
      }) },
  );
  const pending = loader.load('level-1', controller.signal);
  controller.abort();
  finishScene();
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
