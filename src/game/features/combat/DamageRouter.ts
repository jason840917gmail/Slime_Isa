import { areaSetSignature, AttackActivation } from './AttackActivation';
import type {
  DamageAreaRule,
  DamageReceiver,
  DamageRequest,
  DamageResult,
  NormalizedDamageRequest,
  RuntimeNodeId,
} from './DamageReceiver';
import { rejectedDamage } from './DamageReceiver';
import { damageSourceMatches, normalizeDamageRequest, resolveDamage } from './DamageResolver';

interface RegisteredArea {
  readonly receiver: DamageReceiver;
  readonly rule: DamageAreaRule;
}

export interface RoutedDamageOutcome {
  readonly receiverNodeId?: RuntimeNodeId;
  readonly selectedAreaNodeId?: RuntimeNodeId;
  readonly result: DamageResult;
}

interface CandidateGroup {
  readonly receiver: DamageReceiver;
  readonly candidates: Array<{ request: NormalizedDamageRequest; area: DamageAreaRule }>;
}

export class DamageRouter {
  private readonly areas = new Map<RuntimeNodeId, RegisteredArea>();

  constructor(
    private readonly activations: AttackActivation,
    private readonly simulationClock?: () => number,
  ) {}

  hasArea(areaNodeId: RuntimeNodeId): boolean {
    return this.areas.has(areaNodeId);
  }

  receiverNodeIdForArea(areaNodeId: RuntimeNodeId): RuntimeNodeId | undefined {
    return this.areas.get(areaNodeId)?.receiver.runtimeNodeId;
  }

  /** Every registered hurtbox area, for attacks that sweep the world instead of overlapping one area (the Stretch Lash). */
  areaNodeIds(): readonly RuntimeNodeId[] {
    return [...this.areas.keys()];
  }

  registerArea(receiver: DamageReceiver, rule: DamageAreaRule): void {
    const existing = this.areas.get(rule.areaNodeId);
    if (existing) {
      throw new Error(`Damage area '${rule.areaNodeId}' is already registered to '${existing.receiver.runtimeNodeId}'.`);
    }
    this.areas.set(rule.areaNodeId, { receiver, rule });
  }

  unregisterArea(receiver: DamageReceiver, areaNodeId: RuntimeNodeId): void {
    const existing = this.areas.get(areaNodeId);
    if (existing?.receiver === receiver) this.areas.delete(areaNodeId);
  }

  unregisterReceiver(receiver: DamageReceiver): void {
    for (const [areaNodeId, registered] of this.areas) {
      if (registered.receiver === receiver) this.areas.delete(areaNodeId);
    }
  }

  routeStep(requests: readonly DamageRequest[], simulationTime: number): readonly RoutedDamageOutcome[] {
    const resolvedSimulationTime = this.simulationClock?.() ?? simulationTime;
    const outcomes: RoutedDamageOutcome[] = [];
    const groups = new Map<RuntimeNodeId, CandidateGroup>();

    for (const request of requests) {
      const normalized = normalizeDamageRequest(request);
      if (!normalized) {
        outcomes.push({ result: rejectedDamage('invalid', false) });
        continue;
      }
      const activationFailure = this.activations.validate(normalized);
      if (activationFailure) {
        outcomes.push({ result: activationFailure });
        continue;
      }
      const registered = this.areas.get(normalized.targetAreaNodeId);
      if (!registered) {
        outcomes.push({ result: rejectedDamage('invalid', false) });
        continue;
      }
      const receiverNodeId = registered.receiver.runtimeNodeId;
      const groupKey = `${normalized.activationId}\u0000${receiverNodeId}`;
      const group = groups.get(groupKey) ?? { receiver: registered.receiver, candidates: [] };
      group.candidates.push({ request: normalized, area: registered.rule });
      groups.set(groupKey, group);
    }

    for (const groupKey of [...groups.keys()].sort()) {
      const group = groups.get(groupKey);
      if (!group) continue;
      const receiverNodeId = group.receiver.runtimeNodeId;
      const uniqueCandidates = [...new Map(group.candidates
        .map((candidate) => [candidate.area.areaNodeId, candidate] as const)).values()];
      const firstRequest = uniqueCandidates[0]?.request;
      if (!firstRequest) continue;
      const matching = uniqueCandidates.filter((candidate) => damageSourceMatches(candidate.area, candidate.request));
      const selected = matching.sort((left, right) => (
        right.area.priority - left.area.priority
        || left.area.areaNodeId.localeCompare(right.area.areaNodeId)
      ))[0];
      const signature = selected?.area.areaNodeId
        ?? areaSetSignature(uniqueCandidates.map((candidate) => candidate.area.areaNodeId));
      const cached = this.activations.beforeAttempt(firstRequest.activationId, receiverNodeId, signature);
      if (cached) {
        outcomes.push({ receiverNodeId, selectedAreaNodeId: selected?.area.areaNodeId, result: cached });
        continue;
      }

      const result = selected
        ? resolveDamage(group.receiver, selected.request, selected.area, resolvedSimulationTime)
        : rejectedDamage('source-blocked', false);
      this.activations.record(firstRequest.activationId, receiverNodeId, signature, result);
      if (result.status === 'accepted' && selected) {
        const commit = Object.freeze({
          request: selected.request,
          area: selected.area,
          result,
          simulationTime: resolvedSimulationTime,
        });
        group.receiver.commitDamage(commit);
        group.receiver.publishDamageFeedback?.(commit);
      }
      outcomes.push({ receiverNodeId, selectedAreaNodeId: selected?.area.areaNodeId, result });
    }

    return Object.freeze(outcomes);
  }
}
