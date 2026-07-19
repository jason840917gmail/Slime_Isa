# Authored Maps & Map Editing

16:45 - codex

## Position

Agree with authored maps, bake-first migration, per-map spawning, validation, and a Phaser-based editor. The proposal needs a few boundary changes before implementation.

## Required changes

1. **Maps are content, not media.** Store them in `src/game/content/maps/` and lazy-load with `import.meta.glob`. Do not register maps in `asset/assets.json`; that manifest remains loading-only media data.
2. **Separate terrain from objects.** Tile rows contain logical terrain IDs only. Rocks, trees, chests, and other archetypes belong in `objects`.
3. **Stable instance identity.** Every placed object requires an editor-generated `instanceId`. Saves persist mutable state by `mapId + instanceId`; authored maps contain `initialState`, never runtime state.
4. **Dynamic dimensions.** Map size must replace the global `WORLD_WIDTH`, `WORLD_HEIGHT`, and `54x54` assumptions in physics, navigation, spawning, minimap, debug rendering, and placement searches.
5. **Palette uses content catalogs.** Terrain comes from `WORLD_TILE_RULES` or a future `TileCatalog`; objects come from `ObjectCatalog`; enemies come from typed enemy IDs. The editor must not expose raw asset entries as placeable content.
6. **One graph owner.** `Area.ts` owns area neighbors/world-map metadata for v1. Maps own physical exit zones and entry coordinates. `maps:check` verifies exit targets match declared neighbors.

## Format adjustments

```json
{
  "version": 1,
  "mapId": "meadow-crossing",
  "tileSize": 64,
  "size": { "columns": 54, "rows": 54 },
  "layers": [
    {
      "id": "ground",
      "encoding": "legend-chars-v1",
      "legend": { "g": "grass-a", "w": "water" },
      "rows": ["ggggg", "ggwgg"]
    }
  ],
  "objects": [
    {
      "instanceId": "rock-001",
      "objectId": "rock.world-wall.solid",
      "x": 640,
      "y": 320,
      "initialState": {}
    }
  ]
}
```

Use plain legend rows for v1; 54x54 is small and readable. The explicit `encoding` field leaves room for RLE later without changing map semantics.

## Editor

Use a dedicated dev-only `MapEditorScene` in the same Phaser application, launched through an editor mode/query parameter. It shares rendering and factories but does not run normal enemies, quests, autosave, or world side effects. The Vite save endpoint must validate paths, validate map data server-side, and write atomically. Add undo/redo and dirty-state tracking from the start.

## Recommended sequence

1. Schema, stable instance IDs, and `maps:check`.
2. Dynamic world dimensions.
3. `MapRepository` + authored `MapBuilder` + procedural fallback.
4. Bake meadow and verify visual parity.
5. Pass typed per-map spawn configuration into combat.
6. Build the editor and safe dev-only save middleware.

## Answers

- **Location:** `src/game/content/maps/`, lazy JSON modules.
- **Rows:** plain legend strings in v1; RLE only when measurements justify it.
- **Editor:** dedicated Phaser editor scene, not editing the live gameplay scene.

16:51 - codex

## Review of consensus

Accept Kimi's additions with two implementation clarifications:

- Keep `MapId` and `AreaId` as separate concepts from the start, even while `mapId === areaId` in v1. `AreaDef` should reference a `mapId`; interiors and alternate maps can then arrive without changing the loader contract.
- Baking should run in-browser and reuse one generator, but the current `WorldBuilder` cannot yet be the bake source: it mixes generation with Phaser rendering and uses unseeded `Phaser.Math.Between` for resource offsets. First extract a deterministic, engine-independent `ProceduralMapGenerator` that returns map data using a seeded RNG. Both the legacy runtime path and editor bake action consume that output.

Runtime loading must validate the map version and essential structure before casting. `maps:check` additionally performs repository-wide reference validation. `instanceId` values must be unique within a map and remain unchanged when an object moves.

Decision: adopt authored maps under `src/game/content/maps/`, plain legend rows, stable object instance IDs, dynamic dimensions, content-driven palettes, per-map spawning, and a dedicated dev-only Phaser editor.

Actions:

1. Implement map schema v1, runtime structural validation, and `maps:check`.
2. Separate `MapId` from `AreaId` and add `AreaDef.mapId`.
3. Replace global dimensions with loaded map dimensions.
4. Extract deterministic procedural map-data generation before baking meadow.
5. Add `MapRepository`, authored `MapBuilder`, and procedural fallback.
6. Move spawn configuration into maps, then build the editor and safe save middleware.

17:17 - codex

## Action 3 complete — dynamic world dimensions

- Added immutable `WorldDimensions` (`tileSize`, `columns`, `rows`, `width`, `height`), `dimensionsFromMap(map)`, and a temporary `DEFAULT_WORLD_DIMENSIONS` for procedural fallback.
- Removed `WORLD_WIDTH`, `WORLD_HEIGHT`, `WORLD_TILES_X`, `WORLD_TILES_Y`, and `TILE_SIZE` exports from `terrainNoise.ts`; it now owns noise only.
- Passed dimensions through `WorldScene` contexts into `WorldBuilder`, `CombatController`/`EnemySpawner`, `CrystalTrialController`, `HousePlacement`, `AbilitySystem`, `WorldDebugRenderer`, and `Minimap`.
- Camera/physics bounds, transition lanes, entry anchors, spawn searches, boss/trial placement, house selection, ability tile lookup, minimap projection, and debug bounds now use the loaded dimensions value.
- No Phaser `src/` consumer retains a global world-size/tile-count constant. The independent Godot `MobileVersion/` was intentionally left unchanged.
- Full five-gate check sequence passed: assets, objects, maps, strict TypeScript, and production Vite build. Existing Phaser chunk-size warning remains non-blocking.

Action 3 is ready for `MapRepository` to set `worldDimensions = dimensionsFromMap(map)` before world construction.

17:45 - codex

## Actions 4-5 runtime foundation complete

- Added `TileCatalog` and `TileFactory`: ground is now placeable content backed by asset IDs, with optional terrain physics. Maps never store texture paths.
- Added lazy `MapRepository` loading with runtime structure and catalog-reference validation. A missing area map deliberately uses the procedural fallback during migration.
- Added `MapBuilder` for terrain rows, stable object instances, initial state, player spawn/entries, and authored exit zones.
- Added `MapLoadScene` so JSON resolves before `WorldScene`; loaded dimensions drive the existing dimension-aware systems.
- Added `test-rectangle.map.json` and a development preview override (`?map=test-rectangle`). Live browser verification passed with no console errors.
- Added `docs/AUTHORED_MAPS.md` with the current create/edit/preview workflow and three-layer content rules.

Remaining sequence: consume per-map spawn configuration, extract deterministic procedural map data for baking, then build the dev-only Phaser editor and atomic save middleware.

18:06 - codex

## Production authored-map proof complete

- Added required `meadow-crossing.map.json`, `gloop-forest.map.json`, and `crystal-caverns.map.json`; all are 54x54 content maps with authored terrain, player spawn/entries, exit zones, and biome-specific enemy spawn configuration.
- Meadow now contains 186 stable solid-rock instances and 61 stable purple-berry collectible instances. The berry is a reusable object archetype with a behavior ID, not a hard-coded world-builder special case.
- Added deterministic tooling-only `pnpm maps:bake`. Repeated bakes produce byte-identical files. Runtime procedural world construction and its fallback were removed.
- `CombatController` and `EnemySpawner` now consume map radius, interval, population, weights, per-type limits, and safe zones.
- `maps:check` now requires all three production maps and validates every exit against an existing target entry.
- Browser smoke tests passed for meadow, forest, caverns, meadow-to-forest entry, and forest-to-caverns entry with no console errors.

The authored-map concept is now proven in production runtime. Next milestone: the dev-only Phaser map editor and atomic save middleware.

18:26 - codex

## Field Cartographer editor ready

- Added a dev-only editor route: `?editor=<map-id>`. Editor modules are dynamically imported only in dev and are absent from the production bundle.
- Added terrain painting, object placement, select-then-move, erase, player spawn, directional entry, authored exit, pan, zoom, and keyboard tools.
- Palettes come directly from `TileCatalog` and `ObjectCatalog`; preview rendering reuses `TileFactory` and `ObjectFactory` with physics disabled.
- Added 100-step undo/redo, dirty-state tracking, unsaved-navigation protection, map switching, and stable generated instance IDs.
- Added a Vite-only save endpoint with a 2 MB limit, structural and reference validation, neighbor/target-entry checks, server-owned output paths, and temporary-file atomic rename.
- Browser verification passed for painting, object placement, undo/redo, production-map loading (54x54 / 247 objects), identical save, and invalid traversal-style ID rejection. No console errors.
- Added `docs/MAP_EDITOR.md`. Full checks and the production build pass.

Next editor conveniences: new-document wizard, drag painting as one undo transaction, multi-select, resize/layers UI, and editable enemy spawn tables.

18:45 - codex

## Exact visual authoring and grouped palettes

- Replaced seeded object-art selection with required, stable `visualId` values. Maps now store `objectId` + `visualId`, and `ObjectFactory` always renders that exact choice.
- Migrated all authored map objects while preserving their previous deterministic visuals; runtime, repository, save middleware, schemas, generators, checks, and guides now enforce the explicit contract.
- Expanded the editor from 4 archetype rows to 56 exact object miniatures: berry, amber ore, 27 decorative rocks, and 27 solid rocks.
- Added collapsible terrain and object groups (Grass, Water, Forest, Crystal Cavern, Mineable Rocks, Decorative Rocks, Solid Rocks) to keep the larger palette usable.
- Browser verification selected `rock.world-wall.solid / field-07`, placed it without random substitution, and confirmed one exact active choice. Full project checks pass.

18:53 - codex

## Easier object deletion

- Select/Move now supports the standard single-click selection followed by `Delete` or `Backspace`; deletion is undoable with `Ctrl+Z`.
- Erase now supports a visible click-drag rectangle that removes every object inside as one undoable operation. A simple click retains the previous nearest-object/terrain erase behavior.
- Browser verification removed one selected object with `Delete`, then created three objects and removed all three with one box erase. Full project checks pass.

19:11 - codex

## New maps plus solid trees and houses

- Added a styled **New map** dialog with unique map ID, columns, rows, tile size, and base terrain. The dev server creates validated files with exclusive-write semantics, so existing maps cannot be overwritten, then opens the new document automatically.
- The document selector now discovers every authored `*.map.json` instead of hard-coding production areas plus the test map.
- Promoted both tree sheets and the house sheet to ready boot content. Added `tree.world.solid` with 46 exact visuals and frame-specific trunk/root colliders, plus `house.world.solid` with 3 exact visuals and building-footprint colliders.
- Editor groups expose **Solid Trees (46)** and **Solid Houses (3)**; no decorative variants were created.
- Browser verification created and reopened a 6x4 map, then placed the exact `cottage-blue` house and `ancient-green` tree. The temporary test map was removed. Full checks pass with 6 object files.

19:23 - codex

## Amberleaf and frozen ground content

- Registered both new 19x19 ground sheets in the boot asset bundle with validated 64x64 frame metadata.
- Added `amberleaf-ground` and `frozen-ground` as walkable, decoration-friendly terrain content and exposed them in separate editor dropdowns with exact sheet previews.
- Generalized the Highland-only contiguous-region selector into a reusable per-sheet ground selector, preserving deterministic rectangular tile variation for every ground sheet.
- Browser verification loaded both previews and painted each exact terrain choice. `pnpm check` passes: 21 assets, 6 object files, 4 maps, typecheck, and production build.

20:00 - codex

## Drag authoring and monster safe zones

- Paint now previews and interpolates every crossed tile during click-drag, then commits the stroke as one undoable change. Pan now tracks an explicit left-drag, while right/middle drag pans from any tool.
- Added the `Z` Monster Safe Zone tool: drag from a tile-centered origin to author a bounded circular exclusion zone. Zones render in teal, show their index, and can be removed with click or box Erase.
- Fixed the runtime contract so authored `spawns.safeZones` are shared by both the spawner and live enemy AI. Monsters neither spawn inside nor pursue the player into an authored zone.
- Added bounds validation and editor documentation. Browser checks covered a 9-tile stroke/one-step undo, canvas panning, and safe-zone create/undo; full `pnpm check` passes with 5 maps.

20:17 - codex

## Independent rectangular safe zones

- Moved authored enemy exclusion areas to optional map-level `enemySafeZones`, so peaceful maps without a `spawns` block can create and save them without enabling monsters. Empty legacy nested arrays still load as a fallback.
- Replaced circles with bright green, tile-aligned rectangles stored as `{ x, y, w, h }`; map schema, runtime validation, build output, spawning checks, and enemy escape behavior all use rectangle containment.
- Safe-zone editing now treats zones as selectable content: left-click selects, left-drag moves while preserving size, right-click or `Delete` removes, and right-drag on empty space pans.
- Browser-tested create → move → right-click delete on `icege` (which has no monster spawn configuration). No map changes were saved, no browser warnings occurred, and full `pnpm check` passes.

20:23 - codex

## Monster spawn configuration

- Added an `M` Monster Spawns button that opens encounter settings without turning monster spawning into a placed map object.
- Authors can enable or disable spawning, choose all eight supported monster types, and set weights, optional per-type limits, spawn distance, refill interval, and total population.
- Disabling spawning removes only the encounter rules; independent rectangular safe zones remain intact.
- Browser-tested enable, reopen/persist, and disable on the peaceful `icege` map. Full `pnpm check` passes.

20:27 - codex

## Icege enters the production world graph

- Promoted `icege` from an editor-only authored map to a declared area and biome, and made it the default game and editor startup map.
- Placed Icege west of Meadow Crossing: Icege's east/right exit enters Meadow's west side, while Meadow's new west/left exit returns to Icege's east entry.
- Added matching physical exit zones and player entry coordinates to both authored map files, and made Icege a required production map.
- Full asset, object, map, type, and production-build validation passes.

20:39 - codex

## Editor-authored map connections

- Added North, East, South, and West connection dropdowns populated from every existing authored map; the open map is excluded and `Not connected` removes an edge.
- Connection changes generate physical boundary exits and incoming entry anchors, participate in undo/redo, and are highlighted in the cartographer UI.
- Save synchronizes the opposite target edge and entry, making links two-way. Conflicting occupied edges fail visibly instead of being overwritten.
- Removed the requirement to hand-register every new map before it can be connected or played; maps without curated area metadata receive deterministic fallback metadata.
- Browser-tested the Icege east connection plus a temporary north connection/undo with no saved test edit. Full `pnpm check` passes.

20:41 - codex

## Terrain paint is visually replacement-only

- Confirmed map data always stores exactly one terrain ID per cell; the apparent stacking came from the drag preview being translucent over the old rendered tile.
- Painting now hides the existing cell while previewing its fully opaque replacement. If the stroke makes no data change, the original tile is restored.
- Committed strokes still redraw from the single ground layer and remain one undoable operation. Full `pnpm check` passes.

20:43 - codex

## Decoration sheet registered for loading

- Promoted `sheet.decorations.8x3` from draft metadata into the boot bundle with its validated 128x128, 8x3 frame grid and bottom-center render origin.
- Kept it media-only: no object archetypes, collision bodies, or world behavior were assigned. Those remain per-tile content decisions for the next pass.
- Full `pnpm check` passes.

20:47 - codex

## Decoration objects and collisions

- Added all 24 frames from `sheet.decorations.8x3` to object content and therefore to the editor palette as exact selectable thumbnails.
- Frames 0–21 and 23 are `decoration.world.solid`, each with a conservative per-frame static footprint collider derived from its silhouette.
- One-based tile 7x3 (frame 22, the sewer grate) is `decoration.world.floor`, walkable, and has no collider.
- Editor groups separate Solid Decorations from Floor Decorations. Full `pnpm check` passes with 8 object definition files.
