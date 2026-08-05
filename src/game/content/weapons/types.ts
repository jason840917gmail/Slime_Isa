import type { AttributeScaling } from '../../combat/CombatScaling';

export interface WeaponDefinition {
  readonly version: 1;
  readonly weaponId: string;
  readonly displayName: string;
  readonly category: 'melee' | 'ranged';
  readonly animKey: string;
  readonly assetId?: string;
  readonly animations?: WeaponAnimationSet;
  readonly visual?: {
    readonly sourceOffset: readonly [number, number];
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
