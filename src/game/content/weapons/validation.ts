import type { WeaponAnimationDocument, WeaponDefinition } from './types';

function validateAnimation(animation: unknown, path: string, issues: string[]): void {
  if (animation === null || typeof animation !== 'object' || Array.isArray(animation)) {
    issues.push(`${path}: must be an object`);
    return;
  }
  const clip = animation as Partial<WeaponAnimationDocument>;
  if (!Array.isArray(clip.frames) || clip.frames.length === 0 || clip.frames.some((frame) => !Number.isInteger(frame) || frame < 0)) issues.push(`${path}.frames: must contain non-negative integers`);
  if (typeof clip.framesPerSecond !== 'number' || !Number.isInteger(clip.framesPerSecond) || clip.framesPerSecond < 1 || clip.framesPerSecond > 240) issues.push(`${path}.framesPerSecond: must be an integer between 1 and 240`);
  if (typeof clip.loop !== 'boolean') issues.push(`${path}.loop: must be boolean`);
  if (clip.loopMode !== undefined && clip.loopMode !== 'wrap' && clip.loopMode !== 'ping-pong') issues.push(`${path}.loopMode: must be 'wrap' or 'ping-pong'`);
}

export function validateWeaponDefinition(value: unknown): string[] {
  const issues: string[] = [];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return ['weapon: must be an object'];
  const weapon = value as Partial<WeaponDefinition>;
  if (weapon.version !== 1) issues.push('weapon.version: must be 1');
  if (typeof weapon.weaponId !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(weapon.weaponId)) issues.push('weapon.weaponId: must be a lowercase kebab-case ID');
  if (typeof weapon.displayName !== 'string' || weapon.displayName.trim().length === 0 || weapon.displayName.length > 80) issues.push('weapon.displayName: must be between 1 and 80 characters');
  if (weapon.category !== 'melee' && weapon.category !== 'ranged') issues.push("weapon.category: must be 'melee' or 'ranged'");
  if (typeof weapon.animKey !== 'string' || weapon.animKey.length === 0) issues.push('weapon.animKey: must be a non-empty animation key');
  if (weapon.assetId !== undefined && (typeof weapon.assetId !== 'string' || weapon.assetId.length === 0)) issues.push('weapon.assetId: must be a non-empty string');
  if (weapon.animations !== undefined) {
    validateAnimation(weapon.animations.idle, 'weapon.animations.idle', issues);
    validateAnimation(weapon.animations.attack, 'weapon.animations.attack', issues);
    validateAnimation(weapon.animations.impact, 'weapon.animations.impact', issues);
  }
  if (weapon.visual !== undefined) {
    const sourceOffset = weapon.visual.sourceOffset;
    if (!Array.isArray(sourceOffset) || sourceOffset.length !== 2 || sourceOffset.some((entry) => typeof entry !== 'number' || !Number.isInteger(entry))) issues.push('weapon.visual.sourceOffset: must contain exactly two integers');
  }
  for (const field of ['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxDurationMs', 'knockStrength'] as const) {
    if (typeof weapon[field] !== 'number' || !Number.isFinite(weapon[field]) || weapon[field] < 0) issues.push(`weapon.${field}: must be zero or greater`);
  }
  if (typeof weapon.vfxColor !== 'number' || !Number.isInteger(weapon.vfxColor) || weapon.vfxColor < 0) issues.push('weapon.vfxColor: must be a non-negative integer');
  if (typeof weapon.unlockLevel !== 'number' || !Number.isInteger(weapon.unlockLevel) || weapon.unlockLevel < 1) issues.push('weapon.unlockLevel: must be a positive integer');
  if (typeof weapon.iconKey !== 'string') issues.push('weapon.iconKey: must be a string');
  if (typeof weapon.description !== 'string') issues.push('weapon.description: must be a string');
  return issues;
}
