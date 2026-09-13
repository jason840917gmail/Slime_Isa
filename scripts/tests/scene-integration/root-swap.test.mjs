import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

test('host shutdown is idempotent and releases manual physics ownership after tree cleanup', () => {
  const calls = [];
  const tree = new t.SceneTree(); tree.setRoot(new t.Node({ runtimeId: 'host/root', name: 'Root' }));
  const backend = {
    startManualStepping: () => calls.push('start'), advancePhysicsAnimations() {}, synchronizePhysicsToBackend() {}, stepPhysics() {},
    readAuthoritativePhysicsState() {}, collectManagedContacts() {}, resolveManagedAttacks() {}, runPostPhysics() {}, advanceRenderAnimations() {},
    synchronizePresentation() {}, clearHeldInputTransitions() {}, shutdown: () => calls.push('shutdown'),
  };
  const legacy = new t.LegacyWorldAdapter({ dispose: () => calls.push('legacy:dispose') });
  const host = new t.PhaserSceneTreeHost({ tree, backend, legacy });
  host.shutdown(); host.shutdown();
  assert.deepEqual(calls, ['start', 'legacy:dispose', 'shutdown']);
  assert.equal(tree.indexedNodeCount, 0);
  assert.throws(() => host.advanceFrame(0), /shut down/);
});

test('presentation leases follow successful and rolled-back root swaps', () => {
  const state = { active: 0, created: 0 };
  const spriteFactory = () => {
    state.active += 1; state.created += 1;
    const sprite = { destroy() { if (this.active) { this.active = false; state.active -= 1; } }, active: true };
    for (const method of ['setName', 'setOrigin', 'setAlpha', 'setFlip', 'setTint', 'setPosition', 'setRotation', 'setScale', 'setVisible', 'setDepth']) sprite[method] = () => sprite;
    return sprite;
  };
  const scene = {
    add: { sprite: spriteFactory },
    scale: { width: 320, height: 180 }, cameras: { add() {}, remove() {} },
    physics: { disableUpdate() {}, enableUpdate() {}, world: { step() {} } },
  };
  const resources = new Map([['texture.dot', { version: 1, resourceId: 'texture.dot', kind: 'texture', assetId: 'dot' }]]);
  const context = new t.PhaserNodeContext(scene, resources);
  const make = (id) => new t.Sprite2DNode({ runtimeId: `swap/${id}`, name: id, context, texture: 'texture.dot' });
  const first = make('First'); const second = make('Second');
  const tree = new t.SceneTree(); tree.setRoot(first);
  assert.equal(state.active, 1);
  assert.equal(tree.replaceRoot(second), true);
  assert.equal(state.active, 1);
  assert.equal(first.is_freed(), true);
  class FailingSprite extends t.Sprite2DNode { _ready() { throw new Error('ready failed'); } }
  const failing = new FailingSprite({ runtimeId: 'swap/failing', name: 'Failing', context, texture: 'texture.dot' });
  assert.equal(tree.replaceRoot(failing), false);
  assert.equal(tree.root, second);
  assert.equal(state.active, 1);
  assert.equal(context.managedPresentationCount, 1);
  assert.equal(state.created, 4);
});

test('shutdown attempts legacy and backend cleanup even when one disposer fails', () => {
  const calls = [];
  const tree = new t.SceneTree(); tree.setRoot(new t.Node({ runtimeId: 'cleanup/root', name: 'Root' }));
  const backend = {
    startManualStepping() {}, advancePhysicsAnimations() {}, synchronizePhysicsToBackend() {}, stepPhysics() {}, readAuthoritativePhysicsState() {},
    collectManagedContacts() {}, resolveManagedAttacks() {}, runPostPhysics() {}, advanceRenderAnimations() {}, synchronizePresentation() {}, clearHeldInputTransitions() {},
    shutdown: () => calls.push('backend'),
  };
  const legacy = new t.LegacyWorldAdapter({ dispose: () => { calls.push('legacy'); throw new Error('legacy cleanup failed'); } });
  const host = new t.PhaserSceneTreeHost({ tree, backend, legacy });
  assert.throws(() => host.shutdown(), AggregateError);
  assert.deepEqual(calls, ['legacy', 'backend']);
});
