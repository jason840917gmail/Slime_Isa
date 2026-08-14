import type { AttributeScaling } from '../../combat/CombatScaling';
import type {
  AnimationClipDocument,
  AnimationEventDocument,
  AnimationJsonValue,
  LayeredAnimationDocument,
  NormalizedAnimationClipDocument,
  NormalizedLayeredAnimationDocument,
} from '../../shared/animation';

/** Compatibility value used only while normalizing pre-authored sector hitboxes. */
export const LEGACY_WEAPON_SECTOR_ARC_RAD = 0.8;

export interface WeaponCombatDefinition {
  readonly weaponId: string;
  readonly displayName: string;
  readonly category: 'melee' | 'ranged';
  readonly baseDamage: number;
  readonly cooldownMs: number;
  readonly hitboxWidth: number;
  readonly hitboxHeight: number;
  readonly hitboxOffset: number;
  readonly hitboxDurationMs: number;
  readonly knockStrength: number;
  readonly scaling?: {
    readonly damage?: AttributeScaling;
    readonly cooldown?: AttributeScaling;
    readonly knockback?: AttributeScaling;
  };
  readonly vfxColor: number;
  readonly unlockLevel: number;
  readonly iconKey: string;
  readonly description: string;
}

/** Existing single-layer storage shape retained as migration input. */
export interface LegacyWeaponDefinition extends WeaponCombatDefinition {
  readonly version: 1;
  /** Legacy runtime animation key. New content should use characterActionId. */
  readonly animKey?: string;
  readonly characterActionId?: string;
  readonly assetId?: string;
  readonly animations?: WeaponAnimationSet;
  readonly directionalAttacks?: Partial<Readonly<Record<WeaponAuthoredAttackDirection, WeaponDirectionalAttackDocument>>>;
  readonly hitboxes?: Readonly<Record<string, WeaponHitboxDocument>>;
  readonly attackTrack?: WeaponAttackTrackDocument;
  readonly visual?: {
    readonly sourceOffset: readonly [number, number];
    readonly animationOffsets?: Readonly<Record<string, readonly [number, number]>>;
    readonly frameOffsets?: Readonly<Record<string, readonly [number, number]>>;
    readonly origin?: readonly [number, number];
    readonly scale?: readonly [number, number];
    readonly facingMode?: 'vector' | 'horizontal-flip';
  };
}

/** Compatibility name used by the legacy Weapon Studio until its v2 migration task. */
export type WeaponDefinition = LegacyWeaponDefinition;

export interface LayeredWeaponDirectionalAttackDocument {
  readonly animation: LayeredAnimationDocument;
  readonly characterActionId: string;
  readonly attackTrack?: WeaponAttackTrackDocument;
  readonly hitboxes: Readonly<Record<string, WeaponHitboxDocument>>;
}

export interface LayeredWeaponDefinition extends WeaponCombatDefinition {
  readonly version: 2;
  readonly characterActionId: string;
  readonly animations: {
    readonly idle: LayeredAnimationDocument;
  };
  readonly directionalAttacks: {
    readonly right: LayeredWeaponDirectionalAttackDocument;
    readonly left?: LayeredWeaponDirectionalAttackDocument;
    readonly down: LayeredWeaponDirectionalAttackDocument;
    readonly up?: LayeredWeaponDirectionalAttackDocument;
  };
  readonly presentation?: {
    readonly facingMode?: 'vector' | 'horizontal-flip';
  };
  readonly onHitEffectId?: string;
}

export type AuthoredWeaponDefinition = LegacyWeaponDefinition | LayeredWeaponDefinition;

export type WeaponHitboxShape = 'rectangle' | 'circle' | 'ellipse' | 'sector';

export interface WeaponHitboxDocument {
  readonly shape: WeaponHitboxShape;
  readonly width: number;
  readonly height: number;
  readonly radius?: number;
  readonly radiusX?: number;
  readonly radiusY?: number;
  readonly offsetX: number;
  readonly offsetY: number;
  readonly innerRadius?: number;
  readonly outerRadius?: number;
  readonly arcWidthRad?: number;
  readonly damageMultiplier?: number;
  readonly knockbackMultiplier?: number;
}

export interface WeaponHitboxSpanDocument {
  readonly hitboxId: string;
  readonly from: number;
  readonly through: number;
}

export interface WeaponEventDocument extends AnimationEventDocument {
  readonly payload?: AnimationJsonValue;
}

export interface WeaponAttackTrackDocument {
  readonly hitboxSpans: readonly WeaponHitboxSpanDocument[];
  readonly events?: readonly WeaponEventDocument[];
}

export interface WeaponAnimationDocument extends AnimationClipDocument {
  /** Per-occurrence visual edits keyed by position in `frames`, not source frame number. */
  readonly frameTransforms?: Readonly<Record<string, WeaponFrameTransformDocument>>;
}

export interface NormalizedWeaponAnimationDocument extends NormalizedAnimationClipDocument {
  readonly frameTransforms?: Readonly<Record<string, WeaponFrameTransformDocument>>;
}

export interface WeaponFrameTransformDocument {
  readonly offset?: readonly [number, number];
  readonly scale?: readonly [number, number];
  readonly rotationDeg?: number;
}

export type WeaponAttackDirection = 'right' | 'left' | 'up' | 'down';
/** `side` is accepted only as migration input from the original three-direction format. */
export type WeaponAuthoredAttackDirection = WeaponAttackDirection | 'side';
export type WeaponPlaybackAnimationId = 'idle' | 'attack-right' | 'attack-left' | 'attack-up' | 'attack-down';

export interface WeaponDirectionalAttackDocument {
  readonly animation: WeaponAnimationDocument;
  readonly characterActionId?: string;
  readonly attackTrack?: WeaponAttackTrackDocument;
  readonly hitboxes?: Readonly<Record<string, WeaponHitboxDocument>>;
}

export type WeaponDirectionalPresentation = 'legacy-vector' | 'authored' | 'mirror-right' | 'mirror-down';

export interface NormalizedWeaponDirectionalAttack {
  readonly animation: NormalizedLayeredAnimationDocument;
  readonly characterActionId: string;
  readonly attackTrack?: WeaponAttackTrackDocument;
  readonly hitboxes: Readonly<Record<string, WeaponHitboxDocument>>;
  readonly authored: boolean;
  readonly presentation: WeaponDirectionalPresentation;
  readonly sourceDirection: WeaponAttackDirection;
  readonly mirrorX: boolean;
  readonly mirrorY: boolean;
}

export interface WeaponAnimationSet {
  readonly idle: WeaponAnimationDocument;
  readonly attack: WeaponAnimationDocument;
  readonly impact: WeaponAnimationDocument;
}

/** Retained for legacy editor helpers while Weapon Studio is migrated. */
export interface NormalizedWeaponAnimationSet {
  readonly idle: NormalizedWeaponAnimationDocument;
  readonly attack: NormalizedWeaponAnimationDocument;
  readonly impact: NormalizedWeaponAnimationDocument;
}

export interface NormalizedWeaponDefinition extends WeaponCombatDefinition {
  readonly sourceVersion: 1 | 2;
  readonly characterActionId: string;
  readonly animations: {
    readonly idle: NormalizedLayeredAnimationDocument;
  };
  readonly directionalAttacks: Readonly<Record<WeaponAttackDirection, NormalizedWeaponDirectionalAttack>>;
  readonly presentation: {
    readonly facingMode: 'vector' | 'horizontal-flip';
  };
  readonly onHitEffectId?: string;
  readonly legacyImmediateHit: boolean;
}
