import type { CharacterStudioAssetManifestInput } from '../characters/characterAssetCatalog';
import type { ProjectileAnimationDocument, ProjectileDefinition } from './types';

function validateIntegerPair(value: unknown, path: string, issues: string[]): value is readonly [number, number] {
  if (!Array.isArray(value) || value.length !== 2 || value.some((entry) => typeof entry !== 'number' || !Number.isInteger(entry))) {
    issues.push(`${path}: must contain exactly two integers`);
    return false;
  }
  return true;
}

function validateAnimationClip(
  animation: unknown,
  path: string,
  issues: string[],
): animation is ProjectileAnimationDocument {
  if (animation === null || typeof animation !== 'object' || Array.isArray(animation)) {
    issues.push(`${path}: must be an object`);
    return false;
  }
  const clip = animation as Partial<ProjectileAnimationDocument>;
  if (!Array.isArray(clip.frames) || clip.frames.length === 0) issues.push(`${path}.frames: must contain at least one frame`);
  if (typeof clip.framesPerSecond !== 'number' || !Number.isInteger(clip.framesPerSecond) || clip.framesPerSecond < 1 || clip.framesPerSecond > 240) issues.push(`${path}.framesPerSecond: must be an integer between 1 and 240`);
  if (typeof clip.loop !== 'boolean') issues.push(`${path}.loop: must be boolean`);
  if (clip.loopMode !== undefined && clip.loopMode !== 'wrap' && clip.loopMode !== 'ping-pong') issues.push(`${path}.loopMode: must be 'wrap' or 'ping-pong'`);
  for (const [index, frame] of (Array.isArray(clip.frames) ? clip.frames : []).entries()) {
    if (!Number.isInteger(frame) || frame < 0) issues.push(`${path}.frames[${index}]: must be a non-negative integer`);
  }
  return true;
}

export function validateProjectileDefinition(
  value: unknown,
  manifest?: CharacterStudioAssetManifestInput,
): string[] {
  const issues: string[] = [];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return ['projectile: must be an object'];
  const projectile = value as Partial<ProjectileDefinition>;
  if (projectile.version !== 1) issues.push('projectile.version: must be 1');
  if (typeof projectile.projectileId !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(projectile.projectileId)) issues.push('projectile.projectileId: must be a lowercase kebab-case ID');
  if (typeof projectile.displayName !== 'string' || projectile.displayName.trim().length === 0 || projectile.displayName.length > 80) issues.push('projectile.displayName: must be between 1 and 80 characters');
  if (typeof projectile.assetId !== 'string' || !projectile.assetId) issues.push('projectile.assetId: must reference an asset');
  else if (manifest?.assets && !(projectile.assetId in manifest.assets)) issues.push(`projectile.assetId: unknown manifest asset '${projectile.assetId}'`);
  if (projectile.animations !== undefined) {
    if (typeof projectile.animations !== 'object' || projectile.animations === null || Array.isArray(projectile.animations)) issues.push('projectile.animations: must be an object');
    else {
      const animations = projectile.animations as Partial<NonNullable<ProjectileDefinition['animations']>>;
      validateAnimationClip(animations.move, 'projectile.animations.move', issues);
      validateAnimationClip(animations.impact, 'projectile.animations.impact', issues);
    }
  } else if (projectile.animation !== undefined) {
    validateAnimationClip(projectile.animation, 'projectile.animation', issues);
  } else {
    issues.push('projectile.animations: move and impact clips are required');
  }
  if (projectile.visual !== undefined) {
    if (typeof projectile.visual !== 'object' || projectile.visual === null || Array.isArray(projectile.visual)) issues.push('projectile.visual: must be an object');
    else {
      const visual = projectile.visual as { sourceOffset?: unknown; frameOffsets?: unknown };
      validateIntegerPair(visual.sourceOffset, 'projectile.visual.sourceOffset', issues);
      if (visual.frameOffsets !== undefined) {
        if (typeof visual.frameOffsets !== 'object' || visual.frameOffsets === null || Array.isArray(visual.frameOffsets)) issues.push('projectile.visual.frameOffsets: must be an object');
        else for (const [frame, offset] of Object.entries(visual.frameOffsets)) validateIntegerPair(offset, `projectile.visual.frameOffsets.${frame}`, issues);
      }
    }
  }
  const body = projectile.body;
  if (!body || typeof body !== 'object') issues.push('projectile.body: must be an object');
  else {
    const bodyRecord = body as Record<string, unknown>;
    if (bodyRecord.shape !== undefined && bodyRecord.shape !== 'rectangle' && bodyRecord.shape !== 'circle' && bodyRecord.shape !== 'ellipse') issues.push("projectile.body.shape: must be 'rectangle', 'circle', or 'ellipse'");
    if (bodyRecord.shape === 'circle') {
      if (typeof bodyRecord.radius !== 'number' || !Number.isFinite(bodyRecord.radius) || bodyRecord.radius <= 0) issues.push('projectile.body.radius: must be greater than zero for a circle');
    } else if (bodyRecord.shape === 'ellipse') {
      if (typeof bodyRecord.radiusX !== 'number' || !Number.isFinite(bodyRecord.radiusX) || bodyRecord.radiusX <= 0) issues.push('projectile.body.radiusX: must be greater than zero for an ellipse');
      if (typeof bodyRecord.radiusY !== 'number' || !Number.isFinite(bodyRecord.radiusY) || bodyRecord.radiusY <= 0) issues.push('projectile.body.radiusY: must be greater than zero for an ellipse');
    }
    for (const field of ['width', 'height', 'centerOffsetX', 'centerOffsetY'] as const) {
      if (typeof body[field] !== 'number' || !Number.isFinite(body[field])) issues.push(`projectile.body.${field}: must be finite`);
    }
    if (typeof body.width !== 'number' || body.width <= 0) issues.push('projectile.body.width: must be greater than zero');
    if (typeof body.height !== 'number' || body.height <= 0) issues.push('projectile.body.height: must be greater than zero');
  }
  const movement = projectile.movement;
  if (!movement || typeof movement !== 'object') issues.push('projectile.movement: must be an object');
  else {
    if (typeof movement.defaultSpeed !== 'number' || !Number.isFinite(movement.defaultSpeed) || movement.defaultSpeed <= 0) issues.push('projectile.movement.defaultSpeed: must be greater than zero');
    if (typeof movement.lifetimeMs !== 'number' || !Number.isInteger(movement.lifetimeMs) || movement.lifetimeMs <= 0) issues.push('projectile.movement.lifetimeMs: must be a positive integer');
    if (typeof movement.rotateToVelocity !== 'boolean') issues.push('projectile.movement.rotateToVelocity: must be boolean');
  }
  return issues;
}
