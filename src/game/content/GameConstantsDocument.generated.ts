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
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "resources".
 */
export interface Resources {
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
  progression: Progression;
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
 * via the `definition` "progression".
 */
export interface Progression {
  maxLevel: PositiveInteger;
  baseMaxHp: number;
  baseMaxEnergy: number;
  baseAttack: NonNegative;
  baseDefense: NonNegative;
  /**
   * @minItems 1
   */
  levels: [Level, ...Level[]];
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "level".
 */
export interface Level {
  level: PositiveInteger;
  xpToNextLevel: number | null;
  gains: Gains;
}
/**
 * This interface was referenced by `GameConstantsDocument`'s JSON-Schema
 * via the `definition` "gains".
 */
export interface Gains {
  maxHp: NonNegative;
  maxEnergy: NonNegative;
  attack: NonNegative;
  defense: NonNegative;
}
