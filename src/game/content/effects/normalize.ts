import { normalizeLayeredAnimation } from '../../shared/animation';
import type { EffectDefinition, EffectDirection, NormalizedEffectDefinition, NormalizedEffectVariant } from './types';

export const EFFECT_DIRECTIONS = ['right', 'left', 'up', 'down'] as const satisfies readonly EffectDirection[];

export function resolveEffectVariant(
  effect: EffectDefinition,
  direction: EffectDirection,
): NormalizedEffectVariant | undefined {
  const exact = effect.directions?.[direction];
  if (exact) return { animation: normalizeLayeredAnimation({ ...exact, loop: false }), mirrored: false, source: direction };
  if (direction === 'left' && effect.mirrorLeftFromRight && effect.directions?.right) {
    return { animation: normalizeLayeredAnimation({ ...effect.directions.right, loop: false }), mirrored: true, source: 'right' };
  }
  if (effect.default) return { animation: normalizeLayeredAnimation({ ...effect.default, loop: false }), mirrored: false, source: 'default' };
  return undefined;
}

export function normalizeEffectDefinition(effect: EffectDefinition): NormalizedEffectDefinition {
  const variants = Object.fromEntries(EFFECT_DIRECTIONS.map((direction) => {
    const variant = resolveEffectVariant(effect, direction);
    if (!variant) throw new Error(`Effect '${effect.effectId}' does not resolve direction '${direction}'`);
    return [direction, variant];
  })) as unknown as Readonly<Record<EffectDirection, NormalizedEffectVariant>>;
  return { version: 1, effectId: effect.effectId, displayName: effect.displayName, variants };
}
