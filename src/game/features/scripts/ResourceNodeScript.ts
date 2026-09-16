import type { JsonValue } from '../../content/scenes/types';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { DamageCommit, DamageMitigationInput, DamageStateDecision } from '../combat/DamageReceiver';
import {
  DestructibleScript,
  type DestructibleDestroyed,
} from './DestructibleScript';

export const RESOURCE_NODE_SERVICE = 'world.resource-node';

export interface ResourceDropRequest {
  readonly mapId: string;
  readonly instanceId: string;
  readonly objectId: string;
  readonly dropObjectId: string;
  readonly dropVisualId: string;
  readonly pieces: number;
  readonly depletionMessage?: string;
}

export interface ResourceHitFeedbackRequest {
  readonly mapId: string;
  readonly instanceId: string;
  readonly objectId: string;
  readonly actualDamage: number;
  readonly effectId?: string;
  readonly animationId?: string;
}

export interface ResourceHarvestBlocked {
  readonly mapId: string;
  readonly instanceId: string;
  readonly targetTag: string;
  readonly minimumTier: number;
  readonly message: string;
}

export interface ResourceNodePort {
  publishHit(request: ResourceHitFeedbackRequest): void;
  publishHarvestBlocked(request: ResourceHarvestBlocked): void;
  spawnDrops(request: ResourceDropRequest): void;
}

interface HarvestRequirement {
  readonly targetTag: string;
  readonly minimumTier: number;
  readonly failureMessage: string;
}

interface DropConfiguration {
  readonly objectId: string;
  readonly visualId: string;
  readonly pieces: number;
}

function isRecord(value: JsonValue | undefined): value is Readonly<Record<string, JsonValue>> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export class ResourceNodeScript extends DestructibleScript {
  private resourcePort?: ResourceNodePort;
  private dropsPublished = false;

  override canReceiveDamage(input: DamageMitigationInput): DamageStateDecision {
    const base = super.canReceiveDamage(input);
    if (!base.accepted) return base;
    const requirement = this.harvestRequirement();
    if (!requirement) return base;
    const capability = input.request.weaponTags
      .map((tag) => this.harvestTier(tag, requirement.targetTag))
      .reduce((highest, tier) => Math.max(highest, tier), 0);
    if (capability >= requirement.minimumTier) return base;
    const blocked: ResourceHarvestBlocked = {
      mapId: this.mapId,
      instanceId: this.instanceId,
      targetTag: requirement.targetTag,
      minimumTier: requirement.minimumTier,
      message: requirement.failureMessage,
    };
    this.resourcePort?.publishHarvestBlocked(blocked);
    this.getSignal<ResourceHarvestBlocked>('harvest_blocked')?.emit(blocked);
    return { accepted: false, reason: 'state-blocked' };
  }

  override _enter_tree(): void {
    this.resourcePort = this.service<ResourceNodePort>(RESOURCE_NODE_SERVICE);
    super._enter_tree();
  }

  override _exit_tree(): void {
    super._exit_tree();
    this.resourcePort = undefined;
  }

  protected override shouldPersistHealth(): boolean {
    return this.booleanProperty('persistHealth', true);
  }

  protected override onPositiveDamage(commit: DamageCommit): void {
    const request: ResourceHitFeedbackRequest = {
      mapId: this.mapId,
      instanceId: this.instanceId,
      objectId: this.objectId,
      actualDamage: commit.result.actualDamage,
      ...(this.stringProperty('hitEffectId', '') ? { effectId: this.stringProperty('hitEffectId', '') } : {}),
      ...(this.stringProperty('onHitAnimationId', '') ? { animationId: this.stringProperty('onHitAnimationId', '') } : {}),
    };
    this.resourcePort?.publishHit(request);
    this.getSignal<ResourceHitFeedbackRequest>('resource_hit')?.emit(request);
  }

  protected override onDestroyed(event: DestructibleDestroyed): void {
    super.onDestroyed(event);
    if (this.dropsPublished) return;
    const drop = this.dropConfiguration();
    if (!drop) return;
    this.dropsPublished = true;
    const request: ResourceDropRequest = {
      mapId: this.mapId,
      instanceId: this.instanceId,
      objectId: this.objectId,
      dropObjectId: drop.objectId,
      dropVisualId: drop.visualId,
      pieces: drop.pieces,
      ...(this.stringProperty('depletionMessage', '') ? { depletionMessage: this.stringProperty('depletionMessage', '') } : {}),
    };
    this.resourcePort?.spawnDrops(request);
    this.getSignal<ResourceDropRequest>('drops_requested')?.emit(request);
  }

  private harvestRequirement(): HarvestRequirement | undefined {
    const value = this.jsonProperty('harvestRequirement');
    if (!isRecord(value)) return undefined;
    const targetTag = value.targetTag;
    const minimumTier = value.minimumTier;
    const failureMessage = value.failureMessage;
    if (typeof targetTag !== 'string' || typeof minimumTier !== 'number' || typeof failureMessage !== 'string') return undefined;
    return { targetTag, minimumTier, failureMessage };
  }

  private dropConfiguration(): DropConfiguration | undefined {
    const value = this.jsonProperty('drop');
    if (!isRecord(value)) return undefined;
    if (typeof value.objectId !== 'string' || typeof value.visualId !== 'string' || typeof value.pieces !== 'number') return undefined;
    return { objectId: value.objectId, visualId: value.visualId, pieces: Math.max(1, Math.floor(value.pieces)) };
  }

  private harvestTier(tag: string, targetTag: string): number {
    const prefix = `harvest:${targetTag}:`;
    if (!tag.startsWith(prefix)) return 0;
    const tier = Number(tag.slice(prefix.length));
    return Number.isSafeInteger(tier) && tier > 0 ? tier : 0;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ResourceNodeScript {
    return new ResourceNodeScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
