import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');
const descriptors = await loadTypescriptModule('src/game/content/scenes/propertyDescriptors.ts');
const depth = await loadTypescriptModule('src/game/presentation/WorldDepth.ts');

function fakeScene() {
  const sprites = [];
  const chain = (target) => {
    for (const method of ['setName', 'setOrigin', 'setAlpha', 'setTint', 'setPosition', 'setRotation', 'setScale', 'setVisible', 'setDepth']) {
      target[method] = (...args) => { target[method.slice(3).toLowerCase()] = args.length === 1 ? args[0] : args; return target; };
    }
    target.setFlip = (x, y) => { target.flipX = x; target.flipY = y; return target; };
    target.setFrame = (frame) => { target.frame.name = frame; return target; };
    return target;
  };
  const scene = {
    add: { sprite: (_x, _y, texture, frame) => { const sprite = chain({ texture, frame: { name: frame, realHeight: 32 }, active: true, destroy() { this.active = false; } }); sprites.push(sprite); return sprite; } },
    physics: { systems: {}, disableUpdate() {}, enableUpdate() {}, world: { step() {} } },
  };
  return { scene, sprites };
}

function fixture() {
  const { scene, sprites } = fakeScene();
  const resources = new Map([['texture.dot', { version: 1, resourceId: 'texture.dot', kind: 'texture', assetId: 'dot' }]]);
  const context = new t.PhaserNodeContext(scene, resources, (assetId) => `runtime-${assetId}`);
  return { context, sprites };
}

test('Sprite2D flipX/flipY are animatable step properties and plain settable node properties', () => {
  const registry = descriptors.createCoreDescriptorRegistry();
  const properties = new Map(descriptors.propertiesForNode('Sprite2D', undefined, registry).map((property) => [property.key, property]));
  for (const key of ['flipX', 'flipY', 'depthOffset']) {
    assert.equal(properties.get(key)?.animation?.interpolation, 'step', `${key} is a step-animated property`);
  }
  assert.ok(properties.get('depthMode').value.values.includes('relative'));

  const { context, sprites } = fixture();
  const root = new t.Node2D({ runtimeId: 'fixture/root', name: 'Root' });
  const sprite = new t.Sprite2DNode({ runtimeId: 'fixture/sprite', name: 'Sprite', context, texture: 'texture.dot' });
  root.add_child(sprite);
  const tree = new t.SceneTree(); tree.setRoot(root);
  context.synchronizePresentation(1);
  assert.equal(sprites[0].flipX, false);

  sprite.flipX = true;
  assert.equal(sprite.flipX, true);
  assert.equal(sprites[0].flipX, true);

  const binding = new t.AnimationBinding(sprite, 'flipY', properties.get('flipY'));
  const owner = {};
  binding.acquire(owner, 'physics');
  binding.apply(1, [{ at: 0, value: false }, { at: 1, value: true }]);
  assert.equal(sprite.flipY, true);
  assert.equal(sprites[0].flipY, true);
  binding.release(owner, true);
  assert.equal(sprite.flipY, false, 'releasing the animation restores the authored flip');
  tree.shutdown();
});

test('relative depth follows the nearest depth-source ancestor so attachments draw with their wielder', () => {
  const { context, sprites } = fixture();
  const world = new t.Node2D({ runtimeId: 'fixture/world', name: 'World' });
  const body = new t.Node2D({ runtimeId: 'fixture/body', name: 'Body', position: { x: 10, y: 100 }, depthAnchor: { x: 0, y: 27 } });
  const visual = new t.Sprite2DNode({ runtimeId: 'fixture/visual', name: 'Visual', context, texture: 'texture.dot', depthMode: 'relative' });
  const weaponMount = new t.Node2D({ runtimeId: 'fixture/weapon', name: 'Weapon' });
  const blade = new t.Sprite2DNode({ runtimeId: 'fixture/blade', name: 'Blade', context, texture: 'texture.dot', position: { x: 0, y: -60 }, depthMode: 'relative', depthOffset: 0.011 });
  const slash = new t.Sprite2DNode({ runtimeId: 'fixture/slash', name: 'Slash', context, texture: 'texture.dot', position: { x: 0, y: 60 }, depthMode: 'relative', depthOffset: 0.01 });
  world.add_child(body); body.add_child(visual); body.add_child(weaponMount); weaponMount.add_child(blade); weaponMount.add_child(slash);
  const tree = new t.SceneTree(); tree.setRoot(world);
  context.synchronizePresentation(1);

  const feet = depth.resolveWorldDepth(127, { stableId: 'fixture/body' }).depth;
  assert.equal(visual.depthSortY, 127, 'the character sorts by its feet, not its sprite origin');
  assert.equal(sprites[0].depth, feet);
  assert.equal(sprites[1].depth, feet + 0.011, 'layer order is preserved above the wielder regardless of each sprite Y');
  assert.equal(sprites[2].depth, feet + 0.01);

  body.position = { x: 10, y: 300 };
  context.synchronizePresentation(1);
  assert.ok(Math.abs(sprites[1].depth - sprites[0].depth - 0.011) < 1e-5);

  body.depthOverride = 42;
  blade.depthOffset = 0.5;
  context.synchronizePresentation(1);
  assert.equal(sprites[0].depth, 42, 'an explicit base depth replaces the world-sorted anchor depth');
  assert.equal(sprites[1].depth, 42.5);
  tree.shutdown();
});
