import type Phaser from 'phaser';

import type { CollectibleCollectedPayload } from '../../core/EventBus';
import type { CollectibleProgressState } from '../progression/WorldProgress';
import type { InventoryWorldTransaction } from '../progression/InventoryWorldTransaction';
import type {
  CollectiblePickupRequest,
  CollectiblePickupResult,
  CollectibleWorldPort,
} from '../scripts/CollectibleScript';

export interface CollectibleStateChange {
  readonly instanceId: string;
  readonly remaining: number;
  readonly sourceResourceInstanceId?: string;
  readonly sourceInventoryDropId?: string;
}

export interface CollectibleEventPublisher {
  publishCollected(payload: CollectibleCollectedPayload): void;
}

export interface CollectibleControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly transaction: InventoryWorldTransaction;
  readonly progress: {
    collectibleState(mapId: string, instanceId: string): CollectibleProgressState | undefined;
  };
  readonly publisher: CollectibleEventPublisher;
  readonly showMessage: (x: number, y: number, message: string, color: 'white' | 'yellow', important?: boolean) => void;
  readonly onStateChanged?: (change: CollectibleStateChange) => void;
}

/** Coordinates pickup transactions for collectible ScriptNodes. */
export class CollectibleController implements CollectibleWorldPort {
  private readonly managedInitialQuantities = new Map<string, number>();
  private inventoryHintReadyAt = 0;

  constructor(private readonly ctx: CollectibleControllerContext) {}

  ensureInitialized(mapId: string, instanceId: string, quantity: number): void {
    if (mapId !== this.ctx.mapId || !Number.isSafeInteger(quantity) || quantity <= 0) return;
    this.managedInitialQuantities.set(instanceId, quantity);
  }

  remaining(mapId: string, instanceId: string): number {
    if (mapId !== this.ctx.mapId) return 0;
    return this.ctx.progress.collectibleState(mapId, instanceId)?.remaining
      ?? this.managedInitialQuantities.get(instanceId)
      ?? 0;
  }

  pickup(request: CollectiblePickupRequest): CollectiblePickupResult {
    const remaining = this.remaining(request.mapId, request.instanceId);
    if (request.mapId !== this.ctx.mapId) {
      return { status: 'rejected', moved: 0, remaining, reason: 'wrong-map' };
    }
    if (remaining <= 0) return { status: 'rejected', moved: 0, remaining: 0, reason: 'depleted' };
    const moved = this.ctx.transaction.collectWorldItem({
      mapId: request.mapId,
      instanceId: request.instanceId,
      itemId: request.itemId,
      remaining,
      requested: request.requested,
      ...(request.sourceResourceInstanceId ? { sourceResourceInstanceId: request.sourceResourceInstanceId } : {}),
      ...(request.sourceInventoryDropId ? { sourceInventoryDropId: request.sourceInventoryDropId } : {}),
    });
    if (moved <= 0) {
      if (this.ctx.scene.time.now >= this.inventoryHintReadyAt) {
        this.inventoryHintReadyAt = this.ctx.scene.time.now + 1000;
        this.ctx.showMessage(request.x, request.y - 34, 'Inventory full', 'white', true);
      }
      return { status: 'rejected', moved: 0, remaining, reason: 'inventory-full' };
    }

    const next = this.ctx.progress.collectibleState(request.mapId, request.instanceId) ?? { remaining: remaining - moved };
    this.ctx.onStateChanged?.({
      instanceId: request.instanceId,
      remaining: next.remaining,
      ...(next.sourceResourceInstanceId ? { sourceResourceInstanceId: next.sourceResourceInstanceId } : {}),
      ...(next.sourceInventoryDropId ? { sourceInventoryDropId: next.sourceInventoryDropId } : {}),
    });
    this.ctx.showMessage(request.x, request.y - 34, `+${moved} ${request.itemId}`, 'yellow');
    this.ctx.publisher.publishCollected({
      mapId: request.mapId,
      instanceId: request.instanceId,
      objectId: request.objectId,
      itemId: request.itemId,
      quantity: moved,
    });
    return {
      status: next.remaining === 0 ? 'collected' : 'partial',
      moved,
      remaining: next.remaining,
    };
  }

  destroy(): void {
    this.managedInitialQuantities.clear();
  }
}
