import { isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import { resolveInventoryDropDefinition } from '../../content/items/InventoryDropCatalog';
import type { InventorySlot } from '../../core/types';
import type { FacingDirection } from '../../infrastructure/persistence/SaveSchema';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { InventoryWorldDropProgress } from '../progression/WorldProgress';
import type { CollectibleStateChange } from './CollectibleController';
import { findInventoryDropDestination, type InventoryDropCellInspection } from './InventoryDropPlacement';
import { scatterLootDestinations } from './LootDropPlacement';
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
  /** True where enemy loot must not land (walls, trees, water, outside the world). */
  readonly isLootPointBlocked: (x: number, y: number) => boolean;
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

/** An enemy's loot: the items that fell when it was defeated, where it fell. */
export interface EnemyLootRequest {
  readonly x: number;
  readonly y: number;
  readonly items: readonly { readonly itemId: string; readonly count: number }[];
}

/**
 * Owns persistent physical drops: items the player drops from the bag, and
 * enemy loot (playtest 2026-10-01: loot lands on the ground and is picked up
 * by walking over it, like resources). Both persist until picked up.
 */
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

  /**
   * Scatters an enemy's loot around where it fell. Each piece is persisted
   * before it launches, so a failed spawn still comes back on reload; an item
   * with no ground look goes straight into the bag.
   */
  dropLoot(request: EnemyLootRequest): void {
    const destinations = scatterLootDestinations(request, request.items.length, this.ctx.dimensions.tileSize, this.ctx.isLootPointBlocked);
    request.items.forEach((item, index) => {
      if (!Number.isSafeInteger(item.count) || item.count <= 0) return;
      const definition = resolveInventoryDropDefinition(item.itemId);
      const destination = destinations[index];
      if (!definition || !destination) {
        this.ctx.inventory.add(item.itemId, item.count);
        return;
      }
      const record = this.ctx.progress.createInventoryDrop(this.ctx.mapId, {
        itemId: item.itemId,
        amount: item.count,
        objectId: definition.objectId,
        visualId: definition.visualId,
        x: destination.x,
        y: destination.y,
        origin: 'loot',
      });
      try {
        this.ctx.spawnWorldDrop({
          mode: 'launch',
          source: { x: request.x, y: request.y },
          destination,
          launchIndex: index,
          drop: {
            objectId: definition.objectId,
            visualId: definition.visualId,
            instanceId: record.id,
            initialState: { remaining: item.count, sourceInventoryDropId: record.id },
          },
        });
      } catch (error) {
        if (import.meta.env.DEV) console.warn('Enemy loot could not be spawned; it returns on reload.', error);
      }
    });
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
