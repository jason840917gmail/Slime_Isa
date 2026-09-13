import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { Node, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

class LifecycleNode extends Node {
  constructor(id, options = {}) { super({ runtimeId: `root/${id}`, name: id }); this.options = options; this.enters = 0; this.exits = 0; }
  _enter_tree() { this.enters += 1; if (this.options.failEnterAt === this.enters) throw new Error(`enter failed:${this.name}`); }
  _ready() {
    if (this.options.command) this.queue_external_command(this.options.command);
    if (this.options.failReady) throw new Error(`ready failed:${this.name}`);
    if (this.options.assertPrivate) {
      assert.equal(this.get_tree().getNodeById(this.runtimeId), undefined);
      assert.equal(this.get_tree().getNodesInGroup('staged').includes(this), false);
      assert.equal(this.get_tree().root, undefined);
      assert.equal(this.get_node(`/${this.name}`), this);
    }
  }
  _exit_tree() { this.exits += 1; }
}

test('failed replacement restores the old root and discards staged external commands', () => {
  let commands = 0;
  const oldRoot = new LifecycleNode('Old');
  const replacement = new LifecycleNode('Replacement', { command: () => { commands += 1; }, failReady: true, assertPrivate: true });
  replacement.add_to_group('staged');
  const tree = new SceneTree(); tree.setRoot(oldRoot);
  assert.equal(tree.replaceRoot(replacement), false);
  assert.equal(tree.root, oldRoot);
  assert.equal(oldRoot.lifecycleState, 'ready');
  assert.equal(oldRoot.enters, 2);
  assert.equal(commands, 0);
  assert.equal(replacement.lifecycleState, 'detached');
  assert.equal(tree.indexedNodeCount, 1);
});

test('failed initial insertion keeps staged lookup private and discards enter and exit commands', () => {
  let commands = 0;
  class CommandNode extends LifecycleNode {
    _enter_tree() { super._enter_tree(); this.queue_external_command(() => { commands += 1; }); }
    _exit_tree() { super._exit_tree(); this.queue_external_command(() => { commands += 10; }); }
  }
  const root = new CommandNode('Initial', { failReady: true, assertPrivate: true });
  const tree = new SceneTree();
  tree.setRoot(root);
  assert.equal(tree.root, undefined);
  assert.equal(root.lifecycleState, 'detached');
  assert.equal(tree.indexedNodeCount, 0);
  assert.equal(commands, 0);
});

test('successful replacement commits commands only after ready and frees the old root', () => {
  let commands = 0;
  const oldRoot = new LifecycleNode('Old');
  const replacement = new LifecycleNode('Replacement', { command: () => { commands += 1; }, assertPrivate: true });
  replacement.add_to_group('staged');
  const tree = new SceneTree(); tree.setRoot(oldRoot);
  assert.equal(tree.replaceRoot(replacement), true);
  assert.equal(tree.root, replacement);
  assert.equal(replacement.lifecycleState, 'ready');
  assert.equal(oldRoot.lifecycleState, 'freed');
  assert.equal(commands, 1);
  assert.deepEqual(tree.getNodesInGroup('staged'), [replacement]);
});

test('a failed old-root restoration leaves the tree paused and fatal', () => {
  const oldRoot = new LifecycleNode('Old', { failEnterAt: 2 });
  const replacement = new LifecycleNode('Replacement', { failReady: true });
  const tree = new SceneTree(); tree.setRoot(oldRoot);
  assert.equal(tree.replaceRoot(replacement), false);
  assert.equal(tree.root, undefined);
  assert.equal(tree.isFatal, true);
  assert.equal(tree.paused, true);
  assert.equal(tree.indexedNodeCount, 0);
  assert.match(tree.diagnostics.at(-1).message, /could not be restored/);
});
