import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { PhysicsContact } from '../../runtime/scene/physics/PhysicsContact';
import { Node2D } from '../../runtime/scene/Node2D';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const COLLECTIBLE_WORLD_SERVICE = 'world.collectible-transaction';

export interface CollectiblePickupRequest {
  readonly mapId: string;
  readonly instanceId: string;
  readonly objectId: string;
  readonly itemId: string;
  readonly requested: number;
  readonly collectorAreaNodeId: string;
  readonly x: number;
  readonly y: number;
  readonly sourceResourceInstanceId?: string;
  readonly sourceInventoryDropId?: string;
}

export type CollectiblePickupResult =
  | { readonly status: 'collected' | 'partial'; readonly moved: number; readonly remaining: number }
  | { readonly status: 'rejected'; readonly moved: 0; readonly remaining: number; readonly reason: string };

export interface CollectibleWorldPort {
  ensureInitialized(mapId: string, instanceId: string, quantity: number): void;
  remaining(mapId: string, instanceId: string): number;
  pickup(request: CollectiblePickupRequest): CollectiblePickupResult;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('CollectibleScript requires a registered script identity.');
  return context.scriptId;
}

export class CollectibleScript extends ScriptNode {
  readonly mapId: string;
  readonly instanceId: string;
  readonly objectId: string;
  readonly itemId: string;
  readonly quantity: number;
  readonly sourceResourceInstanceId?: string;
  readonly sourceInventoryDropId?: string;
  private world?: CollectibleWorldPort;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.mapId = this.stringProperty('mapId', '');
    this.instanceId = this.stringProperty('instanceId', '');
    this.objectId = this.stringProperty('objectId', '');
    this.itemId = this.stringProperty('itemId', '');
    this.quantity = Math.max(1, Math.floor(this.numberProperty('quantity', 1)));
    const source = this.stringProperty('sourceResourceInstanceId', '');
    this.sourceResourceInstanceId = source || undefined;
    const inventoryDrop = this.stringProperty('sourceInventoryDropId', '');
    this.sourceInventoryDropId = inventoryDrop || undefined;
    this.registerSignalHandler<PhysicsContact>('on_area_entered', (contact) => {
      if (contact.otherKind === 'area') this.requestPickup(contact.otherId);
    });
  }

  get remaining(): number {
    return this.world?.remaining(this.mapId, this.instanceId) ?? this.quantity;
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.world = this.service<CollectibleWorldPort>(COLLECTIBLE_WORLD_SERVICE);
    this.world.ensureInitialized(this.mapId, this.instanceId, this.quantity);
    if (!this.getReference('pickupArea')?.configuredTarget) {
      throw new Error(`CollectibleScript '${this.runtimeId}' requires its pickupArea reference.`);
    }
  }

  override _exit_tree(): void {
    this.world = undefined;
  }

  requestPickup(collectorAreaNodeId: string): CollectiblePickupResult {
    const pickupArea = this.getReference('pickupArea')?.configuredTarget;
    const position = pickupArea instanceof Node2D
      ? pickupArea.get_global_transform().position
      : { x: 0, y: 0 };
    const request: CollectiblePickupRequest = {
      mapId: this.mapId,
      instanceId: this.instanceId,
      objectId: this.objectId,
      itemId: this.itemId,
      requested: this.remaining,
      collectorAreaNodeId,
      x: position.x,
      y: position.y,
      ...(this.sourceResourceInstanceId ? { sourceResourceInstanceId: this.sourceResourceInstanceId } : {}),
      ...(this.sourceInventoryDropId ? { sourceInventoryDropId: this.sourceInventoryDropId } : {}),
    };
    const result = this.world?.pickup(request) ?? {
      status: 'rejected' as const,
      moved: 0 as const,
      remaining: request.requested,
      reason: 'unavailable',
    };
    this.getSignal<CollectiblePickupResult>('pickup_resolved')?.emit(result);
    if (result.status !== 'rejected' && result.remaining === 0) this.getSignal<CollectiblePickupRequest>('depleted')?.emit(request);
    return result;
  }

  private stringProperty(key: string, fallback: string): string {
    const value = this.exportedProperties[key];
    return typeof value === 'string' ? value : fallback;
  }

  private numberProperty(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): CollectibleScript {
    return new CollectibleScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
