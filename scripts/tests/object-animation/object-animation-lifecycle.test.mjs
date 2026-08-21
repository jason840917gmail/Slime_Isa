import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { build } from 'esbuild';

const repoRoot = process.cwd();

async function loadObjectTemplateModules() {
  const result = await build({
    absWorkingDir: repoRoot,
    stdin: {
      contents: `export { ObjectTemplateEditorState } from './src/game/editor/ObjectTemplateEditorState.ts'; export { getObjectVisualChoice } from './src/game/content/objects/ObjectCatalog.ts';`,
      resolveDir: repoRoot,
      sourcefile: 'object-template-test-entry.ts',
    },
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

async function loadObjectAnimationAdapter() {
  const result = await build({
    absWorkingDir: repoRoot,
    entryPoints: [path.join(repoRoot, 'src/game/features/objects/ObjectAnimationAdapter.ts')],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
    plugins: [{
      name: 'phaser-test-double',
      setup(buildApi) {
        buildApi.onResolve({ filter: /^phaser$/ }, () => ({ path: 'phaser-test-double', namespace: 'test' }));
        buildApi.onLoad({ filter: /.*/, namespace: 'test' }, () => ({ contents: `export default { Scenes: { Events: { SHUTDOWN: 'shutdown' } } };` }));
      },
    }],
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

test('clearing an object animation updates both the draft and live visual override', async () => {
  const { ObjectTemplateEditorState, getObjectVisualChoice } = await loadObjectTemplateModules();
  const state = new ObjectTemplateEditorState('tree.world.solid', 'snow-pine');
  assert.equal(state.value.draft.idleAnimationId, 'object.tree.idle');
  assert.equal(state.updateDraft({ idleAnimationId: '' }), true);
  assert.equal(state.value.draft.idleAnimationId, undefined);
  assert.equal(getObjectVisualChoice('tree.world.solid', 'snow-pine').idleAnimationId, undefined);
});

test('disposing during on-hit playback finalizes its pending callback exactly once', async () => {
  const { ObjectAnimationAdapter } = await loadObjectAnimationAdapter();
  const listeners = new Map();
  const sprite = () => {
    const value = {};
    for (const method of ['setVisible', 'setFrame', 'setOrigin', 'setPosition', 'setScale', 'setFlip', 'setRotation', 'setDepth', 'setTexture']) value[method] = () => value;
    value.destroy = () => undefined;
    return value;
  };
  const scene = {
    events: {
      once: (event, listener) => listeners.set(event, listener),
      off: (event) => listeners.delete(event),
    },
    add: { sprite },
  };
  const anchor = {
    x: 10, y: 20, depth: 30, visible: true,
    setVisible(visible) { this.visible = visible; return this; },
  };
  const animation = {
    version: 2, durationSeconds: 0.25, framesPerSecond: 4, loop: false, loopMode: 'wrap',
    layers: [{
      layerId: 'base', displayName: 'Base', assetId: 'sheet.trees.8x6', depthOffset: 0,
      transform: { origin: [0.5, 1], offset: [0, 0], scale: [1, 1], rotationDeg: 0, flipX: false, flipY: false },
      blocks: [{ from: 0, through: 0, sourceFrame: 0, transform: { offset: [0, 0], scale: [1, 1], rotationDeg: 0, flipX: false, flipY: false } }],
    }],
  };
  const adapter = new ObjectAnimationAdapter({ scene, anchor, resolver: { get: () => ({ ok: true, animation, package: { animation } }) }, objectId: 'resource.test' });
  let completions = 0;
  assert.equal(adapter.animateOnHit('object.test.hit', () => { completions += 1; }), true);
  adapter.dispose();
  adapter.dispose();
  assert.equal(completions, 1);
  assert.equal(anchor.visible, true);
});
