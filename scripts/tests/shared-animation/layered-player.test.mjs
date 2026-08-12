import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let animation;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  animation = await loadTypeScriptModule('src/game/shared/animation/index.ts');
});

test('layered player resolves gaps from the same external clock and releases its subscription', () => {
  const clock = new animation.AnimationClock();
  const document = animation.normalizeLayeredAnimation({
    version: 2, durationSeconds: 0.3, framesPerSecond: 10, loop: false,
    layers: [{
      layerId: 'flash', displayName: 'Flash', assetId: 'effect.flash', depthOffset: 0,
      blocks: [{ from: 1, through: 1, sourceFrame: 4 }],
    }],
  });
  const frames = [];
  const player = new animation.LayeredAnimationPlayer(clock, document, (state) => {
    frames.push([state.timelineFrame, state.layers.map((layer) => layer.sourceFrame)]);
  });
  clock.start(document);
  clock.update(300);
  assert.deepEqual(frames, [[0, []], [1, [4]], [2, []]]);
  player.destroy();
  clock.start(document);
  assert.equal(frames.length, 3);
});
