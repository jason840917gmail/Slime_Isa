import type { JsonValue } from '../../content/scenes/types';
import type { CraftingSite, RecipeDef } from '../../content/recipes/types';
import { PORTABLE_SITE, recipesAt, siteTitle, stationName } from '../../content/recipes/RecipeCatalog';
import { gameEvents } from '../../core/EventBus';
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
}

/** Crafting presentation and quantity state for the one crafting modal every station shares. */
export class CraftingSurfacePort implements UiSurfacePort {
  private readonly modalHandle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private readonly quantities = new Map<string, number>();
  private selectedRecipeId?: string;
  private status?: string;
  /** Color of the status line: red after a refused craft, green after a craft. */
  private statusColor?: string;
  private openValue = false;
  private stopped = false;
  /** Where the modal was last opened: C (portable) or a station and its tier. */
  private site: CraftingSite = PORTABLE_SITE;

  constructor(private readonly options: CraftingSurfaceOptions) {
    this.modalHandle = options.modalStack.register('crafting', {
      isOpen: () => this.isOpen(),
      close: () => this.close(),
    });
    gameEvents.on('inventory.changed', this.onInventoryChanged, this);
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  isOpen(): boolean { return this.openValue; }
  toggle(site: CraftingSite = PORTABLE_SITE): void { if (this.openValue) this.close(); else this.open(site); }

  /** Opens the modal for a site: C crafts portable recipes, a station its own. */
  open(site: CraftingSite = PORTABLE_SITE): void {
    if (this.stopped || this.openValue) return;
    this.site = site;
    if (!this.recipes().some((recipe) => recipe.id === this.selectedRecipeId)) this.selectedRecipeId = undefined;
    this.selectedRecipeId ??= this.recipes()[0]?.id;
    this.status = undefined;
    this.statusColor = undefined;
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
      title: siteTitle(this.site),
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      recipes: recipes.map((entry) => {
        const item = itemRegistry.get(entry.output.itemId);
        const rowQuote = this.options.service.quote(entry, 1, this.site);
        const status = rowQuote.status;
        // Unlearned recipes, recipes above the station's tier and another station's recipes read as locked
        // (greyed, craft disabled); recipes short of materials are flagged red and say what is missing.
        const locked = status === 'not-learned' || status === 'station-tier' || status === 'wrong-station';
        const short = status === 'missing-materials';
        const state = short ? `Missing ${missingList(rowQuote, 2)}` : rowState(status, entry);
        return {
          id: entry.id,
          label: `${entry.name}\n${state}`,
          ...(item || locked || short ? { metadata: {
            ...(item ? { iconKey: item.icon, iconFrame: item.iconFrame ?? 0, showLabel: true } : {}),
            ...(locked ? { locked: true } : {}),
            ...(short ? { short: true } : {}),
          } } : {}),
        };
      }),
      selectedIndex: recipe ? selectedIndex : -1,
      detailsName: recipe ? itemRegistry.get(recipe.output.itemId)?.name ?? recipe.name : 'Nothing to craft here',
      details: recipe && quote ? detailsFor(recipe, quote) : 'No recipes available',
      materials: quote ? materialRows(quote) : [],
      quantity: quote ? `Amount: ${quote.requestedQuantity}  ·  MAX ${quote.maxCraftable}` : 'Amount: 0',
      status: this.status ?? (recipe && quote?.status && quote.status !== 'ready' ? reasonText(quote.status, recipe, this.site, quote) : ''),
      statusColor: this.statusColor ?? STATUS_COLORS.hint,
      // Short of materials or space, Craft still answers with exactly what is missing.
      craftDisabled: !quote || (quote.status !== 'ready' && quote.status !== 'missing-materials' && quote.status !== 'inventory-full'),
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
      this.statusColor = undefined;
      this.publish();
      return;
    }
    const recipe = recipes.find((entry) => entry.id === this.selectedRecipeId);
    if (!recipe) return;
    if (actionId === 'craft') {
      const result = this.options.service.craft(recipe, this.quote(recipe).requestedQuantity, this.site);
      if (result.ok) {
        this.status = `Crafted ${result.outputQuantity} × ${recipe.name}`;
        this.statusColor = STATUS_COLORS.success;
        this.options.onCrafted(result);
      } else {
        this.status = reasonText(result.reason, recipe, this.site, result.quote);
        this.statusColor = STATUS_COLORS.refused;
        gameEvents.emit('craft.failed', { recipeId: recipe.id, reason: result.reason });
      }
    } else {
      const max = this.options.service.quote(recipe, 1, this.site).maxCraftable;
      const current = this.quote(recipe).requestedQuantity;
      const delta = actionId === 'quantity-minus-10' ? -10 : actionId === 'quantity-minus-1' ? -1
        : actionId === 'quantity-plus-1' ? 1 : actionId === 'quantity-plus-10' ? 10 : 0;
      if (actionId === 'quantity-max') this.quantities.set(recipe.id, max);
      else if (delta !== 0) this.quantities.set(recipe.id, normalizeQuantity(current + delta, max));
      else return;
      this.status = undefined;
      this.statusColor = undefined;
    }
    this.publish();
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    gameEvents.off('inventory.changed', this.onInventoryChanged, this);
    this.resizeObserver.disconnect();
    this.modalHandle.unregister();
    this.listeners.clear();
  }

  private recipes(): readonly RecipeDef[] { return recipesAt(this.site); }

  private quote(recipe: RecipeDef): CraftQuote {
    const max = this.options.service.quote(recipe, 1, this.site).maxCraftable;
    const quantity = normalizeQuantity(this.quantities.get(recipe.id) ?? 1, max);
    this.quantities.set(recipe.id, quantity);
    return this.options.service.quote(recipe, quantity, this.site);
  }

  /** New materials answer a refused craft: its "Missing ..." line gives way to the live quote. */
  private readonly onInventoryChanged = (): void => {
    if (this.statusColor === STATUS_COLORS.refused) {
      this.status = undefined;
      this.statusColor = undefined;
    }
    this.publish();
  };

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('crafting-ui');
    for (const listener of this.listeners) listener(model);
  };
}

function detailsFor(recipe: RecipeDef, quote: CraftQuote): string {
  const stats = quote.stats.map((stat) => `${stat.label}: ${stat.value}`);
  return [recipe.description, ...(stats.length ? ['', stats.join('  ·  ')] : [])].join('\n');
}

/** One row per material: its icon, what the bag holds of what the craft needs; short ones in red. */
function materialRows(quote: CraftQuote): JsonValue[] {
  return quote.requirements.map((cost) => {
    const item = itemRegistry.get(cost.itemId);
    const name = item?.name ?? cost.itemId;
    return {
      id: `material-${cost.itemId}`,
      label: `${name}\n${cost.available} / ${cost.required}${cost.missing > 0 ? `  (need ${cost.missing} more)` : '  ✓'}`,
      metadata: {
        ...(item ? { iconKey: item.icon, iconFrame: item.iconFrame ?? 0, showLabel: true } : {}),
        ...(cost.missing > 0 ? { short: true } : {}),
      },
    };
  });
}

/** The short state under a recipe's name in the list. */
function rowState(status: 'ready' | CraftFailureReason, recipe: RecipeDef): string {
  switch (status) {
    case 'ready': return 'Ready to craft';
    case 'station-tier': return `Needs tier ${recipe.tier}`;
    case 'not-learned': return 'Not learned yet';
    case 'unique-owned': return 'Already owned';
    case 'inventory-full': return 'Inventory full';
    case 'wrong-station': return `At the ${stationName(recipe.station)}`;
    case 'missing-materials': return 'Materials needed';
    case 'invalid-recipe': return 'Unavailable';
  }
}

const STATUS_COLORS = { hint: '#ffd277', refused: '#ff6f88', success: '#86f0c3' } as const;

/** "12 Wood, 3 Stone": what one more craft still needs, at most `limit` materials. */
function missingList(quote: CraftQuote, limit = Number.POSITIVE_INFINITY): string {
  const missing = quote.requirements.filter((requirement) => requirement.missing > 0);
  const shown = missing.slice(0, limit).map((requirement) => `${requirement.missing} ${itemRegistry.get(requirement.itemId)?.name ?? requirement.itemId}`);
  return missing.length > limit ? `${shown.join(', ')}, …` : shown.join(', ');
}

/** Why the selected recipe cannot be crafted here, in plain words. */
function reasonText(reason: CraftFailureReason, recipe: RecipeDef, site: CraftingSite, quote?: CraftQuote): string {
  switch (reason) {
    case 'invalid-recipe': return 'This recipe is unavailable.';
    case 'wrong-station': return `Craft this at the ${stationName(recipe.station)}.`;
    case 'station-tier': return `Needs a tier ${recipe.tier} ${stationName(site.station)}.`;
    case 'not-learned': return 'Not learned yet — a quest will teach it.';
    case 'unique-owned': return 'You already have this item.';
    case 'missing-materials': return quote && missingList(quote) ? `Missing: ${missingList(quote)}.` : 'More materials are needed.';
    case 'inventory-full': return 'Make room in your inventory first.';
  }
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
