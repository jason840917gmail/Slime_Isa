import type { PlayerProgressionDefinition } from '../../Constant';
import { levelEntry } from '../../systems/PlayerProgression';

export interface MigratedPlayerProgression {
  readonly level: number;
  readonly currentXp: number;
}

export function legacyCumulativeXpForLevel(level: number): number {
  if (level <= 1) return 0;
  let total = 0;
  for (let nextLevel = 2; nextLevel <= level; nextLevel += 1) {
    total += Math.round(80 * Math.pow(nextLevel - 1, 1.5));
  }
  return total;
}

export function migratePlayerProgression(
  progression: PlayerProgressionDefinition,
  level: unknown,
  legacyXp: unknown,
): MigratedPlayerProgression {
  if (!Number.isInteger(level) || (level as number) < 1 || (level as number) > progression.maxLevel) {
    throw new RangeError(`Saved level must be an integer within 1..${progression.maxLevel}`);
  }
  if (typeof legacyXp !== 'number' || !Number.isFinite(legacyXp) || legacyXp < 0) {
    throw new RangeError('Legacy cumulative XP must be finite and nonnegative');
  }
  const savedLevel = level as number;
  if (savedLevel === progression.maxLevel) return { level: savedLevel, currentXp: 0 };
  const requirement = levelEntry(progression, savedLevel).xpToNextLevel;
  if (requirement === null) return { level: savedLevel, currentXp: 0 };
  const rawRemainder = legacyXp - legacyCumulativeXpForLevel(savedLevel);
  return {
    level: savedLevel,
    currentXp: Math.min(Math.max(0, rawRemainder), requirement - 1),
  };
}
