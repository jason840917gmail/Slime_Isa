import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { DamageCommit, DamageMitigationInput, DamageStateDecision } from '../combat/DamageReceiver';
import { bossPerimeterContains, clampToBossArena } from '../bosses/BossCampBehavior';
import { EnemyScript } from './EnemyScript';

type FattyOneEyePhase = 'chase' | 'return-to-center' | 'contact-hop' | 'small-hop' | 'airborne' | 'landing' | 'recovery' | 'dead';

export class FattyScript extends EnemyScript {
  private phaseValue: FattyOneEyePhase = 'chase';
  private phaseStartedAt = 0;
  private nextContactHopAt = 0;
  private nextLeapAt = 0;
  private leapFrom = { x: 0, y: 0 };
  private leapTarget = { x: 0, y: 0 };

  get phase(): FattyOneEyePhase { return this.phaseValue; }

  override canReceiveDamage(input: DamageMitigationInput): DamageStateDecision {
    if (this.phaseValue === 'airborne' || this.phaseValue === 'contact-hop') {
      return { accepted: false as const, reason: 'state-blocked' as const };
    }
    return super.canReceiveDamage(input);
  }

  /**
   * Bosses keep their authored phase flow: a hit never cancels a phase or
   * stuns. Only while chasing does a non-immune knockback shove the body, with
   * the raw knockback strength and no resistance scaling (legacy boss rule).
   */
  protected override reactToDamage(commit: DamageCommit, defeated: boolean): void {
    if (defeated || this.phaseValue !== 'chase') return;
    const potency = commit.result.appliedEffects
      .filter((effect) => effect.effectId === 'knockback')
      .reduce((total, effect) => total + effect.potency, 0);
    const length = Math.hypot(commit.request.impact.knockX, commit.request.impact.knockY);
    if (potency <= 0 || length === 0) return;
    this.body().velocity = {
      x: (commit.request.impact.knockX / length) * potency,
      y: (commit.request.impact.knockY / length) * potency,
    };
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.nextLeapAt = this.simulationTime + Math.max(1, this.numberProperty('leapCadenceMs', 5000));
  }

  override _physics_process(deltaSeconds: number): void {
    super._physics_process(deltaSeconds);
    if (this.defeated || this.phaseValue === 'dead') return;
    const time = this.simulationTime;
    const body = this.body();

    // The arena leash itself lives in EnemyScript; Fatty only mirrors it as a phase.
    if (this.phaseValue === 'chase') {
      if (this.returningToArena) {
        this.beginReturn(time);
        return;
      }
      if (this.runtimeState === 'attack') {
        if (this.requestContactHop(time)) this.playAnimation('contact-hop');
        return;
      }
      if (time >= this.nextLeapAt) {
        this.cancelAttack();
        this.beginLeapTelegraph(time);
        body.velocity = { x: 0, y: 0 };
      }
      return;
    }

    if (this.phaseValue === 'return-to-center') {
      if (!this.returningToArena) this.resumeChase(time);
      return;
    }

    body.velocity = { x: 0, y: 0 };
    if (this.phaseValue === 'contact-hop') {
      if (this.elapsedInPhase(time) >= Math.max(1, this.numberProperty('contactHopDurationMs', 300))) {
        this.resumeChase(time);
      }
      return;
    }
    if (this.phaseValue === 'small-hop') {
      const hopCycle = Math.max(1, this.numberProperty('smallHopDurationMs', 260) + this.numberProperty('betweenHopsMs', 100));
      const telegraphDuration = hopCycle * Math.max(1, this.numberProperty('smallHopCount', 3));
      if (this.elapsedInPhase(time) >= telegraphDuration) this.beginAirborne(time);
      return;
    }
    if (this.phaseValue === 'airborne') {
      const airTime = Math.max(1, this.numberProperty('airTimeMs', 1000));
      const progress = Math.min(1, this.elapsedInPhase(time) / airTime);
      body.set_global_transform({
        ...body.get_global_transform(),
        position: {
          x: this.leapFrom.x + (this.leapTarget.x - this.leapFrom.x) * progress,
          y: this.leapFrom.y + (this.leapTarget.y - this.leapFrom.y) * progress,
        },
      });
      if (progress >= 1) this.land(time);
      return;
    }
    if (this.phaseValue === 'landing' && this.elapsedInPhase(time) >= 360) {
      this.beginRecovery(time);
      return;
    }
    if (this.phaseValue === 'recovery' && this.elapsedInPhase(time) >= Math.max(1, this.numberProperty('recoveryMs', 700))) {
      this.nextLeapAt = time + Math.max(1, this.numberProperty('leapCadenceMs', 5000));
      this.resumeChase(time);
    }
  }

  requestContactHop(time: number): boolean {
    if (this.defeated || this.phaseValue !== 'chase' || time < this.nextContactHopAt) return false;
    const arena = this.arena();
    if (arena && !bossPerimeterContains(arena, this.worldPosition.x, this.worldPosition.y)) return false;
    this.transitionTo('contact-hop', time);
    this.nextContactHopAt = time + Math.max(1, this.numberProperty('contactHopCooldownMs', 1000));
    this.setBodyCollision(false);
    return true;
  }

  beginLeapTelegraph(time: number): boolean {
    if (this.defeated || this.phaseValue !== 'chase') return false;
    this.transitionTo('small-hop', time);
    this.playAnimation('small-hop');
    return true;
  }

  beginAirborne(time: number): boolean {
    if (this.phaseValue !== 'small-hop') return false;
    this.leapFrom = this.body().get_global_transform().position;
    const target = this.currentTarget()?.position ?? this.leapFrom;
    const arena = this.arena();
    this.leapTarget = arena ? clampToBossArena(arena, target) : target;
    this.setBodyCollision(false);
    this.transitionTo('airborne', time);
    this.playAnimation('airborne');
    return true;
  }

  land(time: number): boolean {
    if (this.phaseValue !== 'airborne') return false;
    this.setBodyCollision(true);
    this.transitionTo('landing', time);
    this.playAnimation('landing');
    const target = this.currentTarget();
    if (target) this.routeImmediateAttack(target, this.numberProperty('landingDamage', 32), this.numberProperty('landingRadius', 64));
    return true;
  }

  beginRecovery(time: number): boolean {
    if (this.phaseValue !== 'landing') return false;
    this.transitionTo('recovery', time);
    this.playAnimation('recovery');
    return true;
  }

  resumeChase(time: number): boolean {
    if (!['contact-hop', 'recovery', 'return-to-center'].includes(this.phaseValue)) return false;
    this.setBodyCollision(true);
    this.transitionTo('chase', time);
    this.playAnimation('chase');
    return true;
  }

  beginReturn(time: number): boolean {
    if (this.defeated || this.phaseValue === 'dead') return false;
    this.setBodyCollision(true);
    this.transitionTo('return-to-center', time);
    this.playAnimation('chase');
    return true;
  }

  elapsedInPhase(time: number): number {
    return Math.max(0, time - this.phaseStartedAt);
  }

  protected override defeat(): void {
    if (this.defeated) return;
    super.defeat();
    this.setBodyCollision(false);
    this.playAnimation('death');
    this.transitionTo('dead', this.simulationTime);
  }

  protected override canRunCommonAttack(): boolean { return this.phaseValue === 'chase'; }
  protected override mirrorsSideFacing(): boolean { return false; }

  private transitionTo(phase: FattyOneEyePhase, time: number): void {
    this.phaseValue = phase;
    this.phaseStartedAt = time;
    this.getSignal<{ phase: FattyOneEyePhase; time: number }>('phase_changed')?.emit({ phase, time });
  }

  private setBodyCollision(enabled: boolean): void {
    const body = this.body() as unknown as { collisionEnabled?: boolean };
    if ('collisionEnabled' in body) body.collisionEnabled = enabled;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): FattyScript {
    return new FattyScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
