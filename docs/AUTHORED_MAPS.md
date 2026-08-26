# Authored Maps

Authored maps live in `src/game/content/maps/` as `<map-id>.map.json`. They contain stable content IDs, positions, and initial state. They never contain image paths, collider definitions, or behavior rules.

## Content layers

1. `asset/assets.json` describes loadable media and sprite-sheet regions.
2. `TileCatalog.ts` and `content/objects/*.json` turn media into placeable terrain or reusable objects. Terrain may omit physics; object files own their collider and behavior.
3. A map places terrain IDs and exact object `objectId` + `visualId` pairs. A placement may set `initialState`, but cannot override physics or behavior.

Ground belongs in the content catalog because map authors place logical terrain such as `grass-a` or `water`, not texture paths. Ground does not need a collider unless that terrain type should block movement.

## Create a map

1. Copy `src/game/content/maps/test-rectangle.map.json` to `<map-id>.map.json`.
2. Keep the filename and `mapId` identical and kebab-cased.
3. Set `tileSize`, `size.columns`, and `size.rows`.
4. Add one character per cell to every layer row. Each layer must have exactly `size.rows` rows of exactly `size.columns` characters.
5. Map each character in `legend` to a terrain ID from `src/game/content/terrain/TileCatalog.ts`.
6. Add placeable objects from `src/game/content/objects/`. Every placement needs a unique, stable `instanceId`; do not change it when moving the object.
7. Set `player.spawn`, optional directional `player.entries`, and optional `exits`.
8. Run `pnpm maps:check`, then `pnpm check`.

Minimal placement:

```json
{
  "instanceId": "amber-rock-001",
  "objectId": "rock.amber-ore.mineable",
  "visualId": "amber-ore",
  "x": 288,
  "y": 192,
  "initialState": { "health": 30 }
}
```

## Preview and activate

Start the game with `pnpm dev`, then preview any authored map in development mode:

```text
http://localhost:3000/?map=test-rectangle
```

For normal area loading, set the area's `mapId` in `src/game/world/Area.ts`. Every production area must have a matching map file; a missing map stops loading with a visible error.

An empty `exits` array means the authored map has no exits. `Area.ts` owns the world graph; authored maps own the physical exit zones and entry coordinates.

## Edit a map today

Use the dev-only Field Cartographer editor described in `docs/MAP_EDITOR.md`, or edit the JSON directly. In both workflows, keep stable IDs and run the checks; the JSON contract remains the source of truth.

The two generated production maps were created by `pnpm maps:bake`. That command is a deterministic bootstrap tool and overwrites `gloop-forest` and `crystal-caverns`; it does not overwrite the hand-authored `level-1` map. Do not run it after hand-editing generated maps unless the overwrite is intentional.
