import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';

const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});

const policy = await vite.ssrLoadModule('/src/game/features/npcs/NpcWanderPolicy.ts');
const geometry = await vite.ssrLoadModule('/src/game/content/npcs/npcWanderGeometry.ts');

test.after(async () => vite.close());

const body = {
  shape: 'ellipse', width: 34, height: 24, radiusX: 17, radiusY: 12, centerOffsetX: 0, centerOffsetY: 10,
};

test('NPC policy uses the authored timing constants and pauses before moving', () => {
  assert.equal(policy.NPC_AREA_MARGIN, 8);
  assert.equal(policy.NPC_TARGET_ARRIVAL_DISTANCE, 6);
  assert.equal(policy.NPC_STUCK_PROGRESS_DISTANCE, 2);
  assert.equal(policy.NPC_STUCK_SAMPLE_MS, 750);

  const paused = policy.createNpcWanderState(100, 'left');
  const result = policy.stepNpcWander(paused, {
    position: { x: 10, y: 10 },
    deltaMs: 40,
    speed: 18,
    body,
    perimeter: { shape: 'rectangle', x: 0, y: 0, w: 160, h: 160 },
  });
  assert.equal(result.state.phase, 'pause');
  assert.equal(result.state.pauseRemainingMs, 60);
  assert.deepEqual(result.velocity, { x: 0, y: 0 });
  assert.equal(result.animation, 'idle');
  assert.equal(result.state.facing, 'left');
});

test('NPC policy samples a valid target and chooses the dominant-axis walk clip', () => {
  const result = policy.stepNpcWander(policy.createNpcWanderState(0), {
    position: { x: 40, y: 40 },
    deltaMs: 16,
    speed: 18,
    body,
    perimeter: { shape: 'rectangle', x: 0, y: 0, w: 160, h: 160 },
    random: () => 0.5,
  });
  assert.equal(result.state.phase, 'move');
  assert.ok(result.state.target);
  assert.equal(result.animation, 'walk-right');
  assert.ok(result.velocity.x > 0);
  assert.ok(Math.abs(result.velocity.x) >= Math.abs(result.velocity.y));
  assert.ok(geometry.npcAnchorInsideDomain(result.state.target, geometry.npcAnchorDomain({ shape: 'rectangle', x: 0, y: 0, w: 160, h: 160 }, body)));
});

test('NPC policy recovers a stalled target and normalizes non-finite deltas', () => {
  const stalled = policy.stepNpcWander({
    phase: 'move',
    pauseRemainingMs: 0,
    target: { x: 100, y: 0 },
    facing: 'right',
    stuckSampleRemainingMs: 1,
    previousDistance: 100,
  }, {
    position: { x: 0, y: 0 },
    deltaMs: 1,
    speed: 18,
    body,
    perimeter: { shape: 'rectangle', x: 0, y: 0, w: 160, h: 160 },
  });
  assert.equal(stalled.state.phase, 'pause');
  assert.equal(stalled.state.target, undefined);
  assert.deepEqual(stalled.velocity, { x: 0, y: 0 });

  const stillPaused = policy.stepNpcWander(policy.createNpcWanderState(100), {
    position: { x: 10, y: 10 },
    deltaMs: Number.POSITIVE_INFINITY,
    speed: 18,
    body,
    perimeter: { shape: 'rectangle', x: 0, y: 0, w: 160, h: 160 },
  });
  assert.equal(stillPaused.state.pauseRemainingMs, 100);
  assert.deepEqual(stillPaused.velocity, { x: 0, y: 0 });
});

test('NPC policy caps a large frame step at the sampled target', () => {
  const result = policy.stepNpcWander({
    phase: 'move', pauseRemainingMs: 0, target: { x: 100, y: 0 }, facing: 'right',
    stuckSampleRemainingMs: policy.NPC_STUCK_SAMPLE_MS, previousDistance: undefined,
  }, {
    position: { x: 0, y: 0 }, deltaMs: 500, speed: 42, body,
    perimeter: { shape: 'rectangle', x: 0, y: 0, w: 160, h: 160 },
  });
  assert.equal(result.velocity.x, 42);

  const nearTarget = policy.stepNpcWander({
    phase: 'move', pauseRemainingMs: 0, target: { x: 10, y: 0 }, facing: 'right',
    stuckSampleRemainingMs: policy.NPC_STUCK_SAMPLE_MS, previousDistance: undefined,
  }, {
    position: { x: 0, y: 0 }, deltaMs: 500, speed: 42, body,
    perimeter: { shape: 'rectangle', x: 0, y: 0, w: 160, h: 160 },
  });
  assert.equal(nearTarget.velocity.x, 20);
});
