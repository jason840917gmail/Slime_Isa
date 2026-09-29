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
import { runState, type EnemyAIConfig, type EnemySafeZone, type EnemyState } from '../../enemies/EnemyAI';
import type { MapEnemyAreaPerimeter, MapEnemySpawnArea } from '../../content/maps/mapFormat';
import { bossArenaCenter, bossPerimeterContains } from '../bosses/BossCampBehavior';
import { sensorShapeContainsPoint, sensorShapesIntersect, type SensorShape } from '../../runtime/scene/physics/SensorGeometry';

export const DAMAGE_ROUTER_SERVICE = 'combat.damage-router';
export const ATTACK_ACTIVATION_SERVICE = 'combat.attack-activation';
export const ENEMY_TARGET_SERVICE = 'world.enemy-target';

export interface EnemyTargetSnapshot {
  readonly position: CharacterPoint;
  readonly damageAreaNodeId: string;
  /** World-space hurtbox shapes; authored attack areas test against these (the position when absent). */
  readonly damageShapes?: readonly SensorShape[];
  readonly active: boolean;
  readonly hostile: boolean;
}

/** One authored attack area as the dev overlay draws it. */
export interface EnemyDebugAttackArea {
  readonly reference: string;
  readonly shapes: readonly SensorShape[];
  /** The primary target currently overlaps the area. */
  readonly overlapsTarget: boolean;
}

/** Area references the dev overlay draws when a script authors them. */
const DEBUG_ATTACK_AREA_REFERENCES = ['attackArea', 'contactAttack', 'landingZone'] as const;

export interface EnemyTargetService {
  getPrimaryTarget(sourceNodeId: string): EnemyTargetSnapshot | undefined;
}

export interface EnemyRuntimePort extends EnemyTargetService {
  getNavigation?(sourceNodeId: string): EnemyNavigationSnapshot | undefined;
  fireProjectile?(request: EnemyProjectileRequest): void;
  spawnImpactEffect?(request: { readonly effectId: string; readonly x: number; readonly y: number }): void;
  showDamageNumber?(request: EnemyDamageNumberRequest): void;
  /** Ground warning where an attack will land (world-space shapes plus a shadow point); replaces any previous one. */
  showTelegraph?(request: EnemyTelegraphRequest): void;
  clearTelegraph?(sourceNodeId: string): void;
  shakeCamera?(request: { readonly durationMs: number; readonly intensity: number }): void;
}

export interface EnemyTelegraphRequest {
  readonly sourceNodeId: string;
  readonly shapes: readonly SensorShape[];
  readonly shadow?: CharacterPoint;
}

export interface ImmediateAttackOptions {
  readonly baseDamage: number;
  /** Only targets within this distance are hit (omit when the caller already checked its area). */
  readonly range?: number;
  /** Overrides the script's contact knockback strength for this hit. */
  readonly knockbackStrength?: number;
  /** Plays the script's impactEffect on a successful hit (default true). */
  readonly impactEffect?: boolean;
}

export interface EnemyDamageNumberRequest {
  readonly sourceNodeId: string;
  readonly x: number;
  readonly y: number;
  readonly amount: number;
}

/** Knockback added to every accepted hit before resistance (legacy Enemy.applyDamage). */
export const ENEMY_HIT_KNOCKBACK_BASE = 120;
/** Hit-stun is BASE + min(MAX_BONUS, knockback * PER_STRENGTH) milliseconds. */
export const ENEMY_HIT_STUN_BASE_MS = 320;
export const ENEMY_HIT_STUN_MAX_BONUS_MS = 280;
export const ENEMY_HIT_STUN_PER_STRENGTH_MS = 0.35;
/** Knockback velocity retained per 60 Hz step while stunned. */
export const ENEMY_HIT_STUN_VELOCITY_DECAY = 0.94;
export const ENEMY_HIT_FLASH_MS = 120;
export const ENEMY_HIT_FLASH_COLOR = 0xff6f88;
/** Attack sequences outlive their clip by this margin and never exceed the cap. */
export const ENEMY_ATTACK_SEQUENCE_PADDING_MS = 250;
export const ENEMY_ATTACK_SEQUENCE_MAX_MS = 2000;
/** Melee impacts land only while the target is within this multiple of attackRange. */
export const ENEMY_MELEE_REACH_MULTIPLIER = 1.35;

type EnemyFacing = 'side' | 'up' | 'down';
type EnemyAnimationAction = 'idle' | 'walk' | 'attack' | 'knockback' | 'die';

interface FlippableVisual {
  flipX: boolean;
}

interface TintableVisual {
  setTintFill(color: number): unknown;
  clearTint(): unknown;
}

export interface EnemyNavigationSnapshot {
  readonly safeZones?: readonly EnemySafeZone[];
  readonly spawnArea?: MapEnemySpawnArea;
  /** Boss camp arena the boss must not pursue beyond. */
  readonly arena?: MapEnemyAreaPerimeter;
}

export interface EnemyProjectileRequest {
  readonly sourceNodeId: string;
  readonly position: CharacterPoint;
  readonly direction: CharacterPoint;
  readonly speed: number;
  readonly damage: number;
  readonly knockbackStrength: number;
  readonly projectileId?: string;
  readonly assetId?: string;
  /** Milliseconds a hit keeps the player stuck in place (spider webs). */
  readonly stickMs?: number;
}

export type EnemyRank = 'ordinary' | 'elite' | 'boss';
export type EnemyRuntimeState = EnemyState;

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
  readonly displayName: string;
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
  private targetService?: EnemyRuntimePort;
  private runtimeStateValue: EnemyRuntimeState = 'idle';
  private simulationTimeMs = 0;
  private activeActivationId?: string;
  private activeSequenceId?: number;
  private attackImpactAt = 0;
  private attackFinishAt = 0;
  private attackResolved = false;
  private attackDirection: CharacterPoint = { x: 0, y: 1 };
  private aiState: EnemyState = 'idle';
  private facing: EnemyFacing = 'down';
  private facingFlipped = false;
  private hitStunUntil = 0;
  private hitFlashUntil = 0;
  private returningToArenaValue = false;

  constructor(context: NodeConstructionContext) {
    super(context);
    this.displayName = this.stringProperty('displayName', '');
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
  get staggered(): boolean { return this.simulationTimeMs < this.hitStunUntil; }
  get attacking(): boolean { return this.activeSequenceId !== undefined; }
  get facingDirection(): EnemyFacing { return this.facing; }
  /** True while an arena-leashed enemy walks home because its target left the arena. */
  get returningToArena(): boolean { return this.returningToArenaValue; }
  get worldPosition(): CharacterPoint { return this.body().get_global_transform().position; }

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
    const defeated = commit.result.defeated || this.hpValue <= 0;
    this.reactToDamage(commit, defeated);
    if (defeated) this.defeat();
  }

  /**
   * Ordinary hit reaction: flash, damage number, cancel the current attack,
   * knock back by (potency + base) * (1 - knockbackResist) and stun for a
   * duration that grows with the applied knockback. Bosses override this.
   */
  protected reactToDamage(commit: DamageCommit, defeated: boolean): void {
    this.hitFlashUntil = this.simulationTimeMs + ENEMY_HIT_FLASH_MS;
    this.tintableVisual()?.setTintFill(ENEMY_HIT_FLASH_COLOR);
    const origin = this.body().get_global_transform().position;
    this.targetService?.showDamageNumber?.({ sourceNodeId: this.runtimeId, x: origin.x, y: origin.y, amount: commit.result.actualDamage });
    if (defeated) return;

    this.cancelAttack();
    const knockbackImmune = commit.result.rejectedEffects.some((effect) => effect.effectId === 'knockback' && effect.reason === 'immune');
    const potency = commit.result.appliedEffects
      .filter((effect) => effect.effectId === 'knockback')
      .reduce((total, effect) => total + effect.potency, 0);
    const resist = Math.min(1, Math.max(0, this.attributeNumber('knockbackResist', 0)));
    const strength = knockbackImmune ? 0 : (potency + ENEMY_HIT_KNOCKBACK_BASE) * (1 - resist);
    const length = Math.hypot(commit.request.impact.knockX, commit.request.impact.knockY);
    if (strength > 0 && length > 0) {
      this.body().velocity = {
        x: (commit.request.impact.knockX / length) * strength,
        y: (commit.request.impact.knockY / length) * strength,
      };
    }
    const stunMs = ENEMY_HIT_STUN_BASE_MS + Math.min(ENEMY_HIT_STUN_MAX_BONUS_MS, strength * ENEMY_HIT_STUN_PER_STRENGTH_MS);
    this.hitStunUntil = Math.max(this.hitStunUntil, this.simulationTimeMs + stunMs);
    this.playFacing('knockback', true);
    this.getSignal<{ durationMs: number; strength: number }>('hit_reaction')?.emit({ durationMs: stunMs, strength });
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
    const damageRouter = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    this.damageRouter = damageRouter;
    this.attackActivations = this.service<AttackActivation>(ATTACK_ACTIVATION_SERVICE);
    this.targetService = this.service<EnemyRuntimePort>(ENEMY_TARGET_SERVICE);
    const target = this.getReference('damageArea')?.configuredTarget;
    if (!target) throw new Error(`EnemyScript '${this.runtimeId}' requires its damageArea reference.`);
    if (!this.getReference('attackArea')?.configuredTarget) throw new Error(`EnemyScript '${this.runtimeId}' requires its attackArea reference.`);
    const damageRule = this.damageRule(target.runtimeId);
    damageRouter.registerArea(this, damageRule);
    this.entryDisposables.add(() => damageRouter.unregisterArea(this, target.runtimeId));
    this.set_physics_process(true);
  }

  override _physics_process(deltaSeconds: number): void {
    this.simulationTimeMs += deltaSeconds * 1000;
    this.updateHitFlash();
    const body = this.body();
    if (this.defeatedValue) {
      body.velocity = { x: 0, y: 0 };
      this.runtimeStateValue = 'dead';
      return;
    }

    if (this.simulationTimeMs < this.hitStunUntil) {
      const decay = Math.pow(ENEMY_HIT_STUN_VELOCITY_DECAY, deltaSeconds * 60);
      body.velocity = { x: body.velocity.x * decay, y: body.velocity.y * decay };
      return;
    }

    const target = this.currentTarget();
    if (!target?.active || !target.hostile) {
      this.cancelAttack();
      this.aiState = 'idle';
      this.runtimeStateValue = 'idle';
      body.velocity = { x: 0, y: 0 };
      this.playFacing('idle');
      return;
    }

    const origin = body.get_global_transform().position;
    const navigation = this.navigation();
    // Arena leash (boss camps): outside the arena the enemy drops the fight and walks home.
    if (navigation?.arena && !bossPerimeterContains(navigation.arena, target.position.x, target.position.y)) {
      this.cancelAttack();
      this.returningToArenaValue = true;
      this.aiState = 'idle';
      this.runtimeStateValue = 'idle';
      const velocity = this.velocityTowardArenaCenter(navigation.arena, origin, deltaSeconds);
      body.velocity = velocity;
      this.updateFacing(velocity);
      this.playFacing(Math.hypot(velocity.x, velocity.y) > 2 ? 'walk' : 'idle');
      return;
    }
    this.returningToArenaValue = false;
    const movement = this.movementToward(origin, target.position, 1);
    const direction = movement.speed > 0 ? { x: movement.x, y: movement.y } : this.attackDirection;
    const distance = Math.sqrt(this.distanceSquared(origin, target.position));

    if (this.activeSequenceId !== undefined) {
      if (!this.attackResolved && this.simulationTimeMs >= this.attackImpactAt) this.resolveRuntimeAttack(target, origin);
      if (this.activeSequenceId !== undefined && this.simulationTimeMs >= this.attackFinishAt) {
        this.finishAttack(this.activeSequenceId);
        const fleeRange = this.attributeOptionalNumber('fleeRange');
        this.aiState = fleeRange !== undefined && fleeRange > 0 && distance < fleeRange ? 'flee' : 'chase';
      }
    }

    // The AI keeps running during an attack exactly as the legacy enemy did:
    // the attack state holds position, and a target that escapes beyond the
    // attack range is chased while the committed swing plays out.
    const velocity = { x: body.velocity.x, y: body.velocity.y };
    const velocityPort = {
      setVelocity: (x: number, y: number) => { velocity.x = x; velocity.y = y; },
      velocity: { scale: (amount: number) => { velocity.x *= amount; velocity.y *= amount; } },
    };
    const directionPort = { ...direction, clone: () => ({ ...directionPort }) };
    let state = this.aiState;
    for (let transitions = 0; transitions < 3; transitions += 1) {
      const before = { ...velocity };
      const result = runState(state, {
        enemy: { x: origin.x, y: origin.y, body: velocityPort },
        player: target.position,
        time: this.simulationTimeMs,
        delta: deltaSeconds * 1000,
        distToPlayer: distance,
        inAttackReach: this.attackAreaReach(target),
        dirToPlayer: directionPort,
        config: this.aiConfig(),
        requestAttack: (attackDirection) => {
          if (this.canRunCommonAttack()) this.beginRuntimeAttack(attackDirection);
        },
        safeZones: navigation?.safeZones ? [...navigation.safeZones] : undefined,
        spawnArea: navigation?.spawnArea,
      });
      if (result === 'continue') break;
      state = result;
      const startedMoving = velocity.x !== 0 || velocity.y !== 0;
      const velocityChanged = velocity.x !== before.x || velocity.y !== before.y;
      if (startedMoving && velocityChanged) break;
    }
    // Presentation hook (alert chirp/hiss): idle or wandering enemies that start pursuing or fleeing.
    if ((this.aiState === 'idle' || this.aiState === 'wander') && (state === 'chase' || state === 'flee')) {
      this.getSignal<{ state: string }>('alerted')?.emit({ state });
    }
    this.aiState = state;
    this.runtimeStateValue = this.activeSequenceId === undefined ? state : 'attack';
    body.velocity = velocity;
    if (this.activeSequenceId !== undefined) return;
    this.updateFacing(velocity);
    this.playFacing(Math.hypot(velocity.x, velocity.y) > 2 ? 'walk' : 'idle');
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
    this.playFacing('die', true);
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

  protected body(): VelocityNode {
    const body = this.getReference<Node>('body')?.configuredTarget;
    if (!body || !body.has_runtime_capability('character-body') || !('velocity' in body) || !('get_global_transform' in body)) {
      throw new Error(`EnemyScript '${this.runtimeId}' requires a CharacterBody2D body reference.`);
    }
    return body as VelocityNode;
  }

  protected currentTarget(): EnemyTargetSnapshot | undefined {
    return this.targetService?.getPrimaryTarget(this.runtimeId);
  }

  protected navigation(): EnemyNavigationSnapshot | undefined {
    return this.targetService?.getNavigation?.(this.runtimeId);
  }

  /** The arena this enemy is leashed to, when a boss camp spawned it. */
  protected arena(): MapEnemyAreaPerimeter | undefined {
    return this.navigation()?.arena;
  }

  /** Walks toward the arena centre at movement speed, snapping onto it on the last step. */
  private velocityTowardArenaCenter(arena: MapEnemyAreaPerimeter, origin: CharacterPoint, deltaSeconds: number): CharacterPoint {
    const center = bossArenaCenter(arena);
    const dx = center.x - origin.x;
    const dy = center.y - origin.y;
    const remaining = Math.hypot(dx, dy);
    if (remaining <= Math.max(1, this.movementSpeed * Math.max(0, deltaSeconds))) {
      const body = this.body();
      body.set_global_transform({ ...body.get_global_transform(), position: { x: center.x, y: center.y } });
      return { x: 0, y: 0 };
    }
    return { x: (dx / remaining) * this.movementSpeed, y: (dy / remaining) * this.movementSpeed };
  }

  protected canRunCommonAttack(): boolean { return true; }

  /**
   * Authored-area reach for the common attack (trigger and impact). Undefined
   * keeps the `attackRange` distance rule; scripts whose attack is an authored
   * area return `targetOverlapsArea(...)` so the drawn shape is the truth.
   */
  protected attackAreaReach(_target: EnemyTargetSnapshot): boolean | undefined { return undefined; }

  /**
   * World-space shapes of every CollisionShape2D under an Area2D reference.
   * Disabled shapes count: `disabled` only gates physics monitoring while idle,
   * the authored geometry is still the attack's reach.
   */
  protected referencedAreaShapes(reference: string): readonly SensorShape[] {
    const area = this.getReference<Node>(reference)?.configuredTarget;
    return (area?.get_children() ?? []).flatMap((child) => {
      const shape = child as unknown as { worldShape?: () => SensorShape };
      return typeof shape.worldShape === 'function' ? [shape.worldShape()] : [];
    });
  }

  /** Whether the target's hurtbox (its position when it exposes none) overlaps any of the shapes. */
  protected targetOverlapsShapes(shapes: readonly SensorShape[], target: EnemyTargetSnapshot): boolean {
    const hurtbox = target.damageShapes;
    if (hurtbox && hurtbox.length > 0) return shapes.some((shape) => hurtbox.some((other) => sensorShapesIntersect(shape, other)));
    return shapes.some((shape) => sensorShapeContainsPoint(shape, target.position.x, target.position.y));
  }

  protected targetOverlapsArea(reference: string, target: EnemyTargetSnapshot): boolean {
    return this.targetOverlapsShapes(this.referencedAreaShapes(reference), target);
  }

  /** Authored attack areas with their live overlap state, for the dev overlay. */
  debugAttackAreas(): readonly EnemyDebugAttackArea[] {
    if (this.defeatedValue) return [];
    const target = this.currentTarget();
    const seen = new Set<string>();
    const areas: EnemyDebugAttackArea[] = [];
    for (const reference of DEBUG_ATTACK_AREA_REFERENCES) {
      const node = this.getReference<Node>(reference)?.configuredTarget;
      if (!node || seen.has(node.runtimeId)) continue;
      seen.add(node.runtimeId);
      const shapes = this.referencedAreaShapes(reference);
      if (shapes.length === 0) continue;
      areas.push({ reference, shapes, overlapsTarget: target?.active === true && this.targetOverlapsShapes(shapes, target) });
    }
    return areas;
  }

  /** Directional enemies mirror their side clips when facing left. */
  protected mirrorsSideFacing(): boolean { return true; }

  protected playAnimation(name: string, restart = false): void {
    const animation = this.animationPlayer();
    if (animation && (restart || animation.currentAnimation !== name) && animation.hasAnimation(name)) animation.play(name);
  }

  protected animationPlayer(): AnimationPlayerNode | undefined {
    const animation = this.getReference<Node>('animation')?.configuredTarget;
    return animation instanceof AnimationPlayerNode ? animation : undefined;
  }

  protected routeImmediateAttack(target: EnemyTargetSnapshot, options: ImmediateAttackOptions): boolean {
    const attackArea = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!attackArea || !this.attackActivations || !this.damageRouter) return false;
    const origin = this.body().get_global_transform().position;
    const movement = this.movementToward(origin, target.position, 1);
    if (!target.active || !target.hostile) return false;
    if (options.range !== undefined && Math.sqrt(this.distanceSquared(origin, target.position)) > options.range) return false;
    const activationId = this.attackActivations.begin(this.runtimeId, [attackArea.runtimeId]);
    const outcomes = this.damageRouter.routeStep([{
      activationId,
      sourceNodeId: this.runtimeId,
      attackAreaNodeId: attackArea.runtimeId,
      targetAreaNodeId: target.damageAreaNodeId,
      weaponId: 'enemy-contact',
      weaponTags: ['enemy', 'contact'],
      damageTypes: ['physical'],
      baseDamage: options.baseDamage,
      effects: this.knockbackEffects(options.knockbackStrength),
      impact: { x: origin.x, y: origin.y, knockX: movement.x, knockY: movement.y },
    }], this.simulationTimeMs);
    const hit = outcomes.some((outcome) => outcome.result.status === 'accepted' && outcome.result.actualDamage > 0);
    if (hit && options.impactEffect !== false) this.spawnImpactEffect(origin);
    this.attackActivations.end(activationId);
    return hit;
  }

  /** Plays an effect scene (`effect.<id>`) at a world point. */
  protected spawnEffectAt(effectId: string, point: CharacterPoint): void {
    if (effectId) this.targetService?.spawnImpactEffect?.({ effectId, x: point.x, y: point.y });
  }

  protected showTelegraph(shapes: readonly SensorShape[], shadow?: CharacterPoint): void {
    this.targetService?.showTelegraph?.({ sourceNodeId: this.runtimeId, shapes, ...(shadow ? { shadow } : {}) });
  }

  protected clearTelegraph(): void {
    this.targetService?.clearTelegraph?.(this.runtimeId);
  }

  protected shakeCamera(durationMs: number, intensity: number): void {
    if (durationMs > 0 && intensity > 0) this.targetService?.shakeCamera?.({ durationMs, intensity });
  }

  private stopBody(): void {
    const body = this.getReference<Node>('body')?.configuredTarget;
    if (body && 'velocity' in body) (body as unknown as VelocityNode).velocity = { x: 0, y: 0 };
    if (body && 'collisionEnabled' in body) (body as unknown as { collisionEnabled: boolean }).collisionEnabled = false;
  }

  private beginRuntimeAttack(direction: CharacterPoint): void {
    const sequenceId = this.tryBeginAttack(this.simulationTimeMs);
    if (sequenceId === undefined) return;
    const attackArea = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!attackArea || !this.attackActivations) return;
    const length = Math.hypot(direction.x, direction.y);
    this.attackDirection = length > 0 ? { x: direction.x / length, y: direction.y / length } : this.attackDirection;
    this.activeSequenceId = sequenceId;
    this.activeActivationId = this.attackActivations.begin(this.runtimeId, [attackArea.runtimeId]);
    const windupMs = Math.max(0, this.attributeNumber('attackWindupMs', 0));
    const recoveryMs = Math.max(0, this.attributeNumber('attackRecoveryMs', 0));
    this.updateFacing(this.attackDirection);
    const clipMs = this.animationPlayer()?.animationLengthMs(this.facingAnimation('attack')) ?? 0;
    this.attackImpactAt = this.simulationTimeMs + windupMs;
    this.attackFinishAt = this.simulationTimeMs + Math.min(
      ENEMY_ATTACK_SEQUENCE_MAX_MS,
      Math.max(windupMs + recoveryMs, clipMs) + ENEMY_ATTACK_SEQUENCE_PADDING_MS,
    );
    this.attackResolved = false;
    this.setAttackAreaActive(true);
    this.playFacing('attack', true);
    this.getSignal<{ ranged: boolean; windupMs: number }>('attack_started')?.emit({ ranged: this.projectileConfiguration() !== undefined, windupMs });
  }

  private resolveRuntimeAttack(target: EnemyTargetSnapshot, origin: CharacterPoint): void {
    this.attackResolved = true;
    const activationId = this.activeActivationId;
    const attackArea = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!activationId || !attackArea || !this.damageRouter) return;
    if (!target.active || !target.hostile) return;
    const projectile = this.projectileConfiguration();
    if (projectile) {
      // Ranged attacks commit at windup start: the projectile always leaves in
      // the aimed direction and its own flight decides whether it connects.
      this.targetService?.fireProjectile?.({
        sourceNodeId: this.runtimeId,
        position: origin,
        direction: this.attackDirection,
        speed: this.attributeNumber('projectileSpeed', 200),
        damage: projectile.damage,
        knockbackStrength: this.attributeNumber('knockbackStrength', 0),
        ...(projectile.projectileId ? { projectileId: projectile.projectileId } : {}),
        ...(projectile.assetId ? { assetId: projectile.assetId } : {}),
        ...(projectile.stickMs ? { stickMs: projectile.stickMs } : {}),
      });
      return;
    }
    const reach = this.attackAreaReach(target);
    const targetDistance = Math.sqrt(this.distanceSquared(origin, target.position));
    if (reach === false || (reach === undefined && targetDistance > this.attackRange * ENEMY_MELEE_REACH_MULTIPLIER)) return;
    const knock = this.movementToward(origin, target.position, 1);
    const outcomes = this.damageRouter.routeStep([{
      activationId,
      sourceNodeId: this.runtimeId,
      attackAreaNodeId: attackArea.runtimeId,
      targetAreaNodeId: target.damageAreaNodeId,
      weaponId: 'enemy-contact',
      weaponTags: ['enemy', 'contact'],
      damageTypes: ['physical'],
      baseDamage: this.attributeNumber('contactDamage', 0),
      effects: this.knockbackEffects(),
      impact: {
        x: origin.x,
        y: origin.y,
        knockX: knock.speed > 0 ? knock.x : this.attackDirection.x,
        knockY: knock.speed > 0 ? knock.y : this.attackDirection.y,
      },
    }], this.simulationTimeMs);
    if (outcomes.some((outcome) => outcome.result.status === 'accepted' && outcome.result.actualDamage > 0)) {
      this.spawnImpactEffect(origin);
    }
  }

  private spawnImpactEffect(origin: CharacterPoint): void {
    const value = this.jsonProperty('impactEffect');
    if (!isRecord(value) || typeof value.effectId !== 'string') return;
    const distance = typeof value.distance === 'number' && Number.isFinite(value.distance) ? value.distance : 0;
    this.targetService?.spawnImpactEffect?.({
      effectId: value.effectId,
      x: origin.x + this.attackDirection.x * distance,
      y: origin.y + this.attackDirection.y * distance,
    });
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

  /** Legacy facing rule: horizontal-dominant vectors use the side clip, mirrored when moving left. */
  private updateFacing(vector: CharacterPoint): void {
    if (Math.hypot(vector.x, vector.y) < 1e-6) return;
    if (Math.abs(vector.x) > Math.abs(vector.y)) {
      this.facing = 'side';
      this.facingFlipped = vector.x < 0;
    } else {
      this.facing = vector.y < 0 ? 'up' : 'down';
      this.facingFlipped = false;
    }
    const visual = this.mirrorsSideFacing() ? this.flippableVisual() : undefined;
    if (visual && visual.flipX !== this.facingFlipped) visual.flipX = this.facingFlipped;
  }

  private facingAnimation(action: EnemyAnimationAction): string {
    return `${action}-${this.facing}`;
  }

  private playFacing(action: EnemyAnimationAction, restart = false): void {
    this.playAnimation(this.facingAnimation(action), restart);
  }

  private visualNode(): Node | undefined {
    return this.getReference<Node>('visual')?.configuredTarget;
  }

  private flippableVisual(): FlippableVisual | undefined {
    const visual = this.visualNode();
    return visual && 'flipX' in visual ? visual as unknown as FlippableVisual : undefined;
  }

  private tintableVisual(): TintableVisual | undefined {
    const visual = this.visualNode() as (Node & Partial<TintableVisual>) | undefined;
    return visual && typeof visual.setTintFill === 'function' && typeof visual.clearTint === 'function'
      ? visual as unknown as TintableVisual
      : undefined;
  }

  private updateHitFlash(): void {
    if (this.hitFlashUntil <= 0 || this.simulationTimeMs < this.hitFlashUntil) return;
    this.hitFlashUntil = 0;
    this.tintableVisual()?.clearTint();
  }

  private attributeNumber(key: string, fallback: number): number {
    const attributes = this.jsonProperty('attributes');
    if (!isRecord(attributes)) return fallback;
    const value = attributes[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  private knockbackEffects(strength?: number): readonly { readonly effectId: string; readonly potency: number }[] {
    const potency = strength ?? this.attributeNumber('knockbackStrength', 0);
    return potency > 0 ? [{ effectId: 'knockback', potency }] : [];
  }

  private aiConfig(): EnemyAIConfig {
    return {
      behavior: this.attributeString('behavior') === 'slime-spider' ? 'slime-spider' : undefined,
      aggroRange: this.targetingRadius,
      attackRange: this.attackRange,
      fleeRange: this.attributeOptionalNumber('fleeRange'),
      wanderSpeed: this.attributeNumber('wanderSpeed', 0),
      chaseSpeed: this.movementSpeed,
      attackCooldownMs: this.attackCooldownMs,
      attackWindupMs: this.attributeNumber('attackWindupMs', 0),
      attackRecoveryMs: this.attributeNumber('attackRecoveryMs', 0),
      contactDamage: this.attributeNumber('contactDamage', 0),
      knockbackStrength: this.attributeNumber('knockbackStrength', 0),
      isRanged: this.attributeBoolean('isRanged') || this.projectileConfiguration() !== undefined,
      projectileSpeed: this.attributeOptionalNumber('projectileSpeed'),
      knockbackResist: this.attributeNumber('knockbackResist', 0),
    };
  }

  private projectileConfiguration(): { readonly projectileId?: string; readonly assetId?: string; readonly damage: number; readonly stickMs?: number } | undefined {
    const value = this.jsonProperty('projectile');
    if (!isRecord(value) || typeof value.damage !== 'number') return undefined;
    const projectileId = typeof value.projectileId === 'string' ? value.projectileId : undefined;
    const assetId = typeof value.assetId === 'string' ? value.assetId : undefined;
    if (!projectileId && !assetId) return undefined;
    const stickMs = typeof value.stickMs === 'number' && value.stickMs > 0 ? value.stickMs : undefined;
    return { ...(projectileId ? { projectileId } : {}), ...(assetId ? { assetId } : {}), damage: value.damage, ...(stickMs ? { stickMs } : {}) };
  }

  private attributeOptionalNumber(key: string): number | undefined {
    const value = this.attributeValue(key);
    return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
  }

  private attributeString(key: string): string | undefined {
    const value = this.attributeValue(key);
    return typeof value === 'string' ? value : undefined;
  }

  private attributeBoolean(key: string): boolean {
    return this.attributeValue(key) === true;
  }

  private attributeValue(key: string): JsonValue | undefined {
    const attributes = this.jsonProperty('attributes');
    return isRecord(attributes) ? attributes[key] : undefined;
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
