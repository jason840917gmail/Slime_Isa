export type RuntimeNodeId = string;

export interface DamageEffectRequest {
  readonly effectId: string;
  readonly potency: number;
}

export interface DamageImpact {
  readonly x: number;
  readonly y: number;
  readonly knockX: number;
  readonly knockY: number;
}

export interface DamageRequest {
  readonly activationId: string;
  readonly sourceNodeId: RuntimeNodeId;
  readonly attackAreaNodeId: RuntimeNodeId;
  readonly targetAreaNodeId: RuntimeNodeId;
  readonly weaponId?: string;
  readonly weaponTags: readonly string[];
  readonly damageTypes: readonly string[];
  readonly baseDamage: number;
  readonly trueDamage?: boolean;
  readonly effects: readonly DamageEffectRequest[];
  readonly impact: Readonly<DamageImpact>;
}

export interface NormalizedDamageRequest extends Omit<DamageRequest, 'trueDamage'> {
  readonly trueDamage: boolean;
}

export interface AttackSourceMatcher {
  readonly weaponIds?: readonly string[];
  readonly allWeaponTags?: readonly string[];
  readonly anyDamageTypes?: readonly string[];
}

export type EffectResponse =
  | { readonly mode: 'immune' }
  | { readonly mode: 'multiplier'; readonly multiplier: number };

export interface DamageAreaRule {
  readonly areaNodeId: RuntimeNodeId;
  readonly priority: number;
  readonly damageMultiplier: number;
  readonly acceptedSources?: readonly AttackSourceMatcher[];
  readonly blockedWeaponTags?: readonly string[];
  readonly damageTypeMultipliers?: Readonly<Record<string, number>>;
  readonly effectResponses?: Readonly<Record<string, EffectResponse>>;
}

export interface DamageReceiverState {
  readonly hp: number;
  readonly maxHp: number;
  readonly dead: boolean;
}

export interface DamageMitigationInput {
  readonly scaledDamage: number;
  readonly request: NormalizedDamageRequest;
  readonly area: DamageAreaRule;
  readonly state: DamageReceiverState;
  readonly simulationTime: number;
}

export type DamageMitigationPolicy = (input: DamageMitigationInput) => number;

export interface DamageStateDecision {
  readonly accepted: boolean;
  readonly reason?: 'state-blocked' | 'dead';
}

export interface AppliedDamageEffect {
  readonly effectId: string;
  readonly potency: number;
}

export interface RejectedDamageEffect {
  readonly effectId: string;
  readonly reason: 'immune' | 'zero-potency';
}

export interface AcceptedDamageResult {
  readonly status: 'accepted';
  readonly actualDamage: number;
  readonly defeated: boolean;
  readonly appliedEffects: readonly AppliedDamageEffect[];
  readonly rejectedEffects: readonly RejectedDamageEffect[];
}

export type DamageRejectionReason =
  | 'invalid'
  | 'inactive-attack'
  | 'duplicate'
  | 'source-blocked'
  | 'state-blocked'
  | 'immune'
  | 'dead';

export interface RejectedDamageResult {
  readonly status: 'rejected';
  readonly actualDamage: 0;
  readonly reason: DamageRejectionReason;
  readonly retryable: boolean;
}

export type DamageResult = AcceptedDamageResult | RejectedDamageResult;

export interface DamageCommit {
  readonly request: NormalizedDamageRequest;
  readonly area: DamageAreaRule;
  readonly result: AcceptedDamageResult;
  readonly simulationTime: number;
}

export interface DamageReceiver {
  readonly runtimeNodeId: RuntimeNodeId;
  getDamageState(): DamageReceiverState;
  canReceiveDamage?(input: DamageMitigationInput): DamageStateDecision;
  mitigateDamage?: DamageMitigationPolicy;
  commitDamage(commit: DamageCommit): void;
  publishDamageFeedback?(commit: DamageCommit): void;
}

export function rejectedDamage(
  reason: DamageRejectionReason,
  retryable = reason === 'state-blocked',
): RejectedDamageResult {
  return Object.freeze({ status: 'rejected', actualDamage: 0, reason, retryable });
}

