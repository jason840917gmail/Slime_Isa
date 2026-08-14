export type DirectionalMirrorAxis = 'x' | 'y';

export interface DirectionalInheritancePair<TDirection extends string> {
  readonly child: TDirection;
  readonly master: TDirection;
  readonly axis: DirectionalMirrorAxis;
  readonly enabled: boolean;
}

export interface DirectionalInheritancePolicy<TDirection extends string, T> {
  readonly pairs: readonly DirectionalInheritancePair<TDirection>[];
  readonly defaultValue?: T;
}

export interface ResolvedDirectionalVariant<T, TDirection extends string> {
  readonly value: T;
  readonly requestedDirection: TDirection;
  readonly sourceDirection: TDirection | 'default';
  readonly authored: boolean;
  readonly mirrorX: boolean;
  readonly mirrorY: boolean;
}

function resultFor<T, TDirection extends string>(
  value: T,
  requestedDirection: TDirection,
  sourceDirection: TDirection | 'default',
  authored: boolean,
  axis?: DirectionalMirrorAxis,
): ResolvedDirectionalVariant<T, TDirection> {
  return {
    value,
    requestedDirection,
    sourceDirection,
    authored,
    mirrorX: axis === 'x',
    mirrorY: axis === 'y',
  };
}

/**
 * Resolves one direction without mutating the authored variant map.
 * Exact children always win, so an enabled mirror flag is dormant while its
 * exact child exists. Defaults are never used as mirror masters.
 */
export function resolveDirectionalVariant<T, TDirection extends string>(
  variants: Partial<Readonly<Record<TDirection, T>>>,
  requestedDirection: TDirection,
  policy: DirectionalInheritancePolicy<TDirection, T>,
): ResolvedDirectionalVariant<T, TDirection> | undefined {
  const exact = variants[requestedDirection];
  if (exact !== undefined) return resultFor(exact, requestedDirection, requestedDirection, true);

  const pair = policy.pairs.find((candidate) => candidate.child === requestedDirection && candidate.enabled);
  if (pair) {
    const master = variants[pair.master];
    if (master !== undefined) return resultFor(master, requestedDirection, pair.master, false, pair.axis);
  }

  if (policy.defaultValue !== undefined) {
    return resultFor(policy.defaultValue, requestedDirection, 'default', false);
  }
  return undefined;
}

export const RIGHT_LEFT_INHERITANCE = {
  child: 'left',
  master: 'right',
  axis: 'x',
  enabled: true,
} as const;

export const DOWN_UP_INHERITANCE = {
  child: 'up',
  master: 'down',
  axis: 'y',
  enabled: true,
} as const;
