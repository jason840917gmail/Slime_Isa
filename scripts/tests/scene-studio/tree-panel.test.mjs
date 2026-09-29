import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { sceneTreeRows, renderSceneTreePanel, planSceneTreeDrop, sceneTreeDropZone, sceneTreeEntry, sceneTreeRowMovable } = await loadTypescriptModule('src/game/editor/scene-studio/SceneTreePanel.ts');
const { SceneDocumentState } = await loadTypescriptModule('src/game/editor/scene-studio/SceneDocumentState.ts');
const { sceneCommands } = await loadTypescriptModule('src/game/editor/scene-studio/SceneCommand.ts');
const { createCoreDescriptorRegistry } = await loadTypescriptModule('src/game/content/scenes/propertyDescriptors.ts');

const child = { version: 1, sceneId: 'shared.child', rootNodeId: 'child-root', nodes: [{ id: 'child-root', name: 'ChildRoot', type: 'Node', parentId: null, order: 0, properties: {} }, { id: 'leaf', name: 'Leaf', type: 'Node2D', parentId: 'child-root', order: 0, properties: {} }], instances: [] };
const document = { version: 1, sceneId: 'tree.fixture', rootNodeId: 'root', nodes: [{ id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} }, { id: 'local', name: 'Local', type: 'Node2D', parentId: 'root', order: 1, properties: {} }], instances: [{ instanceId: 'nested', name: 'Nested', sceneId: 'shared.child', parentNodeId: 'root', order: 0, overrides: [] }] };

test('tree panel interleaves local nodes and instances while resolved descendants stay read-only', () => {
  const rows = sceneTreeRows(document, (id) => id === child.sceneId ? child : undefined);
  assert.deepEqual(rows.map((row) => [row.kind, row.name, row.depth, row.readOnly]), [['node', 'Root', 0, false], ['instance', 'Nested', 1, false], ['node', 'ChildRoot', 2, true], ['node', 'Leaf', 3, true], ['node', 'Local', 1, false]]);
  const html = renderSceneTreePanel(rows, rows[1].key);
  assert.match(html, /role="tree"/);
  assert.match(html, /aria-selected="true"/);
});

test('instance rename, move, duplicate, and delete are command-level reversible', () => {
  const state = new SceneDocumentState(document, { registry: createCoreDescriptorRegistry() });
  const original = state.document;
  for (const command of [sceneCommands.renameInstance('nested', 'Renamed'), sceneCommands.moveInstance('nested', 'root', 1), sceneCommands.duplicateInstance('nested', 'copy', 'Copy'), sceneCommands.removeInstance('nested')]) {
    state.execute(command);
  }
  assert.deepEqual(state.document.instances.map((entry) => entry.instanceId), ['copy']);
  for (let index = 0; index < 4; index += 1) assert.equal(state.undo(), true);
  assert.deepEqual(state.document, original);
});

const nested = {
  version: 1, sceneId: 'tree.drag', rootNodeId: 'root',
  nodes: [
    { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
    { id: 'a', name: 'A', type: 'Node2D', parentId: 'root', order: 0, properties: {} },
    { id: 'a-child', name: 'AChild', type: 'Node2D', parentId: 'a', order: 0, properties: {} },
    { id: 'b', name: 'B', type: 'Node2D', parentId: 'root', order: 2, properties: {} },
  ],
  instances: [{ instanceId: 'house', name: 'House', sceneId: 'shared.child', parentNodeId: 'root', order: 1, overrides: [] }],
};
const node = (nodeId) => ({ kind: 'node', nodeId });
const instance = (instanceId) => ({ kind: 'instance', instanceId });

test('tree drops plan the new parent and sibling position like Godot', () => {
  // middle of a node row: last child of that node
  assert.deepEqual(planSceneTreeDrop(nested, node('b'), node('a'), 'inside'), { parentId: 'a', order: 1 });
  assert.deepEqual(planSceneTreeDrop(nested, instance('house'), node('a-child'), 'inside'), { parentId: 'a-child', order: 0 });
  // edges: before/after the target among its siblings (the dragged entry itself excluded)
  assert.deepEqual(planSceneTreeDrop(nested, node('b'), node('a'), 'before'), { parentId: 'root', order: 0 });
  assert.deepEqual(planSceneTreeDrop(nested, node('a'), instance('house'), 'after'), { parentId: 'root', order: 1 });
  assert.deepEqual(planSceneTreeDrop(nested, node('a-child'), node('b'), 'after'), { parentId: 'root', order: 3 });
  // refused: itself, its own subtree, beside the root, the root itself, into an instance, unknown entries
  assert.equal(planSceneTreeDrop(nested, node('a'), node('a'), 'inside'), undefined);
  assert.equal(planSceneTreeDrop(nested, node('a'), node('a-child'), 'inside'), undefined);
  assert.equal(planSceneTreeDrop(nested, node('a'), node('a-child'), 'after'), undefined);
  assert.equal(planSceneTreeDrop(nested, node('b'), node('root'), 'before'), undefined);
  assert.equal(planSceneTreeDrop(nested, node('root'), node('b'), 'inside'), undefined);
  assert.equal(planSceneTreeDrop(nested, node('b'), instance('house'), 'inside'), undefined);
  assert.equal(planSceneTreeDrop(nested, node('missing'), node('a'), 'inside'), undefined);
});

test('planned tree drops apply as undoable reparent and move commands', () => {
  const state = new SceneDocumentState(nested, { registry: createCoreDescriptorRegistry() });
  const into = planSceneTreeDrop(state.document, node('b'), node('a'), 'inside');
  state.execute(sceneCommands.reparentNode('b', into.parentId, into.order));
  const before = planSceneTreeDrop(state.document, instance('house'), node('a-child'), 'before');
  state.execute(sceneCommands.moveInstance('house', before.parentId, before.order));
  const byParent = (parentId) => [
    ...state.document.nodes.filter((entry) => entry.parentId === parentId).map((entry) => [entry.order, entry.id]),
    ...state.document.instances.filter((entry) => entry.parentNodeId === parentId).map((entry) => [entry.order, entry.instanceId]),
  ].sort((left, right) => left[0] - right[0]).map((entry) => entry[1]);
  assert.deepEqual(byParent('a'), ['house', 'a-child', 'b']);
  assert.deepEqual(byParent('root'), ['a']);
  assert.equal(state.undo(), true);
  assert.equal(state.undo(), true);
  assert.deepEqual(state.document, nested);
});

test('drop zones split rows into edges and middle, and only editable non-root rows drag', () => {
  assert.equal(sceneTreeDropZone(2, 32, node('a')), 'before');
  assert.equal(sceneTreeDropZone(16, 32, node('a')), 'inside');
  assert.equal(sceneTreeDropZone(30, 32, node('a')), 'after');
  // instances take no children, so their rows only split in half
  assert.equal(sceneTreeDropZone(14, 32, instance('house')), 'before');
  assert.equal(sceneTreeDropZone(18, 32, instance('house')), 'after');

  const rows = sceneTreeRows(document, (id) => id === child.sceneId ? child : undefined);
  assert.deepEqual(rows.map((row) => sceneTreeRowMovable(row, document.rootNodeId)), [false, true, false, false, true]);
  assert.deepEqual(rows.map((row) => sceneTreeEntry(row)), [node('root'), instance('nested'), undefined, undefined, node('local')]);
  const html = renderSceneTreePanel(rows, undefined, document.rootNodeId);
  assert.equal((html.match(/draggable="true"/g) ?? []).length, 2);
  assert.doesNotMatch(renderSceneTreePanel(rows), /draggable/);
});
