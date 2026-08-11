import { gameState } from '../core/GameState';
import type { PerkChoice } from '../core/types';
import { PLAYER_CONFIG } from '../content/player';
import { PERK_BALANCE, PERK_DEFS, PERK_IDS, type PerkId } from '../content/perks';
import type { CharacterAttributeSet } from '../content/characters/types';

/**
 * Derived player stats. Reads level + perks from GameState and produces the
 * final combat/movement numbers. Pure read-side — does not mutate state.
 *
 * Stat growth (per level): +12 maxHp, +2 atk, +1 def, +4 energy (see GameState).
 * Perks apply multiplicative or additive bonuses on top of the level base.
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
  /** Percent of enemy melee damage returned as HP. */
  lifeStealPct: number;
  /** Damage taken multiplier (lower = tankier). 0.9 = 10% reduction. */
  damageTakenMult: number;
  /** I-frame duration in ms after a hit. */
  iFrameMs: number;
}

export const MAX_MOVEMENT_SPEED = 480;

export function resolveMovementSpeed(baseSpeed: number, flatBonus = 0, multiplier = 1): number {
  if (!Number.isFinite(baseSpeed) || !Number.isFinite(flatBonus) || !Number.isFinite(multiplier)) return 0;
  return Math.min(MAX_MOVEMENT_SPEED, Math.max(0, (baseSpeed + flatBonus) * Math.max(0, multiplier)));
}

export const ALL_PERK_IDS = [...PERK_IDS];

export function getPerkDef(perkId: string) {
  return (PERK_IDS as readonly string[]).includes(perkId)
    ? PERK_DEFS[perkId as PerkId]
    : undefined;
}

/** Build the 3 random perk choices offered on a level-up. */
export function rollPerkChoices(): PerkChoice[] {
  const available = ALL_PERK_IDS.filter((id) => {
    const def = PERK_DEFS[id];
    return gameState.perkRank(id) < def.maxRank;
  });

  const pool = available.length > 0 ? available.slice() : ALL_PERK_IDS.slice();
  const choices: PerkChoice[] = [];
  const take = Math.min(3, pool.length);

  for (let i = 0; i < take; i += 1) {
    const idx = Math.floor(Math.random() * pool.length);
    const id = pool.splice(idx, 1)[0];
    const def = PERK_DEFS[id];
    choices.push({ id, title: def.title, description: def.description, icon: def.icon });
  }

  return choices;
}

export function getStats(): DerivedStats {
  const baseAttack = gameState.attackBase;
  const baseDefense = gameState.defenseBase;

  const fangs = gameState.perkRank('sharp-fangs');
  const skin = gameState.perkRank('thick-skin');
  const quick = gameState.perkRank('quick-steps');
  const crit = gameState.perkRank('lucky-crit');
  const recovery = gameState.perkRank('quick-recovery');
  const vampiric = gameState.perkRank('vampiric-goo');

  return {
    attributes: gameState.attributes,
    maxHp: gameState.maxHp,
    attack: Math.round(baseAttack * (1 + fangs * PERK_BALANCE.attackMultiplierPerSharpFangsRank)),
    defense: baseDefense,
    movementSpeed: resolveMovementSpeed(PLAYER_CONFIG.movement.baseSpeed, quick * PERK_BALANCE.speedPerQuickStepsRank),
    movementSpeedCap: MAX_MOVEMENT_SPEED,
    critChance: 0.05 + crit * PERK_BALANCE.critChancePerLuckyCritRank,
    critMult: 1.75,
    maxEnergy: gameState.maxEnergy,
    energyRegenPerSec: 8 * (1 + recovery * PERK_BALANCE.energyRegenMultiplierPerQuickRecoveryRank),
    lifeStealPct: vampiric * PERK_BALANCE.lifeStealPerVampiricGooRank,
    damageTakenMult: Math.max(0.5, 1 - skin * PERK_BALANCE.damageReductionPerThickSkinRank),
    iFrameMs: 500,
  };
}
