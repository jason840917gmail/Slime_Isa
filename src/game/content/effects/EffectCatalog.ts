import { effectDefinitions as authoredDefinitions } from 'virtual-effect-content';
import { normalizeEffectDefinition } from './normalize';
import type { EffectDefinition, NormalizedEffectDefinition } from './types';

const definitions = authoredDefinitions as unknown as readonly EffectDefinition[];
const normalized = definitions.map(normalizeEffectDefinition);
const byId = new Map(normalized.map((effect) => [effect.effectId, effect]));

export function getEffectDefinition(effectId: string): NormalizedEffectDefinition {
  const effect = byId.get(effectId);
  if (!effect) throw new Error(`Unknown effect '${effectId}'`);
  return effect;
}

export function getEffectDefinitions(): readonly NormalizedEffectDefinition[] {
  return normalized;
}
