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
