import { getBaseItemDefinitions } from '../../content/items/ItemCatalog';
import { RECIPE_CATALOG } from '../../content/recipes/RecipeCatalog';
import type { QuestRewards } from '../../content/quests/types';

function itemName(itemId: string): string {
  return getBaseItemDefinitions()[itemId]?.name ?? itemId;
}

function recipeName(recipeId: string): string {
  return RECIPE_CATALOG.find((recipe) => recipe.id === recipeId)?.name ?? recipeId;
}

/** Every reward as a short player-facing line: coins, XP, items, then unlocked recipes. */
export function questRewardLines(rewards: QuestRewards): readonly string[] {
  return [
    ...(rewards.coins ? [`${rewards.coins} coins`] : []),
    ...(rewards.xp ? [`${rewards.xp} XP`] : []),
    ...(rewards.items ?? []).map((item) => `${item.count > 1 ? `${item.count}× ` : ''}${itemName(item.itemId)}`),
    ...(rewards.recipeIds ?? []).map((recipeId) => `New recipe: ${recipeName(recipeId)}`),
  ];
}

/** One-line summary for journal and offer text. */
export function questRewardSummary(rewards: QuestRewards): string {
  const lines = questRewardLines(rewards);
  return lines.length > 0 ? `Reward: ${lines.join(' · ')}` : 'Reward: the elder\'s gratitude';
}
