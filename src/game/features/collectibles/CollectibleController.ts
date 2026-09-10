import type Phaser from 'phaser';

import { getObjectArchetype, isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import type { CollectibleCollectedPayload } from '../../core/EventBus';
import type { CollectibleProgressState } from '../progression/WorldProgress';
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
}

export interface CollectibleControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly group: Phaser.Physics.Arcade.StaticGroup;
  readonly inventory: { add(itemId: string, count: number): number };
  readonly progress: {
    collectibleState(mapId: string, instanceId: string): CollectibleProgressState | undefined;
    setCollectibleState(mapId: string, instanceId: string, state: CollectibleProgressState): void;
  };
  readonly publisher: CollectibleEventPublisher;
  readonly showMessage: (x: number, y: number, message: string, color: 'white' | 'yellow', important?: boolean) => void;
  readonly onStateChanged?: (change: CollectibleStateChange) => void;
}

/** Owns all walk-over collectible objects, including resource drops. */
export class CollectibleController {
  private readonly records = new Map<Phaser.GameObjects.GameObject, CollectibleRecord>();
  private inventoryHintReadyAt = 0;

  constructor(private readonly ctx: CollectibleControllerContext) {}

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
    this.syncImageData(record);

    if (record.remaining <= 0) {
      this.remove(record);
    }
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
    this.records.clear();
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
