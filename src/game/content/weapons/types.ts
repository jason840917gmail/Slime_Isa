import type { AttributeScaling } from '../../combat/CombatScaling';

export interface WeaponDefinition {
  readonly version: 1;
  readonly weaponId: string;
  readonly displayName: string;
  readonly category: 'melee' | 'ranged';
  /** Legacy runtime animation key. New content should use characterActionId. */
  readonly animKey?: string;
  /** Stable character visual clip ID, for example `trick` or `cast`. */
  readonly characterActionId?: string;
  readonly assetId?: string;
  readonly animations?: WeaponAnimationSet;
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
    readonly reach?: AttributeScaling;
  };
  readonly vfxColor: number;
  readonly unlockLevel: number;
  readonly iconKey: string;
  readonly description: string;
}

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

export interface WeaponEventDocument {
  readonly at: number;
  readonly eventId: string;
  readonly payload?: unknown;
}

export interface WeaponAttackTrackDocument {
  readonly hitboxSpans: readonly WeaponHitboxSpanDocument[];
  readonly events?: readonly WeaponEventDocument[];
}

export interface WeaponAnimationDocument {
  readonly frames: readonly number[];
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: 'wrap' | 'ping-pong';
}

export interface WeaponAnimationSet {
  readonly idle: WeaponAnimationDocument;
  readonly attack: WeaponAnimationDocument;
  readonly impact: WeaponAnimationDocument;
}

export interface NormalizedWeaponDefinition extends WeaponDefinition {
  readonly characterActionId: string;
  readonly animations: WeaponAnimationSet;
  readonly visual: NonNullable<WeaponDefinition['visual']>;
  readonly hitboxes: Readonly<Record<string, WeaponHitboxDocument>>;
  readonly attackTrack?: WeaponAttackTrackDocument;
  readonly legacyImmediateHit: boolean;
}
