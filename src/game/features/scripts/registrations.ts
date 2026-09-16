import { createCoreDescriptorRegistry, type PropertyDescriptor, type ScriptDescriptor } from '../../content/scenes/propertyDescriptors';
import { ScriptRegistry } from '../../runtime/scene/registries/ScriptRegistry';
import type { ScriptServiceMap } from '../../runtime/scene/scripts/ScriptNode';
import { CharacterScript } from './CharacterScript';
import { EnemyScript } from './EnemyScript';
import { FattyScript } from './FattyScript';
import { BossCampScript } from './BossCampScript';
import { ChestScript } from './ChestScript';
import { PlayerScript } from './PlayerScript';
import { NpcScript } from './NpcScript';
import { WeaponScript } from './WeaponScript';
import { ProjectileScript } from './ProjectileScript';
import { EffectScript } from './EffectScript';

const numberProperty = (key: string, label: string, defaultValue: number, group: string): PropertyDescriptor => ({
  key, label, group, value: { kind: 'number', min: 0 }, defaultValue,
  serialized: true, inspector: 'number', overridable: true,
});

const nodeReference = (key: string, label: string, capability?: string): PropertyDescriptor => ({
  key, label, group: 'Nodes', value: { kind: 'node-reference', ...(capability ? { capability } : {}) },
  required: true, serialized: true, inspector: 'node', overridable: true,
});

const jsonProperty = (key: string, label: string, group: string, defaultValue: JsonValue): PropertyDescriptor => ({
  key, label, group, value: { kind: 'json' }, defaultValue,
  serialized: true, inspector: 'json', overridable: true,
});

const stringProperty = (key: string, label: string, group: string): PropertyDescriptor => ({
  key, label, group, value: { kind: 'string', minLength: 1 }, required: true,
  serialized: true, inspector: 'text', overridable: true,
});

type JsonValue = import('../../content/scenes/types').JsonValue;

export const CHARACTER_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.character',
  displayName: 'Character Script',
  description: 'Common character state and movement helpers.',
  sourcePath: 'src/game/features/scripts/CharacterScript.ts',
  capabilities: ['character-script'],
  exclusiveCapabilities: ['character-controller'],
  properties: [
    nodeReference('body', 'Character Body', 'character-body'),
    nodeReference('visual', 'Visual', undefined),
    nodeReference('animation', 'Animation Player', undefined),
  ],
};

export const ENEMY_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.enemy',
  displayName: 'Enemy Script',
  description: 'Faction, targeting, health, damage, effects, rewards, and death for every hostile rank.',
  sourcePath: 'src/game/features/scripts/EnemyScript.ts',
  extends: 'game.character',
  capabilities: ['enemy-script', 'damage-receiver'],
  references: [
    { key: 'body', label: 'Character Body', required: true, expectedCapability: 'character-body' },
    { key: 'visual', label: 'Visual', required: true },
    { key: 'animation', label: 'Animation Player', required: true, expectedNodeType: 'AnimationPlayer' },
    { key: 'damageArea', label: 'Damage Area', required: true, expectedCapability: 'area' },
    { key: 'attackArea', label: 'Attack Area', required: true, expectedCapability: 'area' },
  ],
  properties: [
    nodeReference('damageArea', 'Damage Area', 'area'),
    nodeReference('attackArea', 'Attack Area', 'area'),
    { key: 'faction', label: 'Faction', group: 'Identity', value: { kind: 'string', minLength: 1 }, defaultValue: 'hostile', serialized: true, inspector: 'text', overridable: true },
    { key: 'rank', label: 'Rank', group: 'Identity', value: { kind: 'enum', values: ['ordinary', 'elite', 'boss'] }, defaultValue: 'ordinary', serialized: true, inspector: 'select', overridable: true },
    numberProperty('maxHealth', 'Maximum Health', 1, 'Health'),
    numberProperty('targetingRadius', 'Targeting Radius', 0, 'Targeting'),
    numberProperty('attackRange', 'Attack Range', 0, 'Targeting'),
    numberProperty('movementSpeed', 'Movement Speed', 0, 'Movement'),
    numberProperty('attackCooldownMs', 'Attack Cooldown', 0, 'Combat'),
    jsonProperty('attributes', 'Attributes', 'Combat', {}),
    jsonProperty('projectile', 'Projectile', 'Combat', {}),
    jsonProperty('impactEffect', 'Impact Effect', 'Presentation', {}),
    jsonProperty('damageRule', 'Damage Rule', 'Damage Reception', { priority: 0, damageMultiplier: 1 }),
    jsonProperty('rewards', 'Rewards', 'Rewards', {}),
  ],
  signals: [
    { id: 'health_changed', payload: 'EnemyHealthChanged' },
    { id: 'damaged', payload: 'DamageCommit' },
    { id: 'damage_feedback', payload: 'DamageCommit' },
    { id: 'defeated', payload: 'EnemyDefeated' },
    { id: 'reward_requested', payload: 'EnemyRewardRequest' },
  ],
};

export const PLAYER_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.player',
  displayName: 'Player Script',
  description: 'Node-backed player movement, dodge state, damage reception, and typed runtime ports.',
  sourcePath: 'src/game/features/scripts/PlayerScript.ts',
  extends: 'game.character',
  capabilities: ['player-script', 'damage-receiver', 'player-runtime'],
  references: [
    { key: 'body', label: 'Character Body', required: true, expectedCapability: 'character-body' },
    { key: 'visual', label: 'Visual', required: true },
    { key: 'animation', label: 'Animation Player', required: true, expectedNodeType: 'AnimationPlayer' },
    { key: 'damageArea', label: 'Damage Area', required: true, expectedCapability: 'area' },
  ],
  properties: [
    nodeReference('damageArea', 'Damage Area', 'area'),
    stringProperty('playerName', 'Player Name', 'Identity'),
  ],
  signals: [
    { id: 'health_changed', payload: 'PlayerHealthChanged' },
    { id: 'damaged', payload: 'DamageCommit' },
    { id: 'damage_feedback', payload: 'DamageCommit' },
    { id: 'defeated', payload: 'PlayerDefeated' },
  ],
};

export const NPC_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.npc',
  displayName: 'NPC Script',
  description: 'Node-backed NPC wandering, presentation, and interaction locking.',
  sourcePath: 'src/game/features/scripts/NpcScript.ts',
  extends: 'game.character',
  capabilities: ['npc-script', 'interactable'],
  references: [
    { key: 'body', label: 'Character Body', required: true, expectedCapability: 'character-body' },
    { key: 'visual', label: 'Visual', required: true },
    { key: 'animation', label: 'Animation Player', required: true, expectedNodeType: 'AnimationPlayer' },
  ],
  properties: [
    stringProperty('characterId', 'Character ID', 'Identity'),
    numberProperty('wanderSpeed', 'Wander Speed', 0, 'Movement'),
    numberProperty('pauseMinMs', 'Minimum Pause', 0, 'Movement'),
    numberProperty('pauseMaxMs', 'Maximum Pause', 0, 'Movement'),
  ],
  signals: [
    { id: 'interaction_lock_changed', payload: 'NpcLockChanged' },
  ],
};

export const FATTY_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.fatty',
  displayName: 'Fatty Script',
  description: 'Fatty-specific hop, leap, airborne, landing, recovery, and return states.',
  sourcePath: 'src/game/features/scripts/FattyScript.ts',
  extends: 'game.enemy',
  capabilities: ['fatty-behavior'],
  properties: [
    nodeReference('contactAttack', 'Contact-Hop Attack Area', 'area'),
    numberProperty('contactHopCooldownMs', 'Contact-Hop Cooldown', 1000, 'Fatty'),
    numberProperty('contactHopDurationMs', 'Contact-Hop Duration', 300, 'Fatty'),
    numberProperty('leapCadenceMs', 'Leap Cadence', 5000, 'Fatty'),
    numberProperty('smallHopCount', 'Small Hop Count', 3, 'Fatty'),
    numberProperty('smallHopDurationMs', 'Small Hop Duration', 260, 'Fatty'),
    numberProperty('betweenHopsMs', 'Between Hops', 100, 'Fatty'),
    numberProperty('airTimeMs', 'Air Time', 1000, 'Fatty'),
    numberProperty('recoveryMs', 'Recovery', 700, 'Fatty'),
    numberProperty('landingDamage', 'Landing Damage', 32, 'Fatty'),
    numberProperty('landingRadius', 'Landing Radius', 64, 'Fatty'),
  ],
  references: [{ key: 'contactAttack', label: 'Contact-Hop Attack Area', required: true, expectedCapability: 'area' }],
  signals: [{ id: 'phase_changed', payload: 'FattyPhaseChanged' }],
};

export const CHEST_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.chest',
  displayName: 'Chest Script',
  description: 'Guard, persistent contents, transactional transfer, and typed view intents.',
  sourcePath: 'src/game/features/scripts/ChestScript.ts',
  capabilities: ['chest', 'interactable'],
  exclusiveCapabilities: ['interaction-controller'],
  properties: [
    stringProperty('mapId', 'Map ID', 'Persistence'),
    stringProperty('instanceId', 'Instance ID', 'Persistence'),
    jsonProperty('initialContents', 'Initial Contents', 'Contents', {}),
  ],
  signals: [
    { id: 'guard_blocked', payload: 'ChestIdentity' },
    { id: 'open_requested', payload: 'ChestViewModel' },
    { id: 'stack_transferred', payload: 'ChestTransfer' },
    { id: 'closed', payload: 'ChestIdentity' },
  ],
};

export const BOSS_CAMP_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.boss-camp',
  displayName: 'Boss Camp Script',
  description: 'Activation, dynamic boss spawning, respawn, boss UI, and guarded chest state.',
  sourcePath: 'src/game/features/scripts/BossCampScript.ts',
  capabilities: ['boss-camp', 'encounter'],
  exclusiveCapabilities: ['encounter-controller'],
  references: [
    { key: 'activationArea', label: 'Activation Area', required: true, expectedCapability: 'area' },
    { key: 'arenaArea', label: 'Arena Area', required: true, expectedCapability: 'area' },
    { key: 'activeBosses', label: 'Active Boss Container', required: true },
    { key: 'guardedChest', label: 'Guarded Chest', required: true },
  ],
  properties: [
    stringProperty('mapId', 'Map ID', 'Persistence'),
    stringProperty('campId', 'Camp ID', 'Persistence'),
    stringProperty('bossId', 'Boss ID', 'Boss'),
    { key: 'bossScene', label: 'Boss Scene', group: 'Boss', value: { kind: 'scene-reference', dynamic: true }, required: true, serialized: true, inspector: 'scene', overridable: true },
    nodeReference('activationArea', 'Activation Area', 'area'),
    nodeReference('arenaArea', 'Arena Area', 'area'),
    nodeReference('activeBosses', 'Active Boss Container'),
    nodeReference('guardedChest', 'Guarded Chest'),
    stringProperty('guardedChestInstanceId', 'Guarded Chest Instance ID', 'Guard'),
    numberProperty('respawnMs', 'Respawn Delay', 180000, 'Respawn'),
    { key: 'spawn', label: 'Boss Spawn', group: 'Boss', value: { kind: 'vector2' }, defaultValue: [0, 0], serialized: true, inspector: 'vector2', overridable: true },
  ],
  signals: [
    { id: 'boss_spawn_requested', payload: 'BossSceneSpawnRequest' },
    { id: 'boss_defeated', payload: 'BossIdentity' },
    { id: 'guard_changed', payload: 'ChestGuardChanged' },
  ],
};

export const WEAPON_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.weapon',
  displayName: 'Weapon Script',
  description: 'Scene-owned weapon timing, directional hitbox windows, and presentation playback.',
  sourcePath: 'src/game/features/scripts/WeaponScript.ts',
  capabilities: ['weapon-script', 'attack-source'],
  exclusiveCapabilities: ['weapon-controller'],
  references: [
    { key: 'attackArea', label: 'Attack Area', required: true, expectedCapability: 'area' },
    { key: 'animation', label: 'Animation Player', required: true, expectedNodeType: 'AnimationPlayer' },
  ],
  properties: [
    stringProperty('weaponId', 'Weapon ID', 'Identity'),
    { key: 'category', label: 'Category', group: 'Identity', value: { kind: 'enum', values: ['melee', 'ranged'] }, defaultValue: 'melee', serialized: true, inspector: 'select', overridable: true },
    nodeReference('attackArea', 'Attack Area', 'area'),
    nodeReference('animation', 'Animation Player'),
    numberProperty('baseDamage', 'Base Damage', 0, 'Combat'),
    numberProperty('cooldownMs', 'Cooldown', 0, 'Combat'),
    numberProperty('knockStrength', 'Knockback Strength', 0, 'Combat'),
    { key: 'onHitEffectId', label: 'On-Hit Effect ID', group: 'Presentation', value: { kind: 'string' }, serialized: true, inspector: 'text', overridable: true },
    jsonProperty('damageModifiers', 'Damage Modifiers', 'Combat', []),
    jsonProperty('harvestCapabilities', 'Harvest Capabilities', 'Combat', {}),
    jsonProperty('scaling', 'Attribute Scaling', 'Combat', {}),
    jsonProperty('attackPlans', 'Directional Attack Plans', 'Combat', {}),
  ],
  signals: [
    { id: 'attack_started', payload: 'WeaponAttackEvent' },
    { id: 'attack_finished', payload: 'WeaponAttackEvent' },
  ],
  handlers: [{ id: 'on_area_entered', payload: 'PhysicsContact' }],
};

export const PROJECTILE_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.projectile',
  displayName: 'Projectile Script',
  description: 'Scene-owned projectile launch, movement direction, rotation, and lifetime.',
  sourcePath: 'src/game/features/scripts/ProjectileScript.ts',
  capabilities: ['projectile-script', 'attack-source'],
  exclusiveCapabilities: ['projectile-controller'],
  references: [
    { key: 'body', label: 'Projectile Body', required: true, expectedCapability: 'character-body' },
    { key: 'visual', label: 'Visual', required: true },
    { key: 'animation', label: 'Animation Player', required: true, expectedNodeType: 'AnimationPlayer' },
    { key: 'attackArea', label: 'Attack Area', required: true, expectedCapability: 'area' },
  ],
  properties: [
    stringProperty('projectileId', 'Projectile ID', 'Identity'),
    nodeReference('body', 'Projectile Body', 'character-body'),
    nodeReference('visual', 'Visual'),
    nodeReference('animation', 'Animation Player'),
    nodeReference('attackArea', 'Attack Area', 'area'),
    numberProperty('defaultSpeed', 'Default Speed', 0, 'Movement'),
    numberProperty('lifetimeMs', 'Lifetime', 0, 'Movement'),
    { key: 'rotateToVelocity', label: 'Rotate to Velocity', group: 'Movement', value: { kind: 'boolean' }, defaultValue: false, serialized: true, inspector: 'checkbox', overridable: true },
  ],
  signals: [
    { id: 'launched', payload: 'ProjectileEvent' },
    { id: 'expired', payload: 'ProjectileEvent' },
  ],
  handlers: [{ id: 'on_area_entered', payload: 'PhysicsContact' }],
};

export const EFFECT_SCRIPT_DESCRIPTOR: ScriptDescriptor = {
  scriptId: 'game.effect',
  displayName: 'Effect Script',
  description: 'Scene-owned directional effect playback and finite lifetime.',
  sourcePath: 'src/game/features/scripts/EffectScript.ts',
  capabilities: ['effect-script'],
  exclusiveCapabilities: ['effect-controller'],
  references: [{ key: 'animation', label: 'Animation Player', required: true, expectedNodeType: 'AnimationPlayer' }],
  properties: [
    stringProperty('effectId', 'Effect ID', 'Identity'),
    nodeReference('animation', 'Animation Player'),
    numberProperty('lifetimeMs', 'Lifetime', 0, 'Playback'),
  ],
  signals: [{ id: 'finished', payload: 'EffectEvent' }],
};

export const GAME_SCRIPT_DESCRIPTORS = Object.freeze([
  CHARACTER_SCRIPT_DESCRIPTOR,
  PLAYER_SCRIPT_DESCRIPTOR,
  NPC_SCRIPT_DESCRIPTOR,
  ENEMY_SCRIPT_DESCRIPTOR,
  FATTY_SCRIPT_DESCRIPTOR,
  CHEST_SCRIPT_DESCRIPTOR,
  BOSS_CAMP_SCRIPT_DESCRIPTOR,
  WEAPON_SCRIPT_DESCRIPTOR,
  PROJECTILE_SCRIPT_DESCRIPTOR,
  EFFECT_SCRIPT_DESCRIPTOR,
]);

export function createGameScriptRegistry(services: ScriptServiceMap = {}): ScriptRegistry {
  return new ScriptRegistry(services)
    .registerDefinition({ descriptor: CHARACTER_SCRIPT_DESCRIPTOR, factory: (context) => new CharacterScript(context) })
    .registerDefinition({ descriptor: PLAYER_SCRIPT_DESCRIPTOR, factory: (context) => new PlayerScript(context) })
    .registerDefinition({ descriptor: NPC_SCRIPT_DESCRIPTOR, factory: (context) => new NpcScript(context) })
    .registerDefinition({ descriptor: ENEMY_SCRIPT_DESCRIPTOR, factory: (context) => new EnemyScript(context) })
    .registerDefinition({ descriptor: FATTY_SCRIPT_DESCRIPTOR, factory: (context) => new FattyScript(context) })
    .registerDefinition({ descriptor: CHEST_SCRIPT_DESCRIPTOR, factory: (context) => new ChestScript(context) })
    .registerDefinition({ descriptor: BOSS_CAMP_SCRIPT_DESCRIPTOR, factory: (context) => new BossCampScript(context) })
    .registerDefinition({ descriptor: WEAPON_SCRIPT_DESCRIPTOR, factory: (context) => new WeaponScript(context) })
    .registerDefinition({ descriptor: PROJECTILE_SCRIPT_DESCRIPTOR, factory: (context) => new ProjectileScript(context) })
    .registerDefinition({ descriptor: EFFECT_SCRIPT_DESCRIPTOR, factory: (context) => new EffectScript(context) });
}

export function createGameDescriptorRegistry() {
  return createCoreDescriptorRegistry(GAME_SCRIPT_DESCRIPTORS);
}
