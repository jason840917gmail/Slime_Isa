# Tooling Reference

The tools in `scripts/` and `godot/tools/`, and what they read and write. `package.json` holds the
`pnpm` shortcuts; the rest run with `node`, `python` or the Godot console executable directly.

Python tools need Pillow; the ones marked **numpy** also need numpy. Runtime art lives in
`godot/asset/` (`res://asset/...`); sources stay in `asset/Originals/`, outside the Godot project.
A tool that writes a sheet keeps its file name, so the scenes that use it and its Godot `.import`
file stay valid; open the Godot editor (or run a headless `--import` while no editor is open) to
import new or changed art, and commit the `.import` files.

Until the cutover (2026-10-05) many of these tools also registered their output in the Phaser asset
manifest or generated Phaser scene JSON; those steps are gone. Scenes are edited in the Godot editor.

## Godot

- `pnpm test:godot [-- --filter=<text>]` — the headless integration tests in `godot/tests/`
  (`--filter="a|b"` runs the tests matching either). `GODOT` points at the Godot 4.7.2 console
  executable when it is not in the default place. Run it when asked or after a big change.
- `res://tools/verify_scenes.gd` (`--headless --path godot -s res://tools/verify_scenes.gd`) — loads
  and instantiates every scene in `godot/game/scenes/scene_index.json`, checks properties and node
  references, and plays level-1 for 30 frames.
- `res://tools/build_player_clips.gd` (`--headless --path godot -s res://tools/build_player_clips.gd
  [-- --only=roll,attack-1]`) — (re)builds the directional clips of each v2 page in
  `game/characters/player_slime.tscn` from the page manifests (`asset/Originals/characters/slime-v2/page-<n>.json`),
  plus the keyed sword swings (`attack-1-<direction>`) and the keyed action clips (`hop`, `squash`,
  `teleport`, `eat` and `knockback`, each `-down`/`-up`/`-side`: page-1 frames chosen by pose); a row with
  a `shift` keys `Visual:offset` back by it, and a shifted `-side` row also gets a mirrored `-left` clip.
  Every other clip in the scene is removed. `--only` rebuilds just the clips with those name prefixes, so
  clips tuned in the editor (idle-down) stay as they are. Save or close the scene in an open editor
  first and reload it afterwards.
- `res://tools/build_ui_theme.gd` — rebuilds `game/ui/theme/slime_theme.tres` from `ui_tokens.gd`
  ([godot/UI_THEME.md](godot/UI_THEME.md)).
- `res://tools/build_terrain_lab.gd` — rebuilds the terrain lab scene ([godot/TERRAIN_LAB.md](godot/TERRAIN_LAB.md)).
- `python scripts/godot/fit-symbol-font-metrics.py [--check]` — copies the UI font's line metrics
  (Source Sans 3) into the symbol fallback font (Noto Sans Symbols 2), so the fallback does not make every
  label taller. Rerun it after replacing either font, then let Godot reimport the font
  ([UI_THEME.md](godot/UI_THEME.md#font)); `--check` exits 1 when they differ.

## Art pipelines

See [assets/README.md](assets/README.md) for the art workflow.

- `pnpm grounds:pack [-- --only <sheet>]` (**numpy**) — builds each 19x19 (64x64 tile)
  `godot/asset/MAPS/grounds/64x64-tile_19x19_<ground>.webp` (lossless) from
  `asset/Originals/grounds/{generated,legacy-sheets}/`, graded and made wrap-seamless for sheet-wrap tiling.
- `python scripts/art/build-terrain-edge-tiles.py [ground ...] [--preview DIR] [--grounds-2x]` (**numpy**) —
  the hand-made terrain edges: reads `asset/Originals/grounds/generated/terrain-edges/<ground>-island.png`
  and `-hole.png` (and the ground sheet in `godot/asset/MAPS/grounds/` as the colour reference) and writes
  `godot/game/world/terrain_edges/art/<ground>-edges.png` and `-edges-rim.png` ([godot/TERRAIN_LAB.md](godot/TERRAIN_LAB.md)).
- `pnpm props:pack` (**numpy**) — packs `asset/Originals/props/` into bottom-anchored
  `godot/asset/MAPS/rocks/<frame>x<frame>-tile_<cols>x<rows>-<name>.webp` atlases (the crystal cluster art of the
  `crystal-cluster-wall` object scenes).
- `python scripts/props/normalize-stone-walls.py` and `python scripts/props/build-wall-junctions.py` —
  register every stone wall piece in `godot/asset/MAPS/walls/` on one layout (vertical bands at x 9-61,
  horizontal bands at y 7-63 of the 70 px cell), then rebuild the T-junction art from the corners.
- `python scripts/props/pack-web-decor.py` — keys the spider web decorations (ground webs, tree webs,
  hanging and ground victim cocoons, egg sacs; generated on `#FF00FF`) out of `asset/Originals/props/webs/`
  and packs them into `godot/asset/MAPS/props/256x256-tile_4x3-web-decor.webp`.
- `python scripts/props/pack-gulp-props.py` — packs the Gulp and secret props (cracked ground, sinkhole,
  cave ladder, silk cocoon, spider web, Goo Heart, pressure plate up and down) from
  `asset/Originals/props/gulp/` into `godot/asset/MAPS/props/256x256-tile_8x1-gulp-props.webp`, and the
  Gulp form badges from `asset/Originals/ui/gulp/` into `godot/asset/UI/ui-gulp-form-icons-2x1.webp`.
- `python scripts/effects/pack-stretch-lash.py` — packs the Stretch Lash goo tendril from
  `asset/Originals/effects/stretch-lash/` into `godot/asset/MAPS/effects/384x96-tile_4x2-stretch-lash.webp`.
- `python scripts/characters/build-gulp-form-skins.py` — builds the Gulp form skins
  `godot/asset/characters/slime-form-{heavy,sticky}.webp` (the old side-view sheet re-textured; the
  top-down slime draws its forms with a shader instead).
- `python scripts/characters/pack-slime-v2-page.py [--page N] [--preview out.gif]` (**numpy**, Node,
  Brave) — packs a page of the three-quarter top-down player slime (1 = idle, walk, doze and sleep; 2 =
  rolls, the stretch lash and the defeat) from the Seedance clips in
  `asset/Originals/characters/slime-v2/videos/` into
  `godot/asset/characters/256x256-tile_8x8-slime-v2-page-<n>.webp` and `slime-v2/page-<n>.json` (loop
  choice, fps and looping per row). Rows listed in its `SPINS` are baked from a still, rows in `PICKS` use
  hand-picked source frames, rows in `SHIFTS` are drawn shifted in their cells (the manifest records the
  shift) and rows in `ROW_SCALES` smaller than the page scale. A page is always packed whole. It extracts
  frames with `node scripts/characters/extract-video-frames.mjs <outDir> <fps> <size> <name>=<file.mp4> ...`
  (headless Brave through Playwright; no ffmpeg needed). Then run `tools/build_player_clips.gd`.
- `python scripts/props/pack-training-dummy.py` — the playground's training dummy into
  `godot/asset/MAPS/objects/256x256-tile_1x1-training-dummy.webp`.
- `python scripts/effects/pack-lash-bell.py` — the lash bell post (at rest and swung both ways) into
  `godot/asset/MAPS/objects/256x256-tile_3x1-lash-bell-post.webp`.
- `python scripts/props/pack-resource-piles.py` — the resource piles from `asset/Originals/props/resources/`
  into `godot/asset/MAPS/resources/128x128-tile_4x2-resource-piles.webp` (heaps, then pickups) and
  `128x128-tile_2x1-starter-materials.webp`, each item fitted into its frame's old footprint so no scene moves.
- `python scripts/props/pack-level-1-landmarks.py` — the level-1 landmarks (Verdant Gate closed/open,
  village well, footbridge) into `godot/asset/MAPS/landmarks/320x256-tile_4x1-level-1-landmarks.webp`.
- `pnpm items:pack` (**numpy**) — slices the item icon sources in `asset/Originals/items/` into the 64x64
  atlases in `godot/asset/MAPS/items/`; `asset/Originals/items/atlas-index.json` names every frame. Item icon
  frames are listed in `godot/game/data/item-icons.json` and `items.json`.
- `python scripts/interiors/normalize-interior-sheets.py` (**numpy**) — rebuilds the interior atlases in
  `godot/asset/MAPS/interiors/` (and removes sheets it no longer produces, with their `.import` files).
- `python scripts/houses/normalize-mushroom-houses.py`, `pack-workshop.py` and `pack-forge.py` (**numpy**
  for the forge) — the house exteriors in `godot/asset/MAPS/Houses/` (one shared crop box per house, so a
  building does not shift when restored).
- `python scripts/items/pack-chapter-2-art.py` (**numpy**) — Chapter 2's item icons into
  `godot/asset/MAPS/items/chapter-2-5x2.webp`, and the iron ore node into
  `godot/asset/MAPS/rocks/128x128-tile_2x1-iron-ore.webp`.
- `python scripts/weapons/pack-iron-tools.py` (**numpy**) — the Chapter 2 weapon art into
  `godot/asset/MAPS/weapons/128x128-tile_4x1-iron-tools.webp`.
- `python scripts/art/build-ambient-decoration-sheets.py`, `build-tree-sway-sheets.py` and
  `build-water-life-sheets.py` (**numpy**) — the idle-loop sheets (campfire, cauldron, lantern post,
  banner, birdbath; tree canopy sway; water life) in `godot/asset/MAPS/`; the scenes' AnimationPlayers
  are edited in Godot ([assets/AMBIENT_ANIMATION.md](assets/AMBIENT_ANIMATION.md)).
- `python scripts/art/despill-magenta-fringe.py [--all] [--min-blue N] [--write] <image>...` (**numpy**) —
  removes magenta chroma-key fringe from sprite sheets. Dry run by default.

Every pack tool saves WebP through `scripts/lib/game_webp.py` (lossy quality 90 unless a small outlined
icon sheet would shift colour, then lossless; transparency always exact and verified).

## Audio

- `pnpm audio:bake [-- --library <dir>]` — ships one flavour per cue, as picked in
  `scripts/audio/picks.json`: renders the synth-picked cues from `scripts/audio/cues.mjs` to
  `godot/asset/audio/sfx/synth/` and keeps the library-picked cues' files in `godot/asset/audio/sfx/library/`;
  `--library` re-imports the library takes listed in `godot/asset/audio/CREDITS.md` (the parent folder
  must also hold a `magnific` copy of `asset/Originals/audio/magnific/`). It removes takes it no longer
  produces, with their `.import` files. Scenes reference the takes by path, so cue file names must stay.
