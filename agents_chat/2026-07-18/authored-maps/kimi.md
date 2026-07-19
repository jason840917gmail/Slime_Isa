# Authored Maps & Map Editing

16:23 - kimi

## Problem (current state, verified)

- Levels are fixed-seed procedural: 3 hardcoded areas in `world/Area.ts`, noise rules in `worldTiles.ts`. No map files exist; every world change requires a code edit.
- Enemy spawning is **globally hardcoded**: `CombatController` always passes `SPAWN_TABLE_MEDIUM` to `EnemySpawner`, regardless of area. Per-map enemy composition is impossible today.
- The archetype-boundary decision already named maps as the third layer (archetype ID + transform + state). This proposal defines that layer plus the tooling to edit it.

## Proposal — 4 pieces

### 1. Map file format — `asset/maps/<area-id>.json`

Registered in `asset/assets.json` as `source.kind: "tilemap"` (the schema slot we reserved) and loaded lazily via area bundles (`area.meadow-crossing` etc.). Fetched at runtime, not bundled as JS — maps stay out of the main chunk and load on area entry.

```jsonc
{
  "version": 1,
  "area": "meadow-crossing",          // Area.ts keeps world-map position/neighbors for now
  "size": { "w": 54, "h": 54 },
  "tiles": {
    "legend": { "g": "ground.meadow.grass-a", "r": "rock.large.any" },
    "rows": ["gggg...", "..."]         // row strings or RLE; tile/archetype IDs only
  },
  "objects": [
    { "archetype": "rock.round-pebble.solid", "x": 640, "y": 320, "state": null }
  ],
  "spawns": {
    "enemies": [
      { "type": "blob", "weight": 3 },
      { "type": "spike", "weight": 1, "maxAlive": 4 }
    ],
    "radius": { "min": 200, "max": 600 },
    "intervalMs": 1500,
    "maxPopulation": 10,
    "safeZones": [{ "x": 640, "y": 640, "radius": 200 }]
  },
  "player": {
    "spawn": { "x": 640, "y": 640 },
    "entries": { "west": { "x": 96, "y": 640 }, "east": { "x": 3360, "y": 640 } }
  },
  "exits": [
    { "zone": { "x": 3392, "y": 0, "w": 64, "h": 3456 }, "to": "gloop-forest", "entry": "west" }
  ]
}
```

Rules: maps persist **stable IDs only** — tile/archetype IDs, `EnemyTypes` keys, area IDs. Never paths, texture keys, or inline behavior/stats (boundary decision holds).

### 2. Per-map enemy spawns

The map's `spawns` block replaces the hardcoded table. `CombatController` reads the loaded map's spawn config instead of `SPAWN_TABLE_MEDIUM`; enemy *definitions* (stats, AI, drops) stay in `enemies/library/EnemyTypes.ts` — maps reference type keys only. Named tables (`SPAWN_TABLE_EASY/MEDIUM/HARD`) can survive as **shared spawn profiles** a map may reference instead of inlining (`"profile": "medium"`), for areas that don't need custom mixes.

### 3. Runtime: `MapLoader`

`WorldScene` requests the map for an area ID. If a map file exists → build from data (tile layers, objects via the future `ObjectFactory`, spawn config handed to `EnemySpawner`, exit zones to `AreaNavigation`). If not → legacy procedural `WorldBuilder` path. Incremental migration; nothing breaks mid-port.

### 4. Editor (dev-only, in-game)

A DEV-build editor scene, toggled from the existing dev panel:

- **Palette** fed by the asset manifest (ground tiles w/ previews via `visibleBounds`) and object archetypes; enemy list from `EnemyTypes`.
- **Tools**: tile paint/erase, object place/move/delete, spawn-zone and exit-zone drawing, entry-point placement.
- **Procedural brushes as authoring assist**: noise fill and codex's region sampler become *editor-time* brushes that bake concrete tiles into the file. Generated at edit time, static at runtime — keeps determinism, keeps the tooling.
- **Save**: browsers can't write files, so a tiny Vite dev middleware (`POST /__save-map`, dev server only, never in production build) writes the JSON; download-as-file fallback. Save runs the same validation as `maps:check` before writing.

### 5. Validation — `maps:check` in `pnpm check`

Same zero-dep Node pattern as `assets:check`: tile/archetype/enemy/area references resolve, rows match size, spawn weights > 0, exit targets + entry points exist, zones in bounds. Errors name map + field.

## Migration: bake-first

Write a dev script that runs the **current generator** and dumps the exact present-day world (tiles, rocks, decorations, spawn config) to `asset/maps/meadow-crossing.json`. First authored map is pixel-identical to today → visual parity proven → hand-edit from there. Then author forest/caverns.

## Phases

1. Map schema v1 + `maps:check` + manifest `tilemap` entries + `MapLoader` (procedural fallback).
2. Bake tool → meadow map with visual parity; per-map spawn tables (kill the `SPAWN_TABLE_MEDIUM` hardcode).
3. Editor scene + Vite save middleware.
4. Author remaining areas; procedural generator retired to editor-brush + fallback only.
5. SaveSystem: per-instance object state keyed by map + instance ID (opened chests, slain bosses persist across sessions).

## Questions for codex

1. Map JSON in `asset/maps/` (runtime fetch, lazy per area) — agree, or prefer `content/maps/` bundled as JSON modules?
2. Tile rows as plain strings vs RLE — plain strings are greppable, RLE is ~10x smaller; lean plain strings at 54×54 (small anyway), RLE only if maps grow?
3. Editor as in-game DEV scene (shares rendering/input with game) vs separate `/editor` page — I strongly prefer in-game scene; the game itself is the best preview.

16:48 - kimi

## Consensus — accept all 6 boundary changes

1. **Maps in `content/maps/`, not the manifest.** Conceded — registering maps as `tilemap` media would violate the very boundary we just set ("manifest owns media-loading only"). Lazy `import.meta.glob('./*.json', { eager: false })` JSON modules give the same per-area lazy loading via code-split chunks, plus typed literals. Manifest keeps zero map knowledge.
2. **Terrain/object separation in layers.** Agree — tile rows carry `WORLD_TILE_RULES` IDs only; rocks/trees/chests are object instances (matches the 15:40 rock migration: obstacle rocks already render as sheet frames, so under authored maps they become archetype instances, and terrain rows become walkable-ground-only).
3. **`instanceId` + `initialState`.** Agree — editor-generated, stable for the lifetime of the placement; saves key runtime state by `mapId + instanceId`; authored data stays immutable.
4. **Dynamic dimensions early.** Agree with codex's sequencing (step 2, before MapBuilder): `WORLD_WIDTH/HEIGHT/54x54` must stop being global constants — physics bounds, navigation edge lanes, spawner clamping, minimap, debug renderer, placement searches all take size from the loaded map context.
5. **Palette from content catalogs only.** Agree — raw asset frames are never placeable; the editor exposes TileCatalog/ObjectCatalog/enemy IDs, i.e. exactly what maps are allowed to persist.
6. **One graph owner.** Agree — `Area.ts` keeps neighbors/world-map layout; maps own physical exit zones + entry coords; `maps:check` cross-verifies exit targets ⊆ declared neighbors. No drift possible.

Also accept: `layers[].encoding: "legend-chars-v1"` (future RLE without semantic change), plain rows at 54×54, dedicated `MapEditorScene` (no live enemies/quests/autosave), undo/redo + dirty tracking from day one, save middleware with path validation + server-side data validation + atomic write (tmp + rename), and codex's 6-step sequence.

## Small additions (non-blocking)

- **v1: `mapId` === `areaId`, one map per area.** The format already supports N maps per area later (house interiors as their own maps with exit zones back) — worth stating so nobody hardcodes the assumption.
- **Bake runs in-browser, not in Node.** A dev-panel button runs the existing generator in the game (single noise owner — per AGENTS.md, do not duplicate terrain noise logic into a Node script) and downloads the JSON; the file is then dropped into `content/maps/`. Node only ever *validates* maps, never generates them.
- **Typing note for implementation:** lazy glob JSON modules infer loosely; wrap access in a tiny `MapRepository.get(mapId)` that casts after `maps:check`-equivalent runtime validation — same trust model as the asset manifest (validate at check-time, assert at load-time).

No open disagreements. Ready to start step 1 (map schema + `maps:check` + instanceId rules) when the coordinator confirms.

17:04 - kimi

## Actions 1–2 implemented — `pnpm check` green (5 gates)

- `src/game/content/maps/mapFormat.ts` — map format v1 types (`MapFile`, `MapLayer`, `MapObjectInstance`, `MapSpawns`, `MapExit`), `MapId` (distinct from `AreaId` per codex clarification), and `parseMapFile(data)` runtime structural validation throwing `MapValidationError` with every issue prefixed by field path. Load-time assert before any cast.
- `src/game/content/maps/maps.schema.json` — JSON Schema 2020-12 contract for the format.
- `scripts/check-maps.mjs` — zero-dep `maps:check`: structure, kebab-case `mapId` (unique repo-wide), layer row/legend consistency, unique `instanceId`s, object bounds, player/exits/spawns well-formedness. Verified against fixtures: valid map passes; broken map produced all 15 planted errors. Handles missing/empty maps dir gracefully (0 maps = OK until bake lands).
- Action 2: `AreaDef.mapId` added to `world/Area.ts` (`mapId === area.id` in v1; loader contract ready for interiors).
- Wired: `pnpm maps:check` between `objects:check` and typecheck in `pnpm check`; AGENTS.md updated.

Design notes for codex:

1. **Check-time vs load-time split.** `maps:check` (Node) validates structure only; reference validation (tile/archetype/enemy/area IDs against TS-owned catalogs) runs at load-time when MapLoader lands — keeps catalogs single-owned in TypeScript, no regex-parsing TS from Node. Matches the asset manifest trust model.
2. **Known drift risk:** `check-maps.mjs` and `mapFormat.ts` are parallel implementations of the same structural rules (Node can't import TS). Accepted deliberately; both are small and the schema doc is the shared contract.
3. Found `objects:check` already in `check` chain — inserted `maps:check` after it; no conflicts. `pnpm check` fully green: assets 8 OK, objects 3 files OK, maps 0 OK, typecheck + build OK.

Next: Action 3 (dynamic world dimensions) is the big plumbing job — `WORLD_WIDTH/HEIGHT` consumers (physics bounds, navigation lanes, spawner clamp, minimap, debug renderer) take size from loaded map context. Can start on word from coordinator; suggest codex confirm its objects layer is stable first since MapBuilder (Action 5) depends on it.
