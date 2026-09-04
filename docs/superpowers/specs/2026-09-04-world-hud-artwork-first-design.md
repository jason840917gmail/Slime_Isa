# World HUD Artwork-First Presentation

## Status

Approved visual direction on 2026-09-04. This is the implementation spec for
the next in-world HUD polish pass. It refines the broader
[Game UI Visual Skin System](./2026-09-03-game-ui-visual-skin-design.md)
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
- Replace the near-opaque code-drawn map block with a low-opacity interior
  tint. Terrain remains visible through it.
- Keep player, friend, house, and camera markers unchanged in meaning and
  color; strengthen only their outlines/size if needed for contrast.

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
  code-native slot treatment.
- Preserve hover scale and click hit areas. The hit area may remain larger than
  the visible outline to keep input forgiving.

## Responsive behavior

- Wide viewports use the authored positions with viewport-safe margins.
- Medium viewports reduce the HUD meter width and hotbar cell/gap sizes before
  reducing text below its readable minimum.
- Narrow viewports keep all six hotbar slots inside `viewport width - 24px` and
  keep the minimap square; no element may clip the screen edge. At 390×720 the
  hotbar's visible width must be at most 366px. If a narrower viewport is
  supported, cells may reduce to 40px and gaps to 4px but must not go below
  those values; thumbnail art remains at least 22px and key labels at least
  8px.
- Existing `scale.resize` listeners remain responsible for rebuilding or
  repositioning the complete visible composition. Every new listener must be
  removed during `destroy`, and every owned decorative frame image must also be
  destroyed with its owning widget (`HUD.destroy()` and `Minimap.destroy()` must
  call `frame?.destroy()`; the hotbar root already owns its child artwork and
  must continue destroying the root).

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
  center while the minimap uses only its illustrated outer frame;
- with the optional frame missing, HUD and hotbar remain transparent with
  code-drawn outlines, and the minimap uses a transparent/low-opacity fallback
  interior rather than the old near-opaque block;
- decorative frame images are destroyed with `HUD` and `Minimap` and do not
  survive scene teardown;
- inventory and crafting are unchanged.

Run `pnpm typecheck` and `pnpm build` after implementation. Run the complete
`pnpm check` when the wider UI skin batches are ready.
