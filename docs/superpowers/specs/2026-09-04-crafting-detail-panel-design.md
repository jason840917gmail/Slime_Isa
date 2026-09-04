# Crafting Detail Panel and Quantity Crafting

## Goal

Improve the crafting experience by turning the existing recipe list into a two-column workbench. Selecting a recipe shows a detailed, contextual preview on the right. The player enters a craft quantity directly, sees the total output and material requirements update immediately, and confirms with one large, reliable Craft button.

The existing non-pixel-art, hand-painted organic UI direction remains the visual foundation. The world stays visible around the workbench, and text, icons, stats, quantities, and interactive controls remain code-rendered so they stay accurate and localizable.

## Approved experience

- The left column keeps the existing scrollable recipe list and supports eight readable rows on normal-height screens.
- Clicking a recipe selects it only; it no longer crafts immediately.
- Keyboard selection (Up/Down and W/S) updates the same selected recipe and right-side details.
- The right column shows:
  - output item preview and recipe name;
  - recipe description;
  - contextual item stats;
  - output quantity for the requested craft amount;
  - ingredient requirements with current/required quantities;
  - a numeric quantity input, defaulting to `1`;
  - one large Craft button with a generous hit area.
- The quantity input accepts whole numbers, updates on input/change, and is clamped to the current craftable maximum.
- Enter in the quantity field crafts only when the input is valid. The Craft button remains the primary action.
- While the quantity field is focused, Up/Down recipe navigation does not react to those key events.
- Narrow layouts stack the details below the recipe list without changing the selected recipe or quantity state.

## Architecture and ownership

### Crafting service

Add `src/game/crafting/CraftingService.ts` as a focused crafting service boundary. It owns recipe quotes and transactions while remaining independently testable through injected inventory, item lookup, weapon lookup, and completion-event dependencies.

The service contract is:

```ts
interface CraftingServiceDependencies {
  readonly inventory: CraftingInventory;
  readonly getItem: (itemId: string) => ItemDef | undefined;
  readonly getWeapon: (weaponId: string) => NormalizedWeaponDefinition | undefined;
  readonly emitCompleted: (payload: CraftCompletedPayload) => void;
}

class CraftingService {
  quote(recipe: RecipeDef, requestedQuantity: number | string): CraftQuote;
  craft(recipe: RecipeDef, requestedQuantity: number | string): CraftResult;
}

function normalizeQuantity(value: number | string, maxCraftable: number): number;
```

`CraftingUIContext` requires `craftingService: CraftingService`; production constructs it once from the player inventory adapter and passes it from `WorldScene`, while UI tests inject a fixture service. The compatibility singleton exported by `Crafting.ts` delegates to the same production service for non-UI callers.

`CraftingInventory` is defined as:

```ts
interface CraftingInventory {
  count(itemId: string): number;
  previewTransact(removals: readonly InventorySlot[], additions: readonly InventorySlot[]): boolean;
  transact(removals: readonly InventorySlot[], additions: readonly InventorySlot[]): boolean;
}
```

The production adapter delegates to `playerInventory`; tests use an in-memory implementation. The exported data contract is:

```ts
type CraftFailureReason = 'invalid-recipe' | 'unique-owned' | 'missing-materials' | 'inventory-full';

interface CraftRequirementQuote {
  readonly itemId: string;
  readonly perCraft: number;
  readonly required: number;
  readonly available: number;
  readonly missing: number;
}

interface CraftStatLine { readonly label: string; readonly value: string; }

interface CraftQuote {
  readonly recipeId: string;
  readonly requestedQuantity: number;
  readonly maxCraftable: number;
  readonly outputItemId: string;
  readonly outputQuantity: number;
  readonly requirements: readonly CraftRequirementQuote[];
  readonly stats: readonly CraftStatLine[];
  readonly status: 'ready' | CraftFailureReason;
}

type CraftResult =
  | { readonly ok: true; readonly recipe: RecipeDef; readonly quote: CraftQuote; readonly outputQuantity: number; }
  | { readonly ok: false; readonly recipe: RecipeDef; readonly quote: CraftQuote; readonly reason: CraftFailureReason; };

interface CraftCompletedPayload {
  readonly recipeId: string;
  readonly itemId: string;
  readonly quantity: number;
}
```

`CraftQuote.status` is the closed availability union above. Runtime recipe validation rejects missing or blank IDs, non-positive ingredient/output counts, unknown ingredient/output items, and equipment outputs whose referenced weapon definition is missing; these produce `invalid-recipe`.

The quote includes:

- normalized requested quantity;
- maximum craftable quantity;
- output item and total output quantity;
- per-ingredient required, available, and missing quantities;
- a closed availability union: `ready`, `missing-materials`, `unique-owned`, `inventory-full`, or `invalid-recipe`;
- contextual stats resolved from existing item and weapon definitions.

Contextual stats are formatted consistently: an output with `itemDef.equipment.weaponId` and non-empty `harvestCapabilities` is treated as a tool and shows each capability as `target tag: level`; other equipment outputs show integer `baseDamage` and cooldown in seconds from `cooldownMs`; consumables show `+N HP` and/or `+N energy` from their use definition; materials and other items show no stat rows beyond their description. This classification intentionally uses weapon-definition capabilities because harvesting tools are currently registered as equipment items with a weapon category.

`maxCraftable` is constrained by ingredient availability, unique-output rules, and inventory capacity for the produced item. Failure precedence for a requested amount is `invalid-recipe`, then `unique-owned`, then `missing-materials`, then `inventory-full`; the quote still exposes per-ingredient availability so the UI can show all relevant shortages. The service is the single source of truth for availability; the UI does not recreate crafting rules from colors or labels.

The service aggregates duplicate ingredient entries before checking. Inventory removals are applied before additions, so recipes that consume and produce the same item are valid when the post-removal inventory can accept the output. A multi-output total means multiple crafts of the catalog's single `output` entry; the current recipe model does not add multiple output items.

For both direct service calls and the DOM adapter, the exported `normalizeQuantity(value, maxCraftable)` is the only normalization path: convert a trimmed string or finite number to a numeric value; if it is missing, malformed, negative, zero, fractional, `NaN`, or infinite, return the default quantity `1` when any craft is possible; return `0` when `maxCraftable === 0`; otherwise truncate and clamp the positive value to `maxCraftable`. The DOM field may remain visually empty while being edited, but its quote and blur/submit behavior use this shared function.

### Inventory transaction boundary

Extend the inventory transaction path with `previewTransact(removals, additions): boolean` or an equivalent shared draft calculation. The preview must account for aggregated removals, removals before additions, existing partial stacks, duplicate additions, and available slots. The actual transaction reuses the same rules atomically, so a stale quote cannot partially consume materials or emit an inventory event.

### Completion event

A successful quantity craft emits one `craft.completed` event with the recipe ID, output item ID, and total output quantity (`recipe.output.count × requestedQuantity`). Existing quest tracking continues to consume this event. `CraftingUIContext.onCrafted` becomes `(result: Extract<CraftResult, { ok: true }>) => void`, so `WorldScene` can retain automatic weapon-loadout assignment and floating-text feedback without performing crafting checks itself.

The existing exported `canCraft` and `craft` functions in `Crafting.ts` become compatibility delegates to the production `CraftingService`; they do not retain independent rule logic. `CraftingUI` calls the service directly and no longer reads `playerInventory` for availability or invokes `craft` itself.

## Visual design and asset

Generate a new sibling asset, `ui-crafting-detail-workbench-backplate.png`, registered under the stable manifest ID `ui.backplate.crafting-detail-workbench`, for the two-column crafting workbench. Keep the existing `ui.backplate.crafting-workbench` asset available for compatibility/fallback; the new runtime layout uses the sibling asset. It should match the existing slime-game style: organic wood framing, moss, slime-glass accents, and a dark translucent interior that blends with the world. It should include a subtle inset divider and a softly recessed action area for the right panel, but no baked text, item icons, numeric values, or button labels.

The runtime asset is registered in `asset/assets.json` and loaded through the shared UI-skin helper. The image is a visual surface only; the UI renders all live content and controls in code.

Recommended composition:

- left list region approximately 58–62% of the usable width;
- right detail region approximately 34–38% of the usable width;
- generous inner padding and a clear vertical seam;
- enough vertical room for eight rows plus the detail panel and Craft action;
- transparent or softly blended outer surroundings so the game world remains visible.

Asset acceptance criteria: target a 2048×1152 transparent PNG with a 16:9 composition, visible two-column insets, no text/watermark/pixel-art treatment, and no opaque rectangle outside the organic frame. Runtime integration must preserve the source alpha and register a new stable manifest ID.

## Interaction and failure behavior

- The recipe row has a selection hit area only.
- The Craft button owns a single large rectangular interactive zone, is added before decorative children, stops propagation, and is never found through a scene-wide coordinate scan.
- The Craft button is disabled when the quote is not ready. A status line immediately above or inside the action area always renders the service-provided reason, so the reason does not depend on hover behavior.
- If inventory changes between quote and click, the service revalidates and returns a typed failure without consuming anything.
- Missing resources pulse their requirement rows or chips; transaction failures pulse the Craft button/selection area briefly.
- Inventory changes rebuild the quote and detail panel while preserving the selected recipe.
- Resize rebuilds the layout and keeps the selected absolute recipe index, visible list offset, and normalized quantity where possible.
- The numeric input is destroyed with the crafting overlay and all DOM/input listeners are removed on close/destroy.

### Numeric input rules

- Use a text input with numeric input mode rather than relying on browser decimal behavior.
- On each input event, pass the raw field value through the shared `normalizeQuantity` function; pasted decimals, signs, letters, and other malformed values therefore resolve identically to direct service calls.
- While the field is being edited, an empty string is temporarily allowed in the DOM but quotes as quantity `1` when any craft is possible.
- On blur, Enter, or Craft-button activation, empty and zero values normalize to `1` when `maxCraftable > 0`; when `maxCraftable === 0`, the displayed value is `0` and Craft is disabled.
- Positive values above `maxCraftable` clamp to `maxCraftable`; positive values below `1` normalize to `1` when crafting is possible.
- The Phaser keyboard handlers ignore Up, Down, W, S, and Enter while the quantity input is the active element. The DOM handler prevents default Enter propagation and invokes the same single craft command, preventing double crafting.

Quantity is remembered per recipe ID while the overlay is open. Selecting another recipe restores that recipe's previous value or defaults to `1`; inventory refreshes and quote changes clamp the remembered value to the new maximum, using `0` only when no quantity is craftable.

### Refresh and resize state

- Track the selected recipe by stable recipe ID. After a refresh or resize, preserve that ID if it still exists.
- If it was removed, select the first recipe; if no recipes remain, render an empty detail state and disable Craft.
- Recompute the list offset from the selected recipe's new index and clamp it to the new capacity.
- Preserve the requested quantity when possible; otherwise clamp it to the new maximum, or use `1` when any craft is possible and `0` when none is possible.

## Testing and verification

Add focused tests for:

- quantity normalization and clamping;
- ingredient-based maximum quantity;
- unique-output limits;
- output stack/slot capacity;
- multi-craft totals from the single recipe output and completion-event quantity;
- atomic failure behavior;
- contextual stat mapping: weapon `baseDamage` and `cooldownMs`, tool harvest capabilities, consumable HP/energy effects, and no irrelevant stat rows for materials;
- duplicate ingredients, output matching an ingredient, partial stacks, and full-slot capacity;
- numeric input sanitization for empty, zero, negative, decimal, pasted, non-numeric, above-maximum, and zero-capacity values;
- selected recipe persistence through refresh and resize;
- quantity-input and Craft-button interaction guards;
- existing list scrolling and eight-row layout behavior.

The service tests live in `scripts/tests/crafting/crafting-service.test.mjs` and use the existing Vite SSR harness pattern; list/layout tests remain in `scripts/tests/crafting/crafting-layout.test.mjs`.

Run the repository TypeScript check, crafting tests, asset validation, and production build. Any pre-existing unrelated asset-manifest failures must be reported separately rather than changed as part of this feature.
