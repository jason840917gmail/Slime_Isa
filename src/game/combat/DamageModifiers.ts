import type { WeaponDamageModifier } from '../content/weapons/types';

/**
 * Resolves the first modifier for the target's ordered tags. Content should
 * put the most specific tag first (for example `wood` before `resource`).
 */
export function resolveDamageModifier(
  modifiers: readonly WeaponDamageModifier[] | undefined,
  targetTags: readonly string[],
): number {
  if (!modifiers || modifiers.length === 0 || targetTags.length === 0) return 1;

  for (const targetTag of targetTags) {
    const match = modifiers.find((entry) => entry.targetTag === targetTag);
    if (match) return match.modifier;
  }

  return 1;
}
