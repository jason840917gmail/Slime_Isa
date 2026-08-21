import { animationPackages } from 'virtual-animation-content';
import { normalizeAnimationPackage } from './validation';
import type { AnimationPackageDiagnostic, NormalizedAnimationPackage } from './types';

export interface AnimationDefinitionResolution {
  readonly ok: true;
  readonly package: NormalizedAnimationPackage;
  readonly animation: NormalizedAnimationPackage['animation'];
}

export interface MissingAnimationResolution {
  readonly ok: false;
  readonly diagnostic: AnimationPackageDiagnostic;
}

export type AnimationDefinitionResult = AnimationDefinitionResolution | MissingAnimationResolution;

export interface AnimationDefinitionResolver {
  get(animationId: string): AnimationDefinitionResult;
}

const normalizedPackages = animationPackages
  .map((value) => normalizeAnimationPackage(value))
  .sort((left, right) => left.animationId.localeCompare(right.animationId));
const packagesById = new Map(normalizedPackages.map((value) => [value.animationId, value]));

if (packagesById.size !== normalizedPackages.length) throw new Error('Duplicate animation package IDs were discovered');

export function getAnimationPackages(): readonly NormalizedAnimationPackage[] {
  return normalizedPackages;
}

export function getAnimationPackage(animationId: string): NormalizedAnimationPackage | undefined {
  return packagesById.get(animationId);
}

export function resolveAnimationDefinition(animationId: string): AnimationDefinitionResult {
  const packageValue = packagesById.get(animationId);
  if (!packageValue) {
    return {
      ok: false,
      diagnostic: {
        code: 'animation-reference-missing',
        animationId,
        message: `Animation package '${animationId}' was not found in the shared catalog`,
      },
    };
  }
  return { ok: true, package: packageValue, animation: packageValue.animation };
}

export const animationDefinitionResolver = { get: resolveAnimationDefinition };
