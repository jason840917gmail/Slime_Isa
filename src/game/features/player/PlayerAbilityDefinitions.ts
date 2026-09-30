import type { PlayerAbilityId } from '../../content/abilities';

export { isPlayerAbilityId, PLAYER_ABILITY_IDS, type PlayerAbilityId } from '../../content/abilities';

export interface PlayerAbilityDefinition {
  /** Player-facing name, used when the ability is learned. */
  readonly title: string;
  /** Keyboard key that uses the ability. */
  readonly key: string;
  /** How a locked ability is earned, shown on the ability bar ("Quest", "Boss"). */
  readonly earnedBy: string;
  readonly cooldownMs: number;
  readonly energyCost: number;
  readonly distance?: number;
  readonly durationMs?: number;
  readonly radius?: number;
  readonly damage?: number;
}

/**
 * Ability balance owned by the player feature until promoted into game constants.
 * Abilities are taught by the story (quest and boss rewards), never by level:
 * Jump by a Chapter 1 quest, Stretch Lash and Squash Slam in Chapter 2,
 * Teleport later.
 */
export const PLAYER_ABILITY_DEFINITIONS: Readonly<Record<PlayerAbilityId, PlayerAbilityDefinition>> = {
  jump: { title: 'Jump', key: 'Space', earnedBy: 'Quest', cooldownMs: 700, energyCost: 0, distance: 168, durationMs: 420 },
  teleport: { title: 'Teleport', key: 'Y', earnedBy: 'Later', cooldownMs: 1800, energyCost: 35, distance: 240 },
  'squash-slam': { title: 'Squash Slam', key: 'T', earnedBy: 'Boss', cooldownMs: 2500, energyCost: 30, radius: 90, damage: 30 },
  'stretch-lash': { title: 'Stretch Lash', key: 'R', earnedBy: 'Quest', cooldownMs: 2000, energyCost: 20, distance: 180, damage: 18 },
};
