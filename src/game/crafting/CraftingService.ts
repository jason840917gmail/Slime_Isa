import type { InventorySlot, ItemDef } from '../core/types';
import type { NormalizedWeaponDefinition } from '../content/weapons/types';
import type { CraftingSite, RecipeDef } from '../content/recipes/types';
import { PORTABLE_SITE, stationCrafts } from '../content/recipes/RecipeCatalog';

export type CraftFailureReason =
  | 'invalid-recipe'
  | 'wrong-station'
  | 'station-tier'
  | 'not-learned'
  | 'unique-owned'
  | 'missing-materials'
  | 'inventory-full';

export interface CraftCompletedPayload {
  readonly recipeId: string;
  readonly itemId: string;
  readonly quantity: number;
}

export interface CraftingInventory {
  count(itemId: string): number;
  previewTransact(removals: readonly Readonly<InventorySlot>[], additions: readonly Readonly<InventorySlot>[]): boolean;
  transact(removals: readonly Readonly<InventorySlot>[], additions: readonly Readonly<InventorySlot>[]): boolean;
}

export interface CraftingServiceDependencies {
  readonly inventory: CraftingInventory;
  readonly getItem: (itemId: string) => ItemDef | undefined;
  readonly getWeapon: (weaponId: string) => NormalizedWeaponDefinition | undefined;
  readonly emitCompleted: (payload: CraftCompletedPayload) => void;
  /** Recipes flagged `learnedByQuest` stay locked until this returns true. Defaults to all known. */
  readonly isRecipeLearned?: (recipeId: string) => boolean;
}

export interface CraftRequirementQuote {
  readonly itemId: string;
  readonly perCraft: number;
  readonly required: number;
  readonly available: number;
  readonly missing: number;
}

export interface CraftStatLine {
  readonly label: string;
  readonly value: string;
}

export interface CraftQuote {
  readonly recipeId: string;
  readonly requestedQuantity: number;
  readonly maxCraftable: number;
  readonly outputItemId: string;
  readonly outputQuantity: number;
  readonly requirements: readonly CraftRequirementQuote[];
  readonly stats: readonly CraftStatLine[];
  readonly status: 'ready' | CraftFailureReason;
}

export type CraftSuccess = {
  readonly ok: true;
  readonly recipe: RecipeDef;
  readonly quote: CraftQuote;
  readonly outputQuantity: number;
};

export type CraftFailure = {
  readonly ok: false;
  readonly recipe: RecipeDef;
  readonly quote: CraftQuote;
  readonly reason: CraftFailureReason;
};

export type CraftResult = CraftSuccess | CraftFailure;

const INVALID_QUOTE_STATUS: CraftFailureReason = 'invalid-recipe';

function positiveInteger(value: number): number {
  return Number.isSafeInteger(value) && value > 0 ? value : 0;
}

/** Shared by the DOM quantity adapter and direct service callers. */
export function normalizeQuantity(value: number | string, maxCraftable: number): number {
  const max = positiveInteger(maxCraftable);
  if (max === 0) return 0;

  const numeric = typeof value === 'number' ? value : Number(value.trim());
  if (!Number.isFinite(numeric) || numeric <= 0) return 1;
  return Math.max(1, Math.min(max, Math.trunc(numeric)));
}

function aggregateIngredients(recipe: RecipeDef): Map<string, number> {
  const totals = new Map<string, number>();
  for (const ingredient of recipe.ingredients) {
    totals.set(ingredient.itemId, (totals.get(ingredient.itemId) ?? 0) + ingredient.count);
  }
  return totals;
}

function transactionFor(recipe: RecipeDef, quantity: number): {
  readonly removals: readonly InventorySlot[];
  readonly additions: readonly InventorySlot[];
} {
  const ingredients = aggregateIngredients(recipe);
  return {
    removals: [...ingredients.entries()].map(([itemId, count]) => ({ itemId, count: count * quantity })),
    additions: [{ itemId: recipe.output.itemId, count: recipe.output.count * quantity }],
  };
}

function weaponStats(
  item: ItemDef,
  getWeapon: (weaponId: string) => NormalizedWeaponDefinition | undefined,
): readonly CraftStatLine[] {
  const weaponId = item.equipment?.weaponId;
  if (!weaponId) return [];
  const weapon = getWeapon(weaponId);
  if (!weapon) return [];

  const harvest = weapon.harvestCapabilities;
  if (harvest && Object.keys(harvest).length > 0) {
    return Object.entries(harvest).map(([tag, level]) => ({ label: 'Harvest', value: `${tag}: ${level}` }));
  }

  return [
    { label: 'Damage', value: `${Math.round(weapon.baseDamage)}` },
    { label: 'Cooldown', value: `${(weapon.cooldownMs / 1000).toFixed(1)}s` },
  ];
}

function itemStats(
  item: ItemDef | undefined,
  getWeapon: (weaponId: string) => NormalizedWeaponDefinition | undefined,
): readonly CraftStatLine[] {
  if (!item) return [];
  if (item.equipment) return weaponStats(item, getWeapon);
  if (!item.use) return [];

  const stats: CraftStatLine[] = [];
  if (item.use.healHp !== undefined) stats.push({ label: 'Effect', value: `+${item.use.healHp} HP` });
  if (item.use.healEnergy !== undefined) stats.push({ label: 'Effect', value: `+${item.use.healEnergy} energy` });
  return stats;
}

export class CraftingService {
  private readonly deps: CraftingServiceDependencies;

  constructor(deps: CraftingServiceDependencies) {
    this.deps = deps;
  }

  /** Quotes a craft at `site` (portable by default): a recipe of another station is `wrong-station`. */
  quote(recipe: RecipeDef, requestedQuantity: number | string, site: CraftingSite = PORTABLE_SITE): CraftQuote {
    const outputItemId = typeof recipe?.output?.itemId === 'string' ? recipe.output.itemId : '';
    const outputDef = this.deps.getItem(outputItemId);
    if (!outputDef || !this.isValidRecipe(recipe, outputDef)) {
      return {
        recipeId: typeof recipe?.id === 'string' ? recipe.id : '',
        requestedQuantity: 0,
        maxCraftable: 0,
        outputItemId,
        outputQuantity: 0,
        requirements: [],
        stats: [],
        status: INVALID_QUOTE_STATUS,
      };
    }

    const ingredientTotals = aggregateIngredients(recipe);
    const ingredientLimit = Math.min(
      ...[...ingredientTotals.entries()].map(([itemId, count]) => Math.floor(this.deps.inventory.count(itemId) / count)),
    );
    const uniqueLimit = recipe.uniqueOutput && this.deps.inventory.count(recipe.output.itemId) > 0 ? 0 : recipe.uniqueOutput ? 1 : Number.MAX_SAFE_INTEGER;
    const maxCandidate = Math.max(0, Math.min(ingredientLimit, uniqueLimit));
    const maxCraftable = this.findMaximumTransaction(recipe, maxCandidate);
    const quantity = normalizeQuantity(requestedQuantity, maxCraftable);
    const requirementQuantity = Math.max(1, quantity);
    const requirements = recipe.ingredients.map((ingredient) => {
      const available = this.deps.inventory.count(ingredient.itemId);
      const required = ingredient.count * requirementQuantity;
      return {
        itemId: ingredient.itemId,
        perCraft: ingredient.count,
        required,
        available,
        missing: Math.max(0, required - available),
      };
    });

    const status = this.resolveStatus(recipe, site, outputDef, maxCraftable, requirements);
    return {
      recipeId: recipe.id,
      requestedQuantity: quantity,
      maxCraftable,
      outputItemId: recipe.output.itemId,
      outputQuantity: recipe.output.count * quantity,
      requirements,
      stats: itemStats(outputDef, this.deps.getWeapon),
      status,
    };
  }

  /** Crafts at `site`; anything but a ready quote is refused before the inventory is touched. */
  craft(recipe: RecipeDef, requestedQuantity: number | string, site: CraftingSite = PORTABLE_SITE): CraftResult {
    let quote = this.quote(recipe, requestedQuantity, site);
    if (quote.status !== 'ready') {
      return { ok: false, recipe, quote, reason: quote.status };
    }

    const transaction = transactionFor(recipe, quote.requestedQuantity);
    if (!this.deps.inventory.transact(transaction.removals, transaction.additions)) {
      quote = this.quote(recipe, requestedQuantity, site);
      const reason = quote.status === 'ready' ? 'inventory-full' : quote.status;
      return { ok: false, recipe, quote, reason };
    }

    const result: CraftSuccess = {
      ok: true,
      recipe,
      quote,
      outputQuantity: quote.outputQuantity,
    };
    this.deps.emitCompleted({
      recipeId: recipe.id,
      itemId: recipe.output.itemId,
      quantity: quote.outputQuantity,
    });
    return result;
  }

  private isValidRecipe(recipe: RecipeDef, outputDef: ItemDef | undefined): boolean {
    if (!recipe || typeof recipe.id !== 'string' || recipe.id.trim().length === 0) return false;
    if (!recipe.output || typeof recipe.output.itemId !== 'string') return false;
    if (!Array.isArray(recipe.ingredients) || recipe.ingredients.length === 0) return false;
    if (!outputDef || !Number.isSafeInteger(recipe.output.count) || recipe.output.count <= 0) return false;
    if (outputDef.equipment?.weaponId && !this.deps.getWeapon(outputDef.equipment.weaponId)) return false;
    return recipe.ingredients.every((ingredient) => (
      typeof ingredient.itemId === 'string'
      && ingredient.itemId.trim().length > 0
      && this.deps.getItem(ingredient.itemId) !== undefined
      && Number.isSafeInteger(ingredient.count)
      && ingredient.count > 0
    ));
  }

  private findMaximumTransaction(recipe: RecipeDef, candidate: number): number {
    if (candidate <= 0) return 0;
    let low = 0;
    let high = candidate;
    while (low < high) {
      const mid = Math.ceil((low + high) / 2);
      const transaction = transactionFor(recipe, mid);
      if (this.deps.inventory.previewTransact(transaction.removals, transaction.additions)) low = mid;
      else high = mid - 1;
    }
    return low;
  }

  private resolveStatus(
    recipe: RecipeDef,
    site: CraftingSite,
    outputDef: ItemDef,
    maxCraftable: number,
    requirements: readonly CraftRequirementQuote[],
  ): 'ready' | CraftFailureReason {
    // The most fundamental reason wins: station, tier, knowledge, then materials and space.
    if (!stationCrafts(site.station, recipe)) return 'wrong-station';
    if (recipe.tier > site.tier) return 'station-tier';
    if (recipe.learnedByQuest && !(this.deps.isRecipeLearned?.(recipe.id) ?? true)) return 'not-learned';
    if (recipe.uniqueOutput && this.deps.inventory.count(recipe.output.itemId) > 0) return 'unique-owned';
    if (requirements.some((requirement) => requirement.available < requirement.perCraft)) return 'missing-materials';
    if (maxCraftable === 0) return outputDef ? 'inventory-full' : 'invalid-recipe';
    return 'ready';
  }
}
