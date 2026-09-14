import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const scene = JSON.parse(await readFile(
  `${REPOSITORY_ROOT}/src/game/content/scenes/authored/characters/worm-brawler.scene.json`,
  'utf8',
));

async function instantiate() {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const packed = await new t.SceneResolver({ documents: loader, registry: descriptors }).prepare_scene(scene.sceneId);
  const scripts = t.createGameScriptRegistry({ [t.DAMAGE_ROUTER_SERVICE]: router });
  const root = new t.SceneInstantiator({
    nodeTypes: t.createCoreNodeTypeRegistry(), scripts, descriptors,
  }).instantiate_scene(packed, { runtimeNamespace: 'worm-fixture' });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  return { activations, router, root, tree, packed, loader };
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

