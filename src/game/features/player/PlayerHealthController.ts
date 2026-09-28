import { gameState } from '../../core/GameState';
import { gameEvents } from '../../core/EventBus';
import { getStats } from '../../systems/PlayerStats';
import { PlayerHealthService } from './PlayerHealthService';
import type { DamageAreaRule } from '../combat/DamageReceiver';
import type {
  DamageCommit,
  DamageMitigationInput,
  DamageReceiver,
} from '../combat/DamageReceiver';

/**
 * Player-facing damage pipeline:
 *
 *   incoming → defense mitigation → status modifiers → apply
 *            → i-frames → knockback → flash → event → death check
 *
 * The scene supplies position and presentation feedback; combat rules remain
 * independent of Phaser.
 */

export interface PlayerHealthControllerContext {
  getPlayerPosition: () => { readonly x: number; readonly y: number };
  /** Applies accepted-hit knockback without allowing movement to overwrite it. */
  applyKnockback?: (direction: { readonly x: number; readonly y: number }, strength: number, durationMs: number) => void;
  /** Sticks the player in place (web hit) for the given milliseconds. */
  applyWeb?: (durationMs: number) => void;
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

export class PlayerHealthController implements DamageReceiver {
  private readonly playerHealth: PlayerHealthService;
  private directActivationSequence = 0;

  constructor(private readonly ctx: PlayerHealthControllerContext) {
    this.playerHealth = new PlayerHealthService('managed-player/Health', {
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
    const webMs = commit.result.appliedEffects.find((effect) => effect.effectId === 'web')?.potency ?? 0;
    if (webMs > 0) this.ctx.applyWeb?.(webMs);
    const strength = commit.result.appliedEffects.find((effect) => effect.effectId === 'knockback')?.potency ?? 0;
    if (strength <= 0) return;
    this.applyKnockback(commit.request.impact.knockX, commit.request.impact.knockY, strength, 160);
  }

  applyDamage(req: DamageRequest, time: number): DamageResult {
    if (!Number.isFinite(req.amount) || req.amount <= 0) return this.rejected(req.amount, 'invalid');
    this.directActivationSequence += 1;
    const sourceNodeId = req.source?.trim() || 'external:unknown';
    const area: DamageAreaRule = {
      areaNodeId: 'managed-player/Body',
      priority: 0,
      damageMultiplier: 1,
    };
    const outcome = this.playerHealth.applyDamage({
      activationId: `${sourceNodeId}:${this.directActivationSequence}`,
      sourceNodeId,
      attackAreaNodeId: `${sourceNodeId}:attack`,
      targetAreaNodeId: area.areaNodeId,
      weaponTags: [],
      damageTypes: [],
      baseDamage: req.amount,
      trueDamage: req.trueDamage,
      effects: [],
      impact: {
        x: this.ctx.getPlayerPosition().x,
        y: this.ctx.getPlayerPosition().y,
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
      this.applyKnockback(req.knockX ?? 0, req.knockY ?? 0, strength, 160);
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

  private applyKnockback(x: number, y: number, strength: number, durationMs: number): void {
    const length = Math.hypot(x, y);
    if (length > 0) this.ctx.applyKnockback?.({ x: x / length, y: y / length }, strength, durationMs);
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
