import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type {
  DamageAreaRule,
  DamageCommit,
  DamageMitigationInput,
  DamageReceiver,
  DamageStateDecision,
} from '../combat/DamageReceiver';
import type { DamageRouter } from '../combat/DamageRouter';
import {
  cancelEnemyAttack,
  finishEnemyAttack,
  tryBeginEnemyAttack,
  type EnemyAttackLifecycleState,
} from '../../enemies/enemyCombatLifecycle';
import { CharacterScript, type CharacterPoint } from './CharacterScript';

export const DAMAGE_ROUTER_SERVICE = 'combat.damage-router';

export type EnemyRank = 'ordinary' | 'elite' | 'boss';

export interface EnemyHealthChanged {
  readonly hp: number;
  readonly maxHp: number;
}

export interface EnemyRewardRequest {
  readonly receiverNodeId: string;
  readonly rewards: JsonValue;
}

interface DamageRuleConfiguration {
  readonly priority?: number;
  readonly damageMultiplier?: number;
  readonly acceptedSources?: DamageAreaRule['acceptedSources'];
  readonly blockedWeaponTags?: readonly string[];
  readonly damageTypeMultipliers?: Readonly<Record<string, number>>;
  readonly effectResponses?: DamageAreaRule['effectResponses'];
}

function isRecord(value: JsonValue | undefined): value is { readonly [key: string]: JsonValue } {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export class EnemyScript extends CharacterScript implements DamageReceiver {
  readonly faction: string;
  readonly rank: EnemyRank;
  readonly maxHealth: number;
  readonly targetingRadius: number;
  readonly attackRange: number;
  readonly movementSpeed: number;
  readonly attackCooldownMs: number;

  private hpValue: number;
  private defeatedValue = false;
  private rewardPublished = false;
  private attackState: EnemyAttackLifecycleState = { active: false, readyAt: 0, sequenceId: 0 };
  private readonly activeEffects = new Map<string, number>();
  private damageRouter?: DamageRouter;

  constructor(context: NodeConstructionContext) {
    super(context);
    this.faction = this.stringProperty('faction', 'hostile');
    this.rank = this.stringProperty('rank', 'ordinary') as EnemyRank;
    this.maxHealth = Math.max(1, this.numberProperty('maxHealth', 1));
    this.hpValue = this.maxHealth;
    this.targetingRadius = Math.max(0, this.numberProperty('targetingRadius', 0));
    this.attackRange = Math.max(0, this.numberProperty('attackRange', 0));
    this.movementSpeed = Math.max(0, this.numberProperty('movementSpeed', 0));
    this.attackCooldownMs = Math.max(0, this.numberProperty('attackCooldownMs', 0));
  }

  get hp(): number { return this.hpValue; }
  get defeated(): boolean { return this.defeatedValue; }
  get runtimeNodeId(): string { return this.runtimeId; }

  getDamageState() {
    return { hp: this.hpValue, maxHp: this.maxHealth, dead: this.defeatedValue };
  }

  canReceiveDamage(_input: DamageMitigationInput): DamageStateDecision {
    return this.defeatedValue
      ? { accepted: false as const, reason: 'dead' as const }
      : { accepted: true as const };
  }

  commitDamage(commit: DamageCommit): void {
    if (this.defeatedValue) return;
    this.hpValue = Math.max(0, this.hpValue - commit.result.actualDamage);
    for (const effect of commit.result.appliedEffects) this.activeEffects.set(effect.effectId, effect.potency);
    this.getSignal<EnemyHealthChanged>('health_changed')?.emit({ hp: this.hpValue, maxHp: this.maxHealth });
    this.getSignal<DamageCommit>('damaged')?.emit(commit);
    if (commit.result.defeated || this.hpValue <= 0) this.defeat();
  }

  publishDamageFeedback(commit: DamageCommit): void {
    this.getSignal<DamageCommit>('damage_feedback')?.emit(commit);
  }

  effectPotency(effectId: string): number | undefined {
    return this.activeEffects.get(effectId);
  }

  canTarget(origin: CharacterPoint, target: CharacterPoint, hostile: boolean): boolean {
    return hostile && this.distanceSquared(origin, target) <= this.targetingRadius * this.targetingRadius;
  }

  isInAttackRange(origin: CharacterPoint, target: CharacterPoint): boolean {
    return this.distanceSquared(origin, target) <= this.attackRange * this.attackRange;
  }

  tryBeginAttack(time: number): number | undefined {
    const result = tryBeginEnemyAttack(this.attackState, time, this.attackCooldownMs);
    this.attackState = result.state;
    return result.sequenceId;
  }

  finishAttack(sequenceId: number): void {
    this.attackState = finishEnemyAttack(this.attackState, sequenceId);
  }

  cancelAttack(): void {
    this.attackState = cancelEnemyAttack(this.attackState);
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.damageRouter = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    const target = this.getReference('damageArea')?.configuredTarget;
    if (!target) throw new Error(`EnemyScript '${this.runtimeId}' requires its damageArea reference.`);
    const damageRule = this.damageRule(target.runtimeId);
    this.damageRouter.registerArea(this, damageRule);
    this.entryDisposables.add(() => this.damageRouter?.unregisterArea(this, target.runtimeId));
  }

  protected damageRule(areaNodeId: string): DamageAreaRule {
    const value = this.jsonProperty('damageRule');
    const config = isRecord(value) ? value as unknown as DamageRuleConfiguration : {};
    return {
      areaNodeId,
      priority: config.priority ?? 0,
      damageMultiplier: config.damageMultiplier ?? 1,
      acceptedSources: config.acceptedSources,
      blockedWeaponTags: config.blockedWeaponTags,
      damageTypeMultipliers: config.damageTypeMultipliers,
      effectResponses: config.effectResponses,
    };
  }

  protected defeat(): void {
    if (this.defeatedValue) return;
    this.defeatedValue = true;
    this.hpValue = 0;
    this.cancelAttack();
    this.getSignal<EnemyHealthChanged>('health_changed')?.emit({ hp: 0, maxHp: this.maxHealth });
    this.getSignal<{ receiverNodeId: string }>('defeated')?.emit({ receiverNodeId: this.runtimeId });
    if (!this.rewardPublished) {
      this.rewardPublished = true;
      this.getSignal<EnemyRewardRequest>('reward_requested')?.emit({
        receiverNodeId: this.runtimeId,
        rewards: this.jsonProperty('rewards') ?? {},
      });
    }
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): EnemyScript {
    return new EnemyScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
