import { WEAPON_HOTBAR_SLOT_COUNT } from './types';

/**
 * A saved weapon belt fitted to `WEAPON_HOTBAR_SLOT_COUNT` slots. A belt from
 * an older save (six slots, then three) that holds more weapons than fit
 * keeps the equipped weapon and the filled slots after it, in belt order and
 * wrapping around; the rest stay owned in the bag, so nothing is lost.
 */
export function fitWeaponSlots(value: unknown, equippedWeaponId: string | null = null): Array<string | null> {
  const input = Array.isArray(value) ? value : [];
  const entries = input.map((entry): string | null => (typeof entry === 'string' && entry.trim().length > 0 ? entry : null));
  const fitted: Array<string | null> = Array.from({ length: WEAPON_HOTBAR_SLOT_COUNT }, (_, index) => entries[index] ?? null);
  const filled = entries.filter((entry): entry is string => entry !== null);
  if (filled.every((weaponId) => fitted.includes(weaponId))) return fitted;

  // Too many to keep their places: pack them, starting from the equipped weapon.
  const start = Math.max(0, equippedWeaponId ? filled.indexOf(equippedWeaponId) : 0);
  const kept = Array.from({ length: Math.min(filled.length, WEAPON_HOTBAR_SLOT_COUNT) }, (_, offset) => filled[(start + offset) % filled.length]!);
  return Array.from({ length: WEAPON_HOTBAR_SLOT_COUNT }, (_, index) => kept[index] ?? null);
}
