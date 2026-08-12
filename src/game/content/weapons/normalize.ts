import { normalizeLayeredAnimation } from '../../shared/animation';
import { migrateLegacyWeaponDefinition, normalizeWeaponHitboxes } from './migrateLegacyWeapon';
import type {
  AuthoredWeaponDefinition,
  LayeredWeaponDefinition,
  NormalizedWeaponDefinition,
  NormalizedWeaponDirectionalAttack,
  WeaponAttackDirection,
} from './types';

function normalizeLayeredWeaponDefinition(
  definition: LayeredWeaponDefinition,
  sourceVersion: 1 | 2,
): NormalizedWeaponDefinition {
  const right = definition.directionalAttacks.right;
  const normalizeDirection = (
    authored: typeof right,
    presentation: NormalizedWeaponDirectionalAttack['presentation'],
    isAuthored: boolean,
  ): NormalizedWeaponDirectionalAttack => ({
    animation: normalizeLayeredAnimation({ ...authored.animation, loop: false }),
    characterActionId: authored.characterActionId,
    hitboxes: normalizeWeaponHitboxes(authored.hitboxes),
    ...(authored.attackTrack ? { attackTrack: authored.attackTrack } : {}),
    authored: isAuthored,
    presentation,
  });
  const directionalAttacks: Readonly<Record<WeaponAttackDirection, NormalizedWeaponDirectionalAttack>> = {
    right: normalizeDirection(right, 'authored', true),
    left: definition.directionalAttacks.left
      ? normalizeDirection(definition.directionalAttacks.left, 'authored', true)
      : normalizeDirection(right, 'mirror-right', false),
    up: normalizeDirection(definition.directionalAttacks.up, 'authored', true),
    down: normalizeDirection(definition.directionalAttacks.down, 'authored', true),
  };
  return {
    sourceVersion,
    weaponId: definition.weaponId,
    displayName: definition.displayName,
    category: definition.category,
    characterActionId: definition.characterActionId,
    animations: { idle: normalizeLayeredAnimation(definition.animations.idle) },
    directionalAttacks,
    presentation: { facingMode: definition.presentation?.facingMode ?? 'vector' },
    ...(definition.onHitEffectId ? { onHitEffectId: definition.onHitEffectId } : {}),
    baseDamage: definition.baseDamage,
    cooldownMs: definition.cooldownMs,
    hitboxWidth: definition.hitboxWidth,
    hitboxHeight: definition.hitboxHeight,
    hitboxOffset: definition.hitboxOffset,
    hitboxDurationMs: definition.hitboxDurationMs,
    knockStrength: definition.knockStrength,
    ...(definition.scaling ? { scaling: definition.scaling } : {}),
    vfxColor: definition.vfxColor,
    unlockLevel: definition.unlockLevel,
    iconKey: definition.iconKey,
    description: definition.description,
    legacyImmediateHit: sourceVersion === 1 && definition.directionalAttacks.right.attackTrack === undefined,
  };
}

export function normalizeWeaponDefinition(definition: AuthoredWeaponDefinition): NormalizedWeaponDefinition {
  return definition.version === 1
    ? normalizeLayeredWeaponDefinition(migrateLegacyWeaponDefinition(definition), 1)
    : normalizeLayeredWeaponDefinition(definition, 2);
}
