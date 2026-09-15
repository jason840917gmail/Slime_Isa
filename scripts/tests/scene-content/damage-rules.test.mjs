import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const {
  AttackActivation,
  DamageRouter,
  damageSourceMatches,
  normalizeDamageRequest,
  resolveDamage,
} = await loadTypescriptModule('src/game/features/combat/tooling.ts');

function request(overrides = {}) {
  return {
    activationId: 'weapon:1',
    sourceNodeId: 'weapon',
    attackAreaNodeId: 'blade',
    targetAreaNodeId: 'body',
    weaponId: 'iron-spear',
    weaponTags: ['melee', 'spear'],
    damageTypes: ['physical', 'piercing'],
    baseDamage: 10,
    effects: [],
    impact: { x: 1, y: 2, knockX: 1, knockY: 0 },
    ...overrides,
  };
}

function rule(overrides = {}) {
  return {
    areaNodeId: 'body',
    priority: 0,
    damageMultiplier: 1,
    ...overrides,
  };
}

function receiver(overrides = {}) {
  const commits = [];
  const feedback = [];
  return {
    runtimeNodeId: 'target',
    getDamageState: () => ({ hp: 30, maxHp: 30, dead: false }),
    commitDamage: (commit) => commits.push(commit),
    publishDamageFeedback: (commit) => feedback.push(commit),
    commits,
    feedback,
    ...overrides,
  };
}

test('normalization supplies false and rejects duplicate identifiers and invalid numbers', () => {
  const normalized = normalizeDamageRequest(request());
  assert.equal(normalized.trueDamage, false);
  assert.deepEqual(normalized.damageTypes, ['physical', 'piercing']);
  assert.equal(normalizeDamageRequest(request({ weaponTags: ['spear', 'spear'] })), undefined);
  assert.equal(normalizeDamageRequest(request({ baseDamage: Number.NaN })), undefined);
  assert.equal(normalizeDamageRequest(request({ effects: [
    { effectId: 'burn', potency: 1 },
    { effectId: 'burn', potency: 2 },
  ] })), undefined);
});

test('source matchers use OR between entries and AND inside an entry', () => {
  const normalized = normalizeDamageRequest(request());
  const matchingRule = rule({
    acceptedSources: [
      { weaponIds: ['wood-club'] },
      { allWeaponTags: ['melee', 'spear'], anyDamageTypes: ['piercing'] },
    ],
  });
  assert.equal(damageSourceMatches(matchingRule, normalized), true);
  assert.equal(damageSourceMatches({ ...matchingRule, blockedWeaponTags: ['spear'] }, normalized), false);
  assert.equal(damageSourceMatches(rule({
    acceptedSources: [{ allWeaponTags: ['melee', 'magic'], anyDamageTypes: ['piercing'] }],
  }), normalized), false);
});

test('resolver scales unrounded values, invokes mitigation once, rounds once, and clamps overkill', () => {
  let mitigationCalls = 0;
  const target = receiver({
    getDamageState: () => ({ hp: 7, maxHp: 30, dead: false }),
    mitigateDamage: ({ scaledDamage }) => {
      mitigationCalls += 1;
      assert.equal(scaledDamage, 13.125);
      return scaledDamage * 0.6;
    },
  });
  const result = resolveDamage(target, request({ baseDamage: 12.5 }), rule({
    damageMultiplier: 1.5,
    damageTypeMultipliers: { piercing: 0.7, physical: 1 },
  }), 100);
  assert.equal(mitigationCalls, 1);
  assert.deepEqual(result, {
    status: 'accepted', actualDamage: 7, defeated: true, appliedEffects: [], rejectedEffects: [],
  });
  assert.equal(target.commits.length, 0, 'the pure resolver must not mutate the receiver');
});

test('effects resolve independently when computed damage is zero', () => {
  const target = receiver();
  const result = resolveDamage(target, request({
    baseDamage: 0,
    effects: [
      { effectId: 'burn', potency: 4 },
      { effectId: 'slow', potency: 2 },
      { effectId: 'sticky', potency: 3 },
    ],
  }), rule({
    damageMultiplier: 0,
    effectResponses: {
      burn: { mode: 'multiplier', multiplier: 1.5 },
      slow: { mode: 'immune' },
      sticky: { mode: 'multiplier', multiplier: 0 },
    },
  }), 100);
  assert.deepEqual(result, {
    status: 'accepted',
    actualDamage: 0,
    defeated: false,
    appliedEffects: [{ effectId: 'burn', potency: 6 }],
    rejectedEffects: [
      { effectId: 'slow', reason: 'immune' },
      { effectId: 'sticky', reason: 'zero-potency' },
    ],
  });
});

test('router selects highest-priority eligible area and commits before feedback exactly once', () => {
  const activations = new AttackActivation();
  const router = new DamageRouter(activations);
  const target = receiver();
  router.registerArea(target, rule({ areaNodeId: 'body', priority: 1, damageMultiplier: 1 }));
  router.registerArea(target, rule({ areaNodeId: 'eye', priority: 10, damageMultiplier: 2 }));
  const activationId = activations.begin('weapon', ['blade']);
  const outcomes = router.routeStep([
    request({ activationId, targetAreaNodeId: 'body' }),
    request({ activationId, targetAreaNodeId: 'eye' }),
  ], 100);
  assert.equal(outcomes.length, 1);
  assert.equal(outcomes[0].selectedAreaNodeId, 'eye');
  assert.equal(outcomes[0].result.actualDamage, 20);
  assert.equal(target.commits.length, 1);
  assert.equal(target.feedback.length, 1);
  assert.equal(target.commits[0], target.feedback[0]);

  const duplicate = router.routeStep([request({ activationId, targetAreaNodeId: 'eye' })], 101);
  assert.equal(duplicate[0].result.reason, 'duplicate');
  assert.equal(target.commits.length, 1);
});

test('router uses its shared simulation clock for receivers spanning independently mounted sources', () => {
  let simulationTime = 4_200;
  const activations = new AttackActivation();
  const router = new DamageRouter(activations, () => simulationTime);
  const observedTimes = [];
  const target = receiver({
    canReceiveDamage: (input) => { observedTimes.push(input.simulationTime); return { accepted: true }; },
  });
  router.registerArea(target, rule());
  const first = activations.begin('weapon', ['blade']);
  router.routeStep([request({ activationId: first })], 25);
  simulationTime = 9_900;
  const second = activations.begin('weapon', ['blade']);
  router.routeStep([request({ activationId: second })], 10);
  assert.deepEqual(observedTimes, [4_200, 9_900]);
  assert.deepEqual(target.commits.map((commit) => commit.simulationTime), [4_200, 9_900]);
});

test('an armor rejection does not suppress a later weak-point hit in the activation', () => {
  const activations = new AttackActivation();
  const router = new DamageRouter(activations);
  const target = receiver();
  router.registerArea(target, rule({
    areaNodeId: 'armor',
    priority: 20,
    acceptedSources: [{ allWeaponTags: ['blunt'] }],
  }));
  router.registerArea(target, rule({
    areaNodeId: 'eye',
    priority: 10,
    acceptedSources: [{ allWeaponTags: ['spear'] }],
  }));
  const activationId = activations.begin('weapon', ['blade']);
  const blocked = router.routeStep([request({ activationId, targetAreaNodeId: 'armor' })], 100);
  assert.equal(blocked[0].result.reason, 'source-blocked');
  const accepted = router.routeStep([request({ activationId, targetAreaNodeId: 'eye' })], 101);
  assert.equal(accepted[0].result.status, 'accepted');
  assert.equal(target.commits.length, 1);
});

test('state-blocked contact is retryable while terminal selected-area rejection is cached', () => {
  let grounded = false;
  const activations = new AttackActivation();
  const router = new DamageRouter(activations);
  const target = receiver({
    canReceiveDamage: () => grounded
      ? { accepted: true }
      : { accepted: false, reason: 'state-blocked' },
  });
  router.registerArea(target, rule({ areaNodeId: 'eye', priority: 10 }));
  const activationId = activations.begin('weapon', ['blade']);
  const rejected = router.routeStep([request({ activationId, targetAreaNodeId: 'eye' })], 100);
  assert.deepEqual(rejected[0].result, {
    status: 'rejected', actualDamage: 0, reason: 'state-blocked', retryable: true,
  });
  grounded = true;
  const accepted = router.routeStep([request({ activationId, targetAreaNodeId: 'eye' })], 101);
  assert.equal(accepted[0].result.status, 'accepted');
});

test('area ownership is unique and exact receiver disposal releases the lease', () => {
  const activations = new AttackActivation();
  const router = new DamageRouter(activations);
  const first = receiver();
  const second = receiver({ runtimeNodeId: 'other' });
  router.registerArea(first, rule());
  assert.throws(() => router.registerArea(second, rule()), /already registered/);
  router.unregisterArea(second, 'body');
  assert.throws(() => router.registerArea(second, rule()), /already registered/);
  router.unregisterArea(first, 'body');
  assert.doesNotThrow(() => router.registerArea(second, rule()));
});
