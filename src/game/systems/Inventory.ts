import { gameEvents } from '../core/EventBus';
import type { InventorySlot, ItemDef } from '../core/types';
import { getBaseItemDefinitions } from '../content/items/ItemCatalog';
import { getWeaponDefinitions } from '../content/weapons/WeaponCatalog';
import { GAME_CONSTANTS } from '../Constant';
import type { InventorySaveData } from '../infrastructure/persistence/SaveSchema';

/**
 * Slot-based inventory with categories + stacking.
 *
 * Item definitions live in a registry (registered by BootScene/data loader);
 * the inventory only stores itemId + count. This keeps saves small and
 * content-driven.
 */

class ItemRegistryImpl {
  private defs: Record<string, ItemDef> = { ...getBaseItemDefinitions() };

  register(def: ItemDef): void {
    this.defs[def.id] = def;
  }

  get(itemId: string): ItemDef | undefined {
    return this.defs[itemId];
  }

  all(): ItemDef[] {
    return Object.values(this.defs);
  }
}

export const itemRegistry = new ItemRegistryImpl();

for (const weapon of getWeaponDefinitions()) {
  itemRegistry.register({
    id: weapon.weaponId,
    name: weapon.displayName,
    category: 'weapon',
    icon: weapon.iconKey,
    ...(weapon.iconFrame !== undefined ? { iconFrame: weapon.iconFrame } : {}),
    description: weapon.description,
    maxStack: GAME_CONSTANTS.inventory.weaponMaxStack,
    equipment: { weaponId: weapon.weaponId },
  });
}

export function weaponItemFor(weaponId: string): ItemDef | undefined {
  return itemRegistry.all().find((item) => item.equipment?.weaponId === weaponId);
}

export class Inventory {
  private slots: InventorySlot[] = [];
  private maxSlotsValue = GAME_CONSTANTS.inventory.initialMaxSlots;

  transact(
    removals: readonly Readonly<InventorySlot>[],
    additions: readonly Readonly<InventorySlot>[],
  ): boolean {
    const draft = this.createTransactionDraft(removals, additions);
    if (!draft) return false;
    this.slots = draft;
    gameEvents.emit('inventory.changed', {});
    return true;
  }

  previewTransact(
    removals: readonly Readonly<InventorySlot>[],
    additions: readonly Readonly<InventorySlot>[],
  ): boolean {
    return this.createTransactionDraft(removals, additions) !== null;
  }

  private createTransactionDraft(
    removals: readonly Readonly<InventorySlot>[],
    additions: readonly Readonly<InventorySlot>[],
  ): InventorySlot[] | null {
    const draft = this.slots.map((slot) => ({ ...slot }));
    const removalTotals = new Map<string, number>();
    for (const removal of removals) {
      if (!Number.isSafeInteger(removal.count) || removal.count <= 0) return null;
      removalTotals.set(removal.itemId, (removalTotals.get(removal.itemId) ?? 0) + removal.count);
    }

    for (const [itemId, count] of removalTotals) {
      let remaining = count;
      for (const slot of draft) {
        if (remaining <= 0) break;
        if (slot.itemId !== itemId) continue;
        const amount = Math.min(slot.count, remaining);
        slot.count -= amount;
        remaining -= amount;
      }
      if (remaining > 0) return null;
    }

    const compact = draft.filter((slot) => slot.count > 0);
    const additionTotals = new Map<string, number>();
    for (const addition of additions) {
      if (!Number.isSafeInteger(addition.count) || addition.count <= 0) return null;
      additionTotals.set(addition.itemId, (additionTotals.get(addition.itemId) ?? 0) + addition.count);
    }

    for (const [itemId, count] of additionTotals) {
      const def = itemRegistry.get(itemId);
      if (!def || !Number.isSafeInteger(def.maxStack) || def.maxStack <= 0) return null;
      let remaining = count;
      for (const slot of compact) {
        if (remaining <= 0) break;
        if (slot.itemId !== itemId || slot.count >= def.maxStack) continue;
        const amount = Math.min(def.maxStack - slot.count, remaining);
        slot.count += amount;
        remaining -= amount;
      }
      while (remaining > 0 && compact.length < this.maxSlotsValue) {
        const amount = Math.min(def.maxStack, remaining);
        compact.push({ itemId, count: amount });
        remaining -= amount;
      }
      if (remaining > 0) return null;
    }
    return compact;
  }

  add(itemId: string, count = 1): number {
    const def = itemRegistry.get(itemId);
    if (!def) return 0;

    let remaining = count;

    // Stack into existing slot first.
    for (const slot of this.slots) {
      if (remaining <= 0) break;
      if (slot.itemId !== itemId) continue;
      if (slot.count >= def.maxStack) continue;
      const space = def.maxStack - slot.count;
      const add = Math.min(space, remaining);
      slot.count += add;
      remaining -= add;
    }

    // Open new slots.
    while (remaining > 0 && this.slots.length < this.maxSlotsValue) {
      const add = Math.min(def.maxStack, remaining);
      this.slots.push({ itemId, count: add });
      remaining -= add;
    }

    gameEvents.emit('inventory.changed', {});
    return count - remaining;
  }

  remove(itemId: string, count = 1): number {
    let remaining = count;
    for (const slot of this.slots) {
      if (remaining <= 0) break;
      if (slot.itemId !== itemId) continue;
      const take = Math.min(slot.count, remaining);
      slot.count -= take;
      remaining -= take;
    }
    this.slots = this.slots.filter((s) => s.count > 0);
    gameEvents.emit('inventory.changed', {});
    return count - remaining;
  }

  removeFromSlot(slotIndex: number, count = 1): number {
    if (!Number.isInteger(slotIndex) || !Number.isInteger(count) || count <= 0) return 0;
    const slot = this.slots[slotIndex];
    if (!slot) return 0;

    const removed = Math.min(slot.count, count);
    slot.count -= removed;
    if (slot.count === 0) this.slots.splice(slotIndex, 1);
    gameEvents.emit('inventory.changed', {});
    return removed;
  }

  count(itemId: string): number {
    return this.slots
      .filter((s) => s.itemId === itemId)
      .reduce((sum, s) => sum + s.count, 0);
  }

  getSlots(): ReadonlyArray<InventorySlot> {
    return this.slots;
  }

  maxSlots(): number {
    return this.maxSlotsValue;
  }

  increaseMaxSlots(amount: number): boolean {
    if (!Number.isInteger(amount) || amount <= 0) return false;
    this.maxSlotsValue += amount;
    gameEvents.emit('inventory.changed', {});
    return true;
  }

  serialize(): InventorySaveData {
    return { maxSlots: this.maxSlotsValue, slots: this.slots.map((slot) => ({ ...slot })) };
  }

  load(data: InventorySaveData): void {
    this.maxSlotsValue = data.maxSlots;
    this.slots = data.slots.map((slot) => ({ ...slot }));
    gameEvents.emit('inventory.changed', {});
  }

  clear(): void {
    this.slots = [];
    this.maxSlotsValue = GAME_CONSTANTS.inventory.initialMaxSlots;
    gameEvents.emit('inventory.changed', {});
  }
}

export const playerInventory = new Inventory();
