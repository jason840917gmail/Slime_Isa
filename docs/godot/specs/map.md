# Map spec: the minimap and the world map

The minimap in the HUD's lower-left corner and the world map window, as the Phaser build behaves
today, and how the Godot port does it. Phaser sources are under `src/game/`; file:line references
are to the commit this port was written against. Godot files: `godot/game/ui/map/`, mounted from
`godot/game/ui/hud.gd`; tests in `godot/tests/test_map.gd`.

Tags: **[IN]** ported, **[OUT]** not ported (with the reason and the owner), **[DIFF]** deliberate
difference.

## 0. Pieces

| Phaser | Live? | Godot |
|---|---|---|
| `features/ui/MinimapSurfacePort.ts` (canvas renderer) + `content/scenes/authored/ui/minimap.scene.json` (Control host, frame) | yes | `game/ui/map/minimap.gd` (`Minimap`), `map_terrain.gd` (`MapTerrain`) |
| `features/ui/WorldMapSurfacePort.ts` (model, `map` key, pause) + `ui/world-map-ui.scene.json` (window) | yes | `game/ui/map/world_map_window.tscn` / `.gd` (`WorldMapWindow`) |
| `features/progression/WorldProgress.ts:350-360` (`discoverArea`, `discovered`) | yes | `RunState.world["discovered_areas"]`, `RunState.mark_area_discovered` |
| `world/Area.ts:24-72` (`AREAS`: name, biome, `mapX`, neighbours), `world/Biome.ts:11-40` | yes | **[DIFF]** the world layout `game/data/world-map.json` (regions, their cells and maps, passages; read through `game/world/atlas/world_map_data.gd`) for the world map; `game/shell/area_titles.gd` (names, biome colours) for the area banner |
| `src/game/Minimap.ts` (Phaser Graphics minimap) and `src/game/ui/WorldMapUI.ts` (area-node graph) | **no**: nothing mounts them since the DOM surfaces (`8187b2b`); kept only as a converter input list (`scripts/inventory-scene-conversion.mjs:15`) | not ported; `Minimap.ts` documents the frame fallback reused below |
| quest waypoint pin (`features/quests/QuestWaypoint.ts`, `WorldScene.ts:1148-1164`) | yes | **[OUT]** quests session; the pin's look is ported as the marker kind `waypoint` (§3) |

`game/ui/map/map_ui.gd` (`MapUi`) is the glue: it builds the minimap and the window, keeps the
shared markers (`map_markers.gd`, `MapMarkers`), opens the window from the `map` key and registers
the pause menu's Map button.

## 1. Minimap (Phaser)

### 1.1 Mounting, size and place
- Scene `ui.minimap` is mounted last of the world UI scenes (`UniversalSceneWorldController.ts:732`,
  listed in `config.ts:120`); its port is made at `:484` with the world dimensions and registered as
  surface `minimap` (`:525`). Title mode hides every world UI (`styles.css:3725`).
- Size and place (`MinimapSurfacePort.ts:24-34`, re-published by a ResizeObserver on the UI root,
  `:20-21`, `:139-143`): `short = min(ui width, ui height)`, `size = min(180, max(128, short · 0.24))`,
  `margin = min(16, max(12, short · 0.025))`; anchored to the bottom-left corner with
  `offsetMin = [round(margin), -round(margin + size)]`, `offsetMax = [round(margin + size), -round(margin)]`.
  At 1280 × 720: size 172.8, margin 16, box (16, 531)–(189, 704), 173 px square. The authored
  defaults are the same box at 180 px (`minimap.scene.json:13-28`). Godot, since 2026-10-08: the
  minimap is docked in the HUD console (roadmap 4.12): `Minimap.dock` is the console's 128-unit
  minimap rect (the frame inside it, the box 6 units in), and the view rectangle shows the camera's
  play area (the viewport above the console's `bottom_inset`). `box_for` stays the undocked place.
- Frame (`minimap.scene.json:38-69`): TextureRect `ui.frame.organic-minimap`
  (`godot/asset/UI/ui-organic-minimap-frame.webp`, 1254 px square, a vine-and-slime ring with a
  transparent middle about 11 % in from each edge) filling the box grown by 6 px on every side,
  drawn **under** the canvas host (order 0 vs 1). The surface has no background, border or shadow
  and takes no pointer events (`styles.css:3686-3689`).

### 1.2 What it draws (`MinimapSurfacePort.ts:44-109`)
The canvas fills the box (`size = min(host width, height)`, device-pixel-ratio backing store):
1. clear; fill the box `rgba(24, 43, 70, 0.16)` (`#182b46` at 16 %: "a soft tint keeps markers
   legible without hiding the world behind the map", `Minimap.ts:63`);
2. 1 px border `rgba(185, 239, 202, 0.42)` on the half pixel (`strokeRect(0.5, 0.5, size−1, size−1)`);
3. the player (`player.x / y`, the slime centre): a dark disc r 5.25 `rgba(8, 16, 34, 0.88)` under a
   `#72d8ff` disc r 4; the canvas' aria label becomes "Local map. Player at X, Y.";
4. the quest waypoint when one is shown (§4.1): a dark teardrop `rgba(8, 16, 34, 0.9)` from the
   tip `(x, y + 1)` to `(x − 5, y − 6)` around a circle r 5 at `(x, y − 8)` (arc 0.8π → 0.2π
   clockwise, over the top), then a gold `#ffd277` disc r 3.4 at `(x, y − 8)`;
5. the camera view: `strokeRect` 1.5 px `rgba(136, 200, 153, 0.95)` from `(scrollX, scrollY)` to
   `(scrollX + width / zoom, scrollY + height / zoom)`, at least 2 px each way.

World → minimap: `mx = x / world width · size`, `my = y / world height · size` (the whole box, no
inset; the frame's vines cover its outer ~14 px, and markers draw over them).

**There is no terrain.** The interior is see-through by design (2026-09-04 artwork-first HUD,
`styles.css:3784-3786`, `docs/GAME_ROADMAP.md` 4.8): the world under the HUD shows through the
16 % tint, so the minimap reads as a position indicator, not a map. Nothing else is drawn: no NPCs,
exits, camps or fog (the legacy friend and house dots went with `49f2ced`).

### 1.3 Update rate
`WorldScene.updateGameplay` calls `minimapSurface.update(camera, player, waypointTarget)` every
fixed step (`WorldScene.ts:814-816`, run from `beforeFixedStep`,
`UniversalSceneWorldController.ts:692-696`), so 60 times a second, and never while the simulation is
paused or frozen by a hit-stop (`PhaserSceneTreeHost.ts:97-101`, `WorldScene.ts:793-797`).

### 1.4 Edge cases
- Zoom: the view rectangle grows and shrinks with `camera.zoom`, but its corner is `scrollX`, which
  is the view's left edge only at zoom 1 (Phaser's `worldView.x = scrollX + w/2 − w/(2·zoom)`), so
  at other zooms the rectangle is offset by `w/2 − w/(2·zoom)` (a Phaser bug).
- Fixed-camera worlds (interiors) keep the minimap; their small world fills the same box.
- The frame fallback when the texture is missing (`Minimap.ts:51-61`): a rounded rect r 8, 1.5 px
  `#9be8b8` at 0.72 around the box grown by the pad (`clamp(size · 0.033, 4, 6)`).

## 2. World map window (Phaser)

### 2.1 Window (`world-map-ui.scene.json`, `WorldMapSurfacePort.ts:53-76`, `styles.css:3678-3683`)
- ModalRoot centred, `width = min(620, max(1, ui width − 32))`, `height = min(340, max(1, ui height − 32))`
  (`:57-58`, offsets ±w/2, ±h/2); field-kit window: surface 94 %, border 74 %, radius 12, shadow
  `0 18px 48px #080e1abf`; z-index 90, input priority 2000. No backdrop dim.
- Title "World Map" (anchors top, offsets (20, 12)–(−20, 50); tone warning, 24 px, bold, centred).
- Four area labels in a row, by `mapX` (`Area.ts`): Icege (−1), Slimeshire Meadow (0), Gloop Forest
  (1), Crystal Caverns (2); anchors x 0.02–0.22, 0.26–0.46, 0.52–0.72, 0.78–0.98, y 0.34–0.76;
  tone info, 15 px (10 px when the page is at most 520 px wide), centred, wrapped, line height 1.35.
  Text (`:59-63`): unknown `"?\nUnknown"`; discovered `"●\n<name>"`; the current area
  `"◉\n<name>\nCurrent area"` (the current area is the world's area id, so an interior such as
  `elder-house` marks no column).
- Links: `"━━━━"` (tone muted, 12 px) at x 0.44–0.54 / 0.70–0.80, y 0.41–0.61 when both
  `level-1` and `gloop-forest`, resp. `gloop-forest` and `crystal-caverns`, are discovered (`:72-73`).
  Icege has no neighbours and no link.
- Summary (bottom, offsets (18, −78)–(−18, −46), tone muted, 12 px): `"<n> discovered · Areas stay
  marked as you travel"`, `n` = every discovered area id, interiors included (`:74`).
- Close (bottom-right, offsets (−94, −42)–(−16, −10), 78 × 32, tone muted, bold, radius 6) and the
  ModalRoot's own `close_requested`: both `close` (`world-map-ui.scene.json` connections). Clicks play
  `sfx.ui.click` (40 ms minimum interval).

### 2.2 Opening, closing, pause
- `open()` (`:37-44`): no-op when open; `discover(current area)`, then open, pause source
  `worldmap` (`setWorldMapPaused`, `WorldScene.ts:2285` → `setSimulationPaused`, `:750-770`), the
  modal stack entry `world-map`, publish. `close()` (`:45-51`) undoes it. The world's area is also
  discovered on every world load (`WorldScene.ts:396`); a new run starts with `level-1` discovered
  (`content/initial-state/InitialRun.ts:58`).
- The `map` key (M; `:99-106`, capture phase, before every other handler): ignored on repeat or with
  Ctrl / Alt / Meta; when the map is closed it is ignored while any other modal is open (pause menu,
  bag, dialogue, title, game over…) or while focus is in a text field; otherwise it toggles.
- Escape closes it through the modal stack (`ModalStack.ts:130-144`).
- The pause menu's Map button closes the pause menu and calls `openMap` (`WorldScene.ts:547`).
- The world map is the Map tab of the menu tab strip (`WorldScene.ts:215-225`): the menu key (B;
  KeyE in Phaser) closes it like any open tab (`toggleMenu`, `WorldScene.ts:2066-2077`), and the
  journal key (J, 2026-10-08) switches it to the Journal.
- Opening: `MenuOpen` cue, closing `MenuClose` (`AudioEventBridge.ts:104-109`); the first opening
  teaches the `map` control hint and reports `control.used {controlId: "menu:map"}` to tutorial
  quests (`WorldScene.ts:141-147, 596-602`).
- `world.progress.changed` republishes the model while open (`:28`); the world's teardown closes it
  (`destroy`, `:88-97`).

## 3. Godot

### 3.1 Files and tree
```
Hud (CanvasLayer 10, hud.gd)
  MapUi (map_ui.gd, Node, ALWAYS, group "map_ui")   <- one line in hud.gd `_build()`
    Minimap (minimap.gd, Control, bottom-left, mouse IGNORE)
      Frame (TextureRect, the organic frame)        Overlay (Control: markers, player, view)
GameWindows (CanvasLayer 40, game/ui/screens/game_windows.gd; main's child)
  Root > WorldMap (world_map_window.tscn, WorldMapWindow, group "world_map")
           Panel (WindowPanel) > Chart (grid, regions, edges, links, current ring),
             Regions (one Label per region, made from the layout), Overlay (player dot, badges),
             Title, Message (hidden unless the layout is missing), Summary, Close; ClickSfx
```
- **[IN]** `MapUi` builds the minimap at once and the window lazily: the window is handed to
  `GameWindows.add_window()` the first time the `game_windows` group has a node (on
  `world_registered`, or when something opens it), because the HUD is ready before main makes
  GameWindows. `MapUi._exit_tree` closes and frees the window and unregisters the Shell action.
- Both are Godot-owned (CONVENTIONS "Scenes Godot owns"): the converted `ui.minimap` and
  `ui.world-map-ui` scenes were never loaded and were not kept when the scenes became Godot's.

### 3.2 Minimap
- **[IN]** Size and place as §1.1 from the HUD viewport's visible size, re-laid out on
  `size_changed`; frame and see-through tint, border, player (`player.get_centre()`), view rectangle
  and the waypoint pin as §1.2, in the same colours and sizes. Order: terrain, tint and border (the
  Minimap's own `_draw`) < Frame < Overlay (markers, view rectangle, player on top, as Phaser's
  canvas draws over its frame). The missing-texture fallback of §1.4.
- **[DIFF] Terrain (owner decision 2026-10-05: on).** Phaser's interior is see-through under the
  16 % tint (the artwork-first HUD of 2026-09-04); the owner found that minimap underdeveloped and
  chose a drawn map. `Minimap.terrain_alpha` (default 1) draws the world's ground under the tint;
  0 gives Phaser's see-through interior back. The bake: `MapTerrain.bake(ground)`
  makes one `Image` of one pixel per tile (each tile's average colour: its atlas texture shrunk to the
  atlas grid with trilinear filtering, i.e. a box average, cached per texture for the whole run;
  empty cells transparent; level-1 bakes in about 130 ms the first time, a few ms once its atlases
  are cached). That image is scaled once to the map area with cubic filtering (smooth shores at
  about 2.7 px a tile) into one `ImageTexture`, redone only when the box size or the world changes.
  Baked on `WorldService.world_registered`, dropped when that world root leaves the tree (travel,
  load, quit), so nothing per world outlives its world and nothing is per tile at draw time. (The
  2026-09-03 skin design had code-drawn terrain inside this frame; the 2026-09-04 artwork-first
  design replaced it with the see-through tint; the owner brought the drawn map back on
  2026-10-05.) Walls and trees are
  objects, not ground, and are not drawn (stamping their collision shapes was tried: it only adds
  speckle at this scale).
- **[DIFF] Frame art.** The 1254 px painting has no mipmaps, so the frame shows it shrunk once to
  its exact size with Lanczos (the decoded art is kept for the run).
- **[DIFF] Inset.** The map (terrain, markers, view) fills the box inset by `MAP_INSET` = 12 px, so
  the frame's vines (about 14 px deep) hide only the world's outermost tiles (Phaser maps onto the
  whole box).
- **[DIFF] View rectangle** from the camera's real view: `WorldCamera.center ± viewport / (2 · zoom)`
  (the camera without its shake), which fixes Phaser's offset at zoom ≠ 1 (§1.4).
- **[DIFF] Update rate.** The overlay is redrawn from `_process` whenever the player point, the view,
  the markers or the size changed (HUD is PROCESS_MODE_ALWAYS; process priority 200, after the
  WorldCamera's 100, so the rectangle is the frame's own view). In play this matches Phaser's
  per-step update; while paused only the zoom keys can move the view, and the minimap follows them.
- Hidden while no world is registered.

### 3.3 Markers (the API other features use)
Markers are shared by both views (`MapMarkers`, owned by `MapUi`); setting one on either view or on
`MapUi` shows it on both.

```gdscript
var map_ui := get_tree().get_first_node_in_group(&"map_ui")   # MapUi, under the HUD
map_ui.set_marker(&"quest-waypoint", point, &"waypoint")      # kind defaults to &"waypoint"
map_ui.set_marker(&"camp", camp_point, &"boss", "gloop-forest")  # another world's marker
map_ui.clear_marker(&"quest-waypoint")
map_ui.clear_markers()
# also: map_ui.minimap.set_marker(...) / map_ui.world_map.set_marker(...), same arguments
```
- `set_marker(id: StringName, world_point: Vector2, kind: StringName = &"waypoint", map_id: String = "")`:
  adds or moves a marker. `world_point` is in **world pixels of the old Phaser space**, the space of
  `WorldService.areas()`, spawn points, `primary_target().centre` and `player.get_centre()`: a plain
  Node2D's `global_position` (the world root sits at the origin), and for a re-anchored character
  `FeetAnchor.phaser_position(root)`. `map_id` = the world it belongs to, default the current world.
  Markers outlive travel: the minimap draws only the current world's; the world map badges the
  region of each waypoint.
- `clear_marker(id)`, `clear_markers()`, `has_marker(id)`, `marker(id) -> {point, kind, map_id}`,
  `marker_ids()`.
- Kinds (look on the minimap): `waypoint` = Phaser's gold quest pin (§1.2 item 4); **[DIFF]** extra
  kinds for later use, dark-rimmed dots like the player's: `npc` r 3 `#ffb347` (the old friend dot),
  `exit` r 3 accent `#86f0c3`, `boss` r 4 danger `#ff6f88`, `point` r 3 text `#f5f7ff`; an unknown
  kind draws as `point`. Drawn in insertion order under the player dot.
- The world map shows the waypoint pin (1.5×, deep-gold teardrop for the dark panel), its tip at
  the upper right of the name of every region holding a `waypoint` marker in one of its maps (its
  overworld or an interior), once per region; the other kinds show only on the minimap.

### 3.4 World map window
- **[IN]** The window of §2.1 in `world_map_window.tscn` on the UI theme: `WindowPanel` (radius 12
  and shadow), `PanelTitle` "World Map", `CaptionLabel` summary, `MutedButton` Close with the bold
  font and radius 6. Re-laid out on viewport resize.
- **[DIFF] Panel size (2026-10-10).** `WindowPanel` at most 720 × 816 (Phaser 620 × 340), `w − 32`
  across and `h − 88` down (44 px above and below: the menu tab strip ends 40 px down), and no
  bigger than the square grid those leave needs (`WorldMapWindow.panel_size_for`: 720 × 816 at the
  1024 × 1024 base view, 448 × 544 at 480 × 900). The grid sits 24 px from the panel's sides, 58 px
  from its top (under the title) and 86 px from its bottom (over the summary and Close), at whole
  pixels per chunk (84 px at the base view).
- **[DIFF] The world layout instead of four columns (2026-10-10).** Phaser's row of four area
  columns (`◉` / `●` glyphs, `━` links) became the overworld of `game/data/world-map.json`
  (`WorldMapData`, read once for the run by `WorldMapWindow.map_data()`): its chunk grid (8 × 8)
  drawn on the Chart control, each region over its own cells (`regionCells`, so the irregular Wilds
  and the L-shaped Volcano Ridge keep their shapes), in this order: the well (`SHADOW`) under
  unplanned cells; each region's cells, in `SURFACE_INSET` fog until it is discovered, then its
  colour mixed half into `SURFACE_INSET`; the chunk lines (border at 35 %); every region's edge
  (1.5 px border at 95 %); the two-way passages' links; the well's frame; and the current region's
  edge as a 2.5 px warning ring. Interiors are not drawn.
  - A region is **discovered** when one of its maps (its overworld `world` or one of its
    `interiors`) is in `RunState.world.discovered_areas`, and **current** when the current world is
    one of them (an interior rings its region too).
  - **Names**: one Label per region (under `Regions`), in the largest rectangle of whole chunks the
    region holds (its cells' bounds without one), 4 px in: discovered `HudLabel` at 14 px (10 px at
    ≤ 520 px) reading `<name>` or `<name>\nCurrent area`; undiscovered a `MutedLabel` `?` at 22 px
    (14 px). `region_text(key or map id)` returns a region's label text. The names are the
    layout's (`regions[].name`) as `AreaTitles.region_name` gives them, the same as the area
    banner and the save slots: without a trailing note in parentheses (the sketch tool's planning
    note on an open design slot, "Desert (open)" reads "Desert"; the file keeps it).
  - **Links**: each entry of the layout's `passages` (`{a, b, x, y, w, h}` in cells, written by
    `godot/tools/build_region_worlds.gd`: 18 openings in the current layout) whose two regions are
    discovered and that can be travelled both ways (`passage_shown`) gets a short bar across their
    border at the middle of its opening (0.18 of a chunk each way): a 2 px accent line on a 5 px
    dark one (the legacy `WorldMapUI.ts:112-115` link, darker and stronger to read on the tinted
    regions). It runs sideways when the cells left and right of the opening belong to its two
    regions, downwards when those above and below do, else across the opening's long side.
    `link_shown(a, b, discovered)` and `has_passage(a, b)` take region keys or map ids.
  - **[DIFF] Two-way passages only (2026-10-11).** The map does not read the world scenes' exits
    (loading level-1's scene alone takes about a second), so `is_two_way` decides from the regions'
    `placeholder` flags: two placeholders (the region builder gives each side of every opening its
    exit) or two hand-made worlds (their own exits: Slimeshire Meadow – Gloop Forest and Gloop
    Forest – Crystal Caverns work both ways) get a link; a placeholder next to a hand-made world
    does not, because only the placeholder's exit is built and level-1, gloop-forest and
    crystal-caverns have no exit back yet (seven openings: [WORLD_ATLAS.md](../WORLD_ATLAS.md),
    "Openings on hand-made worlds"). When a hand-made world gets its exit at such an opening, this
    rule has to change with it (for example the region builder marking the passages whose
    hand-made side has no exit). A release build can discover only Slimeshire Meadow, Gloop Forest
    and Crystal Caverns (the placeholders ship only in "Web (dev)"), so it shows those two links.
  - **Player**: when the current world is a region's overworld, the minimap's player dot
    (`#72d8ff` r 4 on a dark r 5.25) at the player's place in the world (`player.get_centre()` over
    `WorldService.world_rect()`) mapped onto the region's chunk block (`player_dot()`), drawn on the
    Overlay control over the names. No dot in an interior.
  - **Summary**: `"<n> of <m> regions discovered · Areas stay marked as you travel"`, `n` the
    discovered regions, `m` all the layout's regions.
  - **No layout**: a missing or unreadable `world-map.json` (a warning, or WorldMapData's error)
    leaves an empty framed well with the `Message` label "The world layout could not be read." and
    Phaser's summary (`"<n> discovered · ..."`, every discovered map id); nothing else changes.
    `WorldMapWindow.use_map(map)` (tools and tests; null = none) and `reload_map()` replace the
    cached layout.
  - Every text is in the theme fonts (`?` and `·` are in Source Sans 3).
- **[IN]** `open() -> bool`: true when already open; refuses (false) without GameWindows or a
  registered world; marks the current world discovered (`RunState.mark_area_discovered`), lays out,
  refreshes and shows, then `GameWindows.push(self, &"world-map")` (the `modal` pause, the MenuOpen
  cue and `window_opened(&"world-map")`, which the quests session maps to `menu:map`), emits
  `opened` and focuses Close. `close()`: no-op when closed; hides, `GameWindows.pop(self)`
  (MenuClose; the last window unpauses and clears the player's input), emits `closed`.
  `toggle() -> bool` (open afterwards). Escape reaches GameWindows, which calls `close()`.
- **[IN]** The `map` input action (M) when it exists in the InputMap, heard by `MapUi._unhandled_input`
  (GameWindows swallows keys while one of its windows is open, so it never opens over the bag or a
  dialogue): ignored on echo or with Ctrl / Alt / Meta, and while a Shell window or another game
  window is open, no world runs (group `world_main`) or main `is_transitioning()` (**[DIFF]** Phaser
  does not check the travel). While the map is
  open, the window's `_input` closes it on `map` and on `menu` (Phaser's menu key closes the open
  tab) and consumes the key.
- **[IN]** Pause menu: `MapUi` registers `Services.shell().set_action(&"map", open_world_map)`, so the
  Shell closes the pause menu and opens the map in one call.
- **[IN]** The world's teardown closes it (`GameWindows.close_all()` in main's `_teardown_world`).
  While open it refreshes on `world_registered`.
- **[IN]** The menu's Map tab: when MenuWindows exists (group `menu_windows`,
  `game/ui/screens/menu_windows.gd`, the crafting/inventory work's tab strip, coach tip and menu
  key), `MapUi` registers the window as its tab (`register_tab(&"map", window)`, removed on exit), so
  the strip shows over the map, its tabs switch to and from it, and the menu key closes it.
  **[OUT]** The `map` control hint is the control-hints work.
- Open API for others: `MapUi.open_world_map() -> bool`, `close_world_map()`, `toggle_world_map()`,
  `is_world_map_open()`, or the window itself (`map_ui.world_map`, group `world_map`): `open()`,
  `close()`, `toggle()`, `is_open()`.

## 4. Tests

`godot/tests/test_map.gd`: the minimap's box at 1280 × 720 and the formula at other sizes; the baked
level-1 terrain (64 × 64, water cells blue, meadow cells green, an empty cell transparent) and the
frame; the player marker following a teleport; the marker API (set, move, clear, other worlds,
both views); the world map from the `map` action and from the Shell's Map button (open, `modal`
pause, the region labels: Slimeshire Meadow current, Gloop Forest and Crystal Caverns `?`; the
player dot on level-1's block, the summary, no link yet, the panel size and `panel_size_for` at
1024 × 1024 and 480 × 900, `window_opened(&"world-map")`, Escape, `map` and Close closing it);
refusal while a Shell window or another game window is open; the regions of the layout (by map id,
interior and key; labels in an interior and undiscovered; names without a trailing planning note,
on the map and in `AreaTitles.area_name`, for every region) and the passage links on a copy of the
layout (level-1 / gloop-forest linked once both are discovered; a hand-made world next to a
placeholder never linked, two placeholders linked); the missing-layout message and summary
(`use_map(null)`, then `reload_map()`); and a travel to gloop-forest rebuilding the terrain
(64 × 64) and freeing level-1's image and texture, the world map showing Gloop Forest current,
Slimeshire Meadow named, Crystal Caverns `?`, two regions discovered, the dot on gloop-forest's
block and the level-1 / gloop-forest link exactly when the layout has a passage there. Headless
runs keep the 1024 × 1024 base view (`display/window/size/viewport_*`), so the live panel check
runs at `panel_size_for(1024 × 1024)` = 720 × 816; the 480 × 900 size is checked against the
formula only.
