import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';
import { loadSceneTooling } from '../../lib/scene-conversion/load-scene-tooling.mjs';
import { collisionBits as converterCollisionBits } from '../../lib/scene-conversion/collision-layers.mjs';

const tooling = await loadSceneTooling();
const content = await loadAuthoredSceneContent();
const registry = tooling.createGameDescriptorRegistry();
const table = JSON.parse(await readFile(path.join(REPOSITORY_ROOT, 'src/game/content/physics/collision-layers.json'), 'utf8'));

test('the project collision layer table keeps the Area2D bit semantics combat and pickups rely on', () => {
  assert.equal(tooling.collisionBits('world'), 1);
  assert.equal(tooling.collisionBits('hurtbox'), 8);
  assert.equal(tooling.collisionBits('hitbox'), 16);
  assert.equal(tooling.collisionBits('pickup-seeker'), 32);
  assert.equal(tooling.collisionBits('pickup'), 64);
  for (const entry of table.layers) {
    assert.equal(tooling.collisionBits(entry.name), converterCollisionBits(entry.name), `converter and runtime agree on '${entry.name}'`);
  }
  assert.throws(() => tooling.collisionBits('walls'), /Unknown collision layer/);
  assert.equal(tooling.CHARACTER_BODY_REQUIRED_MASK, tooling.collisionBits('world'));
});

test('blocking rule: movers use their own mask, static masks are irrelevant, dynamic pairs accept either side', () => {
  const body = (layer, mask, isStatic = false) => ({ collisionLayer: tooling.collisionBits(...layer), collisionMask: tooling.collisionBits(...mask), isStatic });
  const wall = body(['world'], [], true);
  assert.equal(tooling.blockingPairAccepts(body(['player'], ['world']), wall), true);
  assert.equal(tooling.blockingPairAccepts(wall, body(['player'], ['world'])), true, 'argument order does not matter');
  assert.equal(tooling.blockingPairAccepts(body(['player'], ['enemy']), wall), false, 'a mover without the world layer passes walls');
  assert.equal(tooling.blockingPairAccepts(body(['world'], ['player'], true), body(['player'], [])), false, 'a static mask never blocks a mover');
  assert.equal(tooling.blockingPairAccepts(wall, body(['world'], ['world'], true)), false, 'static pairs never interact');
  assert.equal(tooling.blockingPairAccepts(body(['player'], ['enemy']), body(['enemy'], [])), true, 'either dynamic mask suffices');
  assert.equal(tooling.blockingPairAccepts(body(['npc'], ['world']), body(['npc'], ['world'])), false);
});

function sceneById(sceneId) {
  const scene = content.scenes.find((candidate) => candidate.sceneId === sceneId);
  assert.ok(scene, `scene '${sceneId}' exists`);
  return scene;
}

function rootBody(scene) {
  const root = scene.nodes.find((node) => node.id === scene.rootNodeId);
  assert.match(root.type, /Body2D$/, `${scene.sceneId} is rooted at a physics body`);
  const properties = root.properties;
  return { sceneId: scene.sceneId, collisionLayer: properties.collisionLayer, collisionMask: properties.collisionMask, isStatic: root.type === 'StaticBody2D' };
}

function scriptId(scene) {
  return scene.nodes.find((node) => node.type === 'ScriptNode')?.scriptId;
}

test('production scenes reproduce the pre-refactor blocking relationships (ec0271e colliders)', () => {
  const player = rootBody(sceneById('character.player-slime'));
  const characterScenes = content.scenes.filter((scene) => scene.sceneId.startsWith('character.'));
  const npcs = characterScenes.filter((scene) => scriptId(scene) === 'game.npc').map(rootBody);
  const enemies = characterScenes.filter((scene) => ['game.enemy', 'game.fatty'].includes(scriptId(scene))).map(rootBody);
  const arrow = rootBody(sceneById('projectile.worm-arrow'));
  const staticProps = content.scenes
    .filter((scene) => scene.nodes.find((node) => node.id === scene.rootNodeId)?.type === 'StaticBody2D')
    .map(rootBody);
  const wallLayers = content.scenes.flatMap((scene) => scene.nodes
    .filter((node) => node.type === 'TileMapLayer2D')
    .map((node) => ({ sceneId: `${scene.sceneId}#${node.id}`, collisionLayer: node.properties.collisionLayer, collisionMask: node.properties.collisionMask, isStatic: true })));
  assert.ok(npcs.length >= 4 && enemies.length >= 4 && staticProps.length >= 20 && wallLayers.length > 0);

  const solids = [...staticProps, ...wallLayers];
  for (const mover of [player, ...npcs, ...enemies, arrow]) {
    for (const solid of solids) {
      assert.equal(tooling.blockingPairAccepts(mover, solid), true, `${mover.sceneId} is blocked by ${solid.sceneId}`);
    }
  }
  // Old WorldScene/CombatController/BossCampController: player <-> enemies collided;
  // no collider existed for enemy <-> enemy, NPC <-> NPC or projectile bodies <-> characters.
  // Player <-> NPC was passable before the refactor; NPCs are now solid to the player.
  for (const enemy of enemies) assert.equal(tooling.blockingPairAccepts(player, enemy), true, `player blocks ${enemy.sceneId}`);
  for (const npc of npcs) assert.equal(tooling.blockingPairAccepts(player, npc), true, `player blocks ${npc.sceneId}`);
  for (const first of enemies) for (const second of enemies) assert.equal(tooling.blockingPairAccepts(first, second), false);
  for (const first of npcs) for (const second of npcs) assert.equal(tooling.blockingPairAccepts(first, second), false);
  for (const character of [player, ...npcs, ...enemies]) assert.equal(tooling.blockingPairAccepts(arrow, character), false);
});

test('character bodies collide with world bounds; projectiles do not', () => {
  const root = (sceneId) => { const scene = sceneById(sceneId); return scene.nodes.find((node) => node.id === scene.rootNodeId); };
  assert.equal(root('character.player-slime').properties.collideWorldBounds, true);
  assert.equal(root('character.worm-archer').properties.collideWorldBounds, true);
  assert.equal(root('character.fatty-one-eye').properties.collideWorldBounds, true);
  assert.equal(root('projectile.worm-arrow').properties.collideWorldBounds, false);
  const descriptor = tooling.propertiesForNode('CharacterBody2D', undefined, registry).find((entry) => entry.key === 'collideWorldBounds');
  assert.equal(descriptor.defaultValue, true);
});

function bodyScene(properties, type = 'CharacterBody2D') {
  return {
    version: 1, sceneId: 'fixture.body', rootNodeId: 'body',
    nodes: [{ id: 'body', name: 'Body', type, parentId: null, order: 0, properties }],
    instances: [],
  };
}

test('scene validation rejects collision bits the layer table does not define', () => {
  const undefinedBit = 2 ** 20;
  const issues = tooling.validateSceneDocument(bodyScene({ collisionLayer: undefinedBit, collisionMask: 1 }), { registry });
  assert.match(issues.map((issue) => issue.message).join('\n'), /no named layer/);
  const areaIssues = tooling.validateSceneDocument({
    version: 1, sceneId: 'fixture.area', rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
      { id: 'area', name: 'Area', type: 'Area2D', parentId: 'root', order: 0, properties: { collisionMask: 0xffff_ffff } },
    ],
    instances: [],
  }, { registry });
  assert.match(areaIssues.map((issue) => issue.message).join('\n'), /no named layer/);
  assert.deepEqual(tooling.validateSceneDocument(bodyScene({ collisionLayer: tooling.collisionBits('player'), collisionMask: tooling.collisionBits('world', 'enemy') }), { registry }), []);
});

test('scene validation requires enabled CharacterBody2D masks to include the world layer unless opted out', () => {
  const noWorld = { collisionLayer: tooling.collisionBits('player'), collisionMask: tooling.collisionBits('enemy') };
  assert.match(tooling.validateSceneDocument(bodyScene(noWorld), { registry }).map((issue) => issue.message).join('\n'), /must include the 'world' layer/);
  assert.deepEqual(tooling.validateSceneDocument(bodyScene({ ...noWorld, allowWorldPassThrough: true }), { registry }), []);
  assert.deepEqual(tooling.validateSceneDocument(bodyScene({ ...noWorld, collisionEnabled: false }), { registry }), []);
  assert.deepEqual(tooling.validateSceneDocument(bodyScene({ collisionLayer: tooling.collisionBits('world'), collisionMask: 0 }, 'StaticBody2D'), { registry }), [], 'static bodies need no mask');
  assert.deepEqual(tooling.validateSceneDocument(bodyScene({}), { registry }), [], 'descriptor defaults satisfy the rule');
});
