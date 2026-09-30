import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { placedBedId, planRespawn, worldHasBed } = await loadTypescriptModule(
  'src/game/features/rest/RespawnDestination.ts',
);

const readScene = async (path) => JSON.parse(await readFile(new URL(`../../../src/game/content/scenes/authored/${path}`, import.meta.url), 'utf8'));

const bedScene = { sceneId: 'object.bed', nodes: [{ id: 'script', scriptId: 'game.bed' }], instances: [] };
const rugScene = { sceneId: 'object.rug', nodes: [{ id: 'visual' }], instances: [] };
const worldScene = {
  sceneId: 'world.home',
  nodes: [],
  instances: [
    { instanceId: 'home-bed', sceneId: 'object.bed', persistenceKey: 'world.home.bed' },
    { instanceId: 'home-rug', sceneId: 'object.rug', persistenceKey: 'world.home.rug' },
  ],
};

function lookup({ scenes = [bedScene, rugScene, worldScene], placed = {} } = {}) {
  const byId = new Map(scenes.map((scene) => [scene.sceneId, scene]));
  return { scene: (id) => byId.get(id), placedFurniture: (mapId) => placed[mapId] ?? [] };
}

test('an authored bed is found by persistence key or instance ID, but not a non-bed instance', () => {
  assert.equal(worldHasBed(lookup(), 'home', 'world.home.bed'), true);
  assert.equal(worldHasBed(lookup(), 'home', 'home-bed'), true);
  assert.equal(worldHasBed(lookup(), 'home', 'world.home.rug'), false);
  assert.equal(worldHasBed(lookup(), 'home', 'world.home.missing'), false);
});

test('a missing world never has a bed; a legacy point without a bed ID only needs its world', () => {
  assert.equal(worldHasBed(lookup(), 'gone', 'world.home.bed'), false);
  assert.equal(worldHasBed(lookup(), 'gone', undefined), false);
  assert.equal(worldHasBed(lookup(), 'home', undefined), true);
});

test('a placed bed exists only while its placement record does', () => {
  const placed = { home: [{ id: 'placed-furniture-3', itemId: 'bed', sceneId: 'object.bed', x: 0, y: 0 }] };
  assert.equal(worldHasBed(lookup({ placed }), 'home', placedBedId('placed-furniture-3')), true);
  assert.equal(worldHasBed(lookup({ placed }), 'home', placedBedId('placed-furniture-4')), false);
  assert.equal(worldHasBed(lookup(), 'home', placedBedId('placed-furniture-3')), false);
});

test('respawn plans wake at an existing bed and fall back to the start when it is gone', () => {
  const point = { areaId: 'home', mapId: 'home', x: 10, y: 20, bedId: 'world.home.bed' };
  assert.deepEqual(planRespawn(point, () => true), { kind: 'bed', point });
  assert.deepEqual(planRespawn(point, () => false), { kind: 'start', staleBed: true });
  assert.deepEqual(planRespawn(undefined, () => true), { kind: 'start', staleBed: false });
});

test('every authored home bed resolves against the real world scenes', async () => {
  const scenes = [
    await readScene('worlds/slime-home.scene.json'),
    await readScene('worlds/mushroom-home.scene.json'),
    await readScene('objects/interiors/beds/interior-beds-straw-nest-s.scene.json'),
    await readScene('objects/interiors/mushroom-large/interior-mushroom-large-bed-mushroom-cap-s.scene.json'),
  ];
  const real = lookup({ scenes });
  assert.equal(worldHasBed(real, 'slime-home', 'world.slime-home.west-bed'), true);
  assert.equal(worldHasBed(real, 'slime-home', 'world.slime-home.east-bed'), true);
  assert.equal(worldHasBed(real, 'mushroom-home', 'world.mushroom-home.bed'), true);
  assert.equal(worldHasBed(real, 'slime-home', 'world.slime-home.west-bed-rug'), false);
});
