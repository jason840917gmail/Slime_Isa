# Asset Creation And Integration

This is the starting point for creating new game art and making it available
to the game (Godot; `godot/`).

## Recommended workflow

1. Read the [asset sheet and size contract](asset-sheet-spec.md).
2. Choose the right art type guide:
   - [Animated character sheets](slime-sheet-guide.md)
   - [Terrain and ground art](terrain-tile-guide.md)
   - [Houses and world props](houses-and-world-props-guide.md)
   - [Ambient object animation](AMBIENT_ANIMATION.md) for anything that should move while idle
3. Generate or commission the art using the [visual style guide](visual-style-guide.md), the [Magnific MCP guide](magnific-mcp-guide.md), or the [character animation video prompt](character-animation-video-prompt.md).
4. Keep source and experimental output under `asset/Originals/`. Where a pack script exists, run it
   to produce the runtime sheet in `godot/asset/` (see below); otherwise export a clean uniform-grid
   sheet there yourself. Runtime images ship as WebP (see [Image format](#image-format)).
5. Let the Godot editor import it (commit the `.import` file), then use it in a scene: a new object
   is a scene in `godot/game/scenes/objects/` (copy a similar one: a `Sprite2D` with `hframes`/`vframes`,
   collision shapes, an `AnimationPlayer` for idle loops), listed in `godot/game/scenes/scene_index.json`
   when the game loads it by id, and placed as an instance in a world scene.
6. Check it in the game (the playground, `godot/game/dev/playground.tscn`, F6).

## Asset folders

| Folder | Holds | Loaded by the game? |
| --- | --- | --- |
| `asset/Originals/` | Sources and concepts only: generated renders, Seedance clips, start and end stills, concept sheets, intermediate cut-outs, packer manifests and notes | **Never.** It sits outside the Godot project, so Godot never imports it |
| `asset/project/` | Sprite-sheet tool projects (`.sscproj`) | Never (sources) |
| `godot/asset/MAPS/<kind>/` | World art: grounds, rocks, trees, resources, props, houses, interiors, landmarks, effects, decorations | Yes (`res://asset/MAPS/...`) |
| `godot/asset/characters/`, `godot/asset/UI/`, `godot/asset/audio/` | Character sheets, UI art, sound and music | Yes (same) |
| `godot/game/world/terrain_edges/art/` | The terrain edge sheets `build-terrain-edge-tiles.py` writes | Yes |

A game-ready sheet never lives in `asset/Originals/`: pack it into the runtime folder of its kind in
`godot/asset/` and keep its sources next to the others in `Originals/`. Until the cutover
(2026-10-05) the runtime folders sat in `asset/` and were registered in `asset/assets.json`; both
moved or retired with the Phaser app.

## Pack and generator scripts

The Python tools need Python 3 with Pillow (and numpy for most of them). Every tool and what it
reads and writes: [TOOLING.md](../TOOLING.md#art-pipelines).

| Command | Reads | Writes |
| --- | --- | --- |
| `pnpm grounds:pack` | `asset/Originals/grounds/{generated,legacy-sheets}/` | wrap-seamless `godot/asset/MAPS/grounds/64x64-tile_19x19_<ground>.webp` |
| `pnpm props:pack` | `asset/Originals/props/` | bottom-anchored `godot/asset/MAPS/rocks/<frame>x<frame>-tile_<cols>x<rows>-<name>.webp` |
| `pnpm items:pack` | `asset/Originals/items/` | the item atlases in `godot/asset/MAPS/items/` and `asset/Originals/items/atlas-index.json` |
| `python scripts/interiors/normalize-interior-sheets.py` | `asset/Originals/interiors/generated-sheets/` | `normalized-sheets/`, `godot/asset/MAPS/interiors/`, `atlas-index.json` |
| `python scripts/props/pack-level-1-landmarks.py` | `asset/Originals/props/level-1/` | `godot/asset/MAPS/landmarks/320x256-tile_4x1-level-1-landmarks.webp` |
| `python scripts/props/pack-resource-piles.py` | `asset/Originals/props/resources/resource-{heaps,pickups}.png` | `godot/asset/MAPS/resources/128x128-tile_4x2-resource-piles.webp` (mine heaps, then pickups) and `128x128-tile_2x1-starter-materials.webp` (wood and stone pickups), each item fitted into the old frame's footprint |
| `python scripts/houses/normalize-mushroom-houses.py` | `asset/Originals/houses/` | mushroom house sheet in `godot/asset/MAPS/Houses/` |
| `python scripts/art/build-ambient-decoration-sheets.py` | decoration sheet + `asset/Originals/decorations/ambient/` | `godot/asset/MAPS/decorations/128x128-tile_8x5-decorations-ambient.webp` ([ambient animation](AMBIENT_ANIMATION.md)) |
| `python scripts/art/despill-magenta-fringe.py [--all] [--write] <image>...` | runtime images | the same files with magenta chroma-key fringe removed |
| `python scripts/art/build-terrain-edge-tiles.py [ground ...] [--preview DIR] [--grounds-2x]` | `asset/Originals/grounds/generated/terrain-edges/<ground>-island.png`, `<ground>-hole.png` | terrain edge art in `godot/game/world/terrain_edges/art/`: 16 edge tiles + rim weights per ground; with `--grounds-2x`, 128 px ground sheets from padded upscales ([terrain edges](../godot/TERRAIN_LAB.md)) |

## Which file owns what?

| Need | Source of truth |
| --- | --- |
| The image or sound | Its file in `godot/asset/` (sheet grid in the file name, e.g. `128x128-tile_4x2-...`) |
| Import settings (compression, filtering) | Its `.import` file, set in the Godot editor's Import dock |
| Art style, generation constraints, and source preparation | This folder's guides |
| Sprite frames, collision shapes, draw order, animations, script properties | The scene in `godot/game/scenes/` (Godot editor) |
| Terrain tile ids, sheet selection, and tile physics | `godot/game/world/terrain_tileset.tres` (`tile_id` custom data) |
| Placement and per-instance overrides | Instances in a world scene (`godot/game/scenes/worlds/<map-id>.tscn`) |
| Item icons | `godot/game/data/items.json` and `item-icons.json` |
| Gameplay behaviour | Scripts in `godot/game/` (scene scripts in `godot/game/scripts/`) |

## Image format

Runtime images ship as WebP; sources in `asset/Originals/` stay as generated. Pack scripts save
through `scripts/lib/game_webp.py` (`save_game_webp`): colour is lossy (quality 90) unless that would
visibly shift a small outlined icon sheet (then lossless), and transparency is always kept exactly and
checked after every save. Godot then imports each texture with the project's settings (its `.import`
file; the terrain edge sheets are imported lossless).

## Guides in this folder

- [Asset Sheet And Size Guide](asset-sheet-spec.md) — shared sizes and sheet rules.
- [Slime Sheet Guide](slime-sheet-guide.md) — player slime sheet format and frame layout.
- [Terrain And Tile Guide](terrain-tile-guide.md) — ground sheets, tile physics, walls, and floor decorations.
- [Houses And World Props Guide](houses-and-world-props-guide.md) — buildings, props, and doors.
- [Visual Style Guide](visual-style-guide.md) — project art direction and generation constraints.
- [Character Animation Video Prompt](character-animation-video-prompt.md) — reusable prompt for extracting animation frames.
- [Character Animation Video Prompt Template](character-animation-video-prompt-template.md) — fill-in template with action and direction presets.
- [Magnific MCP Guide](magnific-mcp-guide.md) — image/video generation workflow and project placement.
- [Magnific MCP Login Fix](magnific-mcp-login-fix.md) — Codex CLI re-authentication workaround for the Magnific connector.
- [Ambient Animation](AMBIENT_ANIMATION.md) — which objects get idle loops and how.

The Phaser-era guides (adding assets through the manifest and Scene Studio, character sprites and
animation libraries) are in [../archive/phaser/assets/](../archive/phaser/assets/).
