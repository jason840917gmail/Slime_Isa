import type { ItemDef } from '../../core/types';
import { GAME_CONSTANTS } from '../../Constant';
import { weaponDefinitions } from 'virtual-weapon-content';
import itemsJson from './items.json';

type BaseItemInput = Omit<ItemDef, 'maxStack'>;

const BASE_ITEM_INPUTS = itemsJson as unknown as Readonly<Record<string, BaseItemInput>>;
const inputIds = Object.keys(BASE_ITEM_INPUTS).sort();
const configuredIds = Object.keys(GAME_CONSTANTS.inventory.maxStackByItem).sort();
if (inputIds.length !== configuredIds.length || inputIds.some((itemId, index) => itemId !== configuredIds[index])) {
  throw new Error(`Base item stack configuration mismatch: items=[${inputIds.join(', ')}], configured=[${configuredIds.join(', ')}]`);
}

const BASE_ITEMS: Readonly<Record<string, ItemDef>> = Object.fromEntries(inputIds.map((itemId) => {
  const input = BASE_ITEM_INPUTS[itemId];
  if (input.id !== itemId) throw new Error(`Base item '${itemId}' must use the same embedded id`);
  return [itemId, { ...input, maxStack: GAME_CONSTANTS.inventory.maxStackByItem[itemId] }];
}));
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
