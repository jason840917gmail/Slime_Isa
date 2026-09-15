import type { AppliedDamageEffect, DamageImpact } from '../combat/DamageReceiver';

export interface PlayerHealthStatePort {
  getHp(): number;
  getMaxHp(): number;
  commitResolvedDamage(amount: number, source?: string): number;
  heal(amount: number): number;
  revive(): void;
}

export interface PlayerHealthStats {
  readonly defense: number;
  readonly damageTakenMult: number;
  readonly iFrameMs: number;
}

export interface PlayerHealthStatsPort {
  getHealthStats(): PlayerHealthStats;
}

export interface PlayerEffectPort {
  applyResolvedEffect(effect: AppliedDamageEffect): void;
}

export interface PlayerHealthFeedbackPort {
  onDamageCommitted?(actualDamage: number, defeated: boolean): void;
  onDeath?(): void;
  onRespawn?(): void;
  onKnockback?(impact: DamageImpact): void;
}

export interface PlayerHealthServicePorts {
  readonly state: PlayerHealthStatePort;
  readonly stats: PlayerHealthStatsPort;
  readonly effects?: PlayerEffectPort;
  readonly feedback?: PlayerHealthFeedbackPort;
}

export interface PlayerPositionPort {
  getPosition(): Readonly<{ x: number; y: number }>;
}

export interface PlayerBodyPort {
  getBodyBounds(): Readonly<{ x: number; y: number; width: number; height: number }>;
}

export interface PlayerDodgePort {
  isDodging(): boolean;
}

export interface PlayerKnockbackPort {
  applyKnockback(direction: Readonly<{ x: number; y: number }>, strength: number, durationMs: number): void;
}

export interface PlayerRuntimePorts extends PlayerPositionPort, PlayerBodyPort, PlayerDodgePort, PlayerKnockbackPort {}

export interface PlayerMotionPort extends PlayerDodgePort, PlayerKnockbackPort {
  move(direction: Readonly<{ x: number; y: number }>, speed: number): boolean;
  stopMovement(): void;
  beginDodge(direction: Readonly<{ x: number; y: number }>, speed: number, invulnerabilityMs: number): boolean;
  isMovementSuppressed(): boolean;
}

export interface PlayerActorPort extends PlayerRuntimePorts, PlayerMotionPort {}
