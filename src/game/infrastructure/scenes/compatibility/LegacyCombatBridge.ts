import type { AttackActivation } from '../../../features/combat/AttackActivation';
import type { DamageEffectRequest, DamageImpact, DamageRequest, DamageResult } from '../../../features/combat/DamageReceiver';
import type { DamageRouter, RoutedDamageOutcome } from '../../../features/combat/DamageRouter';

export interface LegacyWeaponContact {
  readonly sourceNodeId: string;
  readonly attackAreaNodeId: string;
  readonly targetAreaNodeId: string;
  readonly weaponId?: string;
  readonly weaponTags?: readonly string[];
  readonly damageTypes?: readonly string[];
  readonly damage: number;
  readonly trueDamage?: boolean;
  readonly effects?: readonly DamageEffectRequest[];
  readonly impact: DamageImpact;
}

export class LegacyCombatBridge {
  private readonly pending: DamageRequest[] = [];
  private readonly activationBySource = new Map<string, string>();
  private disposed = false;

  constructor(
    private readonly activations: AttackActivation,
    private readonly router: DamageRouter,
  ) {}

  beginAttack(sourceNodeId: string, attackAreaNodeIds: readonly string[]): string {
    this.assertActive();
    const previous = this.activationBySource.get(sourceNodeId);
    if (previous) this.activations.end(previous);
    const activationId = this.activations.begin(sourceNodeId, attackAreaNodeIds);
    this.activationBySource.set(sourceNodeId, activationId);
    return activationId;
  }

  collectContact(contact: LegacyWeaponContact): boolean {
    this.assertActive();
    const activationId = this.activationBySource.get(contact.sourceNodeId);
    if (!activationId) return false;
    this.pending.push(Object.freeze({
      activationId,
      sourceNodeId: contact.sourceNodeId,
      attackAreaNodeId: contact.attackAreaNodeId,
      targetAreaNodeId: contact.targetAreaNodeId,
      weaponId: contact.weaponId,
      weaponTags: Object.freeze([...(contact.weaponTags ?? [])]),
      damageTypes: Object.freeze([...(contact.damageTypes ?? [])]),
      baseDamage: contact.damage,
      trueDamage: contact.trueDamage,
      effects: Object.freeze([...(contact.effects ?? [])]),
      impact: Object.freeze({ ...contact.impact }),
    }));
    return true;
  }

  resolveStep(simulationTime: number): readonly RoutedDamageOutcome[] {
    this.assertActive();
    const contacts = this.pending.splice(0);
    return this.router.routeStep(contacts, simulationTime);
  }

  cancelAttack(sourceNodeId: string): void {
    const activationId = this.activationBySource.get(sourceNodeId);
    if (activationId) this.activations.end(activationId);
    this.activationBySource.delete(sourceNodeId);
    for (let index = this.pending.length - 1; index >= 0; index -= 1) {
      if (this.pending[index].sourceNodeId === sourceNodeId) this.pending.splice(index, 1);
    }
  }

  currentActivation(sourceNodeId: string): string | undefined {
    return this.activationBySource.get(sourceNodeId);
  }

  dispose(): void {
    if (this.disposed) return;
    for (const sourceNodeId of [...this.activationBySource.keys()]) this.cancelAttack(sourceNodeId);
    this.pending.length = 0;
    this.disposed = true;
  }

  private assertActive(): void {
    if (this.disposed) throw new Error('LegacyCombatBridge has been disposed.');
  }
}

export function legacyDamageAccepted(outcome: RoutedDamageOutcome | undefined): outcome is RoutedDamageOutcome & {
  readonly result: Extract<DamageResult, { readonly status: 'accepted' }>;
} {
  return outcome?.result.status === 'accepted';
}

