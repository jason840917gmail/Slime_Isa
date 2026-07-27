export const PLAYER_CONFIG = {
  name: 'bob',
  body: {
    // Stable world-unit geometry migrated from the former 0.28-scaled
    // 108x80 body. Visual-set scale changes never affect this body.
    width: 30.24,
    height: 22.4,
    centerOffsetX: 0,
    centerOffsetY: 14.56,
  },
  movement: {
    baseSpeed: 230,
    boostSpeed: 360,
    dodgeSpeed: 420,
    dodgeInvulnerabilityMs: 400,
  },
  progression: {
    baseMaxHp: 100,
    baseMaxEnergy: 100,
    hpPerLevel: 12,
    attackPerLevel: 2,
    defensePerLevel: 1,
    energyPerLevel: 4,
  },
} as const;
