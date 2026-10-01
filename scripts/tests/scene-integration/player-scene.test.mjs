import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const scene = content.scenes.find((document) => document.sceneId === 'character.player-slime');

class TestCharacterBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
  teleportedTo;
  queue_teleport(position) { this.teleportedTo = { ...position }; }
}

class TestDamageArea extends t.Node {
  contactBounds() { return { x: -15, y: 1.56, width: 30, height: 26 }; }
}

class TestAnimationPlayer extends t.Node {
  currentAnimation;
  hasAnimation(animationId) { return ['idle', 'walk', 'roll'].includes(animationId); }
  play(animationId) { this.currentAnimation = animationId; }
}

async function instantiate() {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  let hp = 100;
  const health = {
    runtimeNodeId: 'player-health',
    getDamageState: () => ({ hp, maxHp: 100, dead: hp <= 0 }),
    commitDamage: (commit) => { hp -= commit.result.actualDamage; },
  };
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(scene.sceneId);
  const scripts = t.createGameScriptRegistry({
    [t.DAMAGE_ROUTER_SERVICE]: router,
    [t.PLAYER_HEALTH_SERVICE]: health,
  });
  const nodeTypes = t.createCoreNodeTypeRegistry()
    .replace('CharacterBody2D', (context) => new TestCharacterBody({
      runtimeId: context.runtimeId,
      name: context.name,
      position: Array.isArray(context.properties.position)
        ? { x: Number(context.properties.position[0]), y: Number(context.properties.position[1]) }
        : undefined,
    }))
    .replace('Area2D', (context) => new TestDamageArea({ runtimeId: context.runtimeId, name: context.name }))
    .replace('AnimationPlayer', (context) => new TestAnimationPlayer({ runtimeId: context.runtimeId, name: context.name }));
  const root = new t.SceneInstantiator({ nodeTypes, scripts, descriptors }).instantiate_scene(packed, { runtimeNamespace: 'player-fixture' });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  return { activations, router, root, tree, packed, loader, resources, getHp: () => hp };
}

function damageRequest(activationId, targetAreaNodeId, damage = 10) {
  return {
    activationId,
    sourceNodeId: 'enemy',
    attackAreaNodeId: 'enemy-attack',
    targetAreaNodeId,
    weaponId: 'enemy-contact',
    weaponTags: ['enemy', 'contact'],
    damageTypes: ['physical'],
    baseDamage: damage,
    effects: [],
    impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
  };
}

test('player scene exposes node-backed runtime ports, dodge immunity, and one routed health owner', async () => {
  const fixture = await instantiate();
  const script = fixture.root.get_node('PlayerScript');
  const damageArea = fixture.root.get_node('DamageArea');
  const pickupArea = fixture.root.get_node('PickupArea');
  assert.deepEqual(fixture.tree.diagnostics, []);
  assert.ok(script instanceof t.PlayerScript);
  assert.equal(script.playerName, 'bob');
  assert.equal(script.is_in_group('player'), true);
  assert.ok(pickupArea);
  assert.deepEqual(script.getBodyBounds(), { x: -15, y: 1.56, width: 30, height: 26 });

  fixture.tree.dispatchInput({ handled: false, type: 'key-down', action: 'move-right', pressed: true, released: false });
  fixture.tree.dispatchInput({ handled: false, type: 'key-down', action: 'move-up', pressed: true, released: false });
  assert.deepEqual(script.getMovementInput(), { x: 1, y: -1 });
  fixture.tree.dispatchInput({ handled: false, type: 'key-up', action: 'move-up', pressed: false, released: true });
  assert.deepEqual(script.getMovementInput(), { x: 1, y: 0 });
  fixture.tree.dispatchInput({ handled: false, type: 'key-down', action: 'attack', pressed: true, released: false });
  fixture.tree.dispatchInput({ handled: false, type: 'key-down', action: 'attack', pressed: true, released: false });
  assert.equal(script.consumeActionPress('attack'), true);
  assert.equal(script.consumeActionPress('attack'), false);
  script.clearInput();

  // A press that waits longer than input.bufferMs (150 ms) is dropped, not fired late.
  fixture.tree.dispatchInput({ handled: false, type: 'key-down', action: 'dodge', pressed: true, released: false });
  fixture.tree.dispatchInput({ handled: false, type: 'key-up', action: 'dodge', pressed: false, released: true });
  fixture.tree.physicsProcess(0.2);
  assert.equal(script.consumeActionPress('dodge'), false, 'a stale press expires');
  fixture.tree.dispatchInput({ handled: false, type: 'key-down', action: 'dodge', pressed: true, released: false });
  fixture.tree.physicsProcess(0.1);
  assert.equal(script.consumeActionPress('dodge'), true, 'a fresh press is used');
  script.clearInput();

  // The wheel moves one step per notch, then waits for the wheel to go quiet.
  const wheel = (timestamp, wheelDelta = 100, action = 'weapon-next') => fixture.tree.dispatchInput({ handled: false, type: 'wheel', action, wheelDelta, timestamp, pressed: false, released: false });
  wheel(1000);
  assert.equal(script.consumeActionPress('weapon-next'), true);
  wheel(1050);
  wheel(1100);
  assert.equal(script.consumeActionPress('weapon-next'), false, 'one swipe is one step');
  wheel(1400, 20);
  wheel(1410, 20);
  assert.equal(script.consumeActionPress('weapon-next'), false, 'small trackpad deltas add up first');
  wheel(1420, 20);
  assert.equal(script.consumeActionPress('weapon-next'), true);
  script.clearInput();
  assert.deepEqual(script.getMovementInput(), { x: 0, y: 0 });

  assert.equal(script.move({ x: 3, y: 4 }, 100), true);
  assert.deepEqual(fixture.root.velocity, { x: 60, y: 80 });
  script.stopMovement();
  assert.deepEqual(fixture.root.velocity, { x: 0, y: 0 });
  assert.equal(script.beginDodge({ x: 1, y: 0 }, 300, 500, 400), true);
  assert.equal(script.isDodging(), true);
  assert.equal(script.isRolling(), true);
  assert.equal(script.move({ x: 0, y: 1 }, 100), false, 'the roll owns the body');
  assert.deepEqual(fixture.root.velocity, { x: 300, y: 0 });
  assert.equal(script.beginDodge({ x: -1, y: 0 }, 300, 500, 400), false, 'no new roll mid-roll');
  const blockedActivation = fixture.activations.begin('enemy', ['enemy-attack']);
  const blocked = fixture.router.routeStep([damageRequest(blockedActivation, damageArea.runtimeId)], 0);
  assert.equal(blocked[0].result.reason, 'state-blocked');
  assert.equal(fixture.getHp(), 100);

  fixture.tree.physicsProcess(0.4);
  const acceptedActivation = fixture.activations.begin('enemy', ['enemy-attack']);
  const accepted = fixture.router.routeStep([damageRequest(acceptedActivation, damageArea.runtimeId)], 400);
  assert.equal(accepted[0].result.status, 'accepted');
  assert.equal(fixture.getHp(), 90);
  assert.equal(script.isDodging(), false, 'the last 100 ms of the roll is recovery');
  fixture.tree.physicsProcess(0.1);
  assert.equal(script.isRolling(), false);

  script.applyKnockback({ x: 1, y: 0 }, 200, 160);
  assert.equal(script.move({ x: 0, y: 1 }, 100), false);
  assert.deepEqual(fixture.root.velocity, { x: 200, y: 0 });
  fixture.tree.physicsProcess(0.16);
  assert.equal(script.move({ x: 0, y: 1 }, 100), true);
  script.teleport({ x: 50, y: 60 });
  assert.deepEqual(fixture.root.teleportedTo, { x: 50, y: 60 });

  fixture.tree.shutdown();
  assert.equal(fixture.router.hasArea(damageArea.runtimeId), false);
  fixture.packed.dispose();
  assert.equal(fixture.loader.activeLeaseCount(), 0);
  assert.equal(fixture.resources.activeLeaseCount(), 0);
});
