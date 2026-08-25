import {
  DOWN_UP_INHERITANCE,
  normalizeLayeredAnimation,
  resolveDirectionalVariant,
  RIGHT_LEFT_INHERITANCE,
} from '../../shared/animation';
import { resolveAnimationDefinition } from '../animations/AnimationCatalog';
import { migrateLegacyWeaponDefinition, normalizeWeaponHitboxes } from './migrateLegacyWeapon';
import { resolveWeaponPresentationOffsetY } from './presentation';
import type {
  AuthoredWeaponDefinition,
  LayeredWeaponDefinition,
  NormalizedWeaponDefinition,
  NormalizedWeaponDirectionalAttack,
  WeaponAttackDirection,
  WeaponAnimationTimelineDocument,
} from './types';

function emptyLayeredAnimation(timeline?: WeaponAnimationTimelineDocument) {
  return {
    version: 2 as const,
    durationSeconds: timeline?.durationSeconds ?? 1,
    framesPerSecond: timeline?.framesPerSecond ?? 8,
    loop: timeline?.loop ?? true,
    loopMode: timeline?.loopMode ?? 'wrap' as const,
    layers: [],
  };
}

function resolveSharedAnimation(
  animationId: string | undefined,
  embeddedAnimation: LayeredWeaponDefinition['animations']['idle'] | undefined,
  timeline: WeaponAnimationTimelineDocument | undefined,
  label: string,
) {
  if (animationId) {
    const resolved = resolveAnimationDefinition(animationId);
    if (!resolved.ok) throw new Error(`${label}: ${resolved.diagnostic.message}`);
    return resolved.animation;
  }
  return embeddedAnimation ?? emptyLayeredAnimation(timeline);
}

function normalizeLayeredWeaponDefinition(
  definition: LayeredWeaponDefinition,
  sourceVersion: 1 | 2,
): NormalizedWeaponDefinition {
  const idleAnimation = resolveSharedAnimation(
    definition.animations.idleAnimationId,
    definition.animations.idle,
    definition.animations.idleTimeline,
    `Weapon '${definition.weaponId}' idle animation`,
  );
  const resolvedAttackDefinitions = Object.fromEntries(Object.entries(definition.directionalAttacks).map(([direction, attack]) => [
    direction,
    {
      ...attack,
      animation: resolveSharedAnimation(
        attack.animationId,
        attack.animation,
        attack.animationTimeline,
        `Weapon '${definition.weaponId}' ${direction} attack animation`,
      ),
    },
  ])) as LayeredWeaponDefinition['directionalAttacks'];
  const resolvedDirections: Array<[WeaponAttackDirection, NormalizedWeaponDirectionalAttack]> = (['right', 'left', 'up', 'down'] as const).map((direction) => {
    const resolved = resolveDirectionalVariant(
      resolvedAttackDefinitions,
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
      presentationOffsetY: resolveWeaponPresentationOffsetY(resolved.mirrorY),
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
    animations: { idle: normalizeLayeredAnimation(idleAnimation) },
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
    ...(definition.harvestCapabilities ? { harvestCapabilities: definition.harvestCapabilities } : {}),
    ...(definition.scaling ? { scaling: definition.scaling } : {}),
    vfxColor: definition.vfxColor,
    unlockLevel: definition.unlockLevel,
    iconKey: definition.iconKey,
    ...(definition.iconFrame !== undefined ? { iconFrame: definition.iconFrame } : {}),
    description: definition.description,
    legacyImmediateHit: sourceVersion === 1 && resolvedAttackDefinitions.right.attackTrack === undefined,
  };
}

export function normalizeWeaponDefinition(definition: AuthoredWeaponDefinition): NormalizedWeaponDefinition {
  return definition.version === 1
    ? normalizeLayeredWeaponDefinition(migrateLegacyWeaponDefinition(definition), 1)
    : normalizeLayeredWeaponDefinition(definition, 2);
}
