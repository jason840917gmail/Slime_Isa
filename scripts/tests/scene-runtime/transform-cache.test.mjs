import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { Node, Node2D } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

const node2d = (name, position = { x: 0, y: 0 }) => new Node2D({ runtimeId: `cache/${name}`, name, position });

test('cached global transforms follow ancestor moves through plain nodes', () => {
  const root = node2d('Root', { x: 10, y: 0 });
  const group = new Node({ runtimeId: 'cache/group', name: 'Group' });
  const child = node2d('Child', { x: 1, y: 2 });
  const grandchild = node2d('Grandchild', { x: 3, y: 4 });
  root.add_child(group); group.add_child(child); child.add_child(grandchild);

  assert.deepEqual(grandchild.get_global_transform().position, { x: 14, y: 6 });
  const revision = grandchild.get_global_transform_revision();
  assert.equal(grandchild.get_global_transform_revision(), revision, 'clean reads keep the revision');

  root.position = { x: 20, y: 5 };
  assert.deepEqual(grandchild.get_global_transform().position, { x: 24, y: 11 });
  assert.notEqual(grandchild.get_global_transform_revision(), revision, 'ancestor moves bump descendant revisions');

  const moved = grandchild.get_global_transform_revision();
  root.position = { x: 20, y: 5 };
  assert.equal(grandchild.get_global_transform_revision(), moved, 'assigning an identical position is not a change');
});

test('reparenting a plain node invalidates Node2D descendants', () => {
  const left = node2d('Left', { x: 100, y: 0 });
  const right = node2d('Right', { x: 0, y: 200 });
  const group = new Node({ runtimeId: 'cache/moved-group', name: 'MovedGroup' });
  const leaf = node2d('Leaf', { x: 1, y: 1 });
  left.add_child(group); group.add_child(leaf);
  assert.deepEqual(leaf.get_global_transform().position, { x: 101, y: 1 });

  left.remove_child(group);
  assert.deepEqual(leaf.get_global_transform().position, { x: 1, y: 1 }, 'detached subtree has no transform parent');
  right.add_child(group);
  assert.deepEqual(leaf.get_global_transform().position, { x: 1, y: 201 });
});

test('a sibling read does not hide a later ancestor move from other descendants', () => {
  const root = node2d('SharedRoot');
  const first = node2d('First', { x: 1, y: 0 });
  const second = node2d('Second', { x: 2, y: 0 });
  const nested = node2d('Nested', { x: 0, y: 3 });
  root.add_child(first); root.add_child(second); second.add_child(nested);
  assert.deepEqual(nested.get_global_transform().position, { x: 2, y: 3 });

  root.position = { x: 50, y: 0 };
  assert.deepEqual(first.get_global_transform().position, { x: 51, y: 0 }, 'revalidates the shared root first');
  assert.deepEqual(nested.get_global_transform().position, { x: 52, y: 3 });

  second.scale = { x: 2, y: 2 };
  assert.deepEqual(nested.get_global_transform().position, { x: 52, y: 6 });
  assert.deepEqual(first.get_global_transform().position, { x: 51, y: 0 }, 'sibling subtrees are unaffected');
});
