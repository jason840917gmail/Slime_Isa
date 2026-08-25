import type Phaser from 'phaser';

import { getObjectArchetype, isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import type { CollectibleProgressState } from '../progression/WorldProgress';
import type { BuiltObjectRegistration } from '../world/MapBuilder';

export interface CollectibleStateChange {
  readonly instanceId: string;
  readonly remaining: number;
  readonly sourceResourceInstanceId?: string;
}

interface CollectibleRecord {
  readonly image: Phaser.Physics.Arcade.Image;
  readonly objectId: string;
  readonly instanceId: string;
  readonly itemId: string;
  remaining: number;
  readonly sourceResourceInstanceId?: string;
}

export interface CollectibleControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly group: Phaser.Physics.Arcade.StaticGroup;
  readonly inventory: { add(itemId: string, count: number): number };
  readonly progress: {
    collectibleState(mapId: string, instanceId: string): CollectibleProgressState | undefined;
    migrateLegacyCollectibleState(mapId: string, instanceId: string): CollectibleProgressState | undefined;
    setCollectibleState(mapId: string, instanceId: string, state: CollectibleProgressState): void;
  };
  readonly showMessage: (x: number, y: number, message: string, color: 'white' | 'yellow', important?: boolean) => void;
  readonly onCollected?: (payload: { mapId: string; instanceId: string; objectId: string; itemId: string; quantity: number }) => void;
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
    const savedState = this.ctx.progress.collectibleState(this.ctx.mapId, registration.instanceId)
      ?? this.ctx.progress.migrateLegacyCollectibleState(this.ctx.mapId, registration.instanceId);
    const initialState = registration.initialState ?? {};
    const itemId = definition.collectible.itemId;
    const quantity = this.positiveIntegerState(initialState.quantity, definition.collectible.quantity);
    const sourceResourceInstanceId = typeof initialState.sourceResourceInstanceId === 'string'
      ? initialState.sourceResourceInstanceId
      : savedState?.sourceResourceInstanceId;
    const rawRemaining = this.nonNegativeIntegerState(
      savedState?.remaining ?? initialState.remaining,
      quantity,
    );
    const remaining = sourceResourceInstanceId ? rawRemaining : Math.min(quantity, rawRemaining);
    const record: CollectibleRecord = {
      image,
      objectId: registration.objectId,
      instanceId: registration.instanceId,
      itemId,
      remaining,
      ...(sourceResourceInstanceId ? { sourceResourceInstanceId } : {}),
    };
    this.records.set(image, record);
    image.setData('collectibleInstanceId', registration.instanceId);
    image.setData('collectibleItemId', record.itemId);
    image.setData('collectibleQuantity', record.remaining);
    image.setData('collectibleSourceResourceInstanceId', sourceResourceInstanceId);

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

    record.remaining -= added;
    record.image.setData('collectibleQuantity', record.remaining);
    this.ctx.progress.setCollectibleState(this.ctx.mapId, record.instanceId, {
      remaining: record.remaining,
      ...(record.sourceResourceInstanceId ? { sourceResourceInstanceId: record.sourceResourceInstanceId } : {}),
    });
    this.ctx.onStateChanged?.({
      instanceId: record.instanceId,
      remaining: record.remaining,
      ...(record.sourceResourceInstanceId ? { sourceResourceInstanceId: record.sourceResourceInstanceId } : {}),
    });
    this.ctx.showMessage(record.image.x, record.image.y - 34, `+${added} ${record.itemId}`, 'yellow');
    this.ctx.onCollected?.({
      mapId: this.ctx.mapId,
      instanceId: record.instanceId,
      objectId: record.objectId,
      itemId: record.itemId,
      quantity: added,
    });
    if (record.remaining <= 0) this.remove(record);
  }

  destroy(): void {
    this.records.clear();
  }

  private remove(record: CollectibleRecord): void {
    this.records.delete(record.image);
    this.ctx.group.remove(record.image, true, true);
  }

  private positiveIntegerState(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isInteger(value) && value > 0 ? value : fallback;
  }

  private nonNegativeIntegerState(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : fallback;
  }
}
