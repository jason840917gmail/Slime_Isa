import test from 'node:test';
import assert from 'node:assert/strict';
import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const scene = content.scenes.find((document) => document.sceneId === 'character.fatty-one-eye');

class TestCharacterBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
  collisionEnabled = true;
}

/** Reports its world-space shape like the game's CollisionShape2DNode (translation only). */
class TestCollisionShape extends t.Node2D {
  constructor(context) {
    super({ runtimeId: context.runtimeId, name: context.name, position: Array.isArray(context.properties.position) ? { x: context.properties.position[0], y: context.properties.position[1] } : undefined });
    this.value = context.resources.get(context.properties.shape?.resourceId)?.value;
  }

  worldShape() {
    const { x, y } = this.get_global_transform().position;
    const value = this.value;
    if (value.shape === 'circle') return { shapeId: this.runtimeId, shape: 'circle', centerX: x, centerY: y, radius: value.radius };
    if (value.shape === 'ellipse') return { shapeId: this.runtimeId, shape: 'ellipse', centerX: x, centerY: y, radiusX: value.radiusX, radiusY: value.radiusY };
    return { shapeId: this.runtimeId, shape: 'rectangle', x: x - value.width / 2, y: y - value.height / 2, width: value.width, height: value.height };
  }
}

async function instantiate(targetService = { getPrimaryTarget: () => undefined }) {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(scene.sceneId);
  const scripts = t.createGameScriptRegistry({
    [t.DAMAGE_ROUTER_SERVICE]: router,
    [t.ATTACK_ACTIVATION_SERVICE]: activations,
    [t.ENEMY_TARGET_SERVICE]: targetService,
  });
  const nodeTypes = t.createCoreNodeTypeRegistry().replace('CollisionShape2D', (context) => new TestCollisionShape(context)).replace('CharacterBody2D', (context) => new TestCharacterBody({
    runtimeId: context.runtimeId,
    name: context.name,
    position: Array.isArray(context.properties.position)
      ? { x: Number(context.properties.position[0]), y: Number(context.properties.position[1]) }
      : undefined,
  }));
  const root = new t.SceneInstantiator({
    nodeTypes, scripts, descriptors,
  }).instantiate_scene(packed, { runtimeNamespace: 'fatty-fixture' });
  const tree = new t.SceneTree(); tree.setRoot(root);
  return { activations, router, root, tree, packed };
}

function request(activationId, targetAreaNodeId, weaponId = 'wooden-spear') {
  return {
    activationId, sourceNodeId: 'player-weapon', attackAreaNodeId: 'player-swing', targetAreaNodeId,
    weaponId, weaponTags: ['melee', 'spear'], damageTypes: ['physical'], baseDamage: 12,
    effects: [{ effectId: 'knockback', potency: 1 }],
    impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
  };
}

test('Fatty is a boss-ranked EnemyScript with one eye receiver and common authoring references', async () => {
  const fixture = await instantiate();
  const script = fixture.root.get_node('FattyScript');
  assert.ok(script instanceof t.FattyScript);
  assert.ok(script instanceof t.EnemyScript);
  assert.equal(script.rank, 'boss');
  assert.equal(script.hp, 140);
  assert.equal(script.getReference('damageArea').configuredTarget.name, 'Eye');
  assert.equal(script.getReference('contactAttack').configuredTarget.name, 'ContactAttack');
  assert.equal(script.getReference('attackArea').configuredTarget.name, 'ContactAttack');
  assert.deepEqual(
    t.createGameDescriptorRegistry().scripts.get('game.fatty').extends,
    'game.enemy',
  );
  fixture.tree.shutdown(); fixture.packed.dispose();
});

test('Fatty enforces grounded eye weapon filtering and retries airborne state within one activation', async () => {
  const fixture = await instantiate();
  const script = fixture.root.get_node('FattyScript');
  const eye = fixture.root.get_node('Eye');
  const wrongActivation = fixture.activations.begin('player-weapon', ['player-swing']);
  const wrong = fixture.router.routeStep([request(wrongActivation, eye.runtimeId, 'wooden-club')], 0);
  assert.equal(wrong[0].result.reason, 'source-blocked');
  assert.equal(script.hp, 140);

  assert.equal(script.beginLeapTelegraph(10), true);
  assert.equal(script.beginAirborne(20), true);
  const activationId = fixture.activations.begin('player-weapon', ['player-swing']);
  const airborne = fixture.router.routeStep([request(activationId, eye.runtimeId)], 30);
  assert.deepEqual(airborne[0].result, {
    status: 'rejected', actualDamage: 0, reason: 'state-blocked', retryable: true,
  });
  assert.equal(script.hp, 140);
  assert.equal(script.land(1000), true);
  assert.equal(script.beginRecovery(1360), true);
  assert.equal(script.resumeChase(2060), true);
  const grounded = fixture.router.routeStep([request(activationId, eye.runtimeId)], 2061);
  assert.equal(grounded[0].result.status, 'accepted');
  assert.equal(grounded[0].result.actualDamage, 12);
  assert.deepEqual(grounded[0].result.appliedEffects, []);
  assert.deepEqual(grounded[0].result.rejectedEffects, [{ effectId: 'knockback', reason: 'immune' }]);
  assert.equal(script.hp, 128);
  fixture.tree.shutdown(); fixture.packed.dispose();
});

test('Fatty contact-hop state blocks eye damage and preserves its cooldown', async () => {
  const fixture = await instantiate();
  const script = fixture.root.get_node('FattyScript');
  const eye = fixture.root.get_node('Eye');
  assert.equal(script.requestContactHop(100), true);
  assert.equal(script.requestContactHop(101), false);
  const activationId = fixture.activations.begin('player-weapon', ['player-swing']);
  assert.equal(fixture.router.routeStep([request(activationId, eye.runtimeId)], 102)[0].result.reason, 'state-blocked');
  assert.equal(script.resumeChase(300), true);
  assert.equal(script.requestContactHop(1099), false);
  assert.equal(script.requestContactHop(1100), true);
  fixture.tree.shutdown(); fixture.packed.dispose();
});

test('Fatty fixed-step phases reuse enemy combat for contact hop and landing damage', async () => {
  const target = { position: { x: 20, y: 0 }, damageAreaNodeId: 'legacy-player-area', active: true, hostile: true };
  const fixture = await instantiate({ getPrimaryTarget: () => target });
  let hp = 100;
  let commits = 0;
  fixture.router.registerArea({
    runtimeNodeId: 'legacy-player',
    getDamageState: () => ({ hp, maxHp: 100, dead: hp <= 0 }),
    commitDamage: (commit) => { hp -= commit.result.actualDamage; commits += 1; },
  }, { areaNodeId: target.damageAreaNodeId, priority: 0, damageMultiplier: 1 });
  const script = fixture.root.get_node('FattyScript');
  const body = fixture.root;

  fixture.tree.physicsProcess(1 / 60);
  assert.equal(script.phase, 'contact-hop');
  assert.equal(body.collisionEnabled, false);
  fixture.tree.physicsProcess(0.25);
  assert.deepEqual({ hp, commits }, { hp: 82, commits: 1 });
  fixture.tree.physicsProcess(0.05);
  assert.equal(script.phase, 'chase');
  assert.equal(body.collisionEnabled, true);

  target.position = { x: 200, y: 0 };
  fixture.tree.physicsProcess(4.7);
  assert.equal(script.phase, 'small-hop');
  fixture.tree.physicsProcess(1.08);
  assert.equal(script.phase, 'airborne');
  assert.equal(body.collisionEnabled, false);
  fixture.tree.physicsProcess(0.5);
  assert.deepEqual(body.position, { x: 100, y: 0 });
  fixture.tree.physicsProcess(0.5);
  assert.equal(script.phase, 'landing');
  assert.deepEqual({ hp, commits }, { hp: 50, commits: 2 });
  fixture.tree.physicsProcess(0.36);
  assert.equal(script.phase, 'recovery');
  fixture.tree.physicsProcess(0.7);
  assert.equal(script.phase, 'chase');
  fixture.tree.shutdown(); fixture.packed.dispose();
});

test('Fatty warns where its leap lands, splashes only inside its landing zone, and cracks the ground', async () => {
  const target = { position: { x: 0, y: 0 }, damageAreaNodeId: 'legacy-player-area', active: true, hostile: true };
  const telegraphs = [];
  const cleared = [];
  const effects = [];
  const shakes = [];
  const fixture = await instantiate({
    getPrimaryTarget: () => target,
    showTelegraph: (request) => telegraphs.push(request),
    clearTelegraph: (sourceNodeId) => cleared.push(sourceNodeId),
    spawnImpactEffect: (request) => effects.push(request),
    shakeCamera: (request) => shakes.push(request),
  });
  const knockbacks = [];
  fixture.router.registerArea({
    runtimeNodeId: 'legacy-player',
    getDamageState: () => ({ hp: 100, maxHp: 100, dead: false }),
    commitDamage: (commit) => knockbacks.push(commit.result.appliedEffects.find((effect) => effect.effectId === 'knockback')?.potency),
  }, { areaNodeId: target.damageAreaNodeId, priority: 0, damageMultiplier: 1 });
  const script = fixture.root.get_node('FattyScript');

  // Leap toward (300, 0): the authored landing zone is shown there with the shadow, before Fatty arrives.
  target.position = { x: 300, y: 0 };
  assert.equal(script.beginLeapTelegraph(0), true);
  assert.equal(script.beginAirborne(10), true);
  assert.equal(telegraphs.length, 1);
  assert.deepEqual(telegraphs[0].shadow, { x: 300, y: 0 });
  assert.deepEqual(telegraphs[0].shapes.map(({ shape, centerX, centerY, radius }) => ({ shape, centerX, centerY, radius })), [{ shape: 'circle', centerX: 300, centerY: 0, radius: 106 }]);

  // The player steps just outside the zone before the landing: no damage, but the crack and shake still happen.
  fixture.root.set_global_transform({ ...fixture.root.get_global_transform(), position: { x: 300, y: 0 } });
  target.position = { x: 410, y: 0 };
  assert.equal(script.land(20), true);
  assert.deepEqual(knockbacks, []);
  assert.deepEqual(cleared.at(-1), script.runtimeId);
  assert.deepEqual(effects.at(-1), { effectId: 'boss-ground-crack', x: 300, y: 0 });
  assert.deepEqual(shakes, [{ durationMs: 100, intensity: 0.003 }]);

  // Inside the zone the landing hits with the stronger landing knockback.
  script.beginRecovery(30);
  script.resumeChase(40);
  script.beginLeapTelegraph(50);
  target.position = { x: 320, y: 0 };
  script.beginAirborne(60);
  script.land(70);
  assert.deepEqual(knockbacks, [280]);
  fixture.tree.shutdown(); fixture.packed.dispose();
});

test('the landing zone is an authored area Studio can show and resize', () => {
  const scene = content.scenes.find((document) => document.sceneId === 'character.fatty-one-eye');
  const script = scene.nodes.find((node) => node.scriptId === 'game.fatty');
  assert.deepEqual(script.properties.landingZone, { nodeId: 'landing-zone' });
  assert.equal(script.properties.landingRadius, undefined);
  const shape = scene.nodes.find((node) => node.parentId === 'landing-zone' && node.type === 'CollisionShape2D');
  assert.deepEqual(scene.subresources.find((resource) => resource.resourceId === shape.properties.shape.resourceId).value, { shape: 'circle', radius: 106 });
  assert.ok(content.scenes.some((document) => document.sceneId === `effect.${script.properties.landingEffectId}`), 'the landing effect scene exists');
});
