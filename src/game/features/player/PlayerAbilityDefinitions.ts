import type { PassiveAbilityId, PlayerAbilityId } from '../../content/abilities';
import { GAME_CONSTANTS } from '../../Constant';
import type { PlayerInputAction } from './PlayerInputActions';

export {
  isPassiveAbilityId,
  isPlayerAbilityId,
  PASSIVE_ABILITY_IDS,
  PLAYER_ABILITY_IDS,
  type PassiveAbilityId,
  type PlayerAbilityId,
} from '../../content/abilities';

export interface PlayerAbilityDefinition {
  /** Player-facing name, used when the ability is learned. */
  readonly title: string;
  /** The control that uses it; its key label comes from the binding table. */
  readonly action: PlayerInputAction;
  /** How a locked ability is earned, shown on the ability bar ("Quest", "Boss"). */
  readonly earnedBy: string;
  readonly cooldownMs: number;
  readonly energyCost: number;
  readonly distance?: number;
  readonly durationMs?: number;
  readonly radius?: number;
  readonly damage?: number;
}

const { dodgeDurationMs, dodgeCooldownMs } = GAME_CONSTANTS.character.player.movement;

/**
 * Ability balance owned by the player feature until promoted into game constants.
 * Abilities are taught by the story (quest and boss rewards), never by level:
 * Dodge and Jump by Chapter 1 quests, Stretch Lash and Squash Slam in Chapter 2,
 * Teleport later. The dodge's timing lives in game constants (`movement`); its
 * cooldown runs from the start of the roll, so the wait after it ends is
 * `dodgeCooldownMs`.
 */
export const PLAYER_ABILITY_DEFINITIONS: Readonly<Record<PlayerAbilityId, PlayerAbilityDefinition>> = {
  jump: { title: 'Jump', action: 'jump', earnedBy: 'Quest', cooldownMs: 700, energyCost: 0, distance: 168, durationMs: 420 },
  dodge: { title: 'Dodge', action: 'dodge', earnedBy: 'Quest', cooldownMs: dodgeDurationMs + dodgeCooldownMs, energyCost: 0, durationMs: dodgeDurationMs },
  teleport: { title: 'Teleport', action: 'teleport', earnedBy: 'Later', cooldownMs: 1800, energyCost: 35, distance: 240 },
  'squash-slam': { title: 'Squash Slam', action: 'squash-slam', earnedBy: 'Boss', cooldownMs: 2500, energyCost: 30, radius: 90, damage: 30 },
  // A goo hook, not a weapon: no damage (LegacyPlayerAbilityPresentation.presentStretchLash).
  'stretch-lash': { title: 'Stretch Lash', action: 'stretch-lash', earnedBy: 'Quest', cooldownMs: 2000, energyCost: 20, distance: 180 },
};

export interface PassiveAbilityDefinition {
  readonly title: string;
  /** Shown when the ability is learned. */
  readonly learnedText: string;
}

/**
 * Passive abilities, taught by a later quest whose mission needs them. The
 * Goo Trail's balance (mark lifetime, slow radius) lives with `SlimeTrail`.
 */
export const PASSIVE_ABILITY_DEFINITIONS: Readonly<Record<PassiveAbilityId, PassiveAbilityDefinition>> = {
  'goo-trail': { title: 'Goo Trail', learnedText: 'Goo Trail learned: enemies on your goo slow down' },
};

/** Player-facing name of any learnable ability. */
export function abilityTitle(abilityId: string): string {
  if (abilityId in PLAYER_ABILITY_DEFINITIONS) return PLAYER_ABILITY_DEFINITIONS[abilityId as PlayerAbilityId].title;
  if (abilityId in PASSIVE_ABILITY_DEFINITIONS) return PASSIVE_ABILITY_DEFINITIONS[abilityId as PassiveAbilityId].title;
  return abilityId;
}
