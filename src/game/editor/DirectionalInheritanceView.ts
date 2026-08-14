import type { DirectionalInheritancePair, ResolvedDirectionalVariant } from '../shared/animation';

export function directionalStatusLabel<TDirection extends string>(
  direction: TDirection,
  resolved: ResolvedDirectionalVariant<unknown, TDirection> | undefined,
  pairs: readonly DirectionalInheritancePair<TDirection>[],
): string {
  const pair = pairs.find((candidate) => candidate.child === direction);
  if (!pair) return 'MASTER';
  if (!resolved) return 'UNRESOLVED';
  if (resolved.authored) return 'CUSTOM';
  if (resolved.sourceDirection === pair.master) return `MIRROR ${pair.master.toUpperCase()}`;
  return `FALLBACK ${resolved.sourceDirection.toUpperCase()}`;
}

export function directionalModeDescription<TDirection extends string>(
  direction: TDirection,
  resolved: ResolvedDirectionalVariant<unknown, TDirection> | undefined,
  pairs: readonly DirectionalInheritancePair<TDirection>[],
): string {
  const pair = pairs.find((candidate) => candidate.child === direction);
  if (!pair) return `${direction.toUpperCase()} owns this animation.`;
  if (!resolved) return `${direction.toUpperCase()} has no usable visual package.`;
  if (resolved.authored) return `${direction.toUpperCase()} is custom and can be edited independently.`;
  return `${direction.toUpperCase()} inherits ${pair.master.toUpperCase()} at runtime. Convert it to edit independently.`;
}
