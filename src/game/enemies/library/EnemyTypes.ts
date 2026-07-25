import type { EnemyConfig } from '../Enemy';

/**
 * Enemy type library. Each config defines stats, AI behavior, and drops.
 * The spawner picks from a weighted table of these configs.
 */

export const ENEMY_CONFIGS: Record<string, EnemyConfig> = {
  // 1. Blob — slow, easy, contact damage only
  blob: {
    textureKey: 'enemy-blob',
    visualSetId: 'enemy.blob',
    defaultClip: 'idle',
    maxHp: 40,
    scale: 1.4,
    bodyWidth: 28,
    bodyHeight: 28,
    ai: {
      aggroRange: 180,
      attackRange: 28,
      wanderSpeed: 30,
      chaseSpeed: 60,
      attackCooldownMs: 1200,
      attackWindupMs: 300,
      contactDamage: 8,
      isRanged: false,
      knockbackResist: 0,
    },
    drop: { xp: 20, coins: 3 },
  },

  // 2. Spike Slime — retaliates, moderate HP
  spike: {
    textureKey: 'enemy-spike',
    maxHp: 70,
    scale: 1.4,
    bodyWidth: 28,
    bodyHeight: 28,
    ai: {
      aggroRange: 200,
      attackRange: 32,
      wanderSpeed: 28,
      chaseSpeed: 70,
      attackCooldownMs: 1500,
      attackWindupMs: 400,
      contactDamage: 14,
      isRanged: false,
      knockbackResist: 0.3,
    },
    drop: { xp: 35, coins: 6, items: [{ itemId: 'silk-clump', chance: 0.2 }] },
  },

  // 3. Bouncer — fast, leaps at player
  bouncer: {
    textureKey: 'enemy-bouncer',
    maxHp: 55,
    scale: 1.3,
    bodyWidth: 24,
    bodyHeight: 24,
    ai: {
      aggroRange: 240,
      attackRange: 30,
      leapRange: 120,
      wanderSpeed: 50,
      chaseSpeed: 140,
      attackCooldownMs: 1800,
      attackWindupMs: 500,
      contactDamage: 16,
      isRanged: false,
      isLeaper: true,
      knockbackResist: 0.1,
    },
    drop: { xp: 40, coins: 8 },
  },

  // 4. Caster Slime — ranged, keeps distance, low HP
  caster: {
    textureKey: 'enemy-caster',
    maxHp: 35,
    scale: 1.3,
    bodyWidth: 24,
    bodyHeight: 24,
    ai: {
      aggroRange: 280,
      attackRange: 220,
      fleeRange: 120,
      wanderSpeed: 30,
      chaseSpeed: 80,
      attackCooldownMs: 2200,
      attackWindupMs: 600,
      contactDamage: 6,
      isRanged: true,
      projectileSpeed: 180,
      knockbackResist: 0,
    },
    drop: { xp: 45, coins: 10, items: [{ itemId: 'shard', chance: 0.15 }] },
  },

  // 5. Swarmer — fast, low HP, comes in packs
  swarmer: {
    textureKey: 'enemy-swarmer',
    maxHp: 20,
    scale: 0.9,
    bodyWidth: 18,
    bodyHeight: 18,
    ai: {
      aggroRange: 200,
      attackRange: 22,
      wanderSpeed: 60,
      chaseSpeed: 160,
      attackCooldownMs: 800,
      attackWindupMs: 200,
      contactDamage: 6,
      isRanged: false,
      knockbackResist: 0,
    },
    drop: { xp: 12, coins: 2 },
  },

  // 6. Armored Slime — high HP, knockback resistant
  armored: {
    textureKey: 'enemy-armored',
    maxHp: 120,
    scale: 1.6,
    bodyWidth: 32,
    bodyHeight: 32,
    ai: {
      aggroRange: 180,
      attackRange: 34,
      wanderSpeed: 20,
      chaseSpeed: 50,
      attackCooldownMs: 2000,
      attackWindupMs: 500,
      contactDamage: 18,
      isRanged: false,
      knockbackResist: 0.7,
    },
    drop: { xp: 60, coins: 15, items: [{ itemId: 'shard', chance: 0.3 }] },
  },

  // 7. Mimic — looks like a collectible, ambushes
  mimic: {
    textureKey: 'enemy-mimic',
    maxHp: 80,
    scale: 1.3,
    bodyWidth: 26,
    bodyHeight: 26,
    ai: {
      aggroRange: 80,
      attackRange: 28,
      wanderSpeed: 0,
      chaseSpeed: 100,
      attackCooldownMs: 1200,
      attackWindupMs: 300,
      contactDamage: 20,
      isRanged: false,
      knockbackResist: 0.2,
    },
    drop: { xp: 50, coins: 30 },
  },

  // 8. Sticky Spider-Slime — ranged web, applies slow
  spider: {
    textureKey: 'enemy-spider',
    maxHp: 50,
    scale: 1.3,
    bodyWidth: 26,
    bodyHeight: 26,
    ai: {
      aggroRange: 260,
      attackRange: 200,
      fleeRange: 100,
      wanderSpeed: 35,
      chaseSpeed: 90,
      attackCooldownMs: 2500,
      attackWindupMs: 500,
      contactDamage: 10,
      isRanged: true,
      projectileSpeed: 140,
      knockbackResist: 0.15,
    },
    drop: { xp: 40, coins: 8, items: [{ itemId: 'silk-clump', chance: 0.4 }] },
  },
};

/** Weighted spawn tables per difficulty tier. */
export const SPAWN_TABLE_EASY: { config: EnemyConfig; weight: number }[] = [
  { config: ENEMY_CONFIGS.blob, weight: 50 },
  { config: ENEMY_CONFIGS.swarmer, weight: 30 },
  { config: ENEMY_CONFIGS.spike, weight: 20 },
];

export const SPAWN_TABLE_MEDIUM: { config: EnemyConfig; weight: number }[] = [
  { config: ENEMY_CONFIGS.blob, weight: 25 },
  { config: ENEMY_CONFIGS.swarmer, weight: 25 },
  { config: ENEMY_CONFIGS.spike, weight: 20 },
  { config: ENEMY_CONFIGS.bouncer, weight: 15 },
  { config: ENEMY_CONFIGS.caster, weight: 10 },
  { config: ENEMY_CONFIGS.spider, weight: 5 },
];

export const SPAWN_TABLE_HARD: { config: EnemyConfig; weight: number }[] = [
  { config: ENEMY_CONFIGS.spike, weight: 20 },
  { config: ENEMY_CONFIGS.bouncer, weight: 20 },
  { config: ENEMY_CONFIGS.caster, weight: 15 },
  { config: ENEMY_CONFIGS.armored, weight: 15 },
  { config: ENEMY_CONFIGS.spider, weight: 15 },
  { config: ENEMY_CONFIGS.swarmer, weight: 10 },
  { config: ENEMY_CONFIGS.mimic, weight: 5 },
];
