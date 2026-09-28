import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const infra = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');
const maps = await loadTypescriptModule('src/game/content/maps/mapFormat.ts');

function node(authoredNodeId, parentKey, type, properties, scriptId) {
  return { key: authoredNodeId, authoredNodeId, instancePath: [], name: authoredNodeId, type, parentKey, order: 0, properties, propertyScopes: {}, ...(scriptId ? { scriptId } : {}) };
}

/** A one-tile world with a single enemy spawn area whose shapes the caller controls. */
function spawnWorld({ pursue = { shape: 'rectangle', width: 200, height: 100 }, stay = { shape: 'rectangle', width: 50, height: 40 }, stayPosition = [10, 0], areaRotation, scriptProperties = {} } = {}) {
  return { definition: {
    sourceSceneId: 'world.test',
    nodes: [
      node('world-definition', null, 'ScriptNode', { mapId: 'test', tileSize: 64, columns: 20, rows: 20, metadata: { objects: [] } }, 'game.world-definition'),
      node('ground', null, 'TileMapLayer2D', { tileData: { resourceId: 'tiles.test.data' } }),
      node('player-spawn', null, 'Node2D', { position: [32, 32] }),
      node('world', null, 'Node2D', { position: [100, 50] }),
      node('world/area', 'world', 'Area2D', { position: [300, 200], ...(areaRotation === undefined ? {} : { rotation: areaRotation }) }),
      node('world/area/pursue', 'world/area', 'CollisionShape2D', { shape: { resourceId: 'pursue' } }),
      node('world/area/stay', 'world/area', 'CollisionShape2D', { position: stayPosition, shape: { resourceId: 'stay' } }),
      node('world/area/script', 'world/area', 'ScriptNode', {
        areaKind: 'enemy-spawn', areaId: 'camp', area: { nodeId: 'world/area' }, shape: { nodeId: 'world/area/pursue' }, stayShape: { nodeId: 'world/area/stay' },
        data: { enemies: [{ type: 'worm-brawler', weight: 1 }], intervalMs: 1000, maxPopulation: 2 },
        ...scriptProperties,
      }, 'game.world-area'),
    ],
    resources: [
      { version: 1, resourceId: 'tiles.test.data', kind: 'tile-data', tileSet: 'tiles.test.set', columns: 1, rows: 1, cells: [{ x: 0, y: 0, tileId: 'grass' }] },
      { version: 1, resourceId: 'pursue', kind: 'collision-shape', value: pursue },
      { version: 1, resourceId: 'stay', kind: 'collision-shape', value: stay },
    ],
  } };
}

const load = (packed, mapId = 'test') => new infra.WorldSceneLoader({ ensure: async () => packed }).load(mapId);

test('world area perimeters come from their collision shapes at global position', async () => {
  const world = await load(spawnWorld());
  const [area] = world.loadedMap.map.enemySpawnAreas;
  // Area global = world (100,50) + area (300,200) = (400,250); shapes are centred on their node.
  assert.deepEqual(area.pursuePerimeter, { shape: 'rectangle', x: 300, y: 200, w: 200, h: 100 });
  assert.deepEqual(area.stayPerimeter, { shape: 'rectangle', x: 385, y: 230, w: 50, h: 40 });
  assert.equal(area.id, 'camp');
  assert.equal(area.maxPopulation, 2);
});

test('circle spawn areas and resized shapes flow straight into gameplay data', async () => {
  const world = await load(spawnWorld({ pursue: { shape: 'circle', radius: 120 }, stay: { shape: 'circle', radius: 30 }, stayPosition: [40, 0] }));
  const [area] = world.loadedMap.map.enemySpawnAreas;
  assert.deepEqual(area.pursuePerimeter, { shape: 'circle', x: 400, y: 250, radius: 120 });
  assert.deepEqual(area.stayPerimeter, { shape: 'circle', x: 440, y: 250, radius: 30 });
});

test('invalid world area geometry is rejected with the area named', async () => {
  await assert.rejects(load(spawnWorld({ stayPosition: [150, 0] })), /'camp'.*stay rectangle must fit inside the pursue rectangle/);
  await assert.rejects(load(spawnWorld({ stay: { shape: 'circle', radius: 10 } })), /'camp'.*both be rectangles or both be circles/);
  await assert.rejects(load(spawnWorld({ areaRotation: 0.5 })), /'camp'.*cannot be rotated/);
  await assert.rejects(load(spawnWorld({ scriptProperties: { stayShape: undefined } })), /'camp'.*requires its stay shape reference/);
});

test('every authored world loads its areas from shapes and passes map validation', async () => {
  const content = await loadAuthoredSceneContent();
  const registry = t.createGameDescriptorRegistry();
  const documents = new t.SceneDocumentLoader(async (id) => content.scenes.find((scene) => scene.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const resolver = new t.SceneResolver({ documents, resources, registry });
  const worlds = content.scenes.filter((scene) => scene.sceneId.startsWith('world.'));
  assert.ok(worlds.length > 0);
  for (const scene of worlds) {
    for (const area of scene.nodes.filter((candidate) => candidate.scriptId === 'game.world-area')) {
      const data = area.properties.data ?? {};
      for (const legacy of ['x', 'y', 'w', 'h', 'perimeter', 'stayPerimeter', 'pursuePerimeter']) {
        assert.equal(data[legacy], undefined, `${scene.sceneId} ${area.properties.areaId} keeps geometry '${legacy}' in data; it belongs on its shapes`);
      }
    }
    const packed = await resolver.prepare_scene(scene.sceneId);
    const world = await load(packed, scene.sceneId.replace('world.', ''));
    assert.doesNotThrow(() => maps.parseMapFile(world.loadedMap.map, scene.sceneId), scene.sceneId);
  }
});
