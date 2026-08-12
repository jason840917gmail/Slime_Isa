import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let animation; let trackModule;
async function load(entry) { const result = await build({ absWorkingDir: root, entryPoints: [entry], bundle: true, format: 'esm', platform: 'node', write: false }); return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`); }
before(async () => { [animation, trackModule] = await Promise.all([load('src/game/shared/animation/index.ts'), load('src/game/combat/WeaponAttackTrackRunner.ts')]); });
test('weapon visual and hitbox tracks consume one clock in phase order', () => {
  const calls = []; const clock = new animation.AnimationClock({ onEvent: (event) => calls.push(`event:${event.eventId}`), onComplete: () => calls.push('complete') });
  clock.subscribeFrame('visual', (state) => calls.push(`visual:${state.timelineFrame}`));
  const runner = new trackModule.WeaponAttackTrackRunner(clock, { hitboxSpans: [{ hitboxId: 'primary', from: 1, through: 1 }], events: [{ at: 1, eventId: 'sound.swing' }] }, { onHitboxActivated: () => calls.push('hitbox:on'), onHitboxDeactivated: () => calls.push('hitbox:off') });
  const clip = { version: 2, durationSeconds: 0.3, framesPerSecond: 10, loop: false, layers: [{ layerId: 'base', displayName: 'Base', assetId: 'weapon.fixture', depthOffset: 0, blocks: [{ from: 0, through: 2, sourceFrame: 0 }] }] };
  clock.start(clip, [{ at: 1, eventId: 'sound.swing' }]); calls.length = 0; clock.update(300);
  assert.deepEqual(calls, ['visual:1', 'hitbox:on', 'event:sound.swing', 'visual:2', 'hitbox:off', 'complete']); runner.destroy();
});
