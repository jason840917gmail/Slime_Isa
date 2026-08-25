import type { CraftingContext, RecipeDef } from './types';

export const RECIPE_CATALOG: readonly RecipeDef[] = [
  {
    id: 'craft-wooden-spear', name: 'Wooden Spear', context: 'portable', tier: 1, uniqueOutput: true,
    description: 'A light starter weapon with a visible golden thrust.',
    ingredients: [{ itemId: 'wood', count: 20 }], output: { itemId: 'wooden-spear', count: 1 },
  },
  {
    id: 'craft-stone-axe', name: 'Stone Axe', context: 'portable', tier: 1, uniqueOutput: true,
    description: 'Required to harvest trees efficiently.',
    ingredients: [{ itemId: 'wood', count: 10 }, { itemId: 'stone', count: 10 }], output: { itemId: 'stone-axe', count: 1 },
  },
  {
    id: 'craft-stone-pickaxe', name: 'Stone Pickaxe', context: 'portable', tier: 1, uniqueOutput: true,
    description: 'Required to break stone resource nodes.',
    ingredients: [{ itemId: 'wood', count: 10 }, { itemId: 'stone', count: 10 }], output: { itemId: 'stone-pickaxe', count: 1 },
  },
  {
    id: 'craft-stone-spear', name: 'Stone Spear', context: 'portable', tier: 1, uniqueOutput: true,
    description: 'A stronger spear with a cool stone-blue thrust.',
    ingredients: [{ itemId: 'wood', count: 20 }, { itemId: 'stone', count: 20 }], output: { itemId: 'stone-spear', count: 1 },
  },
  {
    id: 'brew-tonic', name: 'Brew Slime Tonic', context: 'alchemy', tier: 1,
    description: 'Turn meadow berries into a reliable healing tonic.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 3 }], output: { itemId: 'hp-potion', count: 1 },
  },
  {
    id: 'brew-fizzy', name: 'Brew Fizzy Brew', context: 'alchemy', tier: 1,
    description: 'Charge berry juice with crystal shards for energy recovery.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 2 }, { itemId: 'shard', count: 1 }], output: { itemId: 'energy-potion', count: 1 },
  },
  {
    id: 'weave-tonics', name: 'Sticky Field Kit', context: 'alchemy', tier: 1,
    description: 'Use spider-silk binding to pack two tonics.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 2 }, { itemId: 'silk-clump', count: 2 }], output: { itemId: 'hp-potion', count: 2 },
  },
] as const;

export function recipesFor(context: CraftingContext, tier = 1): readonly RecipeDef[] {
  return RECIPE_CATALOG.filter((recipe) => recipe.context === context && recipe.tier <= tier);
}
