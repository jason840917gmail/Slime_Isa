import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const sceneIds = [
  'character.lili',
  'character.mossy-scout',
  'character.red-slime-boy',
  'character.village-elder-plop',
  'character.yellow-blond-slime-girl',
];

class TestCharacterBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
}

class TestAnimationPlayer extends t.Node {
  currentAnimation;
  hasAnimation(animationId) {
    return ['idle', 'walk-down', 'walk-up', 'walk-left', 'walk-right'].includes(animationId);
  }
  play(animationId) { this.currentAnimation = animationId; }
}

async function instantiatePair(sceneId) {
  const scene = content.scenes.find((document) => document.sceneId === sceneId);
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const descriptors = t.createGameDescriptorRegistry();
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(scene.sceneId);
  const agents = [];
  const runtime = {
    acquire(request) {
      const record = { request, disposeCount: 0, steps: 0 };
      agents.push(record);
      return {
        initialState: t.createNpcWanderState(0, 'right'),
        step(state, input) {
          record.steps += 1;
          return {
            state: { ...state, phase: 'move', facing: 'right' },
            velocity: { x: input.speed, y: 0 },
            animation: 'walk-right',
          };
        },
        dispose() { record.disposeCount += 1; },
      };
    },
  };
  const scripts = t.createGameScriptRegistry({ [t.NPC_RUNTIME_SERVICE]: runtime });
  const nodeTypes = t.createCoreNodeTypeRegistry()
    .replace('CharacterBody2D', (context) => new TestCharacterBody({ runtimeId: context.runtimeId, name: context.name }))
    .replace('AnimationPlayer', (context) => new TestAnimationPlayer({ runtimeId: context.runtimeId, name: context.name }));
  const instantiator = new t.SceneInstantiator({ nodeTypes, scripts, descriptors });
  const first = instantiator.instantiate_scene(packed, { runtimeNamespace: `${sceneId}-first` });
  const second = instantiator.instantiate_scene(packed, { runtimeNamespace: `${sceneId}-second` });
  const firstTree = new t.SceneTree();
  const secondTree = new t.SceneTree();
  firstTree.setRoot(first);
  secondTree.setRoot(second);
  return { first, second, firstTree, secondTree, agents, packed, loader, resources };
}

for (const sceneId of sceneIds) {
  test(`${sceneId} owns independent wander and interaction-lock state`, async () => {
    const fixture = await instantiatePair(sceneId);
    const first = fixture.first.get_node('NpcScript');
    const second = fixture.second.get_node('NpcScript');
    assert.ok(first instanceof t.NpcScript);
    assert.ok(second instanceof t.NpcScript);
    assert.notEqual(first.runtimeId, second.runtimeId);
    assert.equal(first.is_in_group('npc'), true);
    assert.equal(first.is_in_group('interactable'), true);
    assert.equal(fixture.agents[0].request.characterId, sceneId.slice('character.'.length));

    fixture.firstTree.physicsProcess(1 / 60);
    assert.deepEqual(fixture.first.velocity, { x: first.wanderSpeed, y: 0 });
    assert.equal(fixture.first.get_node('Animation').currentAnimation, 'walk-right');
    assert.equal(fixture.agents[0].steps, 1);
    assert.equal(fixture.agents[1].steps, 0);

    const release = first.acquireInteractionLock();
    assert.equal(first.interactionLocked, true);
    fixture.firstTree.physicsProcess(1 / 60);
    assert.deepEqual(fixture.first.velocity, { x: 0, y: 0 });
    assert.equal(fixture.agents[0].steps, 1);
    release();
    assert.equal(first.interactionLocked, false);
    fixture.firstTree.physicsProcess(1 / 60);
    assert.equal(fixture.agents[0].steps, 2);

    first.setSimulationPaused(true);
    fixture.firstTree.physicsProcess(1 / 60);
    assert.deepEqual(fixture.first.velocity, { x: 0, y: 0 });
    fixture.firstTree.shutdown();
    fixture.secondTree.shutdown();
    fixture.packed.dispose();
    assert.deepEqual(fixture.agents.map((agent) => agent.disposeCount), [1, 1]);
    assert.equal(fixture.loader.activeLeaseCount(), 0);
    assert.equal(fixture.resources.activeLeaseCount(), 0);
  });
}
