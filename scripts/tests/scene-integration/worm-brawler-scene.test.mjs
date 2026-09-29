import test from 'node:test';
import assert from 'node:assert/strict';
import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const scene = content.scenes.find((document) => document.sceneId === 'character.worm-brawler');

class TestCharacterBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
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
  const nodeTypes = t.createCoreNodeTypeRegistry().replace('CharacterBody2D', (context) => new TestCharacterBody({
    runtimeId: context.runtimeId,
    name: context.name,
    position: Array.isArray(context.properties.position)
      ? { x: Number(context.properties.position[0]), y: Number(context.properties.position[1]) }
      : undefined,
  }));
  const root = new t.SceneInstantiator({
    nodeTypes, scripts, descriptors,
  }).instantiate_scene(packed, { runtimeNamespace: 'worm-fixture' });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  return { activations, router, root, tree, packed, loader, resources };
}

function request(activationId, targetAreaNodeId, damage) {
  return {
    activationId,
    sourceNodeId: 'player-weapon',
    attackAreaNodeId: 'player-swing',
    targetAreaNodeId,
    weaponId: 'wooden-spear',
    weaponTags: ['melee', 'spear'],
    damageTypes: ['physical'],
    baseDamage: damage,
    effects: [],
    impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
  };
}

test('Worm Brawler resolves through the universal enemy script, damage router, and reward signal', async () => {
  const fixture = await instantiate();
  const script = fixture.root.get_node('EnemyScript');
  const damageArea = fixture.root.get_node('DamageArea');
  assert.ok(script instanceof t.EnemyScript);
  assert.equal(script.rank, 'ordinary');
  assert.equal(script.faction, 'hostile');
  assert.equal(script.hp, 55);
  assert.equal(script.canTarget({ x: 0, y: 0 }, { x: 240, y: 0 }, true), true);
  assert.equal(script.isInAttackRange({ x: 0, y: 0 }, { x: 35, y: 0 }), false);
  assert.equal(script.getReference('attackArea').configuredTarget.name, 'AttackArea');
  assert.deepEqual(script.movementToward({ x: 0, y: 0 }, { x: 3, y: 4 }, script.movementSpeed), {
    x: 0.6, y: 0.8, speed: 130,
  });

  const listener = new t.Node({ runtimeId: 'test/listener', name: 'Listener' });
  let rewards = 0;
  listener.registerSignalHandler('reward', () => { rewards += 1; });
  fixture.root.add_child(listener);
  fixture.tree.flushMutations();
  script.getSignal('reward_requested').connect(listener, 'reward');

  const firstActivation = fixture.activations.begin('player-weapon', ['player-swing']);
  const first = fixture.router.routeStep([request(firstActivation, damageArea.runtimeId, 10)], 100);
  assert.equal(first[0].result.status, 'accepted');
  assert.equal(script.hp, 45);
  const duplicate = fixture.router.routeStep([request(firstActivation, damageArea.runtimeId, 10)], 101);
  assert.equal(duplicate[0].result.reason, 'duplicate');
  assert.equal(script.hp, 45);

  const fatalActivation = fixture.activations.begin('player-weapon', ['player-swing']);
  const fatal = fixture.router.routeStep([request(fatalActivation, damageArea.runtimeId, 999)], 200);
  assert.equal(fatal[0].result.actualDamage, 45);
  assert.equal(fatal[0].result.defeated, true);
  assert.equal(script.defeated, true);
  assert.equal(rewards, 1);

  const afterDeath = fixture.activations.begin('player-weapon', ['player-swing']);
  assert.equal(fixture.router.routeStep([request(afterDeath, damageArea.runtimeId, 1)], 201)[0].result.reason, 'dead');
  assert.equal(rewards, 1);
  fixture.tree.shutdown();
  fixture.packed.dispose();
  assert.equal(fixture.loader.activeLeaseCount(), 0);
  assert.equal(fixture.resources.activeLeaseCount(), 0);
});

test('Worm attack lifecycle preserves cooldown, cancellation, and sequence identity', async () => {
  const fixture = await instantiate();
  const script = fixture.root.get_node('EnemyScript');
  const first = script.tryBeginAttack(0);
  assert.equal(first, 1);
  assert.equal(script.tryBeginAttack(500), undefined);
  script.finishAttack(first);
  assert.equal(script.tryBeginAttack(1099), undefined);
  assert.equal(script.tryBeginAttack(1100), 2);
  script.cancelAttack();
  assert.equal(script.tryBeginAttack(1101), undefined);
  fixture.tree.shutdown();
  fixture.packed.dispose();
});

test('Worm fixed-step behavior chases and routes one timed contact attack through the shared damage pipeline', async () => {
  const target = { position: { x: 100, y: 0 }, damageAreaNodeId: 'legacy-player-area', active: true, hostile: true };
  const effects = [];
  const fixture = await instantiate({ getPrimaryTarget: () => target, spawnImpactEffect: (request) => effects.push(request) });
  let hp = 100;
  let commits = 0;
  fixture.router.registerArea({
    runtimeNodeId: 'legacy-player',
    getDamageState: () => ({ hp, maxHp: 100, dead: hp <= 0 }),
    commitDamage: (commit) => { hp -= commit.result.actualDamage; commits += 1; },
  }, { areaNodeId: target.damageAreaNodeId, priority: 0, damageMultiplier: 1 });
  const script = fixture.root.get_node('EnemyScript');
  const body = fixture.root;
  fixture.tree.physicsProcess(1 / 60);
  assert.equal(script.runtimeState, 'chase');
  assert.deepEqual(body.velocity, { x: 130, y: 0 });

  target.position = { x: 20, y: 0 };
  fixture.tree.physicsProcess(1 / 60);
  assert.equal(script.runtimeState, 'attack');
  assert.deepEqual(body.velocity, { x: 0, y: 0 });
  fixture.tree.physicsProcess(0.25);
  assert.equal(commits, 1);
  assert.equal(hp, 48);
  assert.deepEqual(effects, [{ effectId: 'enemy-worm-brawler-hit', x: 22, y: 0 }]);
  fixture.tree.physicsProcess(0.25);
  // The committed sequence lasts max(windup + recovery, clip) + 250 ms.
  assert.equal(script.attacking, true);
  fixture.tree.physicsProcess(0.26);
  assert.equal(script.attacking, false);
  assert.equal(commits, 1);
  assert.equal(effects.length, 1);
  fixture.tree.shutdown();
  fixture.packed.dispose();
});

test('Worm impact visual resolves to one authored effect scene that embeds its visual resources', () => {
  const effect = content.scenes.find((document) => document.sceneId === 'effect.enemy-worm-brawler-hit');
  assert.ok(effect);
  assert.equal(effect.nodes.find((node) => node.scriptId === 'game.effect')?.properties.effectId, 'enemy-worm-brawler-hit');
  const embedded = (effect.subresources ?? []).filter((resource) => resource.kind !== 'audio').map((resource) => resource.resourceId).sort();
  assert.deepEqual(embedded, ['effect.enemy.worm-brawler-hit.animations', 'effect.enemy.worm-brawler-hit.sprite']);
  assert.deepEqual((effect.subresources ?? []).filter((resource) => resource.kind === 'audio').map((resource) => resource.resourceId), ['sfx.weapon.hit-punch']);
  assert.ok(!content.resources.some((resource) => embedded.includes(resource.resourceId)), 'single-owner visual resources are not also shared files');
});
