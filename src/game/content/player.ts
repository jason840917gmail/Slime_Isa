export const PLAYER_CONFIG = {
  name: 'bob',
  textureKey: 'slime',
  scale: 0.28,
  depth: 10,
  body: {
    width: 108,
    height: 80,
    offsetX: 74,
    offsetY: 140,
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
