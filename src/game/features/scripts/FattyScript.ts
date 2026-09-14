import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { DamageMitigationInput, DamageStateDecision } from '../combat/DamageReceiver';
import type { FattyOneEyePhase } from '../bosses/FattyOneEyeBehavior';
import { EnemyScript } from './EnemyScript';

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

  override _enter_tree(): void {
    super._enter_tree();
    this.nextLeapAt = this.simulationTime + Math.max(1, this.numberProperty('leapCadenceMs', 5000));
  }

  override _physics_process(deltaSeconds: number): void {
    super._physics_process(deltaSeconds);
    if (this.defeated || this.phaseValue === 'dead') return;
    const time = this.simulationTime;
    const body = this.body();

    if (this.phaseValue === 'chase') {
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

    body.velocity = { x: 0, y: 0 };
    if (this.phaseValue === 'contact-hop') {
      if (this.elapsedInPhase(time) >= Math.max(1, this.numberProperty('contactHopDurationMs', 300))) {
        this.resumeChase(time);
        this.playAnimation('chase');
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
      this.resumeChase(time);
      this.nextLeapAt = time + Math.max(1, this.numberProperty('leapCadenceMs', 5000));
      this.playAnimation('chase');
    }
  }

  requestContactHop(time: number): boolean {
    if (this.defeated || this.phaseValue !== 'chase' || time < this.nextContactHopAt) return false;
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
    this.leapTarget = this.currentTarget()?.position ?? this.leapFrom;
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
    this.transitionTo('return-to-center', time);
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
