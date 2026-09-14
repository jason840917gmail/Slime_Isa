import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

function fakePhaser() {
  const state = { sprites: [], cameras: [], disabled: 0, enabled: 0, steps: 0 };
  const chain = (target) => {
    for (const method of ['setName', 'setOrigin', 'setAlpha', 'setFlip', 'setTint', 'setPosition', 'setRotation', 'setScale', 'setVisible', 'setDepth', 'setZoom', 'setRoundPixels', 'setViewport']) {
      target[method] = (...args) => { target[method.slice(3).toLowerCase()] = args.length === 1 ? args[0] : args; return target; };
    }
    target.setFrame = (frame) => { target.frame.name = frame; return target; };
    return target;
  };
  const scene = {
    scale: { width: 320, height: 180 },
    add: { sprite: (_x, _y, texture, frame) => { const sprite = chain({ texture, frame: { name: frame }, active: true, destroy() { this.active = false; } }); state.sprites.push(sprite); return sprite; } },
    cameras: {
      add: () => { const camera = chain({ active: true, centerOn(x, y) { this.center = [x, y]; return this; } }); state.cameras.push(camera); return camera; },
      remove: (camera) => { camera.active = false; },
    },
    physics: { systems: {}, disableUpdate: () => { state.disabled += 1; }, enableUpdate: () => { state.enabled += 1; }, world: { step: () => { state.steps += 1; } } },
  };
  return { scene, state };
}

test('Sprite2D and Camera2D own entry leases, synchronize logical transforms, and re-enter cleanly', () => {
  const { scene, state } = fakePhaser();
  const resources = new Map([['texture.dot', { version: 1, resourceId: 'texture.dot', kind: 'texture', assetId: 'dot' }]]);
  const context = new t.PhaserNodeContext(scene, resources, (assetId) => `runtime-${assetId}`);
  const root = new t.Node2D({ runtimeId: 'fixture/root', name: 'Root', position: { x: 10, y: 20 } });
  const sprite = new t.Sprite2DNode({ runtimeId: 'fixture/sprite', name: 'Sprite', context, texture: 'texture.dot', position: { x: 2, y: 3 }, visualOffset: { x: 1, y: -1 }, alpha: 0.5, flipX: true });
  const camera = new t.Camera2DNode({ runtimeId: 'fixture/camera', name: 'Camera', context, position: { x: 4, y: 5 }, zoom: 2 });
  root.add_child(sprite); root.add_child(camera);
  const tree = new t.SceneTree(); tree.setRoot(root);
  context.synchronizePresentation(1);
  assert.equal(context.managedPresentationCount, 2);
  assert.equal(state.sprites[0].texture, 'runtime-dot');
  assert.deepEqual(state.sprites[0].position, [13, 22]);
  sprite.frame = 4;
  sprite.alpha = 0.25;
  assert.equal(state.sprites[0].frame.name, 4);
  assert.equal(state.sprites[0].alpha, 0.25);
  assert.deepEqual(state.cameras[0].center, [14, 25]);
  root.remove_child(sprite); tree.flushMutations();
  assert.equal(state.sprites[0].active, false);
  assert.equal(context.managedPresentationCount, 1);
  root.add_child(sprite); tree.flushMutations(); context.synchronizePresentation(1);
  assert.equal(state.sprites.length, 2);
  assert.equal(sprite.was_ready(), true);
  assert.equal(context.managedPresentationCount, 2);
  tree.shutdown();
  assert.equal(context.managedPresentationCount, 0);
  assert.equal(state.sprites.every((entry) => !entry.active), true);
  assert.equal(state.cameras.every((entry) => !entry.active), true);
});

test('packed resource leases share identical resources, reject collisions, and release inline resources', () => {
  const { scene } = fakePhaser();
  const base = { version: 1, resourceId: 'texture.base', kind: 'texture', assetId: 'base' };
  const inline = { version: 1, resourceId: 'shape.inline', kind: 'collision-shape', value: { shape: 'circle', radius: 4 } };
  const context = new t.PhaserNodeContext(scene, new Map([[base.resourceId, base]]));
  const releaseFirst = context.acquireResources([base, inline]);
  const releaseSecond = context.acquireResources([structuredClone(inline)]);
  assert.equal(context.resource('shape.inline').value.radius, 4);
  assert.throws(() => context.acquireResources([{ ...inline, value: { shape: 'circle', radius: 8 } }]), /conflicts/);
  releaseFirst();
  assert.equal(context.resource('shape.inline').value.radius, 4);
  releaseSecond();
  assert.throws(() => context.resource('shape.inline'), /not available/);
  assert.equal(context.resource('texture.base').assetId, 'base');
  context.shutdown();
});

test('one context exclusively owns manual Arcade stepping and releases ownership on shutdown', () => {
  const { scene, state } = fakePhaser();
  const first = new t.PhaserNodeContext(scene);
  const second = new t.PhaserNodeContext(scene);
  first.startManualStepping();
  assert.equal(state.disabled, 1);
  assert.throws(() => second.startManualStepping(), /already has a managed manual-step owner/);
  first.shutdown();
  assert.equal(state.enabled, 1);
  second.startManualStepping();
  second.shutdown();
  assert.deepEqual({ disabled: state.disabled, enabled: state.enabled }, { disabled: 2, enabled: 2 });
});

test('the Phaser registry constructs specialized presentation nodes from exported properties', () => {
  const { scene } = fakePhaser();
  const resource = { version: 1, resourceId: 'texture.dot', kind: 'texture', assetId: 'dot' };
  const context = new t.PhaserNodeContext(scene, new Map([['texture.dot', resource]]));
  const registry = t.createPhaserNodeRegistry(context);
  const node = registry.construct({
    runtimeId: 'registry/sprite', name: 'Sprite', type: 'Sprite2D', resources: new Map([['texture.dot', resource]]),
    properties: { texture: { resourceId: 'texture.dot' }, position: [3, 4], scale: [2, 2], visible: true },
  });
  assert.equal(node instanceof t.Sprite2DNode, true);
  assert.deepEqual(node.position, { x: 3, y: 4 });
  assert.deepEqual(node.scale, { x: 2, y: 2 });
});
