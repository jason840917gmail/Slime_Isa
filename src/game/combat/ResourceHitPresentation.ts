export interface ResourceHitPresentationInput {
  readonly acceptedDamage: number;
  readonly depleted: boolean;
  readonly onHitAnimationId?: string;
}

export type ResourceHitPresentation = 'deplete' | 'animate-hit' | 'none';

/** Keeps lethal resource removal ahead of optional non-lethal hit animation. */
export function resolveResourceHitPresentation(
  input: ResourceHitPresentationInput,
): ResourceHitPresentation {
  if (input.depleted) return 'deplete';
  if (input.acceptedDamage > 0 && input.onHitAnimationId) return 'animate-hit';
  return 'none';
}
