import type { WeaponDefinition } from './types';

export function validateWeaponDefinition(value: unknown): string[] {
  const issues: string[] = [];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return ['weapon: must be an object'];
  const weapon = value as Partial<WeaponDefinition>;
  if (weapon.version !== 1) issues.push('weapon.version: must be 1');
  if (typeof weapon.weaponId !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(weapon.weaponId)) issues.push('weapon.weaponId: must be a lowercase kebab-case ID');
  if (typeof weapon.displayName !== 'string' || weapon.displayName.trim().length === 0 || weapon.displayName.length > 80) issues.push('weapon.displayName: must be between 1 and 80 characters');
  if (weapon.category !== 'melee' && weapon.category !== 'ranged') issues.push("weapon.category: must be 'melee' or 'ranged'");
  if (typeof weapon.animKey !== 'string' || weapon.animKey.length === 0) issues.push('weapon.animKey: must be a non-empty animation key');
  for (const field of ['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxDurationMs', 'knockStrength'] as const) {
    if (typeof weapon[field] !== 'number' || !Number.isFinite(weapon[field]) || weapon[field] < 0) issues.push(`weapon.${field}: must be zero or greater`);
  }
  if (typeof weapon.vfxColor !== 'number' || !Number.isInteger(weapon.vfxColor) || weapon.vfxColor < 0) issues.push('weapon.vfxColor: must be a non-negative integer');
  if (typeof weapon.unlockLevel !== 'number' || !Number.isInteger(weapon.unlockLevel) || weapon.unlockLevel < 1) issues.push('weapon.unlockLevel: must be a positive integer');
  if (typeof weapon.iconKey !== 'string') issues.push('weapon.iconKey: must be a string');
  if (typeof weapon.description !== 'string') issues.push('weapon.description: must be a string');
  return issues;
}

