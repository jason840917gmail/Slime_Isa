import type {
  AcceptedDamageResult,
  AttackSourceMatcher,
  DamageAreaRule,
  DamageEffectRequest,
  DamageReceiver,
  DamageReceiverState,
  DamageRequest,
  DamageResult,
  NormalizedDamageRequest,
} from './DamageReceiver';
import { rejectedDamage } from './DamageReceiver';

function isFiniteNonNegative(value: number): boolean {
  return Number.isFinite(value) && value >= 0;
}

function hasDuplicates(values: readonly string[]): boolean {
  return new Set(values).size !== values.length;
}

function validIdentifiers(values: readonly string[]): boolean {
  return values.every((value) => value.trim().length > 0) && !hasDuplicates(values);
}

function validMatcher(matcher: AttackSourceMatcher): boolean {
  const clauses = [matcher.weaponIds, matcher.allWeaponTags, matcher.anyDamageTypes]
    .filter((value): value is readonly string[] => value !== undefined);
  return clauses.length > 0 && clauses.every((value) => value.length > 0 && validIdentifiers(value));
}

export function normalizeDamageRequest(request: DamageRequest): NormalizedDamageRequest | undefined {
  const { impact } = request;
  if (
    request.activationId.trim().length === 0
    || request.sourceNodeId.trim().length === 0
    || request.attackAreaNodeId.trim().length === 0
    || request.targetAreaNodeId.trim().length === 0
    || !isFiniteNonNegative(request.baseDamage)
    || (request.trueDamage !== undefined && typeof request.trueDamage !== 'boolean')
    || !validIdentifiers(request.weaponTags)
    || !validIdentifiers(request.damageTypes)
    || ![impact.x, impact.y, impact.knockX, impact.knockY].every(Number.isFinite)
    || request.effects.some((effect) => effect.effectId.trim().length === 0 || !isFiniteNonNegative(effect.potency))
    || hasDuplicates(request.effects.map((effect) => effect.effectId))
  ) {
    return undefined;
  }

  return Object.freeze({
    ...request,
    weaponTags: Object.freeze([...request.weaponTags].sort()),
    damageTypes: Object.freeze([...request.damageTypes].sort()),
    effects: Object.freeze(request.effects
      .map((effect) => Object.freeze({ ...effect }))
      .sort((left, right) => left.effectId.localeCompare(right.effectId))),
    impact: Object.freeze({ ...impact }),
    trueDamage: request.trueDamage ?? false,
  });
}

export function damageSourceMatches(rule: DamageAreaRule, request: NormalizedDamageRequest): boolean {
  if (rule.blockedWeaponTags?.some((tag) => request.weaponTags.includes(tag))) return false;
  if (rule.acceptedSources === undefined) return true;
  if (rule.acceptedSources.length === 0 || rule.acceptedSources.some((matcher) => !validMatcher(matcher))) return false;

  return rule.acceptedSources.some((matcher) => {
    const weaponMatches = matcher.weaponIds === undefined
      || (request.weaponId !== undefined && matcher.weaponIds.includes(request.weaponId));
    const tagsMatch = matcher.allWeaponTags === undefined
      || matcher.allWeaponTags.every((tag) => request.weaponTags.includes(tag));
    const typesMatch = matcher.anyDamageTypes === undefined
      || matcher.anyDamageTypes.some((type) => request.damageTypes.includes(type));
    return weaponMatches && tagsMatch && typesMatch;
  });
}

export function validateDamageAreaRule(rule: DamageAreaRule): boolean {
  return rule.areaNodeId.trim().length > 0
    && Number.isSafeInteger(rule.priority)
    && isFiniteNonNegative(rule.damageMultiplier)
    && (rule.blockedWeaponTags === undefined || validIdentifiers(rule.blockedWeaponTags))
    && (rule.acceptedSources === undefined
      || (rule.acceptedSources.length > 0 && rule.acceptedSources.every(validMatcher)))
    && Object.values(rule.damageTypeMultipliers ?? {}).every(isFiniteNonNegative)
    && Object.values(rule.effectResponses ?? {}).every((response) => (
      response.mode === 'immune'
      || (response.mode === 'multiplier' && isFiniteNonNegative(response.multiplier))
    ));
}

function validState(state: DamageReceiverState): boolean {
  return Number.isFinite(state.hp)
    && Number.isFinite(state.maxHp)
    && state.maxHp >= 0
    && state.hp >= 0
    && state.hp <= state.maxHp;
}

function resolveEffects(
  effects: readonly DamageEffectRequest[],
  rule: DamageAreaRule,
): Pick<AcceptedDamageResult, 'appliedEffects' | 'rejectedEffects'> | undefined {
  const appliedEffects: Array<{ effectId: string; potency: number }> = [];
  const rejectedEffects: Array<{ effectId: string; reason: 'immune' | 'zero-potency' }> = [];

  for (const effect of effects) {
    const response = rule.effectResponses?.[effect.effectId];
    if (response?.mode === 'immune') {
      rejectedEffects.push({ effectId: effect.effectId, reason: 'immune' });
      continue;
    }
    const potency = effect.potency * (response?.mode === 'multiplier' ? response.multiplier : 1);
    if (!isFiniteNonNegative(potency)) return undefined;
    if (potency === 0) rejectedEffects.push({ effectId: effect.effectId, reason: 'zero-potency' });
    else appliedEffects.push({ effectId: effect.effectId, potency });
  }

  return {
    appliedEffects: Object.freeze(appliedEffects.map((effect) => Object.freeze(effect))),
    rejectedEffects: Object.freeze(rejectedEffects.map((effect) => Object.freeze(effect))),
  };
}

export function resolveDamage(
  receiver: DamageReceiver,
  request: DamageRequest | NormalizedDamageRequest,
  area: DamageAreaRule,
  simulationTime: number,
): DamageResult {
  return resolveDamageDetailed(receiver, request, area, simulationTime).result;
}

export interface DetailedDamageResolution {
  readonly result: DamageResult;
  /** Rounded damage before the remaining-HP clamp, retained for legacy feedback parity. */
  readonly roundedDamage: number;
}

export function resolveDamageDetailed(
  receiver: DamageReceiver,
  request: DamageRequest | NormalizedDamageRequest,
  area: DamageAreaRule,
  simulationTime: number,
): DetailedDamageResolution {
  const normalized = normalizeDamageRequest(request);
  if (!normalized || !validateDamageAreaRule(area) || area.areaNodeId !== normalized.targetAreaNodeId
    || !Number.isFinite(simulationTime)) return { result: rejectedDamage('invalid', false), roundedDamage: 0 };
  if (!damageSourceMatches(area, normalized)) {
    return { result: rejectedDamage('source-blocked', false), roundedDamage: 0 };
  }

  const state = receiver.getDamageState();
  if (!validState(state)) return { result: rejectedDamage('invalid', false), roundedDamage: 0 };
  if (state.dead || state.hp <= 0) return { result: rejectedDamage('dead', false), roundedDamage: 0 };

  let scaledDamage = normalized.baseDamage * area.damageMultiplier;
  for (const damageType of normalized.damageTypes) {
    scaledDamage *= area.damageTypeMultipliers?.[damageType] ?? 1;
  }
  if (!isFiniteNonNegative(scaledDamage)) return { result: rejectedDamage('invalid', false), roundedDamage: 0 };

  const mitigationInput = Object.freeze({ scaledDamage, request: normalized, area, state, simulationTime });
  const stateDecision = receiver.canReceiveDamage?.(mitigationInput);
  if (stateDecision && !stateDecision.accepted) {
    const reason = stateDecision.reason ?? 'state-blocked';
    return { result: rejectedDamage(reason, reason === 'state-blocked'), roundedDamage: 0 };
  }

  const mitigatedDamage = receiver.mitigateDamage?.(mitigationInput) ?? scaledDamage;
  if (!isFiniteNonNegative(mitigatedDamage)) return { result: rejectedDamage('invalid', false), roundedDamage: 0 };
  const roundedDamage = Math.max(0, Math.round(mitigatedDamage));
  const actualDamage = Math.min(state.hp, roundedDamage);
  const effects = resolveEffects(normalized.effects, area);
  if (!effects) return { result: rejectedDamage('invalid', false), roundedDamage: 0 };
  if (actualDamage === 0 && effects.appliedEffects.length === 0) {
    return { result: rejectedDamage('immune', false), roundedDamage };
  }

  const result = Object.freeze({
    status: 'accepted',
    actualDamage,
    defeated: actualDamage >= state.hp,
    ...effects,
  });
  return Object.freeze({ result, roundedDamage });
}
