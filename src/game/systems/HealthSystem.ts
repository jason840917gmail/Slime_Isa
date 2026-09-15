import Phaser from 'phaser';
import { gameState } from '../core/GameState';
import { gameEvents } from '../core/EventBus';
import { getStats } from './PlayerStats';
import type { StatusEffectManager } from './StatusEffects';
import { PlayerHealthService } from '../features/player/PlayerHealthService';
import type { DamageAreaRule } from '../features/combat/DamageReceiver';
import type {
  DamageCommit,
  DamageMitigationInput,
  DamageReceiver,
} from '../features/combat/DamageReceiver';

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

export class HealthSystem implements DamageReceiver {
  private readonly playerHealth: PlayerHealthService;
  private legacyActivationSequence = 0;

  constructor(private readonly ctx: HealthSystemContext) {
    this.playerHealth = new PlayerHealthService('legacy:player', {
      state: {
        getHp: () => gameState.hp,
        getMaxHp: () => gameState.maxHp,
        commitResolvedDamage: (amount, source) => gameState.damage(amount, source),
        heal: (amount) => gameState.heal(amount),
        revive: () => gameState.revive(),
      },
      stats: {
        getHealthStats: () => {
          const stats = getStats();
          return {
            defense: stats.defense,
            damageTakenMult: stats.damageTakenMult,
            iFrameMs: stats.iFrameMs,
          };
        },
      },
      feedback: { onDeath: () => this.ctx.onDeath?.() },
    });

    gameEvents.on('player.death', this.handleDeath, this);
  }

  isInvulnerable(time: number): boolean {
    return this.playerHealth.isInvulnerable(time);
  }

  isDead(): boolean {
    return this.playerHealth.isDead();
  }

  get runtimeNodeId(): string {
    return this.playerHealth.runtimeNodeId;
  }

  get managedReceiver(): HealthSystem {
    return this;
  }

  getDamageState() {
    return this.playerHealth.getDamageState();
  }

  canReceiveDamage(input: DamageMitigationInput) {
    return this.playerHealth.canReceiveDamage(input);
  }

  mitigateDamage(input: DamageMitigationInput): number {
    return this.playerHealth.mitigateDamage(input);
  }

  commitDamage(commit: DamageCommit): void {
    this.playerHealth.commitDamage(commit);
  }

  publishDamageFeedback(commit: DamageCommit): void {
    this.playerHealth.publishDamageFeedback(commit);
    if (commit.result.actualDamage > 0) {
      this.ctx.onHit?.({
        status: 'accepted',
        requestedDamage: commit.request.baseDamage,
        mitigatedDamage: commit.result.actualDamage,
        actualHpLost: commit.result.actualDamage,
      });
    }
    if (commit.result.defeated) return;
    const strength = commit.result.appliedEffects.find((effect) => effect.effectId === 'knockback')?.potency ?? 0;
    if (strength <= 0) return;
    const direction = new Phaser.Math.Vector2(commit.request.impact.knockX, commit.request.impact.knockY);
    if (direction.lengthSq() > 0) this.ctx.applyKnockback?.(direction.normalize(), strength, 160);
  }

  applyDamage(req: DamageRequest, time: number): DamageResult {
    if (!Number.isFinite(req.amount) || req.amount <= 0) return this.rejected(req.amount, 'invalid');
    this.legacyActivationSequence += 1;
    const sourceNodeId = req.source?.trim() || 'legacy:unknown';
    const area: DamageAreaRule = {
      areaNodeId: 'legacy:player:body',
      priority: 0,
      damageMultiplier: 1,
    };
    const outcome = this.playerHealth.applyDamage({
      activationId: `${sourceNodeId}:${this.legacyActivationSequence}`,
      sourceNodeId,
      attackAreaNodeId: `${sourceNodeId}:attack`,
      targetAreaNodeId: area.areaNodeId,
      weaponTags: [],
      damageTypes: [],
      baseDamage: req.amount,
      trueDamage: req.trueDamage,
      effects: [],
      impact: {
        x: this.ctx.getPlayer().x,
        y: this.ctx.getPlayer().y,
        knockX: req.knockX ?? 0,
        knockY: req.knockY ?? 0,
      },
    }, area, time);
    if (outcome.result.status === 'rejected') {
      const reason = outcome.result.reason === 'state-blocked' ? 'invulnerable'
        : outcome.result.reason === 'dead' ? 'dead'
          : 'invalid';
      return this.rejected(req.amount, reason);
    }

    if (!outcome.result.defeated && (req.knockX !== undefined || req.knockY !== undefined)) {
      const strength = req.knockStrength ?? 220;
      const direction = new Phaser.Math.Vector2(req.knockX ?? 0, req.knockY ?? 0);
      if (direction.lengthSq() > 0) {
        this.ctx.applyKnockback?.(direction.normalize(), strength, 160);
      }
    }

    const result: AcceptedDamageResult = {
      status: 'accepted',
      requestedDamage: req.amount,
      mitigatedDamage: outcome.roundedDamage,
      actualHpLost: outcome.result.actualDamage,
    };
    this.ctx.onHit?.(result);

    return result;
  }

  heal(amount: number): number {
    return this.playerHealth.heal(amount);
  }

  respawn(): void {
    this.playerHealth.respawn();
  }

  update(time: number): void {
    // Invulnerability flash handled by onHit; nothing to do per-frame here.
    void time;
  }

  private handleDeath = (): void => {
    this.playerHealth.markDead();
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
