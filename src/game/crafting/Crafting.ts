import { recipesFor } from '../content/recipes/RecipeCatalog';
import type { RecipeDef } from '../content/recipes/types';
import { gameEvents } from '../core/EventBus';
import { itemRegistry, playerInventory } from '../systems/Inventory';
import { getWeaponDefinitions } from '../content/weapons/WeaponCatalog';
import { CraftingService } from './CraftingService';

export type { RecipeDef, RecipeIngredient } from '../content/recipes/types';

export const RECIPES: readonly RecipeDef[] = recipesFor('portable');

const craftingService = new CraftingService({
  inventory: playerInventory,
  getItem: (itemId) => itemRegistry.get(itemId),
  getWeapon: (weaponId) => getWeaponDefinitions().find((weapon) => weapon.weaponId === weaponId),
  emitCompleted: (payload) => gameEvents.emit('craft.completed', payload),
});

export { craftingService };

export function canCraft(recipe: RecipeDef): boolean {
  return craftingService.quote(recipe, 1).status === 'ready';
}

export function craft(recipe: RecipeDef): boolean {
  return craftingService.craft(recipe, 1).ok;
}

export function itemName(itemId: string): string {
  return itemRegistry.get(itemId)?.name ?? itemId;
}
