import {
  DOWN_UP_INHERITANCE,
  normalizeLayeredAnimation,
  resolveDirectionalVariant,
  RIGHT_LEFT_INHERITANCE,
} from '../../shared/animation';
import type { EffectDefinition, EffectDirection, NormalizedEffectDefinition, NormalizedEffectVariant } from './types';

export const EFFECT_DIRECTIONS = ['right', 'left', 'up', 'down'] as const satisfies readonly EffectDirection[];

export function resolveEffectVariant(
  effect: EffectDefinition,
  direction: EffectDirection,
): NormalizedEffectVariant | undefined {
  const resolved = resolveDirectionalVariant(
    effect.directions ?? {},
    direction,
    {
      pairs: [
        { ...RIGHT_LEFT_INHERITANCE, enabled: effect.mirrorLeftFromRight === true },
        { ...DOWN_UP_INHERITANCE, enabled: effect.mirrorUpFromDown === true },
      ],
      defaultValue: effect.default,
    },
  );
  if (!resolved) return undefined;
  return {
    animation: normalizeLayeredAnimation({ ...resolved.value, loop: false }),
    authored: resolved.authored,
    source: resolved.sourceDirection,
    mirrorX: resolved.mirrorX,
    mirrorY: resolved.mirrorY,
  };
}

export function normalizeEffectDefinition(effect: EffectDefinition): NormalizedEffectDefinition {
  const variants = Object.fromEntries(EFFECT_DIRECTIONS.map((direction) => {
    const variant = resolveEffectVariant(effect, direction);
    if (!variant) throw new Error(`Effect '${effect.effectId}' does not resolve direction '${direction}'`);
    return [direction, variant];
  })) as unknown as Readonly<Record<EffectDirection, NormalizedEffectVariant>>;
  return { version: 1, effectId: effect.effectId, displayName: effect.displayName, variants };
}
