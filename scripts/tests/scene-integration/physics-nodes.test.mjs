import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

function fakePhaser() {
  const state = { bodies: [], colliders: [], destroyed: 0 };
  const updatePosition = (body) => { body.position = { x: body.center.x - body.width / 2, y: body.center.y - body.height / 2 }; };
  const scene = {
    add: {
      zone(x, y, width, height) {
        const zone = {
          x, y, width, height, active: true, body: null,
          setName(name) { this.name = name; return this; },
          setVisible(visible) { this.visible = visible; return this; },
          setPosition(nextX, nextY) { this.x = nextX; this.y = nextY; return this; },
          setSize(nextWidth, nextHeight) { this.width = nextWidth; this.height = nextHeight; return this; },
          destroy() { if (!this.active) return; this.active = false; if (this.body) state.bodies.splice(state.bodies.indexOf(this.body), 1); state.destroyed += 1; },
        };
        return zone;
      },
    },
    physics: {
      systems: {}, disableUpdate() {}, enableUpdate() {},
      add: {
        existing(zone, isStatic) {
          const body = {
            gameObject: zone, isStatic, enable: true, width: zone.width, height: zone.height,
            center: { x: zone.x, y: zone.y }, position: { x: zone.x - zone.width / 2, y: zone.y - zone.height / 2 },
            velocity: { x: 0, y: 0 }, touching: { left: false, right: false, up: false, down: false }, checkCollision: { none: false },
            setSize(width, height) { this.width = width; this.height = height; updatePosition(this); return this; },
            setCircle(radius) { this.width = radius * 2; this.height = radius * 2; this.isCircle = true; updatePosition(this); return this; },
            reset(x, y) { this.center = { x, y }; updatePosition(this); return this; },
            updateFromGameObject() { this.center = { x: zone.x, y: zone.y }; updatePosition(this); return this; },
            setVelocity(x, y) { this.velocity = { x, y }; return this; },
          };
          zone.body = body; state.bodies.push(body);
        },
        collider(first, second, onCollide, process) {
          const collider = { first: first.body, second: second.body, onCollide, process, active: true, destroy() { this.active = false; } };
          state.colliders.push(collider); return collider;
        },
      },
      world: {
        step(delta) {
          for (const body of state.bodies) {
            body.touching = { left: false, right: false, up: false, down: false };
            if (!body.isStatic && body.enable) { body.center.x += body.velocity.x * delta; body.center.y += body.velocity.y * delta; updatePosition(body); }
          }
          for (const collider of state.colliders) {
            if (!collider.active || !collider.process()) continue;
            const a = collider.first; const b = collider.second;
            if (!a.enable || !b.enable || a.position.x >= b.position.x + b.width || a.position.x + a.width <= b.position.x || a.position.y >= b.position.y + b.height || a.position.y + a.height <= b.position.y) continue;
            const dynamic = a.isStatic ? b : a; const fixed = a.isStatic ? a : b;
            if (dynamic.velocity.x >= 0) { dynamic.center.x = fixed.position.x - dynamic.width / 2; dynamic.touching.right = true; }
            else { dynamic.center.x = fixed.position.x + fixed.width + dynamic.width / 2; dynamic.touching.left = true; }
            dynamic.velocity.x = 0; updatePosition(dynamic); collider.onCollide();
          }
        },
        overlapRect(x, y, width, height) {
          return state.bodies.filter((body) => body.enable && body.position.x <= x + width && body.position.x + body.width >= x && body.position.y <= y + height && body.position.y + body.height >= y);
        },
      },
    },
  };
  return { scene, state };
}

const resource = (id, value) => [id, { version: 1, resourceId: id, kind: 'collision-shape', value }];
const shapeNode = (context, id, resourceId, options = {}) => new t.CollisionShape2DNode({ runtimeId: id, name: id.split('/').at(-1), context, shape: resourceId, ...options });

test('PhysicsBody2D remains an abstract registered inspection type', () => {
  const registry = t.createCoreNodeTypeRegistry();
  assert.equal(registry.has('PhysicsBody2D'), true);
  assert.throws(() => registry.construct({ runtimeId: 'abstract/body', name: 'Body', type: 'PhysicsBody2D', properties: {}, resources: new Map() }), /abstract/);
});

test('managed bodies block once, read authoritative state, expose prior contacts, teleport, and tear down', () => {
  const { scene, state } = fakePhaser();
  const context = new t.PhaserNodeContext(scene, new Map([resource('rect10', { shape: 'rectangle', width: 10, height: 10 })]));
  const root = new t.Node2D({ runtimeId: 'physics/root', name: 'Root' });
  const character = new t.CharacterBody2DNode({ runtimeId: 'physics/character', name: 'Character', context, position: { x: 0, y: 0 }, velocity: { x: 60, y: 0 }, collisionLayer: 1, collisionMask: 2 });
  character.add_child(shapeNode(context, 'physics/character-shape', 'rect10'));
  const wall = new t.StaticBody2DNode({ runtimeId: 'physics/wall', name: 'Wall', context, position: { x: 20, y: 0 }, collisionLayer: 2, collisionMask: 1 });
  wall.add_child(shapeNode(context, 'physics/wall-shape', 'rect10'));
  root.add_child(character); root.add_child(wall);
  const tree = new t.SceneTree(); tree.setRoot(root);
  const host = new t.PhaserSceneTreeHost({ tree, backend: context });

  for (let step = 0; step < 30 && character.velocity.x !== 0; step += 1) host.advanceFrame(1 / 60);
  assert.equal(character.position.x, 10);
  assert.equal(character.velocity.x, 0);
  assert.equal(character.blockingContacts.length, 1);
  assert.equal(character.blockingContacts[0].colliderId, 'physics/wall');
  assert.equal(context.managedBlockingColliderCount, 1);

  character.velocity = { x: 0, y: 0 };
  character.queue_teleport({ x: -20, y: 4 });
  host.advanceFrame(1 / 60);
  assert.deepEqual(character.position, { x: -20, y: 4 });
  host.shutdown();
  assert.equal(state.bodies.length, 0);
  assert.equal(context.managedBlockingColliderCount, 0);
  assert.equal(state.destroyed, 2);
});

test('compound Area2D contacts follow post-step body motion and reconcile disabled/free exits', () => {
  const { scene } = fakePhaser();
  const resources = new Map([
    resource('rect8', { shape: 'rectangle', width: 8, height: 8 }),
    resource('circle6', { shape: 'circle', radius: 6 }),
    resource('ellipse', { shape: 'ellipse', radiusX: 8, radiusY: 3 }),
  ]);
  const context = new t.PhaserNodeContext(scene, resources);
  const root = new t.Node2D({ runtimeId: 'area/root', name: 'Root' });
  const character = new t.CharacterBody2DNode({ runtimeId: 'area/character', name: 'Character', context, position: { x: 0, y: 0 }, velocity: { x: 60, y: 0 }, collisionLayer: 2, collisionMask: 0 });
  character.add_child(shapeNode(context, 'area/character-shape', 'rect8'));
  const area = new t.Area2DNode({ runtimeId: 'area/sensor', name: 'Sensor', context, collisionMask: 2 });
  const near = shapeNode(context, 'area/sensor-near', 'circle6');
  const far = shapeNode(context, 'area/sensor-far', 'ellipse', { position: { x: 30, y: 0 } });
  area.add_child(near); area.add_child(far);
  root.add_child(character); root.add_child(area);
  const tree = new t.SceneTree(); tree.setRoot(root);
  const host = new t.PhaserSceneTreeHost({ tree, backend: context });
  host.advanceFrame(1 / 60);
  assert.equal(area.currentContacts.length, 1);
  assert.equal(area.currentContacts[0].otherId, 'area/character');
  near.disabled = true;
  assert.equal(area.currentContacts.length, 0, 'disabled shape invalidates live queries before reconciliation');
  host.advanceFrame(1 / 60);
  near.disabled = false;
  host.advanceFrame(1 / 60);
  assert.equal(area.currentContacts.length, 1);
  character.queue_free(); tree.flushMutations();
  assert.equal(area.currentContacts.length, 0);
  host.advanceFrame(1 / 60);
  host.shutdown();
});

test('native circle bodies use their authored radius for blocking', () => {
  const { scene } = fakePhaser();
  const context = new t.PhaserNodeContext(scene, new Map([resource('circle5', { shape: 'circle', radius: 5 })]));
  const root = new t.Node2D({ runtimeId: 'circle/root', name: 'Root' });
  const character = new t.CharacterBody2DNode({ runtimeId: 'circle/character', name: 'Character', context, velocity: { x: 60, y: 0 }, collisionLayer: 1, collisionMask: 2 });
  character.add_child(shapeNode(context, 'circle/character-shape', 'circle5'));
  const wall = new t.StaticBody2DNode({ runtimeId: 'circle/wall', name: 'Wall', context, position: { x: 18, y: 0 }, collisionLayer: 2, collisionMask: 1 });
  wall.add_child(shapeNode(context, 'circle/wall-shape', 'circle5'));
  root.add_child(character); root.add_child(wall);
  const tree = new t.SceneTree(); tree.setRoot(root);
  const host = new t.PhaserSceneTreeHost({ tree, backend: context });
  for (let step = 0; step < 20 && character.velocity.x !== 0; step += 1) host.advanceFrame(1 / 60);
  assert.equal(character.position.x, 8);
  assert.equal(character.blockingContacts[0].colliderId, 'circle/wall');
  wall.collisionMask = 0;
  character.queue_teleport({ x: 0, y: 0 });
  character.velocity = { x: 60, y: 0 };
  for (let step = 0; step < 20; step += 1) host.advanceFrame(1 / 60);
  assert.equal(character.position.x, 20, 'blocking requires both body masks to accept the other layer');
  host.shutdown();
});

test('elliptical blocking bodies use their conservative authored bounds in Arcade', () => {
  const { scene } = fakePhaser();
  const context = new t.PhaserNodeContext(scene, new Map([resource('ellipse', { shape: 'ellipse', radiusX: 8, radiusY: 3 })]));
  const body = new t.CharacterBody2DNode({ runtimeId: 'ellipse/body', name: 'EllipseBody', context });
  body.add_child(shapeNode(context, 'ellipse/shape', 'ellipse'));
  const tree = new t.SceneTree();
  tree.setRoot(body);
  assert.equal(body.physicsObject.body.width, 16);
  assert.equal(body.physicsObject.body.height, 6);
  tree.shutdown();
  context.shutdown();
});

test('blocking nodes reject unsupported geometry, multiple enabled shapes, rotation, and non-uniform circles', () => {
  const invalidCases = [
    { resource: { shape: 'rectangle', width: 5, height: 5 }, extraShape: true, body: {} },
    { resource: { shape: 'rectangle', width: 5, height: 5 }, extraShape: false, body: { rotation: 0.2 } },
    { resource: { shape: 'circle', radius: 5 }, extraShape: false, body: { scale: { x: 2, y: 1 } } },
  ];
  for (const [index, invalid] of invalidCases.entries()) {
    const { scene } = fakePhaser();
    const context = new t.PhaserNodeContext(scene, new Map([resource(`shape${index}`, invalid.resource)]));
    const body = new t.CharacterBody2DNode({ runtimeId: `invalid/body${index}`, name: `Body${index}`, context, ...invalid.body });
    body.add_child(shapeNode(context, `invalid/shape${index}`, `shape${index}`));
    if (invalid.extraShape) body.add_child(shapeNode(context, `invalid/extra${index}`, `shape${index}`));
    const diagnostics = [];
    const tree = new t.SceneTree({ diagnosticSink: (diagnostic) => diagnostics.push(diagnostic) });
    tree.setRoot(body);
    assert.equal(tree.root, undefined, `invalid case ${index} must roll back insertion`);
    assert.match(diagnostics.map((entry) => entry.message).join('\n'), /only supports|exactly one|rotated|uniform/, `invalid case ${index}`);
    context.shutdown();
  }
});
