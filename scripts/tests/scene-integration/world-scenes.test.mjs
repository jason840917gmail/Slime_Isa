import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';
import { collisionBits } from '../../lib/scene-conversion/collision-layers.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const mapRoot = path.join(REPOSITORY_ROOT, 'src/game/content/maps');
const reportRoot = path.join(REPOSITORY_ROOT, 'src/game/content/scenes/authored/reports/worlds');

async function json(file) {
  return JSON.parse(await readFile(file, 'utf8'));
}

test('every authored map placement has exactly one reported scene owner', async () => {
  const mapFiles = (await readdir(mapRoot)).filter((name) => name.endsWith('.map.json')).sort();
  assert.equal(mapFiles.length, 19);
  for (const name of mapFiles) {
    const map = await json(path.join(mapRoot, name));
    const report = await json(path.join(reportRoot, `${map.mapId}.mapping.json`));
    const world = content.scenes.find((scene) => scene.sceneId === `world.${map.mapId}`);
    assert.ok(world, `missing world.${map.mapId}`);
    assert.deepEqual(report.sourceCounts, {
      objects: map.objects.length,
      bossCamps: map.bossCamps?.length ?? 0,
      playerMarkers: 1 + Object.keys(map.player.entries).length,
      exits: map.exits?.length ?? 0,
      enemySafeZones: map.enemySafeZones?.length ?? 0,
      enemySpawnAreas: map.enemySpawnAreas?.length ?? 0,
      npcWanderAreas: map.npcWanderAreas?.length ?? 0,
    });
    assert.equal(report.placements.length, map.objects.length + (map.bossCamps?.length ?? 0));
    const reportedInstances = report.placements.filter((placement) => placement.ownership === 'world-instance');
    assert.equal(reportedInstances.length, report.worldInstanceCount);
    for (const placement of reportedInstances) {
      assert.equal(world.instances.filter((instance) => instance.instanceId === placement.instanceId).length, 1, `${map.mapId} lost ${placement.instanceId}`);
    }
    assert.equal(new Set(world.instances.map((instance) => instance.instanceId)).size, world.instances.length);
    assert.equal(new Set(world.instances.map((instance) => instance.persistenceKey)).size, world.instances.length);

    const sourceKeys = report.placements.map((placement) => `${placement.sourceKind}:${placement.sourceId}`);
    assert.equal(new Set(sourceKeys).size, sourceKeys.length, `${map.mapId} has duplicate mapping rows`);
    for (const object of map.objects) assert.ok(sourceKeys.includes(`object:${object.instanceId}`), `${map.mapId} lost ${object.instanceId}`);
    for (const camp of map.bossCamps ?? []) assert.ok(sourceKeys.includes(`boss-camp:${camp.id}`), `${map.mapId} lost ${camp.id}`);

    const expectedNavigationPaths = [
      '$.player.spawn',
      ...['north', 'east', 'south', 'west']
        .filter((direction) => map.player.entries[direction])
        .map((direction) => `$.player.entries.${direction}`),
      ...(map.exits ?? []).map((_, index) => `$.exits[${index}]`),
    ];
    assert.deepEqual(report.navigation.map((mapping) => mapping.sourcePath), expectedNavigationPaths);
    assert.equal(new Set(report.navigation.map((mapping) => mapping.sourcePath)).size, report.navigation.length);
    assert.equal(report.navigation.length, report.sourceCounts.playerMarkers + report.sourceCounts.exits);
    for (const mapping of report.navigation) {
      const nodeId = mapping.nodeId ?? mapping.areaNodeId;
      assert.equal(world.nodes.filter((node) => node.id === nodeId).length, 1, `${map.mapId} lost ${mapping.sourcePath}`);
    }
    const expectedAreaPaths = [
      ...(map.enemySafeZones ?? []).map((_, index) => `$.enemySafeZones[${index}]`),
      ...(map.enemySpawnAreas ?? []).map((_, index) => `$.enemySpawnAreas[${index}]`),
      ...(map.npcWanderAreas ?? []).map((_, index) => `$.npcWanderAreas[${index}]`),
    ];
    assert.deepEqual(report.areas.map((mapping) => mapping.sourcePath), expectedAreaPaths);
    for (const mapping of report.areas) {
      assert.equal(world.nodes.find((node) => node.id === mapping.areaNodeId)?.type, 'Area2D');
      assert.equal(world.nodes.find((node) => node.id === mapping.scriptNodeId)?.scriptId, 'game.world-area');
    }
    const worldDefinition = world.nodes.find((node) => node.scriptId === 'game.world-definition');
    assert.equal(worldDefinition.properties.mapId, map.mapId);
    assert.deepEqual(
      [worldDefinition.properties.tileSize, worldDefinition.properties.columns, worldDefinition.properties.rows],
      [map.tileSize, map.size.columns, map.size.rows],
    );
  }
});

test('authored navigation nodes preserve marker order, exit geometry, targets, gates, and signal wiring', () => {
  const icege = content.scenes.find((scene) => scene.sceneId === 'world.icege');
  assert.deepEqual(
    icege.nodes.filter((node) => node.parentId === 'world' && node.id.startsWith('player-')).map((node) => node.id),
    ['player-spawn', 'player-entry-north', 'player-entry-east', 'player-entry-south', 'player-entry-west'],
  );

  const levelOne = content.scenes.find((scene) => scene.sceneId === 'world.level-1');
  const area = levelOne.nodes.find((node) => node.id === 'exit-1');
  const shape = levelOne.nodes.find((node) => node.id === 'exit-1-shape');
  const script = levelOne.nodes.find((node) => node.id === 'exit-1-script');
  assert.deepEqual(area.properties.position, [3552, 576]);
  assert.equal(area.properties.collisionLayer, collisionBits('trigger'));
  assert.equal(area.properties.collisionMask, collisionBits('player', 'npc'), 'exits detect the character bodies they detected before the named-layer table');
  assert.deepEqual(shape.properties.shape, { resourceId: 'level-1.exit-1.shape' });
  assert.deepEqual(script.properties, {
    mapId: 'level-1', exitId: 'exit-1', targetAreaId: 'gloop-forest', entry: 'west', area: { nodeId: 'exit-1' },
    gate: {
      id: 'level-1-east-verdant-gate', requiredItemId: 'green-key', consumeOnUnlock: true,
      lockedMessage: 'The eastern gate needs a green key.',
    },
  });
  assert.deepEqual(levelOne.subresources.find((resource) => resource.resourceId === 'level-1.exit-1.shape').value, {
    shape: 'rectangle', width: 64, height: 128,
  });
  assert.deepEqual(levelOne.connections, [{
    source: { nodeId: 'exit-1' }, signal: 'body_entered', target: { nodeId: 'exit-1-script' }, handler: 'on_body_entered',
  }]);
});

test('world preparation preserves placement transforms, identities, persistence, and nested encounter ownership', async () => {
  const descriptors = t.createGameDescriptorRegistry();
  const documents = new t.SceneDocumentLoader(async (id) => content.scenes.find((scene) => scene.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const resolver = new t.SceneResolver({ documents, resources, registry: descriptors });

  const rectangle = await resolver.prepare_scene('world.test-rectangle');
  const amberRoot = rectangle.definition.nodes.find((node) => node.key === 'amber-rock-001/body');
  const amberScript = rectangle.definition.nodes.find((node) => node.key === 'amber-rock-001/script');
  assert.equal(amberRoot.persistenceKey, 'test-rectangle.amber-rock-001');
  assert.deepEqual(amberRoot.properties.position, [288, 192]);
  assert.deepEqual(
    { mapId: amberScript.properties.mapId, instanceId: amberScript.properties.instanceId, initialHealth: amberScript.properties.initialHealth },
    { mapId: 'test-rectangle', instanceId: 'amber-rock-001', initialHealth: 30 },
  );
  rectangle.dispose();

  const levelOne = await resolver.prepare_scene('world.level-1');
  const campRoot = levelOne.definition.nodes.find((node) => node.key === 'level-1-fatty-one-eye-camp/root');
  const guardedChest = levelOne.definition.nodes.find((node) => node.key === 'level-1-fatty-one-eye-camp/guarded-chest/body');
  assert.equal(campRoot.persistenceKey, 'level-1-fatty-one-eye-camp');
  assert.deepEqual(campRoot.properties.position, [2528, 1472]);
  assert.equal(guardedChest.provenance.authoredInstanceId, 'guarded-chest');
  assert.equal(levelOne.definition.nodes.some((node) => node.key.startsWith('level-1-fatty-guarded-chest/')), false);
  levelOne.dispose();

  assert.equal(documents.activeLeaseCount(), 0);
  assert.equal(resources.activeLeaseCount(), 0);
});

test('every door links to an existing door in its target world and has an arrival point', () => {
  const doorsOf = (scene) => scene.nodes
    .filter((node) => node.scriptId === 'game.door')
    .map((script) => ({ script, door: scene.nodes.find((node) => node.id === script.parentId) }));
  const worlds = content.scenes.filter((scene) => scene.sceneId.startsWith('world.'));
  let linked = 0;
  for (const world of worlds) {
    for (const { script, door } of doorsOf(world)) {
      const where = `${world.sceneId} door '${script.properties.doorId}'`;
      assert.ok(door, `${where} has no parent node`);
      assert.equal(script.properties.entry, undefined, `${where} still uses a compass entry`);
      assert.equal(world.nodes.filter((node) => node.parentId === door.id && node.name === 'arrival').length, 1, `${where} needs one arrival child`);
      const target = worlds.find((scene) => scene.sceneId === `world.${script.properties.targetAreaId}`);
      assert.ok(target, `${where} targets missing world '${script.properties.targetAreaId}'`);
      const targetDoors = doorsOf(target).filter(({ script: other }) => other.properties.doorId === script.properties.targetDoorId);
      assert.equal(targetDoors.length, 1, `${where} targets door '${script.properties.targetDoorId}' that ${target.sceneId} does not define exactly once`);
      linked += 1;
    }
  }
  assert.ok(linked >= 4);
});
