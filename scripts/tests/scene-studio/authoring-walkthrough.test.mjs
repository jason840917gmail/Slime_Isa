import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { createCoreDescriptorRegistry } = await loadTypescriptModule('src/game/content/scenes/propertyDescriptors.ts');
const { SceneDocumentState } = await loadTypescriptModule('src/game/editor/scene-studio/SceneDocumentState.ts');
const { sceneCommands } = await loadTypescriptModule('src/game/editor/scene-studio/SceneCommand.ts');
const animation = await loadTypescriptModule('src/game/editor/scene-studio/animation/AnimationClipModel.ts');
const { animatableProperties } = await loadTypescriptModule('src/game/editor/scene-studio/animation/AnimationTargets.ts');
const { AnimationClock } = await loadTypescriptModule('src/game/shared/animation/clock.ts');
const { sceneInspectorModel } = await loadTypescriptModule('src/game/editor/scene-studio/SceneInspector.ts');
const { AudioPreviewContext } = await loadTypescriptModule('src/game/editor/scene-studio/contexts/AudioContext.ts');
const { compatibleSignalConnections } = await loadTypescriptModule('src/game/editor/scene-studio/contexts/SignalContext.ts');
const { SceneDebugContext } = await loadTypescriptModule('src/game/editor/scene-studio/contexts/DebugContext.ts');

test('ordinary-enemy authoring uses only common nodes, resources, descriptors, and commands', () => {
  const registry = createCoreDescriptorRegistry();
  const document = { version: 1, sceneId: 'enemy.fixture', rootNodeId: 'root', nodes: [{ id: 'root', name: 'Enemy', type: 'Node2D', parentId: null, order: 0, properties: {} }], instances: [], subresources: [{ version: 1, resourceId: 'shape.body', kind: 'collision-shape', value: { shape: 'ellipse', radiusX: 9, radiusY: 6 } }] };
  const state = new SceneDocumentState(document, { registry });
  state.execute(sceneCommands.addNode({ id: 'body', name: 'Body', type: 'CharacterBody2D', parentId: 'root', order: 0, properties: {} }));
  state.execute(sceneCommands.addNode({ id: 'shape', name: 'Shape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: 'shape.body' } } }));
  state.execute(sceneCommands.addNode({ id: 'hurt-area', name: 'HurtArea', type: 'Area2D', parentId: 'root', order: 1, properties: {} }));
  const body = state.document.nodes.find((node) => node.id === 'body');
  const model = sceneInspectorModel(body, registry);
  assert.ok(model.groups.get('Properties').some((entry) => entry.descriptor.key === 'velocity'));
  assert.ok(animatableProperties(body, registry, 'physics').some((descriptor) => descriptor.key === 'velocity'));
  assert.equal(state.document.nodes.some((node) => /boss|fatty/i.test(`${node.type} ${node.name}`)), false);
  assert.equal(state.issues.length, 0);
});

test('animation timeline authors arbitrary typed tracks and seek-only preview stays silent', () => {
  let clip = { durationSeconds: 1, framesPerSecond: 10, loop: false, tracks: [], events: [] };
  clip = animation.addTrack(clip, '../body', 'velocity', { at: 0, value: [0, 0] });
  clip = animation.setKey(clip, 0, 4, [20, 0]);
  clip = animation.addEvent(clip, { at: 4, eventId: 'damage', gameplay: true }).clip;
  assert.equal(clip.tracks[0].keys.length, 2);
  assert.match(animation.clipDomainIssues(clip, 'render').join('\n'), /physics clock domain/);
  const events = [];
  const clock = new AnimationClock({ onEvent: (event) => events.push(event.eventId) });
  clock.start(clip, clip.events);
  clock.pause();
  clock.scrub(4);
  assert.deepEqual(events, []);
  clock.start(clip, clip.events);
  clock.update(500);
  assert.ok(events.includes('damage'));
});

test('audio, signals, and diagnostics remain generic selected-node contexts', () => {
  let stops = 0;
  const audio = new AudioPreviewContext();
  audio.preview(() => () => { stops += 1; });
  audio.preview(() => () => { stops += 1; });
  assert.equal(stops, 1);
  audio.stop();
  assert.equal(stops, 2);

  const registry = createCoreDescriptorRegistry([{
    scriptId: 'fixture.receiver', displayName: 'Receiver', sourcePath: 'Receiver.ts', properties: [], handlers: [{ id: 'on_enter', payload: 'PhysicsContact' }],
  }]);
  const source = { id: 'area', name: 'Area', type: 'Area2D', parentId: 'root', order: 0, properties: {} };
  const target = { id: 'receiver', name: 'Receiver', type: 'ScriptNode', scriptId: 'fixture.receiver', parentId: 'root', order: 1, properties: {} };
  assert.ok(compatibleSignalConnections(source, target, registry).some((entry) => entry.signal === 'body_entered' && entry.handler === 'on_enter'));

  const debug = new SceneDebugContext();
  debug.reportLifecycle(new Error('ready failed'));
  debug.reportUnresolved('root/missing');
  debug.setActiveResources(3);
  assert.deepEqual(debug.snapshot([]), { validation: [], lifecycleErrors: ['ready failed'], unresolvedReferences: ['root/missing'], activeResources: 3 });
});
