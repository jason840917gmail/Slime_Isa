import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const STEP = 1 / 60;

class TestArea extends t.Node2D {
  monitoring;
  monitorable;
  /** Stand-in for the contact router's overlap query (Area2DNode.currentContacts). */
  currentContacts = [];
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

async function instantiateWeapon(sceneId) {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const enemy = { hp: 1000, commits: [] };
  router.registerArea({
    runtimeNodeId: 'enemy',
    getDamageState: () => ({ hp: enemy.hp, maxHp: 1000, dead: false }),
    commitDamage: (commit) => { enemy.hp -= commit.result.actualDamage; enemy.commits.push(commit); },
  }, { areaNodeId: 'enemy-area', priority: 0, damageMultiplier: 1 });
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => content.scenes.find((candidate) => candidate.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((candidate) => candidate.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(sceneId);
  const nodeTypes = t.createCoreNodeTypeRegistry()
    .replace('Area2D', (context) => new TestArea({ runtimeId: context.runtimeId, name: context.name, monitoring: context.properties.monitoring, monitorable: context.properties.monitorable }))
    .replace('CollisionShape2D', (context) => new TestShape({ runtimeId: context.runtimeId, name: context.name, disabled: context.properties.disabled }));
  const scripts = t.createGameScriptRegistry({
    [t.ATTACK_ACTIVATION_SERVICE]: activations,
    [t.DAMAGE_ROUTER_SERVICE]: router,
    [t.PLAYER_WEAPON_COMBAT_SERVICE]: {
      onAttackStarted: () => {},
      onAttackFinished: () => {},
      transformDamage: (damage) => damage,
      onOutcome: () => {},
    },
  });
  const root = new t.SceneInstantiator({ nodeTypes, scripts, descriptors }).instantiate_scene(packed, { runtimeNamespace: `hit-windows-${sceneId}` });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  const area = root.get_node('AttackArea');
  return {
    enemy, tree, area,
    script: root.get_node('WeaponScript'),
    shape: (name) => area.get_children().find((node) => node.name === name),
    dispose: () => { tree.shutdown(); packed.dispose(); },
  };
}

/**
 * Emulates the contact pass after a physics step: the enemy's area overlaps
 * every listed shape; only enabled shapes of a monitoring area report contacts.
 */
function reconcile(fixture, overlappingShapeNames) {
  const shapes = overlappingShapeNames
    .map((name) => fixture.shape(name))
    .filter((shape) => fixture.area.monitoring && !shape.disabled)
    .map((shape) => ({ observerShapeId: shape.runtimeId, otherShapeId: 'enemy-shape' }));
  const previous = fixture.area.currentContacts.length > 0;
  fixture.area.currentContacts = shapes.length > 0
    ? [{ observerId: fixture.area.runtimeId, otherId: 'enemy-area', observerKind: 'area', otherKind: 'area', shapes }]
    : [];
  if (!previous && shapes.length > 0) fixture.area.getSignal('area_entered').emit(fixture.area.currentContacts[0]);
}

function runAttack(fixture, overlappingShapeNames) {
  while (fixture.script.attacking) {
    fixture.tree.physicsProcess(STEP);
    reconcile(fixture, overlappingShapeNames);
  }
  fixture.tree.physicsProcess(STEP);
}

test('each hitbox window of a multi-hitbox attack lands on a target that stays inside the area', async () => {
  const fixture = await instantiateWeapon('weapon.goo-gauntlet');
  assert.equal(fixture.script.playAttack('right', { damage: 20, knockbackStrength: 100, cooldownMs: 320 }), true);
  runAttack(fixture, ['right--punch', 'right--impact']);
  assert.equal(fixture.enemy.commits.length, 2, 'punch and impact are separate windows');
  const [punch, impact] = fixture.enemy.commits;
  assert.equal(punch.result.actualDamage, 20);
  assert.deepEqual(punch.request.effects, [{ effectId: 'knockback', potency: 100 }]);
  // The impact window carries its own authored multipliers (0.35 damage, 0.6 knockback).
  assert.equal(impact.result.actualDamage, 7);
  assert.deepEqual(impact.request.effects, [{ effectId: 'knockback', potency: 60 }]);
  fixture.dispose();
});

test('a window never hits the same receiver twice', async () => {
  const fixture = await instantiateWeapon('weapon.goo-gauntlet');
  fixture.script.playAttack('right', { damage: 20, knockbackStrength: 0, cooldownMs: 320 });
  runAttack(fixture, ['right--punch']);
  assert.equal(fixture.enemy.commits.length, 1);
  fixture.dispose();
});

test('a target already overlapping when a window opens is hit without a new enter event', async () => {
  const fixture = await instantiateWeapon('weapon.basic-sword');
  // The enemy's area already overlaps the idle weapon area before the swing.
  fixture.area.currentContacts = [{ observerId: fixture.area.runtimeId, otherId: 'enemy-area', observerKind: 'area', otherKind: 'area', shapes: [] }];
  fixture.script.playAttack('right', { damage: 9, knockbackStrength: 0, cooldownMs: 100 });
  while (fixture.script.attacking) {
    fixture.tree.physicsProcess(STEP);
    const shape = fixture.shape('right--primary');
    // Contacts persist (no transition), only their shape list follows enabled shapes.
    fixture.area.currentContacts = [{
      observerId: fixture.area.runtimeId, otherId: 'enemy-area', observerKind: 'area', otherKind: 'area',
      shapes: fixture.area.monitoring && !shape.disabled ? [{ observerShapeId: shape.runtimeId, otherShapeId: 'enemy-shape' }] : [],
    }].filter((contact) => contact.shapes.length > 0);
  }
  assert.equal(fixture.enemy.commits.length, 1);
  assert.equal(fixture.enemy.commits[0].result.actualDamage, 9);
  fixture.dispose();
});

test('weapon timing follows its simulation clock, not an external wall clock', async () => {
  const fixture = await instantiateWeapon('weapon.basic-sword');
  assert.equal(fixture.script.tryBeginAttack('right'), true);
  const startedAt = fixture.script.simulationTime;
  // No physics steps (the tree is paused): the window never opens and the attack never ends.
  assert.equal(fixture.shape('right--primary').disabled, true);
  assert.equal(fixture.script.attacking, true);
  assert.equal(fixture.script.simulationTime, startedAt);
  fixture.tree.paused = true;
  fixture.tree.physicsProcess(STEP);
  fixture.tree.physicsProcess(STEP);
  assert.equal(fixture.script.simulationTime, startedAt);
  assert.equal(fixture.script.attacking, true);
  fixture.tree.paused = false;
  fixture.tree.physicsProcess(0.18);
  assert.equal(fixture.shape('right--primary').disabled, false);
  fixture.dispose();
});
