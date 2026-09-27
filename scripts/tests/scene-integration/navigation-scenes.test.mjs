import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

test('WorldExitScript delegates navigation and gate decisions through one typed service', async () => {
  const document = {
    version: 1,
    sceneId: 'world.exit-fixture',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
      { id: 'exit', name: 'Exit', type: 'Area2D', parentId: 'root', order: 0, properties: {} },
      {
        id: 'script', name: 'WorldExitScript', type: 'ScriptNode', scriptId: 'game.world-exit', parentId: 'exit', order: 0,
        properties: {
          mapId: 'level-1', exitId: 'exit-1', targetAreaId: 'gloop-forest', entry: 'west', area: { nodeId: 'exit' },
          gate: { id: 'verdant-gate', requiredItemId: 'green-key', consumeOnUnlock: true, lockedMessage: 'Locked' },
        },
      },
    ],
    instances: [],
    connections: [{ source: { nodeId: 'exit' }, signal: 'body_entered', target: { nodeId: 'script' }, handler: 'on_body_entered' }],
  };
  const requests = [];
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async () => document);
  const packed = await new t.SceneResolver({ documents: loader, registry: descriptors }).prepare_scene(document.sceneId);
  const root = new t.SceneInstantiator({
    nodeTypes: t.createCoreNodeTypeRegistry(),
    scripts: t.createGameScriptRegistry({
      [t.WORLD_EXIT_SERVICE]: { requestExit: (request) => { requests.push(request); return { status: 'queued' }; } },
    }),
    descriptors,
  }).instantiate_scene(packed, { runtimeNamespace: 'exit-fixture' });
  const outcomes = [];
  const listener = new t.Node({ runtimeId: 'exit-fixture/listener', name: 'Listener' });
  listener.registerSignalHandler('capture', (result) => outcomes.push(result));
  root.add_child(listener);
  const tree = new t.SceneTree();
  tree.setRoot(root);
  root.get_node('Exit/WorldExitScript').getSignal('navigation_resolved').connect(listener, 'capture');
  // Past the arrival grace so entering bodies are evaluated.
  tree.physicsProcess(1);
  root.get_node('Exit').getSignal('body_entered').emit({
    observerId: 'exit-fixture/exit', otherId: 'enemy/damage-area', observerKind: 'area', otherKind: 'area', shapes: [],
  });
  assert.deepEqual(requests, []);
  assert.deepEqual(outcomes, []);
  root.get_node('Exit').getSignal('body_entered').emit({
    observerId: 'exit-fixture/exit', otherId: 'player/body', observerKind: 'area', otherKind: 'character-body', shapes: [],
  });
  assert.deepEqual(requests, [{
    mapId: 'level-1', exitId: 'exit-1', targetAreaId: 'gloop-forest', entry: 'west', actorNodeId: 'player/body',
    gate: { id: 'verdant-gate', requiredItemId: 'green-key', consumeOnUnlock: true, lockedMessage: 'Locked' },
  }]);
  assert.deepEqual(outcomes, [{ status: 'queued' }]);
  tree.shutdown();
  packed.dispose();
  assert.equal(loader.activeLeaseCount(), 0);
});

class TestArea extends t.Node2D {
  currentContacts = [];
}

async function instantiateExit(requestExit) {
  const document = {
    version: 1,
    sceneId: 'world.exit-overlap-fixture',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
      { id: 'exit', name: 'Exit', type: 'Area2D', parentId: 'root', order: 0, properties: {} },
      {
        id: 'script', name: 'WorldExitScript', type: 'ScriptNode', scriptId: 'game.world-exit', parentId: 'exit', order: 0,
        properties: {
          mapId: 'level-1', exitId: 'exit-1', targetAreaId: 'gloop-forest', entry: 'west', area: { nodeId: 'exit' },
          gate: { id: 'verdant-gate', requiredItemId: 'green-key', consumeOnUnlock: true, lockedMessage: 'Locked' },
        },
      },
    ],
    instances: [],
    connections: [{ source: { nodeId: 'exit' }, signal: 'body_entered', target: { nodeId: 'script' }, handler: 'on_body_entered' }],
  };
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async () => document);
  const packed = await new t.SceneResolver({ documents: loader, registry: descriptors }).prepare_scene(document.sceneId);
  const root = new t.SceneInstantiator({
    nodeTypes: t.createCoreNodeTypeRegistry().replace('Area2D', (context) => new TestArea({ runtimeId: context.runtimeId, name: context.name })),
    scripts: t.createGameScriptRegistry({ [t.WORLD_EXIT_SERVICE]: { requestExit } }),
    descriptors,
  }).instantiate_scene(packed, { runtimeNamespace: 'exit-overlap' });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  const area = root.get_node('Exit');
  const script = root.get_node('Exit/WorldExitScript');
  return { tree, area, script, dispose: () => { tree.shutdown(); packed.dispose(); } };
}

const playerInside = { observerId: 'exit-overlap/exit', otherId: 'player/body', observerKind: 'area', otherKind: 'character-body', shapes: [] };

test('an exit triggers once its gate unlocks while the player keeps standing inside', async () => {
  let hasKey = false;
  const requests = [];
  const fixture = await instantiateExit((request) => {
    requests.push(request.actorNodeId);
    return hasKey ? { status: 'queued' } : { status: 'blocked', message: 'Locked' };
  });
  fixture.tree.physicsProcess(1);
  fixture.area.currentContacts = [playerInside];
  fixture.area.getSignal('body_entered').emit(playerInside);
  assert.equal(requests.length, 1, 'locked on entry');
  fixture.tree.physicsProcess(1 / 60);
  assert.equal(requests.length, 2, 'still re-evaluated while overlapping');
  hasKey = true;
  fixture.tree.physicsProcess(1 / 60);
  assert.equal(requests.length, 3);
  fixture.tree.physicsProcess(1 / 60);
  fixture.tree.physicsProcess(1 / 60);
  assert.equal(requests.length, 3, 'a queued navigation is not requested again');
  fixture.dispose();
});

test('an actor already inside an exit when it mounts navigates after the arrival grace, not during it', async () => {
  const requests = [];
  const fixture = await instantiateExit((request) => { requests.push(request.actorNodeId); return { status: 'queued' }; });
  fixture.area.currentContacts = [playerInside];
  fixture.area.getSignal('body_entered').emit(playerInside);
  const graceSteps = Math.floor(fixture.script.arrivalGraceMs / (1000 / 60)) - 1;
  for (let index = 0; index < graceSteps; index += 1) fixture.tree.physicsProcess(1 / 60);
  assert.deepEqual(requests, [], 'arrival grace suppresses the exit');
  for (let index = 0; index < 3; index += 1) fixture.tree.physicsProcess(1 / 60);
  assert.deepEqual(requests, ['player/body']);
  fixture.dispose();
});
