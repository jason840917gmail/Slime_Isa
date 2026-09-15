import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

test('legacy weapon contacts reach managed receivers once, while cancellation and disposal clear pending work', () => {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  let hp = 20;
  let commits = 0;
  const receiver = {
    runtimeNodeId: 'managed.enemy',
    getDamageState: () => ({ hp, maxHp: 20, dead: hp <= 0 }),
    commitDamage: ({ result }) => { commits += 1; hp -= result.actualDamage; },
  };
  router.registerArea(receiver, { areaNodeId: 'managed.enemy.body', priority: 0, damageMultiplier: 1 });
  const bridge = new t.LegacyCombatBridge(activations, router);
  bridge.beginAttack('legacy.weapon', ['legacy.swing']);
  const contact = {
    sourceNodeId: 'legacy.weapon', attackAreaNodeId: 'legacy.swing', targetAreaNodeId: 'managed.enemy.body',
    weaponId: 'wooden-spear', weaponTags: ['spear'], damageTypes: ['physical'], damage: 7,
    impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
  };
  bridge.collectContact(contact);
  bridge.collectContact(contact);
  assert.equal(bridge.resolveStep(1)[0].result.status, 'accepted');
  assert.equal(hp, 13);
  assert.equal(commits, 1);
  bridge.collectContact(contact);
  assert.equal(bridge.resolveStep(2)[0].result.reason, 'duplicate');
  bridge.beginAttack('legacy.weapon', ['legacy.swing']);
  bridge.collectContact(contact);
  bridge.cancelAttack('legacy.weapon');
  assert.deepEqual(bridge.resolveStep(3), []);
  bridge.dispose();
  assert.throws(() => bridge.collectContact(contact), /disposed/);
});

test('legacy authored hitboxes spatially collect managed damage areas during fixed attack resolution', () => {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  let hp = 30;
  let commits = 0;
  const receiver = {
    runtimeNodeId: 'managed.worm',
    getDamageState: () => ({ hp, maxHp: 30, dead: hp <= 0 }),
    commitDamage: ({ result }) => { commits += 1; hp -= result.actualDamage; },
  };
  router.registerArea(receiver, { areaNodeId: 'managed.worm.body', priority: 0, damageMultiplier: 1 });

  let resolution;
  let unregisters = 0;
  const participant = {
    runtimeId: 'managed.worm.body', node: {}, kind: 'area', collisionLayer: 1, collisionMask: 1,
    monitoring: false, monitorable: true, contactActive: true,
    contactShapes: () => [{ shapeId: 'managed.worm.shape', shape: 'circle', centerX: 12, centerY: 10, radius: 5 }],
    contactBounds: () => ({ x: 7, y: 5, width: 10, height: 10 }),
    contactEntered() {}, contactExited() {},
  };
  const context = {
    registerCallback: (phase, callback) => {
      assert.equal(phase, 'attack-resolution');
      resolution = callback;
      return () => { unregisters += 1; };
    },
    queryContactParticipants: () => [participant],
  };
  const combat = new t.LegacyCombatBridge(activations, router);
  const outcomes = [];
  let transforms = 0;
  const bridge = new t.LegacyWeaponTargetBridge({
    context,
    combat,
    router,
    weaponTags: () => ['spear'],
    transformDamage: (damage, target) => {
      transforms += 1;
      assert.equal(target.receiverNodeId, 'managed.worm');
      return damage + 2;
    },
    onOutcome: (outcome, target) => outcomes.push([outcome.result.status, target?.areaNodeId]),
  });
  bridge.beginAttack({ weaponId: 'wooden-spear', hitboxIds: ['point'], playbackId: 4 });
  const handle = bridge.activateHitbox({
    weaponId: 'wooden-spear', hitboxId: 'point', attackDirection: 'right', attackVector: [1, 0], playbackId: 4,
    damage: 6, knockX: 1, knockY: 0, knockStrength: 20,
    hitbox: { x: 10, y: 10, width: 12, height: 8, damage: 6, durationMs: 100, shape: 'rect' },
  });
  assert.equal(handle.isActive, true);
  resolution(1 / 60);
  resolution(1 / 60);
  assert.equal(hp, 22);
  assert.equal(commits, 1);
  assert.equal(transforms, 1);
  assert.deepEqual(outcomes, [['accepted', 'managed.worm.body']]);

  handle.deactivate();
  assert.equal(handle.isActive, false);
  bridge.endAttack();
  bridge.dispose();
  assert.equal(unregisters, 1);
  assert.throws(() => bridge.beginAttack({ weaponId: 'wooden-spear', hitboxIds: ['point'], playbackId: 5 }), /disposed/);
});

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
  const chest = map.objects.find((entry) => entry.instanceId === 'level-1-fatty-guarded-chest');
  assert.equal(bridge.shouldSuppressLegacyObject(chest), true);
  for (const placement of npcPlacements) {
    const npc = map.objects.find((entry) => entry.instanceId === placement.placementId);
    assert.equal(bridge.shouldSuppressLegacyObject(npc), true);
  }
  assert.equal(bridge.shouldSuppressLegacyBossCamp(map.bossCamps[0]), true);
});
