import { playerInventory, itemRegistry } from '../systems/Inventory';

export interface RecipeIngredient {
  itemId: string;
  count: number;
}

export interface RecipeDef {
  id: string;
  name: string;
  description: string;
  ingredients: RecipeIngredient[];
  output: RecipeIngredient;
}

export const RECIPES: readonly RecipeDef[] = [
  {
    id: 'brew-tonic',
    name: 'Brew Slime Tonic',
    description: 'Turn meadow berries into a reliable healing tonic.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 3 }],
    output: { itemId: 'hp-potion', count: 1 },
  },
  {
    id: 'brew-fizzy',
    name: 'Brew Fizzy Brew',
    description: 'Charge berry juice with crystal shards for energy recovery.',
    ingredients: [
      { itemId: 'purple-berry-mat', count: 2 },
      { itemId: 'shard', count: 1 },
    ],
    output: { itemId: 'energy-potion', count: 1 },
  },
  {
    id: 'weave-tonics',
    name: 'Sticky Field Kit',
    description: 'Use spider-silk binding to pack two tonics for longer trips.',
    ingredients: [
      { itemId: 'purple-berry-mat', count: 2 },
      { itemId: 'silk-clump', count: 2 },
    ],
    output: { itemId: 'hp-potion', count: 2 },
  },
] as const;

export function canCraft(recipe: RecipeDef): boolean {
  return recipe.ingredients.every((i) => playerInventory.count(i.itemId) >= i.count);
}

export function craft(recipe: RecipeDef): boolean {
  if (!canCraft(recipe)) return false;

  for (const ingredient of recipe.ingredients) {
    playerInventory.remove(ingredient.itemId, ingredient.count);
  }

  return playerInventory.add(recipe.output.itemId, recipe.output.count) === recipe.output.count;
}

export function itemName(itemId: string): string {
  return itemRegistry.get(itemId)?.name ?? itemId;
}
