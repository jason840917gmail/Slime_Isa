import { recipesFor } from '../content/recipes/RecipeCatalog';
import type { RecipeDef } from '../content/recipes/types';
import { playerInventory, itemRegistry } from '../systems/Inventory';

export type { RecipeDef, RecipeIngredient } from '../content/recipes/types';

export const RECIPES: readonly RecipeDef[] = recipesFor('portable');

export function canCraft(recipe: RecipeDef): boolean {
  if (recipe.uniqueOutput && playerInventory.count(recipe.output.itemId) > 0) return false;
  return recipe.ingredients.every((ingredient) => playerInventory.count(ingredient.itemId) >= ingredient.count);
}

export function craft(recipe: RecipeDef): boolean {
  if (!canCraft(recipe)) return false;
  return playerInventory.transact(recipe.ingredients, [recipe.output]);
}

export function itemName(itemId: string): string {
  return itemRegistry.get(itemId)?.name ?? itemId;
}
