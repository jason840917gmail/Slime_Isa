import type { JsonValue } from '../../content/scenes/types';
import { gameEvents } from '../../core/EventBus';
import { playerInventory, itemRegistry } from '../../systems/Inventory';
import { playerWeaponLoadout } from '../../systems/WeaponLoadout';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface InventorySurfaceActions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly onPausedChange: (paused: boolean) => void;
  readonly onUseItem: (itemId: string) => void;
  readonly onEquipWeapon: (weaponId: string) => void;
  readonly onAssignWeapon: (weaponId: string, slotIndex: number) => void;
  readonly canDropItem: (itemId: string) => boolean;
  readonly onDropItem: (slotIndex: number, quantity: number) => boolean;
}

/** Domain and modal owner for the authored inventory Control scene. */
export class InventorySurfacePort implements UiSurfacePort {
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly modalHandle: ModalHandle;
  private readonly resizeObserver: ResizeObserver;
  private selectedSlotIndex?: number;
  private selectedItemId?: string;
  private quantity = 1;
  private openValue = false;
  private stopped = false;

  constructor(private readonly actions: InventorySurfaceActions) {
    this.modalHandle = actions.modalStack.register('inventory', {
      isOpen: () => this.isOpen(),
      close: () => this.close(),
    });
    gameEvents.on('inventory.changed', this.publish, this);
    gameEvents.on('weapon.loadout.changed', this.publish, this);
    gameEvents.on('weapon.equipped', this.publish, this);
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(actions.uiRoot);
  }

  isOpen(): boolean { return this.openValue; }
  toggle(): void { if (this.openValue) this.close(); else this.open(); }

  open(): void {
    if (this.stopped || this.openValue) return;
    this.ensureSelectedItem();
    this.openValue = true;
    this.actions.onPausedChange(true);
    this.modalHandle.open();
    this.publish();
  }

  close(): void {
    if (!this.openValue) { this.modalHandle.close(); return; }
    this.openValue = false;
    this.modalHandle.close();
    this.actions.onPausedChange(false);
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'inventory-ui' || this.stopped) return {};
    this.ensureSelectedItem();
    const slots = playerInventory.getSlots();
    const slot = this.selectedSlotIndex === undefined ? undefined : slots[this.selectedSlotIndex];
    const def = slot ? itemRegistry.get(slot.itemId) : undefined;
    const equipment = def?.equipment;
    const assignedIndex = equipment ? playerWeaponLoadout.slots().indexOf(equipment.weaponId) : -1;
    const equipped = equipment ? playerWeaponLoadout.equippedWeaponId() === equipment.weaponId : false;
    const effects = def?.use ? [
      def.use.healHp ? `Heal HP +${def.use.healHp}` : '',
      def.use.healEnergy ? `Energy +${def.use.healEnergy}` : '',
      def.use.cureStatus?.length ? `Cures ${def.use.cureStatus.join(', ')}` : '',
    ].filter(Boolean).join(' · ') : '';
    const width = Math.min(1000, Math.max(320, this.actions.uiRoot.clientWidth - 32));
    const height = Math.min(640, Math.max(1, this.actions.uiRoot.clientHeight - 32));
    return {
      open: this.openValue,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      items: Array.from({ length: playerInventory.maxSlots() }, (_, index) => {
        const stack = slots[index];
        const item = stack ? itemRegistry.get(stack.itemId) : undefined;
        return {
          id: `slot-${index + 1}`,
          label: item ? `${item.name}${stack!.count > 1 ? ` ×${stack!.count}` : ''}` : 'Empty',
          disabled: !item,
          ...(item ? { metadata: { iconKey: item.icon, iconFrame: item.iconFrame ?? 0, shortcut: stack!.count > 1 ? String(stack!.count) : '' } } : {}),
        };
      }),
      selectedIndex: this.selectedSlotIndex ?? -1,
      details: def && slot ? [
        def.name,
        `${def.category} · x${slot.count}`,
        '',
        def.description,
        ...(equipment ? ['', equipped ? 'EQUIPPED' : assignedIndex >= 0 ? `HOTBAR SLOT ${assignedIndex + 1}` : 'NOT ON HOTBAR', 'Assign number key below.'] : []),
        ...(effects ? ['', effects] : []),
      ].join('\n') : 'Select an item',
      quantity: `Quantity: ${this.quantity}`,
      primaryLabel: equipment ? 'Equip Now' : 'Use',
      primaryDisabled: !def || (!equipment && !def.use),
      hotbarVisible: !!equipment,
      hotbarSlots: Array.from({ length: 5 }, (_, index) => ({ id: `assign-${index + 1}`, label: `${index + 1}` })),
      hotbarSelectedIndex: assignedIndex,
      quantityVisible: !!def && !equipment,
      actionsVisible: !!def && !equipment,
      dropDisabled: !def || !!equipment || !this.actions.canDropItem(def.id),
      removeDisabled: !def || !!equipment,
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'inventory-ui' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (this.stopped || surfaceId !== 'inventory-ui') return;
    if (actionId === 'close') { this.close(); return; }
    if (!this.openValue) return;
    if (actionId === 'select-item') {
      const index = selectionIndex(payload);
      const slot = index === undefined ? undefined : playerInventory.getSlots()[index];
      if (!slot) return;
      this.selectedSlotIndex = index;
      this.selectedItemId = slot.itemId;
      this.quantity = 1;
      this.publish();
      return;
    }
    const selected = this.selectedSlotIndex === undefined ? undefined : playerInventory.getSlots()[this.selectedSlotIndex];
    if (!selected || selected.itemId !== this.selectedItemId) return;
    const def = itemRegistry.get(selected.itemId);
    if (!def) return;
    if (actionId === 'use-or-equip') {
      if (def.equipment) this.actions.onEquipWeapon(def.equipment.weaponId);
      else if (def.use) this.actions.onUseItem(def.id);
    } else if (actionId === 'assign-slot' && def.equipment) {
      const index = selectionIndex(payload);
      if (index !== undefined && index >= 0 && index < 5) this.actions.onAssignWeapon(def.equipment.weaponId, index);
    } else if (actionId === 'quantity-minus-10') this.adjustQuantity(-10, selected.count);
    else if (actionId === 'quantity-minus-1') this.adjustQuantity(-1, selected.count);
    else if (actionId === 'quantity-plus-1') this.adjustQuantity(1, selected.count);
    else if (actionId === 'quantity-plus-10') this.adjustQuantity(10, selected.count);
    else if ((actionId === 'drop' || actionId === 'drop-all') && !def.equipment && this.actions.canDropItem(def.id)) {
      this.actions.onDropItem(this.selectedSlotIndex!, actionId === 'drop-all' ? selected.count : this.quantity);
      this.close();
    } else if ((actionId === 'remove' || actionId === 'remove-all') && !def.equipment) {
      const amount = actionId === 'remove-all' ? selected.count : this.quantity;
      const slotIndex = this.selectedSlotIndex!;
      if (amount >= selected.count) { this.selectedSlotIndex = undefined; this.selectedItemId = undefined; this.quantity = 1; }
      else this.quantity = Math.min(this.quantity, selected.count - amount);
      playerInventory.removeFromSlot(slotIndex, amount);
    }
    this.publish();
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    this.resizeObserver.disconnect();
    gameEvents.off('inventory.changed', this.publish, this);
    gameEvents.off('weapon.loadout.changed', this.publish, this);
    gameEvents.off('weapon.equipped', this.publish, this);
    this.modalHandle.unregister();
    this.listeners.clear();
  }

  private adjustQuantity(delta: number, available: number): void {
    this.quantity = Math.max(1, Math.min(available, this.quantity + delta));
  }

  private ensureSelectedItem(): void {
    const slots = playerInventory.getSlots();
    const selected = this.selectedSlotIndex === undefined ? undefined : slots[this.selectedSlotIndex];
    if (selected && selected.itemId === this.selectedItemId) {
      this.quantity = Math.max(1, Math.min(this.quantity, selected.count));
      return;
    }
    this.selectedSlotIndex = slots.length ? 0 : undefined;
    this.selectedItemId = slots[0]?.itemId;
    this.quantity = 1;
  }

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('inventory-ui');
    for (const listener of this.listeners) listener(model);
  };
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
