import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

class HostNode extends t.Node {
  constructor(trace) { super({ runtimeId: 'host/root', name: 'Root' }); this.trace = trace; this.set_process(true); this.set_physics_process(true); this.set_process_input(true); }
  _input(event) { this.trace.push(`input:${event.payload}`); }
  _physics_process() { this.trace.push('tree:physics'); }
  _process() { this.trace.push('tree:render'); }
}

function backend(trace, overrides = {}) {
  return {
    startManualStepping: () => trace.push('backend:start'),
    advancePhysicsAnimations: () => trace.push('animation:physics'),
    synchronizePhysicsToBackend: () => trace.push('sync:physics'),
    stepPhysics: () => trace.push('backend:step'),
    readAuthoritativePhysicsState: () => trace.push('sync:readback'),
    collectManagedContacts: () => trace.push('contacts'),
    resolveManagedAttacks: () => trace.push('attacks'),
    runPostPhysics: () => trace.push('post:managed'),
    advanceRenderAnimations: () => trace.push('animation:render'),
    synchronizePresentation: () => trace.push('sync:presentation'),
    clearHeldInputTransitions: () => trace.push('input:clear'),
    shutdown: () => trace.push('backend:shutdown'),
    ...overrides,
  };
}

test('the host drains timestamped input and runs the normative fixed/render order', () => {
  const trace = [];
  const tree = new t.SceneTree(); tree.setRoot(new HostNode(trace));
  const lifecycle = {
    afterUnhandledInput: (event) => trace.push(`lifecycle:input:${event.payload}`),
    beforeFixedStep: () => trace.push('lifecycle:before'), afterFixedStep: () => trace.push('lifecycle:after'), beforePresentation: () => trace.push('lifecycle:render'),
  };
  const host = new t.PhaserSceneTreeHost({ tree, backend: backend(trace), lifecycle });
  trace.length = 0;
  host.enqueueInput({ handled: false, timestamp: 20, payload: 'late' });
  host.enqueueInput({ handled: false, timestamp: 10, payload: 'early' });
  assert.equal(host.advanceFrame(1 / 60), 1);
  assert.deepEqual(trace, [
    'input:early', 'lifecycle:input:early', 'input:late', 'lifecycle:input:late',
    'lifecycle:before', 'animation:physics', 'tree:physics', 'sync:physics', 'backend:step', 'sync:readback',
    'contacts', 'attacks', 'post:managed', 'lifecycle:after',
    'lifecycle:render', 'animation:render', 'tree:render', 'sync:presentation',
  ]);
});

test('catch-up is capped at five, excess time is dropped, and resume clears stale input transitions', () => {
  const trace = []; const diagnostics = [];
  const tree = new t.SceneTree(); tree.setRoot(new HostNode(trace));
  const host = new t.PhaserSceneTreeHost({ tree, backend: backend(trace), diagnosticSink: (entry) => diagnostics.push(entry) });
  trace.length = 0;
  assert.equal(host.advanceFrame(10 / 60), 5);
  assert.equal(trace.filter((entry) => entry === 'backend:step').length, 5);
  assert.equal(host.accumulatedSeconds, 0);
  assert.match(diagnostics[0].message, /Dropped/);
  host.setPaused(true); host.advanceFrame(1); host.setPaused(false);
  assert.equal(trace.at(-1), 'input:clear');
  assert.equal(host.accumulatedSeconds, 0);
});

test('a backend invariant failure pauses the tree and is surfaced', () => {
  const trace = []; const diagnostics = [];
  const tree = new t.SceneTree(); tree.setRoot(new HostNode(trace));
  const host = new t.PhaserSceneTreeHost({ tree, backend: backend(trace, { stepPhysics: () => { throw new Error('backend exploded'); } }), diagnosticSink: (entry) => diagnostics.push(entry) });
  assert.throws(() => host.advanceFrame(1 / 60), /backend exploded/);
  assert.equal(tree.paused, true);
  assert.equal(diagnostics.at(-1).phase, 'frame');
});

test('input priority wins before stable tree order and handled input does not reach lifecycle fallback', () => {
  const trace = [];
  class InputNode extends t.Node {
    constructor(id, priority, handle = false) { super({ runtimeId: `input/${id}`, name: id }); this.set_process_input(true); this.set_input_priority(priority); this.handle = handle; }
    _input(event) { trace.push(this.name); if (this.handle) event.handled = true; }
  }
  const root = new t.Node({ runtimeId: 'input/root', name: 'Root' });
  root.add_child(new InputNode('Low', 0)); root.add_child(new InputNode('HighFirst', 10, true)); root.add_child(new InputNode('HighSecond', 10));
  const tree = new t.SceneTree(); tree.setRoot(root);
  const host = new t.PhaserSceneTreeHost({ tree, backend: backend([]), lifecycle: { afterUnhandledInput: () => trace.push('fallback') } });
  host.enqueueInput({ handled: false }); host.advanceFrame(0);
  assert.deepEqual(trace, ['HighFirst', 'HighSecond', 'Low']);
});
