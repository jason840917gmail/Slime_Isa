import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

async function instantiate(document, services, nodeTypes = t.createCoreNodeTypeRegistry()) {
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => id === document.sceneId ? document : undefined);
  const packed = await new t.SceneResolver({ documents: loader, registry: descriptors }).prepare_scene(document.sceneId);
  const root = new t.SceneInstantiator({
    nodeTypes,
    scripts: t.createGameScriptRegistry(services),
    descriptors,
  }).instantiate_scene(packed, { runtimeNamespace: `fixture-${document.sceneId}` });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  return { root, tree, packed, loader };
}

function dispose(fixture) {
  fixture.tree.shutdown();
  fixture.packed.dispose();
  assert.equal(fixture.loader.activeLeaseCount(), 0);
}

function damageRequest(activationId, targetAreaNodeId, weaponTags, baseDamage) {
  return {
    activationId,
    sourceNodeId: 'weapon',
    attackAreaNodeId: 'weapon-area',
    targetAreaNodeId,
    weaponId: 'stone-axe',
    weaponTags,
    damageTypes: ['physical'],
    baseDamage,
    effects: [],
    impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
  };
}

test('resource nodes receive routed damage, enforce harvest tiers, and publish one depletion request', async () => {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const savedHealth = [];
  const destroyed = [];
  const hits = [];
  const blocked = [];
  const drops = [];
  const document = {
    version: 1,
    sceneId: 'object.resource-fixture',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Resource', type: 'StaticBody2D', parentId: null, order: 0, properties: {} },
      { id: 'damage-area', name: 'DamageArea', type: 'Area2D', parentId: 'root', order: 0, properties: {} },
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'root', order: 1, properties: { library: { resourceId: 'resource.animations' }, domain: 'physics', autoplay: 'tree-idle' } },
      {
        id: 'script', name: 'ResourceNodeScript', type: 'ScriptNode', scriptId: 'game.resource-node', parentId: 'root', order: 2,
        properties: {
          mapId: 'level-1', instanceId: 'tree-1', objectId: 'tree.world.solid', maxHealth: 10, initialHealth: 9,
          tags: ['wood', 'resource'], damageArea: { nodeId: 'damage-area' }, persistHealth: true,
          animation: { nodeId: 'animation' }, idleAnimationId: 'tree-idle', hitEffectId: 'wood-impact', onHitAnimationId: 'tree-hit', depletionMessage: 'Tree felled',
          harvestRequirement: { targetTag: 'wood', minimumTier: 1, failureMessage: 'Requires an Axe' },
          drop: { objectId: 'collectible.wood-pile', visualId: 'wood-pile', pieces: 2 },
          damageRule: { priority: 0, damageMultiplier: 1 },
        },
      },
    ],
    instances: [],
    subresources: [{
      version: 1,
      resourceId: 'resource.animations',
      kind: 'animation-library',
      animations: {
        'tree-idle': { durationSeconds: 1, framesPerSecond: 1, loop: true, tracks: [] },
        'tree-hit': { durationSeconds: 0.1, framesPerSecond: 10, loop: false, tracks: [] },
      },
    }],
  };
  const nodeTypes = t.createCoreNodeTypeRegistry().replace('AnimationPlayer', (context) => {
    const resourceId = context.properties.library.resourceId;
    const library = context.resources.get(resourceId);
    return new t.AnimationPlayerNode({
      runtimeId: context.runtimeId,
      name: context.name,
      domain: 'physics',
      animations: library.animations,
      autoplay: context.properties.autoplay,
      resolveBinding: () => { throw new Error('Fixture animations have no tracks'); },
    });
  });
  const fixture = await instantiate(document, {
    [t.DAMAGE_ROUTER_SERVICE]: router,
    [t.WORLD_OBJECT_STATE_SERVICE]: {
      load: () => undefined,
      saveHealth: (...args) => savedHealth.push(args),
      markDestroyed: (...args) => destroyed.push(args),
    },
    [t.RESOURCE_NODE_SERVICE]: {
      publishHit: (request) => hits.push(request),
      publishHarvestBlocked: (request) => blocked.push(request),
      spawnDrops: (request) => drops.push(request),
    },
  }, nodeTypes);
  const script = fixture.root.get_node('ResourceNodeScript');
  const animation = fixture.root.get_node('Animation');
  const targetAreaNodeId = fixture.root.get_node('DamageArea').runtimeId;
  assert.ok(script instanceof t.ResourceNodeScript);

  const blockedActivation = activations.begin('weapon', ['weapon-area']);
  const blockedOutcome = router.routeStep([
    damageRequest(blockedActivation, targetAreaNodeId, ['weapon'], 4),
  ], 0)[0];
  assert.equal(blockedOutcome.result.status, 'rejected');
  assert.equal(blockedOutcome.result.reason, 'state-blocked');
  assert.equal(script.health, 9);
  assert.equal(blocked.length, 1);
  assert.equal(blocked[0].message, 'Requires an Axe');

  const firstActivation = activations.begin('weapon', ['weapon-area']);
  const firstOutcome = router.routeStep([
    damageRequest(firstActivation, targetAreaNodeId, ['harvest:wood:1', 'weapon'], 4),
  ], 10)[0];
  assert.equal(firstOutcome.result.status, 'accepted');
  assert.equal(script.health, 5);
  assert.equal(animation.currentAnimation, 'tree-hit');
  fixture.tree.physicsProcess(0.2);
  assert.equal(animation.currentAnimation, 'tree-idle');
  assert.deepEqual(savedHealth, [['level-1', 'tree-1', 5, 10]]);
  assert.equal(hits.length, 1);
  assert.equal(hits[0].effectId, 'wood-impact');

  const finalActivation = activations.begin('weapon', ['weapon-area']);
  router.routeStep([damageRequest(finalActivation, targetAreaNodeId, ['harvest:wood:1', 'weapon'], 20)], 20);
  assert.equal(script.destroyed, true);
  assert.equal(script.health, 0);
  assert.deepEqual(destroyed, [['level-1', 'tree-1']]);
  assert.equal(drops.length, 1);
  assert.equal(drops[0].pieces, 2);
  assert.equal(drops[0].dropObjectId, 'collectible.wood-pile');

  const deadActivation = activations.begin('weapon', ['weapon-area']);
  const deadOutcome = router.routeStep([
    damageRequest(deadActivation, targetAreaNodeId, ['harvest:wood:1', 'weapon'], 1),
  ], 30)[0];
  assert.equal(deadOutcome.result.status, 'rejected');
  assert.equal(deadOutcome.result.reason, 'dead');
  assert.equal(drops.length, 1);
  dispose(fixture);
  assert.equal(router.hasArea(targetAreaNodeId), false);
});

test('collectibles delegate capacity-aware pickup and preserve remaining quantity', async () => {
  let remaining = 5;
  const requests = [];
  const document = {
    version: 1,
    sceneId: 'object.collectible-fixture',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Collectible', type: 'Node2D', parentId: null, order: 0, properties: { position: [32, 48] } },
      { id: 'pickup-area', name: 'PickupArea', type: 'Area2D', parentId: 'root', order: 0, properties: {} },
      {
        id: 'script', name: 'CollectibleScript', type: 'ScriptNode', scriptId: 'game.collectible', parentId: 'root', order: 1,
        properties: {
          mapId: 'level-1', instanceId: 'drop-1', objectId: 'collectible.wood-pile', itemId: 'wood', quantity: 5,
          sourceResourceInstanceId: 'tree-1', sourceInventoryDropId: 'inventory-drop-1', pickupArea: { nodeId: 'pickup-area' },
        },
      },
    ],
    instances: [],
  };
  const fixture = await instantiate(document, {
    [t.COLLECTIBLE_WORLD_SERVICE]: {
      ensureInitialized: (_mapId, _instanceId, quantity) => { remaining = Math.min(remaining, quantity); },
      remaining: () => remaining,
      pickup: (request) => {
        requests.push(request);
        const moved = Math.min(3, remaining);
        remaining -= moved;
        return { status: remaining === 0 ? 'collected' : 'partial', moved, remaining };
      },
    },
  });
  const script = fixture.root.get_node('CollectibleScript');
  assert.ok(script instanceof t.CollectibleScript);
  assert.deepEqual(script.requestPickup('player-area'), { status: 'partial', moved: 3, remaining: 2 });
  assert.deepEqual(script.requestPickup('player-area'), { status: 'collected', moved: 2, remaining: 0 });
  assert.equal(requests[0].sourceResourceInstanceId, 'tree-1');
  assert.equal(requests[0].sourceInventoryDropId, 'inventory-drop-1');
  assert.deepEqual({ x: requests[0].x, y: requests[0].y }, { x: 32, y: 48 });
  assert.equal(requests[1].requested, 2);
  dispose(fixture);
});

test('generic interactions publish domain-service outcomes without mutating world state directly', async () => {
  const requests = [];
  const document = {
    version: 1,
    sceneId: 'object.interaction-fixture',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Gate', type: 'Node2D', parentId: null, order: 0, properties: {} },
      {
        id: 'script', name: 'InteractionScript', type: 'ScriptNode', scriptId: 'game.interaction', parentId: 'root', order: 0,
        properties: { interactionId: 'verdant-gate', instanceId: 'gate-1', prompt: 'Unlock gate', priority: 90, action: { type: 'unlock-gate', itemId: 'green-key' } },
      },
    ],
    instances: [],
  };
  const fixture = await instantiate(document, {
    [t.WORLD_INTERACTION_SERVICE]: {
      execute: (request) => {
        requests.push(request);
        return { status: 'completed', navigationTarget: 'level-2' };
      },
    },
  });
  const script = fixture.root.get_node('InteractionScript');
  assert.ok(script instanceof t.InteractionScript);
  assert.deepEqual(script.requestInteraction('player'), { status: 'completed', navigationTarget: 'level-2' });
  assert.equal(requests[0].action.itemId, 'green-key');
  assert.equal(script.priority, 90);
  dispose(fixture);
});
