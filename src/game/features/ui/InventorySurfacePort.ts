import type { JsonValue } from '../../content/scenes/types';
import { gameEvents } from '../../core/EventBus';
import { WEAPON_HOTBAR_SLOT_COUNT } from '../../core/types';
import { playerInventory, itemRegistry, weaponItemFor } from '../../systems/Inventory';
import { playerWeaponLoadout } from '../../systems/WeaponLoadout';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface InventorySurfaceActions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly onPausedChange: (paused: boolean) => void;
  readonly onUseItem: (itemId: string) => void;
  /** Starts placing a furniture item from the inventory. */
  readonly onPlaceItem: (itemId: string) => void;
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
    const belt = playerWeaponLoadout.slots();
    const inHand = playerWeaponLoadout.equippedWeaponId();
    const assignedIndex = equipment ? belt.indexOf(equipment.weaponId) : -1;
    const equipped = equipment ? inHand === equipment.weaponId : false;
    const effects = def?.use ? [
      def.use.healHp ? `Heal HP +${def.use.healHp}` : '',
      def.use.healEnergy ? `Energy +${def.use.healEnergy}` : '',
      def.use.cureStatus?.length ? `Cures ${def.use.cureStatus.join(', ')}` : '',
    ].filter(Boolean).join(' · ') : '';
    const status = !def || !slot ? { text: '', color: STATUS_COLOR.muted }
      : equipment ? equipped
        ? { text: `In your hand · belt slot ${assignedIndex + 1}`, color: STATUS_COLOR.inHand }
        : assignedIndex >= 0
          ? { text: `On belt slot ${assignedIndex + 1} · not in your hand`, color: STATUS_COLOR.onBelt }
          : { text: 'In the bag · not on your belt', color: STATUS_COLOR.muted }
        : { text: `${capitalize(def.category)} · ${slot.count} in the bag`, color: STATUS_COLOR.muted };
    const width = Math.min(1000, Math.max(320, this.actions.uiRoot.clientWidth - 32));
    const height = Math.min(640, Math.max(1, this.actions.uiRoot.clientHeight - 32));
    return {
      open: this.openValue,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      belt: belt.map((weaponId, index) => {
        const item = weaponId && playerWeaponLoadout.ownsWeapon(weaponId) ? weaponItemFor(weaponId) : undefined;
        return {
          id: `belt-${index + 1}`,
          label: item ? item.name : `Slot ${index + 1}\nEmpty`,
          ...(item ? { metadata: { iconKey: item.icon, iconFrame: item.iconFrame ?? 0, showLabel: true, shortcut: String(index + 1), draggable: true } } : {}),
        };
      }),
      beltSelectedIndex: inHand ? belt.indexOf(inHand) : -1,
      items: Array.from({ length: playerInventory.maxSlots() }, (_, index) => {
        const stack = slots[index];
        const item = stack ? itemRegistry.get(stack.itemId) : undefined;
        // Weapons say where they are: in hand, on a belt slot, or nothing (only in the bag).
        const beltIndex = item?.equipment ? belt.indexOf(item.equipment.weaponId) : -1;
        const tag = item?.equipment
          ? item.equipment.weaponId === inHand ? 'in hand' : beltIndex >= 0 ? `belt ${beltIndex + 1}` : ''
          : stack && stack.count > 1 ? `×${stack.count}` : '';
        return {
          id: `slot-${index + 1}`,
          label: item ? item.name : 'Empty',
          disabled: !item,
          ...(item ? {
            metadata: {
              iconKey: item.icon,
              iconFrame: item.iconFrame ?? 0,
              showLabel: true,
              shortcut: tag,
              ...(item.equipment ? { draggable: true } : {}),
            },
          } : {}),
        };
      }),
      selectedIndex: this.selectedSlotIndex ?? -1,
      detailsName: def ? def.name : 'Your bag is empty',
      detailsStatus: status.text,
      detailsStatusColor: status.color,
      details: def && slot ? [
        def.description,
        ...(effects ? ['', effects] : []),
      ].join('\n') : 'Pick things up in the world and they land here.',
      quantity: `Quantity: ${this.quantity}`,
      primaryLabel: equipment ? (equipped ? 'In your hand' : 'Hold in hand') : def?.placeable ? 'Place' : 'Use',
      primaryDisabled: !def || equipped || (!equipment && !def.use && !def.placeable),
      hotbarVisible: !!equipment,
      hotbarSlots: belt.map((weaponId, index) => {
        const item = weaponId && playerWeaponLoadout.ownsWeapon(weaponId) ? weaponItemFor(weaponId) : undefined;
        return { id: `assign-${index + 1}`, label: `${index + 1}: ${item?.name ?? 'empty'}` };
      }),
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
    if (actionId === 'hold-belt-slot') {
      // A belt slot click holds that weapon and shows it in the details.
      const index = selectionIndex(payload);
      const weaponId = index === undefined ? null : playerWeaponLoadout.weaponAt(index);
      if (weaponId) {
        this.selectItemById(weaponItemFor(weaponId)?.id);
        this.actions.onEquipWeapon(weaponId);
      }
      this.publish();
      return;
    }
    if (actionId === 'drop-on-belt') {
      const drop = beltDrop(payload);
      const weaponId = drop ? this.draggedWeaponId(drop.sourceItemId, drop.sourceIndex) : undefined;
      if (drop && weaponId) {
        this.selectItemById(weaponItemFor(weaponId)?.id);
        this.actions.onAssignWeapon(weaponId, drop.index);
      }
      this.publish();
      return;
    }
    const selected =this.selectedSlotIndex === undefined ? undefined : playerInventory.getSlots()[this.selectedSlotIndex];
    if (!selected || selected.itemId !== this.selectedItemId) return;
    const def = itemRegistry.get(selected.itemId);
    if (!def) return;
    if (actionId === 'use-or-equip') {
      if (def.equipment) this.actions.onEquipWeapon(def.equipment.weaponId);
      else if (def.placeable) {
        this.close();
        this.actions.onPlaceItem(def.id);
        return;
      } else if (def.use) this.actions.onUseItem(def.id);
    } else if (actionId === 'assign-slot' && def.equipment) {
      const index = selectionIndex(payload);
      if (index !== undefined && index >= 0 && index < WEAPON_HOTBAR_SLOT_COUNT) this.actions.onAssignWeapon(def.equipment.weaponId, index);
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

  /** The weapon behind a dragged bag slot (`slot-N`) or belt slot (`belt-N`). */
  private draggedWeaponId(sourceItemId: string, sourceIndex: number): string | undefined {
    if (sourceItemId.startsWith('belt-')) return playerWeaponLoadout.weaponAt(sourceIndex) ?? undefined;
    if (!sourceItemId.startsWith('slot-')) return undefined;
    const stack = playerInventory.getSlots()[sourceIndex];
    return stack ? itemRegistry.get(stack.itemId)?.equipment?.weaponId : undefined;
  }

  private selectItemById(itemId: string | undefined): void {
    const index = itemId ? playerInventory.getSlots().findIndex((stack) => stack?.itemId === itemId) : -1;
    if (index < 0) return;
    this.selectedSlotIndex = index;
    this.selectedItemId = itemId;
    this.quantity = 1;
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

/** Status line colors: the weapon in hand (gold), on the belt (green), anything else (muted). */
const STATUS_COLOR = { inHand: '#ffd277', onBelt: '#86f0c3', muted: '#a9c4b4' } as const;

function capitalize(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function beltDrop(payload: JsonValue | undefined): { index: number; sourceItemId: string; sourceIndex: number } | undefined {
  const index = selectionIndex(payload);
  if (index === undefined || index >= WEAPON_HOTBAR_SLOT_COUNT) return undefined;
  const record = payload as Readonly<Record<string, JsonValue>>;
  const { sourceItemId, sourceIndex } = record;
  if (typeof sourceItemId !== 'string' || typeof sourceIndex !== 'number' || !Number.isSafeInteger(sourceIndex) || sourceIndex < 0) return undefined;
  return { index, sourceItemId, sourceIndex };
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
