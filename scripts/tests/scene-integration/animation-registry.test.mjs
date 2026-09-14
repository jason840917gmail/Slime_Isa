import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

test('Phaser registry builds AnimationPlayer from a reusable library and a named binding service', () => {
  const scene = { physics: { systems: {}, disableUpdate() {}, enableUpdate() {}, world: { step() {} }, add: { collider() { return { destroy() {} }; } } } };
  const library = {
    version: 1, resourceId: 'animation.fixture', kind: 'animation-library',
    animations: { drift: { durationSeconds: 2, framesPerSecond: 1, loop: true, tracks: [{ binding: 'visual', property: 'rotation', keys: [{ at: 0, value: 0 }, { at: 1, value: 4 }] }] } },
  };
  const resources = new Map([['animation.fixture', library]]);
  const context = new t.PhaserNodeContext(scene, resources);
  const target = new t.Node2D({ runtimeId: 'animation-registry/target', name: 'Target', rotation: 2 });
  const descriptor = { key: 'rotation', label: 'Rotation', value: { kind: 'number' }, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains: ['render'] }, overridable: true };
  const registry = t.createPhaserNodeRegistry(context, {
    resolveAnimationBinding: (_player, binding, property) => {
      assert.equal(binding, 'visual');
      return new t.AnimationBinding(target, property, descriptor);
    },
  });
  const player = registry.construct({
    runtimeId: 'animation-registry/player', name: 'Player', type: 'AnimationPlayer', resources,
    properties: { library: { resourceId: 'animation.fixture' }, domain: 'render' },
  });
  assert.equal(player instanceof t.AnimationPlayerNode, true);
  const root = new t.Node({ runtimeId: 'animation-registry/root', name: 'Root' });
  root.add_child(target); root.add_child(player);
  const tree = new t.SceneTree(); tree.setRoot(root);
  player.play('drift');
  context.advanceRenderAnimations(1);
  assert.equal(target.rotation, 4);
  tree.shutdown(); context.shutdown();
  assert.equal(target.rotation, 2);
});
