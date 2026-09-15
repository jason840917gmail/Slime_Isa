import { convertedOutput, readJson, requireSupportedUnit, resourcePath, shapeValue } from './adapter-utils.mjs';

const CHARACTER_SUPPORTED = new Set([
  'character:worm-archer',
  'character:worm-brawler',
  'character:worm-swordsman',
  'character:slime-spider',
  'character:fatty-one-eye',
]);
const ENEMY_SUPPORTED = new Set(['enemy:worm-archer', 'enemy:worm-brawler', 'enemy:worm-swordsman']);

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
      if (character.characterId === 'slime-spider') {
        outputs.push(...enemyOutputs(unit, character, character.enemy, [
          '$.characterId', '$.displayName', '$.kind', '$.visualSetId', '$.enemy',
        ], [
          { path: '$.$schema', owner: unit.oldSourcePath },
          { path: '$.version', owner: unit.oldSourcePath },
          { path: '$.hitboxes', owner: unit.oldSourcePath },
          { path: '$.animationTracks', owner: unit.oldSourcePath },
        ]));
      }
    }
    return outputs;
  },
};

function enemyScene(character, enemy) {
  const visualPrefix = character.visualSetId;
  return {
    version: 1,
    sceneId: `character.${character.characterId}`,
    rootNodeId: 'body',
    nodes: [
      { id: 'body', name: nodeName(character.characterId), type: 'CharacterBody2D', parentId: null, order: 0, properties: { collisionLayer: 2, collisionMask: 5, position: [0, 0], velocity: [0, 0] } },
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
            ...(enemy.ai.behavior ? { behavior: enemy.ai.behavior } : {}),
            ...(enemy.ai.fleeRange === undefined ? {} : { fleeRange: enemy.ai.fleeRange }),
            ...(enemy.ai.isRanged ? { isRanged: true, projectileSpeed: enemy.ai.projectileSpeed } : {}),
          },
          damageRule: { priority: 0, damageMultiplier: 1 }, rewards: enemy.drop,
          ...(enemy.projectile ? { projectile: enemy.projectile } : {}),
          ...(enemy.impactEffect ? { impactEffect: enemy.impactEffect } : {}),
        },
      },
    ],
    instances: [],
  };
}

function nodeName(characterId) {
  return characterId.split('-').map((part) => `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`).join('');
}

function enemyOutputs(unit, character, enemy, consumedFieldPaths, intentionallyRetainedFields) {
  if (!enemy) throw new Error(`Enemy character '${character.characterId}' has no enemy gameplay document`);
  return [
    convertedOutput(unit, resourcePath('characters', character.characterId, 'attack-shape'), shapeResource(
      `${character.characterId}.attack-shape`, { shape: 'circle', radius: enemy.ai.attackRange * 1.35 },
    ), consumedFieldPaths),
    convertedOutput(unit, `characters/${character.characterId}.scene.json`, enemyScene(character, enemy), consumedFieldPaths, intentionallyRetainedFields),
  ];
}

export const enemySceneAdapter = {
  async convert({ units, readSource }) {
    const outputs = [];
    for (const unit of units) {
      requireSupportedUnit(unit, ENEMY_SUPPORTED);
      const catalog = await readJson(readSource, unit.oldSourcePath);
      const characterId = unit.key.slice('enemy:'.length);
      const enemy = catalog.types[characterId];
      const character = await readJson(readSource, `src/game/content/characters/${characterId}/character.json`);
      outputs.push(...enemyOutputs(unit, character, enemy, [
        `$.types.${characterId}`,
      ], [
        { path: '$.$schema', owner: unit.oldSourcePath },
        ...Object.keys(catalog.types)
          .filter((id) => id !== characterId)
          .sort()
          .map((id) => ({ path: `$.types.${id}`, owner: unit.oldSourcePath })),
      ]));
    }
    return outputs;
  },
};
