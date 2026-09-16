import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { Node } from '../../runtime/scene/Node';
import { AnimationPlayerNode } from '../../runtime/scene/animation/AnimationPlayerNode';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export type WeaponAttackDirection = 'right' | 'left' | 'up' | 'down';

interface WeaponAttackSpan {
  readonly hitboxId: string;
  readonly from: number;
  readonly through: number;
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
  }

  get attacking(): boolean { return this.activePlan !== undefined; }
  get attackDirection(): WeaponAttackDirection | undefined { return this.activeDirection; }
  get nextReadyAt(): number { return this.readyAtMs; }

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
    this.setAttackAreaActive(enabled.size > 0, enabled);
  }

  override _exit_tree(): void {
    this.cancelAttack();
    this.set_physics_process(false);
  }

  tryBeginAttack(direction: WeaponAttackDirection, timeMs = this.simulationTimeMs): boolean {
    if (!Number.isFinite(timeMs) || timeMs < this.readyAtMs || this.activePlan) return false;
    const plan = this.attackPlan(direction);
    if (!plan) return false;
    this.simulationTimeMs = Math.max(this.simulationTimeMs, timeMs);
    this.activeDirection = direction;
    this.activePlan = plan;
    this.activeSinceMs = timeMs;
    this.readyAtMs = timeMs + this.cooldownMs;
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
      hitboxSpans.push({ hitboxId: span.hitboxId, from: span.from, through: span.through });
    }
    return { animationId, durationMs, framesPerSecond, hitboxSpans };
  }

  private finishAttack(): void {
    const direction = this.activeDirection;
    this.setAttackAreaActive(false, new Set());
    this.activeDirection = undefined;
    this.activePlan = undefined;
    if (direction) this.getSignal<{ weaponId: string; direction: WeaponAttackDirection }>('attack_finished')?.emit({ weaponId: this.weaponId, direction });
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
