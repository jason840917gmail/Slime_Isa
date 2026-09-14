import type { DamageResult, NormalizedDamageRequest, RuntimeNodeId } from './DamageReceiver';
import { rejectedDamage } from './DamageReceiver';

interface ActiveAttack {
  readonly activationId: string;
  readonly sourceNodeId: RuntimeNodeId;
  readonly attackAreaNodeIds: Set<RuntimeNodeId>;
  readonly acceptedReceivers: Set<RuntimeNodeId>;
  readonly terminalRejections: Map<RuntimeNodeId, Set<string>>;
}

export class AttackActivation {
  private readonly sequenceBySource = new Map<RuntimeNodeId, number>();
  private readonly active = new Map<string, ActiveAttack>();

  begin(sourceNodeId: RuntimeNodeId, attackAreaNodeIds: readonly RuntimeNodeId[]): string {
    if (sourceNodeId.trim().length === 0 || attackAreaNodeIds.length === 0
      || attackAreaNodeIds.some((id) => id.trim().length === 0)) {
      throw new Error('An attack activation requires a source and at least one valid attack area.');
    }
    const sequence = (this.sequenceBySource.get(sourceNodeId) ?? 0) + 1;
    this.sequenceBySource.set(sourceNodeId, sequence);
    const activationId = `${sourceNodeId}:${sequence}`;
    this.active.set(activationId, {
      activationId,
      sourceNodeId,
      attackAreaNodeIds: new Set(attackAreaNodeIds),
      acceptedReceivers: new Set(),
      terminalRejections: new Map(),
    });
    return activationId;
  }

  end(activationId: string): void {
    this.active.delete(activationId);
  }

  clearSource(sourceNodeId: RuntimeNodeId): void {
    for (const [activationId, attack] of this.active) {
      if (attack.sourceNodeId === sourceNodeId) this.active.delete(activationId);
    }
  }

  validate(request: NormalizedDamageRequest): DamageResult | undefined {
    const attack = this.active.get(request.activationId);
    if (!attack || attack.sourceNodeId !== request.sourceNodeId
      || !attack.attackAreaNodeIds.has(request.attackAreaNodeId)) {
      return rejectedDamage('inactive-attack', false);
    }
    return undefined;
  }

  beforeAttempt(
    activationId: string,
    receiverNodeId: RuntimeNodeId,
    areaSignature: string,
  ): DamageResult | undefined {
    const attack = this.active.get(activationId);
    if (!attack) return rejectedDamage('inactive-attack', false);
    if (attack.acceptedReceivers.has(receiverNodeId)) return rejectedDamage('duplicate', false);
    if (attack.terminalRejections.get(receiverNodeId)?.has(areaSignature)) {
      return rejectedDamage('duplicate', false);
    }
    return undefined;
  }

  record(
    activationId: string,
    receiverNodeId: RuntimeNodeId,
    areaSignature: string,
    result: DamageResult,
  ): void {
    const attack = this.active.get(activationId);
    if (!attack) return;
    if (result.status === 'accepted') {
      attack.acceptedReceivers.add(receiverNodeId);
      return;
    }
    if (result.retryable) return;
    const signatures = attack.terminalRejections.get(receiverNodeId) ?? new Set<string>();
    signatures.add(areaSignature);
    attack.terminalRejections.set(receiverNodeId, signatures);
  }
}

export function areaSetSignature(areaNodeIds: readonly RuntimeNodeId[]): string {
  return [...new Set(areaNodeIds)].sort().join('|');
}

