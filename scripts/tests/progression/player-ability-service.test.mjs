import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { PlayerAbilityService } = await loadTypescriptModule('src/game/features/player/PlayerAbilityService.ts');

function fixture({ learned = ['jump', 'teleport', 'squash-slam', 'stretch-lash'], energy = 100, blocked = () => false } = {}) {
  let now = 0;
  let actionLocked = false;
  let spendCount = 0;
  const service = new PlayerAbilityService({
    nowMs: () => now,
    state: {
      isLearned: (abilityId) => learned.includes(abilityId),
      getEnergy: () => energy,
      isActionLocked: () => actionLocked,
      setActionLocked: (locked) => { actionLocked = locked; },
      spendEnergy: (amount) => {
        if (energy < amount) return false;
        energy -= amount;
        spendCount += amount > 0 ? 1 : 0;
        return true;
      },
    },
    terrain: { isBlocked: blocked },
  });
  return {
    service,
    setNow: (value) => { now = value; },
    setLocked: (value) => { actionLocked = value; },
    get locked() { return actionLocked; },
    get energy() { return energy; },
    get spendCount() { return spendCount; },
  };
}

const request = {
  position: { x: 10, y: 20 },
  direction: { x: 3, y: 4 },
  facing: { x: 0, y: -1 },
};

test('ability unlock, cooldown, energy, and busy checks preserve their decision order', () => {
  const locked = fixture({ learned: [] });
  assert.deepEqual(locked.service.tryBegin('jump', request), { accepted: false, reason: 'locked' });

  const active = fixture();
  const accepted = active.service.tryBegin('teleport', request);
  assert.equal(accepted.accepted, true);
  assert.equal(active.energy, 65);
  assert.equal(active.spendCount, 1);
  assert.equal(active.locked, true);
  assert.deepEqual(active.service.tryBegin('jump', request), { accepted: false, reason: 'busy' });
  assert.equal(active.service.complete(999), false);
  assert.equal(active.service.complete(accepted.intent.sequenceId), true);
  assert.equal(active.locked, false);
  assert.deepEqual(active.service.tryBegin('teleport', request), { accepted: false, reason: 'cooldown' });
  active.setNow(1800);
  assert.equal(active.service.tryBegin('teleport', request).accepted, true);

  const noEnergy = fixture({ energy: 34 });
  assert.deepEqual(noEnergy.service.tryBegin('teleport', request), { accepted: false, reason: 'energy' });
  assert.equal(noEnergy.energy, 34);
  assert.equal(noEnergy.spendCount, 0);

  const actionLocked = fixture();
  actionLocked.setLocked(true);
  assert.deepEqual(actionLocked.service.tryBegin('jump', request), { accepted: false, reason: 'action-locked' });
});

test('a moving jump follows the movement; a jump from standing still lands where it started', () => {
  const open = fixture();
  const jump = open.service.tryBegin('jump', request);
  assert.equal(jump.accepted, true);
  assert.deepEqual(jump.intent.direction, { x: 0.6, y: 0.8 });
  assert.deepEqual(jump.intent.target, { x: 110.8, y: 154.4 });
  open.service.complete(jump.intent.sequenceId);

  const standing = fixture({ blocked: () => true });
  const inPlace = standing.service.tryBegin('jump', {
    position: { x: 10, y: 20 }, direction: { x: 0, y: 0 }, facing: { x: 0, y: -1 },
  });
  assert.equal(inPlace.accepted, true);
  assert.deepEqual(inPlace.intent.target, { x: 10, y: 20 }, 'no movement input: up and down on the spot');

  const wall = fixture({ blocked: (x) => x >= 26 });
  const shortJump = wall.service.tryBegin('jump', {
    position: { x: 10, y: 20 }, direction: { x: 1, y: 0 }, facing: { x: 1, y: 0 },
  });
  assert.equal(shortJump.accepted, true);
  assert.deepEqual(shortJump.intent.target, { x: 18, y: 20 }, 'a moving jump still stops before water');
});

test('teleport lands on the farthest safe spot, across a river or a thin wall, and fails without one', () => {
  const river = fixture({ blocked: (x) => x >= 100 && x < 180 });
  const across = river.service.tryBegin('teleport', {
    position: { x: 10, y: 20 }, direction: { x: 1, y: 0 }, facing: { x: 1, y: 0 },
  });
  assert.equal(across.accepted, true);
  assert.deepEqual(across.intent.target, { x: 250, y: 20 }, 'the full 240 px, on the far bank');

  const farBankWater = fixture({ blocked: (x) => x >= 100 });
  const shortOfRiver = farBankWater.service.tryBegin('teleport', {
    position: { x: 10, y: 20 }, direction: { x: 1, y: 0 }, facing: { x: 1, y: 0 },
  });
  assert.deepEqual(shortOfRiver.intent.target, { x: 98, y: 20 }, 'water all the way: the farthest safe spot before it');

  const occupied = new PlayerAbilityService({
    nowMs: () => 0,
    state: { isLearned: () => true, getEnergy: () => 100, isActionLocked: () => false, setActionLocked: () => {}, spendEnergy: () => true },
    terrain: { isBlocked: () => false, isOccupied: (x) => x > 200 },
  });
  const wall = occupied.tryBegin('teleport', { position: { x: 10, y: 20 }, direction: { x: 1, y: 0 }, facing: { x: 1, y: 0 } });
  assert.deepEqual(wall.intent.target, { x: 194, y: 20 }, 'never inside a wall, house or tree');

  const nowhere = fixture({ blocked: (x) => x > 10 });
  assert.deepEqual(nowhere.service.tryBegin('teleport', {
    position: { x: 10, y: 20 }, direction: { x: 1, y: 0 }, facing: { x: 1, y: 0 },
  }), { accepted: false, reason: 'blocked' });
  assert.equal(nowhere.energy, 100, 'a failed teleport costs nothing');
});

test('cancel releases the action lock without clearing cooldown or charging twice', () => {
  const active = fixture();
  const slam = active.service.tryBegin('squash-slam', request);
  assert.equal(slam.accepted, true);
  assert.equal(active.energy, 70);
  active.service.cancel();
  assert.equal(active.locked, false);
  assert.equal(active.service.isBusy(), false);
  assert.deepEqual(active.service.tryBegin('squash-slam', request), { accepted: false, reason: 'cooldown' });
  assert.equal(active.energy, 70);
  assert.equal(active.spendCount, 1);
});
