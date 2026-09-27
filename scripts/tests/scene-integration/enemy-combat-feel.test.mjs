import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const STEP = 1 / 60;

class TestCharacterBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
}

class TestSprite extends t.Node2D {
  flipX = false;
  tint = undefined;
  setTintFill(color) { this.tint = color; return this; }
  clearTint() { this.tint = undefined; return this; }
}

function position(context) {
  return Array.isArray(context.properties.position)
    ? { x: Number(context.properties.position[0]), y: Number(context.properties.position[1]) }
    : undefined;
}

async function instantiateEnemy(sceneId, targetService, { animationOverrides = {} } = {}) {
  const scene = content.scenes.find((document) => document.sceneId === sceneId);
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const descriptors = t.createGameDescriptorRegistry();
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(scene.sceneId);
  const scripts = t.createGameScriptRegistry({
    [t.DAMAGE_ROUTER_SERVICE]: router,
    [t.ATTACK_ACTIVATION_SERVICE]: activations,
    [t.ENEMY_TARGET_SERVICE]: targetService,
  });
  const nodeTypes = t.createCoreNodeTypeRegistry()
    .replace('CharacterBody2D', (context) => new TestCharacterBody({ runtimeId: context.runtimeId, name: context.name, position: position(context) }))
    .replace('Sprite2D', (context) => new TestSprite({ runtimeId: context.runtimeId, name: context.name, position: position(context) }))
    .replace('AnimationPlayer', (context) => {
      const library = context.resources.get(context.properties.library.resourceId);
      // Property tracks target the Phaser sprite; the gameplay clock only needs timing.
      const animations = Object.fromEntries(Object.entries(library.animations)
        .map(([name, animation]) => [name, { ...animation, tracks: [], ...(animationOverrides[name] ?? {}) }]));
      return new t.AnimationPlayerNode({
        runtimeId: context.runtimeId,
        name: context.name,
        domain: 'physics',
        animations,
        autoplay: context.properties.autoplay,
        resolveBinding: () => { throw new Error('Fixture animations have no tracks'); },
      });
    });
  const root = new t.SceneInstantiator({ nodeTypes, scripts, descriptors }).instantiate_scene(packed, { runtimeNamespace: `${sceneId}-feel` });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  const dispose = () => { tree.shutdown(); packed.dispose(); };
  const script = root.get_children().find((node) => node instanceof t.EnemyScript);
  return { activations, router, root, tree, dispose, script, visual: root.get_node('Visual'), animation: root.get_node('Animation') };
}

function registerPlayer(router, areaNodeId) {
  const player = { hp: 1000, commits: [] };
  router.registerArea({
    runtimeNodeId: 'test-player',
    getDamageState: () => ({ hp: player.hp, maxHp: 1000, dead: player.hp <= 0 }),
    commitDamage: (commit) => { player.hp -= commit.result.actualDamage; player.commits.push(commit); },
  }, { areaNodeId, priority: 0, damageMultiplier: 1 });
  return player;
}

function hitEnemy(fixture, { damage = 5, knockback = 0, knockX = 1, knockY = 0 } = {}) {
  const activationId = fixture.activations.begin('player-weapon', ['player-swing']);
  const outcome = fixture.router.routeStep([{
    activationId,
    sourceNodeId: 'player-weapon',
    attackAreaNodeId: 'player-swing',
    targetAreaNodeId: fixture.root.get_node('DamageArea').runtimeId,
    weaponId: 'wooden-spear',
    weaponTags: ['weapon', 'spear'],
    damageTypes: ['physical'],
    baseDamage: damage,
    effects: knockback > 0 ? [{ effectId: 'knockback', potency: knockback }] : [],
    impact: { x: 0, y: 0, knockX, knockY },
  }], fixture.script.simulationTime)[0];
  fixture.activations.end(activationId);
  return outcome;
}

function steps(tree, count) {
  for (let index = 0; index < count; index += 1) tree.physicsProcess(STEP);
}

test('a hit during windup staggers the enemy, knocks it back by (strength + 120) * (1 - resist) and cancels the attack', async () => {
  const target = { position: { x: 20, y: 0 }, damageAreaNodeId: 'player-area', active: true, hostile: true };
  const fixture = await instantiateEnemy('character.worm-swordsman', { getPrimaryTarget: () => target });
  const player = registerPlayer(fixture.router, target.damageAreaNodeId);
  const { script, root } = fixture;

  steps(fixture.tree, 2);
  assert.equal(script.attacking, true, 'target in range starts an attack');
  assert.equal(fixture.animation.currentAnimation, 'attack-side');

  const outcome = hitEnemy(fixture, { damage: 5, knockback: 200, knockX: 1, knockY: 0 });
  assert.equal(outcome.result.status, 'accepted');
  // worm-swordsman authors knockbackResist 0.45.
  const strength = (200 + 120) * (1 - 0.45);
  assert.equal(script.attacking, false, 'the hit cancels the committed attack');
  assert.equal(script.staggered, true);
  assert.ok(Math.abs(root.velocity.x - strength) < 1e-9);
  assert.equal(root.velocity.y, 0);
  assert.equal(fixture.animation.currentAnimation, 'knockback-side');
  assert.equal(fixture.visual.tint, t.ENEMY_HIT_FLASH_COLOR);

  const stunMs = 320 + Math.min(280, strength * 0.35);
  steps(fixture.tree, Math.floor(stunMs / (STEP * 1000)) - 1);
  assert.equal(script.staggered, true, `stun lasts ${stunMs}ms`);
  assert.ok(root.velocity.x > 0 && root.velocity.x < strength * 0.35, 'knockback velocity decays while stunned');
  assert.equal(fixture.visual.tint, undefined, 'hit flash clears on the simulation clock');

  // Past both the stun and the original 400 ms windup: the cancelled attack never lands.
  steps(fixture.tree, 10);
  assert.equal(script.staggered, false);
  assert.equal(player.commits.length, 0);
  assert.equal(script.attacking, false, 'the cancelled attack keeps its cooldown');
  fixture.dispose();
});

test('knockback-immune damage rules still stagger but never shove the enemy', async () => {
  const fixture = await instantiateEnemy('character.worm-brawler', { getPrimaryTarget: () => undefined });
  fixture.router.unregisterReceiver(fixture.script);
  fixture.router.registerArea(fixture.script, {
    areaNodeId: fixture.root.get_node('DamageArea').runtimeId,
    priority: 0,
    damageMultiplier: 1,
    effectResponses: { knockback: { mode: 'immune' } },
  });
  hitEnemy(fixture, { damage: 1, knockback: 300 });
  assert.equal(fixture.script.staggered, true);
  assert.deepEqual(fixture.root.velocity, { x: 0, y: 0 });
  fixture.dispose();
});

test('an attack lasts for its authored clip when the clip outlasts windup plus recovery', async () => {
  const target = { position: { x: 20, y: 0 }, damageAreaNodeId: 'player-area', active: true, hostile: true };
  // worm-brawler: windup 250 + recovery 250 = 500 ms; a 1.2 s clip must not be cut off.
  const fixture = await instantiateEnemy('character.worm-brawler', { getPrimaryTarget: () => target }, {
    animationOverrides: { 'attack-side': { durationSeconds: 1.2 } },
  });
  registerPlayer(fixture.router, target.damageAreaNodeId);
  steps(fixture.tree, 1);
  assert.equal(fixture.script.attacking, true);
  const startedAt = fixture.script.simulationTime - STEP * 1000;
  // Keep the target out of reach so no follow-up attack starts once this one ends.
  target.position = { x: 200, y: 0 };
  while (fixture.script.attacking && fixture.script.simulationTime - startedAt < 3000) fixture.tree.physicsProcess(STEP);
  const lasted = fixture.script.simulationTime - startedAt;
  assert.ok(Math.abs(lasted - (1200 + 250)) <= STEP * 1000 + 1e-6, `attack lasted ${lasted}ms`);
  fixture.dispose();
});

test('an attack whose clip is shorter than windup plus recovery lasts windup + recovery + 250 ms', async () => {
  const target = { position: { x: 20, y: 0 }, damageAreaNodeId: 'player-area', active: true, hostile: true };
  const fixture = await instantiateEnemy('character.worm-swordsman', { getPrimaryTarget: () => target });
  registerPlayer(fixture.router, target.damageAreaNodeId);
  steps(fixture.tree, 2);
  const startedAt = fixture.script.simulationTime - STEP * 1000;
  while (fixture.script.attacking) fixture.tree.physicsProcess(STEP);
  const lasted = fixture.script.simulationTime - startedAt;
  assert.ok(Math.abs(lasted - (400 + 400 + 250)) <= STEP * 1000 + 1e-6, `attack lasted ${lasted}ms`);
  fixture.dispose();
});

test('ranged enemies flee after an attack when the target is inside fleeRange', async () => {
  const target = { position: { x: 180, y: 0 }, damageAreaNodeId: 'player-area', active: true, hostile: true };
  const projectiles = [];
  const fixture = await instantiateEnemy('character.worm-archer', {
    getPrimaryTarget: () => target,
    fireProjectile: (request) => projectiles.push(request),
  });
  steps(fixture.tree, 2);
  assert.equal(fixture.script.attacking, true);
  target.position = { x: 100, y: 0 };
  while (fixture.script.attacking) fixture.tree.physicsProcess(STEP);
  assert.equal(projectiles.length, 1);
  assert.equal(fixture.script.runtimeState, 'flee');
  assert.ok(fixture.root.velocity.x < 0, 'flees away from the target');
  fixture.dispose();
});

test('enemies mirror their side clips when moving or attacking to the left', async () => {
  const target = { position: { x: -150, y: 0 }, damageAreaNodeId: 'player-area', active: true, hostile: true };
  const fixture = await instantiateEnemy('character.worm-swordsman', { getPrimaryTarget: () => target });
  steps(fixture.tree, 1);
  assert.ok(fixture.root.velocity.x < 0);
  assert.equal(fixture.animation.currentAnimation, 'walk-side');
  assert.equal(fixture.visual.flipX, true);

  target.position = { x: 150, y: 0 };
  steps(fixture.tree, 1);
  assert.equal(fixture.visual.flipX, false);

  target.position = { x: 0, y: 150 };
  steps(fixture.tree, 1);
  assert.equal(fixture.animation.currentAnimation, 'walk-down');
  assert.equal(fixture.visual.flipX, false);

  target.position = { x: -20, y: 0 };
  steps(fixture.tree, 1);
  assert.equal(fixture.script.attacking, true);
  assert.equal(fixture.animation.currentAnimation, 'attack-side');
  assert.equal(fixture.visual.flipX, true);
  fixture.dispose();
});

test('the boss keeps its phase flow when hit: no stagger, no attack cancellation', async () => {
  const target = { position: { x: -300, y: 0 }, damageAreaNodeId: 'player-area', active: true, hostile: true };
  const fixture = await instantiateEnemy('character.fatty-one-eye', { getPrimaryTarget: () => target });
  const script = fixture.root.get_node('FattyScript');
  steps(fixture.tree, 1);
  assert.equal(script.phase, 'chase');
  const attackingBefore = script.attacking;
  const activationId = fixture.activations.begin('player-weapon', ['player-swing']);
  const outcome = fixture.router.routeStep([{
    activationId,
    sourceNodeId: 'player-weapon',
    attackAreaNodeId: 'player-swing',
    targetAreaNodeId: script.getReference('damageArea').configuredTarget.runtimeId,
    weaponId: 'wooden-spear',
    weaponTags: ['weapon', 'spear'],
    damageTypes: ['physical'],
    baseDamage: 5,
    effects: [{ effectId: 'knockback', potency: 300 }],
    impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
  }], script.simulationTime)[0];
  assert.equal(outcome.result.status, 'accepted');
  assert.equal(script.staggered, false);
  assert.equal(script.attacking, attackingBefore);
  steps(fixture.tree, 1);
  assert.equal(script.phase, 'chase');
  assert.deepEqual(fixture.root.velocity, { x: -script.movementSpeed, y: 0 }, 'keeps chasing at full speed');
  assert.equal(fixture.visual.flipX, false, 'the boss art is never mirrored');
  fixture.dispose();
});

test('hit-stun is measured in simulation time and does not expire while the tree is paused', async () => {
  const fixture = await instantiateEnemy('character.worm-brawler', { getPrimaryTarget: () => undefined });
  hitEnemy(fixture, { damage: 1, knockback: 0 });
  assert.equal(fixture.script.staggered, true);
  fixture.tree.paused = true;
  for (let index = 0; index < 120; index += 1) fixture.tree.physicsProcess(STEP);
  assert.equal(fixture.script.staggered, true);
  fixture.tree.paused = false;
  steps(fixture.tree, 60);
  assert.equal(fixture.script.staggered, false);
  fixture.dispose();
});
