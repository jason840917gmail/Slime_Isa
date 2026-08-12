import { validateLayeredAnimationDocument, type LayeredAnimationValidationOptions } from '../../shared/animation';
import { EFFECT_DIRECTIONS, resolveEffectVariant } from './normalize';
import type { EffectDefinition } from './types';

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function validateEffectDefinition(
  value: unknown,
  options: Pick<LayeredAnimationValidationOptions, 'assetLookup'> = {},
): string[] {
  if (!isRecord(value)) return ['effect: must be an object'];
  const effect = value as unknown as EffectDefinition;
  const issues: string[] = [];
  if (effect.version !== 1) issues.push('effect.version: must be 1');
  if (typeof effect.effectId !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(effect.effectId)) issues.push('effect.effectId: must be a lowercase kebab-case ID');
  if (typeof effect.displayName !== 'string' || !effect.displayName.trim() || effect.displayName.length > 80) issues.push('effect.displayName: must contain 1 to 80 characters');
  if (effect.mirrorLeftFromRight !== undefined && typeof effect.mirrorLeftFromRight !== 'boolean') issues.push('effect.mirrorLeftFromRight: must be boolean');
  if (effect.default !== undefined) issues.push(...validateLayeredAnimationDocument(effect.default, { ...options, path: 'effect.default', allowLoop: false }));
  if (effect.directions !== undefined) {
    if (!isRecord(effect.directions)) issues.push('effect.directions: must be an object');
    else for (const [direction, animation] of Object.entries(effect.directions)) {
      if (!EFFECT_DIRECTIONS.includes(direction as never)) issues.push(`effect.directions.${direction}: unsupported direction`);
      else issues.push(...validateLayeredAnimationDocument(animation, { ...options, path: `effect.directions.${direction}`, allowLoop: false }));
    }
  }
  if (effect.mirrorLeftFromRight && !effect.directions?.right && !effect.default) issues.push('effect.mirrorLeftFromRight: requires a Right variant or Default fallback');
  for (const direction of EFFECT_DIRECTIONS) {
    try {
      if (!resolveEffectVariant(effect, direction)) issues.push(`effect: direction '${direction}' does not resolve to a usable variant`);
    } catch {
      issues.push(`effect: direction '${direction}' does not resolve to a usable variant`);
    }
  }
  return issues;
}
