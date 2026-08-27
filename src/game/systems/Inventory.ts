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
    const draft = this.slots.map((slot) => ({ ...slot }));
    for (const removal of removals) {
      let remaining = removal.count;
      for (const slot of draft) {
        if (remaining <= 0) break;
        if (slot.itemId !== removal.itemId) continue;
        const amount = Math.min(slot.count, remaining);
        slot.count -= amount;
        remaining -= amount;
      }
      if (remaining > 0) return false;
    }

    const compact = draft.filter((slot) => slot.count > 0);
    for (const addition of additions) {
      const def = itemRegistry.get(addition.itemId);
      if (!def || addition.count <= 0) return false;
      let remaining = addition.count;
      for (const slot of compact) {
        if (remaining <= 0) break;
        if (slot.itemId !== addition.itemId || slot.count >= def.maxStack) continue;
        const amount = Math.min(def.maxStack - slot.count, remaining);
        slot.count += amount;
        remaining -= amount;
      }
      while (remaining > 0 && compact.length < this.maxSlotsValue) {
        const amount = Math.min(def.maxStack, remaining);
        compact.push({ itemId: addition.itemId, count: amount });
        remaining -= amount;
      }
      if (remaining > 0) return false;
    }

    this.slots = compact;
    gameEvents.emit('inventory.changed', {});
    return true;
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
