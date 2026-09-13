import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { DisposableScope, Node, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

test('signals dispatch over a snapshot and skip connections removed before invocation', () => {
  const calls = [];
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const source = new Node({ runtimeId: 'world/source', name: 'Source' });
  const first = new Node({ runtimeId: 'world/first', name: 'First' });
  const second = new Node({ runtimeId: 'world/second', name: 'Second' });
  const fired = source.createSignal('fired');
  let secondHandle;
  first.registerSignalHandler('accept', () => { calls.push('first'); secondHandle.disconnect(); });
  second.registerSignalHandler('accept', () => calls.push('second'));
  fired.connect(first, 'accept');
  secondHandle = fired.connect(second, 'accept');
  root.add_child(source); root.add_child(first); root.add_child(second);
  const tree = new SceneTree(); tree.setRoot(root);
  fired.emit({ amount: 1 });
  assert.deepEqual(calls, ['first']);
  assert.equal(secondHandle.connected, false);
});

test('signal-time free is deferred, later live endpoints still run, and free disconnects permanently', () => {
  const calls = [];
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const source = new Node({ runtimeId: 'world/source', name: 'Source' });
  const first = new Node({ runtimeId: 'world/first', name: 'First' });
  const second = new Node({ runtimeId: 'world/second', name: 'Second' });
  const fired = source.createSignal('fired');
  first.registerSignalHandler('accept', () => { calls.push('first'); first.queue_free(); });
  second.registerSignalHandler('accept', () => calls.push('second'));
  const firstHandle = fired.connect(first, 'accept');
  fired.connect(second, 'accept');
  root.add_child(source); root.add_child(first); root.add_child(second);
  const tree = new SceneTree(); tree.setRoot(root);
  fired.emit(undefined);
  assert.deepEqual(calls, ['first', 'second']);
  assert.equal(first.lifecycleState, 'freed');
  assert.equal(firstHandle.connected, false);
  calls.length = 0; fired.emit(undefined);
  assert.deepEqual(calls, ['second']);
});

test('entry leases are reacquired on re-entry while authored signal connections persist once', () => {
  let activeLeases = 0;
  let readyCalls = 0;
  let deliveries = 0;
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const target = new Node({ runtimeId: 'world/target', name: 'Target' });
  target.registerSignalHandler('accept', () => { deliveries += 1; });
  class Source extends Node {
    constructor() { super({ runtimeId: 'world/source', name: 'Source' }); this.fired = this.createSignal('fired'); }
    _enter_tree() { activeLeases += 1; this.entryDisposables.add(() => { activeLeases -= 1; }); }
    _ready() { readyCalls += 1; this.fired.connect(target, 'accept'); }
  }
  const source = new Source();
  root.add_child(target); root.add_child(source);
  const tree = new SceneTree(); tree.setRoot(root);
  source.fired.emit(undefined);
  assert.deepEqual({ activeLeases, readyCalls, deliveries }, { activeLeases: 1, readyCalls: 1, deliveries: 1 });
  root.remove_child(source); tree.flushMutations();
  assert.equal(activeLeases, 0);
  source.fired.emit(undefined);
  assert.equal(deliveries, 1);
  root.add_child(source); tree.flushMutations();
  source.fired.emit(undefined);
  assert.deepEqual({ activeLeases, readyCalls, deliveries }, { activeLeases: 1, readyCalls: 1, deliveries: 2 });
});

test('disposable scopes run every cleanup in reverse order despite failures', () => {
  const trace = [];
  const errors = [];
  const scope = new DisposableScope();
  scope.add(() => trace.push('first'));
  scope.add(() => { trace.push('second'); throw new Error('second failed'); });
  scope.add(() => trace.push('third'));
  scope.disposeSafely((error) => errors.push(error));
  scope.disposeSafely(() => assert.fail('dispose must be idempotent'));
  assert.deepEqual(trace, ['third', 'second', 'first']);
  assert.equal(errors.length, 1);
});

test('duplicate preserves only internal authored signal connections', () => {
  const calls = [];
  class Receiver extends Node {
    constructor(options) { super(options); this.registerSignalHandler('accept', () => calls.push(this.runtimeId)); }
    _duplicateSelf(runtimeId) { return new Receiver({ runtimeId, name: this.name }); }
  }
  class Source extends Node {
    constructor(options) { super(options); this.fired = this.createSignal('fired'); }
    _duplicateSelf(runtimeId) { return new Source({ runtimeId, name: this.name }); }
  }
  const root = new Node({ runtimeId: 'source/root', name: 'Root' });
  const source = new Source({ runtimeId: 'source/source', name: 'Source' });
  const internal = new Receiver({ runtimeId: 'source/internal', name: 'Internal' });
  const external = new Receiver({ runtimeId: 'source/external', name: 'External' });
  source.fired.connect(internal, 'accept');
  source.fired.connect(external, 'accept');
  root.add_child(source); root.add_child(internal);
  const copy = root.duplicate();
  const copiedSource = copy.get_node('Source');
  const tree = new SceneTree(); tree.setRoot(copy);
  copiedSource.getSignal('fired').emit(undefined);
  assert.equal(calls.length, 1);
  assert.equal(calls[0], copy.get_node('Internal').runtimeId);
});
