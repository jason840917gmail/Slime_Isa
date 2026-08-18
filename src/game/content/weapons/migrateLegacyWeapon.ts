import {
  normalizeAnimationClip,
  normalizeLayeredAnimation,
  timelineFrameCount,
  type AnimationVisualBlockDocument,
  type LayeredAnimationDocument,
  type NormalizedLayeredAnimationDocument,
} from '../../shared/animation';
import type {
  LayeredWeaponDefinition,
  LegacyWeaponDefinition,
  WeaponAnimationDocument,
  WeaponAttackDirection,
  WeaponAttackTrackDocument,
  WeaponDirectionalAttackDocument,
  WeaponHitboxDocument,
} from './types';
import { LEGACY_WEAPON_SECTOR_ARC_RAD } from './types';

const DEFAULT_ACTION_ID = 'trick';

function legacyActionId(animKey: string | undefined): string {
  const value = animKey?.trim() ?? '';
  return value.startsWith('slime-') ? value.slice('slime-'.length) : value;
}

function defaultAnimations(): LegacyWeaponDefinition['animations'] & {} {
  return {
    idle: { frames: [0], framesPerSecond: 8, loop: true, loopMode: 'wrap' },
    attack: { frames: [0], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
    impact: { frames: [0], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
  };
}

function legacyPrimaryHitbox(definition: LegacyWeaponDefinition): WeaponHitboxDocument {
  return {
    shape: 'sector',
    width: definition.hitboxWidth,
    height: definition.hitboxHeight,
    offsetX: definition.hitboxOffset,
    offsetY: 0,
    innerRadius: 0,
    outerRadius: definition.hitboxOffset + definition.hitboxWidth / 2,
    arcWidthRad: LEGACY_WEAPON_SECTOR_ARC_RAD,
  };
}

export function normalizeWeaponHitboxes(
  hitboxes: Readonly<Record<string, WeaponHitboxDocument>>,
): Readonly<Record<string, WeaponHitboxDocument>> {
  return Object.fromEntries(Object.entries(hitboxes).map(([hitboxId, hitbox]) => [
    hitboxId,
    hitbox.shape === 'sector' && hitbox.arcWidthRad === undefined
      ? { ...hitbox, arcWidthRad: LEGACY_WEAPON_SECTOR_ARC_RAD }
      : hitbox,
  ]));
}

function addPair(left: readonly [number, number], right: readonly [number, number]): readonly [number, number] {
  return [left[0] + right[0], left[1] + right[1]];
}

function subtractPair(left: readonly [number, number], right: readonly [number, number]): readonly [number, number] {
  return [left[0] - right[0], left[1] - right[1]];
}

export function migrateLegacyAnimation(
  definition: LegacyWeaponDefinition,
  animation: WeaponAnimationDocument,
  animationOffsetKey: string,
  forceOneShot = false,
): LayeredAnimationDocument {
  const normalized = normalizeAnimationClip(animation);
  const frameCount = timelineFrameCount(normalized);
  const selectedAnimationOffset = definition.visual?.animationOffsets?.[animationOffsetKey]
    ?? (animationOffsetKey.startsWith('attack-') ? definition.visual?.animationOffsets?.attack : undefined);
  const baseOffset = selectedAnimationOffset ?? definition.visual?.sourceOffset ?? [0, 0];
  const blocks: AnimationVisualBlockDocument[] = normalized.frames.map((sourceFrame, index) => {
    const from = normalized.keyframeTimes[index];
    const through = index + 1 < normalized.keyframeTimes.length
      ? normalized.keyframeTimes[index + 1] - 1
      : frameCount - 1;
    const frameOffset = definition.visual?.frameOffsets?.[String(sourceFrame)];
    const occurrence = animation.frameTransforms?.[String(index)];
    const offset = addPair(frameOffset ? subtractPair(frameOffset, baseOffset) : [0, 0], occurrence?.offset ?? [0, 0]);
    const hasTransform = offset[0] !== 0
      || offset[1] !== 0
      || occurrence?.scale !== undefined
      || occurrence?.rotationDeg !== undefined;
    return {
      from,
      through,
      sourceFrame,
      ...(hasTransform ? {
        transform: {
          ...(offset[0] !== 0 || offset[1] !== 0 ? { offset } : {}),
          ...(occurrence?.scale ? { scale: occurrence.scale } : {}),
          ...(occurrence?.rotationDeg !== undefined ? { rotationDeg: occurrence.rotationDeg } : {}),
        },
      } : {}),
    };
  });

  return {
    version: 2,
    durationSeconds: frameCount / normalized.framesPerSecond,
    framesPerSecond: normalized.framesPerSecond,
    loop: forceOneShot ? false : normalized.loop,
    loopMode: normalized.loopMode,
    layers: definition.assetId ? [{
      layerId: 'base',
      displayName: definition.displayName,
      assetId: definition.assetId,
      depthOffset: 0,
      transform: {
        offset: baseOffset,
        ...(definition.visual?.scale ? { scale: definition.visual.scale } : {}),
        ...(definition.visual?.origin ? { origin: definition.visual.origin } : {}),
      },
      blocks,
    }] : [],
  };
}

function stripImpactEvents(events: WeaponAttackTrackDocument['events']): WeaponAttackTrackDocument['events'] {
  return events?.filter((event) => event.eventId !== 'weapon.impact');
}

function migratedDirection(
  definition: LegacyWeaponDefinition,
  direction: WeaponAttackDirection,
  authored: WeaponDirectionalAttackDocument | undefined,
  fallbackAnimation: WeaponAnimationDocument,
  fallbackHitboxes: Readonly<Record<string, WeaponHitboxDocument>>,
  fallbackAction: string,
  fallbackTrack: WeaponAttackTrackDocument | undefined = definition.attackTrack,
) {
  const animation = authored?.animation ?? fallbackAnimation;
  const track = authored?.attackTrack ?? fallbackTrack;
  const events = stripImpactEvents(track?.events);
  return {
    animation: migrateLegacyAnimation(definition, animation, `attack-${direction}`, true),
    characterActionId: authored?.characterActionId?.trim() || fallbackAction,
    hitboxes: normalizeWeaponHitboxes(authored?.hitboxes ?? fallbackHitboxes),
    ...(track ? { attackTrack: { ...track, ...(events ? { events } : {}) } } : {}),
  };
}

export function migrateLegacyWeaponDefinition(
  definition: LegacyWeaponDefinition,
  options: { readonly onHitEffectId?: string } = {},
): LayeredWeaponDefinition {
  const animations = definition.animations ?? defaultAnimations();
  const characterActionId = definition.characterActionId?.trim()
    || legacyActionId(definition.animKey)
    || DEFAULT_ACTION_ID;
  const rootHitboxes = normalizeWeaponHitboxes(definition.hitboxes ?? { primary: legacyPrimaryHitbox(definition) });
  const authored = definition.directionalAttacks;
  const rightSource = authored?.right ?? authored?.side;
  const right = migratedDirection(definition, 'right', rightSource, animations.attack, rootHitboxes, characterActionId);
  const up = migratedDirection(definition, 'up', authored?.up, animations.attack, rootHitboxes, characterActionId);
  const down = migratedDirection(definition, 'down', authored?.down, animations.attack, rootHitboxes, characterActionId);
  const left = authored?.left
    ? migratedDirection(definition, 'left', authored.left, animations.attack, right.hitboxes, right.characterActionId, right.attackTrack)
    : undefined;

  return {
    version: 2,
    weaponId: definition.weaponId,
    displayName: definition.displayName,
    category: definition.category,
    characterActionId,
    animations: { idle: migrateLegacyAnimation(definition, animations.idle, 'idle') },
    directionalAttacks: { right, ...(left ? { left } : {}), up, down },
    presentation: { facingMode: definition.visual?.facingMode ?? 'vector' },
    ...(options.onHitEffectId ? { onHitEffectId: options.onHitEffectId } : {}),
    ...(definition.onResourceHitEffectId ? { onResourceHitEffectId: definition.onResourceHitEffectId } : {}),
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
  };
}

export function normalizedMigratedAnimation(animation: LayeredAnimationDocument): NormalizedLayeredAnimationDocument {
  return normalizeLayeredAnimation(animation);
}
