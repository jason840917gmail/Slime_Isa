import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { SceneHistory } = await loadTypescriptModule('src/game/editor/scene-studio/SceneHistory.ts');
const { sceneCommands } = await loadTypescriptModule('src/game/editor/scene-studio/SceneCommand.ts');

const document = { version: 1, sceneId: 'history.fixture', rootNodeId: 'root', nodes: [{ id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} }], instances: [] };

test('command history restores documents and selections and tracks the saved cursor', () => {
  const history = new SceneHistory();
  let snapshot = { document, selection: { kind: 'scene' } };
  snapshot = history.execute(sceneCommands.addNode({ id: 'child', name: 'Child', type: 'Node', parentId: 'root', order: 0, properties: {} }), snapshot);
  assert.deepEqual(snapshot.selection, { kind: 'node', nodeId: 'child' });
  assert.equal(history.dirty, true);
  history.markSaved();
  snapshot = history.execute(sceneCommands.renameNode('child', 'Renamed'), snapshot);
  assert.equal(snapshot.document.nodes[1].name, 'Renamed');
  assert.equal(history.undoLabel, 'Rename child');
  snapshot = history.undo();
  assert.equal(snapshot.document.nodes[1].name, 'Child');
  assert.equal(history.dirty, false);
  snapshot = history.redo();
  assert.equal(snapshot.document.nodes[1].name, 'Renamed');
  assert.equal(history.dirty, true);
});

test('editing after undo truncates redo without falsely reaching an abandoned saved state', () => {
  const history = new SceneHistory();
  let snapshot = { document, selection: { kind: 'scene' } };
  snapshot = history.execute(sceneCommands.addNode({ id: 'a', name: 'A', type: 'Node', parentId: 'root', order: 0, properties: {} }), snapshot);
  snapshot = history.execute(sceneCommands.renameNode('a', 'Saved Name'), snapshot);
  history.markSaved();
  snapshot = history.undo();
  snapshot = history.execute(sceneCommands.renameNode('a', 'Branch Name'), snapshot);
  assert.equal(history.canRedo, false);
  assert.equal(history.dirty, true);
  assert.equal(snapshot.document.nodes[1].name, 'Branch Name');
});
