import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

function playerHealth() {
  let hp = 30;
  let commits = 0;
  const health = new t.PlayerHealthService('legacy.player', {
    state: {
      getHp: () => hp,
      getMaxHp: () => 30,
      commitResolvedDamage: (amount) => {
        commits += 1;
        const before = hp; hp = Math.max(0, hp - amount); return before - hp;
      },
      heal: () => 0,
      revive: () => { hp = 30; },
    },
    stats: { getHealthStats: () => ({ defense: 2, damageTakenMult: 1, iFrameMs: 100 }) },
  });
  return { health, get hp() { return hp; }, get commits() { return commits; } };
}

test('managed attacks reach one legacy player receiver and the sensor proxy follows post-step body geometry', () => {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const state = playerHealth();
  let bounds = { x: 10, y: 20, width: 16, height: 18 };
  const player = {
    getPosition: () => ({ x: bounds.x, y: bounds.y }),
    getBodyBounds: () => bounds,
    isDodging: () => false,
    applyKnockback: () => {},
  };
  const playerBridge = new t.LegacyPlayerBridge(router, state.health, player);
  playerBridge.enter();
  playerBridge.enter();
  assert.deepEqual(playerBridge.getPrimaryTarget('managed.worm'), {
    position: { x: 10, y: 20 }, damageAreaNodeId: playerBridge.damageAreaNodeId, active: true, hostile: true,
  });
  assert.deepEqual(playerBridge.postPhysicsSensorSnapshot().bounds, bounds);
  bounds = { x: 22, y: 24, width: 16, height: 18 };
  assert.deepEqual(playerBridge.postPhysicsSensorSnapshot().bounds, bounds);

  const combat = new t.LegacyCombatBridge(activations, router);
  combat.beginAttack('managed.fatty', ['managed.contact']);
  const contact = {
    sourceNodeId: 'managed.fatty', attackAreaNodeId: 'managed.contact',
    targetAreaNodeId: playerBridge.damageAreaNodeId, damage: 8,
    weaponTags: [], damageTypes: ['physical'],
    impact: { x: 22, y: 24, knockX: 1, knockY: 0 },
  };
  assert.equal(combat.collectContact(contact), true);
  assert.equal(combat.collectContact(contact), true, 'backend callbacks only collect candidates');
  const outcomes = combat.resolveStep(100);
  assert.equal(outcomes.length, 1);
  assert.equal(outcomes[0].result.actualDamage, 6);
  assert.equal(state.hp, 24);
  assert.equal(state.commits, 1);

  combat.dispose();
  playerBridge.dispose();
  const replacement = { runtimeNodeId: 'replacement', getDamageState: () => ({ hp: 1, maxHp: 1, dead: false }), commitDamage: () => {} };
  assert.doesNotThrow(() => router.registerArea(replacement, {
    areaNodeId: playerBridge.damageAreaNodeId, priority: 0, damageMultiplier: 1,
  }));
});

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

test('map placement bridge assigns the Level 1 camp and nested chest to one scene owner', async () => {
  const map = JSON.parse(await readFile(`${REPOSITORY_ROOT}/src/game/content/maps/level-1.map.json`, 'utf8'));
  const bridge = new t.LegacyMapPlacementBridge('level-1', map.objects, map.bossCamps);
  const placements = bridge.scenePlacements();
  assert.deepEqual(placements, [{
    placementId: 'level-1-fatty-one-eye-camp',
    sceneId: 'encounter.level-1-fatty-camp',
    x: 2528,
    y: 1472,
    persistenceKey: 'level-1-fatty-one-eye-camp',
  }]);
  const chest = map.objects.find((entry) => entry.instanceId === 'level-1-fatty-guarded-chest');
  assert.equal(bridge.shouldSuppressLegacyObject(chest), true);
  assert.equal(bridge.shouldSuppressLegacyBossCamp(map.bossCamps[0]), true);
});
