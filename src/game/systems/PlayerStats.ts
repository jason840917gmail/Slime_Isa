import { gameState } from '../core/GameState';
import { PLAYER_CONFIG } from '../content/player';
import { GAME_CONSTANTS } from '../Constant';
import type { CharacterAttributeSet } from '../content/characters/types';

/**
 * Derived player stats: base values from `game-constants.json`, max HP raised
 * by Goo Hearts. Pure read-side — does not mutate state. Gear (weapon damage and
 * scaling) is applied where the weapon is used.
 */

export interface DerivedStats {
  attributes: CharacterAttributeSet;
  maxHp: number;
  attack: number;
  defense: number;
  movementSpeed: number;
  movementSpeedCap: number;
  critChance: number;
  critMult: number;
  maxEnergy: number;
  /** Energy regen per second. */
  energyRegenPerSec: number;
  /** Damage taken multiplier (lower = tankier). 0.9 = 10% reduction. */
  damageTakenMult: number;
  /** I-frame duration in ms after a hit. */
  iFrameMs: number;
}

export const MAX_MOVEMENT_SPEED = GAME_CONSTANTS.character.player.movement.movementSpeedCap;

export function resolveMovementSpeed(baseSpeed: number, flatBonus = 0, multiplier = 1): number {
  if (!Number.isFinite(baseSpeed) || !Number.isFinite(flatBonus) || !Number.isFinite(multiplier)) return 0;
  return Math.min(MAX_MOVEMENT_SPEED, Math.max(0, (baseSpeed + flatBonus) * Math.max(0, multiplier)));
}

export function getStats(): DerivedStats {
  const stats = GAME_CONSTANTS.character.player.stats;
  return {
    attributes: gameState.attributes,
    maxHp: gameState.maxHp,
    attack: stats.attack,
    defense: stats.defense,
    movementSpeed: resolveMovementSpeed(PLAYER_CONFIG.movement.baseSpeed),
    movementSpeedCap: MAX_MOVEMENT_SPEED,
    critChance: stats.critChance,
    critMult: stats.critMultiplier,
    maxEnergy: gameState.maxEnergy,
    energyRegenPerSec: stats.energyRegenPerSecond,
    damageTakenMult: 1,
    iFrameMs: GAME_CONSTANTS.character.player.hitInvulnerabilityMs,
  };
}
