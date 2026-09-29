import type { CraftingContext, RecipeDef } from './types';

export const RECIPE_CATALOG: readonly RecipeDef[] = [
  // The one recipe craftable anywhere (C): every wood and stone recipe needs a placed workbench.
  {
    id: 'craft-workbench', name: 'Workbench', context: 'portable', tier: 1,
    description: 'A placeable crafting station. Place it from the inventory, then press F at it to craft tools and weapons.',
    ingredients: [{ itemId: 'wood', count: 40 }], output: { itemId: 'workbench', count: 1 },
  },
  {
    id: 'craft-wooden-spear', name: 'Wooden Spear', context: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'A light starter weapon with a visible golden thrust.',
    ingredients: [{ itemId: 'wood', count: 20 }], output: { itemId: 'wooden-spear', count: 1 },
  },
  {
    id: 'craft-stone-axe', name: 'Stone Axe', context: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'Required to harvest trees efficiently.',
    ingredients: [{ itemId: 'wood', count: 10 }, { itemId: 'stone', count: 10 }], output: { itemId: 'stone-axe', count: 1 },
  },
  {
    id: 'craft-stone-pickaxe', name: 'Stone Pickaxe', context: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'Required to break stone resource nodes.',
    ingredients: [{ itemId: 'wood', count: 10 }, { itemId: 'stone', count: 10 }], output: { itemId: 'stone-pickaxe', count: 1 },
  },
  {
    id: 'craft-stone-spear', name: 'Stone Spear', context: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'A stronger spear with a cool stone-blue thrust.',
    ingredients: [{ itemId: 'wood', count: 20 }, { itemId: 'stone', count: 20 }], output: { itemId: 'stone-spear', count: 1 },
  },
  {
    // Portable until the Kitchen (Milestone 10) owns potions; Lili's side quest teaches it.
    id: 'brew-tonic', name: 'Brew Slime Tonic', context: 'portable', tier: 1,
    description: 'Turn meadow berries into a reliable healing tonic.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 3 }], output: { itemId: 'hp-potion', count: 1 },
  },
  {
    // Portable until the Kitchen (Milestone 9) owns food.
    id: 'cook-berry-basket', name: 'Berry Basket', context: 'portable', tier: 1,
    description: 'A little woven basket of berries. Eat it for a quick boost of health and energy.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 2 }, { itemId: 'wood', count: 5 }], output: { itemId: 'berry-basket', count: 1 },
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
