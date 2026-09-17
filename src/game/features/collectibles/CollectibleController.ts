import type Phaser from 'phaser';

import { getObjectArchetype, isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import type { CollectibleCollectedPayload } from '../../core/EventBus';
import { UI_THEME } from '../../presentation/theme';
import { resolveWorldDepth } from '../../presentation/WorldDepth';
import type { CollectibleProgressState } from '../progression/WorldProgress';
import type { InventoryWorldTransaction } from '../progression/InventoryWorldTransaction';
import type {
  CollectiblePickupRequest,
  CollectiblePickupResult,
  CollectibleWorldPort,
} from '../scripts/CollectibleScript';
import type { BuiltObjectRegistration } from '../world/MapBuilder';
import type { InventoryDropCellInspection } from './InventoryDropPlacement';

export interface CollectibleStateChange {
  readonly instanceId: string;
  readonly remaining: number;
  readonly sourceResourceInstanceId?: string;
  readonly sourceInventoryDropId?: string;
}

export interface CollectibleEventPublisher {
  publishCollected(payload: CollectibleCollectedPayload): void;
}

interface CollectibleRecord {
  readonly image: Phaser.Physics.Arcade.Image;
  readonly objectId: string;
  readonly instanceId: string;
  readonly itemId: string;
  remaining: number;
  readonly sourceResourceInstanceId?: string;
  readonly sourceInventoryDropId?: string;
  quantityLabel?: Phaser.GameObjects.Text;
}

export interface CollectibleControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly group: Phaser.Physics.Arcade.StaticGroup;
  readonly inventory: { add(itemId: string, count: number): number };
  readonly transaction: InventoryWorldTransaction;
  readonly progress: {
    collectibleState(mapId: string, instanceId: string): CollectibleProgressState | undefined;
    setCollectibleState(mapId: string, instanceId: string, state: CollectibleProgressState): void;
  };
  readonly publisher: CollectibleEventPublisher;
  readonly showMessage: (x: number, y: number, message: string, color: 'white' | 'yellow', important?: boolean) => void;
  readonly onStateChanged?: (change: CollectibleStateChange) => void;
}

/** Owns all walk-over collectible objects, including resource drops. */
export class CollectibleController implements CollectibleWorldPort {
  private readonly records = new Map<Phaser.GameObjects.GameObject, CollectibleRecord>();
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

  register(registration: BuiltObjectRegistration): void {
    if (!isObjectArchetypeId(registration.objectId)) return;
    const definition = getObjectArchetype(registration.objectId);
    if (!definition.collectible) return;

    const image = registration.image as Phaser.Physics.Arcade.Image;
    if (!this.ctx.group.getChildren().includes(image)) this.ctx.group.add(image);
    const savedState = this.ctx.progress.collectibleState(this.ctx.mapId, registration.instanceId);
    const initialState = registration.initialState ?? {};
    const itemId = definition.collectible.itemId;
    const quantity = this.positiveIntegerState(initialState.quantity, definition.collectible.quantity);
    const sourceResourceInstanceId = typeof initialState.sourceResourceInstanceId === 'string'
      ? initialState.sourceResourceInstanceId
      : savedState?.sourceResourceInstanceId;
    const sourceInventoryDropId = typeof initialState.sourceInventoryDropId === 'string'
      ? initialState.sourceInventoryDropId
      : savedState?.sourceInventoryDropId;
    const rawRemaining = this.nonNegativeIntegerState(
      savedState?.remaining ?? initialState.remaining,
      quantity,
    );
    const remaining = sourceResourceInstanceId || sourceInventoryDropId
      ? rawRemaining
      : Math.min(quantity, rawRemaining);
    const record: CollectibleRecord = {
      image,
      objectId: registration.objectId,
      instanceId: registration.instanceId,
      itemId,
      remaining,
      ...(sourceResourceInstanceId ? { sourceResourceInstanceId } : {}),
      ...(sourceInventoryDropId ? { sourceInventoryDropId } : {}),
    };
    if (record.remaining > 0 && this.mergeIntoExisting(record)) return;
    this.records.set(image, record);
    if (record.remaining <= 0) {
      this.remove(record);
      return;
    }
    this.syncImageData(record);
  }

  collect(target: Phaser.GameObjects.GameObject): void {
    const record = this.records.get(target);
    if (!record || !record.image.active || record.remaining <= 0) return;

    const added = this.ctx.inventory.add(record.itemId, record.remaining);
    if (added <= 0) {
      if (this.ctx.scene.time.now >= this.inventoryHintReadyAt) {
        this.inventoryHintReadyAt = this.ctx.scene.time.now + 1000;
        this.ctx.showMessage(record.image.x, record.image.y - 34, 'Inventory full', 'white', true);
      }
      return;
    }

    const messageX = record.image.x;
    const messageY = record.image.y - 34;
    record.remaining -= added;
    this.syncImageData(record);
    this.persistAndNotify(record);
    const payload: CollectibleCollectedPayload = {
      mapId: this.ctx.mapId,
      instanceId: record.instanceId,
      objectId: record.objectId,
      itemId: record.itemId,
      quantity: added,
    };
    if (record.remaining <= 0) this.remove(record);
    this.ctx.showMessage(messageX, messageY, `+${added} ${record.itemId}`, 'yellow');
    this.ctx.publisher.publishCollected(payload);
  }

  destroy(): void {
    for (const record of this.records.values()) record.quantityLabel?.destroy();
    this.records.clear();
    this.managedInitialQuantities.clear();
  }

  inspectCell(itemId: string, cellX: number, cellY: number, tileSize: number): InventoryDropCellInspection {
    const occupants = [...this.records.values()].filter((record) => record.image.active
      && Math.floor(record.image.x / tileSize) === cellX
      && Math.floor(record.image.y / tileSize) - 1 === cellY);
    if (occupants.length === 0) return { kind: 'open' };
    const stack = occupants.find((record) => record.itemId === itemId && this.isDynamic(record));
    if (!stack || occupants.some((record) => record.itemId !== itemId || !this.isDynamic(record))) {
      return { kind: 'blocked' };
    }
    return { kind: 'compatible-stack', destination: { x: stack.image.x, y: stack.image.y } };
  }

  private remove(record: CollectibleRecord): void {
    this.records.delete(record.image);
    record.quantityLabel?.destroy();
    this.ctx.group.remove(record.image, true, true);
  }

  private mergeIntoExisting(incoming: CollectibleRecord): boolean {
    if (!this.isDynamic(incoming)) return false;
    const target = [...this.records.values()].find((record) => record.image.active
      && record.itemId === incoming.itemId
      && this.isDynamic(record)
      && Math.floor(record.image.x) === Math.floor(incoming.image.x)
      && Math.floor(record.image.y) === Math.floor(incoming.image.y));
    if (!target) return false;

    target.remaining += incoming.remaining;
    this.syncImageData(target);
    this.persistAndNotify(target);
    incoming.remaining = 0;
    this.persistAndNotify(incoming);
    this.ctx.group.remove(incoming.image, true, true);
    return true;
  }

  private isDynamic(record: CollectibleRecord): boolean {
    return Boolean(record.sourceResourceInstanceId || record.sourceInventoryDropId);
  }

  private syncImageData(record: CollectibleRecord): void {
    record.image.setData('collectibleInstanceId', record.instanceId);
    record.image.setData('collectibleItemId', record.itemId);
    record.image.setData('collectibleQuantity', record.remaining);
    record.image.setData('collectibleSourceResourceInstanceId', record.sourceResourceInstanceId);
    record.image.setData('collectibleSourceInventoryDropId', record.sourceInventoryDropId);
    this.syncQuantityLabel(record);
  }

  private syncQuantityLabel(record: CollectibleRecord): void {
    if (!this.ctx.scene.add?.text) return;
    const y = record.image.y - Math.max(22, Math.min(44, record.image.displayHeight * 0.55));
    record.quantityLabel ??= this.ctx.scene.add.text(record.image.x, y, '', {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '16px',
      fontStyle: 'bold',
      color: '#fff4b8',
      stroke: '#101a18',
      strokeThickness: 4,
      backgroundColor: '#101a18cc',
      padding: { x: 4, y: 2 },
    }).setOrigin(0.5, 1);
    record.quantityLabel
      .setText(`×${record.remaining}`)
      .setPosition(record.image.x, y)
      .setDepth(resolveWorldDepth(record.image.y, {
        band: 'reveal-effects',
        stableId: `collectible-quantity:${record.instanceId}`,
      }).depth);
  }

  private persistAndNotify(record: CollectibleRecord): void {
    const state = {
      remaining: record.remaining,
      ...(record.sourceResourceInstanceId ? { sourceResourceInstanceId: record.sourceResourceInstanceId } : {}),
      ...(record.sourceInventoryDropId ? { sourceInventoryDropId: record.sourceInventoryDropId } : {}),
    };
    this.ctx.progress.setCollectibleState(this.ctx.mapId, record.instanceId, state);
    this.ctx.onStateChanged?.({ instanceId: record.instanceId, ...state });
  }

  private positiveIntegerState(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isInteger(value) && value > 0 ? value : fallback;
  }

  private nonNegativeIntegerState(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : fallback;
  }
}
