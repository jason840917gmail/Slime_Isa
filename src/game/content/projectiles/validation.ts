import type { CharacterStudioAssetManifestInput } from '../characters/characterAssetCatalog';
import type { ProjectileDefinition } from './types';

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
  const animation = projectile.animation;
  if (animation !== undefined) {
    if (typeof animation !== 'object' || !Array.isArray(animation.frames) || animation.frames.length === 0) issues.push('projectile.animation.frames: must contain at least one frame');
    if (typeof animation.framesPerSecond !== 'number' || !Number.isFinite(animation.framesPerSecond) || animation.framesPerSecond <= 0 || animation.framesPerSecond > 240) issues.push('projectile.animation.framesPerSecond: must be between 0 and 240');
    if (typeof animation.loop !== 'boolean') issues.push('projectile.animation.loop: must be boolean');
    if (animation.loopMode !== undefined && animation.loopMode !== 'wrap' && animation.loopMode !== 'ping-pong') issues.push("projectile.animation.loopMode: must be 'wrap' or 'ping-pong'");
    for (const [index, frame] of (Array.isArray(animation.frames) ? animation.frames : []).entries()) {
      if (!Number.isInteger(frame) || frame < 0) issues.push(`projectile.animation.frames[${index}]: must be a non-negative integer`);
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
