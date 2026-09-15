export type PlayerAbilityId = 'jump' | 'teleport' | 'squash-slam' | 'stretch-lash';

export interface PlayerAbilityDefinition {
  readonly unlockLevel: number;
  readonly cooldownMs: number;
  readonly energyCost: number;
  readonly distance?: number;
  readonly durationMs?: number;
  readonly radius?: number;
  readonly damage?: number;
}

/** Ability balance owned by the player feature until promoted into game constants. */
export const PLAYER_ABILITY_DEFINITIONS: Readonly<Record<PlayerAbilityId, PlayerAbilityDefinition>> = {
  jump: { unlockLevel: 2, cooldownMs: 700, energyCost: 0, distance: 168, durationMs: 420 },
  teleport: { unlockLevel: 5, cooldownMs: 1800, energyCost: 35, distance: 240 },
  'squash-slam': { unlockLevel: 3, cooldownMs: 2500, energyCost: 30, radius: 90, damage: 30 },
  'stretch-lash': { unlockLevel: 4, cooldownMs: 2000, energyCost: 20, distance: 180, damage: 18 },
};
