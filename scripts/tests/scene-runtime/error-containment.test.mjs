import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { Node, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

test('failed entry rolls back indexes and exhausts leases acquired before failure', () => {
  let released = 0;
  class FailingNode extends Node {
    _enter_tree() { this.entryDisposables.add(() => { released += 1; }); throw new Error('enter exploded'); }
  }
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  root.add_child(new FailingNode({ runtimeId: 'world/failing', name: 'Failing' }));
  const tree = new SceneTree({ sceneId: 'fixture.failure' });
  tree.setRoot(root);
  assert.equal(tree.root, undefined);
  assert.equal(tree.indexedNodeCount, 0);
  assert.equal(tree.indexedGroupCount, 0);
  assert.equal(released, 1);
  assert.equal(tree.diagnostics.some((entry) => entry.phase === 'enter' && entry.nodePath === '/Root/Failing'), true);
});

test('exit and disposer failures are diagnosed while all cleanup completes', () => {
  const cleanup = [];
  class MessyNode extends Node {
    _enter_tree() {
      this.entryDisposables.add(() => cleanup.push('first'));
      this.entryDisposables.add(() => { cleanup.push('second'); throw new Error('dispose exploded'); });
      this.entryDisposables.add(() => cleanup.push('third'));
    }
    _exit_tree() { throw new Error('exit exploded'); }
  }
  const root = new MessyNode({ runtimeId: 'world/root', name: 'Root' });
  const tree = new SceneTree({ sceneId: 'fixture.cleanup' }); tree.setRoot(root); tree.shutdown();
  assert.deepEqual(cleanup, ['third', 'second', 'first']);
  assert.equal(tree.indexedNodeCount, 0);
  assert.equal(root.lifecycleState, 'freed');
  assert.equal(tree.diagnostics.some((entry) => entry.phase === 'exit' && /exit exploded/.test(entry.message)), true);
  assert.equal(tree.diagnostics.some((entry) => entry.phase === 'dispose' && /dispose exploded/.test(entry.message)), true);
});

test('process failures disable only the failing callback and retain contextual diagnostics', () => {
  let calls = 0;
  class FailingProcess extends Node {
    constructor() { super({ runtimeId: 'world/failing', name: 'Failing' }); this.set_process(true); }
    _process() { calls += 1; throw new Error('tick exploded'); }
  }
  const root = new FailingProcess();
  const tree = new SceneTree({ sceneId: 'fixture.process' }); tree.setRoot(root);
  tree.process(0.016); tree.process(0.016);
  assert.equal(calls, 1);
  assert.equal(tree.diagnostics[0].sceneId, 'fixture.process');
  assert.equal(tree.diagnostics[0].runtimeId, 'world/failing');
  assert.equal(tree.diagnostics[0].phase, 'process');
});

test('input consumption suppresses unhandled callbacks and input-time free flushes afterward', () => {
  const trace = [];
  class InputNode extends Node {
    constructor(options, consume = false, free = false) { super(options); this.consume = consume; this.free = free; this.set_process_input(true); this.set_process_unhandled_input(true); }
    _input(event) { trace.push(`input:${this.name}`); if (this.consume) event.handled = true; if (this.free) this.queue_free(); }
    _unhandled_input() { trace.push(`unhandled:${this.name}`); }
  }
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const first = new InputNode({ runtimeId: 'world/first', name: 'First' }, false, true);
  const second = new InputNode({ runtimeId: 'world/second', name: 'Second' }, true);
  root.add_child(first); root.add_child(second);
  const tree = new SceneTree(); tree.setRoot(root);
  tree.dispatchInput({ handled: false, type: 'test' });
  assert.deepEqual(trace, ['input:First', 'input:Second']);
  assert.equal(first.lifecycleState, 'freed');
  assert.equal(second.lifecycleState, 'ready');
});
