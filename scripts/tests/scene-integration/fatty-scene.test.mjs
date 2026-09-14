import test from 'node:test';
import assert from 'node:assert/strict';
import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const scene = content.scenes.find((document) => document.sceneId === 'character.fatty-one-eye');

async function instantiate() {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(scene.sceneId);
  const scripts = t.createGameScriptRegistry({ [t.DAMAGE_ROUTER_SERVICE]: router });
  const root = new t.SceneInstantiator({
    nodeTypes: t.createCoreNodeTypeRegistry(), scripts, descriptors,
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
