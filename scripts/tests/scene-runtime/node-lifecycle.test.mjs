import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { Node, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

class TraceNode extends Node {
  constructor(name, trace) { super({ runtimeId: `test/${name.toLowerCase()}`, name }); this.trace = trace; }
  _enter_tree() { this.trace.push(`enter:${this.name}`); }
  _ready() { this.trace.push(`ready:${this.name}`); }
  _process() { this.trace.push(`process:${this.name}`); }
  _physics_process() { this.trace.push(`physics:${this.name}`); }
  _exit_tree() { this.trace.push(`exit:${this.name}`); }
}

test('entry is parent-first, ready is child-first, and exit is child-first', () => {
  const trace = [];
  const root = new TraceNode('Root', trace);
  const a = new TraceNode('A', trace);
  const grandchild = new TraceNode('Grandchild', trace);
  const b = new TraceNode('B', trace);
  root.add_child(a); a.add_child(grandchild); root.add_child(b);
  const tree = new SceneTree();
  tree.setRoot(root);
  assert.deepEqual(trace, ['enter:Root', 'enter:A', 'enter:Grandchild', 'enter:B', 'ready:Grandchild', 'ready:A', 'ready:B', 'ready:Root']);
  trace.length = 0;
  root.remove_child(a); tree.flushMutations();
  assert.deepEqual(trace, ['exit:Grandchild', 'exit:A']);
  assert.equal(a.lifecycleState, 'detached');
  trace.length = 0;
  root.add_child(a); tree.flushMutations();
  assert.deepEqual(trace, ['enter:A', 'enter:Grandchild']);
  assert.equal(a.was_ready(), true);
  tree.shutdown();
  assert.equal(tree.indexedNodeCount, 0);
});

test('process lists use stable tree order and honor pause policy', () => {
  const trace = [];
  const root = new TraceNode('Root', trace);
  const a = new TraceNode('A', trace);
  const b = new TraceNode('B', trace);
  root.add_child(a); root.add_child(b);
  for (const node of [root, a, b]) { node.set_process(true); node.set_physics_process(true); }
  b.set_process_when_paused(true);
  const tree = new SceneTree(); tree.setRoot(root); trace.length = 0;
  tree.process(0.016); tree.physicsProcess(0.02);
  assert.deepEqual(trace, ['process:Root', 'process:A', 'process:B', 'physics:Root', 'physics:A', 'physics:B']);
  trace.length = 0; tree.paused = true; tree.process(0.016); tree.physicsProcess(0.02);
  assert.deepEqual(trace, ['process:B', 'physics:B']);
});

test('group membership persists through detach and follows current tree order', () => {
  const trace = [];
  const root = new TraceNode('Root', trace);
  const a = new TraceNode('A', trace);
  const b = new TraceNode('B', trace);
  a.add_to_group('actors'); b.add_to_group('actors');
  root.add_child(a); root.add_child(b);
  const tree = new SceneTree(); tree.setRoot(root);
  assert.deepEqual(tree.getNodesInGroup('actors'), [a, b]);
  root.remove_child(a); tree.flushMutations();
  assert.deepEqual(tree.getNodesInGroup('actors'), [b]);
  root.add_child(a); tree.flushMutations();
  assert.deepEqual(tree.getNodesInGroup('actors'), [b, a]);
  tree.shutdown();
  assert.equal(tree.indexedGroupCount, 0);
});

test('queue_free from enter, ready, process, and physics waits for the active boundary', () => {
  class SelfFreeingNode extends Node {
    constructor(phase) { super({ runtimeId: `test/free-${phase}`, name: `Free-${phase}` }); this.phase = phase; this.set_process(true); this.set_physics_process(true); }
    _enter_tree() { if (this.phase === 'enter') this.queue_free(); }
    _ready() { if (this.phase === 'ready') this.queue_free(); }
    _process() { if (this.phase === 'process') this.queue_free(); }
    _physics_process() { if (this.phase === 'physics') this.queue_free(); }
  }
  for (const phase of ['enter', 'ready', 'process', 'physics']) {
    const node = new SelfFreeingNode(phase);
    const tree = new SceneTree(); tree.setRoot(node);
    if (phase === 'process') { assert.equal(node.lifecycleState, 'ready'); tree.process(0.016); }
    if (phase === 'physics') { assert.equal(node.lifecycleState, 'ready'); tree.physicsProcess(0.02); }
    assert.equal(node.lifecycleState, 'freed');
    assert.equal(tree.indexedNodeCount, 0);
  }
});

test('queue_free requested during exit upgrades the detached node on the next flush', () => {
  class ExitFreeNode extends Node { _exit_tree() { this.queue_free(); } }
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const child = new ExitFreeNode({ runtimeId: 'world/child', name: 'Child' });
  root.add_child(child);
  const tree = new SceneTree(); tree.setRoot(root);
  root.remove_child(child); tree.flushMutations();
  assert.equal(child.lifecycleState, 'queued-for-free');
  tree.flushMutations();
  assert.equal(child.lifecycleState, 'freed');
});
