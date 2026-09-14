import type {
  DamageAreaRule,
  DamageCommit,
  DamageMitigationInput,
  DamageReceiver,
  DamageRequest,
  DamageResult,
} from '../combat/DamageReceiver';
import { normalizeDamageRequest, resolveDamageDetailed } from '../combat/DamageResolver';
import type { PlayerHealthServicePorts, PlayerHealthStats } from './PlayerServicePorts';

export interface PlayerDamageOutcome {
  readonly result: DamageResult;
  readonly roundedDamage: number;
}

export function mitigatePlayerDamage(scaledDamage: number, trueDamage: boolean, stats: PlayerHealthStats): number {
  if (scaledDamage === 0) return 0;
  const afterDefense = trueDamage ? scaledDamage : Math.max(1, scaledDamage - stats.defense);
  return afterDefense * stats.damageTakenMult;
}

export class PlayerHealthService implements DamageReceiver {
  private iFrameUntil = 0;
  private dead = false;
  private deathPublished = false;

  constructor(
    readonly runtimeNodeId: string,
    private readonly ports: PlayerHealthServicePorts,
  ) {
    this.dead = ports.state.getHp() <= 0;
    this.deathPublished = this.dead;
  }

  getDamageState() {
    const hp = this.ports.state.getHp();
    return { hp, maxHp: this.ports.state.getMaxHp(), dead: this.dead || hp <= 0 };
  }

  canReceiveDamage = (input: DamageMitigationInput) => (
    input.simulationTime < this.iFrameUntil
      ? { accepted: false as const, reason: 'state-blocked' as const }
      : { accepted: true as const }
  );

  mitigateDamage = (input: DamageMitigationInput): number => (
    mitigatePlayerDamage(input.scaledDamage, input.request.trueDamage, this.ports.stats.getHealthStats())
  );

  commitDamage(commit: DamageCommit): void {
    const committed = this.ports.state.commitResolvedDamage(
      commit.result.actualDamage,
      commit.request.sourceNodeId,
    );
    if (committed !== commit.result.actualDamage) {
      throw new Error(
        `Player health commit drifted: resolved ${commit.result.actualDamage}, committed ${committed}.`,
      );
    }
    for (const effect of commit.result.appliedEffects) this.ports.effects?.applyResolvedEffect(effect);

    if (commit.result.defeated) this.markDead();
    else if (commit.result.actualDamage > 0) {
      this.iFrameUntil = commit.simulationTime + this.ports.stats.getHealthStats().iFrameMs;
    }
    this.ports.feedback?.onDamageCommitted?.(commit.result.actualDamage, commit.result.defeated);
  }

  publishDamageFeedback(commit: DamageCommit): void {
    if (commit.result.actualDamage > 0) this.ports.feedback?.onKnockback?.(commit.request.impact);
  }

  applyDamage(request: DamageRequest, area: DamageAreaRule, simulationTime: number): PlayerDamageOutcome {
    const normalized = normalizeDamageRequest(request);
    if (!normalized) return resolveDamageDetailed(this, request, area, simulationTime);
    const outcome = resolveDamageDetailed(this, normalized, area, simulationTime);
    if (outcome.result.status === 'accepted') {
      const commit = Object.freeze({ request: normalized, area, result: outcome.result, simulationTime });
      this.commitDamage(commit);
      this.publishDamageFeedback(commit);
    }
    return outcome;
  }

  isInvulnerable(simulationTime: number): boolean {
    return simulationTime < this.iFrameUntil;
  }

  isDead(): boolean {
    return this.dead || this.ports.state.getHp() <= 0;
  }

  markDead(): void {
    this.dead = true;
    if (this.deathPublished) return;
    this.deathPublished = true;
    this.ports.feedback?.onDeath?.();
  }

  heal(amount: number): number {
    if (this.isDead()) return 0;
    return this.ports.state.heal(amount);
  }

  respawn(): void {
    this.ports.state.revive();
    this.dead = false;
    this.deathPublished = false;
    this.iFrameUntil = 0;
    this.ports.feedback?.onRespawn?.();
  }
}

