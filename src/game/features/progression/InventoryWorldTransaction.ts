import type { WorldProgressData } from '../../infrastructure/persistence/SaveSchema';
import type { Inventory } from '../../systems/Inventory';
import { playerInventory } from '../../systems/Inventory';
import { worldProgress, type WorldProgress } from './WorldProgress';

export type GateUnlockResult = 'unlocked' | 'already-unlocked' | 'missing-item' | 'failed';

export interface CollectWorldItemInput {
  readonly mapId: string;
  readonly instanceId: string;
  readonly itemId: string;
  readonly remaining: number;
  readonly requested?: number;
  readonly sourceResourceInstanceId?: string;
  readonly sourceInventoryDropId?: string;
}

export class InventoryWorldTransaction {
  constructor(
    private readonly inventory: Inventory,
    private readonly progress: WorldProgress,
  ) {}

  transferChestStack(mapId: string, instanceId: string, itemId: string): number {
    const current = this.progress.chestState(mapId, instanceId)?.remaining ?? {};
    const available = current[itemId] ?? 0;
    if (!Number.isSafeInteger(available) || available <= 0) return 0;

    let low = 0;
    let high = available;
    while (low < high) {
      const candidate = Math.ceil((low + high) / 2);
      if (this.inventory.prepareTransaction([], [{ itemId, count: candidate }])) low = candidate;
      else high = candidate - 1;
    }
    if (low <= 0) return 0;

    const inventoryBefore = this.inventory.captureTransactionSnapshot();
    const worldBefore = this.progress.captureTransactionSnapshot();
    const inventoryAfter = this.inventory.prepareTransaction([], [{ itemId, count: low }]);
    if (!inventoryAfter) return 0;
    const remaining = { ...current };
    const left = available - low;
    if (left > 0) remaining[itemId] = left;
    else delete remaining[itemId];
    const worldAfter = this.progress.prepareChestRemainingSnapshot(mapId, instanceId, remaining);

    return this.commit(inventoryBefore, worldBefore, inventoryAfter, worldAfter, true) ? low : 0;
  }

  collectWorldItem(input: CollectWorldItemInput): number {
    const savedState = this.progress.collectibleState(input.mapId, input.instanceId);
    const remaining = savedState?.remaining ?? input.remaining;
    const requested = input.requested ?? remaining;
    if (!Number.isSafeInteger(remaining) || remaining <= 0) return 0;
    if (!Number.isSafeInteger(requested) || requested <= 0) return 0;
    const available = Math.min(remaining, requested);

    let low = 0;
    let high = available;
    while (low < high) {
      const candidate = Math.ceil((low + high) / 2);
      if (this.inventory.prepareTransaction([], [{ itemId: input.itemId, count: candidate }])) low = candidate;
      else high = candidate - 1;
    }
    if (low <= 0) return 0;

    const inventoryBefore = this.inventory.captureTransactionSnapshot();
    const worldBefore = this.progress.captureTransactionSnapshot();
    const inventoryAfter = this.inventory.prepareTransaction([], [{ itemId: input.itemId, count: low }]);
    if (!inventoryAfter) return 0;
    const sourceResourceInstanceId = savedState?.sourceResourceInstanceId ?? input.sourceResourceInstanceId;
    const sourceInventoryDropId = savedState?.sourceInventoryDropId ?? input.sourceInventoryDropId;
    const worldAfter = this.progress.prepareCollectibleRemainingSnapshot(input.mapId, input.instanceId, {
      remaining: remaining - low,
      ...(sourceResourceInstanceId ? { sourceResourceInstanceId } : {}),
      ...(sourceInventoryDropId ? { sourceInventoryDropId } : {}),
    });

    return this.commit(inventoryBefore, worldBefore, inventoryAfter, worldAfter, true) ? low : 0;
  }

  unlockGate(input: {
    readonly mapId: string;
    readonly gateId: string;
    readonly requiredItemId: string;
    readonly consumeOnUnlock: boolean;
  }): GateUnlockResult {
    if (this.progress.isGateUnlocked(input.mapId, input.gateId)) return 'already-unlocked';
    if (this.inventory.count(input.requiredItemId) < 1) return 'missing-item';

    const inventoryBefore = this.inventory.captureTransactionSnapshot();
    const worldBefore = this.progress.captureTransactionSnapshot();
    const inventoryAfter = input.consumeOnUnlock
      ? this.inventory.prepareTransaction([{ itemId: input.requiredItemId, count: 1 }], [])
      : inventoryBefore;
    if (!inventoryAfter) return 'failed';
    const worldAfter = this.progress.prepareGateUnlockSnapshot(input.mapId, input.gateId);
    return this.commit(inventoryBefore, worldBefore, inventoryAfter, worldAfter, input.consumeOnUnlock)
      ? 'unlocked'
      : 'failed';
  }

  private commit(
    inventoryBefore: ReturnType<Inventory['captureTransactionSnapshot']>,
    worldBefore: WorldProgressData,
    inventoryAfter: ReturnType<Inventory['captureTransactionSnapshot']>,
    worldAfter: WorldProgressData,
    inventoryChanged: boolean,
  ): boolean {
    try {
      this.inventory.installTransactionSnapshot(inventoryAfter);
      this.progress.installTransactionSnapshot(worldAfter);
    } catch {
      try { this.inventory.installTransactionSnapshot(inventoryBefore); } catch { /* preserve the original failure */ }
      try { this.progress.installTransactionSnapshot(worldBefore); } catch { /* preserve the original failure */ }
      return false;
    }
    if (inventoryChanged) this.inventory.emitTransactionChanged();
    this.progress.emitTransactionChanged();
    return true;
  }
}

export const playerInventoryWorldTransaction = new InventoryWorldTransaction(playerInventory, worldProgress);
