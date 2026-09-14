import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { sceneTreeRows, renderSceneTreePanel } = await loadTypescriptModule('src/game/editor/scene-studio/SceneTreePanel.ts');
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
