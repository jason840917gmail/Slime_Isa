# Crafting Overlay Redesign

## Goal

Make the crafting overlay feel like a lightweight in-world list and remove the unreliable click behavior caused by the current scene-wide coordinate hit testing. The game world must remain visible behind the list. A player should craft by clicking the recipe row itself when the recipe is valid; there should be no separate Craft button.

## Approved visual direction

- Remove the panel-level `Crafting` title.
- Remove the panel-level instructional description and footer tip.
- Remove the full-screen dimming rectangle and the opaque rounded parent panel.
- Keep the world visible behind the overlay.
- Render only recipe rows as the visible UI surfaces. Each row must retain its own subtle fill, border, icon, name, and recipe description so it remains readable over the world.
- Show eight rows at once in the normal layout. Additional recipes are reached by scrolling.
- Replace text such as `Wood 40/20` with the material icon and required quantity, using the registered item icon/frame for each ingredient. The current inventory count is not displayed in the cost chip.
- Keep the selected-row treatment (accent border/indicator) so keyboard navigation remains legible without a panel frame.

The companion mockup at `http://localhost:64238/` demonstrates this visual structure at a narrow viewport as well as the ninth-row scroll case.

## Interaction behavior

### Row clicks

Each visible recipe row owns a `Phaser.GameObjects.Zone` centered on the row, sized to the exact row width/height, and added to the same screen-space container as the row graphics. The zone is the only interactive object in that row and is added before non-interactive text/image children. A primary-button pointer click (`pointer.button === 0`) performs these operations in order:

1. Select the clicked recipe.
2. If `canCraft(recipe)` is true, call the existing `craft(recipe)` service and invoke `onCrafted` when it succeeds.
3. If the recipe cannot be crafted, do not consume inventory or emit a completion event. Briefly pulse the missing cost chip(s) (and the muted row for a unique item that is already owned) so the click has clear, lightweight feedback without restoring a footer or modal message.

The hit area belongs to the row and is destroyed with the row container. There will be no manual `clickRegions` array and no scene-wide `pointerdown` coordinate scan. This prevents overlapping controls, stale rectangles after a refresh, and clicks being intercepted by unrelated UI layers. The list owns the highest screen-UI depth; the world remains visible but is paused and cannot win a row click. Clicks outside a row do nothing.

Unavailable feedback lasts 180 ms: missing cost chips tween to the missing color and back; a transaction failure that occurs despite `canCraft` pulses the whole row in amber for the same duration. The tween is presentation-only and is canceled when the container is rebuilt or closed.

### Keyboard and scrolling

- Preserve Up/Down and W/S selection and Enter-to-craft.
- Keep `selectedIndex` over the complete recipe list, not only the currently visible slice.
- Define `MAX_VISIBLE_COUNT = 8`; derive `effectiveVisibleCount` from the camera height as described in Layout and Rendering, then set `maxOffset = Math.max(0, recipes.length - effectiveVisibleCount)`.
- Define dependency-free `clampOffset(offset)`: truncate finite values, treat non-finite values as zero, then clamp to `[0, maxOffset]`.
- When a selection changes, use `ensureVisible(index, offset, effectiveVisibleCount)`: return `index` when `index < offset`; return `index - effectiveVisibleCount + 1` when `index >= offset + effectiveVisibleCount`; otherwise return `offset`; then clamp the result.
- Render `recipes.slice(scrollOffset, scrollOffset + effectiveVisibleCount)`. A clicked visible row maps back to `absoluteIndex = scrollOffset + visibleRowIndex` before selecting/crafting.
- Mouse-wheel input over the list changes the offset by `Math.sign(deltaY)` row per wheel event (zero delta is ignored), then clamps it. Wheel scrolling intentionally changes the viewed window without changing the absolute `selectedIndex`; the selected recipe may be temporarily outside the window. The next Up/Down/W/S selection restores visibility with `ensureVisible`, and Enter still acts on the selected recipe. It is registered only while the overlay is open and is cleaned up on close/destroy.
- When `recipes.length <= effectiveVisibleCount`, `maxOffset` is zero and no scroll movement is possible. When more recipes exist than fit in the current window, the list exposes a small scroll cue/indicator without adding a panel background.

### Availability and refresh

Use the existing `canCraft` and `craft` functions as the single source of truth, including the `uniqueOutput` rule. Inventory changes continue to rebuild the rows so quantities, missing-state styling, and unique-output availability are current. A successful craft therefore immediately updates the same list through the existing inventory event flow.

## Layout and rendering

`CraftingUI` remains responsible for composition, modal registration, pause state, and keyboard bindings. Its build routine changes to:

- Create a screen-space container at the camera center with no backdrop or parent fill/stroke.
- Compute a responsive list width from the camera width with horizontal insets, capped at the existing desktop width.
- Use fixed layout constants (`MAX_VISIBLE_COUNT = 8`, `ROW_GAP = 6`, `LIST_INSET = 16`, `MIN_ROW_HEIGHT = 36`) and compute `availableHeight = Math.max(1, camera.height - 2 * LIST_INSET)`. The effective visible count is `Math.min(MAX_VISIBLE_COUNT, Math.max(1, Math.floor((availableHeight + ROW_GAP) / (MIN_ROW_HEIGHT + ROW_GAP))))`. When the effective count is eight, compute `rowHeight = Math.floor((availableHeight - (MAX_VISIBLE_COUNT - 1) * ROW_GAP) / MAX_VISIBLE_COUNT)`; otherwise use `MIN_ROW_HEIGHT`. The list height is `effectiveVisibleCount * rowHeight + (effectiveVisibleCount - 1) * ROW_GAP`. Normal viewports therefore show eight rows; unusually short viewports show the largest readable count that fits and use a non-zero offset range to reach the rest.
- Render only `RECIPES.slice(scrollOffset, scrollOffset + effectiveVisibleCount)` (plus the selected-state mapping to the absolute recipe index). Virtualizing the visible slice avoids Phaser mask/overflow edge cases and guarantees that off-window rows cannot steal pointer input.
- Use a row layout with an output icon/thumbnail, a text column (recipe name and its own description, both always rendered), and a right-aligned cost column. Reserve at least 84 px for costs and 34 px for the output icon; on narrow widths, stack cost chips vertically and ellipsize the description so icons/quantities cannot overlap the copy.
- Resolve ordinary output/material icons through `itemRegistry` and honor `iconFrame`; retain `createWeaponThumbnail` for weapon outputs.
- Store the list's screen bounds for wheel hit testing; no visual wheel-capture geometry is needed. The named `CraftingUI.handleCraftingWheel` scene listener consumes only deltas whose pointer lies inside those bounds. `WorldScene.handleCameraWheel` must return while `craftingUI.isOpen()` so the existing camera zoom listener cannot zoom the world, regardless of listener registration order, while the crafting list is open. Because only row zones are interactive, wheel handling cannot cover or steal row pointer clicks.
- Rebuild on camera/scale resize while open, preserving the selected absolute recipe index and clamping the scroll offset.

The parent container is still useful as a lifecycle/depth owner, but it must have no visible geometry. Only row graphics and their child text/images are added to it. The panel-level `C / Esc to close` hint is removed from rendering; the existing close keys remain functional. Recipe-level descriptions remain visible because they describe each row, not the removed panel instructions.

### Pure layout helper

Create `src/game/ui/CraftingLayout.ts` with no Phaser or inventory dependencies. It exposes the maximum visible-count constant and pure functions for effective visible count, `maxOffset`, offset clamping, selected-index visibility, visible-range slicing, and responsive row height. Clamping normalizes non-finite recipe counts/offsets to safe zero values before applying integer bounds. `CraftingUI` delegates all index/window math to this helper so pointer, keyboard, wheel, resize, and tests share the same rules.

## State and ownership boundaries

- `CraftingUI`: owns selected index, scroll offset, visible-row construction, Phaser row hit areas, wheel listener lifecycle, and visual availability feedback.
- `src/game/crafting/Crafting.ts`: remains the owner of recipe selection, `canCraft`, inventory transaction, and `craft.completed` events. No duplicate affordability logic is added to the UI.
- `itemRegistry`: remains the owner of item names and icon metadata. The UI reads this metadata for material cost icons and output icons.
- `ModalStack` and `WorldScene`: keep their current open/close and pause contracts. No crafting implementation moves into `WorldScene`.

This change is limited to the portable crafting overlay. Inventory, shop, quest, and other panels are out of scope.

## Edge cases

- Empty recipe catalog: build an empty transparent list without attempting to clamp to a negative selected index; keyboard actions become no-ops.
- Inventory refresh while open: destroy the old row objects/list zone, clamp selection/window, then rebuild once.
- A recipe becomes unavailable between pointer-down and the transaction: `craft` rechecks `canCraft`; the failed transaction gets the same missing-state pulse and no completion callback.
- If `canCraft` is true but `craft` still returns false because the inventory transaction cannot accept the output, pulse the whole row in amber for the same short feedback duration; do not spend ingredients or invoke `onCrafted`.
- A unique output is already owned: keep the recipe visible, show its muted state, and provide the unavailable-row pulse on click.
- Resize while scrolled: retain the selected recipe where possible and clamp the window to the new maximum offset.
- Listener ownership is explicit: inventory and keyboard listeners are installed by the constructor and removed only by `destroy`; wheel and scale-resize listeners are installed by `open`, removed by `close`, and guarded against duplicate registration on reopen. `destroy` removes any still-open wheel/resize listeners before destroying the container. All cleanup is idempotent.

## Verification criteria

Manual verification in the running game should cover:

1. The world remains visible; no panel title, instructional line, footer, dimming rectangle, or opaque parent frame appears.
2. Eight rows are visible at once on the normal viewport; a ninth or later recipe is reachable by wheel and keyboard scrolling.
3. Clicking any part of an available row crafts it, including the former locations occupied by the Craft buttons.
4. Clicking an unavailable row never consumes materials and produces only the brief missing-state feedback.
5. Material icons and required quantities are readable at both wide and narrow viewport sizes.
6. Keyboard selection/Enter crafting still works and selected rows auto-scroll into view.
7. Inventory changes and resize rebuilds do not leave stale hit areas or listeners.

Run the repository's existing `pnpm check` command after implementation. Extract the visible-window/scroll-offset formulas into a small pure `src/game/ui/CraftingLayout.ts` helper and add table-driven tests under `scripts/tests/crafting/` loaded through the existing Vite SSR test pattern. Extend the `test:ui` package script to include that test file. Cover zero/one/eight/nine/many recipes, selected-index wrapping, offset clamping, clicked-row absolute-index mapping, compact-viewport row sizing, and non-finite (`NaN`/`Infinity`) recipe-count, offset, and camera-height inputs. Manual game verification covers Phaser hit-area layering, wheel-versus-camera-zoom behavior, craft success/failure feedback, inventory refreshes, and listener cleanup.
