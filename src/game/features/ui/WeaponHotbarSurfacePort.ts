import type { JsonValue } from '../../content/scenes/types';
import { gameEvents } from '../../core/EventBus';
import { WEAPON_HOTBAR_SLOT_COUNT } from '../../core/types';
import { playerWeaponLoadout } from '../../systems/WeaponLoadout';
import { weaponItemFor } from '../../systems/Inventory';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

type ModelListener = (model: UiPresentationModel) => void;

/** Adapts inventory and loadout state to the authored field belt (three slots, switched with the mouse wheel). */
export class WeaponHotbarSurfacePort implements UiSurfacePort {
  private readonly listeners = new Set<ModelListener>();
  private stopped = false;

  constructor(private readonly equipSlot: (slotIndex: number) => void) {
    gameEvents.on('inventory.changed', this.publish, this);
    gameEvents.on('weapon.loadout.changed', this.publish, this);
    gameEvents.on('weapon.equipped', this.publish, this);
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'weapon-hotbar') return {};
    const slots = playerWeaponLoadout.slots();
    const equipped = playerWeaponLoadout.equippedWeaponId();
    return {
      weapons: Array.from({ length: WEAPON_HOTBAR_SLOT_COUNT }, (_, index) => {
        const weaponId = slots[index];
        const owned = !!weaponId && playerWeaponLoadout.ownsWeapon(weaponId);
        const item = weaponId ? weaponItemFor(weaponId) : undefined;
        const name = weaponId ? item?.name ?? weaponId : 'Empty';
        return {
          id: `slot-${index + 1}`,
          label: name,
          disabled: !owned,
          ...(owned && item ? { metadata: { iconKey: item.icon, iconFrame: item.iconFrame ?? 0 } } : {}),
        };
      }),
      selectedIndex: slots.findIndex((weaponId) => !!weaponId && weaponId === equipped && playerWeaponLoadout.ownsWeapon(weaponId)),
    };
  }

  subscribe(surfaceId: string, listener: ModelListener): () => void {
    if (surfaceId !== 'weapon-hotbar' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (this.stopped || surfaceId !== 'weapon-hotbar' || actionId !== 'equip-slot') return;
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return;
    const index = (payload as Readonly<Record<string, JsonValue>>).index;
    if (typeof index !== 'number' || !Number.isInteger(index) || index < 0 || index >= WEAPON_HOTBAR_SLOT_COUNT) return;
    const weaponId = playerWeaponLoadout.slots()[index];
    if (!weaponId || !playerWeaponLoadout.ownsWeapon(weaponId)) return;
    this.equipSlot(index);
    // A busy equip can fail without emitting weapon.equipped. Restore the real selection.
    this.publish();
  }

  destroy(): void {
    if (this.stopped) return;
    this.stopped = true;
    gameEvents.off('inventory.changed', this.publish, this);
    gameEvents.off('weapon.loadout.changed', this.publish, this);
    gameEvents.off('weapon.equipped', this.publish, this);
    this.listeners.clear();
  }

  private readonly publish = (): void => {
    const model = this.snapshot('weapon-hotbar');
    for (const listener of this.listeners) listener(model);
  };
}
