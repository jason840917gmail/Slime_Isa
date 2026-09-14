import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { PlayerHealthService, mitigatePlayerDamage } = await loadTypescriptModule(
  'src/game/features/combat/tooling.ts',
);

const area = {
  areaNodeId: 'player:body',
  priority: 0,
  damageMultiplier: 1,
};

function damageRequest(overrides = {}) {
  return {
    activationId: 'enemy:1',
    sourceNodeId: 'enemy',
    attackAreaNodeId: 'enemy:attack',
    targetAreaNodeId: 'player:body',
    weaponTags: [],
    damageTypes: [],
    baseDamage: 10,
    effects: [],
    impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
    ...overrides,
  };
}

function harness({ hp = 30, maxHp = 30, defense = 3, damageTakenMult = 1, iFrameMs = 200 } = {}) {
  let currentHp = hp;
  let commits = 0;
  let deaths = 0;
  let effects = [];
  const service = new PlayerHealthService('player', {
    state: {
      getHp: () => currentHp,
      getMaxHp: () => maxHp,
      commitResolvedDamage: (amount) => {
        commits += 1;
        const before = currentHp;
        currentHp = Math.max(0, currentHp - amount);
        return before - currentHp;
      },
      heal: (amount) => {
        const before = currentHp;
        currentHp = Math.min(maxHp, currentHp + amount);
        return currentHp - before;
      },
      revive: () => { currentHp = maxHp; },
    },
    stats: { getHealthStats: () => ({ defense, damageTakenMult, iFrameMs }) },
    effects: { applyResolvedEffect: (effect) => effects.push(effect) },
    feedback: { onDeath: () => { deaths += 1; } },
  });
  return {
    service,
    get hp() { return currentHp; },
    get commits() { return commits; },
    get deaths() { return deaths; },
    get effects() { return effects; },
  };
}

test('player mitigation preserves defense, status multiplier, and fractional final rounding', () => {
  assert.equal(mitigatePlayerDamage(8.5, false, {
    defense: 3, damageTakenMult: 0.75, iFrameMs: 200,
  }), 4.125);
  const state = harness({ defense: 3, damageTakenMult: 0.75 });
  const outcome = state.service.applyDamage(damageRequest({ baseDamage: 8.5 }), area, 100);
  assert.equal(outcome.roundedDamage, 4);
  assert.equal(outcome.result.actualDamage, 4);
  assert.equal(state.hp, 26);
  assert.equal(state.commits, 1);
});

test('true damage bypasses defense only and still respects status multiplier and i-frames', () => {
  const state = harness({ defense: 50, damageTakenMult: 0.5, iFrameMs: 200 });
  const accepted = state.service.applyDamage(damageRequest({ baseDamage: 9, trueDamage: true }), area, 100);
  assert.equal(accepted.roundedDamage, 5);
  assert.equal(state.hp, 25);
  const blocked = state.service.applyDamage(damageRequest({ baseDamage: 9, trueDamage: true }), area, 299);
  assert.deepEqual(blocked.result, {
    status: 'rejected', actualDamage: 0, reason: 'state-blocked', retryable: true,
  });
  assert.equal(state.commits, 1);
  assert.equal(state.service.isInvulnerable(300), false);
});

test('positive damage keeps the minimum-one defense rule before the status multiplier', () => {
  assert.equal(mitigatePlayerDamage(2, false, {
    defense: 99, damageTakenMult: 0.5, iFrameMs: 0,
  }), 0.5);
  const state = harness({ defense: 99, damageTakenMult: 0.5, iFrameMs: 0 });
  const outcome = state.service.applyDamage(damageRequest({ baseDamage: 2 }), area, 0);
  assert.equal(outcome.roundedDamage, 1);
  assert.equal(outcome.result.actualDamage, 1);
});

test('overkill reports pre-clamp rounded damage but commits only remaining HP once', () => {
  const state = harness({ hp: 3, maxHp: 30, defense: 0 });
  const outcome = state.service.applyDamage(damageRequest({ baseDamage: 50 }), area, 10);
  assert.equal(outcome.roundedDamage, 50);
  assert.deepEqual(outcome.result, {
    status: 'accepted', actualDamage: 3, defeated: true, appliedEffects: [], rejectedEffects: [],
  });
  assert.equal(state.hp, 0);
  assert.equal(state.commits, 1);
  assert.equal(state.deaths, 1);
  state.service.markDead();
  assert.equal(state.deaths, 1, 'death must publish only once');
});

test('zero damage can commit an independent effect without manufacturing minimum damage', () => {
  const state = harness({ defense: 99 });
  const outcome = state.service.applyDamage(damageRequest({
    baseDamage: 0,
    effects: [{ effectId: 'slow', potency: 0.6 }],
  }), area, 10);
  assert.equal(outcome.roundedDamage, 0);
  assert.equal(outcome.result.status, 'accepted');
  assert.equal(outcome.result.actualDamage, 0);
  assert.equal(state.hp, 30);
  assert.equal(state.commits, 1);
  assert.deepEqual(state.effects, [{ effectId: 'slow', potency: 0.6 }]);
  assert.equal(state.service.isInvulnerable(11), false);
});

test('respawn clears death and invulnerability state', () => {
  const state = harness({ hp: 2, maxHp: 30, defense: 0, iFrameMs: 500 });
  state.service.applyDamage(damageRequest({ baseDamage: 2 }), area, 100);
  assert.equal(state.service.isDead(), true);
  state.service.respawn();
  assert.equal(state.hp, 30);
  assert.equal(state.service.isDead(), false);
  assert.equal(state.service.isInvulnerable(101), false);
});
