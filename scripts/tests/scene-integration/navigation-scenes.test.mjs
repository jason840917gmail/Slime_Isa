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
