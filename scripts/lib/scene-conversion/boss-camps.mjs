import { convertedOutput, readJson, requireSupportedUnit, resourcePath, withCharacterDepthAnchor } from './adapter-utils.mjs';
import { collision } from './collision-layers.mjs';
import { loadAnimationSampling } from './load-animation-sampling.mjs';

const SUPPORTED = new Set(['boss:fatty-one-eye']);

function fattyScene(character, visual, boss) {
  return {
    version: 1,
    sceneId: 'character.fatty-one-eye',
    rootNodeId: 'body',
    nodes: [
      { id: 'body', name: 'FattyOneEye', type: 'CharacterBody2D', parentId: null, order: 0, properties: { ...collision(['enemy'], ['world', 'water', 'player']), collideWorldBounds: true, position: [0, 0], velocity: [0, 0] } },
      { id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: 'fatty-one-eye.body-shape' } } },
      { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'body', order: 1, properties: { texture: { resourceId: `${visual.visualSetId}.sprite` }, frame: 0, origin: visual.defaults.origin, scale: visual.defaults.scale } },
      { id: 'eye', name: 'Eye', type: 'Area2D', parentId: 'body', order: 2, properties: { ...collision(['hurtbox'], ['hitbox']), monitoring: true, monitorable: true } },
      { id: 'eye-shape', name: 'EyeShape', type: 'CollisionShape2D', parentId: 'eye', order: 0, properties: { shape: { resourceId: 'fatty-one-eye.eye-shape' } } },
      { id: 'contact-attack', name: 'ContactAttack', type: 'Area2D', parentId: 'body', order: 3, properties: { ...collision(['hitbox'], ['hurtbox']), monitoring: false, monitorable: false } },
      { id: 'contact-shape', name: 'ContactShape', type: 'CollisionShape2D', parentId: 'contact-attack', order: 0, properties: { shape: { resourceId: 'fatty-one-eye.contact-shape' }, disabled: true } },
      { id: 'landing-zone', name: 'LandingZone', type: 'Area2D', parentId: 'body', order: 4, properties: { ...collision(['hitbox'], ['hurtbox']), monitoring: false, monitorable: false } },
      { id: 'landing-shape', name: 'LandingShape', type: 'CollisionShape2D', parentId: 'landing-zone', order: 0, properties: { shape: { resourceId: 'fatty-one-eye.landing-shape' } } },
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'body', order: 5, properties: { library: { resourceId: `${visual.visualSetId}.animations` }, domain: 'physics', autoplay: 'chase' } },
      {
        id: 'script', name: 'FattyScript', type: 'ScriptNode', scriptId: 'game.fatty', parentId: 'body', order: 6,
        properties: {
          body: { nodeId: 'body' }, visual: { nodeId: 'visual' }, animation: { nodeId: 'animation' }, damageArea: { nodeId: 'eye' }, attackArea: { nodeId: 'contact-attack' }, contactAttack: { nodeId: 'contact-attack' },
          faction: 'hostile', rank: 'boss', maxHealth: boss.maxHp, targetingRadius: 933, attackRange: 64,
          movementSpeed: boss.chaseSpeed, attackCooldownMs: boss.contactHop.cooldownMs,
          attributes: {
            effectImmunities: boss.effectImmunities, allowedWeaponIds: boss.allowedWeaponIds,
            attackWindupMs: 250, attackRecoveryMs: 50, contactDamage: boss.contactHop.damage,
            knockbackStrength: boss.contactHop.knockbackStrength,
          },
          damageRule: { priority: 100, damageMultiplier: 1, acceptedSources: [{ weaponIds: boss.allowedWeaponIds }], effectResponses: { knockback: { mode: 'immune' } } },
          rewards: {}, contactHopCooldownMs: boss.contactHop.cooldownMs, contactHopDurationMs: 300,
          leapCadenceMs: boss.leap.cadenceMs, smallHopCount: boss.leap.smallHopCount,
          smallHopDurationMs: boss.leap.smallHopDurationMs, betweenHopsMs: boss.leap.betweenHopsMs,
          airTimeMs: boss.leap.airTimeMs, recoveryMs: boss.leap.recoveryMs,
          landingDamage: boss.leap.landingDamage, landingZone: { nodeId: 'landing-zone' },
          landingKnockbackStrength: boss.leap.landingKnockbackStrength, landingEffectId: 'boss-ground-crack',
          landingShakeMs: 100, landingShakeIntensity: 0.003,
        },
      },
    ],
    instances: [],
    subresources: [
      { version: 1, resourceId: 'fatty-one-eye.landing-shape', kind: 'collision-shape', value: { shape: 'circle', radius: boss.leap.landingRadius } },
    ],
  };
}

function campScene(map, camp, chest) {
  const contents = Object.fromEntries((chest.initialState?.contents ?? []).map((entry) => [entry.itemId, entry.quantity]));
  return {
    version: 1,
    sceneId: 'encounter.level-1-fatty-camp',
    rootNodeId: 'root',
    nodes: [
      { id: 'root', name: 'Level1FattyCamp', type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
      { id: 'activation-area', name: 'ActivationArea', type: 'Area2D', parentId: 'root', order: 0, properties: { ...collision(['trigger'], ['enemy']), monitoring: true, monitorable: false } },
      { id: 'activation-shape', name: 'ActivationShape', type: 'CollisionShape2D', parentId: 'activation-area', order: 0, properties: { shape: { resourceId: 'level-1-fatty-camp.activation-shape' } } },
      { id: 'arena-area', name: 'ArenaArea', type: 'Area2D', parentId: 'root', order: 1, properties: { ...collision(['trigger'], ['enemy']), monitoring: true, monitorable: false } },
      { id: 'arena-shape', name: 'ArenaShape', type: 'CollisionShape2D', parentId: 'arena-area', order: 0, properties: { shape: { resourceId: 'level-1-fatty-camp.arena-shape' } } },
      { id: 'active-bosses', name: 'ActiveBosses', type: 'Node2D', parentId: 'root', order: 2, properties: {} },
      {
        id: 'script', name: 'BossCampScript', type: 'ScriptNode', scriptId: 'game.boss-camp', parentId: 'root', order: 3,
        properties: {
          mapId: map.mapId, campId: camp.id, bossId: camp.bossId, bossScene: { sceneId: 'character.fatty-one-eye' },
          activationArea: { nodeId: 'activation-area' }, arenaArea: { nodeId: 'arena-area' }, activeBosses: { nodeId: 'active-bosses' },
          guardedChest: { instancePath: ['guarded-chest'], nodeId: 'body' }, guardedChestInstanceId: camp.guardedChestInstanceId,
          respawnMs: camp.respawnMs, spawn: [0, 0],
        },
      },
    ],
    instances: [{
      instanceId: 'guarded-chest', name: 'GuardedChest', sceneId: 'object.chest-wooden', parentNodeId: 'root', order: 4,
      overrides: [
        { sourceInstancePath: [], sourceNodeId: 'body', property: 'position', value: [chest.x - camp.spawn.x, chest.y - camp.spawn.y] },
        { sourceInstancePath: [], sourceNodeId: 'script', property: 'mapId', value: map.mapId },
        { sourceInstancePath: [], sourceNodeId: 'script', property: 'instanceId', value: chest.instanceId },
        { sourceInstancePath: [], sourceNodeId: 'script', property: 'initialContents', value: contents },
      ],
    }],
    subresources: [
      { version: 1, resourceId: 'level-1-fatty-camp.activation-shape', kind: 'collision-shape', value: { shape: 'circle', radius: camp.activationPerimeter.radius } },
      { version: 1, resourceId: 'level-1-fatty-camp.arena-shape', kind: 'collision-shape', value: { shape: 'circle', radius: camp.arenaPerimeter.radius } },
    ],
  };
}

export const bossCampSceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    for (const unit of units) {
      requireSupportedUnit(unit, SUPPORTED);
      const boss = await readJson(readSource, unit.oldSourcePath);
      const character = await readJson(readSource, 'src/game/content/characters/fatty-one-eye/character.json');
      const visual = await readJson(readSource, 'src/game/content/characters/fatty-one-eye/visual-set.json');
      const map = await readJson(readSource, 'src/game/content/maps/level-1.map.json');
      const camp = map.bossCamps.find((entry) => entry.bossId === boss.id);
      const chest = map.objects.find((entry) => entry.instanceId === camp.guardedChestInstanceId);
      outputs.push(convertedOutput(unit, resourcePath('characters', 'fatty-one-eye', 'eye-shape'), {
        version: 1, resourceId: 'fatty-one-eye.eye-shape', kind: 'collision-shape', value: { shape: 'circle', radius: boss.eye.width / 2 },
      }, ['$.eye']));
      outputs.push(convertedOutput(unit, 'characters/fatty-one-eye.scene.json', withCharacterDepthAnchor(fattyScene(character, visual, boss), (await loadAnimationSampling()).bodyDepthAnchor(character.body)), [
        '$.id', '$.characterId', '$.visualSetId', '$.maxHp', '$.eye', '$.chaseSpeed', '$.contactHop', '$.leap', '$.allowedWeaponIds', '$.effectImmunities',
      ], [
        { path: '$.$schema', owner: unit.oldSourcePath },
        { path: '$.displayName', owner: unit.oldSourcePath },
        { path: '$.visualScale', owner: unit.oldSourcePath },
        { path: '$.editorPreview', owner: unit.oldSourcePath },
        { path: '$.body', owner: 'src/game/content/characters/fatty-one-eye/character.json' },
      ]));
      outputs.push(convertedOutput(unit, 'encounters/level-1-fatty-camp.scene.json', campScene(map, camp, chest), [
        '$.id',
      ], [
        { path: '$.displayName', owner: unit.oldSourcePath },
        { path: '$.mapPlacement', owner: 'src/game/content/maps/level-1.map.json' },
      ]));
    }
    return outputs;
  },
};
