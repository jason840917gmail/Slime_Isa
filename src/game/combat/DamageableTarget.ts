import Phaser from 'phaser';

export interface DamageApplicationRequest {
  readonly amount: number;
  readonly knockX: number;
  readonly knockY: number;
  readonly knockStrength: number;
}

export interface DamageApplicationResult {
  readonly status: 'accepted' | 'rejected';
  readonly actualDamage: number;
  readonly defeated: boolean;
  readonly reason?: 'dead' | 'invulnerable' | 'invalid';
}

export interface DamageableTarget extends Phaser.GameObjects.GameObject {
  applyDamage(request: DamageApplicationRequest): DamageApplicationResult;
}

export function rejectedDamage(reason: NonNullable<DamageApplicationResult['reason']>): DamageApplicationResult {
  return { status: 'rejected', actualDamage: 0, defeated: false, reason };
}

export function acceptedDamage(hpBefore: number, hpAfter: number): DamageApplicationResult {
  const actualDamage = Math.max(0, Math.min(hpBefore, hpBefore - hpAfter));
  return { status: 'accepted', actualDamage, defeated: hpBefore > 0 && hpAfter <= 0 };
}
