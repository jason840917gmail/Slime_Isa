import type { ItemDef } from '../../core/types';
import { weaponDefinitions } from 'virtual-weapon-content';
import itemsJson from './items.json';

const BASE_ITEMS = itemsJson as unknown as Readonly<Record<string, ItemDef>>;
const KNOWN_ITEM_IDS = new Set([
  ...Object.keys(BASE_ITEMS),
  ...weaponDefinitions.flatMap((weapon) => typeof weapon.weaponId === 'string' ? [weapon.weaponId] : []),
]);

export function getBaseItemDefinitions(): Readonly<Record<string, ItemDef>> {
  return BASE_ITEMS;
}

export function isKnownItemId(itemId: string): boolean {
  return KNOWN_ITEM_IDS.has(itemId);
}

export function getKnownItemIds(): readonly string[] {
  return [...KNOWN_ITEM_IDS].sort();
}
