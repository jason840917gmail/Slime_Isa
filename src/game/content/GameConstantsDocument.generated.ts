// Generated from game-constants.schema.json. Run `pnpm constants:generate`; do not edit.

/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "resourceTag".
 */
export type ResourceTag = string;
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "positiveInteger".
 */
export type PositiveInteger = number;
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "nonNegative".
 */
export type NonNegative = number;

export interface GameConstantsDocument {
  $schema: string;
  version: 1;
  resources: Resources;
  inventory: Inventory;
  character: {
    player: Player;
  };
  worldNavigation: {
    edgeTransitionGraceMs: number;
  };
  rest: {
    /**
     * HP restored per second while the player sleeps in a bed.
     */
    sleepHpRegenPerSec: number;
  };
  gulp: {
    /**
     * How long a Gulp form lasts after eating its material, in milliseconds. Eating the same material at a Gulp spot restarts the timer.
     */
    formDurationMs: number;
  };
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "resources".
 */
export interface Resources {
  /**
   * How long a harvested tree, stone node or ore node stays gone, in milliseconds. It grows back the next time its map loads after this time, once its dropped piles are collected.
   */
  respawnMs: number;
  /**
   * @minItems 1
   */
  tags: [ResourceTag, ...ResourceTag[]];
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "inventory".
 */
export interface Inventory {
  initialMaxSlots: PositiveInteger;
  maxStackByItem: {
    [k: string]: PositiveInteger;
  };
  weaponMaxStack: PositiveInteger;
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "player".
 */
export interface Player {
  initialAttributes: Attributes;
  movement: Movement;
  hitInvulnerabilityMs: number;
  stats: PlayerStats;
  gooHeart: GooHeart;
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "attributes".
 */
export interface Attributes {
  strength: NonNegative;
  vitality: NonNegative;
  agility: NonNegative;
  intellect: NonNegative;
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "movement".
 */
export interface Movement {
  baseSpeed: NonNegative;
  boostSpeed: NonNegative;
  dodgeSpeed: NonNegative;
  dodgeInvulnerabilityMs: number;
  movementSpeedCap: NonNegative;
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "playerStats".
 */
export interface PlayerStats {
  maxHp: number;
  maxEnergy: number;
  attack: NonNegative;
  defense: NonNegative;
  critChance: number;
  critMultiplier: number;
  energyRegenPerSecond: NonNegative;
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "gooHeart".
 */
export interface GooHeart {
  maxHpBonus: number;
}
