import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const result = await build({ absWorkingDir: root, entryPoints: ['src/game/features/bosses/BossCampBehavior.ts'], bundle: true, format: 'esm', platform: 'node', write: false });
const behavior = await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
const circle = { shape: 'circle', x: 100, y: 100, radius: 20 };

test('perimeters include their exact boundary', () => {
  assert.equal(behavior.bossPerimeterContains(circle, 120, 100), true);
  assert.equal(behavior.bossPerimeterContains(circle, 120.01, 100), false);
});

test('never-defeated and transient-reset camps respawn immediately inside activation without duplicating a live boss', () => {
  const base = { hasLiveBoss: false, insideActivation: true, observedOutsideAfterDefeat: true, epochNow: 1000 };
  assert.equal(behavior.bossCampSpawnEligible(base), true);
  assert.equal(behavior.bossCampSpawnEligible({ ...base, observedOutsideAfterDefeat: false }), true);
  assert.equal(behavior.bossCampSpawnEligible({ ...base, hasLiveBoss: true }), false);
});

test('true defeat requires timer plus observed exit/re-entry and handles clock movement', () => {
  const base = { hasLiveBoss: false, insideActivation: true, respawnReadyAtEpochMs: 2000, observedOutsideAfterDefeat: true, epochNow: 2000 };
  assert.equal(behavior.bossCampSpawnEligible(base), true);
  assert.equal(behavior.bossCampSpawnEligible({ ...base, epochNow: 1999 }), false);
  assert.equal(behavior.bossCampSpawnEligible({ ...base, observedOutsideAfterDefeat: false }), false);
  assert.equal(behavior.bossCampSpawnEligible({ ...base, insideActivation: false }), false);
});

test('player-death reset suppression holds through the boundary and clears outside without spawning that update', () => {
  assert.deepEqual(behavior.resolveBossCampSpawnSuppression(false, true), {
    suppressSpawnUntilOutside: false,
    blocksSpawnThisUpdate: false,
  });
  assert.deepEqual(behavior.resolveBossCampSpawnSuppression(true, true), {
    suppressSpawnUntilOutside: true,
    blocksSpawnThisUpdate: true,
  });
  assert.deepEqual(behavior.resolveBossCampSpawnSuppression(true, false), {
    suppressSpawnUntilOutside: false,
    blocksSpawnThisUpdate: true,
  });
  assert.equal(behavior.bossPerimeterContains(circle, 120, 100), true);
});
