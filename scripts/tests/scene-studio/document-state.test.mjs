import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { createCoreDescriptorRegistry } = await loadTypescriptModule('src/game/content/scenes/propertyDescriptors.ts');
const { SceneClipboard } = await loadTypescriptModule('src/game/editor/scene-studio/SceneClipboard.ts');
const { SceneDocumentState, SceneDocumentWorkspace } = await loadTypescriptModule('src/game/editor/scene-studio/SceneDocumentState.ts');
const { sceneCommands } = await loadTypescriptModule('src/game/editor/scene-studio/SceneCommand.ts');

const referenceProperty = { key: 'target', label: 'Target', value: { kind: 'node-reference' }, required: true, serialized: true, inspector: 'node', overridable: true };
const registry = createCoreDescriptorRegistry([{ scriptId: 'fixture.reference', displayName: 'Reference', sourcePath: 'fixture.ts', properties: [referenceProperty] }]);
const validation = { registry };

function fixture() {
  return {
    version: 1, sceneId: 'studio.fixture', rootNodeId: 'root', unknownFutureField: { kept: true },
    nodes: [
      { id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} },
      { id: 'target', name: 'Target', type: 'Node2D', parentId: 'root', order: 0, properties: {} },
      { id: 'other', name: 'Other', type: 'Node2D', parentId: 'root', order: 1, properties: {} },
      { id: 'script', name: 'Script', type: 'ScriptNode', scriptId: 'fixture.reference', parentId: 'root', order: 2, properties: { target: { nodeId: 'target' } } },
    ],
    instances: [],
  };
}

test('document commands are immutable, undoable, preserve opaque fields, and share sibling order with instances', () => {
  const source = fixture();
  const state = new SceneDocumentState(source, validation, 'hash-1');
  assert.equal(state.repairMode, true);
  assert.match(state.issues.map((issue) => issue.message).join('\n'), /additional properties/);
  state.execute(sceneCommands.renameNode('target', 'Renamed'));
  state.execute(sceneCommands.setProperty('target', 'position', [4, 5]));
  state.execute(sceneCommands.addInstance({ instanceId: 'nested', name: 'Nested', sceneId: 'other.scene', parentNodeId: 'root', order: 1, overrides: [] }));
  state.execute(sceneCommands.reorderNode('script', 0));
  assert.equal(source.nodes[1].name, 'Target');
  assert.equal(state.document.nodes.find((node) => node.id === 'target').name, 'Renamed');
  assert.deepEqual(state.document.unknownFutureField, { kept: true });
  const children = [
    ...state.document.nodes.filter((node) => node.parentId === 'root').map((node) => [node.order, node.id]),
    ...state.document.instances.map((instance) => [instance.order, instance.instanceId]),
  ].sort((left, right) => left[0] - right[0]);
  assert.deepEqual(children.map((entry) => entry[0]), [0, 1, 2, 3]);
  assert.equal(children[0][1], 'script');
  assert.equal(state.dirty, true);
  assert.equal(state.undo(), true);
  assert.notEqual(state.document.nodes.find((node) => node.id === 'script').order, 0);
  assert.equal(state.redo(), true);
});

test('every document command is inverted by command-level undo, including root replacement', () => {
  const base = fixture();
  base.nodes[1].properties.position = [1, 2];
  base.instances.push({
    instanceId: 'nested', name: 'Nested', sceneId: 'other.scene', parentNodeId: 'root', order: 3,
    overrides: [{ sourceInstancePath: [], sourceNodeId: 'source', property: 'visible', value: false }],
  });
  base.subresources = [{ version: 1, resourceId: 'theme.old', kind: 'theme', values: { tone: 'moss' } }];
  base.connections = [{ source: { nodeId: 'target' }, signal: 'done', target: { nodeId: 'script' }, handler: 'receive' }];

  const cases = [
    sceneCommands.addNode({ id: 'added', name: 'Added', type: 'Node', parentId: 'root', order: 1, properties: {} }),
    sceneCommands.renameNode('target', 'Renamed'),
    sceneCommands.reparentNode('other', 'target', 0),
    sceneCommands.reorderNode('script', 0),
    sceneCommands.setProperty('target', 'position', [9, 8]),
    sceneCommands.clearProperty('target', 'position'),
    sceneCommands.addInstance({ instanceId: 'second', name: 'Second', sceneId: 'second.scene', parentNodeId: 'root', order: 1, overrides: [] }),
    sceneCommands.removeInstance('nested'),
    sceneCommands.setOverride('nested', { sourceInstancePath: [], sourceNodeId: 'source', property: 'visible', value: true }),
    sceneCommands.revertOverride('nested', [], 'source', 'visible'),
    sceneCommands.upsertResource({ version: 1, resourceId: 'theme.new', kind: 'theme', values: { tone: 'amber' } }),
    sceneCommands.removeResource('theme.old'),
    sceneCommands.connectSignal({ source: { nodeId: 'other' }, signal: 'changed', target: { nodeId: 'script' }, handler: 'receive' }),
    sceneCommands.disconnectSignal(0),
    sceneCommands.deleteSubtree('target', [{ ownerNodeId: 'script', property: 'target', value: { nodeId: 'other' } }]),
  ];

  for (const command of cases) {
    const state = new SceneDocumentState(base, validation);
    const before = state.document;
    state.execute(command);
    const after = state.document;
    assert.notDeepEqual(after, before, command.label);
    assert.equal(state.undo(), true, command.label);
    assert.deepEqual(state.document, before, command.label);
    assert.equal(state.redo(), true, command.label);
    assert.deepEqual(state.document, after, command.label);
  }

  const rootState = new SceneDocumentState(base, validation);
  const beforeRoot = rootState.document;
  rootState.execute(sceneCommands.replaceRoot({ id: 'replacement', name: 'Replacement', type: 'Node', parentId: null, order: 0, properties: {} }));
  assert.equal(rootState.document.rootNodeId, 'replacement');
  assert.deepEqual(rootState.document.nodes.map((node) => node.id), ['replacement']);
  assert.equal(rootState.undo(), true);
  assert.deepEqual(rootState.document, beforeRoot);
});

test('command preconditions reject unknown parents, missing resources, and hierarchy cycles without mutation', () => {
  const state = new SceneDocumentState(fixture(), validation);
  const before = state.document;
  assert.throws(() => state.execute(sceneCommands.addInstance({ instanceId: 'bad', name: 'Bad', sceneId: 'other.scene', parentNodeId: 'missing', order: 0, overrides: [] })), /Parent 'missing'/);
  assert.throws(() => state.execute(sceneCommands.removeResource('missing.resource')), /does not exist/);
  assert.throws(() => state.execute(sceneCommands.reparentNode('target', 'target', 0)), /own subtree/);
  assert.deepEqual(state.document, before);
  assert.equal(state.dirty, false);
});

test('deletion requires explicit reference repair and commits all repairs atomically', () => {
  const state = new SceneDocumentState(fixture(), validation);
  const pending = state.requestDeleteNode('target');
  assert.equal(pending.kind, 'requires-repair');
  assert.deepEqual(pending.references.map((entry) => `${entry.ownerNodeId}.${entry.property}:${entry.required}`), ['script.target:true']);
  assert.equal(state.requestDeleteNode('target', { kind: 'remove-optional' }).kind, 'requires-repair');
  assert.throws(() => state.requestDeleteNode('target', { kind: 'repair', replacements: {} }), /needs a replacement/);
  assert.equal(state.requestDeleteNode('target', { kind: 'repair', replacements: { 'script.target': { nodeId: 'other' } } }).kind, 'deleted');
  assert.equal(state.document.nodes.some((node) => node.id === 'target'), false);
  assert.deepEqual(state.document.nodes.find((node) => node.id === 'script').properties.target, { nodeId: 'other' });
  state.undo();
  assert.equal(state.document.nodes.some((node) => node.id === 'target'), true);
  assert.deepEqual(state.document.nodes.find((node) => node.id === 'script').properties.target, { nodeId: 'target' });
});

test('clipboard duplicates a subtree, internal references, and internal signal connections with caller-owned IDs', () => {
  const document = fixture();
  document.nodes.push({ id: 'leaf', name: 'Leaf', type: 'Node', parentId: 'target', order: 0, properties: { peer: { nodeId: 'target' } } });
  document.connections = [{ source: { nodeId: 'target' }, signal: 'done', target: { nodeId: 'leaf' }, handler: 'receive' }];
  const clipboard = new SceneClipboard();
  clipboard.copy(document, 'target');
  const state = new SceneDocumentState(document, validation);
  state.execute(clipboard.paste('root', (id) => `${id}-copy`));
  const copiedLeaf = state.document.nodes.find((node) => node.id === 'leaf-copy');
  assert.equal(copiedLeaf.parentId, 'target-copy');
  assert.deepEqual(copiedLeaf.properties.peer, { nodeId: 'target-copy' });
  assert.deepEqual(state.document.connections.at(-1), { source: { nodeId: 'target-copy' }, signal: 'done', target: { nodeId: 'leaf-copy' }, handler: 'receive' });
});

test('workspace keeps independent dirty tabs and refuses accidental dirty close', () => {
  const workspace = new SceneDocumentWorkspace();
  const first = workspace.open(fixture(), validation);
  const secondDocument = { ...fixture(), sceneId: 'studio.second' };
  workspace.open(secondDocument, validation);
  first.execute(sceneCommands.renameNode('target', 'Dirty'));
  assert.equal(workspace.close('studio.fixture'), false);
  assert.equal(workspace.close('studio.fixture', true), true);
  assert.deepEqual(workspace.openSceneIds, ['studio.second']);
});
