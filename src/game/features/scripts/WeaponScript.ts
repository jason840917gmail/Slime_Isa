import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import { AnimationPlayerNode } from '../../runtime/scene/animation/AnimationPlayerNode';
import type { PhysicsContact } from '../../runtime/scene/physics/PhysicsContact';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import type { AttackActivation } from '../combat/AttackActivation';
import type { DamageRouter, RoutedDamageOutcome } from '../combat/DamageRouter';
import { ATTACK_ACTIVATION_SERVICE, DAMAGE_ROUTER_SERVICE } from './EnemyScript';

export type WeaponAttackDirection = 'right' | 'left' | 'up' | 'down';
export const PLAYER_WEAPON_COMBAT_SERVICE = 'combat.player-weapon';

export interface WeaponDamagePayload {
  readonly damage: number;
  readonly knockbackStrength: number;
  readonly cooldownMs: number;
  readonly weaponTags?: readonly string[];
  readonly damageTypes?: readonly string[];
}

export interface LegacyWeaponHitboxRequest {
  readonly weaponId: string;
  readonly hitboxId: string;
  readonly attackDirection: WeaponAttackDirection;
  readonly damage: number;
  readonly knockbackStrength: number;
}

export interface ManagedWeaponTarget {
  readonly areaNodeId: string;
  readonly receiverNodeId: string;
  readonly x: number;
  readonly y: number;
  readonly attackDirection: WeaponAttackDirection;
}

export interface PlayerWeaponCombatPort {
  onAttackStarted(weaponId: string, direction: WeaponAttackDirection): void;
  onAttackFinished(weaponId: string, direction: WeaponAttackDirection): void;
  activateLegacyHitbox(request: LegacyWeaponHitboxRequest): () => void;
  transformDamage(damage: number, target: ManagedWeaponTarget): number;
  onOutcome(outcome: RoutedDamageOutcome, target: ManagedWeaponTarget): void;
}

interface WeaponAttackSpan {
  readonly hitboxId: string;
  readonly from: number;
  readonly through: number;
  readonly damageMultiplier: number;
  readonly knockbackMultiplier: number;
}

interface WeaponAttackPlan {
  readonly animationId: string;
  readonly durationMs: number;
  readonly framesPerSecond: number;
  readonly hitboxSpans: readonly WeaponAttackSpan[];
}

interface ToggleNode extends Node {
  monitoring?: boolean;
  disabled?: boolean;
}

function isRecord(value: JsonValue | undefined): value is Readonly<Record<string, JsonValue>> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function scriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('WeaponScript requires a registered script identity.');
  return context.scriptId;
}

export class WeaponScript extends ScriptNode {
  readonly weaponId: string;
  readonly category: 'melee' | 'ranged';
  readonly baseDamage: number;
  readonly cooldownMs: number;
  readonly knockStrength: number;
  readonly onHitEffectId?: string;

  private readonly values: Readonly<Record<string, JsonValue>>;
  private simulationTimeMs = 0;
  private readyAtMs = 0;
  private activeDirection?: WeaponAttackDirection;
  private activePlan?: WeaponAttackPlan;
  private activeSinceMs = 0;
  private activeHitboxIds = new Set<string>();
  private damage?: WeaponDamagePayload;
  private activations?: AttackActivation;
  private damageRouter?: DamageRouter;
  private combat?: PlayerWeaponCombatPort;
  private activationId?: string;
  private readonly resolvedReceivers = new Set<string>();
  private readonly legacyHitboxes = new Map<string, () => void>();

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: scriptId(context), exportedProperties: context.properties });
    this.values = context.properties;
    this.weaponId = this.stringProperty('weaponId', 'unknown-weapon');
    this.category = this.stringProperty('category', 'melee') === 'ranged' ? 'ranged' : 'melee';
    this.baseDamage = Math.max(0, this.numberProperty('baseDamage', 0));
    this.cooldownMs = Math.max(0, this.numberProperty('cooldownMs', 0));
    this.knockStrength = Math.max(0, this.numberProperty('knockStrength', 0));
    const effectId = this.values.onHitEffectId;
    this.onHitEffectId = typeof effectId === 'string' && effectId.length > 0 ? effectId : undefined;
    this.registerSignalHandler<PhysicsContact>('on_area_entered', (contact) => this.onAreaEntered(contact));
  }

  get attacking(): boolean { return this.activePlan !== undefined; }
  get attackDirection(): WeaponAttackDirection | undefined { return this.activeDirection; }
  get nextReadyAt(): number { return this.readyAtMs; }

  canBeginAttack(timeMs = this.simulationTimeMs): boolean {
    return Number.isFinite(timeMs) && timeMs >= this.readyAtMs && !this.activePlan;
  }

  override _enter_tree(): void {
    this.setAttackAreaActive(false, new Set());
    this.set_physics_process(true);
  }

  override _physics_process(deltaSeconds: number): void {
    this.simulationTimeMs += deltaSeconds * 1000;
    const plan = this.activePlan;
    if (!plan || !this.activeDirection) return;
    const elapsedMs = this.simulationTimeMs - this.activeSinceMs;
    if (elapsedMs >= plan.durationMs) {
      this.finishAttack();
      return;
    }
    const frame = Math.floor((elapsedMs / 1000) * plan.framesPerSecond);
    const enabled = new Set(plan.hitboxSpans.filter((span) => frame >= span.from && frame <= span.through).map((span) => span.hitboxId));
    this.syncLegacyHitboxes(enabled);
    this.activeHitboxIds = enabled;
    this.setAttackAreaActive(enabled.size > 0, enabled);
  }

  override _exit_tree(): void {
    this.cancelAttack();
    this.set_physics_process(false);
  }

  tryBeginAttack(direction: WeaponAttackDirection, timeMs = this.simulationTimeMs, damage?: WeaponDamagePayload): boolean {
    if (!this.canBeginAttack(timeMs)) return false;
    return this.beginAttack(direction, timeMs, damage);
  }

  playAttack(direction: WeaponAttackDirection, timeMs = this.simulationTimeMs, damage?: WeaponDamagePayload): boolean {
    if (!Number.isFinite(timeMs)) return false;
    if (this.activePlan) this.finishAttack();
    return this.beginAttack(direction, timeMs, damage);
  }

  private beginAttack(direction: WeaponAttackDirection, timeMs: number, damage?: WeaponDamagePayload): boolean {
    const plan = this.attackPlan(direction);
    if (!plan) return false;
    this.simulationTimeMs = Math.max(this.simulationTimeMs, timeMs);
    this.activeDirection = direction;
    this.activePlan = plan;
    this.activeSinceMs = timeMs;
    this.readyAtMs = timeMs + (damage?.cooldownMs ?? this.cooldownMs);
    this.damage = damage;
    this.resolvedReceivers.clear();
    if (damage) this.beginDamageActivation();
    this.combat?.onAttackStarted(this.weaponId, direction);
    const animation = this.getReference<Node>('animation')?.configuredTarget;
    if (animation instanceof AnimationPlayerNode && animation.hasAnimation(plan.animationId)) animation.play(plan.animationId);
    this.getSignal<{ weaponId: string; direction: WeaponAttackDirection }>('attack_started')?.emit({ weaponId: this.weaponId, direction });
    return true;
  }

  cancelAttack(): void {
    if (!this.activePlan) return;
    this.finishAttack();
  }

  attackPlan(direction: WeaponAttackDirection): WeaponAttackPlan | undefined {
    const plans = this.values.attackPlans;
    if (!isRecord(plans) || !isRecord(plans[direction])) return undefined;
    const value = plans[direction];
    const animationId = value.animationId;
    const durationMs = value.durationMs;
    const framesPerSecond = value.framesPerSecond;
    const spans = value.hitboxSpans;
    if (typeof animationId !== 'string' || typeof durationMs !== 'number' || typeof framesPerSecond !== 'number' || !Array.isArray(spans)) return undefined;
    const hitboxSpans: WeaponAttackSpan[] = [];
    for (const span of spans) {
      if (!isRecord(span) || typeof span.hitboxId !== 'string' || typeof span.from !== 'number' || typeof span.through !== 'number') continue;
      hitboxSpans.push({
        hitboxId: span.hitboxId,
        from: span.from,
        through: span.through,
        damageMultiplier: typeof span.damageMultiplier === 'number' ? span.damageMultiplier : 1,
        knockbackMultiplier: typeof span.knockbackMultiplier === 'number' ? span.knockbackMultiplier : 1,
      });
    }
    return { animationId, durationMs, framesPerSecond, hitboxSpans };
  }

  private finishAttack(): void {
    const direction = this.activeDirection;
    const combat = this.combat;
    this.setAttackAreaActive(false, new Set());
    this.activeHitboxIds.clear();
    this.clearLegacyHitboxes();
    this.endDamageActivation();
    this.activeDirection = undefined;
    this.activePlan = undefined;
    const animation = this.getReference<Node>('animation')?.configuredTarget;
    if (animation instanceof AnimationPlayerNode && animation.hasAnimation('idle')) animation.play('idle');
    if (direction) combat?.onAttackFinished(this.weaponId, direction);
    if (direction) this.getSignal<{ weaponId: string; direction: WeaponAttackDirection }>('attack_finished')?.emit({ weaponId: this.weaponId, direction });
  }

  private beginDamageActivation(): void {
    const area = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!area) throw new Error(`WeaponScript '${this.runtimeId}' requires an attackArea reference.`);
    this.activations = this.service<AttackActivation>(ATTACK_ACTIVATION_SERVICE);
    this.damageRouter = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    this.combat = this.service<PlayerWeaponCombatPort>(PLAYER_WEAPON_COMBAT_SERVICE);
    this.activationId = this.activations.begin(this.runtimeId, [area.runtimeId]);
  }

  private onAreaEntered(contact: PhysicsContact): void {
    const damage = this.damage;
    const activationId = this.activationId;
    const router = this.damageRouter;
    const combat = this.combat;
    const direction = this.activeDirection;
    const attackArea = this.getReference<Node>('attackArea')?.configuredTarget;
    if (!damage || !activationId || !router || !combat || !direction || !attackArea || contact.otherKind !== 'area') return;
    const receiverNodeId = router.receiverNodeIdForArea(contact.otherId);
    if (!receiverNodeId || this.resolvedReceivers.has(receiverNodeId)) return;
    const span = this.contactSpan(contact);
    if (!span) return;
    const targetPosition = contact.other instanceof Node2D
      ? contact.other.get_global_transform().position
      : { x: 0, y: 0 };
    const target: ManagedWeaponTarget = {
      areaNodeId: contact.otherId,
      receiverNodeId,
      x: targetPosition.x,
      y: targetPosition.y,
      attackDirection: direction,
    };
    this.resolvedReceivers.add(receiverNodeId);
    const routedDamage = combat.transformDamage(damage.damage * span.damageMultiplier, target);
    const knock = attackVector(direction);
    const outcomes = router.routeStep([{
      activationId,
      sourceNodeId: this.runtimeId,
      attackAreaNodeId: attackArea.runtimeId,
      targetAreaNodeId: contact.otherId,
      weaponId: this.weaponId,
      weaponTags: damage.weaponTags ?? [this.weaponId.includes('spear') ? 'spear' : 'weapon'],
      damageTypes: damage.damageTypes ?? ['physical'],
      baseDamage: Math.max(0, routedDamage),
      effects: damage.knockbackStrength > 0
        ? [{ effectId: 'knockback', potency: damage.knockbackStrength * span.knockbackMultiplier }]
        : [],
      impact: { x: target.x, y: target.y, knockX: knock.x, knockY: knock.y },
    }], this.simulationTimeMs);
    const outcome = outcomes[0];
    if (outcome) combat.onOutcome(outcome, target);
  }

  private contactSpan(contact: PhysicsContact): WeaponAttackSpan | undefined {
    const plan = this.activePlan;
    if (!plan) return undefined;
    const tree = this.get_tree();
    for (const shape of contact.shapes) {
      const name = tree?.getNodeById(shape.observerShapeId)?.name;
      if (!name) continue;
      const separator = name.indexOf('--');
      const hitboxId = separator >= 0 ? name.slice(separator + 2) : name;
      const span = plan.hitboxSpans.find((candidate) => candidate.hitboxId === hitboxId && this.activeHitboxIds.has(hitboxId));
      if (span) return span;
    }
    return plan.hitboxSpans.find((span) => this.activeHitboxIds.has(span.hitboxId));
  }

  private endDamageActivation(): void {
    if (this.activationId) this.activations?.end(this.activationId);
    this.activationId = undefined;
    this.activations = undefined;
    this.damageRouter = undefined;
    this.combat = undefined;
    this.damage = undefined;
    this.resolvedReceivers.clear();
  }

  private syncLegacyHitboxes(enabled: ReadonlySet<string>): void {
    for (const [hitboxId, deactivate] of this.legacyHitboxes) {
      if (enabled.has(hitboxId)) continue;
      deactivate();
      this.legacyHitboxes.delete(hitboxId);
    }
    const plan = this.activePlan;
    const damage = this.damage;
    const combat = this.combat;
    const direction = this.activeDirection;
    if (!plan || !damage || !combat || !direction) return;
    for (const hitboxId of enabled) {
      if (this.legacyHitboxes.has(hitboxId)) continue;
      const span = plan.hitboxSpans.find((candidate) => candidate.hitboxId === hitboxId);
      if (!span) continue;
      this.legacyHitboxes.set(hitboxId, combat.activateLegacyHitbox({
        weaponId: this.weaponId,
        hitboxId,
        attackDirection: direction,
        damage: damage.damage * span.damageMultiplier,
        knockbackStrength: damage.knockbackStrength * span.knockbackMultiplier,
      }));
    }
  }

  private clearLegacyHitboxes(): void {
    for (const deactivate of this.legacyHitboxes.values()) deactivate();
    this.legacyHitboxes.clear();
  }

  private setAttackAreaActive(active: boolean, hitboxIds: ReadonlySet<string>): void {
    const area = this.getReference<Node>('attackArea')?.configuredTarget as ToggleNode | undefined;
    if (!area) return;
    if ('monitoring' in area) area.monitoring = active;
    for (const child of area.get_children() as readonly ToggleNode[]) {
      if (!('disabled' in child)) continue;
      const separator = child.name.indexOf('--');
      const direction = separator >= 0 ? child.name.slice(0, separator) : '';
      const hitboxId = separator >= 0 ? child.name.slice(separator + 2) : child.name;
      child.disabled = !active || direction !== this.activeDirection || !hitboxIds.has(hitboxId);
    }
  }

  private numberProperty(key: string, fallback: number): number {
    const value = this.values[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  private stringProperty(key: string, fallback: string): string {
    const value = this.values[key];
    return typeof value === 'string' ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): WeaponScript {
    return new WeaponScript({ runtimeId, name: this.name, type: 'ScriptNode', scriptId: this.scriptId, properties: this.exportedProperties, resources: new Map() });
  }
}

function attackVector(direction: WeaponAttackDirection): Readonly<{ x: number; y: number }> {
  if (direction === 'left') return { x: -1, y: 0 };
  if (direction === 'up') return { x: 0, y: -1 };
  if (direction === 'down') return { x: 0, y: 1 };
  return { x: 1, y: 0 };
}
