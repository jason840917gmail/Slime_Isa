import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();

class TestBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
}

class TestArea extends t.Node2D {
  monitoring;
  monitorable;
  constructor(context) {
    super(context);
    this.monitoring = context.monitoring;
    this.monitorable = context.monitorable;
  }
}

class TestShape extends t.Node2D {
  disabled;
  constructor(context) {
    super(context);
    this.disabled = context.disabled;
  }
}

async function instantiate(sceneId, services = {}) {
  const scene = content.scenes.find((candidate) => candidate.sceneId === sceneId);
  assert.ok(scene, `missing ${sceneId}`);
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => content.scenes.find((candidate) => candidate.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((candidate) => candidate.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(sceneId);
  const nodeTypes = t.createCoreNodeTypeRegistry()
    .replace('CharacterBody2D', (context) => new TestBody({ runtimeId: context.runtimeId, name: context.name }))
    .replace('Area2D', (context) => new TestArea({ runtimeId: context.runtimeId, name: context.name, monitoring: context.properties.monitoring, monitorable: context.properties.monitorable }))
    .replace('CollisionShape2D', (context) => new TestShape({ runtimeId: context.runtimeId, name: context.name, disabled: context.properties.disabled }));
  const root = new t.SceneInstantiator({ nodeTypes, scripts: t.createGameScriptRegistry(services), descriptors }).instantiate_scene(packed, { runtimeNamespace: `fixture-${sceneId}` });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  return { root, tree, packed, loader, resources };
}

function dispose(fixture) {
  fixture.tree.shutdown();
  fixture.packed.dispose();
  assert.equal(fixture.loader.activeLeaseCount(), 0);
  assert.equal(fixture.resources.activeLeaseCount(), 0);
}

test('weapon scene drives directional hitbox windows and cooldown from one script', async () => {
  const fixture = await instantiate('weapon.basic-sword');
  const script = fixture.root.get_node('WeaponScript');
  const area = fixture.root.get_node('AttackArea');
  const shape = area.get_children().find((node) => node.name === 'right--primary');
  assert.ok(script instanceof t.WeaponScript);
  assert.equal(script.tryBeginAttack('right', 0), true);
  assert.equal(script.tryBeginAttack('right', 0), false);
  fixture.tree.physicsProcess(0.18);
  assert.equal(area.monitoring, true);
  assert.equal(shape.disabled, false);
  fixture.tree.physicsProcess(0.3);
  assert.equal(script.attacking, false);
  assert.equal(area.monitoring, false);
  assert.equal(script.tryBeginAttack('right', 480), false);
  assert.equal(script.tryBeginAttack('right', 1200), true);
  dispose(fixture);
});

test('projectile and effect scenes own finite lifetimes', async () => {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  let hp = 100;
  let damageSource;
  router.registerArea({
    runtimeNodeId: 'player',
    getDamageState: () => ({ hp, maxHp: 100, dead: false }),
    commitDamage: (commit) => {
      hp -= commit.result.actualDamage;
      damageSource = commit.request.sourceNodeId;
    },
  }, { areaNodeId: 'player-area', priority: 0, damageMultiplier: 1 });
  const projectile = await instantiate('projectile.worm-arrow', {
    [t.ATTACK_ACTIVATION_SERVICE]: activations,
    [t.DAMAGE_ROUTER_SERVICE]: router,
  });
  const projectileScript = projectile.root.get_node('ProjectileScript');
  assert.ok(projectileScript instanceof t.ProjectileScript);
  projectileScript.launch({ x: 3, y: 4 }, 180, {
    sourceNodeId: 'archer', damage: 15, knockbackStrength: 20, targetAreaNodeIds: ['player-area'],
  });
  assert.deepEqual(projectile.root.velocity, { x: 108, y: 144 });
  assert.equal(projectile.root.rotation, 0);
  assert.equal(projectile.root.get_node('Visual').rotation, Math.atan2(4, 3));
  projectile.root.get_node('AttackArea').getSignal('area_entered').emit({
    observerId: 'projectile-area', otherId: 'archer-area', observerKind: 'area', otherKind: 'area', shapes: [],
  });
  assert.equal(projectileScript.launched, true);
  assert.equal(hp, 100);
  projectile.root.get_node('AttackArea').getSignal('area_entered').emit({
    observerId: 'projectile-area', otherId: 'player-area', observerKind: 'area', otherKind: 'area', shapes: [],
  });
  assert.equal(hp, 85);
  assert.equal(damageSource, 'archer');
  projectile.tree.physicsProcess(0);
  assert.equal(projectile.root.is_freed(), true);
  projectile.packed.dispose();

  const effect = await instantiate('effect.basic-sword-impact');
  const effectScript = effect.root.get_node('EffectScript');
  assert.ok(effectScript instanceof t.EffectScript);
  assert.equal(effectScript.playing, true);
  effect.tree.physicsProcess(1);
  assert.equal(effect.root.is_freed(), true);
  effect.packed.dispose();
});
