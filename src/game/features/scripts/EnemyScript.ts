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
import type { AttackActivation } from '../combat/AttackActivation';
import {
  cancelEnemyAttack,
  finishEnemyAttack,
  tryBeginEnemyAttack,
  type EnemyAttackLifecycleState,
} from '../../enemies/enemyCombatLifecycle';
import { CharacterScript, type CharacterPoint } from './CharacterScript';
import type { Node } from '../../runtime/scene/Node';
import type { Node2D } from '../../runtime/scene/Node2D';
import { AnimationPlayerNode } from '../../runtime/scene/animation/AnimationPlayerNode';

export const DAMAGE_ROUTER_SERVICE = 'combat.damage-router';
export const ATTACK_ACTIVATION_SERVICE = 'combat.attack-activation';
export const ENEMY_TARGET_SERVICE = 'world.enemy-target';

export interface EnemyTargetSnapshot {
  readonly position: CharacterPoint;
  readonly damageAreaNodeId: string;
  readonly active: boolean;
  readonly hostile: boolean;
}

export interface EnemyTargetService {
  getPrimaryTarget(sourceNodeId: string): EnemyTargetSnapshot | undefined;
}

export type EnemyRank = 'ordinary' | 'elite' | 'boss';
export type EnemyRuntimeState = 'idle' | 'chase' | 'attack' | 'dead';

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

interface VelocityNode extends Node2D {
  velocity: CharacterPoint;
}

interface ToggleNode extends Node {
  monitoring?: boolean;
  disabled?: boolean;
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
  private attackActivations?: AttackActivation;
  private targetService?: EnemyTargetService;
  private runtimeStateValue: EnemyRuntimeState = 'idle';
  private simulationTimeMs = 0;
  private activeActivationId?: string;
  private activeSequenceId?: number;
  private attackImpactAt = 0;
  private attackFinishAt = 0;
  private attackResolved = false;
  private attackDirection: CharacterPoint = { x: 0, y: 1 };

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
  get runtimeState(): EnemyRuntimeState { return this.runtimeStateValue; }
  get simulationTime(): number { return this.simulationTimeMs; }

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
    if (this.activeSequenceId === sequenceId) this.endRuntimeAttack();
  }

  cancelAttack(): void {
    this.attackState = cancelEnemyAttack(this.attackState);
    this.endRuntimeAttack();
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.damageRouter = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    this.attackActivations = this.service<AttackActivation>(ATTACK_ACTIVATION_SERVICE);
    this.targetService = this.service<EnemyTargetService>(ENEMY_TARGET_SERVICE);
    const target = this.getReference('damageArea')?.configuredTarget;
    if (!target) throw new Error(`EnemyScript '${this.runtimeId}' requires its damageArea reference.`);
    if (!this.getReference('attackArea')?.configuredTarget) throw new Error(`EnemyScript '${this.runtimeId}' requires its attackArea reference.`);
    const damageRule = this.damageRule(target.runtimeId);
    this.damageRouter.registerArea(this, damageRule);
    this.entryDisposables.add(() => this.damageRouter?.unregisterArea(this, target.runtimeId));
    this.set_physics_process(true);
  }

  override _physics_process(deltaSeconds: number): void {
    this.simulationTimeMs += deltaSeconds * 1000;
    const body = this.body();
    if (this.defeatedValue) {
      body.velocity = { x: 0, y: 0 };
      this.runtimeStateValue = 'dead';
      return;
    }

    const target = this.targetService?.getPrimaryTarget(this.runtimeId);
    if (!target?.active || !target.hostile) {
      this.cancelAttack();
      this.runtimeStateValue = 'idle';
      body.velocity = { x: 0, y: 0 };
      this.playDirectional('idle', this.attackDirection);
      return;
    }

    const origin = body.get_global_transform().position;
    const movement = this.movementToward(origin, target.position, 1);
    const direction = movement.speed > 0 ? { x: movement.x, y: movement.y } : this.attackDirection;
    const distance = Math.sqrt(this.distanceSquared(origin, target.position));

    if (this.activeSequenceId !== undefined) {
      body.velocity = { x: 0, y: 0 };
      if (!this.attackResolved && this.simulationTimeMs >= this.attackImpactAt) this.resolveRuntimeAttack(target, origin);
      if (this.simulationTimeMs >= this.attackFinishAt) {
        const sequenceId = this.activeSequenceId;
        this.finishAttack(sequenceId);
        this.runtimeStateValue = 'chase';
      }
      return;
    }

    if (distance > this.targetingRadius) {
      this.runtimeStateValue = 'idle';
      body.velocity = { x: 0, y: 0 };
      this.playDirectional('idle', direction);
      return;
    }
    if (distance <= this.attackRange) {
      this.runtimeStateValue = 'attack';
      body.velocity = { x: 0, y: 0 };
      this.beginRuntimeAttack(direction);
      return;
    }

    this.runtimeStateValue = 'chase';
    this.attackDirection = direction;
    body.velocity = { x: direction.x * this.movementSpeed, y: direction.y * this.movementSpeed };
    this.playDirectional('walk', direction);
  }

  override _exit_tree(): void {
    this.cancelAttack();
    this.set_physics_process(false);
    this.damageRouter = undefined;
    this.attackActivations = undefined;
    this.targetService = undefined;
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
    this.runtimeStateValue = 'dead';
    this.stopBody();
    this.setAttackAreaActive(false);
    this.playDirectional('die', this.attackDirection);
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

  private body(): VelocityNode {
    const body = this.getReference<Node>('body')?.configuredTarget;
    if (!body || !body.has_runtime_capability('character-body') || !('velocity' in body) || !('get_global_transform' in body)) {
      throw new Error(`EnemyScript '${this.runtimeId}' requires a CharacterBody2D body reference.`);
    }
    return body as VelocityNode;
  }

  private stopBody(): void {
    const body = this.getReference<Node>('body')?.configuredTarget;
    if (body && 'velocity' in body) (body as unknown as VelocityNode).velocity = { x: 0, y: 0 };
  }

  private beginRuntimeAttack(direction: CharacterPoint): void {
    const sequenceId = this.tryBeginAttack(this.simulationTimeMs);
    if (sequenceId === undefined) return;
    const attackArea = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!attackArea || !this.attackActivations) return;
    this.attackDirection = direction;
    this.activeSequenceId = sequenceId;
    this.activeActivationId = this.attackActivations.begin(this.runtimeId, [attackArea.runtimeId]);
    this.attackImpactAt = this.simulationTimeMs + this.attributeNumber('attackWindupMs', 0);
    this.attackFinishAt = this.attackImpactAt + this.attributeNumber('attackRecoveryMs', 0);
    this.attackResolved = false;
    this.setAttackAreaActive(true);
    this.playDirectional('attack', direction);
  }

  private resolveRuntimeAttack(target: EnemyTargetSnapshot, origin: CharacterPoint): void {
    this.attackResolved = true;
    const activationId = this.activeActivationId;
    const attackArea = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!activationId || !attackArea || !this.damageRouter) return;
    const targetDistance = Math.sqrt(this.distanceSquared(origin, target.position));
    if (!target.active || !target.hostile || targetDistance > this.attackRange * 1.35) return;
    this.damageRouter.routeStep([{
      activationId,
      sourceNodeId: this.runtimeId,
      attackAreaNodeId: attackArea.runtimeId,
      targetAreaNodeId: target.damageAreaNodeId,
      weaponId: 'enemy-contact',
      weaponTags: ['enemy', 'contact'],
      damageTypes: ['physical'],
      baseDamage: this.attributeNumber('contactDamage', 0),
      effects: [],
      impact: {
        x: origin.x,
        y: origin.y,
        knockX: this.attackDirection.x,
        knockY: this.attackDirection.y,
      },
    }], this.simulationTimeMs);
  }

  private endRuntimeAttack(): void {
    if (this.activeActivationId) this.attackActivations?.end(this.activeActivationId);
    this.activeActivationId = undefined;
    this.activeSequenceId = undefined;
    this.attackResolved = false;
    this.setAttackAreaActive(false);
  }

  private setAttackAreaActive(active: boolean): void {
    const area = this.getReference<Node>('attackArea')?.configuredTarget as ToggleNode | undefined;
    if (!area) return;
    if ('monitoring' in area) area.monitoring = active;
    for (const child of area.get_children() as readonly ToggleNode[]) {
      if ('disabled' in child) child.disabled = !active;
    }
  }

  private playDirectional(action: 'idle' | 'walk' | 'attack' | 'die', direction: CharacterPoint): void {
    const animation = this.getReference<Node>('animation')?.configuredTarget;
    if (!(animation instanceof AnimationPlayerNode)) return;
    const suffix = Math.abs(direction.y) > Math.abs(direction.x) ? (direction.y < 0 ? 'up' : 'down') : 'side';
    const clip = `${action}-${suffix}`;
    if (animation.currentAnimation !== clip && animation.hasAnimation(clip)) animation.play(clip);
  }

  private attributeNumber(key: string, fallback: number): number {
    const attributes = this.jsonProperty('attributes');
    if (!isRecord(attributes)) return fallback;
    const value = attributes[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
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
