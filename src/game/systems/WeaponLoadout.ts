import { getWeaponDefinition } from '../content/weapons/WeaponCatalog';
import { gameState } from '../core/GameState';
import { WEAPON_HOTBAR_SLOT_COUNT } from '../core/types';
import { playerInventory, weaponItemFor } from './Inventory';

export const STARTER_WEAPON_IDS = ['goo-gauntlet', 'basic-sword'] as const;

export type WeaponEquipFailure = 'empty' | 'not-owned' | 'busy' | 'unknown';

export type WeaponEquipResult =
  | { readonly ok: true; readonly weaponId: string; readonly changed: boolean }
  | { readonly ok: false; readonly reason: WeaponEquipFailure };

export interface WeaponAssignmentResult {
  readonly ok: boolean;
  readonly equipAssignedWeapon: boolean;
}

class WeaponLoadout {
  slots(): readonly (string | null)[] {
    return gameState.weaponSlots;
  }

  equippedWeaponId(): string {
    return gameState.equippedWeaponId;
  }

  ownsWeapon(weaponId: string): boolean {
    const item = weaponItemFor(weaponId);
    return !!item && playerInventory.count(item.id) > 0;
  }

  weaponAt(slotIndex: number): string | null {
    if (!Number.isInteger(slotIndex) || slotIndex < 0 || slotIndex >= WEAPON_HOTBAR_SLOT_COUNT) return null;
    const weaponId = gameState.weaponSlots[slotIndex];
    return weaponId && this.ownsWeapon(weaponId) ? weaponId : null;
  }

  initializeStarterLoadout(): void {
    for (const weaponId of STARTER_WEAPON_IDS) {
      const item = weaponItemFor(weaponId);
      if (item && playerInventory.count(item.id) <= 0) playerInventory.add(item.id, 1);
    }
    this.reconcile();
  }

  reconcile(): void {
    const slots = Array.from({ length: WEAPON_HOTBAR_SLOT_COUNT }, (_, index) => {
      const weaponId = gameState.weaponSlots[index];
      return weaponId && this.ownsWeapon(weaponId) ? weaponId : null;
    });
    const seen = new Set<string>();
    for (let index = 0; index < slots.length; index += 1) {
      const weaponId = slots[index];
      if (!weaponId) continue;
      if (seen.has(weaponId)) slots[index] = null;
      else seen.add(weaponId);
    }

    for (const weaponId of STARTER_WEAPON_IDS) {
      if (!this.ownsWeapon(weaponId) || seen.has(weaponId)) continue;
      const emptyIndex = slots.indexOf(null);
      if (emptyIndex < 0) break;
      slots[emptyIndex] = weaponId;
      seen.add(weaponId);
    }

    const equipped = gameState.equippedWeaponId;
    if (this.ownsWeapon(equipped) && !seen.has(equipped)) {
      const emptyIndex = slots.indexOf(null);
      if (emptyIndex >= 0) slots[emptyIndex] = equipped;
    }
    gameState.setWeaponSlots(slots);

    if (!this.ownsWeapon(equipped)) {
      const fallback = slots.find((weaponId): weaponId is string => !!weaponId && this.ownsWeapon(weaponId));
      if (fallback) gameState.equipWeapon(fallback);
    }
  }

  assignWeapon(slotIndex: number, weaponId: string): WeaponAssignmentResult {
    if (!Number.isInteger(slotIndex) || slotIndex < 0 || slotIndex >= WEAPON_HOTBAR_SLOT_COUNT || !this.ownsWeapon(weaponId)) {
      return { ok: false, equipAssignedWeapon: false };
    }
    try {
      getWeaponDefinition(weaponId);
    } catch {
      return { ok: false, equipAssignedWeapon: false };
    }

    const slots = [...gameState.weaponSlots];
    const previousTarget = slots[slotIndex];
    const previousIndex = slots.indexOf(weaponId);
    if (previousIndex === slotIndex) return { ok: true, equipAssignedWeapon: false };
    if (previousIndex >= 0) slots[previousIndex] = previousTarget;
    slots[slotIndex] = weaponId;
    gameState.setWeaponSlots(slots);
    return {
      ok: true,
      equipAssignedWeapon: previousIndex < 0 && previousTarget === gameState.equippedWeaponId,
    };
  }

  ensureAssigned(weaponId: string): number | null {
    if (!this.ownsWeapon(weaponId)) return null;
    const currentIndex = gameState.weaponSlots.indexOf(weaponId);
    if (currentIndex >= 0) return currentIndex;
    const emptyIndex = gameState.weaponSlots.indexOf(null);
    if (emptyIndex < 0) return null;
    return this.assignWeapon(emptyIndex, weaponId).ok ? emptyIndex : null;
  }

  equipSlot(slotIndex: number, apply: (weaponId: string) => boolean): WeaponEquipResult {
    const weaponId = gameState.weaponSlots[slotIndex];
    if (!weaponId) return { ok: false, reason: 'empty' };
    if (!this.ownsWeapon(weaponId)) return { ok: false, reason: 'not-owned' };
    try {
      getWeaponDefinition(weaponId);
    } catch {
      return { ok: false, reason: 'unknown' };
    }
    if (weaponId === gameState.equippedWeaponId) return { ok: true, weaponId, changed: false };
    if (!apply(weaponId)) return { ok: false, reason: 'busy' };
    gameState.equipWeapon(weaponId);
    return { ok: true, weaponId, changed: true };
  }
}

export const playerWeaponLoadout = new WeaponLoadout();
