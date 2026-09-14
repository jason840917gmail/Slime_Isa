import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { DamageMitigationInput, DamageStateDecision } from '../combat/DamageReceiver';
import type { FattyOneEyePhase } from '../bosses/FattyOneEyeBehavior';
import { EnemyScript } from './EnemyScript';

export class FattyScript extends EnemyScript {
  private phaseValue: FattyOneEyePhase = 'chase';
  private phaseStartedAt = 0;
  private nextContactHopAt = 0;

  get phase(): FattyOneEyePhase { return this.phaseValue; }

  override canReceiveDamage(input: DamageMitigationInput): DamageStateDecision {
    if (this.phaseValue === 'airborne' || this.phaseValue === 'contact-hop') {
      return { accepted: false as const, reason: 'state-blocked' as const };
    }
    return super.canReceiveDamage(input);
  }

  requestContactHop(time: number): boolean {
    if (this.defeated || this.phaseValue !== 'chase' || time < this.nextContactHopAt) return false;
    this.transitionTo('contact-hop', time);
    this.nextContactHopAt = time + Math.max(1, this.numberProperty('contactHopCooldownMs', 1000));
    return true;
  }

  beginLeapTelegraph(time: number): boolean {
    if (this.defeated || this.phaseValue !== 'chase') return false;
    this.transitionTo('small-hop', time);
    return true;
  }

  beginAirborne(time: number): boolean {
    if (this.phaseValue !== 'small-hop') return false;
    this.transitionTo('airborne', time);
    return true;
  }

  land(time: number): boolean {
    if (this.phaseValue !== 'airborne') return false;
    this.transitionTo('landing', time);
    return true;
  }

  beginRecovery(time: number): boolean {
    if (this.phaseValue !== 'landing') return false;
    this.transitionTo('recovery', time);
    return true;
  }

  resumeChase(time: number): boolean {
    if (!['contact-hop', 'recovery', 'return-to-center'].includes(this.phaseValue)) return false;
    this.transitionTo('chase', time);
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
    this.transitionTo('dead', this.phaseStartedAt);
  }

  private transitionTo(phase: FattyOneEyePhase, time: number): void {
    this.phaseValue = phase;
    this.phaseStartedAt = time;
    this.getSignal<{ phase: FattyOneEyePhase; time: number }>('phase_changed')?.emit({ phase, time });
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
