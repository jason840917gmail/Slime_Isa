# World HUD Artwork-First Presentation

## Status

Approved visual direction on 2026-09-04. This is the implementation spec for
the next in-world HUD polish pass. It refines the broader
[Game UI Visual Skin System](2026-09-03-game-ui-visual-skin-design.md)
without changing inventory or crafting.

## Goal

Make the permanent gameplay HUD feel integrated with the authored world
background instead of placing several opaque dark rectangles on top of it.
The world remains the dominant visual surface. UI chrome should communicate
hierarchy, interaction, and state with restrained lines, shadows, and color
accents rather than filled boxes.

## Locked visual decision — Option C: Artwork-only / artwork-first

Use the approved **Option C** treatment, also called **artwork-only** or
**artwork-first**:

- no opaque compact-frame center behind the HUD or weapon hotbar;
- omit `ui-organic-compact-frame` entirely from the HUD and weapon hotbar in
  this task; do not add a transparent-center asset or a new helper;
- no dark per-slot fills, drop-shadow slabs, or filled number plates;
- thin organic outlines and small text shadows provide separation from the
  world;
- the selected weapon keeps a gold double-outline/seam and a small downward
  marker so selection is not communicated by color alone;
- HP, XP, and energy keep their colored fills, but their empty tracks are
  transparent with a quiet outline;
- the minimap keeps its organic illustrated outer frame, while its map interior
  becomes a very low-opacity tint so markers and the camera rectangle remain
  readable without recreating the dark square.

The result should feel like field equipment laid over the landscape, not a
dashboard floating in front of it.

## Scope

### Included

- `src/game/HUD.ts`
- `src/game/Minimap.ts`
- `src/game/ui/WeaponHotbar.ts`

### Explicitly excluded

- `src/game/ui/InventoryUI.ts` — currently being redesigned separately;
- `src/game/ui/CraftingUI.ts` — currently being redesigned separately;
- `src/game/ui/AbilityBar.ts` — not mounted in the visible `WorldScene` yet;
  it remains a later composition task;
- large modal panels and editor HTML/CSS surfaces;
- gameplay state, weapon ownership, loadout persistence, and input behavior.

## Layout and content rules

### HUD

- Keep the status block in the upper-left safe area.
- Use an explicit two-line hierarchy: line one contains `Level n` and
  `Coins n` laid out with spacing rather than a separator glyph; line two
  contains `Friends n`. None of the three values is treated as a large
  standalone headline.
- Align `Level n` to the left edge of the HUD content region and `Coins n` to
  its right edge. Render coin counts literally from `0` through `9,999`, use
  one-decimal `k` notation from `10k` through `999.9k`, one-decimal `m`
  notation from `1m` through `999.9m`, and `999m+` above that. The layout must
  support a level label up to `Level 99` and the resulting compact coin label
  without overlap; there is no unbounded raw-digit label in this HUD.
- Use a readable primary size for the level line, a smaller secondary size for
  coins/friends, and a compact value label for each meter.
- Keep meter tracks short enough that the right-hand values never leave the
  viewport. At narrow widths, clamp the meter width before shrinking text.
- Use 8px-class meter geometry with a 1px translucent outline and no dark
  background rectangle. Colored fills remain fully opaque enough to read over
  grass and other bright terrain.
- Use a soft dark text shadow rather than a thick stroke on every label.

### Minimap

- Preserve a square viewport-safe footprint and the existing lower-left
  placement.
- Keep the illustrated `ui-organic-minimap-frame` as the visible organic
  border.
- Replace the near-opaque code-drawn map block with a `0.12–0.20` alpha
  interior tint; target `0.16` in the normal layout. Terrain remains visible
  through it.
- Keep player, friend, house, and camera markers unchanged in meaning and
  color. Give each marker a 1px dark outline (or equivalent contrasting ring)
  so bright and dark terrain do not erase its identity.
- If the optional minimap frame is missing, use the same `0.12–0.20` tint and
  a restrained code-drawn outline; never restore the old near-opaque square.

### Weapon hotbar

- Keep six slots centered above the bottom safe area.
- Remove the full-width compact backplate, slot fill, slot shadow, and filled
  key plate.
- Keep a transparent outlined slot with the existing weapon thumbnail and a
  small `1`–`6` key label tucked into the upper-left corner.
- Reduce fallback glyph size so an empty or unavailable slot never dominates
  the weapon art. Existing thumbnail ownership and equip behavior remain the
  authority.
- If the optional compact frame is unavailable, do not create a replacement
  dark backplate; the hotbar remains transparent and outlined using its
  code-native slot treatment. Because the compact frame is omitted entirely
  from this widget, this is the only hotbar frame path in the task.
- Preserve hover scale and click hit areas. The hit area may remain larger than
  the visible outline to keep input forgiving.

## Responsive behavior

- Wide viewports use the authored positions with viewport-safe margins.
- Medium viewports reduce the HUD meter width and hotbar cell/gap sizes before
  reducing text below its readable minimum.
- The minimum supported logical viewport width for this pass is 284px. Define
  `safeWidth = viewportWidth - 24px`; for the six-slot hotbar, use
  `cell = clamp(floor((safeWidth - 5 * gap) / 6), 40px, 56px)` and
  `gap = clamp(floor((safeWidth - 6 * 40px) / 5), 4px, 8px)`. At 284px this
  resolves to six 40px cells with five 4px gaps, exactly 260px wide. At
  390×720 the visible hotbar width must be at most 366px. Do not claim full
  six-slot containment below 284px until the later action-dashboard/mobile
  workflow task defines a reflow.
- Keep the minimap square and keep the HUD value-label slot inside the same
  viewport-safe width; no element may clip the screen edge. Thumbnail art
  remains at least 22px and key labels at least 8px.
- Existing `scale.resize` listeners remain responsible for rebuilding or
  repositioning the complete visible composition. Every new listener must be
  removed during `destroy`. The minimap's owned decorative frame must be
  destroyed by `Minimap.destroy()`; the HUD owns no decorative frame under
  Option C, and the hotbar root already owns its child artwork and must
  continue destroying the root.

## State and behavior

This is a presentation-only pass. Continue to consume the existing
`GameState`, `EventBus`, minimap inputs, and `playerWeaponLoadout` without
moving ownership or adding a second source of truth. Preserve:

- HUD event updates for coins, friends, HP, XP, energy, and level;
- minimap marker and camera-rectangle calculations;
- weapon slot ownership, equipped state, hover feedback, and pointer input;
- screen-space depth ordering and the dedicated screen UI camera.

The transparent treatment must not turn decorative artwork into an input
surface or allow background imagery to intercept pointer events.

## Verification

Manual review is required at 1280×720, 800×600, and 390×720. Inspect:

- full and low HP, partial XP, and full energy;
- long or changing coin/friend values without clipping;
- minimap markers over bright and dark terrain;
- active, owned, empty, and unavailable weapon slots;
- hover and click behavior after a resize;
- no opaque dark rectangular surface remains in the three scoped widgets;
- with the optional frame loaded, the HUD and hotbar still suppress its opaque
  center by omitting the compact asset entirely, while the minimap uses only
  its illustrated outer frame;
- with the optional frame missing, HUD and hotbar remain transparent with
  code-drawn outlines, and the minimap uses a transparent/low-opacity fallback
  interior rather than the old near-opaque block;
- exercise the missing minimap-frame path in a dev-only harness by removing
  the `ui-organic-minimap-frame` texture from the Phaser texture manager before
  constructing `Minimap` (or by blocking that one local asset request), then
  repeat the screenshot checks with the texture restored;
- the minimap decorative frame is destroyed with `Minimap` and does not survive
  scene teardown;
- inventory and crafting are unchanged.

Run `pnpm typecheck` and `pnpm build` after implementation. Run the complete
`pnpm check` when the wider UI skin batches are ready.
