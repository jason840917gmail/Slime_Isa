import type { CharacterAttributeSet } from '../content/characters/types';

export type AttributeScaling = Partial<Record<keyof CharacterAttributeSet, number>>;

const ATTRIBUTE_BASELINE = 10;

/**
 * Resolves a data-authored attribute scaling bonus around the neutral value 10.
 * A coefficient of 0.5 means every 10 points above baseline adds 50%.
 */
export function resolveAttributeScaling(
  scaling: AttributeScaling | undefined,
  attributes: CharacterAttributeSet,
): number {
  if (!scaling) return 0;
  return (Object.entries(scaling) as Array<[keyof CharacterAttributeSet, number | undefined]>)
    .reduce((total, [attribute, coefficient]) => {
      if (!Number.isFinite(coefficient)) return total;
      return total + ((attributes[attribute] - ATTRIBUTE_BASELINE) / ATTRIBUTE_BASELINE) * (coefficient ?? 0);
    }, 0);
}

export function resolveScaledValue(
  baseValue: number,
  scaling: AttributeScaling | undefined,
  attributes: CharacterAttributeSet,
  minimum = 0,
): number {
  if (!Number.isFinite(baseValue)) return minimum;
  const multiplier = Math.max(0, 1 + resolveAttributeScaling(scaling, attributes));
  return Math.max(minimum, baseValue * multiplier);
}

