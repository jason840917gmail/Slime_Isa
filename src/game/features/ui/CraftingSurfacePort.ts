import type { JsonValue } from '../../content/scenes/types';
import type { RecipeDef } from '../../content/recipes/types';
import { gameEvents } from '../../core/EventBus';
import { RECIPES } from '../../crafting/Crafting';
import { CraftingService, normalizeQuantity, type CraftFailureReason, type CraftQuote, type CraftSuccess } from '../../crafting/CraftingService';
import { itemRegistry } from '../../systems/Inventory';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface CraftingSurfaceOptions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly service: CraftingService;
  readonly onPausedChange: (paused: boolean) => void;
  readonly onCrafted: (result: CraftSuccess) => void;
  readonly recipes?: readonly RecipeDef[];
}

/** Crafting presentation and quantity state for the authored workbench modal. */
export class CraftingSurfacePort implements UiSurfacePort {
  private readonly modalHandle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private readonly quantities = new Map<string, number>();
  private selectedRecipeId?: string;
  private status?: string;
  private openValue = false;
  private stopped = false;
  /** Recipes of the station (or portable list) this modal was last opened for. */
  private activeRecipes?: readonly RecipeDef[];

  constructor(private readonly options: CraftingSurfaceOptions) {
    this.modalHandle = options.modalStack.register('crafting', {
      isOpen: () => this.isOpen(),
      close: () => this.close(),
    });
    gameEvents.on('inventory.changed', this.publish, this);
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  isOpen(): boolean { return this.openValue; }
  toggle(recipes?: readonly RecipeDef[]): void { if (this.openValue) this.close(); else this.open(recipes); }

  /** Opens the modal; `recipes` selects the station's list (defaults to the configured list). */
  open(recipes?: readonly RecipeDef[]): void {
    if (this.stopped || this.openValue) return;
    if (recipes) this.activeRecipes = recipes;
    if (!this.recipes().some((recipe) => recipe.id === this.selectedRecipeId)) this.selectedRecipeId = undefined;
    this.selectedRecipeId ??= this.recipes()[0]?.id;
    this.status = undefined;
    this.openValue = true;
    this.options.onPausedChange(true);
    this.modalHandle.open();
    this.publish();
  }

  close(): void {
    if (!this.openValue) { this.modalHandle.close(); return; }
    this.openValue = false;
    this.modalHandle.close();
    this.options.onPausedChange(false);
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'crafting-ui' || this.stopped) return {};
    const recipes = this.recipes();
    const selectedIndex = Math.max(0, recipes.findIndex((recipe) => recipe.id === this.selectedRecipeId));
    const recipe = recipes[selectedIndex];
    if (recipe) this.selectedRecipeId = recipe.id;
    const quote = recipe ? this.quote(recipe) : undefined;
    const width = Math.min(1080, Math.max(1, this.options.uiRoot.clientWidth - 32));
    const height = Math.min(660, Math.max(1, this.options.uiRoot.clientHeight - 32));
    return {
      open: this.openValue,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      recipes: recipes.map((entry) => {
        const item = itemRegistry.get(entry.output.itemId);
        const status = this.options.service.quote(entry, 1).status;
        // Quest-taught recipes read as locked (greyed, craft disabled) until learned.
        const locked = status === 'not-learned';
        const state = locked ? 'Not learned yet' : status === 'ready' ? 'Ready to craft' : 'Materials needed';
        return {
          id: entry.id,
          label: `${entry.name}\n${state}`,
          ...(item || locked ? { metadata: {
            ...(item ? { iconKey: item.icon, iconFrame: item.iconFrame ?? 0, showLabel: true } : {}),
            ...(locked ? { locked: true } : {}),
          } } : {}),
        };
      }),
      selectedIndex: recipe ? selectedIndex : -1,
      details: recipe && quote ? detailsFor(recipe, quote) : 'No recipes available',
      quantity: quote ? `Amount: ${quote.requestedQuantity}  ·  MAX ${quote.maxCraftable}` : 'Amount: 0',
      status: this.status ?? (quote?.status && quote.status !== 'ready' ? reasonText(quote.status) : ''),
      craftDisabled: quote?.status !== 'ready',
      quantityDisabled: !quote || quote.maxCraftable < 1,
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'crafting-ui' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (surfaceId !== 'crafting-ui' || this.stopped) return;
    if (actionId === 'close') { this.close(); return; }
    if (!this.openValue) return;
    const recipes = this.recipes();
    if (actionId === 'select-recipe') {
      const index = selectionIndex(payload);
      const recipe = index === undefined ? undefined : recipes[index];
      if (!recipe) return;
      this.selectedRecipeId = recipe.id;
      this.status = undefined;
      this.publish();
      return;
    }
    const recipe = recipes.find((entry) => entry.id === this.selectedRecipeId);
    if (!recipe) return;
    if (actionId === 'craft') {
      const result = this.options.service.craft(recipe, this.quote(recipe).requestedQuantity);
      if (result.ok) {
        this.status = `Crafted ${result.outputQuantity} × ${recipe.name}`;
        this.options.onCrafted(result);
      } else this.status = reasonText(result.reason);
    } else {
      const max = this.options.service.quote(recipe, 1).maxCraftable;
      const current = this.quote(recipe).requestedQuantity;
      const delta = actionId === 'quantity-minus-10' ? -10 : actionId === 'quantity-minus-1' ? -1
        : actionId === 'quantity-plus-1' ? 1 : actionId === 'quantity-plus-10' ? 10 : 0;
      if (actionId === 'quantity-max') this.quantities.set(recipe.id, max);
      else if (delta !== 0) this.quantities.set(recipe.id, normalizeQuantity(current + delta, max));
      else return;
      this.status = undefined;
    }
    this.publish();
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    gameEvents.off('inventory.changed', this.publish, this);
    this.resizeObserver.disconnect();
    this.modalHandle.unregister();
    this.listeners.clear();
  }

  private recipes(): readonly RecipeDef[] { return this.activeRecipes ?? this.options.recipes ?? RECIPES; }

  private quote(recipe: RecipeDef): CraftQuote {
    const max = this.options.service.quote(recipe, 1).maxCraftable;
    const quantity = normalizeQuantity(this.quantities.get(recipe.id) ?? 1, max);
    this.quantities.set(recipe.id, quantity);
    return this.options.service.quote(recipe, quantity);
  }

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('crafting-ui');
    for (const listener of this.listeners) listener(model);
  };
}

function detailsFor(recipe: RecipeDef, quote: CraftQuote): string {
  const item = itemRegistry.get(recipe.output.itemId);
  return [
    item?.name ?? recipe.name,
    recipe.description,
    '',
    ...quote.stats.map((stat) => `${stat.label}: ${stat.value}`),
    '',
    'MATERIALS NEEDED',
    ...quote.requirements.map((cost) => {
      const name = itemRegistry.get(cost.itemId)?.name ?? cost.itemId;
      return `${name}: ${cost.available} / ${cost.required}${cost.missing > 0 ? ' · missing' : ''}`;
    }),
  ].join('\n');
}

function reasonText(reason: CraftFailureReason): string {
  switch (reason) {
    case 'invalid-recipe': return 'This recipe is unavailable.';
    case 'not-learned': return 'Not learned yet — a quest will teach it.';
    case 'unique-owned': return 'You already have this item.';
    case 'missing-materials': return 'More materials are needed.';
    case 'inventory-full': return 'Make room in your inventory first.';
  }
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
