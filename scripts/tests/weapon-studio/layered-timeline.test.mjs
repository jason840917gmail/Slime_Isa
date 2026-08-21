import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let stateModule;
let viewModule;
let inspectorModule;
let layeredModule;
let sharedStateModule;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [stateModule, viewModule, inspectorModule, layeredModule, sharedStateModule] = await Promise.all([
    loadTypeScriptModule('src/game/editor/LayeredAnimationDocumentState.ts'),
    loadTypeScriptModule('src/game/editor/LayeredAnimationTimelineView.ts'),
    loadTypeScriptModule('src/game/editor/LayeredAnimationBlockInspector.ts'),
    loadTypeScriptModule('src/game/shared/animation/layered.ts'),
    loadTypeScriptModule('src/game/editor/SharedAnimationDocumentState.ts'),
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

test('layered preview playback honors wrap and ping-pong loop modes', () => {
  const animation = { durationSeconds: 0.3, framesPerSecond: 10, loop: true, loopMode: 'wrap' };
  assert.deepEqual([0, 1, 2, 3, 4].map((step) => layeredModule.layeredAnimationFrameAtStep(animation, step)), [0, 1, 2, 0, 1]);
  assert.deepEqual([0, 1, 2, 3, 4, 5].map((step) => layeredModule.layeredAnimationFrameAtStep({ ...animation, loopMode: 'ping-pong' }, step)), [0, 1, 2, 1, 0, 1]);
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  assert.equal(state.setLoopMode('ping-pong'), true);
  assert.equal(state.value.animation.loopMode, 'ping-pong');
});

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

test('Add Tiles replaces occupied cells without changing the master duration', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  assert.equal(state.placeTiles('base', [8, 9], 2), true);
  assert.equal(state.value.animation.durationSeconds, 1);
  assert.deepEqual(state.value.animation.layers[0].blocks, [
    { from: 0, through: 1, sourceFrame: 1 },
    { from: 2, through: 2, sourceFrame: 8 },
    { from: 3, through: 3, sourceFrame: 9 },
    { from: 6, through: 7, sourceFrame: 2 },
  ]);
});

test('shared animation history undoes and redoes authored edits without recording selection changes', () => {
  const state = new sharedStateModule.SharedAnimationDocumentState({
    $schema: './animation.schema.json',
    version: 1,
    animationId: 'weapon.test.attack',
    displayName: 'Test attack',
    description: 'Test package',
    animation: fixture(),
  });
  assert.equal(state.mutateAnimation((document) => document.placeTiles('base', [8], 2)), true);
  assert.equal(state.canUndo, true);
  assert.equal(state.value.animation.animation.layers[0].blocks.some((block) => block.sourceFrame === 8), true);
  assert.equal(state.undo(), true);
  assert.equal(state.value.animation.animation.layers[0].blocks.some((block) => block.sourceFrame === 8), false);
  assert.equal(state.canRedo, true);
  assert.equal(state.redo(), true);
  assert.equal(state.value.animation.animation.layers[0].blocks.some((block) => block.sourceFrame === 8), true);

  const historyDepthBeforeSelection = state.canUndo;
  assert.equal(state.mutateAnimation((document) => document.selectBlock('base', 0)), true);
  assert.equal(state.canUndo, historyDepthBeforeSelection);
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

test('selected tile visual controls render every authored occurrence transform value', () => {
  const block = {
    from: 4,
    through: 6,
    sourceFrame: 9,
    transform: { offset: [35.05, -12.56], scale: [1.25, 0.75], rotationDeg: 17 },
  };
  const html = inspectorModule.renderLayeredAnimationBlockInspector({ block, framesPerSecond: 24, timelineFrames: 12 });
  assert.match(html, /Selected tile/);
  assert.match(html, /data-block-timing-field="startSeconds"/);
  assert.match(html, /Tile offset X/);
  assert.match(html, /Tile offset Y/);
  assert.match(html, /Tile scale X/);
  assert.match(html, /Tile scale Y/);
  assert.match(html, /Tile rotation/);
  assert.match(html, /value="35\.05"[^>]*data-block-transform-field="offsetX"/);
  assert.match(html, /value="-12\.56"[^>]*data-block-transform-field="offsetY"/);
  assert.match(html, /value="1\.25"[^>]*data-block-transform-field="scaleX"/);
  assert.match(html, /value="0\.75"[^>]*data-block-transform-field="scaleY"/);
  assert.match(html, /value="17"[^>]*data-block-transform-field="rotationDeg"/);
  assert.match(html, /data-block-transform-field="flipX"/);
  assert.match(html, /data-block-transform-field="flipY"/);
  assert.match(html, /data-action="reset-block-transform"/);
});

test('Basic sword authored block offsets remain visible in the selected-tile inspector', async () => {
  const animationPackage = JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/animations/weapons/basic-sword/attack-right/animation.json'), 'utf8'));
  const block = animationPackage.animation.layers[0].blocks[0];
  assert.ok(block.transform?.offset, 'Basic sword first attack block must keep its authored offset');
  const html = inspectorModule.renderLayeredAnimationBlockInspector({
    block,
    framesPerSecond: animationPackage.animation.framesPerSecond,
    timelineFrames: 10,
  });
  assert.match(html, new RegExp(`value="${block.transform.offset[0]}"[^>]*data-block-transform-field="offsetX"`));
  assert.match(html, new RegExp(`value="${block.transform.offset[1]}"[^>]*data-block-transform-field="offsetY"`));
});

test('tile transform edits target one block and preserve its timing and source frame', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  assert.equal(state.setBlockTransform('base', 1, {
    offset: [42.33, -16.53], scale: [1.1, 0.9], rotationDeg: 12,
  }), true);
  assert.deepEqual(state.value.animation.layers[0].blocks[1], {
    from: 6, through: 7, sourceFrame: 2,
    transform: { offset: [42.33, -16.53], scale: [1.1, 0.9], rotationDeg: 12 },
  });
  assert.equal(state.value.animation.layers[0].blocks[0].transform, undefined);
  assert.equal(state.setBlockTransform('base', 1), true);
  assert.deepEqual(state.value.animation.layers[0].blocks[1], { from: 6, through: 7, sourceFrame: 2 });
});

test('duration is authoritative and rescales visual blocks like weapon keyframes', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  assert.equal(state.setDurationSeconds(0.7), true);
  assert.equal(state.value.animation.durationSeconds, 0.7);
  assert.deepEqual(state.value.animation.layers[0].blocks.map(({ from, through }) => ({ from, through })), [
    { from: 0, through: 1 },
    { from: 4, through: 5 },
  ]);
  assert.equal(state.setDurationSeconds(0.75), true);
  assert.equal(state.value.animation.durationSeconds, 0.75);
  assert.deepEqual(state.value.animation.layers[0].blocks.map(({ from, through }) => ({ from, through })), [
    { from: 0, through: 1 },
    { from: 5, through: 6 },
  ]);
  assert.equal(viewModule.createLayeredAnimationTimelineView(state.value.animation).effectiveDurationSeconds, 0.75);
});

test('FPS re-samples block timing while preserving the authored duration', () => {
  const state = new stateModule.LayeredAnimationDocumentState(fixture());
  assert.equal(state.setDurationSeconds(0.75), true);
  assert.equal(state.setFramesPerSecond(20), true);
  assert.equal(state.value.animation.durationSeconds, 0.75);
  assert.deepEqual(state.value.animation.layers[0].blocks.map(({ from, through }) => ({ from, through })), [
    { from: 0, through: 3 },
    { from: 10, through: 11 },
  ]);
  assert.deepEqual(state.value.animation.layers[1].blocks.map(({ from, through }) => ({ from, through })), [
    { from: 4, through: 7 },
  ]);
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
