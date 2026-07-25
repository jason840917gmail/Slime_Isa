import Phaser from 'phaser';
import { gameState } from '../core/GameState';
import { gameEvents } from '../core/EventBus';
import { getStats } from './PlayerStats';
import type { StatusEffectManager } from './StatusEffects';

/**
 * HealthSystem handles the damage pipeline for the player:
 *
 *   incoming → defense mitigation → status modifiers → apply
 *            → i-frames → knockback → flash → event → death check
 *
 * Owned by the scene; given a reference to the player sprite and the status
 * manager. Knockback applied via the arcade body.
 */

export interface HealthSystemContext {
  scene: Phaser.Scene;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getStatus: () => StatusEffectManager;
  /** Applies accepted-hit knockback without allowing movement to overwrite it. */
  applyKnockback?: (direction: Phaser.Math.Vector2, strength: number, durationMs: number) => void;
  /** Called after an accepted hit so the scene can render feedback. */
  onHit?: (result: AcceptedDamageResult) => void;
  /** Called when the player dies (scene decides respawn / game over). */
  onDeath?: () => void;
}

export interface DamageRequest {
  amount: number;
  source?: string;
  /** Knockback direction (normalized) + magnitude. */
  knockX?: number;
  knockY?: number;
  knockStrength?: number;
  /** True = ignore defense mitigation. */
  trueDamage?: boolean;
}

export interface AcceptedDamageResult {
  status: 'accepted';
  requestedDamage: number;
  mitigatedDamage: number;
  actualHpLost: number;
}

export interface RejectedDamageResult {
  status: 'rejected';
  reason: 'dead' | 'invulnerable' | 'invalid';
  requestedDamage: number;
  mitigatedDamage: 0;
  actualHpLost: 0;
}

export type DamageResult = AcceptedDamageResult | RejectedDamageResult;

export class HealthSystem {
  private ctx: HealthSystemContext;
  private iFrameUntil = 0;
  private dead = false;

  constructor(ctx: HealthSystemContext) {
    this.ctx = ctx;

    gameEvents.on('player.death', this.handleDeath, this);
  }

  isInvulnerable(time: number): boolean {
    return time < this.iFrameUntil;
  }

  isDead(): boolean {
    return this.dead;
  }

  applyDamage(req: DamageRequest, time: number): DamageResult {
    if (this.dead) return this.rejected(req.amount, 'dead');
    if (this.isInvulnerable(time)) return this.rejected(req.amount, 'invulnerable');
    if (!Number.isFinite(req.amount) || req.amount <= 0) return this.rejected(req.amount, 'invalid');

    const stats = getStats();
    const mitigated = req.trueDamage ? req.amount : Math.max(1, req.amount - stats.defense);
    const final = Math.round(mitigated * stats.damageTakenMult);
    const actualHpLost = gameState.damage(final, req.source);
    if (actualHpLost <= 0) return this.rejected(req.amount, 'dead');

    if (!gameState.isDead()) {
      this.iFrameUntil = time + stats.iFrameMs;

      if (req.knockX !== undefined || req.knockY !== undefined) {
        const strength = req.knockStrength ?? 220;
        const direction = new Phaser.Math.Vector2(req.knockX ?? 0, req.knockY ?? 0);
        if (direction.lengthSq() > 0) {
          this.ctx.applyKnockback?.(direction.normalize(), strength, 160);
        }
      }
    }

    const result: AcceptedDamageResult = {
      status: 'accepted',
      requestedDamage: req.amount,
      mitigatedDamage: final,
      actualHpLost,
    };
    this.ctx.onHit?.(result);

    return result;
  }

  heal(amount: number): number {
    if (this.dead) return 0;
    return gameState.heal(amount);
  }

  respawn(): void {
    this.dead = false;
    this.iFrameUntil = 0;
    gameState.revive();
  }

  update(time: number): void {
    if (this.dead) return;
    // Invulnerability flash handled by onHit; nothing to do per-frame here.
    void time;
  }

  private handleDeath = (): void => {
    if (this.dead) return;
    this.dead = true;
    this.ctx.onDeath?.();
  };

  destroy(): void {
    gameEvents.off('player.death', this.handleDeath, this);
  }

  private rejected(
    requestedDamage: number,
    reason: RejectedDamageResult['reason'],
  ): RejectedDamageResult {
    return {
      status: 'rejected',
      reason,
      requestedDamage,
      mitigatedDamage: 0,
      actualHpLost: 0,
    };
  }
}
