import type { CraftingSite, CraftingStation, RecipeDef } from './types';

export const RECIPE_CATALOG: readonly RecipeDef[] = [
  // The one recipe craftable anywhere (C): every wood and stone recipe needs a placed workbench.
  {
    id: 'craft-workbench', name: 'Workbench', station: 'portable', tier: 1,
    description: 'A placeable crafting station. Place it from the inventory, then press F at it to craft tools and weapons.',
    ingredients: [{ itemId: 'wood', count: 40 }], output: { itemId: 'workbench', count: 1 },
  },
  {
    id: 'craft-wooden-spear', name: 'Wooden Spear', station: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'A light starter weapon with a visible golden thrust.',
    ingredients: [{ itemId: 'wood', count: 20 }], output: { itemId: 'wooden-spear', count: 1 },
  },
  {
    id: 'craft-stone-axe', name: 'Stone Axe', station: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'Required to harvest trees efficiently.',
    ingredients: [{ itemId: 'wood', count: 10 }, { itemId: 'stone', count: 10 }], output: { itemId: 'stone-axe', count: 1 },
  },
  {
    id: 'craft-stone-pickaxe', name: 'Stone Pickaxe', station: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'Required to break stone resource nodes.',
    ingredients: [{ itemId: 'wood', count: 10 }, { itemId: 'stone', count: 10 }], output: { itemId: 'stone-pickaxe', count: 1 },
  },
  {
    id: 'craft-stone-spear', name: 'Stone Spear', station: 'workbench', tier: 1, uniqueOutput: true, learnedByQuest: true,
    description: 'A stronger spear with a cool stone-blue thrust.',
    ingredients: [{ itemId: 'wood', count: 20 }, { itemId: 'stone', count: 20 }], output: { itemId: 'stone-spear', count: 1 },
  },
  // The Workshop's own recipes (it also crafts every workbench recipe). The workbench lists them locked.
  {
    id: 'craft-slam-hammer', name: 'Slam Hammer', station: 'workshop', tier: 1, uniqueOutput: true,
    description: 'A slow, heavy hammer: a short reach, but it knocks enemies far back.',
    ingredients: [{ itemId: 'wood', count: 25 }, { itemId: 'stone', count: 25 }], output: { itemId: 'slam-hammer', count: 1 },
  },
  {
    // Portable so a fresh save can always heal; Lili's side quest teaches it.
    id: 'brew-tonic', name: 'Brew Slime Tonic', station: 'portable', tier: 1,
    description: 'Turn meadow berries into a reliable healing tonic.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 3 }], output: { itemId: 'hp-potion', count: 1 },
  },
  {
    // Portable so a fresh save always has food.
    id: 'cook-berry-basket', name: 'Berry Basket', station: 'portable', tier: 1,
    description: 'A little woven basket of berries. Eat it for a quick boost of health and energy.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 2 }, { itemId: 'wood', count: 5 }], output: { itemId: 'berry-basket', count: 1 },
  },
  // Parked for the Kitchen (after Release 1): no station crafts them before then.
  {
    id: 'brew-fizzy', name: 'Brew Fizzy Brew', station: 'kitchen', tier: 1,
    description: 'Charge berry juice with crystal shards for energy recovery.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 2 }, { itemId: 'shard', count: 1 }], output: { itemId: 'energy-potion', count: 1 },
  },
  {
    id: 'weave-tonics', name: 'Sticky Field Kit', station: 'kitchen', tier: 1,
    description: 'Use spider-silk binding to pack two tonics.',
    ingredients: [{ itemId: 'purple-berry-mat', count: 2 }, { itemId: 'silk-clump', count: 2 }], output: { itemId: 'hp-potion', count: 2 },
  },
] as const;

/** Crafting anywhere with C. */
export const PORTABLE_SITE: CraftingSite = Object.freeze({ station: 'portable', tier: 1 });

/** Stations that also craft another station's recipes ("the Workshop crafts everything the workbench does"). */
const STATION_INCLUDES: Readonly<Record<CraftingStation, readonly CraftingStation[]>> = {
  portable: [],
  workbench: [],
  workshop: ['workbench'],
  forge: [],
  kitchen: [],
};

const STATION_NAMES: Readonly<Record<CraftingStation, string>> = {
  portable: 'Crafting',
  workbench: 'Workbench',
  workshop: 'Workshop',
  forge: 'Forge',
  kitchen: 'Kitchen',
};

export function isCraftingStation(value: unknown): value is CraftingStation {
  return typeof value === 'string' && Object.hasOwn(STATION_NAMES, value);
}

export function stationName(station: CraftingStation): string {
  return STATION_NAMES[station];
}

/** The crafting popup title for a site: "Crafting", "Workbench", "Workshop · Tier 2". */
export function siteTitle(site: CraftingSite): string {
  return site.tier > 1 ? `${STATION_NAMES[site.station]} · Tier ${site.tier}` : STATION_NAMES[site.station];
}

/** Whether a station crafts another station's recipes too (a Workshop does a workbench's). */
export function stationServes(station: CraftingStation, recipeStation: CraftingStation): boolean {
  return recipeStation === station || STATION_INCLUDES[station].includes(recipeStation);
}

/** Whether a station crafts a recipe at all (at some tier). */
export function stationCrafts(station: CraftingStation, recipe: RecipeDef): boolean {
  return stationServes(station, recipe.station);
}

/** Stations that build on this one (the Workshop builds on the workbench). */
function upgradesOf(station: CraftingStation): readonly CraftingStation[] {
  return (Object.keys(STATION_INCLUDES) as CraftingStation[]).filter((other) => STATION_INCLUDES[other].includes(station));
}

/**
 * Every recipe a site lists, lowest tier first and the station's own recipes before
 * the ones it shares (a Workshop lists its own, then the workbench's), including
 * recipes above its tier (shown locked). Last come the tier-1 recipes of the
 * stations that build on it, shown locked as "At the Workshop" so the player
 * knows where to go.
 */
export function recipesAt(site: CraftingSite): readonly RecipeDef[] {
  const upgrades = upgradesOf(site.station);
  const indexed = RECIPE_CATALOG.map((recipe, index) => ({ recipe, index }));
  const own = indexed.filter(({ recipe }) => stationCrafts(site.station, recipe));
  const teasers = indexed.filter(({ recipe }) => upgrades.includes(recipe.station) && recipe.tier === 1);
  const shared = (recipe: RecipeDef) => (recipe.station === site.station ? 0 : 1);
  const order = (a: { recipe: RecipeDef; index: number }, b: { recipe: RecipeDef; index: number }) => (
    a.recipe.tier - b.recipe.tier || shared(a.recipe) - shared(b.recipe) || a.index - b.index
  );
  return [...own.sort(order), ...teasers.sort(order)].map(({ recipe }) => recipe);
}
