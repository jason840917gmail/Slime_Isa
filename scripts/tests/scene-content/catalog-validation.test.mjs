import assert from 'node:assert/strict';
import test from 'node:test';

import { loadSceneTooling } from '../../lib/scene-conversion/load-scene-tooling.mjs';

const tooling = await loadSceneTooling();
const registry = tooling.createCoreDescriptorRegistry();
const scene = (sceneId, target) => ({ version: 1, sceneId, rootNodeId: 'root', nodes: [{ id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} }], instances: target ? [{ instanceId: 'child', name: 'Child', sceneId: target, parentNodeId: 'root', order: 0, overrides: [] }] : [] });

test('catalog rejects missing instance sources and recursive authored instance graphs', () => {
  assert.throws(() => new tooling.SceneCatalog([scene('a', 'missing')], { registry }), /unknown instanced scene/);
  assert.throws(() => new tooling.SceneCatalog([scene('a', 'b'), scene('b', 'a')], { registry }), /scene instance cycle/);
});

test('duplicate scene IDs are rejected before catalog publication', () => {
  assert.throws(() => new tooling.SceneCatalog([scene('a'), scene('a')], { registry }), /Duplicate scene ID/);
});

test('resource validation keeps raw media in the asset manifest and validates resource links', () => {
  assert.deepEqual(tooling.validateSceneResourceDocument({ version: 1, resourceId: 'texture.hero', kind: 'texture', assetId: 'hero' }, { hasAsset: (id) => id === 'hero' }), []);
  assert.match(tooling.validateSceneResourceDocument({ version: 1, resourceId: 'texture.missing', kind: 'texture', assetId: 'missing' }, { hasAsset: () => false })[0].message, /unknown raw-media asset/);
  assert.match(tooling.validateSceneResourceDocument({ version: 1, resourceId: 'theme.main', kind: 'theme', values: {}, surprise: true })[0].message, /field is not valid/);
  assert.deepEqual(tooling.validateSceneResourceDocument({ version: 1, resourceId: 'shape.swing', kind: 'collision-shape', value: { shape: 'sector', angleRad: 0, arcWidthRad: Math.PI / 2, innerRadius: 0, outerRadius: 40 } }), []);
  assert.match(tooling.validateSceneResourceDocument({ version: 1, resourceId: 'shape.bad-swing', kind: 'collision-shape', value: { shape: 'sector', angleRad: 0, arcWidthRad: 0, innerRadius: 10, outerRadius: 10 } })[0].message, /0 < arcWidthRad/);
});

test('nested override references resolve in the containing scene scope', () => {
  const relationshipRegistry = tooling.createCoreDescriptorRegistry([
    {
      scriptId: 'test.emitter', displayName: 'Emitter', sourcePath: 'fixtures/Emitter.ts', properties: [
        { key: 'target', label: 'Target', value: { kind: 'node-reference', capability: 'receiver' }, required: true, serialized: true, inspector: 'node', overridable: true },
      ], signals: [{ id: 'ping', payload: 'event' }],
    },
    {
      scriptId: 'test.receiver', displayName: 'Receiver', sourcePath: 'fixtures/Receiver.ts', capabilities: ['receiver'], properties: [], handlers: [{ id: 'receive', payload: 'event' }],
    },
  ]);
  const leaf = {
    version: 1, sceneId: 'fixture.leaf', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Leaf', type: 'Node', parentId: null, order: 0, properties: {} },
      { id: 'fallback', name: 'Fallback', type: 'ScriptNode', scriptId: 'test.receiver', parentId: 'root', order: 0, properties: {} },
      { id: 'emitter', name: 'Emitter', type: 'ScriptNode', scriptId: 'test.emitter', parentId: 'root', order: 1, properties: { target: { nodeId: 'fallback' } } },
    ], instances: [],
  };
  const middle = {
    version: 1, sceneId: 'fixture.middle', rootNodeId: 'root',
    nodes: [{ id: 'root', name: 'Middle', type: 'Node', parentId: null, order: 0, properties: {} }],
    instances: [{ instanceId: 'leaf-placement', name: 'Leaf', sceneId: 'fixture.leaf', parentNodeId: 'root', order: 0, overrides: [] }],
  };
  const world = {
    version: 1, sceneId: 'fixture.world', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'World', type: 'Node', parentId: null, order: 0, properties: {} },
      { id: 'receiver', name: 'Receiver', type: 'ScriptNode', scriptId: 'test.receiver', parentId: 'root', order: 0, properties: {} },
    ],
    instances: [{
      instanceId: 'middle-placement', name: 'Middle', sceneId: 'fixture.middle', parentNodeId: 'root', order: 1,
      overrides: [{ sourceInstancePath: ['leaf-placement'], sourceNodeId: 'emitter', property: 'target', value: { nodeId: 'receiver' } }],
    }],
    connections: [{
      source: { instancePath: ['middle-placement', 'leaf-placement'], nodeId: 'emitter' }, signal: 'ping',
      target: { nodeId: 'receiver' }, handler: 'receive',
    }],
  };

  assert.doesNotThrow(() => new tooling.SceneCatalog([world, middle, leaf], { registry: relationshipRegistry }));
  const stale = structuredClone(world);
  stale.instances[0].overrides[0].sourceInstancePath = ['missing-placement'];
  assert.throws(() => new tooling.SceneCatalog([stale, middle, leaf], { registry: relationshipRegistry }), /instance 'missing-placement' does not resolve/);
  const incompatible = structuredClone(world);
  incompatible.instances[0].overrides[0].value = { nodeId: 'root' };
  assert.throws(() => new tooling.SceneCatalog([incompatible, middle, leaf], { registry: relationshipRegistry }), /required capability 'receiver'/);
});

test('signal connections require registered endpoints and matching payloads', () => {
  const registryWithSignals = tooling.createCoreDescriptorRegistry([
    { scriptId: 'test.source', displayName: 'Source', sourcePath: 'fixtures/Source.ts', properties: [], signals: [{ id: 'fired', payload: 'damage' }] },
    { scriptId: 'test.target', displayName: 'Target', sourcePath: 'fixtures/Target.ts', properties: [], handlers: [{ id: 'accept', payload: 'healing' }] },
  ]);
  const connected = {
    version: 1, sceneId: 'fixture.signals', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} },
      { id: 'source', name: 'Source', type: 'ScriptNode', scriptId: 'test.source', parentId: 'root', order: 0, properties: {} },
      { id: 'target', name: 'Target', type: 'ScriptNode', scriptId: 'test.target', parentId: 'root', order: 1, properties: {} },
    ], instances: [], connections: [{ source: { nodeId: 'source' }, signal: 'fired', target: { nodeId: 'target' }, handler: 'accept' }],
  };
  assert.throws(() => new tooling.SceneCatalog([connected], { registry: registryWithSignals }), /signal payload 'damage' is incompatible/);
  connected.connections[0].signal = 'missing';
  assert.throws(() => new tooling.SceneCatalog([connected], { registry: registryWithSignals }), /unknown signal 'missing'/);
});
