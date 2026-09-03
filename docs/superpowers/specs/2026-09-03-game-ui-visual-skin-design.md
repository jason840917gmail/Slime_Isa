# Game UI Visual Skin System

## Goal

Give the player-facing UI a distinctive, cohesive visual identity for the top-down slime game. Replace flat procedural panel shapes with a small family of high-resolution, non-pixel-art illustrated surfaces while keeping all gameplay data and interaction states dynamic.

The approved direction is a cozy organic base with biome-specific accents:

- mosswood, amberleaf, translucent slime, crystal caverns, berry gathering, and friendly field gear;
- moss green, amber gold, berry violet, crystal cyan, warm soil brown, and deep blue-green shadow;
- soft hand-painted 2D illustration, clean readable interiors, subtle material texture, and no pixel art;
- translucent slime seams and small gel droplets as the signature motif for frames, dividers, and selection states.

## Scope

### Player-facing runtime surfaces

The visual pass covers these runtime surfaces, in this order:

1. Inventory panel
2. Crafting panel
3. Quest journal
4. World map
5. Level-up modal
6. Quest offer / turn-in modal
7. Shop popup
8. HUD status block
9. Minimap frame
10. Weapon hotbar
11. Ability bar
12. Boss health bar
13. Chat log and chat input
14. Interaction prompt
15. Area title card
16. Combat combo indicator

World-space player health bars and floating combat text remain primarily code-rendered because they follow moving entities. They receive a smaller treatment pass for frame shape, iconography, typography, and feedback effects rather than full bitmap backgrounds.

The developer tools, save/load dialogs, map editor, Character Studio, Projectile Studio, and Weapon Studio are separate HTML/CSS surfaces. They are not included in the player-facing art pack; their industrial field-cartographer treatment should remain independent.

## Visual approach

Use a shared visual-skin system rather than a unique unrelated illustration for every surface. The system has four families:

### Large modal frame

Used by inventory, crafting, journal, map, quest offer, and level-up. It provides an organic illustrated border, quiet interior space, and stable corner details that can survive scaling. The center must remain low-detail so dynamic text and item art stay legible.

### Compact HUD frame

Used by the HUD, minimap, hotbar, ability bar, chat, interaction prompt, and area title card. It uses a lighter footprint, simplified corners, and repeatable edge treatment so permanent screen-space UI does not dominate gameplay.

### Journal/map paper surface

Used by the quest journal and world map. It uses warm parchment or pressed-fiber material with moss, ink, and biome color accents. The map interior remains open for runtime routes, discovered nodes, labels, and camera markers.

### Special event frame

Used by level-up and boss presentation. It can use stronger contrast, glow, crystal accents, and larger silhouettes while still sharing the same organic seam language.

## Dynamic versus static content

Generated artwork supplies only the visual surface:

- frames, borders, corners, empty slot wells, dividers, material texture, and decorative motifs;
- no baked item names, counts, quest text, prices, controls, progress values, or buttons;
- no baked Unicode glyphs that could become corrupted or inaccessible;
- no pixel-art treatment, hard pixel scaling, or tiny painted text.

Code continues to own:

- item icons, quantities, descriptions, recipe costs, quest progress, map routes, discovery markers, health fills, cooldown overlays, button states, hover/focus states, and responsive layout;
- all pause, modal-stack, keyboard, pointer, and resize behavior.

For responsive layouts, artwork should be authored as a broad clean backplate or frame source and consumed through a stretchable frame strategy. Fixed decorative details must stay near the corners and edges; the content area must tolerate desktop and narrow viewport sizes.

## First asset batch

Generated source art is kept under `asset/Originals/ui/` for provenance and iteration. Final runtime copies must live under `asset/UI/`, be added to `asset/assets.json` with stable IDs and dimensions, and be loaded through the existing asset loader. `asset/Originals/ui/` is never a runtime load path.

Create these source images first:

1. `ui-organic-modal-frame.png` — reusable large frame/backplate, clean content-safe interior, no text
2. `ui-organic-compact-frame.png` — reusable compact HUD frame, no text
3. `ui-inventory-backplate.png` — inventory-specific surface with subtle slot-zone guidance but no item art or labels
4. `ui-map-journal-paper.png` — warm map/journal material with empty center space, no text or map symbols
5. `ui-organic-minimap-frame.png` — square minimap frame with quiet map-safe interior, no compass, markers, or labels

The first batch validates palette, texture density, edge readability, and the non-pixel-art treatment before special-case assets are produced. If a generated source is missing or malformed at runtime, the UI falls back to the existing code-drawn surface and reports a development warning; production must not crash because a skin is unavailable. Repository validation remains strict: `assets:check` must reject missing or malformed manifest entries before release.

### Loading contract

UI art joins the existing `boot` bundle. The runtime path is:

1. Add the final runtime copy under `asset/UI/` and add its stable asset ID to `asset/assets.json` under `bundles.boot`.
2. `ProceduralAssetScene.preload()` calls `loadAssetBundle(this, 'boot')`, which queues the image files.
3. `ProceduralAssetScene.create()` calls `assertAssetBundleTextures(this, 'boot')` after procedural textures are created.
4. UI constructors resolve the stable asset ID to its runtime texture key. If a UI skin texture is unavailable at runtime, the owning surface uses its existing code-drawn fallback and emits a development warning.

`assetUrls.ts` currently supplies a self-contained placeholder URL when a manifest path has no bundled Vite URL. Therefore the boot assertion verifies that queued bundle textures exist, but cannot by itself prove that the source file was present when the placeholder was used. `assets:check` is the required source-of-truth gate for missing or malformed manifest paths; do not describe the boot assertion as detecting those stale source files. A future strict-loading mode may turn this into a boot failure, but that is outside this visual pass.

## Surface-to-asset mapping

Each panel uses one explicit composition. The asset is a visual layer only; dynamic children are rendered above it.

| Surface | Base asset | Optional accent layer | Dynamic content stays in code |
| --- | --- | --- | --- |
| Inventory | `ui-inventory-backplate` | shared slot/button treatment | items, counts, selection, details, equip/use/delete actions |
| Crafting | `ui-crafting-workbench-backplate` | ingredient/output slot treatment | recipe rows, icons, costs, availability, craft feedback |
| Quest journal | `ui-quest-journal-backplate` over `ui-map-journal-paper` | status tabs and quest markers | quest lists, progress, descriptions, actions, scrolling |
| World map | `ui-map-journal-paper` | biome corner emblem and compass | routes, discovered nodes, current location, labels |
| Level up | `ui-levelup-crest-frame` over shared modal frame | glow and perk-card accent | perk choices, ranks, descriptions, key prompts |
| Quest offer/turn-in | `ui-quest-offer-scroll-frame` | NPC/quest emblem | title, description, objectives, rewards, errors, buttons |
| Shop | `ui-shop-stall-frame` | merchant badge | offers, prices, purchase result, close action |
| HUD | `ui-organic-compact-frame` | resource icons | level, coins, friends, HP/XP/energy values and fills |
| Minimap | `ui-organic-minimap-frame` | code-drawn compass marker | terrain/map data, player/friend/house markers, camera rectangle |
| Weapon hotbar | `ui-organic-compact-frame` plus code-native slot treatment | active-slot seam | weapon thumbnails, ownership, equipped state, key labels |
| Ability bar | `ui-organic-compact-frame` plus code-native ability slot treatment | cooldown overlay | ability icons, unlock levels, cooldown state, hotkeys |
| Boss bar | `ui-boss-health-frame` | boss portrait/phase accent | boss name, HP fill, HP text, defeat animation |
| Chat | `ui-organic-compact-frame` for the Phaser log | CSS-matched DOM input treatment | chat messages, focus, text entry, resize behavior |
| Interaction prompt | code-drawn compact prompt badge | interaction icon | candidate prompt text, visibility, keyboard action |
| Area title card | `ui-area-title-banner` | biome emblem | area title, biome color, transition timing |
| Combo indicator | code-drawn combat badge | combo/finisher accent | count, multiplier, animation, reset timing |
| Player/world health bars | code-drawn compact bar | optional stable health icon | moving position, HP fill, auto-hide timing |
| Floating combat text | code-rendered text treatment | optional impact emblem | damage/reward text, color, position, lifetime |

The minimap uses the square `ui-organic-minimap-frame` as its fixed frame treatment; its terrain, markers, and camera rectangle remain code-rendered. Chat uses the wide `ui-organic-compact-frame`: preserve the end caps and extend the quiet center to the log width, with the DOM input aligned below it. The interaction prompt, combo indicator, health bars, and floating text do not require raster backgrounds unless a later test shows the code treatment cannot achieve the desired identity. The area title uses `ui-area-title-banner` with a code-drawn banner fallback.

The weapon hotbar, AbilityBar, and chat log each use `ui-organic-compact-frame` when available and retain their existing code-drawn frame geometry as the explicit fallback. The minimap similarly falls back to its existing code-drawn circular/rectangular frame if `ui-organic-minimap-frame` is unavailable.

The map/journal material is the interior surface for those two panels; it does not replace the shared modal frame where a framed outer silhouette is needed. The inventory and crafting backplates are panel-specific because their safe areas and visual affordances differ.

## Raster and responsive contract

- Master large-panel sources target a 4:3 canvas at approximately 2048×1536; compact sources target a wide canvas at approximately 2048×512. The final files may be downscaled only after visual inspection, and must remain sharp at the largest supported display size.
- Author a generous quiet content-safe area. Decorative corners and seams stay within the outer 12% of each edge; no important detail is placed in the stretch zone.
- Use RGBA PNG when the silhouette needs transparent outside corners. Opaque rectangular backplates are acceptable when the artwork is intentionally edge-to-edge. Generated images must contain no text, item art, or baked controls.
- Display artwork with preserved aspect ratio and calculated safe insets. Do not stretch a corner ornament independently. If a panel needs dimensions outside the source ratio, preserve the corners and extend the quiet center through a tiled or carefully cropped surface strategy.
- Wide layout: at least 900 px viewport width uses the authored panel proportions with 24–32 px screen margins.
- Medium layout: 600–899 px uses the same skin scaled down with reduced insets; text and dynamic rows may reflow.
- Narrow layout: below 600 px uses viewport width minus 24 px, viewport height minus 24 px, and scrollable content for journal, crafting, and inventory details. The skin must not reduce readable body text below its existing minimum.
- Rebuild or reposition open overlays on `scale.resize`; never leave a background at the old dimensions while dynamic children move.
- Treat 1× logical display size as the normal target. Do not enlarge a source beyond 1.5× without a larger source or a visibly clean center-extension strategy. Inspect on both standard and high-DPI displays.

| Asset | Source target | Normal logical display | Safe inset | Center strategy |
| --- | --- | --- | --- | --- |
| Organic modal frame | 2048×1536 | 700×520 maximum | 160 px horizontal, 144 px vertical | preserve corners; scale or crop the quiet center |
| Organic compact frame | 2048×512 | 280–520×56–84 | 72 px horizontal, 64 px vertical | preserve end caps; extend the center |
| Inventory backplate | 2048×1152 | 700×360 | 160 px horizontal, 120 px vertical | preserve outer frame; keep slot/detail regions quiet |
| Map/journal paper | 2048×1536 | 560×330 or 620×520 | 144 px horizontal, 120 px vertical | scale-to-fit paper texture; runtime content controls contrast |
| Organic minimap frame | 1024×1024 | 168–192 px square | 72 px on all sides | preserve all four corners; no horizontal stretch |
| Crafting workbench backplate | 2048×1152 | 700×420 | 160 px horizontal, 120 px vertical | preserve workbench edges; extend the quiet recipe center |
| Quest journal backplate | 2048×1536 | 620×520 | 144 px horizontal, 120 px vertical | preserve corners; keep the scroll region low-detail |
| Quest offer scroll frame | 2048×1152 | 660×420 | 144 px horizontal, 112 px vertical | preserve curled ends; extend the quiet center |
| Shop stall frame | 2048×1152 | 660×420 | 144 px horizontal, 112 px vertical | preserve stall silhouette; extend the quiet center |
| Level-up crest frame | 2048×1536 | 680×500 | 160 px horizontal, 144 px vertical | preserve crest corners; keep perk-card area calm |
| Boss health frame | 2048×512 | 640×96 | 72 px horizontal, 64 px vertical | preserve end caps; extend the center bar |
| Area title banner | 2048×512 | 560×84 | 72 px horizontal, 64 px vertical | preserve end caps; extend the quiet title center |

Batch 4 remains code-native by default and has no required raster contract. If a slot, button, tab, compass, chat, or prompt accent is later promoted to raster art, it must receive an explicit source target, logical display bound, safe inset, and center/tiling strategy before generation.

Per-surface layout rules are explicit:

- Inventory uses six columns at wide sizes. Below 600 px it uses four columns, moves the detail pane below the grid, and lets the content scroll vertically.
- Crafting keeps a single readable recipe column at wide sizes. Below 600 px each row stacks output, description, costs, and action vertically; the list scrolls.
- Quest journal uses a scrollable content region at all sizes. Below 600 px it reduces horizontal padding and keeps status sections in a single column.
- World map scales the map drawing to the available inner rectangle. Below 600 px labels wrap below nodes and the footer becomes a compact legend row.
- Level-up cards stay side-by-side at 900 px and above. Below 900 px they become a single-column selectable list with the same card art and a scrollable modal body.
- Quest offer and shop preserve their frame but reflow objective/reward rows and stack action buttons below 600 px.
- HUD, minimap, hotbar, chat, and interaction prompts use viewport-safe margins. The chat DOM input width is `min(480px, viewport width - 24px)` and remains above the canvas with its own focus ring.
- The minimap keeps a square logical box (168–192 px on wide layouts, reduced only as needed on narrow layouts); it never consumes the compact frame’s horizontal extension rule. Chat keeps a wide log frame with preserved end caps, a center extension, and a DOM input below it at `min(480px, viewport width - 24px)`.

## Follow-up asset batches

### Batch 2: functional panels

- `ui-crafting-workbench-backplate.png`
- `ui-quest-journal-backplate.png`
- `ui-quest-offer-scroll-frame.png`
- `ui-shop-stall-frame.png`

### Batch 3: special moments

- `ui-levelup-crest-frame.png`
- `ui-boss-health-frame.png`
- `ui-area-title-banner.png`

### Batch 4: compact decorations

- slot frame variants for inventory and hotbars;
- button, tab, selected, disabled, and warning accents;
- minimap compass/edge ornament;
- chat speech-bubble and interaction-prompt accents.

These compact pieces may be better implemented as code-native shapes if raster artwork would make them less flexible. The art pass should only generate them when the shared frame assets do not provide enough visual identity.

## Runtime integration plan

1. Fix or remove corrupted characters in player-facing strings, including `Â·`, `â€”`, `â—`, `Ã—`, and malformed ability glyphs. Prefer asset-backed icons or simple code shapes over decorative Unicode.
2. Inventory all remaining visible glyphs (`▶`, `✓`, `•`, `×`, `·`, and malformed ability/map/combo symbols). Replace decorative glyphs with code-drawn shapes or explicit asset IDs; keep only characters that are intentionally encoded and tested.
3. Add final runtime copies under `asset/UI/` to the media manifest with stable IDs and explicit dimensions. Keep generated sources under `asset/Originals/ui/` only.
4. Introduce a small UI asset resolver/skin definition owned by presentation/UI code. Do not move gameplay balancing, inventory rules, or modal behavior into the asset manifest.
5. Replace the large procedural panel backgrounds in `InventoryUI`, `CraftingUI`, `QuestJournal`, `WorldMapUI`, `LevelUpModal`, `QuestOfferModal`, and `ShopUI` with the mapped skins.
6. Preserve dynamic children and interaction regions. Background artwork must never contain clickable behavior or runtime data.
7. Apply the compact frame to HUD, hotbar, chat, and interaction surfaces as appropriate; apply the square minimap frame to the minimap and the title banner to area titles. Keep `AbilityBar` and `BossHealthBar` in the visual scope, but add a separate mounting task before their acceptance screenshots: instantiate them from `WorldScene`, own their resize/update/cleanup lifecycle, and then apply their skins. Do not silently assume an unwired module is visible.
8. Keep combo presentation owned by `CombatController`. Keep moving health bars and floating text code-rendered, with any frame/icon improvements implemented by their owning modules.
9. Keep the chat input as a DOM control for focus and keyboard reliability. Move its inline styling into a CSS class that matches the compact Phaser frame; do not place a Phaser interaction layer over the DOM input. The CSS contract includes focus ring, z-index above the canvas, viewport-safe width, and resize repositioning.
10. Verify at the normal 1280×720 layout and narrow responsive sizes. Confirm that no text overlaps decorative art, no panel clips dynamic content, and no bitmap is visibly pixelated.

## Cross-cutting quality rules

- Use one depth strategy for player-facing panels: quiet surface layering and restrained borders; special-event panels may add a controlled glow.
- Keep the content area calmer than the border. Decorative detail must not compete with gameplay text.
- Use one consistent font hierarchy with readable labels and no reliance on text stroke for every element.
- Avoid a different hue for every panel. Biome accents identify context; the shared base skin preserves cohesion.
- Keep all controls visibly interactive through hover, active, focus, disabled, and unavailable states.
- Use this state ownership matrix: skin supplies the base/default surface; code supplies selected/active seam, hover/focus emphasis, unavailable/disabled reduction, success confirmation, and danger/warning emphasis. No state may be communicated by color alone; pair it with border, icon, text, motion, or shape.
- Treat the world behind modal overlays deliberately: large decision modals may dim the world, while lightweight list overlays may keep it visible when readability allows.
- Use actual icons for items, perks, abilities, currencies, and rewards wherever an icon already exists or can be generated cleanly.

## Icon and glyph contract

- Inventory and crafting item/material icons come from `itemRegistry` and existing authored/procedural item textures.
- Weapon thumbnails continue to come from `WeaponThumbnail` and `WeaponIcon` metadata.
- Perk icons use the existing perk icon key; if a key is missing, use a stable code-drawn fallback, not a Unicode glyph.
- Ability icons need explicit texture keys or small code-drawn silhouettes before `AbilityBar` is mounted. The strings in `AbilityBar.ts` must not use malformed glyphs as the permanent icon source.
- Currency, reward, current-location, discovered, locked, selected, close, and unavailable indicators use explicit small graphics or named texture IDs. Separators and bullets are layout elements, not characters embedded in data strings.
- The visible `âŒ¨ Controls` string in `src/game/config.ts` is included in the glyph cleanup; use `Controls` or a tested icon asset.

## Verification

Visual verification must cover:

- panel readability over the game world;
- legibility of dynamic text over each material;
- correct scaling and corner preservation at wide and narrow viewports;
- no visible pixel-art or low-resolution artifacts;
- consistent visual language across all player-facing surfaces;
- clean rendering of all repaired strings and replacement icons;
- no interaction regression when panel children are rebuilt or resized.

The manual screenshot/scenario matrix is:

| Scenario | Viewports | States to inspect |
| --- | --- | --- |
| Inventory | 1280×720, 800×600, 390×720 | empty slot, selected item, equipment, consumable, disabled action, long description |
| Crafting | 1280×720, 800×600, 390×720 | craftable, missing materials, unique output owned, long recipe name, scroll/resize |
| Journal | 1280×720, 800×600, 390×720 | available, active, completed, failed/history, many quests, command error |
| Map | 1280×720, 800×600, 390×720 | unknown, discovered, current area, long area name, route visibility |
| Level-up/quest/shop | 1280×720, 800×600, 390×720 | default, hover/focus, error, long labels, dimmed world |
| HUD/minimap/hotbar/chat | 1280×720, 800×600, 390×720 | full/low HP, max XP, active slot, empty slot, chat focus, interaction prompt |
| Ability bar | 1280×720, 800×600, 390×720 | deferred-pass after `AbilityBar` is mounted: unlocked, locked, active, cooldown, empty slot, resize/cleanup |
| World-space feedback | 1280×720, 800×600, 390×720 | player/world health bar full/low/hidden states; floating damage/reward text for overlap, contrast, lifetime, and position tracking |
| Special events | supported viewport sizes | active-pass: area title and combo streak; deferred-pass after `BossHealthBar` is mounted: boss active/low HP/defeat |

Pass criteria include readable dynamic text, visible non-color state cues, preserved frame corners, no overlap or clipping, no visible pixelation, aligned DOM chat input, and no stale pointer/keyboard behavior after resize or rebuild.

The existing `pnpm check` command remains the final repository verification after runtime integration.
