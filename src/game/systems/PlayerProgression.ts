import type { PlayerLevelDefinition, PlayerProgressionDefinition } from '../content/GameConstantsValidation';

export interface ResolvedLevelStats {
  readonly maxHp: number;
  readonly maxEnergy: number;
  readonly attack: number;
  readonly defense: number;
}

export interface ExperienceResult {
  readonly level: number;
  readonly currentXp: number;
  readonly levelsGained: readonly PlayerLevelDefinition[];
}

export function levelEntry(
  progression: PlayerProgressionDefinition,
  level: number,
): PlayerLevelDefinition {
  if (!Number.isInteger(level) || level < 1 || level > progression.maxLevel) {
    throw new RangeError(`Level ${level} is outside 1..${progression.maxLevel}`);
  }
  const entry = progression.levels[level - 1];
  if (!entry || entry.level !== level) throw new RangeError(`Progression entry for level ${level} is missing`);
  return entry;
}

export function resolveLevelStats(
  progression: PlayerProgressionDefinition,
  level: number,
): ResolvedLevelStats {
  levelEntry(progression, level);
  const stats: ResolvedLevelStats = {
    maxHp: progression.baseMaxHp,
    maxEnergy: progression.baseMaxEnergy,
    attack: progression.baseAttack,
    defense: progression.baseDefense,
  };
  return progression.levels.slice(1, level).reduce<ResolvedLevelStats>((total, entry) => ({
    maxHp: total.maxHp + entry.gains.maxHp,
    maxEnergy: total.maxEnergy + entry.gains.maxEnergy,
    attack: total.attack + entry.gains.attack,
    defense: total.defense + entry.gains.defense,
  }), stats);
}

export function applyExperience(
  progression: PlayerProgressionDefinition,
  level: number,
  currentXp: number,
  amount: number,
): ExperienceResult {
  levelEntry(progression, level);
  if (!Number.isFinite(currentXp) || currentXp < 0) throw new RangeError('Current XP must be finite and nonnegative');
  if (!Number.isFinite(amount) || amount < 0) throw new RangeError('XP amount must be finite and nonnegative');

  let nextLevel = level;
  let remainingXp = currentXp + amount;
  const levelsGained: PlayerLevelDefinition[] = [];
  while (nextLevel < progression.maxLevel) {
    const requirement = levelEntry(progression, nextLevel).xpToNextLevel;
    if (requirement === null || remainingXp < requirement) break;
    remainingXp -= requirement;
    nextLevel += 1;
    levelsGained.push(levelEntry(progression, nextLevel));
  }

  return {
    level: nextLevel,
    currentXp: nextLevel === progression.maxLevel ? 0 : remainingXp,
    levelsGained,
  };
}