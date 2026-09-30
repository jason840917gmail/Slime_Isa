import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { SlimeTrailModel } = await loadTypescriptModule('src/game/features/feel/SlimeTrail.ts');

const options = { poolSize: 4, spacing: 30, lifetimeMs: 1000, freshMs: 500 };

test('a mark drops every spacing of movement, from a fixed pool reused oldest first', () => {
  const trail = new SlimeTrailModel(options);
  assert.equal(trail.step(0, { x: 0, y: 0 }), 0);
  assert.equal(trail.step(10, { x: 20, y: 0 }), undefined, 'not far enough yet');
  assert.equal(trail.step(20, { x: 30, y: 0 }), 1);
  assert.equal(trail.step(30, { x: 60, y: 0 }), 2);
  assert.equal(trail.step(40, { x: 90, y: 0 }), 3);
  assert.equal(trail.step(50, { x: 120, y: 0 }), 0, 'the pool wraps to the oldest mark');
  assert.equal(trail.marks.length, 4, 'never grows');
  assert.deepEqual([trail.marks[0].x, trail.marks[0].bornAt], [120, 50]);
});

test('marks fade over their life, only fresh ones slow, and off-ground steps only age them', () => {
  const trail = new SlimeTrailModel(options);
  trail.step(0, { x: 0, y: 0 });
  trail.step(100, { x: 40, y: 0 });
  assert.equal(trail.opacity(trail.marks[0], 500), 0.5);
  assert.deepEqual(trail.freshPoints(450), [{ x: 0, y: 0 }, { x: 40, y: 0 }]);
  assert.deepEqual(trail.freshPoints(550), [{ x: 40, y: 0 }], 'the first mark is no longer fresh');
  assert.equal(trail.step(700, undefined), undefined, 'mid-jump: nothing drops');
  trail.step(1000, undefined);
  assert.equal(trail.marks[0].live, false, 'expired');
  assert.equal(trail.opacity(trail.marks[0], 1000), 0);
  assert.equal(trail.step(1010, { x: 45, y: 0 }), 2, 'after landing the next step drops at once');
});
