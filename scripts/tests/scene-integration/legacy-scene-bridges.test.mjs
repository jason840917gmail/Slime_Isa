import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

test('legacy chest and boss UI bridges expose only typed view actions and clean their leases', () => {
  const panelEvents = [];
  const chestUi = new t.LegacyChestUiBridge({
    open: (id) => panelEvents.push(['open', id]),
    close: () => panelEvents.push(['close']),
    destroy: () => panelEvents.push(['destroy']),
  });
  let transfers = 0;
  chestUi.open({
    mapId: 'level-1', instanceId: 'chest', contents: { key: 1 },
    transferStack: () => { transfers += 1; return 1; }, close: () => {},
  });
  assert.deepEqual(chestUi.getContents('chest'), { key: 1 });
  assert.equal(chestUi.transferStack('chest', 'key'), 1);
  assert.equal(transfers, 1);
  chestUi.close('other');
  chestUi.close('chest');
  chestUi.dispose();
  assert.deepEqual(panelEvents, [['open', 'chest'], ['close'], ['destroy']]);

  const bossEvents = [];
  const bossUi = new t.LegacyBossUiBridge((campId, bossId) => ({
    defeat: () => bossEvents.push(['defeat', campId, bossId]),
    destroy: () => bossEvents.push(['destroy', campId, bossId]),
  }));
  bossUi.showBoss('camp', 'fatty');
  bossUi.hideBoss('camp', true);
  bossUi.showBoss('camp', 'fatty');
  bossUi.dispose();
  assert.deepEqual(bossEvents, [['defeat', 'camp', 'fatty'], ['destroy', 'camp', 'fatty']]);
});

test('map placement bridge assigns the Level 1 camp, nested chest, and NPCs to one scene owner', async () => {
  const map = JSON.parse(await readFile(`${REPOSITORY_ROOT}/src/game/content/maps/level-1.map.json`, 'utf8'));
  const bridge = new t.LegacyMapPlacementBridge('level-1', map.objects, map.bossCamps);
  const placements = bridge.scenePlacements();
  assert.deepEqual(placements[0], {
    placementId: 'level-1-fatty-one-eye-camp',
    sceneId: 'encounter.level-1-fatty-camp',
    x: 2528,
    y: 1472,
    persistenceKey: 'level-1-fatty-one-eye-camp',
  });
  const npcPlacements = placements.filter((placement) => placement.npcDefinitionId);
  assert.equal(npcPlacements.length, 5);
  assert.deepEqual(
    npcPlacements.map((placement) => [placement.placementId, placement.sceneId, placement.npcDefinitionId]),
    [
      ['level-1-npc-village-elder-plop', 'character.village-elder-plop', 'village-elder-plop'],
      ['level-1-npc-lili', 'character.lili', 'lili'],
      ['level-1-npc-red-slime-boy', 'character.red-slime-boy', 'red-slime-boy'],
      ['level-1-npc-yellow-blond-slime-girl', 'character.yellow-blond-slime-girl', 'yellow-blond-slime-girl'],
      ['level-1-npc-mossy-scout', 'character.mossy-scout', 'level-1-spider-giver'],
    ],
  );
  const resourcePlacements = placements.filter((placement) => placement.sceneId.startsWith('object.resource-stone-node'));
  assert.equal(resourcePlacements.length, 6);
  assert.ok(resourcePlacements.some((placement) => placement.sceneId === 'object.resource-stone-node.big-stone-mine'));
  assert.deepEqual(resourcePlacements[0].propertyOverrides, [
    { nodeId: 'script', property: 'mapId', value: 'level-1' },
    { nodeId: 'script', property: 'instanceId', value: resourcePlacements[0].placementId },
  ]);
  const treePlacements = placements.filter((placement) => placement.sceneId.startsWith('object.tree-world-solid'));
  assert.equal(treePlacements.length, 4);
  assert.ok(treePlacements.every((placement) => placement.sceneId === 'object.tree-world-solid.tree-autumn-01'));
  const collectiblePlacements = placements.filter((placement) => placement.sceneId.startsWith('object.collectible-'));
  assert.equal(collectiblePlacements.length, 9);
  assert.deepEqual(
    [...new Set(collectiblePlacements.map((placement) => placement.sceneId))].sort(),
    ['object.collectible-purple-berry', 'object.collectible-stone-pile', 'object.collectible-wood-pile'],
  );
  assert.deepEqual(collectiblePlacements[0].propertyOverrides, [
    { nodeId: 'script', property: 'mapId', value: 'level-1' },
    { nodeId: 'script', property: 'instanceId', value: collectiblePlacements[0].placementId },
  ]);
  const chest = map.objects.find((entry) => entry.instanceId === 'level-1-fatty-guarded-chest');
  assert.equal(bridge.shouldSuppressLegacyObject(chest), true);
  for (const placement of npcPlacements) {
    const npc = map.objects.find((entry) => entry.instanceId === placement.placementId);
    assert.equal(bridge.shouldSuppressLegacyObject(npc), true);
  }
  for (const placement of collectiblePlacements) {
    const collectible = map.objects.find((entry) => entry.instanceId === placement.placementId);
    assert.equal(bridge.shouldSuppressLegacyObject(collectible), true);
  }
  assert.equal(bridge.shouldSuppressLegacyBossCamp(map.bossCamps[0]), true);
});

test('map placement bridge assigns passive object families to their authored scene variants', () => {
  const objects = [
    { instanceId: 'floor', objectId: 'decoration.world.floor', visualId: 'sewer-grate', x: 1, y: 2 },
    { instanceId: 'decoration', objectId: 'decoration.world.solid', visualId: 'stone-column', x: 3, y: 4 },
    { instanceId: 'house', objectId: 'house.world.solid', visualId: 'forge-red', x: 5, y: 6 },
    { instanceId: 'decorative-rock', objectId: 'rock.world-wall.decorative', visualId: 'field-01', x: 7, y: 8 },
    { instanceId: 'solid-rock', objectId: 'rock.world-wall.solid', visualId: 'large-01', x: 9, y: 10 },
    { instanceId: 'wall', objectId: 'wall.stone.solid', visualId: 'corner-01', x: 11, y: 12 },
  ];
  const bridge = new t.LegacyMapPlacementBridge('passive-test', objects, []);
  const placements = bridge.scenePlacements();
  assert.deepEqual(
    placements.map((placement) => [placement.placementId, placement.sceneId]),
    [
      ['floor', 'object.decoration-world-floor'],
      ['decoration', 'object.decoration-world-solid.stone-column'],
      ['house', 'object.house-world-solid.forge-red'],
      ['decorative-rock', 'object.rock-world-wall-decorative.field-01'],
      ['solid-rock', 'object.rock-world-wall-solid'],
      ['wall', 'object.wall-stone-solid.corner-01'],
    ],
  );
  assert.ok(objects.every((object) => bridge.shouldSuppressLegacyObject(object)));
});

test('map placement bridge suppresses every passive object it assigns on an authored map', async () => {
  const map = JSON.parse(await readFile(`${REPOSITORY_ROOT}/src/game/content/maps/174.map.json`, 'utf8'));
  const bridge = new t.LegacyMapPlacementBridge('174', map.objects, map.bossCamps ?? []);
  const placements = bridge.scenePlacements();
  const passivePlacements = placements.filter((placement) => (
    placement.sceneId.startsWith('object.house-world-solid')
    || placement.sceneId.startsWith('object.decoration-world-solid')
  ));
  assert.equal(passivePlacements.length, 29);
  assert.equal(passivePlacements.filter((placement) => placement.sceneId.startsWith('object.house-world-solid')).length, 15);
  assert.equal(passivePlacements.filter((placement) => placement.sceneId.startsWith('object.decoration-world-solid')).length, 14);
  assert.ok(passivePlacements.every((placement) => {
    const object = map.objects.find((candidate) => candidate.instanceId === placement.placementId);
    return object && bridge.shouldSuppressLegacyObject(object);
  }));
});
