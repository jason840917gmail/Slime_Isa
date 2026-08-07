import type {
  NormalizedWeaponDefinition,
  WeaponDefinition,
  WeaponHitboxDocument,
  WeaponAnimationSet,
} from './types';

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
  };
}

function defaultAnimations(): WeaponAnimationSet {
  return {
    idle: { frames: [0], framesPerSecond: 8, loop: true, loopMode: 'wrap' },
    attack: { frames: [0], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
    impact: { frames: [0], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
  };
}

export function normalizeWeaponDefinition(definition: WeaponDefinition): NormalizedWeaponDefinition {
  const characterActionId = definition.characterActionId?.trim()
    || legacyActionId(definition.animKey)
    || DEFAULT_ACTION_ID;
  const hitboxes = definition.hitboxes ?? { primary: legacyPrimaryHitbox(definition) };
  const visual = {
    sourceOffset: definition.visual?.sourceOffset ?? [0, 0] as const,
    ...(definition.visual?.animationOffsets ? { animationOffsets: definition.visual.animationOffsets } : {}),
    ...(definition.visual?.frameOffsets ? { frameOffsets: definition.visual.frameOffsets } : {}),
    ...(definition.visual?.origin ? { origin: definition.visual.origin } : {}),
    ...(definition.visual?.scale ? { scale: definition.visual.scale } : {}),
    ...(definition.visual?.facingMode ? { facingMode: definition.visual.facingMode } : {}),
  };

  return {
    ...definition,
    characterActionId,
    animations: definition.animations ?? defaultAnimations(),
    visual,
    hitboxes,
    ...(definition.attackTrack ? { attackTrack: definition.attackTrack } : {}),
    legacyImmediateHit: definition.attackTrack === undefined,
  };
}
