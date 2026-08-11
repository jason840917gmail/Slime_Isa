import type {
  NormalizedWeaponAnimationDocument,
  NormalizedWeaponDefinition,
  NormalizedWeaponDirectionalAttack,
  WeaponAttackDirection,
  WeaponAnimationDocument,
  WeaponDefinition,
  WeaponHitboxDocument,
  WeaponAnimationSet,
} from './types';
import { LEGACY_WEAPON_SECTOR_ARC_RAD } from './types';
import { normalizeAnimationClip } from '../../shared/animation';

const DEFAULT_ACTION_ID = 'trick';

function legacyActionId(animKey: string | undefined): string {
  const value = animKey?.trim() ?? '';
  if (value.startsWith('slime-')) return value.slice('slime-'.length);
  return value;
}

function legacyPrimaryHitbox(definition: WeaponDefinition): WeaponHitboxDocument {
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

function normalizeHitboxes(
  hitboxes: Readonly<Record<string, WeaponHitboxDocument>>,
): Readonly<Record<string, WeaponHitboxDocument>> {
  return Object.fromEntries(Object.entries(hitboxes).map(([hitboxId, hitbox]) => [
    hitboxId,
    hitbox.shape === 'sector' && hitbox.arcWidthRad === undefined
      ? { ...hitbox, arcWidthRad: LEGACY_WEAPON_SECTOR_ARC_RAD }
      : hitbox,
  ]));
}

function defaultAnimations(): WeaponAnimationSet {
  return {
    idle: { frames: [0], framesPerSecond: 8, loop: true, loopMode: 'wrap' },
    attack: { frames: [0], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
    impact: { frames: [0], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
  };
}

function normalizeWeaponAnimation(animation: WeaponAnimationDocument): NormalizedWeaponAnimationDocument {
  return {
    ...normalizeAnimationClip(animation),
    ...(animation.frameTransforms ? { frameTransforms: animation.frameTransforms } : {}),
  };
}

export function normalizeWeaponDefinition(definition: WeaponDefinition): NormalizedWeaponDefinition {
  const characterActionId = definition.characterActionId?.trim()
    || legacyActionId(definition.animKey)
    || DEFAULT_ACTION_ID;
  const authoredAnimations = definition.animations ?? defaultAnimations();
  const animations = {
    idle: normalizeWeaponAnimation(authoredAnimations.idle),
    attack: normalizeWeaponAnimation(authoredAnimations.attack),
    impact: normalizeWeaponAnimation(authoredAnimations.impact),
  };
  const hitboxes = normalizeHitboxes(definition.hitboxes ?? { primary: legacyPrimaryHitbox(definition) });
  const visual = {
    sourceOffset: definition.visual?.sourceOffset ?? [0, 0] as const,
    ...(definition.visual?.animationOffsets ? { animationOffsets: definition.visual.animationOffsets } : {}),
    ...(definition.visual?.frameOffsets ? { frameOffsets: definition.visual.frameOffsets } : {}),
    ...(definition.visual?.origin ? { origin: definition.visual.origin } : {}),
    ...(definition.visual?.scale ? { scale: definition.visual.scale } : {}),
    ...(definition.visual?.facingMode ? { facingMode: definition.visual.facingMode } : {}),
  };
  const authoredDirections = definition.directionalAttacks;
  const rightSource = authoredDirections?.right ?? authoredDirections?.side;
  const resolveAttack = (
    authored: typeof rightSource,
    fallback: Pick<NormalizedWeaponDirectionalAttack, 'animation' | 'characterActionId' | 'attackTrack' | 'hitboxes'>,
    presentation: NormalizedWeaponDirectionalAttack['presentation'],
  ): NormalizedWeaponDirectionalAttack => ({
    animation: authored?.animation ? normalizeWeaponAnimation(authored.animation) : fallback.animation,
    characterActionId: authored?.characterActionId?.trim() || fallback.characterActionId,
    hitboxes: normalizeHitboxes(authored?.hitboxes ?? fallback.hitboxes),
    authored: authored !== undefined,
    presentation,
    ...((authored?.attackTrack ?? fallback.attackTrack)
      ? { attackTrack: authored?.attackTrack ?? fallback.attackTrack }
      : {}),
  });
  const baseAttack = {
    animation: animations.attack,
    characterActionId,
    hitboxes,
    ...(definition.attackTrack ? { attackTrack: definition.attackTrack } : {}),
  };
  const rightAttack = resolveAttack(rightSource, baseAttack, rightSource ? 'authored' : 'legacy-vector');
  const leftSource = authoredDirections?.left;
  const directionalAttacks: Readonly<Record<WeaponAttackDirection, NormalizedWeaponDirectionalAttack>> = {
    right: rightAttack,
    left: resolveAttack(leftSource, rightAttack, leftSource ? 'authored' : 'mirror-right'),
    up: resolveAttack(authoredDirections?.up, baseAttack, authoredDirections?.up ? 'authored' : 'legacy-vector'),
    down: resolveAttack(authoredDirections?.down, baseAttack, authoredDirections?.down ? 'authored' : 'legacy-vector'),
  };

  return {
    ...definition,
    characterActionId,
    animations,
    directionalAttacks,
    visual,
    hitboxes,
    ...(definition.attackTrack ? { attackTrack: definition.attackTrack } : {}),
    legacyImmediateHit: definition.attackTrack === undefined,
  };
}
