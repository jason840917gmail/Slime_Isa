import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let LayeredAnimationDocumentState;

before(async () => {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: ['src/game/editor/LayeredAnimationDocumentState.ts'],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  const module = await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
  ({ LayeredAnimationDocumentState } = module);
});

function animationFixture() {
  return {
    version: 2,
    durationSeconds: 0.5,
    framesPerSecond: 10,
    loop: false,
    loopMode: 'wrap',
    layers: [{
      layerId: 'weapon',
      displayName: 'Weapon',
      assetId: 'weapon.fixture',
      depthOffset: 0,
      blocks: [{
        from: 0,
        through: 0,
        sourceFrame: 3,
        transform: { offset: [4, -2], scale: [0.8, 1.1], rotationDeg: 15 },
      }],
    }],
  };
}

test('duplicateBlock copies the selected tile occurrence into the next timeline frame', () => {
  const state = new LayeredAnimationDocumentState(animationFixture());

  assert.equal(state.duplicateBlock('weapon', 0), true);
  assert.deepEqual(state.value.animation.layers[0].blocks, [
    { from: 0, through: 0, sourceFrame: 3, transform: { offset: [4, -2], scale: [0.8, 1.1], rotationDeg: 15 } },
    { from: 1, through: 1, sourceFrame: 3, transform: { offset: [4, -2], scale: [0.8, 1.1], rotationDeg: 15 } },
  ]);
  assert.deepEqual(state.value.selection, { layerId: 'weapon', blockIndex: 1, playhead: 1 });
});

test('duplicateBlock keeps duration authoritative when the selected tile reaches its end', () => {
  const state = new LayeredAnimationDocumentState({
    ...animationFixture(),
    durationSeconds: 0.1,
    layers: [{ ...animationFixture().layers[0], blocks: [{ from: 0, through: 0, sourceFrame: 3 }] }],
  });

  assert.equal(state.duplicateBlock('weapon', 0), false);
  assert.equal(state.value.animation.durationSeconds, 0.1);
  assert.deepEqual(state.value.animation.layers[0].blocks.map(({ from, through }) => ({ from, through })), [
    { from: 0, through: 0 },
  ]);
});

test('duplicateBlock refuses to overlap another tile', () => {
  const overlapping = new LayeredAnimationDocumentState({
    ...animationFixture(),
    layers: [{
      ...animationFixture().layers[0],
      blocks: [
        animationFixture().layers[0].blocks[0],
        { from: 1, through: 1, sourceFrame: 4 },
      ],
    }],
  });
  assert.equal(overlapping.duplicateBlock('weapon', 0), false);
});
