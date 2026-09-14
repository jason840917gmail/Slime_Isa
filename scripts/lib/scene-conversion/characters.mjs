import { convertedOutput, readJson, requireSupportedUnit, resourcePath, shapeValue } from './adapter-utils.mjs';

const CHARACTER_SUPPORTED = new Set(['character:worm-brawler', 'character:fatty-one-eye']);
const ENEMY_SUPPORTED = new Set(['enemy:worm-brawler']);

function shapeResource(resourceId, value) {
  return { version: 1, resourceId, kind: 'collision-shape', value };
}

export const characterSceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    for (const unit of units) {
      requireSupportedUnit(unit, CHARACTER_SUPPORTED);
      const character = await readJson(readSource, unit.oldSourcePath);
      outputs.push(convertedOutput(unit, resourcePath('characters', character.characterId, 'body-shape'), shapeResource(
        `${character.characterId}.body-shape`, shapeValue(character.body),
      ), ['$.characterId', '$.body']));
      if (character.characterId === 'fatty-one-eye') {
        const hitbox = character.hitboxes['contact-hop-impact'];
        outputs.push(convertedOutput(unit, resourcePath('characters', character.characterId, 'contact-shape'), shapeResource(
          `${character.characterId}.contact-shape`, { shape: 'circle', radius: hitbox.radius ?? hitbox.width / 2 },
        ), ['$.characterId', '$.hitboxes.contact-hop-impact', '$.animationTracks.contact-hop'], [
          { path: '$.$schema', owner: unit.oldSourcePath },
          { path: '$.version', owner: unit.oldSourcePath },
          { path: '$.displayName', owner: unit.oldSourcePath },
          { path: '$.kind', owner: unit.oldSourcePath },
          { path: '$.visualSetId', owner: unit.oldSourcePath },
        ]));
      }
    }
    return outputs;
  },
};

function wormScene(character, enemy) {
  const visualPrefix = character.visualSetId;
  return {
    version: 1,
    sceneId: `character.${character.characterId}`,
    rootNodeId: 'body',
    nodes: [
      { id: 'body', name: 'WormBrawler', type: 'CharacterBody2D', parentId: null, order: 0, properties: { collisionLayer: 2, collisionMask: 5, position: [0, 0], velocity: [0, 0] } },
      { id: 'body-shape', name: 'BodyShape', type: 'CollisionShape2D', parentId: 'body', order: 0, properties: { shape: { resourceId: `${character.characterId}.body-shape` }, position: [character.body.centerOffsetX, character.body.centerOffsetY] } },
      { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'body', order: 1, properties: { texture: { resourceId: `${visualPrefix}.sprite` }, frame: 0, origin: [0.5, 0.5], scale: [1, 1] } },
      { id: 'damage-area', name: 'DamageArea', type: 'Area2D', parentId: 'body', order: 2, properties: { collisionLayer: 8, collisionMask: 16, monitoring: true, monitorable: true } },
      { id: 'damage-shape', name: 'DamageShape', type: 'CollisionShape2D', parentId: 'damage-area', order: 0, properties: { shape: { resourceId: `${character.characterId}.body-shape` }, position: [character.body.centerOffsetX, character.body.centerOffsetY] } },
      { id: 'attack-area', name: 'AttackArea', type: 'Area2D', parentId: 'body', order: 3, properties: { collisionLayer: 16, collisionMask: 8, monitoring: false, monitorable: false } },
      { id: 'attack-shape', name: 'AttackShape', type: 'CollisionShape2D', parentId: 'attack-area', order: 0, properties: { shape: { resourceId: `${character.characterId}.attack-shape` }, disabled: true } },
      { id: 'animation', name: 'Animation', type: 'AnimationPlayer', parentId: 'body', order: 4, properties: { library: { resourceId: `${visualPrefix}.animations` }, domain: 'physics', autoplay: 'idle-side' } },
      {
        id: 'script', name: 'EnemyScript', type: 'ScriptNode', scriptId: 'game.enemy', parentId: 'body', order: 5,
        properties: {
          body: { nodeId: 'body' }, visual: { nodeId: 'visual' }, animation: { nodeId: 'animation' }, damageArea: { nodeId: 'damage-area' }, attackArea: { nodeId: 'attack-area' },
          faction: 'hostile', rank: 'ordinary', maxHealth: enemy.maxHp, targetingRadius: enemy.ai.aggroRange,
          attackRange: enemy.ai.attackRange, movementSpeed: enemy.ai.chaseSpeed, attackCooldownMs: enemy.ai.attackCooldownMs,
          attributes: {
            wanderSpeed: enemy.ai.wanderSpeed, attackWindupMs: enemy.ai.attackWindupMs,
            attackRecoveryMs: enemy.ai.attackRecoveryMs, contactDamage: enemy.ai.contactDamage,
            knockbackStrength: enemy.ai.knockbackStrength, knockbackResist: enemy.ai.knockbackResist,
          },
          damageRule: { priority: 0, damageMultiplier: 1 }, rewards: enemy.drop,
        },
      },
    ],
    instances: [],
  };
}

export const enemySceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    for (const unit of units) {
      requireSupportedUnit(unit, ENEMY_SUPPORTED);
      const catalog = await readJson(readSource, unit.oldSourcePath);
      const enemy = catalog.types['worm-brawler'];
      const character = await readJson(readSource, 'src/game/content/characters/worm-brawler/character.json');
      outputs.push(convertedOutput(unit, resourcePath('characters', character.characterId, 'attack-shape'), shapeResource(
        `${character.characterId}.attack-shape`, { shape: 'circle', radius: enemy.ai.attackRange * 1.35 },
      ), ['$.types.worm-brawler.ai.attackRange']));
      outputs.push(convertedOutput(unit, 'characters/worm-brawler.scene.json', wormScene(character, enemy), [
        '$.types.worm-brawler',
      ], [
        { path: '$.$schema', owner: unit.oldSourcePath },
        { path: '$.types.worm-archer', owner: unit.oldSourcePath },
        { path: '$.types.worm-swordsman', owner: unit.oldSourcePath },
      ]));
    }
    return outputs;
  },
};
