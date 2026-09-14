import assert from 'node:assert/strict';
import test from 'node:test';

import { loadSceneTooling } from '../../lib/scene-conversion/load-scene-tooling.mjs';

const tooling = await loadSceneTooling();

test('one property descriptor supplies validation and editor metadata', () => {
  const health = { key: 'health', label: 'Health', help: 'Maximum hit points', units: 'hp', value: { kind: 'number', integer: true, min: 1 }, defaultValue: 10, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains: ['physics'] }, overridable: true };
  const registry = tooling.createCoreDescriptorRegistry([{ scriptId: 'test.actor', displayName: 'Actor', sourcePath: 'Actor.ts', properties: [health] }]);
  const scene = { version: 1, sceneId: 'test.actor', rootNodeId: 'root', nodes: [{ id: 'root', name: 'Root', type: 'ScriptNode', scriptId: 'test.actor', parentId: null, order: 0, properties: { health: 0 } }], instances: [] };
  assert.match(tooling.validateSceneDocument(scene, { registry })[0].message, />= 1/);
  assert.equal(registry.scripts.get('test.actor').properties[0].inspector, 'number');
});

test('descriptor registration rejects incompatible inheritance and signal duplication', () => {
  const property = { key: 'rank', label: 'Rank', value: { kind: 'enum', values: ['normal', 'boss'] }, serialized: true, inspector: 'select', overridable: true };
  const registry = tooling.createCoreDescriptorRegistry([
    { scriptId: 'enemy', displayName: 'Enemy', sourcePath: 'Enemy.ts', properties: [property], signals: [{ id: 'defeated' }] },
    { scriptId: 'fatty', displayName: 'Fatty', sourcePath: 'Fatty.ts', extends: 'enemy', properties: [{ ...property, value: { kind: 'number' } }], signals: [{ id: 'defeated' }] },
  ]);
  const messages = tooling.validateDescriptorRegistry(registry).map((issue) => issue.message).join('\n');
  assert.match(messages, /cannot change inherited type/);
  assert.match(messages, /duplicate inherited signal/);
});

test('non-numeric properties cannot request numeric animation interpolation', () => {
  const registry = tooling.createCoreDescriptorRegistry([{ scriptId: 'bad', displayName: 'Bad', sourcePath: 'Bad.ts', properties: [{ key: 'state', label: 'State', value: { kind: 'enum', values: ['idle'] }, serialized: true, inspector: 'select', animation: { interpolation: 'numeric', domains: ['render'] }, overridable: true }] }]);
  assert.match(tooling.validateDescriptorRegistry(registry)[0].message, /numeric interpolation is incompatible/);
});

test('universal physics descriptors expose only reusable body, area, and shape capabilities', () => {
  const registry = tooling.createCoreDescriptorRegistry();
  assert.deepEqual(registry.nodeTypes.get('Area2D').signals.map((signal) => signal.id), ['body_entered', 'body_exited', 'area_entered', 'area_exited']);
  assert.equal(registry.nodeTypes.get('CharacterBody2D').capabilities.includes('character-body'), true);
  assert.equal(registry.nodeTypes.get('CollisionShape2D').allowedParentTypes.includes('Area2D'), true);
  const physicsTypes = [...registry.nodeTypes.values()].filter((descriptor) => descriptor.capabilities?.some((capability) => ['physics-body', 'character-body', 'area', 'collision-shape'].includes(capability))).map((descriptor) => descriptor.type);
  assert.deepEqual(physicsTypes, ['PhysicsBody2D', 'CharacterBody2D', 'Area2D', 'CollisionShape2D']);
  assert.equal(physicsTypes.some((type) => /enemy|damage|weapon/i.test(type)), false);
});
