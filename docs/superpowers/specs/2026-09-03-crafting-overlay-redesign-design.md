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
- Replace text such as `Wood 40/20` with the material icon and required quantity, using the registered item icon/frame for each ingredient. A craftable cost chip shows only the required quantity; an insufficient cost chip shows `current/required` beside the icon so the player can tell how close they are without returning to the old text-only format.
- Keep the selected-row treatment (accent border/indicator) so keyboard navigation remains legible without a panel frame.

The companion mockup at `http://localhost:64238/` demonstrates this visual structure at a narrow viewport as well as the ninth-row scroll case.

## Interaction behavior

### Row clicks

Each visible recipe row owns a `Phaser.GameObjects.Zone` centered on the row, sized to the exact row width/height, and added to the same screen-space container as the row graphics. The zone is the only interactive object in that row and is added before non-interactive text/image children. A primary-button pointer click (`pointer.button === 0`) performs these operations in order:

1. Select the clicked recipe.
2. If `canCraft(recipe)` is true, call the existing `craft(recipe)` service and invoke `onCrafted` when it succeeds.
3. If the recipe cannot be crafted, do not consume inventory or emit a completion event. Briefly pulse the missing cost chip(s) (and the muted row for a unique item that is already owned) so the click has clear, lightweight feedback without restoring a footer or modal message.

The hit area belongs to the row and is destroyed with the row container. There will be no manual `clickRegions` array and no scene-wide `pointerdown` coordinate scan. This prevents overlapping controls, stale rectangles after a refresh, and clicks being intercepted by unrelated UI layers. The list owns the highest screen-UI depth; the world remains visible but is paused and cannot win a row click. Clicks outside a row do nothing.

The transparent parent also owns an invisible full-screen `Phaser.GameObjects.Zone` modal shield at the same screen-UI depth, created before row zones. The shield has no fill, border, or shadow; its `pointerdown` handler calls `event.stopPropagation()` and otherwise does nothing. Row zones are added afterward so they win hit testing, stop propagation after handling the click, and remain the only actionable controls. This shield prevents lower-depth controls such as the weapon hotbar from receiving clicks while crafting is open without making the game world visually dim or covered.

Unavailable feedback lasts 180 ms: missing cost chips tween to the missing color and back; a transaction failure that occurs despite `canCraft` pulses the whole row in amber for the same duration. The tween is presentation-only and is canceled when the container is rebuilt or closed.

### Keyboard and scrolling

- Preserve Up/Down and W/S selection and Enter-to-craft.
- Keep `selectedIndex` over the complete recipe list, not only the currently visible slice.
- Define `MAX_VISIBLE_COUNT = 8`; derive `capacityCount` from the camera height as described in Layout and Rendering, then set `maxOffset = Math.max(0, recipes.length - capacityCount)`.
- Define dependency-free `clampOffset(offset)`: truncate finite values, treat non-finite values as zero, then clamp to `[0, maxOffset]`.
- When a selection changes, use `ensureVisible(index, offset, capacityCount)`: return `index` when `index < offset`; return `index - capacityCount + 1` when `index >= offset + capacityCount`; otherwise return `offset`; then clamp the result.
- Render `recipes.slice(scrollOffset, scrollOffset + capacityCount)`. A clicked visible row maps back to `absoluteIndex = scrollOffset + visibleRowIndex` before selecting/crafting.
- Mouse-wheel input over the list changes the offset by `Math.sign(deltaY)` row per wheel event (zero delta is ignored), then clamps it. Wheel scrolling intentionally changes the viewed window without changing the absolute `selectedIndex`; the selected recipe may be temporarily outside the window. The next Up/Down/W/S selection restores visibility with `ensureVisible`, and Enter still acts on the selected recipe. It is registered only while the overlay is open and is cleaned up on close/destroy.
- When `recipes.length <= capacityCount`, `maxOffset` is zero and no scroll movement is possible. When more recipes exist than fit in the current window, the list exposes a small scroll cue/indicator without adding a panel background.

### Availability and refresh

Use the existing `canCraft` and `craft` functions as the single source of truth, including the `uniqueOutput` rule. Inventory changes continue to rebuild the rows so quantities, missing-state styling, and unique-output availability are current. A successful craft therefore immediately updates the same list through the existing inventory event flow.

## Layout and rendering

`CraftingUI` remains responsible for composition, modal registration, pause state, and keyboard bindings. Its build routine changes to:

- Create a screen-space container at the camera center with no backdrop or parent fill/stroke.
- Compute a responsive list width from the camera width with horizontal insets, capped at the existing desktop width.
- Use fixed layout constants (`MAX_VISIBLE_COUNT = 8`, `ROW_GAP = 6`, `LIST_INSET = 16`, `MIN_ROW_HEIGHT = 68`, `MAX_ROW_HEIGHT = 76`) and normalize the camera height first: `safeCameraHeight = Number.isFinite(camera.height) ? Math.max(1, camera.height) : 1`; then `availableHeight = Math.max(1, safeCameraHeight - 2 * LIST_INSET)`. The capacity count is `Math.min(MAX_VISIBLE_COUNT, Math.max(1, Math.floor((availableHeight + ROW_GAP) / (MIN_ROW_HEIGHT + ROW_GAP))))`. Compute `rowHeight = Math.min(MAX_ROW_HEIGHT, Math.floor((availableHeight - (capacityCount - 1) * ROW_GAP) / capacityCount))`. The actual window count is `Math.min(recipeCount, capacityCount)`, so a short viewport uses a readable smaller window and a catalog with four recipes does not reserve four empty rows. A normal viewport shows eight rows at 68–76 px each; unusually short viewports expose the largest readable count that fits and use a non-zero offset range to reach the rest.
- Center the capped list in the camera: `listHeight = windowCount * rowHeight + Math.max(0, windowCount - 1) * ROW_GAP`, with the list's top at `-listHeight / 2` relative to the screen-space container center. This keeps tall viewports from stretching rows or pinning the list to an edge.
- Render only `recipes.slice(scrollOffset, scrollOffset + capacityCount)` (plus the selected-state mapping to the absolute recipe index). Virtualizing the visible slice avoids Phaser mask/overflow edge cases and guarantees that off-window rows cannot steal pointer input.
- Use a row layout with an output icon/thumbnail, a text column (recipe name and its own description, both always rendered), and a right-aligned cost column. Reserve at least 84 px for costs and 34 px for the output icon; on narrow widths, stack cost chips vertically and ellipsize the description so icons/quantities cannot overlap the copy.
- Resolve ordinary output/material icons through `itemRegistry` and honor `iconFrame`; retain `createWeaponThumbnail` for weapon outputs.
- Store the list's screen bounds for wheel hit testing; no visual wheel-capture geometry is needed. The named `CraftingUI.handleCraftingWheel` scene listener consumes only deltas whose pointer lies inside those bounds. `WorldScene.handleCameraWheel` must return while `craftingUI.isOpen()` so the existing camera zoom listener cannot zoom the world, regardless of listener registration order, while the crafting list is open. Because the modal shield and row zones stop pointer propagation, wheel handling cannot cover or steal row pointer clicks.
- Rebuild on camera/scale resize while open, preserving the selected absolute recipe index and clamping the scroll offset.

The parent container is still useful as a lifecycle/depth owner, but it must have no visible geometry. Only row graphics and their child text/images are added to it. The panel-level `C / Esc to close` hint is removed from rendering; the existing close keys remain functional. Recipe-level descriptions remain visible because they describe each row, not the removed panel instructions.

### Pure layout helper

Create `src/game/ui/CraftingLayout.ts` with no Phaser or inventory dependencies. It exposes the maximum visible-count constant and pure functions for capacity count, `windowCount = Math.min(recipeCount, capacityCount)`, `maxOffset`, offset clamping, selected-index visibility, visible-range slicing, and responsive row height. Clamping normalizes non-finite recipe counts/offsets to safe zero values before applying integer bounds, and row sizing normalizes non-finite camera heights to a safe finite fallback. `CraftingUI` delegates all index/window math to this helper so pointer, keyboard, wheel, resize, and tests share the same rules.

## State and ownership boundaries

- `CraftingUI`: owns selected index, scroll offset, visible-row construction, Phaser modal/row hit areas, wheel listener lifecycle, and visual availability feedback. It accepts an optional test-only recipe source in its context, defaulting to production `RECIPES`, so scroll behavior can be exercised without changing the live catalog.
- `src/game/crafting/Crafting.ts`: remains the owner of the production recipe catalog, `canCraft`, inventory transaction, and `craft.completed` events. No duplicate affordability logic or selection state is added to the crafting service.
- `itemRegistry`: remains the owner of item names and icon metadata. The UI reads this metadata for material cost icons and output icons.
- `ModalStack` and `WorldScene`: keep their current open/close and pause contracts. No crafting implementation moves into `WorldScene`.

This change is limited to the portable crafting overlay. Inventory, shop, quest, and other panels are out of scope.

## Edge cases

- Empty recipe catalog: build an empty transparent list without attempting to clamp to a negative selected index; keyboard actions become no-ops.
- Inventory refresh while open: destroy the old row objects/modal shield, clamp selection/window, then rebuild once.
- A recipe becomes unavailable between pointer-down and the transaction: `craft` rechecks `canCraft`; the failed transaction gets the same missing-state pulse and no completion callback.
- If `canCraft` is true but `craft` still returns false because the inventory transaction cannot accept the output, pulse the whole row in amber for the same short feedback duration; do not spend ingredients or invoke `onCrafted`.
- A unique output is already owned: keep the recipe visible, show its muted state, and provide the unavailable-row pulse on click.
- Resize while scrolled: retain the selected recipe where possible and clamp the window to the new maximum offset.
- Listener ownership is explicit: inventory and keyboard listeners are installed by the constructor and removed only by `destroy`; wheel and scale-resize listeners are installed by `open`, removed by `close`, and guarded against duplicate registration on reopen. `destroy` removes any still-open wheel/resize listeners before destroying the container. All cleanup is idempotent.

## Verification criteria

Manual verification in the running game should cover:

1. The world remains visible; no panel title, instructional line, footer, dimming rectangle, or opaque parent frame appears.
2. Eight rows are visible at once on the normal viewport. A nine-row test/development fixture confirms that the ninth recipe is reachable by wheel and keyboard scrolling without adding fake recipes to the production portable catalog.
3. Clicking any part of an available row crafts it, including the former locations occupied by the Craft buttons.
4. Clicking an unavailable row never consumes materials and produces only the brief missing-state feedback.
5. Material icons and required quantities are readable at both wide and narrow viewport sizes.
6. Keyboard selection/Enter crafting still works and selected rows auto-scroll into view.
7. Inventory changes and resize rebuilds do not leave stale hit areas or listeners.

Run the repository's existing `pnpm check` command after implementation. Extract the visible-window/scroll-offset formulas into a small pure `src/game/ui/CraftingLayout.ts` helper and add table-driven tests under `scripts/tests/crafting/` loaded through the existing Vite SSR test pattern. Extend the `test:ui` package script to include that test file. Cover zero/one/eight/nine/many synthetic recipe counts, selected-index navigation wrapping (computed by the helper but owned by `CraftingUI`), offset clamping, clicked-row absolute-index mapping, compact-viewport row sizing, max-height centering, and non-finite (`NaN`/`Infinity`) recipe-count, offset, and camera-height inputs. The production portable catalog currently has four recipes; do not add fake recipes to it. For manual nine-row UI verification, pass a test/development fixture through the optional recipe source and keep that fixture out of production builds. Manual game verification covers modal-shield layering against the hotbar, row hit areas, wheel-versus-camera-zoom behavior, craft success/failure feedback, inventory refreshes, and listener cleanup.
