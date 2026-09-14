import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { Node, NodeReference, SceneTree, ScriptNode, ScriptRegistry } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

const property = (key, kind = 'number', defaultValue = 1) => ({ key, label: key, value: { kind }, defaultValue, serialized: true, inspector: kind === 'number' ? 'number' : 'text', overridable: true });
const context = (scriptId, runtimeId = `scripts/${scriptId}`) => ({ runtimeId, name: scriptId, type: 'ScriptNode', scriptId, properties: { speed: 7 }, resources: new Map() });
const factory = (construction) => new ScriptNode({ runtimeId: construction.runtimeId, name: construction.name, scriptId: construction.scriptId, exportedProperties: construction.properties });

test('registered ScriptNodes expose inherited metadata, exports, source navigation, warnings, and typed services', () => {
  const movement = { move() { return 'moved'; } };
  const registry = new ScriptRegistry({ movement })
    .registerDefinition({
      descriptor: {
        scriptId: 'character', displayName: 'Character', sourcePath: 'src/Character.ts', capabilities: ['character'], exclusiveCapabilities: ['movement-owner'],
        properties: [property('speed')], signals: [{ id: 'hurt' }], handlers: [{ id: 'reset' }], references: [{ key: 'body', label: 'Body', required: true, expectedNodeType: 'CharacterBody2D', expectedCapability: 'physics-body' }],
      },
      factory,
      configurationWarnings: [(node) => node.exportedProperties.speed === 0 ? 'Speed is zero' : undefined],
    })
    .registerDefinition({
      descriptor: {
        scriptId: 'player', displayName: 'Player', sourcePath: 'src/Player.ts', extends: 'character', capabilities: ['player'],
        properties: [{ ...property('speed'), label: 'Run Speed', defaultValue: 2 }, property('title', 'string', 'hero')], handlers: [{ id: 'interact' }],
      },
      factory,
    });
  registry.validate();
  const node = registry.construct(context('player'));
  assert.equal(node instanceof ScriptNode, true);
  assert.equal(node.scriptId, 'player');
  assert.equal(node.sourcePath, 'src/Player.ts');
  assert.deepEqual([...node.capabilities], ['character', 'player']);
  assert.deepEqual(node.metadata.exclusiveCapabilities, ['movement-owner']);
  assert.equal(node.metadata.properties.find((entry) => entry.key === 'speed').label, 'Run Speed');
  assert.deepEqual(node.metadata.handlers.map((entry) => entry.id), ['reset', 'interact']);
  assert.equal(node.exportedProperties.speed, 7);
  assert.equal(node.service('movement').move(), 'moved');
  assert.deepEqual(node.get_configuration_warnings(), ["Required node reference 'body' is not configured"]);
  const body = new Node({ runtimeId: 'scripts/body', name: 'Body' });
  node.defineReference('body', new NodeReference(body, true));
  assert.deepEqual(node.get_configuration_warnings(), ['Node reference \'body\' expects CharacterBody2D, received Node', "Node reference 'body' requires capability 'physics-body'"]);
  body._setRuntimeDescriptorInternal('CharacterBody2D', ['physics-body']);
  assert.deepEqual(node.get_configuration_warnings(), []);
  assert.throws(() => { node.scriptId = 'other'; }, TypeError);
});

test('multiple ScriptNodes coexist for distinct responsibilities while exclusive capability conflicts reject entry transactionally', () => {
  const registry = new ScriptRegistry();
  for (const [scriptId, exclusiveCapabilities] of [['move-a', ['movement-owner']], ['move-b', ['movement-owner']], ['health', ['damage-receiver']]]) {
    registry.registerDefinition({ descriptor: { scriptId, displayName: scriptId, sourcePath: `${scriptId}.ts`, exclusiveCapabilities, properties: [] }, factory });
  }
  const accepted = new Node({ runtimeId: 'scripts/accepted', name: 'Accepted' });
  accepted.add_child(registry.construct(context('move-a', 'scripts/move-a')));
  accepted.add_child(registry.construct(context('health', 'scripts/health')));
  const acceptedTree = new SceneTree();
  acceptedTree.setRoot(accepted);
  assert.equal(acceptedTree.indexedNodeCount, 3);
  acceptedTree.shutdown();

  const rejected = new Node({ runtimeId: 'scripts/rejected', name: 'Rejected' });
  rejected.add_child(registry.construct(context('move-a', 'scripts/rejected-a')));
  rejected.add_child(registry.construct(context('move-b', 'scripts/rejected-b')));
  const rejectedTree = new SceneTree();
  rejectedTree.setRoot(rejected);
  assert.equal(rejectedTree.indexedNodeCount, 0);
  assert.match(rejectedTree.diagnostics[0].message, /movement-owner.*exclusively owned/);
});

test('metadata resolution rejects missing bases, cycles, incompatible inherited properties, and duplicate signals', () => {
  const missing = new ScriptRegistry().registerDefinition({ descriptor: { scriptId: 'child', displayName: 'Child', sourcePath: '', extends: 'missing', properties: [] }, factory });
  assert.throws(() => missing.metadata('child'), /Unknown script 'missing'/);

  const cycle = new ScriptRegistry()
    .registerDefinition({ descriptor: { scriptId: 'a', displayName: 'A', sourcePath: '', extends: 'b', properties: [] }, factory })
    .registerDefinition({ descriptor: { scriptId: 'b', displayName: 'B', sourcePath: '', extends: 'a', properties: [] }, factory });
  assert.throws(() => cycle.metadata('a'), /inheritance cycle/);

  const incompatible = new ScriptRegistry()
    .registerDefinition({ descriptor: { scriptId: 'base', displayName: 'Base', sourcePath: '', properties: [property('value')] }, factory })
    .registerDefinition({ descriptor: { scriptId: 'child', displayName: 'Child', sourcePath: '', extends: 'base', properties: [property('value', 'string', 'x')] }, factory });
  assert.throws(() => incompatible.metadata('child'), /cannot change inherited property 'value' type/);

  const duplicateSignal = new ScriptRegistry()
    .registerDefinition({ descriptor: { scriptId: 'base', displayName: 'Base', sourcePath: '', properties: [], signals: [{ id: 'done' }] }, factory })
    .registerDefinition({ descriptor: { scriptId: 'child', displayName: 'Child', sourcePath: '', extends: 'base', properties: [], signals: [{ id: 'done' }] }, factory });
  assert.throws(() => duplicateSignal.metadata('child'), /duplicates inherited signal 'done'/);
});
