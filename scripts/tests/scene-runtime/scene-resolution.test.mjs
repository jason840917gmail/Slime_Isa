import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const tooling = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');

const scripts = [
  { scriptId: 'test.receiver', displayName: 'Receiver', sourcePath: 'test/Receiver.ts', capabilities: ['receiver'], properties: [] },
  { scriptId: 'test.link', displayName: 'Link', sourcePath: 'test/Link.ts', properties: [
    { key: 'label', label: 'Label', value: { kind: 'string' }, serialized: true, inspector: 'text', overridable: true },
    { key: 'tone', label: 'Tone', value: { kind: 'string' }, defaultValue: 'calm', serialized: true, inspector: 'text', overridable: true },
    { key: 'target', label: 'Target', value: { kind: 'node-reference', capability: 'receiver' }, required: true, serialized: true, inspector: 'node', overridable: true },
  ] },
  { scriptId: 'test.dynamic', displayName: 'Dynamic', sourcePath: 'test/Dynamic.ts', properties: [
    { key: 'next', label: 'Next', value: { kind: 'scene-reference', dynamic: true }, serialized: true, inspector: 'scene', overridable: true },
  ] },
];
const registry = tooling.createCoreDescriptorRegistry(scripts);
const node = (id, name, parentId, order, properties = {}, scriptId) => ({ id, name, type: scriptId ? 'ScriptNode' : 'Node', scriptId, parentId, order, properties });

function fixtureDocuments() {
  const leaf = { version: 1, sceneId: 'leaf', rootNodeId: 'root', nodes: [
    node('root', 'LeafRoot', null, 0),
    node('fallback', 'Fallback', 'root', 0, {}, 'test.receiver'),
    node('link', 'Link', 'root', 1, { label: 'source', target: { nodeId: 'fallback' } }, 'test.link'),
  ], instances: [] };
  const middle = { version: 1, sceneId: 'middle', rootNodeId: 'root', nodes: [node('root', 'MiddleRoot', null, 0)], instances: [
    { instanceId: 'leaf-slot', name: 'Leaf', sceneId: 'leaf', parentNodeId: 'root', order: 0, overrides: [
      { sourceInstancePath: [], sourceNodeId: 'link', property: 'label', value: 'middle' },
    ] },
  ] };
  const world = { version: 1, sceneId: 'world', rootNodeId: 'root', nodes: [
    node('root', 'World', null, 0), node('receiver', 'Receiver', 'root', 0, {}, 'test.receiver'),
  ], instances: [
    { instanceId: 'first', name: 'First', sceneId: 'middle', parentNodeId: 'root', order: 1, persistenceKey: 'world.first', overrides: [
      { sourceInstancePath: ['leaf-slot'], sourceNodeId: 'link', property: 'label', value: 'outer' },
      { sourceInstancePath: ['leaf-slot'], sourceNodeId: 'link', property: 'target', value: { nodeId: 'receiver' } },
    ] },
    { instanceId: 'second', name: 'Second', sceneId: 'middle', parentNodeId: 'root', order: 2, overrides: [] },
  ] };
  return [world, middle, leaf];
}

test('preparation expands deep repeated instances, merges order, and preserves override reference scope', async () => {
  const documents = new Map(fixtureDocuments().map((document) => [document.sceneId, document]));
  let loads = 0;
  const loader = new tooling.SceneDocumentLoader(async (id) => { loads += 1; return documents.get(id); });
  const packed = await new tooling.SceneResolver({ documents: loader, registry }).prepare_scene('world');
  assert.equal(loads, 3);
  assert.deepEqual(packed.definition.nodes.map((entry) => entry.key), [
    'root', 'receiver', 'first/root', 'first/leaf-slot/root', 'first/leaf-slot/fallback', 'first/leaf-slot/link',
    'second/root', 'second/leaf-slot/root', 'second/leaf-slot/fallback', 'second/leaf-slot/link',
  ]);
  const first = packed.definition.nodes.find((entry) => entry.key === 'first/leaf-slot/link');
  const second = packed.definition.nodes.find((entry) => entry.key === 'second/leaf-slot/link');
  assert.equal(first.properties.label, 'outer');
  assert.equal(first.properties.tone, 'calm');
  assert.deepEqual(first.propertyScopes.target, []);
  assert.equal(second.properties.label, 'middle');
  assert.deepEqual(second.propertyScopes.target, ['second', 'leaf-slot']);
  const nestedRoot = packed.definition.nodes.find((entry) => entry.key === 'first/leaf-slot/root');
  assert.deepEqual(nestedRoot.provenance.containingInstancePath, ['first']);
  const placedRoot = packed.definition.nodes.find((entry) => entry.key === 'first/root');
  assert.equal(placedRoot.persistenceKey, 'world.first');
  assert.equal(placedRoot.provenance.persistenceKey, 'world.first');
  packed.dispose();
  assert.equal(loader.activeLeaseCount(), 0);
});

test('stale overrides and direct or indirect authored cycles fail, while dynamic scene references do not form construction edges', async () => {
  const staleDocs = fixtureDocuments();
  staleDocs[0].instances[0].overrides[0].sourceNodeId = 'missing';
  const staleLoader = new tooling.SceneDocumentLoader(async (id) => staleDocs.find((entry) => entry.sceneId === id));
  await assert.rejects(new tooling.SceneResolver({ documents: staleLoader, registry }).prepare_scene('world'), /Stale override/);

  for (const documents of [
    [{ version: 1, sceneId: 'a', rootNodeId: 'root', nodes: [node('root', 'A', null, 0)], instances: [{ instanceId: 'self', name: 'Self', sceneId: 'a', parentNodeId: 'root', order: 0, overrides: [] }] }],
    [
      { version: 1, sceneId: 'a', rootNodeId: 'root', nodes: [node('root', 'A', null, 0)], instances: [{ instanceId: 'b', name: 'B', sceneId: 'b', parentNodeId: 'root', order: 0, overrides: [] }] },
      { version: 1, sceneId: 'b', rootNodeId: 'root', nodes: [node('root', 'B', null, 0)], instances: [{ instanceId: 'a', name: 'A', sceneId: 'a', parentNodeId: 'root', order: 0, overrides: [] }] },
    ],
  ]) {
    const loader = new tooling.SceneDocumentLoader(async (id) => documents.find((entry) => entry.sceneId === id));
    await assert.rejects(new tooling.SceneResolver({ documents: loader, registry }).prepare_scene('a'), /cycle/);
  }

  const dynamic = { version: 1, sceneId: 'dynamic', rootNodeId: 'root', nodes: [node('root', 'Dynamic', null, 0, { next: { sceneId: 'dynamic' } }, 'test.dynamic')], instances: [] };
  const loader = new tooling.SceneDocumentLoader(async () => dynamic);
  const packed = await new tooling.SceneResolver({ documents: loader, registry }).prepare_scene('dynamic');
  assert.equal(packed.definition.nodes.length, 1);
  packed.dispose();
});
