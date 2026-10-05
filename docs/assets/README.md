# Asset Creation And Integration

This is the starting point for creating new game art and making it available
to the game.

## Recommended workflow

1. Read the [asset sheet and size contract](./asset-sheet-spec.md).
2. Choose the right art type guide:
   - [Animated character sheets](./slime-sheet-guide.md)
   - [Terrain and ground art](./terrain-tile-guide.md)
   - [Houses and world props](./houses-and-world-props-guide.md)
   - [Ambient object animation](./AMBIENT_ANIMATION.md) for anything that should move while idle
3. Generate or commission the art using the [visual style guide](./visual-style-guide.md), the [Magnific MCP guide](./magnific-mcp-guide.md), or the [character animation video prompt](./character-animation-video-prompt.md).
4. Keep source and experimental output under `asset/Originals/` (ignored by the
   manifest). Where a pack script exists, run it to produce the runtime sheet in
   `asset/MAPS/` (see below); otherwise export a clean uniform-grid sheet there yourself. Runtime images ship as
   WebP (see [Image format](#image-format)).
5. Register the runtime file in `asset/assets.json` and build a scene for it
   through [Adding Game Assets](./adding-assets.md).
6. For animated characters, continue with the [character sprites guide](./character-sprites-guide.md).
7. Run the checks below before placing the asset in a world.

## Pack and generator scripts

The Python tools need Python 3 with Pillow (and numpy for most of them).

| Command | Reads | Writes |
| --- | --- | --- |
| `pnpm grounds:pack` | `asset/Originals/grounds/{generated,legacy-sheets}/` | wrap-seamless `asset/MAPS/grounds/64x64-tile_19x19_<ground>.png` |
| `pnpm props:pack` | `asset/Originals/props/` | bottom-anchored `asset/MAPS/rocks/<frame>x<frame>-tile_<cols>x<rows>-<name>.png` |
| `pnpm items:pack` | `asset/Originals/items/` | `asset/MAPS/items/{gems,materials,forage}-5x2.png` and `asset/Originals/items/atlas-index.json` |
| `python scripts/interiors/normalize-interior-sheets.py` | `asset/Originals/interiors/generated-sheets/` | `normalized-sheets/`, `asset/MAPS/interiors/`, `atlas-index.json` |
| `pnpm interiors:scenes` | `scripts/interiors/interior_catalog.py` + manifest | one `object.interior-*` scene per sprite (`interiors:check` detects drift) |
| `python scripts/props/generate-wall-prop-scenes.py` | manifest sheets | `object.crystal-cluster-wall.*` / `object.tree-forest-wall.*` scenes |
| `python scripts/props/pack-level-1-landmarks.py` | `asset/Originals/props/level-1/` | `asset/MAPS/landmarks/320x256-tile_4x1-level-1-landmarks.webp` |
| `python scripts/houses/normalize-mushroom-houses.py` | `asset/Originals/houses/` | mushroom house sheet in `asset/MAPS/Houses/` |
| `python scripts/art/build-ambient-decoration-sheets.py` | decoration sheet + `asset/Originals/decorations/ambient/` | `asset/MAPS/decorations/128x128-tile_8x5-decorations-ambient.webp` ([ambient animation](./AMBIENT_ANIMATION.md)) |
| `node scripts/props/wire-ambient-animations.mjs [--write]` | object scenes | ambient idle `AnimationPlayer` on animated decorations and trees |
| `python scripts/art/despill-magenta-fringe.py [--all] [--write] <image>...` | runtime images | the same files with magenta chroma-key fringe removed |
| `python scripts/art/build-terrain-edge-tiles.py [--preview <png>]` | `asset/Originals/grounds/generated/terrain-edges/` | Godot terrain-lab art in `godot/game/dev/terrain_lab/art/`: 128 px frozen/sand sheets and the 16 snow edge tiles ([terrain lab](../godot/TERRAIN_LAB.md)) |

None of these edit `asset/assets.json`; add or update the manifest entry by hand.

## Which file owns what?

| Need | Source of truth |
| --- | --- |
| File path, dimensions, sheet grid, frame count, texture key, load bundle | `asset/assets.json` |
| Art style, generation constraints, and source preparation | This folder's guides |
| Sprite, collision shapes, depth/occlusion, animations, script data | The scene JSON under `src/game/content/scenes/authored/` (edited in Scene Studio, `?studio=scenes`) |
| Terrain tile IDs, sheet selection, and tile physics | `terrain.tiles` resource (`scenes/authored/resources/terrain/terrain.tile-set.resource.json`) |
| Placement and per-instance overrides | Instances in a world scene (`scenes/authored/worlds/<map-id>.scene.json`) |
| Gameplay behavior | Script implementations in `src/game/features/scripts/` |

Do not put collision, solidity, health, damage, AI, or interactions in the
asset manifest.

## Verification commands

```text
pnpm assets:check
pnpm scenes:check
pnpm maps:check
```

`assets:check` also fails on any PNG or WebP under `asset/` that is neither registered
nor covered by an `ignore` pattern. Run `pnpm check` before committing, then
smoke-test the asset in Scene Studio and in the game.

## Image format

Runtime images under `asset/` ship as WebP; sources in `asset/Originals/` stay
as generated. Pack scripts save through `scripts/lib/game_webp.py`
(`save_game_webp`): colour is lossy (quality 90) unless that would visibly shift
a small outlined icon sheet (then lossless), and transparency is always kept
exactly and checked after every save. A hand-exported PNG can be converted
with `python scripts/assets/convert-png-to-webp.py --write`, which also
rewrites its path in `asset/assets.json`.

## Guides in this folder

- [Adding Game Assets](./adding-assets.md) — register media, build an object scene, and place instances.
- [Asset Sheet And Size Guide](./asset-sheet-spec.md) — shared sizes and sheet rules.
- [Character Sprites And Animated Visuals](./character-sprites-guide.md) — character scenes, sprite sheets, and animation libraries.
- [Slime Sheet Guide](./slime-sheet-guide.md) — player slime sheet format and frame layout.
- [Terrain And Tile Guide](./terrain-tile-guide.md) — ground sheets, tile physics, walls, and floor decorations.
- [Houses And World Props Guide](./houses-and-world-props-guide.md) — buildings, props, and doors.
- [Visual Style Guide](./visual-style-guide.md) — project art direction and generation constraints.
- [Character Animation Video Prompt](./character-animation-video-prompt.md) — reusable prompt for extracting animation frames.
- [Character Animation Video Prompt Template](./character-animation-video-prompt-template.md) — fill-in template with action and direction presets.
- [Magnific MCP Guide](./magnific-mcp-guide.md) — image/video generation workflow and project placement.
- [Magnific MCP Login Fix](./magnific-mcp-login-fix.md) — Codex CLI re-authentication workaround for the Magnific connector.
