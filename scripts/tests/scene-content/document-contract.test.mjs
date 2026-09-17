import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { loadSceneTooling } from '../../lib/scene-conversion/load-scene-tooling.mjs';

const tooling = await loadSceneTooling();
const registry = tooling.createCoreDescriptorRegistry([{
  scriptId: 'test.actor', displayName: 'Test Actor', sourcePath: 'fixtures/TestActor.ts', properties: [
    { key: 'health', label: 'Health', value: { kind: 'number', integer: true, min: 1 }, required: true, serialized: true, inspector: 'number', overridable: true },
  ], signals: [{ id: 'defeated', payload: 'void' }], handlers: [{ id: 'reset', payload: 'void' }],
}]);
const context = { registry, hasResource: (id) => id === 'texture.hero', getResourceKind: () => 'texture' };

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8'));
const valid = fixture('valid.scene.json');

test('valid scene round trips byte-stably through canonical formatting', () => {
  assert.deepEqual(tooling.validateSceneDocument(valid, context), []);
  const once = tooling.canonicalSceneJson(valid);
  const twice = tooling.canonicalSceneJson(JSON.parse(once));
  assert.equal(twice, once);
});

test('future versions and unknown document fields remain visible as repair issues', () => {
  const messages = tooling.validateSceneDocument(fixture('future-version.scene.json'), context).map((issue) => issue.message).join('\n');
  assert.match(messages, /must be equal to constant/);
  assert.match(messages, /additional properties/);
});

test('hierarchy, identity, names, and combined sibling order are strict', () => {
  const malformed = structuredClone(valid);
  malformed.nodes[2].id = 'visual';
  malformed.nodes[2].name = 'Visual';
  malformed.nodes[2].order = 3;
  const messages = tooling.validateSceneDocument(malformed, context).map((issue) => issue.message).join('\n');
  assert.match(messages, /duplicate node ID/);
  assert.match(messages, /duplicate sibling name/);
  assert.match(messages, /dense sequence/);
});

test('inline resources supplement external references when a catalog is not loaded yet', () => {
  const mixed = {
    version: 1,
    sceneId: 'fixture.mixed-resources',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
      { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0, properties: { texture: { resourceId: 'texture.external' } } },
      { id: 'area', name: 'Area', type: 'Area2D', parentId: 'root', order: 1, properties: {} },
      { id: 'shape', name: 'Shape', type: 'CollisionShape2D', parentId: 'area', order: 0, properties: { shape: { resourceId: 'shape.inline' } } },
    ],
    instances: [],
    subresources: [{
      version: 1, resourceId: 'shape.inline', kind: 'collision-shape',
      value: { shape: 'rectangle', width: 8, height: 8 },
    }],
  };
  assert.deepEqual(tooling.validateSceneDocument(mixed, { registry }), []);
  assert.deepEqual(tooling.validateSceneDocument(mixed, {
    registry,
    hasResource: (id) => id === 'texture.external',
    getResourceKind: (id) => id === 'texture.external' ? 'texture' : undefined,
  }), []);
});

test('runtime IDs encode construction namespaces and survive display-path changes', () => {
  const before = tooling.runtimeNodeId('world-run-17', ['north-camp', 'reward-chest'], 'script');
  assert.equal(before, 'world-run-17/north-camp/reward-chest/script');
  assert.equal(tooling.runtimeNodeId('world-run-17', ['north-camp', 'reward-chest'], 'script'), before);
  assert.throws(() => tooling.sceneId('Not Safe'), /must use lowercase/);
});
