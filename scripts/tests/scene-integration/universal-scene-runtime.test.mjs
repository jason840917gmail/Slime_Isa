import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

function fakePhaser() {
  const state = { disabled: 0, enabled: 0, steps: 0, sprites: [] };
  const scene = {
    add: {
      sprite(_x, _y, texture, frame) {
        const sprite = {
          texture, frame: { name: frame }, active: true,
          setName() { return this; }, setOrigin() { return this; }, setAlpha(value) { this.alpha = value; return this; },
          setFlip() { return this; }, setTint() { return this; }, setPosition() { return this; }, setRotation() { return this; },
          setScale() { return this; }, setVisible() { return this; }, setDepth() { return this; },
          setFrame(value) { this.frame.name = value; return this; }, destroy() { this.active = false; },
        };
        state.sprites.push(sprite);
        return sprite;
      },
    },
    physics: {
      systems: {}, disableUpdate() { state.disabled += 1; }, enableUpdate() { state.enabled += 1; },
      world: { step() { state.steps += 1; }, overlapRect() { return []; } },
      add: { collider() { return { destroy() {} }; } },
    },
  };
  return { scene, state };
}

const animatedScene = {
  version: 1,
  sceneId: 'fixture.animated',
  rootNodeId: 'root',
  nodes: [
    { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
    { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0, properties: { texture: { resourceId: 'fixture.texture' }, frame: 0 } },
    { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'root', order: 1, properties: { library: { resourceId: 'fixture.animations' }, domain: 'render', autoplay: 'pulse' } },
  ],
  instances: [],
  subresources: [
    { version: 1, resourceId: 'fixture.texture', kind: 'texture', assetId: 'fixture.asset' },
    { version: 1, resourceId: 'fixture.animations', kind: 'animation-library', animations: {
      pulse: { durationSeconds: 2, framesPerSecond: 1, loop: true, tracks: [{ binding: '../Visual', property: 'frame', keys: [{ at: 0, value: 0 }, { at: 1, value: 1 }] }] },
    } },
  ],
};

test('universal Phaser runtime mounts multiple packed instances, resolves animation bindings, and owns cleanup', async () => {
  const descriptors = t.createGameDescriptorRegistry();
  const content = await t.PreparedSceneContent.prepare({
    scenes: [animatedScene], resources: [], registry: descriptors, sceneIds: ['fixture.animated'],
    hasAsset: (assetId) => assetId === 'fixture.asset',
  });
  const { scene, state } = fakePhaser();
  const runtime = new t.PhaserUniversalSceneRuntime({
    scene, content, descriptors, resolveAssetKey: (assetId) => `runtime-${assetId}`,
  });
  const first = runtime.mountScene('fixture.animated', { runtimeNamespace: 'fixture-first', position: { x: 10, y: 20 } });
  const second = runtime.mountScene('fixture.animated', { runtimeNamespace: 'fixture-second' });
  assert.equal(runtime.mountedSceneCount, 2);
  assert.deepEqual(first.mount.position, { x: 10, y: 20 });
  assert.equal(state.sprites[0].texture, 'runtime-fixture.asset');
  runtime.advanceFrame(1);
  assert.equal(state.sprites[0].frame.name, 1);
  first.dispose();
  assert.equal(first.disposed, true);
  assert.equal(runtime.mountedSceneCount, 1);
  assert.equal(state.sprites[0].active, false);
  assert.equal(runtime.context.resource('fixture.texture').assetId, 'fixture.asset');
  second.dispose();
  assert.throws(() => runtime.context.resource('fixture.texture'), /not available/);
  runtime.shutdown();
  content.dispose();
  assert.deepEqual({ disabled: state.disabled, enabled: state.enabled }, { disabled: 1, enabled: 1 });
  assert.throws(() => runtime.mountScene('fixture.animated'), /shut down/);
});
