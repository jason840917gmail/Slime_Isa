import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let stateModule;
let viewModule;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [stateModule, viewModule] = await Promise.all([
    loadTypeScriptModule('src/game/editor/LayeredAnimationDocumentState.ts'),
    loadTypeScriptModule('src/game/editor/LayeredAnimationTimelineView.ts'),
  ]);
});

function fixture() {
  return {
    version: 2, durationSeconds: 1, framesPerSecond: 10, loop: false, loopMode: 'wrap',
    layers: [
      { layerId: 'base', displayName: 'Base', assetId: 'weapon.base', depthOffset: 0, blocks: [{ from: 0, through: 2, sourceFrame: 1 }, { from: 6, through: 7, sourceFrame: 2 }] },
      { layerId: 'trail', displayName: 'Trail', assetId: 'effect.trail', depthOffset: 0.1, blocks: [{ from: 3, through: 4, sourceFrame: 3 }] },
    ],
  };
}

test('clicked block duration controls mutate their own lane without relying on selection', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  state.selectBlock('base', 0);
  assert.equal(state.adjustBlockHold('trail', 0, 1), true);
  assert.deepEqual(state.value.animation.layers[1].blocks[0], { from: 3, through: 5, sourceFrame: 3 });
  assert.equal(state.value.animation.layers[0].blocks[0].through, 2);
});

test('Add Tiles scopes to one lane and rejects overlap or overflow atomically', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  const before = state.value.animation;
  assert.equal(state.insertTiles('base', [8, 9], 2), false);
  assert.deepEqual(state.value.animation, before);
  assert.equal(state.insertTiles('trail', [8, 9], 8), true);
  assert.deepEqual(state.value.animation.layers[1].blocks.slice(-2), [
    { from: 8, through: 8, sourceFrame: 8 }, { from: 9, through: 9, sourceFrame: 9 },
  ]);
  assert.equal(state.insertTiles('trail', [10, 11], 9), false);
});

test('block move and right-edge resize snap to frames and preserve transparent gaps', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  assert.equal(state.moveBlock('base', 1, 5.2), true);
  assert.deepEqual(state.value.animation.layers[0].blocks[1], { from: 5, through: 6, sourceFrame: 2 });
  assert.equal(state.resizeBlock('base', 0, 3.6), true);
  assert.equal(state.value.animation.layers[0].blocks[0].through, 4);
  assert.equal(state.deleteBlock('base', 0), true);
  assert.equal(state.value.animation.layers[0].blocks[0].from, 5);
});

test('duration guards visual blocks, hitbox spans, and events while FPS preserves frame indices', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  assert.equal(state.setDurationSeconds(0.7), false);
  assert.equal(state.setDurationSeconds(0.9, { events: [{ at: 9 }] }), false);
  assert.equal(state.setDurationSeconds(0.9, { hitboxSpans: [{ through: 8 }] }), true);
  assert.equal(state.value.animation.durationSeconds, 0.9);
  assert.equal(state.setFramesPerSecond(20), true);
  assert.equal(state.value.animation.durationSeconds, 0.45);
  assert.deepEqual(state.value.animation.layers[0].blocks, fixture().layers[0].blocks);
});

test('preview mute/solo state, layer order, and view geometry are deterministic', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  state.toggleLayerHidden('trail');
  state.toggleLayerSolo('base');
  state.moveLayer('trail', -1);
  const value = state.value;
  assert.deepEqual(value.animation.layers.map((layer) => layer.layerId), ['trail', 'base']);
  assert.deepEqual([...value.hiddenLayerIds], ['trail']);
  assert.equal(value.soloLayerId, 'base');
  assert.equal('hiddenLayerIds' in value.animation, false);
  const view = viewModule.createLayeredAnimationTimelineView(value.animation);
  assert.equal(view.timelineFrames, 10);
  assert.deepEqual(view.lanes[1].blocks.map((block) => [block.gridColumnStart, block.gridColumnSpan]), [[1, 3], [7, 2]]);
  assert.match(viewModule.renderLayeredBlockHoldControls('trail', 0, 1), /data-layer-id="trail"/);
  assert.match(viewModule.renderLayeredBlockResizeHandle('trail', 0, 1), /data-block-index="0"/);
});
