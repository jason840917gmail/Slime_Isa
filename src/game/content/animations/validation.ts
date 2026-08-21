import { ASSET_MANIFEST } from '../../infrastructure/assets/manifest';
import {
  normalizeLayeredAnimation,
  validateLayeredAnimationDocument,
  type LayeredAnimationAssetDescriptor,
} from '../../shared/animation';
import type { AnimationPackageDiagnostic, AnimationPackageDocument, NormalizedAnimationPackage } from './types';

export const ANIMATION_ID_PATTERN = /^[a-z0-9]+(?:[.-][a-z0-9]+(?:-[a-z0-9]+)*)+$/;
export const ANIMATION_PACKAGE_NAME_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function assetDescriptor(assetId: string): LayeredAnimationAssetDescriptor | undefined {
  const value = (ASSET_MANIFEST.assets as Record<string, unknown>)[assetId];
  if (!isRecord(value) || !isRecord(value.source)) return undefined;
  const source = value.source;
  if (source.kind !== 'spritesheet' || !isRecord(source.frame)) {
    return { kind: typeof source.kind === 'string' ? source.kind : 'unknown', frameCount: 1 };
  }
  const frame = source.frame;
  const columns = frame.cols;
  const rows = frame.rows;
  const count = frame.count;
  if (typeof columns !== 'number' || typeof rows !== 'number') return { kind: 'spritesheet', frameCount: 0 };
  return {
    kind: 'spritesheet',
    frameCount: typeof count === 'number' ? count : columns * rows,
  };
}

function nestedDiagnostic(issue: string, animationId?: string): AnimationPackageDiagnostic {
  const separator = issue.indexOf(': ');
  const field = separator >= 0 ? issue.slice(0, separator) : 'package.animation';
  const message = separator >= 0 ? issue.slice(separator + 2) : issue;
  const code: AnimationPackageDiagnostic['code'] = message.includes('unknown asset') || message.includes('must be a spritesheet')
    ? 'animation-asset-invalid'
    : 'animation-package-invalid';
  return { code, animationId, field, message: `${field}: ${message}` };
}

export function validateAnimationPackage(value: unknown): readonly AnimationPackageDiagnostic[] {
  const issues: AnimationPackageDiagnostic[] = [];
  if (!isRecord(value)) return [{ code: 'animation-package-invalid', field: 'package', message: 'package: must be an object' }];
  const animationId = typeof value.animationId === 'string' ? value.animationId : undefined;
  const allowedKeys = new Set(['$schema', 'version', 'animationId', 'displayName', 'description', 'animation']);
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) issues.push({ code: 'animation-package-invalid', animationId, field: `package.${key}`, message: `package.${key}: unknown property` });
  }
  if (typeof value.$schema !== 'string' || value.$schema.trim().length === 0) issues.push({ code: 'animation-package-invalid', field: 'package.$schema', message: 'package.$schema: must be a non-empty string', animationId });
  if (value.version !== 1) issues.push({ code: 'animation-package-invalid', field: 'package.version', message: 'package.version: must be 1', animationId });
  if (typeof animationId !== 'string' || !ANIMATION_ID_PATTERN.test(animationId)) issues.push({ code: 'animation-package-invalid', field: 'package.animationId', message: 'package.animationId: must match the lowercase stable animation ID pattern', animationId });
  for (const field of ['displayName', 'description']) {
    if (typeof value[field] !== 'string' || value[field].trim().length === 0) issues.push({ code: 'animation-package-invalid', field: `package.${field}`, message: `package.${field}: must be a non-empty string`, animationId });
  }
  const animationIssues = validateLayeredAnimationDocument(value.animation, {
    assetLookup: assetDescriptor,
    path: 'package.animation',
  });
  issues.push(...animationIssues.map((issue) => nestedDiagnostic(issue, animationId)));
  return issues;
}

export function normalizeAnimationPackage(value: AnimationPackageDocument, packagePath?: string): NormalizedAnimationPackage {
  const issues = validateAnimationPackage(value);
  if (issues.length > 0) {
    const prefix = packagePath ? `${packagePath}: ` : '';
    throw new Error(`${prefix}${issues.map((issue) => `${issue.code} ${issue.message}`).join('; ')}`);
  }
  return {
    $schema: value.$schema,
    version: 1,
    animationId: value.animationId,
    displayName: value.displayName,
    description: value.description,
    animation: normalizeLayeredAnimation(value.animation),
  };
}

export function getAnimationAssetDescriptor(assetId: string): LayeredAnimationAssetDescriptor | undefined {
  return assetDescriptor(assetId);
}
