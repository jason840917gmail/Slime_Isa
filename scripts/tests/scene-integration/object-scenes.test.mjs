import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();

async function instantiate(sceneId, runtimeNamespace, mapId, instanceId) {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => content.scenes.find((candidate) => candidate.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((candidate) => candidate.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(sceneId);
  const collectibleRemaining = new Map();
  const collectibleRequests = [];
  const root = new t.SceneInstantiator({
    nodeTypes: t.createCoreNodeTypeRegistry(),
    scripts: t.createGameScriptRegistry({
      [t.DAMAGE_ROUTER_SERVICE]: router,
      [t.WORLD_OBJECT_STATE_SERVICE]: { load: () => undefined, saveHealth() {}, markDestroyed() {} },
      [t.RESOURCE_NODE_SERVICE]: { publishHit() {}, publishHarvestBlocked() {}, spawnDrops() {} },
      [t.COLLECTIBLE_WORLD_SERVICE]: {
        ensureInitialized: (_mapId, currentInstanceId, quantity) => collectibleRemaining.set(currentInstanceId, quantity),
        remaining: (_mapId, currentInstanceId) => collectibleRemaining.get(currentInstanceId) ?? 0,
        pickup: (request) => {
          collectibleRequests.push(request);
          collectibleRemaining.set(request.instanceId, 0);
          return { status: 'collected', moved: request.requested, remaining: 0 };
        },
      },
    }),
    descriptors,
  }).instantiate_scene(packed, {
    runtimeNamespace,
    persistenceKey: `${mapId}.${instanceId}`,
    propertyOverrides: [
      { nodeId: 'script', property: 'mapId', value: mapId },
      { nodeId: 'script', property: 'instanceId', value: instanceId },
    ],
  });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  return { root, tree, packed, loader, resources, router, collectibleRequests };
}

for (const [sceneId, itemId, quantity] of [
  ['object.collectible-charcoal-pile', 'charcoal', 5],
  ['object.collectible-crystal-shard', 'shard', 1],
  ['object.collectible-energy-potion', 'energy-potion', 1],
  ['object.collectible-green-key', 'green-key', 1],
  ['object.collectible-hp-potion', 'hp-potion', 1],
  ['object.collectible-iron-ore-pile', 'iron-ore', 5],
  ['object.collectible-purple-berry', 'purple-berry-mat', 1],
  ['object.collectible-silk-clump', 'silk-clump', 1],
  ['object.collectible-small-stone-pile', 'stone', 5],
  ['object.collectible-small-wood-pile', 'wood', 5],
  ['object.collectible-stone-pile', 'stone', 10],
  ['object.collectible-wood-pile', 'wood', 10],
]) {
  test(`${sceneId} mounts an isolated transactional pickup`, async () => {
    const fixture = await instantiate(sceneId, `${sceneId}-fixture`, 'level-1', 'pickup-1');
    const script = fixture.root.get_node('CollectibleScript');
    const pickupArea = fixture.root.get_node('PickupArea');
    assert.ok(script instanceof t.CollectibleScript);
    assert.equal(script.mapId, 'level-1');
    assert.equal(script.instanceId, 'pickup-1');
    assert.equal(script.itemId, itemId);
    assert.equal(script.quantity, quantity);
    assert.equal(pickupArea.has_runtime_capability('area'), true);
    assert.deepEqual(script.requestPickup('player/pickup-area'), {
      status: 'collected', moved: quantity, remaining: 0,
    });
    assert.equal(fixture.collectibleRequests[0].collectorAreaNodeId, 'player/pickup-area');
    dispose(fixture);
  });
}

function dispose(fixture) {
  fixture.tree.shutdown();
  fixture.packed.dispose();
  assert.equal(fixture.loader.activeLeaseCount(), 0);
  assert.equal(fixture.resources.activeLeaseCount(), 0);
}

for (const sceneId of [
  'object.resource-stone-node',
  'object.resource-stone-node.big-stone-mine',
  'object.rock-amber-ore-mineable',
  'object.tree-world-solid',
  'object.tree-world-solid.tree-autumn-01',
]) {
  test(`${sceneId} mounts independent persistent resource state through placement overrides`, async () => {
    const first = await instantiate(sceneId, `${sceneId}-first`, 'level-1', 'stone-1');
    const second = await instantiate(sceneId, `${sceneId}-second`, 'level-2', 'stone-2');
    const firstScript = first.root.get_node('ResourceNodeScript');
    const secondScript = second.root.get_node('ResourceNodeScript');
    assert.ok(firstScript instanceof t.ResourceNodeScript);
    assert.ok(secondScript instanceof t.ResourceNodeScript);
    assert.equal(firstScript.mapId, 'level-1');
    assert.equal(firstScript.instanceId, 'stone-1');
    assert.equal(secondScript.mapId, 'level-2');
    assert.equal(secondScript.instanceId, 'stone-2');
    assert.equal(first.root.explicitPersistenceKey, 'level-1.stone-1');
    assert.equal(first.router.hasArea(first.root.get_node('DamageArea').runtimeId), true);
    dispose(first);
    dispose(second);
  });
}

test('object.rock-amber-ore-mineable owns persistent ore health and a shard drop', async () => {
  const fixture = await instantiate('object.rock-amber-ore-mineable', 'amber-fixture', 'test-rectangle', 'amber-rock-001');
  const script = fixture.root.get_node('ResourceNodeScript');
  assert.ok(script instanceof t.ResourceNodeScript);
  assert.equal(script.maxHealth, 30);
  assert.deepEqual(script.tags, ['rock', 'solid', 'mineable']);
  assert.deepEqual(script.dropDefinition, {
    objectId: 'collectible.crystal-shard', visualId: 'crystal-shard', pieces: 1,
  });
  assert.equal(fixture.router.hasArea(fixture.root.get_node('DamageArea').runtimeId), true);
  dispose(fixture);
});
