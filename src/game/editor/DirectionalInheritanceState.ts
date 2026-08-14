import {
  resolveDirectionalVariant,
  type DirectionalInheritancePair,
  type DirectionalInheritancePolicy,
  type ResolvedDirectionalVariant,
} from '../shared/animation';

export interface DirectionalStudioState<TDirection extends string> extends ResolvedDirectionalVariant<unknown, TDirection> {
  readonly isChild: boolean;
  readonly masterDirection?: TDirection;
}

export function resolveDirectionalStudioState<T, TDirection extends string>(
  variants: Partial<Readonly<Record<TDirection, T>>>,
  direction: TDirection,
  policy: DirectionalInheritancePolicy<TDirection, T>,
): (ResolvedDirectionalVariant<T, TDirection> & { readonly isChild: boolean; readonly masterDirection?: TDirection }) | undefined {
  const resolved = resolveDirectionalVariant(variants, direction, policy);
  if (!resolved) return undefined;
  const pair = policy.pairs.find((candidate) => candidate.child === direction);
  return { ...resolved, isChild: Boolean(pair), masterDirection: pair?.master };
}

export function directionalPairFor<TDirection extends string>(
  pairs: readonly DirectionalInheritancePair<TDirection>[],
  direction: TDirection,
): DirectionalInheritancePair<TDirection> | undefined {
  return pairs.find((pair) => pair.child === direction);
}
