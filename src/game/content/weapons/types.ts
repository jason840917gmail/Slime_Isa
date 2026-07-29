import type { AttributeScaling } from '../../combat/CombatScaling';

export interface WeaponDefinition {
  readonly version: 1;
  readonly weaponId: string;
  readonly displayName: string;
  readonly category: 'melee' | 'ranged';
  readonly animKey: string;
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

