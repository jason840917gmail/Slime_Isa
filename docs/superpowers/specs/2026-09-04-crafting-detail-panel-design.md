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

Add a focused crafting service boundary that owns recipe quotes and transactions. It exposes a read path that computes a detail view model and a write path that performs an atomic multi-craft.

The quote includes:

- normalized requested quantity;
- maximum craftable quantity;
- output item and total output quantity;
- per-ingredient required, available, and missing quantities;
- a typed availability/failure state such as `ready`, `missing-materials`, `unique-owned`, or `inventory-full`;
- contextual stats resolved from existing item and weapon definitions.

`maxCraftable` is constrained by ingredient availability, unique-output rules, and inventory capacity for the produced item. The service is the single source of truth for availability; the UI does not recreate crafting rules from colors or labels.

### Inventory transaction boundary

Extend the inventory transaction path with a preview/check operation or an equivalent shared draft calculation. The preview must account for removals before additions and for stack/slot capacity. The actual transaction reuses the same rules atomically, so a stale quote cannot partially consume materials.

### Completion event

A successful quantity craft emits one `craft.completed` event with the recipe ID, output item ID, and total output quantity. Existing quest tracking and world-scene callbacks continue to consume this event without knowing about the UI quantity control.

## Visual design and asset

Generate one wide, hand-painted raster backplate for the crafting workbench. It should match the existing slime-game style: organic wood framing, moss, slime-glass accents, and a dark translucent interior that blends with the world. It should include a subtle inset divider and a softly recessed action area for the right panel, but no baked text, item icons, numeric values, or button labels.

The runtime asset is registered in `asset/assets.json` and loaded through the shared UI-skin helper. The image is a visual surface only; the UI renders all live content and controls in code.

Recommended composition:

- left list region approximately 58–62% of the usable width;
- right detail region approximately 34–38% of the usable width;
- generous inner padding and a clear vertical seam;
- enough vertical room for eight rows plus the detail panel and Craft action;
- transparent or softly blended outer surroundings so the game world remains visible.

## Interaction and failure behavior

- The recipe row has a selection hit area only.
- The Craft button owns a single large rectangular interactive zone, is added before decorative children, stops propagation, and is never found through a scene-wide coordinate scan.
- The Craft button is disabled when the quote is not ready and presents the service-provided reason.
- If inventory changes between quote and click, the service revalidates and returns a typed failure without consuming anything.
- Missing resources pulse their requirement rows or chips; transaction failures pulse the Craft button/selection area briefly.
- Inventory changes rebuild the quote and detail panel while preserving the selected recipe.
- Resize rebuilds the layout and keeps the selected absolute recipe index, visible list offset, and normalized quantity where possible.
- The numeric input is destroyed with the crafting overlay and all DOM/input listeners are removed on close/destroy.

## Testing and verification

Add focused tests for:

- quantity normalization and clamping;
- ingredient-based maximum quantity;
- unique-output limits;
- output stack/slot capacity;
- multi-output totals and completion-event quantity;
- atomic failure behavior;
- contextual stat mapping;
- selected recipe persistence through refresh and resize;
- quantity-input and Craft-button interaction guards;
- existing list scrolling and eight-row layout behavior.

Run the repository TypeScript check, crafting tests, asset validation, and production build. Any pre-existing unrelated asset-manifest failures must be reported separately rather than changed as part of this feature.
