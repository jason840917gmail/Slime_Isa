import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { Node, Node2D, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

test('free wins over a pending add and ancestor free suppresses descendant work', () => {
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const parent = new Node({ runtimeId: 'world/parent', name: 'Parent' });
  const other = new Node({ runtimeId: 'world/other', name: 'Other' });
  const child = new Node({ runtimeId: 'world/child', name: 'Child' });
  root.add_child(parent); root.add_child(other); parent.add_child(child);
  const tree = new SceneTree(); tree.setRoot(root);
  const pending = new Node({ runtimeId: 'world/pending', name: 'Pending' });
  root.add_child(pending); pending.queue_free();
  child.reparent(other); parent.queue_free();
  tree.flushMutations();
  assert.equal(pending.lifecycleState, 'freed');
  assert.equal(parent.lifecycleState, 'freed');
  assert.equal(child.lifecycleState, 'freed');
  assert.equal(other.get_child_count(), 0);
});

test('same-flush remove/add is rejected as ambiguous', () => {
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const left = new Node({ runtimeId: 'world/left', name: 'Left' });
  const right = new Node({ runtimeId: 'world/right', name: 'Right' });
  const child = new Node({ runtimeId: 'world/child', name: 'Child' });
  root.add_child(left); root.add_child(right); left.add_child(child);
  const tree = new SceneTree(); tree.setRoot(root);
  left.remove_child(child);
  assert.throws(() => right.add_child(child), /Ambiguous same-flush remove\/add/);
  tree.flushMutations();
  assert.equal(child.lifecycleState, 'detached');
  assert.equal(tree.diagnostics.some((entry) => /Ambiguous/.test(entry.message)), true);
});

test('reparent is atomic, rejects ancestry cycles, and preserves global Node2D transform', () => {
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const left = new Node2D({ runtimeId: 'world/left', name: 'Left', position: { x: 10, y: 20 }, scale: { x: 2, y: 2 } });
  const right = new Node2D({ runtimeId: 'world/right', name: 'Right', position: { x: -4, y: 3 }, rotation: Math.PI / 2 });
  const child = new Node2D({ runtimeId: 'world/child', name: 'Child', position: { x: 5, y: 7 }, rotation: 0.25 });
  root.add_child(left); root.add_child(right); left.add_child(child);
  const tree = new SceneTree(); tree.setRoot(root);
  const before = child.get_global_transform();
  child.reparent(right); tree.flushMutations();
  const after = child.get_global_transform();
  assert.ok(Math.abs(after.position.x - before.position.x) < 1e-9);
  assert.ok(Math.abs(after.position.y - before.position.y) < 1e-9);
  assert.ok(Math.abs(after.rotation - before.rotation) < 1e-9);
  assert.equal(child.get_parent(), right);
  right.reparent(child); tree.flushMutations();
  assert.equal(right.get_parent(), root);
  assert.match(tree.diagnostics.at(-1).message, /ancestry cycle/);
});

test('mutations requested during a mutation callback wait for the next flush', () => {
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const replacement = new Node({ runtimeId: 'world/replacement', name: 'Replacement' });
  class ExitSpawner extends Node { _exit_tree() { root.add_child(replacement); } }
  const child = new ExitSpawner({ runtimeId: 'world/child', name: 'Child' });
  root.add_child(child);
  const tree = new SceneTree(); tree.setRoot(root);
  root.remove_child(child); tree.flushMutations();
  assert.equal(replacement.lifecycleState, 'detached');
  assert.equal(tree.queuedMutationCount, 1);
  tree.flushMutations();
  assert.equal(replacement.lifecycleState, 'ready');
});

test('parent compatibility is revalidated at flush without partial insertion', () => {
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const allowed = new Node({ runtimeId: 'world/allowed', name: 'Allowed' });
  const rejected = new Node({ runtimeId: 'world/rejected', name: 'Rejected' });
  root.add_child(allowed); root.add_child(rejected);
  const tree = new SceneTree({ validateParent: (_node, parent) => parent === rejected ? 'Rejected parent type' : undefined });
  tree.setRoot(root);
  const child = new Node({ runtimeId: 'world/child', name: 'Child' });
  rejected.add_child(child); tree.flushMutations();
  assert.equal(child.lifecycleState, 'detached');
  assert.equal(child.get_parent(), undefined);
  assert.match(tree.diagnostics.at(-1).message, /Rejected parent type/);
  child.queue_free();
  assert.equal(child.lifecycleState, 'freed');
});
