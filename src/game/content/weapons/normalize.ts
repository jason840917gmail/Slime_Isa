import {
  DOWN_UP_INHERITANCE,
  normalizeLayeredAnimation,
  resolveDirectionalVariant,
  RIGHT_LEFT_INHERITANCE,
} from '../../shared/animation';
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
  const resolvedDirections: Array<[WeaponAttackDirection, NormalizedWeaponDirectionalAttack]> = (['right', 'left', 'up', 'down'] as const).map((direction) => {
    const resolved = resolveDirectionalVariant(
      definition.directionalAttacks,
      direction,
      { pairs: [RIGHT_LEFT_INHERITANCE, DOWN_UP_INHERITANCE] },
    );
    if (!resolved || resolved.sourceDirection === 'default') {
      throw new Error(`Weapon '${definition.weaponId}' does not resolve direction '${direction}'`);
    }
    const authored = resolved.value;
    const presentation: NormalizedWeaponDirectionalAttack['presentation'] = resolved.authored
      ? 'authored'
      : resolved.mirrorX
        ? 'mirror-right'
        : 'mirror-down';
    const normalized: NormalizedWeaponDirectionalAttack = {
      animation: normalizeLayeredAnimation({ ...authored.animation, loop: false }),
      characterActionId: authored.characterActionId,
      hitboxes: normalizeWeaponHitboxes(authored.hitboxes),
      ...(authored.attackTrack ? { attackTrack: authored.attackTrack } : {}),
      authored: resolved.authored,
      presentation,
      sourceDirection: resolved.sourceDirection,
      mirrorX: resolved.mirrorX,
      mirrorY: resolved.mirrorY,
    };
    return [direction, normalized];
  });
  const directionalAttacks = Object.fromEntries(resolvedDirections) as Readonly<Record<WeaponAttackDirection, NormalizedWeaponDirectionalAttack>>;
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
    ...(definition.damageModifiers ? { damageModifiers: definition.damageModifiers } : {}),
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
