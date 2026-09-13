import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { Node, NodeReference, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

test('name paths support absolute and relative lookup without owning stable identity', () => {
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const branch = new Node({ runtimeId: 'world/branch', name: 'Branch' });
  const leaf = new Node({ runtimeId: 'world/leaf', name: 'Leaf' });
  root.add_child(branch); branch.add_child(leaf);
  const tree = new SceneTree(); tree.setRoot(root);
  assert.equal(root.get_node('Branch/Leaf'), leaf);
  assert.equal(leaf.get_node('/'), root);
  assert.equal(leaf.get_node('../.'), branch);
  assert.equal(leaf.get_node('/Root/Branch'), branch);
  const stableId = leaf.runtimeId;
  leaf.name = 'Renamed';
  assert.equal(leaf.runtimeId, stableId);
  assert.equal(root.get_node('Branch/Renamed'), leaf);
  assert.equal(tree.getNodeById(stableId), leaf);
  const sibling = new Node({ runtimeId: 'world/sibling', name: 'Sibling' });
  root.add_child(sibling); tree.flushMutations();
  assert.throws(() => { branch.name = 'Sibling'; }, /Sibling name|already exists/);
});

test('node references suspend outside a shared active tree and recover after re-entry', () => {
  const root = new Node({ runtimeId: 'world/root', name: 'Root' });
  const owner = new Node({ runtimeId: 'world/owner', name: 'Owner' });
  const target = new Node({ runtimeId: 'world/target', name: 'Target' });
  const reference = owner.defineReference('target', new NodeReference(target, true));
  root.add_child(owner); root.add_child(target);
  const tree = new SceneTree(); tree.setRoot(root);
  assert.equal(reference.resolve(owner), target);
  root.remove_child(target); tree.flushMutations();
  assert.equal(reference.resolve(owner), undefined);
  root.add_child(target); tree.flushMutations();
  assert.equal(reference.resolve(owner), target);
});

test('duplicate remaps internal references and leaves external references unresolved', () => {
  const root = new Node({ runtimeId: 'source/root', name: 'Root' });
  const owner = new Node({ runtimeId: 'source/owner', name: 'Owner' });
  const internal = new Node({ runtimeId: 'source/internal', name: 'Internal' });
  const external = new Node({ runtimeId: 'source/external', name: 'External' });
  owner.defineReference('internal', new NodeReference(internal, true));
  owner.defineReference('external', new NodeReference(external, true));
  root.add_child(owner); root.add_child(internal);
  const copy = root.duplicate();
  const copiedOwner = copy.get_node('Owner');
  const copiedInternal = copy.get_node('Internal');
  assert.equal(copiedOwner.getReference('internal').configuredTarget, copiedInternal);
  assert.equal(copiedOwner.getReference('external').configuredTarget, undefined);
  assert.notEqual(copy.runtimeId, root.runtimeId);
  assert.equal(copy.lifecycleState, 'detached');
  const tree = new SceneTree(); tree.setRoot(copy);
  assert.equal(tree.root, undefined);
  assert.match(tree.diagnostics[0].message, /Required node reference.*unresolved/);
});
