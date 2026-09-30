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
  assert.deepEqual(destroyed, [['level-1', 'tree-1', true]], 'a harvested tree starts its regrowth timer');
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

test('a Goo Heart is taken once when the player reaches it, and stays taken', async () => {
  const collected = [];
  const taken = new Set();
  let player = { x: 400, y: 100 };
  const heart = (heartId) => ({
    version: 1,
    sceneId: `object.goo-heart-fixture-${heartId}`,
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'GooHeart', type: 'Node2D', parentId: null, order: 0, properties: { position: [100, 100] } },
      { id: 'script', name: 'GooHeartScript', type: 'ScriptNode', scriptId: 'game.goo-heart', parentId: 'root', order: 0, properties: { heartId, radius: 36 } },
    ],
    instances: [],
  });
  const services = {
    [t.GOO_HEART_SERVICE]: {
      isCollected: (heartId) => taken.has(heartId),
      collect: (heartId, at) => { taken.add(heartId); collected.push([heartId, at.x, at.y]); },
      playerPosition: () => player,
    },
  };
  const fixture = await instantiate(heart('meadow-lakeside'), services);
  const script = fixture.root.get_node('GooHeartScript');
  assert.ok(script instanceof t.GooHeartScript);
  fixture.tree.process(0.1);
  assert.equal(script.collected, false, 'out of reach');
  player = { x: 120, y: 110 };
  fixture.tree.process(0.1);
  fixture.tree.process(0.1);
  assert.equal(script.collected, true);
  assert.deepEqual(collected, [['meadow-lakeside', 100, 100]], 'granted exactly once');
  dispose(fixture);

  const reloaded = await instantiate(heart('meadow-lakeside'), services);
  const again = reloaded.root.get_node('GooHeartScript');
  assert.equal(again.collected, true, 'a taken heart stays taken when its map loads again');
  reloaded.tree.process(0.1);
  assert.equal(collected.length, 1);
  dispose(reloaded);
});

test('story variants keep only the subtree that matches the flag, and follow it when it changes', async () => {
  const flags = new Set();
  const document = {
    version: 1, sceneId: 'object.story-variant-fixture', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Building', type: 'Node2D', parentId: null, order: 0, properties: {} },
      { id: 'variant', name: 'StoryVariantScript', type: 'ScriptNode', scriptId: 'game.story-variant', parentId: 'root', order: 0,
        properties: { flagId: 'workshop.restored', whenSet: { nodeId: 'restored' }, whenUnset: { nodeId: 'ruined' } } },
      { id: 'ruined', name: 'Ruined', type: 'Node2D', parentId: 'root', order: 1, properties: {} },
      { id: 'restored', name: 'Restored', type: 'Node2D', parentId: 'root', order: 2, properties: {} },
    ],
    instances: [],
  };
  const services = { [t.STORY_FLAG_SERVICE]: { setFlags: (ids) => ids.forEach((id) => flags.add(id)), hasFlag: (id) => flags.has(id) } };
  const fixture = await instantiate(document, services);
  fixture.tree.flushMutations();
  const script = fixture.root.get_node('StoryVariantScript');
  const ruined = script.getReference('whenUnset').configuredTarget;
  const restored = script.getReference('whenSet').configuredTarget;
  assert.equal(ruined.is_inside_tree(), true);
  assert.equal(restored.is_inside_tree(), false, 'the restored building is not there before the flag');
  script.setFlag();
  fixture.tree.flushMutations();
  assert.equal(flags.has('workshop.restored'), true, 'the set handler sets the flag');
  assert.equal(ruined.is_inside_tree(), false);
  assert.equal(restored.is_inside_tree(), true);
  dispose(fixture);

  // Loading with the flag already set shows the restored variant from the start.
  const again = await instantiate(document, services);
  again.tree.flushMutations();
  const againScript = again.root.get_node('StoryVariantScript');
  assert.equal(againScript.getReference('whenSet').configuredTarget.is_inside_tree(), true);
  assert.equal(againScript.getReference('whenUnset').configuredTarget.is_inside_tree(), false);
  dispose(again);
});

test('a pressure plate goes down under weight, shows its pressed frame, and a latching plate stays down', async () => {
  const { readFileSync } = await import('node:fs');
  const document = JSON.parse(readFileSync('src/game/content/scenes/authored/objects/pressure-plate.scene.json', 'utf8'));
  let weights = [];
  const fixture = await instantiate(document, { [t.PLATE_WEIGHT_SERVICE]: { weights: () => weights } });
  fixture.tree.flushMutations();
  const script = fixture.root.get_node('PressurePlateScript') ?? fixture.root.get_children().find((child) => child instanceof t.PressurePlateScript);
  const visual = script.getReference('visual').configuredTarget;
  // The core test registry builds Sprite2D as a plain Node2D: give it the authored frame the Phaser sprite has.
  visual.frame = document.nodes.find((node) => node.id === 'visual').properties.frame;
  const pressed = [];
  const listener = new t.Node({ runtimeId: 'plate-fixture/listener', name: 'Listener' });
  listener.registerSignalHandler('capture', (event) => pressed.push(event.plateId));
  fixture.root.add_child(listener);
  fixture.tree.flushMutations();
  script.getSignal('pressed').connect(listener, 'capture');
  fixture.tree.process(0.1);
  assert.equal(script.pressed, false);
  assert.equal(visual.frame, 6, 'raised');
  weights = [{ x: 10, y: 5 }];
  fixture.tree.process(0.1);
  assert.equal(script.pressed, true);
  assert.equal(visual.frame, 7, 'the pressed frame (its rune glows)');
  assert.deepEqual(pressed, ['plate']);
  weights = [];
  fixture.tree.process(0.1);
  assert.equal(script.pressed, true, 'the authored plate latches');
  assert.equal(visual.frame, 7);
  dispose(fixture);
});

test('a plate opens the gates named by its Opens Gate ID, with no scene connection', async () => {
  const gateText = { requiredItemId: 'green-key', prompt: 'Open', lockedPrompt: 'Locked', lockedMessage: 'Locked.', unlockedMessage: 'Open!' };
  const document = {
    version: 1, sceneId: 'world.plate-gate-fixture', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'World', type: 'Node2D', parentId: null, order: 0, properties: {} },
      { id: 'plate', name: 'Plate', type: 'Node2D', parentId: 'root', order: 0, properties: { position: [100, 100] } },
      { id: 'plate-script', name: 'PressurePlateScript', type: 'ScriptNode', scriptId: 'game.pressure-plate', parentId: 'plate', order: 0, properties: { plateId: 'p1', radius: 40, gateId: 'g1' } },
      { id: 'gate', name: 'Gate', type: 'Node2D', parentId: 'root', order: 1, properties: { position: [100, 0] } },
      { id: 'gate-script', name: 'GateScript', type: 'ScriptNode', scriptId: 'game.gate', parentId: 'gate', order: 0,
        properties: { ...gateText, mapId: 'fixture', gateId: 'g1', visual: { nodeId: 'gate-visual' }, doors: { nodeId: 'gate-doors' } } },
      { id: 'gate-visual', name: 'Visual', type: 'Node2D', parentId: 'gate', order: 1, properties: {} },
      { id: 'gate-doors', name: 'Doors', type: 'Node2D', parentId: 'gate', order: 2, properties: {} },
      { id: 'other', name: 'Other', type: 'Node2D', parentId: 'root', order: 2, properties: { position: [300, 0] } },
      { id: 'other-script', name: 'GateScript', type: 'ScriptNode', scriptId: 'game.gate', parentId: 'other', order: 0,
        properties: { ...gateText, mapId: 'fixture', gateId: 'g2', visual: { nodeId: 'other-visual' }, doors: { nodeId: 'other-doors' } } },
      { id: 'other-visual', name: 'Visual', type: 'Node2D', parentId: 'other', order: 1, properties: {} },
      { id: 'other-doors', name: 'Doors', type: 'Node2D', parentId: 'other', order: 2, properties: {} },
    ],
    instances: [],
  };
  let weights = [];
  const fixture = await instantiate(document, {
    [t.PLATE_WEIGHT_SERVICE]: { weights: () => weights },
    [t.GATE_LOCK_SERVICE]: { isUnlocked: () => false },
  });
  fixture.tree.flushMutations();
  const gate = fixture.root.get_node('Gate/GateScript');
  const other = fixture.root.get_node('Other/GateScript');
  fixture.tree.process(0.1);
  assert.equal(gate.isOpen, false);
  weights = [{ x: 105, y: 95 }];
  fixture.tree.process(0.1);
  assert.equal(gate.isOpen, true, 'the named gate opens');
  assert.equal(other.isOpen, false, 'other gates stay shut');
  dispose(fixture);
});

test('the Workshop is a ruin with a restoration site until its flag is set, then a Workshop station', async () => {
  const { readFileSync } = await import('node:fs');
  const document = JSON.parse(readFileSync('src/game/content/scenes/authored/objects/workshop.scene.json', 'utf8'));
  const flags = new Set();
  const services = { [t.STORY_FLAG_SERVICE]: { setFlags: (ids) => ids.forEach((id) => flags.add(id)), hasFlag: (id) => flags.has(id) } };
  const inTree = (fixture, Type) => {
    const found = [];
    const walk = (node) => { for (const child of node.get_children()) { if (child instanceof Type && child.is_inside_tree()) found.push(child); walk(child); } };
    walk(fixture.root);
    return found;
  };
  const ruin = await instantiate(document, services);
  ruin.tree.flushMutations();
  const [site] = inTree(ruin, t.RestorationSiteScript);
  assert.ok(site, 'the ruin carries a restoration site');
  assert.deepEqual(site.cost, [{ itemId: 'wood', count: 60 }, { itemId: 'stone', count: 40 }]);
  assert.equal(site.flagId, 'workshop.restored');
  assert.equal(site.objectId, 'workshop');
  assert.equal(site.questId, 'the-old-workshop');
  assert.equal(inTree(ruin, t.WorkbenchScript).length, 0, 'no station before the restoration');
  flags.add('workshop.restored');
  ruin.tree.process(0.016);
  ruin.tree.flushMutations();
  assert.equal(inTree(ruin, t.RestorationSiteScript).length, 0, 'the site leaves with the ruin');
  const [station] = inTree(ruin, t.WorkbenchScript);
  assert.deepEqual(station?.site, { station: 'workshop', tier: 1 });
  dispose(ruin);
});

test('cracked ground breaks once when the Heavy slime lands a jump on it; standing only makes it creak', async () => {
  const flags = new Set();
  const cracks = [];
  const creaks = [];
  let weights = [];
  let landing = { x: 900, y: 900, id: 4 };
  const crackDocument = {
    version: 1, sceneId: 'object.cracked-ground-fixture', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Ground', type: 'Node2D', parentId: null, order: 0, properties: { position: [200, 300] } },
      { id: 'crack', name: 'CrackedGroundScript', type: 'ScriptNode', scriptId: 'game.cracked-ground', parentId: 'root', order: 0, properties: { flagId: 'cracked.test', radius: 40 } },
    ],
    instances: [],
  };
  const services = {
    [t.PLATE_WEIGHT_SERVICE]: { weights: () => weights },
    [t.STORY_FLAG_SERVICE]: { setFlags: (ids) => ids.forEach((id) => flags.add(id)), hasFlag: (id) => flags.has(id) },
    [t.GROUND_CRACK_SERVICE]: { groundCracked: (at) => cracks.push(at), lastHeavyLanding: () => landing, groundCreaks: (at) => creaks.push(at) },
  };
  const crack = await instantiate(crackDocument, services);
  crack.tree.process(0.1);
  assert.equal(flags.has('cracked.test'), false, 'a light slime walks over it');
  weights = [{ x: 210, y: 310 }];
  crack.tree.process(0.1);
  assert.equal(flags.has('cracked.test'), false, 'standing on it in Heavy form is not enough');
  assert.deepEqual(creaks, [{ x: 200, y: 300 }], 'it creaks instead');
  landing = { x: 205, y: 310, id: 4 };
  crack.tree.process(0.1);
  assert.equal(flags.has('cracked.test'), false, 'a landing that happened before it loaded does not count');
  landing = { x: 205, y: 310, id: 5 };
  crack.tree.process(0.1);
  crack.tree.process(0.1);
  assert.equal(flags.has('cracked.test'), true, 'a Heavy jump landing breaks it');
  assert.deepEqual(cracks, [{ x: 200, y: 300 }], 'it breaks exactly once');
  dispose(crack);

  // With Requires Landing off, standing on it in Heavy form breaks it (the old rule).
  const standing = await instantiate({ ...crackDocument, nodes: crackDocument.nodes.map((node) => (node.id === 'crack'
    ? { ...node, properties: { ...node.properties, flagId: 'cracked.standing', requiresLanding: false } } : node)) }, services);
  standing.tree.process(0.1);
  assert.equal(flags.has('cracked.standing'), true);
  dispose(standing);
});

test('a web catches a normal slime; the Sticky form tears it open for good', async () => {
  const caught = [];
  const torn = [];
  const flags = new Set();
  let crosses = false;
  const webDocument = {
    version: 1, sceneId: 'object.spider-web-fixture', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Web', type: 'Node2D', parentId: null, order: 0, properties: { position: [100, 100] } },
      { id: 'visual', name: 'Visual', type: 'Node2D', parentId: 'root', order: 0, properties: {} },
      { id: 'script', name: 'SpiderWebScript', type: 'ScriptNode', scriptId: 'game.spider-web', parentId: 'root', order: 1, properties: { width: 100, depth: 40, visual: { nodeId: 'visual' } } },
    ],
    instances: [],
  };
  let player = { x: 100, y: 200 };
  const services = {
    [t.SPIDER_WEB_SERVICE]: { playerPosition: () => player, playerCrossesWebs: () => crosses, catchPlayer: (zone) => caught.push(zone), webTorn: (zone) => torn.push(zone) },
    [t.STORY_FLAG_SERVICE]: { setFlags: (ids) => ids.forEach((id) => flags.add(id)), hasFlag: (id) => flags.has(id) },
  };
  const web = await instantiate(webDocument, services);
  web.tree.flushMutations();
  const script = web.root.get_node('SpiderWebScript');
  const visual = web.root.get_node('Visual');
  visual.visible = true;
  web.tree.process(0.1);
  assert.equal(caught.length, 0, 'outside the web');
  player = { x: 120, y: 90 };
  web.tree.process(0.1);
  assert.deepEqual(caught, [{ x: 100, y: 80, halfWidth: 50, halfHeight: 20 }], 'a normal slime is caught');
  crosses = true;
  web.tree.process(0.1);
  assert.equal(script.torn, true, 'the Sticky form tears it');
  assert.equal(visual.visible, false, 'and it disappears');
  assert.equal(torn.length, 1);
  assert.equal(flags.size, 1, 'the tear is remembered');
  crosses = false;
  web.tree.process(0.1);
  assert.equal(caught.length, 1, 'a torn web never catches again, even when the form wears off');
  dispose(web);

  const again = await instantiate(webDocument, services);
  again.tree.flushMutations();
  assert.equal(again.root.get_node('SpiderWebScript').torn, true, 'it stays open after loading');
  dispose(again);
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
