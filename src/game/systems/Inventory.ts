import { gameEvents } from '../core/EventBus';
import type { InventorySlot, ItemDef } from '../core/types';
import { getWeaponDefinitions } from '../content/weapons/WeaponCatalog';

/**
 * Slot-based inventory with categories + stacking.
 *
 * Item definitions live in a registry (registered by BootScene/data loader);
 * the inventory only stores itemId + count. This keeps saves small and
 * content-driven.
 */

const MAX_SLOTS = 24;

const DEFAULT_DEFS: Record<string, ItemDef> = {
  'hp-potion': {
    id: 'hp-potion',
    name: 'Slime Tonic',
    category: 'consumable',
    icon: 'hp-potion',
    description: 'Restores 40 HP.',
    maxStack: 9,
    use: { healHp: 40 },
  },
  'energy-potion': {
    id: 'energy-potion',
    name: 'Fizzy Brew',
    category: 'consumable',
    icon: 'energy-potion',
    description: 'Restores 50 energy.',
    maxStack: 9,
    use: { healEnergy: 50 },
  },
  'purple-berry-mat': {
    id: 'purple-berry-mat',
    name: 'Purple Berry',
    category: 'material',
    icon: 'purple-berry',
    description: 'A sweet foraged berry. Used in brewing.',
    maxStack: 99,
  },
  'silk-clump': {
    id: 'silk-clump',
    name: 'Sticky Silk',
    category: 'material',
    icon: 'silk-clump',
    description: 'Clumpy silk from a spider-slime.',
    maxStack: 99,
  },
  'shard': {
    id: 'shard',
    name: 'Crystal Shard',
    category: 'collectible',
    icon: 'shard',
    description: 'A glittering crystal. Could power something.',
    maxStack: 99,
  },
};

class ItemRegistryImpl {
  private defs: Record<string, ItemDef> = { ...DEFAULT_DEFS };

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
    description: weapon.description,
    maxStack: 1,
    equipment: { weaponId: weapon.weaponId },
  });
}

export function weaponItemFor(weaponId: string): ItemDef | undefined {
  return itemRegistry.all().find((item) => item.equipment?.weaponId === weaponId);
}

export class Inventory {
  private slots: InventorySlot[] = [];

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
    while (remaining > 0 && this.slots.length < MAX_SLOTS) {
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
    return MAX_SLOTS;
  }

  serialize(): InventorySlot[] {
    return this.slots.map((s) => ({ ...s }));
  }

  load(slots: InventorySlot[]): void {
    this.slots = slots.map((s) => ({ ...s }));
    gameEvents.emit('inventory.changed', {});
  }

  clear(): void {
    this.slots = [];
    gameEvents.emit('inventory.changed', {});
  }
}

export const playerInventory = new Inventory();
