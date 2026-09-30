/**
 * Where a recipe is crafted: anywhere (`portable`, the C key) or at a station.
 * See GAME_GUIDELINES "Crafting And Buildings"; the Kitchen comes after Release 1.
 */
export type CraftingStation = 'portable' | 'workbench' | 'workshop' | 'forge' | 'kitchen';

/** A place the player crafts at: its station and how far it is upgraded. */
export interface CraftingSite {
  readonly station: CraftingStation;
  readonly tier: number;
}

export interface RecipeIngredient {
  readonly itemId: string;
  readonly count: number;
}

export interface RecipeDef {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly station: CraftingStation;
  /** The station tier needed (a tier-2 Workshop crafts tier 1 and 2 recipes). */
  readonly tier: number;
  readonly uniqueOutput?: boolean;
  /** Hidden knowledge: craftable only after a quest reward teaches it (see StoryProgress). */
  readonly learnedByQuest?: boolean;
  readonly ingredients: readonly RecipeIngredient[];
  readonly output: RecipeIngredient;
}
