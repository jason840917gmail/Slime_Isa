import { isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import { resolveInventoryDropDefinition } from '../../content/items/InventoryDropCatalog';
import type { InventorySlot } from '../../core/types';
import type { FacingDirection } from '../../infrastructure/persistence/SaveSchema';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { InventoryWorldDropProgress } from '../progression/WorldProgress';
import type { CollectibleStateChange } from './CollectibleController';
import { findInventoryDropDestination, type InventoryDropCellInspection } from './InventoryDropPlacement';
import type { WorldDropRequest } from './WorldDropRequest';

export interface InventoryDropControllerContext {
  readonly mapId: string;
  readonly dimensions: WorldDimensions;
  readonly inventory: {
    getSlots(): ReadonlyArray<InventorySlot>;
    removeFromSlot(slotIndex: number, count: number): number;
    add(itemId: string, count: number): number;
  };
  readonly getPlayerAnchor: () => { readonly x: number; readonly y: number };
  readonly getFacing: () => FacingDirection;
  readonly inspectCell: (itemId: string, cellX: number, cellY: number) => InventoryDropCellInspection;
  readonly spawnWorldDrop: (request: WorldDropRequest) => void;
  readonly showMessage: (message: string) => void;
  readonly progress: {
    inventoryDrops(mapId: string): readonly InventoryWorldDropProgress[];
    createInventoryDrop(
      mapId: string,
      drop: Omit<InventoryWorldDropProgress, 'id'>,
    ): InventoryWorldDropProgress;
    setInventoryDropAmount(mapId: string, instanceId: string, amount: number): void;
  };
}

/** Owns persistent physical drops created explicitly from player inventory. */
export class InventoryDropController {
  constructor(private readonly ctx: InventoryDropControllerContext) {}

  canDrop(itemId: string): boolean {
    return resolveInventoryDropDefinition(itemId) !== undefined;
  }

  dropFromSlot(slotIndex: number, requestedQuantity: number): boolean {
    const slot = this.ctx.inventory.getSlots()[slotIndex];
    if (!slot || !Number.isInteger(requestedQuantity) || requestedQuantity <= 0) return false;
    const definition = resolveInventoryDropDefinition(slot.itemId);
    if (!definition) return false;
    const quantity = Math.min(slot.count, requestedQuantity);
    const source = this.ctx.getPlayerAnchor();
    const existingDrops = this.ctx.progress.inventoryDrops(this.ctx.mapId);
    const destination = findInventoryDropDestination(
      source,
      this.ctx.getFacing(),
      this.ctx.dimensions,
      (cellX, cellY) => {
        const existing = existingDrops.find((drop) => this.dropOccupiesCell(drop, cellX, cellY));
        if (existing) {
          return existing.itemId === slot.itemId
            ? { kind: 'compatible-stack', destination: { x: existing.x, y: existing.y } }
            : { kind: 'blocked' };
        }
        return this.ctx.inspectCell(slot.itemId, cellX, cellY);
      },
    );
    if (!destination) {
      this.ctx.showMessage('No ground space available');
      return false;
    }

    const removed = this.ctx.inventory.removeFromSlot(slotIndex, quantity);
    if (removed !== quantity) {
      if (removed > 0) this.ctx.inventory.add(slot.itemId, removed);
      return false;
    }

    let record: InventoryWorldDropProgress | undefined;
    try {
      record = this.ctx.progress.createInventoryDrop(this.ctx.mapId, {
        itemId: slot.itemId,
        amount: quantity,
        objectId: definition.objectId,
        visualId: definition.visualId,
        x: destination.x,
        y: destination.y,
      });
      this.ctx.spawnWorldDrop({
        mode: 'launch',
        source,
        destination,
        launchIndex: 0,
        drop: {
          objectId: definition.objectId,
          visualId: definition.visualId,
          instanceId: record.id,
          initialState: { remaining: quantity, sourceInventoryDropId: record.id },
        },
      });
      return true;
    } catch (error) {
      if (record) this.ctx.progress.setInventoryDropAmount(this.ctx.mapId, record.id, 0);
      this.ctx.inventory.add(slot.itemId, quantity);
      this.ctx.showMessage('Could not drop item');
      if (import.meta.env.DEV) console.warn('Inventory drop creation failed.', error);
      return false;
    }
  }

  restore(): void {
    for (const record of this.ctx.progress.inventoryDrops(this.ctx.mapId)) {
      const definition = resolveInventoryDropDefinition(record.itemId);
      if (!definition
        || !isObjectArchetypeId(record.objectId)
        || definition.objectId !== record.objectId
        || definition.visualId !== record.visualId
        || record.amount <= 0) continue;
      this.ctx.spawnWorldDrop({
        mode: 'settled',
        destination: { x: record.x, y: record.y },
        drop: {
          objectId: record.objectId,
          visualId: record.visualId,
          instanceId: record.id,
          initialState: { remaining: record.amount, sourceInventoryDropId: record.id },
        },
      });
    }
  }

  onCollectibleStateChanged(change: CollectibleStateChange): void {
    if (!change.sourceInventoryDropId) return;
    this.ctx.progress.setInventoryDropAmount(this.ctx.mapId, change.sourceInventoryDropId, change.remaining);
  }

  private dropOccupiesCell(drop: InventoryWorldDropProgress, cellX: number, cellY: number): boolean {
    const { tileSize } = this.ctx.dimensions;
    return drop.amount > 0
      && Math.floor(drop.x / tileSize) === cellX
      && Math.floor(drop.y / tileSize) - 1 === cellY;
  }
}
