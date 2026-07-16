import { gameState } from '../core/GameState';
import type { PerkChoice } from '../core/types';

/**
 * Derived player stats. Reads level + perks from GameState and produces the
 * final combat/movement numbers. Pure read-side — does not mutate state.
 *
 * Stat growth (per level): +12 maxHp, +2 atk, +1 def, +4 energy (see GameState).
 * Perks apply multiplicative or additive bonuses on top of the level base.
 */

export interface DerivedStats {
  maxHp: number;
  attack: number;
  defense: number;
  speed: number;
  critChance: number;
  critMult: number;
  maxEnergy: number;
  /** Energy regen per second. */
  energyRegenPerSec: number;
  /** Weapon reach multiplier (1 = base, 1.25 = +25% per rank). */
  weaponReachMult: number;
  /** Weapon attack cone width in radians. Max rank reaches PI = 180 degrees. */
  weaponArcRad: number;
  /** Percent of enemy melee damage returned as HP. */
  lifeStealPct: number;
  /** Damage taken multiplier (lower = tankier). 0.9 = 10% reduction. */
  damageTakenMult: number;
  /** I-frame duration in ms after a hit. */
  iFrameMs: number;
}

const BASE_WEAPON_ARC_RAD = 0.8;
const MAX_WEAPON_ARC_RAD = Math.PI;

const PERK_DEFS: Record<string, { title: string; description: string; icon?: string; maxRank: number }> = {
  'tanky-goo': { title: 'Tanky Goo', description: '+15 max HP per rank', icon: 'perk-tanky', maxRank: 3 },
  'sharp-fangs': { title: 'Sharp Fangs', description: '+15% attack per rank', icon: 'perk-fangs', maxRank: 3 },
  'thick-skin': { title: 'Thick Skin', description: '-8% damage taken per rank', icon: 'perk-skin', maxRank: 3 },
  'quick-steps': { title: 'Quick Steps', description: '+25 move speed per rank', icon: 'perk-quick', maxRank: 3 },
  'lucky-crit': { title: 'Lucky Crit', description: '+8% crit chance per rank', icon: 'perk-crit', maxRank: 3 },
  'deep-well': { title: 'Deep Well', description: '+20 max energy per rank', icon: 'perk-well', maxRank: 3 },
  'quick-recovery': { title: 'Quick Recovery', description: '+50% energy regen per rank', icon: 'perk-recovery', maxRank: 3 },
  'long-reach': { title: 'Long Reach', description: '+25% weapon reach per rank', icon: 'perk-reach', maxRank: 3 },
  'wide-swing': { title: 'Wide Swing', description: 'Widen attack cone; max rank is 180 degrees', icon: 'perk-wide', maxRank: 3 },
  'vampiric-goo': { title: 'Vampiric Goo', description: '+6% life steal per rank on enemy hits', icon: 'perk-lifesteal', maxRank: 3 },
};

export const ALL_PERK_IDS = Object.keys(PERK_DEFS);

export function getPerkDef(perkId: string) {
  return PERK_DEFS[perkId];
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
  const level = gameState.level;
  const baseAttack = 10 + (level - 1) * 2;
  const baseDefense = 2 + (level - 1) * 1;

  const tanky = gameState.perkRank('tanky-goo');
  const fangs = gameState.perkRank('sharp-fangs');
  const skin = gameState.perkRank('thick-skin');
  const quick = gameState.perkRank('quick-steps');
  const crit = gameState.perkRank('lucky-crit');
  const well = gameState.perkRank('deep-well');
  const recovery = gameState.perkRank('quick-recovery');
  const reach = gameState.perkRank('long-reach');
  const wideSwing = gameState.perkRank('wide-swing');
  const vampiric = gameState.perkRank('vampiric-goo');
  const weaponArcRad = BASE_WEAPON_ARC_RAD + (MAX_WEAPON_ARC_RAD - BASE_WEAPON_ARC_RAD) * (wideSwing / 3);

  return {
    maxHp: gameState.maxHp + tanky * 15,
    attack: Math.round(baseAttack * (1 + fangs * 0.15)),
    defense: baseDefense,
    speed: 230 + quick * 25,
    critChance: 0.05 + crit * 0.08,
    critMult: 1.75,
    maxEnergy: gameState.maxEnergy + well * 20,
    energyRegenPerSec: 8 * (1 + recovery * 0.5),
    weaponReachMult: 1 + reach * 0.25,
    weaponArcRad,
    lifeStealPct: vampiric * 0.06,
    damageTakenMult: Math.max(0.5, 1 - skin * 0.08),
    iFrameMs: 600,
  };
}
