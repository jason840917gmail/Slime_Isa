import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');
const descriptors = t.createCoreDescriptorRegistry([
  { scriptId: 'test.emitter', displayName: 'Emitter', sourcePath: 'test/Emitter.ts', properties: [
    { key: 'target', label: 'Target', value: { kind: 'node-reference' }, required: true, serialized: true, inspector: 'node', overridable: true },
    { key: 'items', label: 'Items', value: { kind: 'json' }, serialized: true, inspector: 'json', overridable: true },
  ], signals: [{ id: 'ping', payload: 'number' }] },
  { scriptId: 'test.receiver', displayName: 'Receiver', sourcePath: 'test/Receiver.ts', properties: [], handlers: [{ id: 'receive', payload: 'number' }] },
]);

class ConfigNode extends t.Node {
  constructor(context) { super(context); this.properties = context.properties; this.received = []; }
}

function packedFixture() {
  return new t.PackedScene({ sourceSceneId: 'fixture', rootKey: 'root', resources: [], nodes: [
    { key: 'root', sourceSceneId: 'fixture', authoredNodeId: 'root', instancePath: [], name: 'Root', type: 'Node', parentKey: null, order: 0, properties: {}, propertyScopes: {} },
    { key: 'receiver', sourceSceneId: 'fixture', authoredNodeId: 'receiver', instancePath: [], name: 'Receiver', type: 'ScriptNode', scriptId: 'test.receiver', parentKey: 'root', order: 0, properties: {}, propertyScopes: {} },
    { key: 'emitter', sourceSceneId: 'fixture', authoredNodeId: 'emitter', instancePath: [], name: 'Emitter', type: 'ScriptNode', scriptId: 'test.emitter', parentKey: 'root', order: 1, properties: { target: { nodeId: 'receiver' }, items: ['source'] }, propertyScopes: { target: [], items: [] } },
  ], connections: [{ sourceKey: 'emitter', signal: 'ping', targetKey: 'receiver', handler: 'receive' }] });
}

function instantiator(nodeTypes = new t.NodeTypeRegistry().register('Node', (context) => new ConfigNode(context))) {
  const scripts = new t.ScriptRegistry()
    .register('test.emitter', (context) => new ConfigNode(context))
    .register('test.receiver', (context) => { const node = new ConfigNode(context); node.registerSignalHandler('receive', (value) => node.received.push(value)); return node; });
  return new t.SceneInstantiator({ nodeTypes, scripts, descriptors });
}

test('one immutable packed scene creates independent detached trees with scoped references and signals', () => {
  const packed = packedFixture();
  const maker = instantiator();
  const first = maker.instantiate_scene(packed);
  const second = maker.instantiate_scene(packed);
  assert.equal(first.lifecycleState, 'detached');
  assert.notEqual(first.runtimeId, second.runtimeId);
  const firstEmitter = first.get_node('Emitter');
  const secondEmitter = second.get_node('Emitter');
  firstEmitter.properties.items.push('changed');
  assert.deepEqual(secondEmitter.properties.items, ['source']);
  assert.deepEqual(packed.definition.nodes.find((entry) => entry.key === 'emitter').properties.items, ['source']);
  assert.equal(firstEmitter.getReference('target').configuredTarget, first.get_node('Receiver'));
  firstEmitter.getSignal('ping').emit(1);
  assert.deepEqual(first.get_node('Receiver').received, []);
  const tree = new t.SceneTree(); tree.setRoot(first);
  firstEmitter.getSignal('ping').emit(7);
  assert.deepEqual(first.get_node('Receiver').received, [7]);
  tree.shutdown();
});

test('constructor failures clean every already-created detached node', () => {
  let disposed = 0;
  const types = new t.NodeTypeRegistry()
    .register('Node', (context) => { const node = new ConfigNode(context); node.lifetimeDisposables.add(() => { disposed += 1; }); return node; })
    .register('Broken', () => { throw new Error('constructor exploded'); });
  const packed = new t.PackedScene({ sourceSceneId: 'broken', rootKey: 'root', resources: [], connections: [], nodes: [
    { key: 'root', sourceSceneId: 'broken', authoredNodeId: 'root', instancePath: [], name: 'Root', type: 'Node', parentKey: null, order: 0, properties: {}, propertyScopes: {} },
    { key: 'bad', sourceSceneId: 'broken', authoredNodeId: 'bad', instancePath: [], name: 'Bad', type: 'Broken', parentKey: 'root', order: 0, properties: {}, propertyScopes: {} },
  ] });
  assert.throws(() => new t.SceneInstantiator({ nodeTypes: types, descriptors }).instantiate_scene(packed), /constructor exploded/);
  assert.equal(disposed, 1);
});

test('dynamic persistence keys must be explicit and unique within a tree', () => {
  const packed = packedFixture();
  const maker = instantiator();
  const root = maker.instantiate_scene(packed, { persistenceKey: 'placement.one' });
  assert.equal(root.explicitPersistenceKey, 'placement.one');
  const host = new t.Node({ runtimeId: 'host/root', name: 'Host' });
  const tree = new t.SceneTree(); tree.setRoot(host); host.add_child(root); tree.flushMutations();
  assert.equal(tree.getNodeByPersistenceKey('placement.one'), root);
  const duplicate = maker.instantiate_scene(packed, { persistenceKey: 'placement.one' });
  host.add_child(duplicate); tree.flushMutations();
  assert.equal(duplicate.lifecycleState, 'detached');
  assert.equal(tree.getNodeByPersistenceKey('placement.one'), root);
});

test('instantiation overrides configure one mount without mutating packed scene data', () => {
  const packed = packedFixture();
  const maker = instantiator();
  const root = maker.instantiate_scene(packed, {
    propertyOverrides: [
      { nodeId: 'emitter', property: 'items', value: ['placement-specific'] },
      { nodeId: 'emitter', property: 'target', value: { nodeId: 'receiver' } },
    ],
  });
  const emitter = root.get_node('Emitter');
  assert.deepEqual(emitter.properties.items, ['placement-specific']);
  assert.equal(emitter.getReference('target').configuredTarget, root.get_node('Receiver'));
  assert.deepEqual(packed.definition.nodes.find((entry) => entry.key === 'emitter').properties.items, ['source']);
  assert.throws(() => maker.instantiate_scene(packed, {
    propertyOverrides: [{ nodeId: 'missing', property: 'items', value: [] }],
  }), /does not exist/);
  assert.throws(() => maker.instantiate_scene(packed, {
    propertyOverrides: [{ nodeId: 'emitter', property: 'items', value: [] }, { nodeId: 'emitter', property: 'items', value: [] }],
  }), /duplicated/);
});
