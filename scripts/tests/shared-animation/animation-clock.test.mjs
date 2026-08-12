import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let clockModule;
let playerModule;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: [entryPoint],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [clockModule, playerModule] = await Promise.all([
    loadTypeScriptModule('src/game/shared/animation/clock.ts'),
    loadTypeScriptModule('src/game/shared/animation/player.ts'),
  ]);
});

const timeline = (overrides = {}) => ({
  durationSeconds: 0.3, framesPerSecond: 10, loop: false, loopMode: 'wrap', ...overrides,
});

test('clock dispatches visual, track, event, then completion in deterministic order', () => {
  const calls = [];
  const clock = new clockModule.AnimationClock({
    onEvent: (event) => calls.push(`event:${event.eventId}`),
    onComplete: () => calls.push('complete'),
  });
  clock.subscribeFrame('track', (state) => calls.push(`track:${state.timelineFrame}`));
  clock.subscribeFrame('visual', (state) => calls.push(`visual:${state.timelineFrame}`));
  clock.start(timeline(), [{ at: 2, eventId: 'impact' }]);
  calls.length = 0;
  clock.update(300);
  assert.deepEqual(calls, ['visual:1', 'track:1', 'visual:2', 'track:2', 'event:impact', 'complete']);
  assert.equal(clock.state.finished, true);
});

test('clock wrap and ping-pong traversal remain deterministic', () => {
  const wrapFrames = [];
  const wrap = new clockModule.AnimationClock();
  wrap.subscribeFrame('visual', (state) => wrapFrames.push(state.timelineFrame));
  wrap.start(timeline({ loop: true }));
  wrap.update(400);
  assert.deepEqual(wrapFrames, [0, 1, 2, 0, 1]);

  const pingPongFrames = [];
  const directions = [];
  const pingPong = new clockModule.AnimationClock();
  pingPong.subscribeFrame('visual', (state, context) => {
    pingPongFrames.push(state.timelineFrame);
    directions.push(context.direction);
  });
  pingPong.start(timeline({ loop: true, loopMode: 'ping-pong' }));
  pingPong.update(500);
  assert.deepEqual(pingPongFrames, [0, 1, 2, 1, 0, 1]);
  assert.deepEqual(directions, [1, 1, 1, -1, 1, 1]);
});

test('scrubbing emits frames only and cancel/destroy never completes', () => {
  const calls = [];
  const clock = new clockModule.AnimationClock({
    onEvent: () => calls.push('event'),
    onComplete: () => calls.push('complete'),
  });
  clock.subscribeFrame('visual', (state, context) => calls.push(`frame:${state.timelineFrame}:${context.isScrub}`));
  clock.start(timeline(), [{ at: 2, eventId: 'ignored-by-scrub' }]);
  calls.length = 0;
  clock.scrub(2);
  clock.stop();
  clock.destroy();
  clock.update(1000);
  assert.deepEqual(calls, ['frame:2:true']);
});

test('playback ID changes on restart but not pause/resume', () => {
  const clock = new clockModule.AnimationClock();
  const clip = timeline({ loop: true });
  clock.start(clip);
  const first = clock.state.playbackId;
  clock.pause();
  clock.resume();
  assert.equal(clock.state.playbackId, first);
  clock.start(clip);
  assert.equal(clock.state.playbackId, first + 1);
});

test('AnimationPlayer preserves the existing source-frame callback contract', () => {
  const frames = [];
  const events = [];
  let completed = 0;
  const player = new playerModule.AnimationPlayer({
    onFrame: (state) => frames.push([state.timelineFrame, state.keyframeIndex, state.sourceFrame]),
    onEvent: (event) => events.push(event.eventId),
    onComplete: () => { completed += 1; },
  });
  const clip = {
    frames: [10, 20], keyframeTimes: [0, 2], durationSeconds: 0.4,
    framesPerSecond: 10, loop: false, loopMode: 'wrap',
  };
  player.start(clip, [{ at: 2, eventId: 'switch' }]);
  player.update(400);
  assert.deepEqual(frames, [[0, 0, 10], [1, 0, 10], [2, 1, 20], [3, 1, 20]]);
  assert.deepEqual(events, ['switch']);
  assert.equal(completed, 1);
  assert.equal(player.state.finished, true);
  assert.equal(player.state.sourceFrame, 20);
});
