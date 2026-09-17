import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import type {
  DamageAreaRule,
  DamageCommit,
  DamageMitigationInput,
  DamageReceiver,
  DamageStateDecision,
} from '../combat/DamageReceiver';
import type { DamageRouter } from '../combat/DamageRouter';
import { DAMAGE_ROUTER_SERVICE } from './EnemyScript';

export const WORLD_OBJECT_STATE_SERVICE = 'world.object-state';

export interface DestructibleState {
  readonly health: number;
  readonly destroyed: boolean;
}

export interface WorldObjectStatePort {
  load(mapId: string, instanceId: string): DestructibleState | undefined;
  saveHealth(mapId: string, instanceId: string, health: number, maxHealth: number): void;
  markDestroyed(mapId: string, instanceId: string): void;
}

export interface DestructibleHealthChanged {
  readonly mapId: string;
  readonly instanceId: string;
  readonly health: number;
  readonly maxHealth: number;
}

export interface DestructibleDestroyed {
  readonly mapId: string;
  readonly instanceId: string;
  readonly objectId: string;
}

interface DamageRuleConfiguration {
  readonly priority?: number;
  readonly damageMultiplier?: number;
  readonly acceptedSources?: DamageAreaRule['acceptedSources'];
  readonly blockedWeaponTags?: readonly string[];
  readonly damageTypeMultipliers?: Readonly<Record<string, number>>;
  readonly effectResponses?: DamageAreaRule['effectResponses'];
}

function isRecord(value: JsonValue | undefined): value is Readonly<Record<string, JsonValue>> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('DestructibleScript requires a registered script identity.');
  return context.scriptId;
}

export class DestructibleScript extends ScriptNode implements DamageReceiver {
  readonly mapId: string;
  readonly instanceId: string;
  readonly objectId: string;
  readonly maxHealth: number;
  readonly tags: readonly string[];

  protected healthValue: number;
  protected destroyedValue = false;
  private state?: WorldObjectStatePort;

  constructor(context: NodeConstructionContext) {
    super({
      runtimeId: context.runtimeId,
      name: context.name,
      scriptId: requiredScriptId(context),
      exportedProperties: context.properties,
    });
    this.mapId = this.stringProperty('mapId', '');
    this.instanceId = this.stringProperty('instanceId', '');
    this.objectId = this.stringProperty('objectId', '');
    this.maxHealth = Math.max(1, this.numberProperty('maxHealth', 1));
    const initialHealth = this.numberProperty('initialHealth', 0);
    this.healthValue = initialHealth > 0 ? Math.min(this.maxHealth, initialHealth) : this.maxHealth;
    this.tags = this.stringArrayProperty('tags');
  }

  get runtimeNodeId(): string { return this.runtimeId; }
  get health(): number { return this.healthValue; }
  get destroyed(): boolean { return this.destroyedValue; }

  getDamageState() {
    return { hp: this.healthValue, maxHp: this.maxHealth, dead: this.destroyedValue };
  }

  canReceiveDamage(_input: DamageMitigationInput): DamageStateDecision {
    return this.destroyedValue
      ? { accepted: false, reason: 'dead' }
      : { accepted: true };
  }

  commitDamage(commit: DamageCommit): void {
    if (this.destroyedValue || commit.result.actualDamage <= 0) return;
    this.healthValue = Math.max(0, this.healthValue - commit.result.actualDamage);
    if (this.shouldPersistHealth()) {
      this.state?.saveHealth(this.mapId, this.instanceId, this.healthValue, this.maxHealth);
    }
    const change: DestructibleHealthChanged = {
      mapId: this.mapId,
      instanceId: this.instanceId,
      health: this.healthValue,
      maxHealth: this.maxHealth,
    };
    this.getSignal<DestructibleHealthChanged>('health_changed')?.emit(change);
    this.getSignal<DamageCommit>('damaged')?.emit(commit);
    this.onPositiveDamage(commit);
    if (commit.result.defeated || this.healthValue <= 0) this.destroyObject();
  }

  publishDamageFeedback(commit: DamageCommit): void {
    if (commit.result.actualDamage > 0) this.getSignal<DamageCommit>('damage_feedback')?.emit(commit);
  }

  override _enter_tree(): void {
    super._enter_tree();
    const damageRouter = this.service<DamageRouter>(DAMAGE_ROUTER_SERVICE);
    this.state = this.service<WorldObjectStatePort>(WORLD_OBJECT_STATE_SERVICE);
    const saved = this.state.load(this.mapId, this.instanceId);
    if (saved) {
      this.destroyedValue = saved.destroyed;
      this.healthValue = saved.destroyed ? 0 : Math.min(this.maxHealth, Math.max(0, saved.health));
    }
    if (this.destroyedValue) return;
    const target = this.getReference('damageArea')?.configuredTarget;
    if (!target) throw new Error(`DestructibleScript '${this.runtimeId}' requires its damageArea reference.`);
    damageRouter.registerArea(this, this.damageRule(target.runtimeId));
    this.entryDisposables.add(() => damageRouter.unregisterArea(this, target.runtimeId));
  }

  override _exit_tree(): void {
    this.state = undefined;
  }

  protected shouldPersistHealth(): boolean { return true; }

  protected onPositiveDamage(_commit: DamageCommit): void {}

  protected onDestroyed(event: DestructibleDestroyed): void {
    this.getSignal<DestructibleDestroyed>('destroyed')?.emit(event);
  }

  protected stringProperty(key: string, fallback: string): string {
    const value = this.exportedProperties[key];
    return typeof value === 'string' ? value : fallback;
  }

  protected numberProperty(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  protected booleanProperty(key: string, fallback: boolean): boolean {
    const value = this.exportedProperties[key];
    return typeof value === 'boolean' ? value : fallback;
  }

  protected jsonProperty(key: string): JsonValue | undefined {
    return this.exportedProperties[key];
  }

  private stringArrayProperty(key: string): readonly string[] {
    const value = this.exportedProperties[key];
    return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === 'string') : [];
  }

  private destroyObject(): void {
    if (this.destroyedValue) return;
    this.destroyedValue = true;
    this.healthValue = 0;
    this.state?.markDestroyed(this.mapId, this.instanceId);
    this.onDestroyed({ mapId: this.mapId, instanceId: this.instanceId, objectId: this.objectId });
  }

  private damageRule(areaNodeId: string): DamageAreaRule {
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

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): DestructibleScript {
    return new DestructibleScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
