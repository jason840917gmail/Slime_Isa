import type { EnemyConfig } from '../enemies/Enemy';

export interface BossDef {
  id: string;
  name: string;
  areaId: string;
  config: EnemyConfig;
  reward: {
    coins: number;
    xp: number;
  };
}

export const BLOBFATHER: BossDef = {
  id: 'blobfather',
  name: 'The Blobfather',
  areaId: 'gloop-forest',
  config: {
    textureKey: 'enemy-blobfather',
    maxHp: 360,
    scale: 2.3,
    bodyWidth: 44,
    bodyHeight: 40,
    ai: {
      aggroRange: 520,
      attackRange: 58,
      leapRange: 170,
      wanderSpeed: 18,
      chaseSpeed: 82,
      attackCooldownMs: 1700,
      attackWindupMs: 650,
      contactDamage: 24,
      isRanged: false,
      isLeaper: true,
      knockbackResist: 0.82,
    },
    drop: { xp: 160, coins: 60, items: [{ itemId: 'silk-clump', chance: 1 }] },
    tint: 0x6bd45a,
  },
  reward: {
    coins: 180,
    xp: 220,
  },
};
