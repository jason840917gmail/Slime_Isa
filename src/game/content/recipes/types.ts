export type CraftingContext = 'portable' | 'workbench' | 'forge' | 'kitchen' | 'alchemy';

export interface RecipeIngredient {
  readonly itemId: string;
  readonly count: number;
}

export interface RecipeDef {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly context: CraftingContext;
  readonly tier: number;
  readonly uniqueOutput?: boolean;
  /** Hidden knowledge: craftable only after a quest reward teaches it (see StoryProgress). */
  readonly learnedByQuest?: boolean;
  readonly ingredients: readonly RecipeIngredient[];
  readonly output: RecipeIngredient;
}
