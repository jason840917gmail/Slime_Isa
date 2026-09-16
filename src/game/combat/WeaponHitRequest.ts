import type Phaser from 'phaser';

import type { WeaponAttackDirection } from '../content/weapons/types';
import type { HitboxConfig } from './Hitbox';

export interface WeaponHitRequest {
  readonly target: Phaser.GameObjects.GameObject;
  readonly damage: number;
  readonly knockX: number;
  readonly knockY: number;
  readonly knockStrength: number;
  readonly weaponId: string;
  readonly hitboxId: string;
  readonly attackDirection: WeaponAttackDirection;
  readonly attackVector: readonly [number, number];
  readonly playbackId: number;
  readonly hitbox: Readonly<HitboxConfig>;
}
