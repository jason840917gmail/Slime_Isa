import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const territory = await loadTypescriptModule('src/game/enemies/ai/Territory.ts');
const { segmentIntersectsRect } = await loadTypescriptModule('src/game/shared/segmentIntersectsRect.ts');

const home = { shape: 'circle', x: 0, y: 0, radius: 100 };
const rules = { ...territory.DEFAULT_TERRITORY_RULES, leashRange: 500, searchMs: 3000 };
const base = { now: 0, home, aggroRange: 250, attackReach: 40, seesPlayer: true, hurt: false };

function run(memory, input) {
  return territory.stepTerritory(memory, { ...base, ...input }, rules);
}

test('an enemy at home notices a player in sight and in range, or one that hits it', () => {
  const memory = territory.createTerritoryMemory();
  assert.equal(run(memory, { enemy: { x: 0, y: 0 }, player: { x: 400, y: 0 } }).mode, 'home', 'out of aggro range');
  assert.equal(run(memory, { enemy: { x: 0, y: 0 }, player: { x: 200, y: 0 }, seesPlayer: false }).mode, 'home', 'behind a wall');
  const seen = run(memory, { enemy: { x: 0, y: 0 }, player: { x: 200, y: 0 } });
  assert.equal(seen.mode, 'engaged');
  assert.equal(seen.mayEngage, true);
  const other = territory.createTerritoryMemory();
  assert.equal(run(other, { enemy: { x: 0, y: 0 }, player: { x: 400, y: 0 }, seesPlayer: false, hurt: true }).mode, 'engaged', 'a hit always pulls a reachable enemy');
});

test('the leash: near home it chases far, at the edge only a player almost in reach', () => {
  // distance from home + (distance to player - reach) <= 500
  assert.equal(territory.withinLeash(rules, 0, 400, 40), true, 'at home, a player 400 away is worth it');
  assert.equal(territory.withinLeash(rules, 450, 400, 40), false, 'far from home, the same player is not');
  assert.equal(territory.withinLeash(rules, 450, 60, 40), true, 'far from home, a player almost in reach still is');
  const memory = { mode: 'engaged', searchUntil: 0 };
  const decision = run(memory, { enemy: { x: 560, y: 0 }, player: { x: 800, y: 0 } });
  assert.equal(decision.mode, 'returning', 'past the leash it gives up');
  assert.deepEqual(decision.moveTo, { x: 0, y: 0 });
  assert.equal(decision.regenerate, true);
});

test('a player who hides is searched for 3 seconds where last seen, then the enemy goes home', () => {
  const memory = territory.createTerritoryMemory();
  run(memory, { now: 0, enemy: { x: 0, y: 0 }, player: { x: 200, y: 0 } });
  const lost = run(memory, { now: 100, enemy: { x: 50, y: 0 }, player: { x: 260, y: 40 }, seesPlayer: false });
  assert.equal(lost.mode, 'searching');
  assert.deepEqual(lost.moveTo, { x: 200, y: 0 }, 'walks to where it last saw the player');
  const there = run(memory, { now: 1500, enemy: { x: 195, y: 0 }, player: { x: 260, y: 40 }, seesPlayer: false });
  assert.equal(there.hold, true, 'looks around on the spot');
  assert.equal(run(memory, { now: 3099, enemy: { x: 195, y: 0 }, player: { x: 260, y: 40 }, seesPlayer: false }).mode, 'searching');
  assert.equal(run(memory, { now: 3100, enemy: { x: 195, y: 0 }, player: { x: 260, y: 40 }, seesPlayer: false }).mode, 'returning', 'gives up after 3 s');
});

test('a searching enemy that sees the player again resumes the chase', () => {
  const memory = { mode: 'searching', searchUntil: 3000, lastSeen: { x: 200, y: 0 } };
  assert.equal(run(memory, { now: 1000, enemy: { x: 150, y: 0 }, player: { x: 300, y: 0 } }).mode, 'engaged');
});

test('going home it ignores the player, turns only for a reachable hit, and heals fully on arrival', () => {
  const memory = { mode: 'returning', searchUntil: 0 };
  assert.equal(run(memory, { enemy: { x: 300, y: 0 }, player: { x: 350, y: 0 } }).mode, 'returning', 'sight alone does not turn it');
  assert.equal(run(memory, { enemy: { x: 300, y: 0 }, player: { x: 350, y: 0 }, hurt: true }).mode, 'engaged', 'a hit from within the leash does');
  const back = { mode: 'returning', searchUntil: 0 };
  assert.equal(run(back, { enemy: { x: 480, y: 0 }, player: { x: 1200, y: 0 }, hurt: true }).mode, 'returning', 'a hit from beyond the leash does not: it keeps healing');
  const arrived = run(back, { enemy: { x: 90, y: 0 }, player: { x: 1200, y: 0 } });
  assert.equal(arrived.mode, 'home');
  assert.equal(arrived.restoreHealth, true);
});

test('home distance, rectangle homes and the sight segment test', () => {
  const rect = { shape: 'rectangle', x: 0, y: 0, w: 100, h: 50 };
  assert.equal(territory.homeDistance(rect, { x: 50, y: 25 }), 0);
  assert.equal(territory.homeDistance(rect, { x: 130, y: 90 }), 50);
  assert.equal(territory.homeDistance(home, { x: 150, y: 0 }), 50);
  assert.deepEqual(territory.homeCenter(rect), { x: 50, y: 25 });
  assert.equal(segmentIntersectsRect({ x: 0, y: 0 }, { x: 100, y: 0 }, 40, -10, 20, 20), true, 'a wall between blocks');
  assert.equal(segmentIntersectsRect({ x: 0, y: 0 }, { x: 100, y: 0 }, 40, 10, 20, 20), false, 'a wall beside does not');
  assert.equal(segmentIntersectsRect({ x: 0, y: 0 }, { x: 30, y: 0 }, 40, -10, 20, 20), false, 'a wall beyond the target does not');
  assert.equal(segmentIntersectsRect({ x: 0, y: 0 }, { x: 100, y: 100 }, 45, 45, 10, 10), true, 'diagonals');
});
