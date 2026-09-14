import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const descriptors = await loadTypescriptModule('src/game/content/scenes/propertyDescriptors.ts');
const { sceneInspectorModel, renderSceneInspector } = await loadTypescriptModule('src/game/editor/scene-studio/SceneInspector.ts');
const { PropertyEditorRegistry } = await loadTypescriptModule('src/game/editor/scene-studio/PropertyEditorRegistry.ts');

const script = { scriptId: 'game.actor', displayName: 'Actor behavior', sourcePath: 'features/scripts/Actor.ts', capabilities: ['actor'], references: [{ key: 'body', label: 'Body', required: true }], properties: [{ key: 'health', label: 'Health', group: 'Actor', units: 'HP', value: { kind: 'number', integer: true, min: 1 }, defaultValue: 10, required: true, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains: ['physics'] }, overridable: true }] };
const registry = descriptors.createCoreDescriptorRegistry([script]);

test('inspector is generated from shared descriptors with defaults, overrides, script provenance, and warnings', () => {
  const node = { id: 'logic', name: 'Logic', type: 'ScriptNode', scriptId: 'game.actor', parentId: 'root', order: 0, properties: {} };
  const instance = { instanceId: 'actor', name: 'Actor', sceneId: 'actor.scene', parentNodeId: 'root', order: 0, overrides: [{ sourceInstancePath: [], sourceNodeId: 'logic', property: 'health', value: 22 }] };
  const model = sceneInspectorModel(node, registry, instance);
  assert.equal(model.groups.get('Actor')[0].origin, 'override');
  assert.equal(model.groups.get('Actor')[0].value, 22);
  assert.deepEqual(model.capabilities, ['actor']);
  assert.match(model.warnings[0], /Body/);
  assert.match(renderSceneInspector(model), /features\/scripts\/Actor\.ts/);
});

test('property editors parse descriptor types and enforce numeric constraints', () => {
  const editors = new PropertyEditorRegistry();
  const health = script.properties[0];
  assert.equal(editors.get('number').parse('12', health), 12);
  assert.throws(() => editors.get('number').parse('0', health), /at least 1/);
  assert.deepEqual(editors.get('node').parse('body', { ...health, inspector: 'node' }), { nodeId: 'body' });
});
