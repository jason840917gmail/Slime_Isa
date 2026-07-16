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
  /** Called when i-frames start (e.g. to flash the sprite). */
  onHit?: () => void;
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

  applyDamage(req: DamageRequest, time: number): number {
    if (this.dead) return 0;
    if (this.isInvulnerable(time)) return 0;
    if (req.amount <= 0) return 0;

    const stats = getStats();
    const mitigated = req.trueDamage ? req.amount : Math.max(1, req.amount - stats.defense);
    const final = Math.round(mitigated * stats.damageTakenMult);

    gameState.damage(final, req.source);

    this.iFrameUntil = time + stats.iFrameMs;

    // Knockback
    const player = this.ctx.getPlayer();
    if (req.knockX !== undefined || req.knockY !== undefined) {
      const strength = req.knockStrength ?? 220;
      const kx = (req.knockX ?? 0) * strength;
      const ky = (req.knockY ?? 0) * strength;
      player.setVelocity(kx, ky);
    }

    this.ctx.onHit?.();

    return final;
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
}
