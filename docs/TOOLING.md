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
  [-- --only=roll,attack-1,shape-]`) — (re)builds the directional clips of each v2 page in
  `game/characters/player_slime.tscn` from the page manifests (`asset/Originals/characters/slime-v2/page-<n>.json`),
  plus the keyed sword swings (`attack-1-<direction>`) and the keyed action clips (`hop`, `squash`,
  `teleport`, `eat` and `knockback`, each `-down`/`-up`/`-side`: page-1 frames chosen by pose); a row with
  a `shift` keys `Visual:offset` back by it, and a shifted `-side` row also gets a mirrored `-left` clip.
  Alias clips (`ALIASES`) play a row already built at their own fps: `full-idle-down/-up/-side` on page 5's
  full rows at 2.67 fps (a slow sway at rest). Pose clips: page 6's manifest (`page-6.json`, written by
  `scripts/characters/pack-slime-shape-poses.py`) lists poses, not rows; each pose the game shows
  becomes `shape-<shape>-<pose>-<down|up|side>`, one held frame played once (no `-left`: no keyed
  offset): only the War Axe's `load`, `swing-down` and `swing-up` (9 clips), for its Spin and its
  charge ring (the poses of `ShapePoses.TIMELINES`). `--only=shape-` rebuilds just those. The body
  shapes' strikes have no clips in the scene: the game builds the `strikes` library (each strike and
  direction, and its `-hold` frame for the charge ring) at run time from `game/characters/strikes/`.
  Every other clip in the scene is removed, also on an `--only` run. `--only` rebuilds just the clips with
  those name prefixes, so clips tuned in the editor (idle-down) stay as they are. Save or close the scene
  in an open editor first and reload it afterwards. A headless save writes no `uid=` attributes (the
  editor adds them back on its next save; the scene is loaded by path).
- `godot/addons/strike_preview/` (editor plugin "Strike Preview", enabled in `project.godot` next to godot_ai) —
  click a body-shape strike file (`game/characters/strikes/*.tres`) and the Inspector plays it above its fields: the
  slime large in side, down and up as the game draws it (the strike sheet's body frame, the StrikeRig's weapon,
  neck and views, the hit area, the reach readouts and the socket), a Play / Pause loop in real time and a time bar
  with the windup, active and recovery bands and every key. In each view the hit centre's cross and the reach ring's
  handle can be dragged (`hit_center`, `hit_reach`; each drag one step in the editor's undo history); edits show at
  once, Ctrl+Z undoes them and Ctrl+S saves. It reads the step's timing from `game/data/game-constants.json`, writes
  only through those drags and does not touch the player scene
  ([godot/BODY_SHAPES.md](godot/BODY_SHAPES.md#editing-the-strike-animations-2026-10-12)).
- `res://tools/build_ui_theme.gd` — rebuilds `game/ui/theme/slime_theme.tres` from `ui_tokens.gd`
  ([godot/UI_THEME.md](godot/UI_THEME.md)).
- `res://tools/render_ceremony.gd` (windowed: `--path godot -s res://tools/render_ceremony.gd -- --out=<dir>
  [--ability=swallow]`) — starts the playground like a new run, learns an ability (the Roll by default) and
  saves `<dir>/ceremony-<n>.png` as the ability ceremony plays (the bubble rising, the card, the gulp after a
  key press), for tuning it without playing to a quest.
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
  `godot/asset/MAPS/terrain-edges/<ground>-edges.png` and `-edges-rim.png` ([godot/TERRAIN_LAB.md](godot/TERRAIN_LAB.md));
  `--grounds-2x` also turns `<ground>-2x-padded-upscale.jpg` into the 128 px ground sheet
  `godot/asset/MAPS/grounds/128x128-tile_19x19_<sheet>.webp`.
- `python scripts/art/build-elevation-art.py [name ...] [--preview DIR]` (**numpy**) — the cliff art:
  seamless walls and their corner-stone ends per wall style (nine: meadow rock, snow rock, sandstone,
  cave rock, crystal rock, mossy rock, masonry, root rock, red rock), the stairs kit (treads, risers, a
  coping per wall style), and each ground's cliff lip and foot, from
  `asset/Originals/elevation/generated/` into `godot/asset/MAPS/elevation/`
  ([godot/ELEVATION.md](godot/ELEVATION.md#making-the-art)); `scripts/art/build-elevation-paint-tiles.py` draws
  the elevation layer's paint tiles and `scripts/art/build-cliff-paint-tiles.py` the cliffs layer's
  (one swatch per wall style; run it after the walls).
- `python scripts/maps/build-elevation-park.py` — rebuilds the playground's Elevation Park (its rows
  of ground and water, its painted levels and stairs, the wall styles on its `cliffs` layer); close the
  playground in the editor first. `res://tools/render_elevation_park.gd` (windowed:
  `--path godot -s res://tools/render_elevation_park.gd -- --out=<dir>`) renders the park's rows and a few
  close-ups with the game's own drawing and prints how many walls each style has.
- `python scripts/art/build-fence-art.py [style ...] [--preview DIR]` (**numpy**) — the fences along hill
  rims: cuts each style's generated front view (`asset/Originals/elevation/fences/`) into its kit (posts,
  a seamless rail strip, the rail seen from above, a JSON of measures) in
  `godot/asset/MAPS/fences/` ([godot/FENCES.md](godot/FENCES.md)); `scripts/art/build-fence-paint-tiles.py`
  draws the fences layer's paint tiles.
- `python scripts/art/build-forest-paint-tiles.py` (**numpy**) — the forest layer's palette: a tile per mix and
  per tree of the trees sway sheet, into `godot/asset/MAPS/forest/forest_paint_tiles.png` and
  `godot/game/world/forest/forest_tileset.tres` ([godot/FORESTS.md](godot/FORESTS.md)).
- `python scripts/art/build-cliff-kit.py [--preview DIR]` (**numpy**) — the cliff kits: scales the approved
  cliff paintings (`asset/Originals/elevation/cliff-concepts/`) to 128 px per cell, cuts the outside ground
  away and labels every cell, into `godot/asset/MAPS/cliffs/kit-<name>.png` and `.json`, drawn by the cliff
  shape and cliff builder nodes; `--headless --path godot -s res://tools/build_cliff_kit_lab.gd` rebuilds the
  cliff kit lab ([godot/CLIFFS.md](godot/CLIFFS.md)).
- `python scripts/art/build-elevation-art-from-painting.py [--preview DIR]` (**numpy**) — elevation art cut from
  the aligned H paintings (`godot/asset/MAPS/cliffs/kit-h3.png`, `kit-h2.png`) instead of generated: the wall
  style `storybook-rock` (wall, end stones, stairs coping) and the fringe `storybook-grass` (lip, foot) in
  `godot/asset/MAPS/elevation/`; a world picks them with its ground layer's metadata `cliff_wall_styles` /
  `cliff_fringe`; `--headless --path godot -s res://tools/build_cliff_shapes_lab.gd -- --force` rebuilds the
  cliff shapes lab that shows them ([godot/CLIFFS.md](godot/CLIFFS.md#painted-elevation-2026-10-10)).
- `python scripts/art/build-cliff-tiles.py [--preview DIR]` (**numpy**) — the hand-painted cliffs: cuts the
  generated border, lip, foot, wall and ground decorations (`asset/Originals/elevation/cliff-tiles/`) and the
  128 px grass into one sheet of cell-sized tiles and its tile list in `godot/asset/MAPS/cliffs/`, and the
  labelled guide `docs/godot/cliffs-sheet-guide.png`; then, after the editor imports the sheet,
  `--headless --path godot -s res://tools/build_cliff_lab.gd` writes the cliff TileSet (one terrain set,
  collision) and rebuilds the cliff lab ([godot/CLIFFS.md](godot/CLIFFS.md)).
- `python scripts/maps/build-fence-park.py` — rebuilds the Fence Park dev world
  (`godot/game/scenes/worlds/fence-park.tscn`, every hill shape fenced); `res://tools/render_fence_park.gd`
  (windowed: `--path godot -s res://tools/render_fence_park.gd -- --out=<dir>`) renders it with test slimes and
  prints collision, drop and hop probes against its fences.
- `python scripts/art/pack-hud-console.py` — packs the HUD console's art from `asset/Originals/ui/hud-console/` into
  `godot/asset/UI/hud-console/` (the orb ring, the bar, the slot, an icon per ability and per menu button) and prints the
  measures `game/ui/console/` keeps as constants (the ring's hole, the bar's panel and ends).
- `res://tools/render_hud_mockup.gd` (windowed: `--path godot -s res://tools/render_hud_mockup.gd -- --map=level-1
  --out=<dir>`) renders level-1 at 2x with today's HUD and without it (the views of the console layout), and
  `python scripts/art/build-hud-console-mockup.py --frames <dir> [--out DIR]` (**numpy**) draws the proposed
  bottom console over those frames into `docs/design/hud-console/`, from the art in
  `asset/Originals/ui/hud-console/` ([the mockup](design/2026-10-07-hud-console-mockup.md)).
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
  Gulp form badges from `asset/Originals/ui/gulp/` into `godot/asset/UI/ui-gulp-form-icons-3x1.webp` (Heavy, Sticky, Frog;
  the HUD's form badge).
- `python scripts/art/pack-heavy-plate-art.py` — the heavy plate's fixed base (full and front) and its
  cap (released and pressed) from `asset/Originals/props/heavy-plate/plate-b.png` into
  `godot/asset/MAPS/props/heavy-plate/` (2 px per unit); it prints the placement numbers
  `game/scripts/heavy_plate.gd` uses ([godot/BODY_SHAPES.md](godot/BODY_SHAPES.md#heavy-plates-and-heavy-blocks-2026-10-14)).
- `python scripts/art/pack-door-art.py` — the door pictures from `asset/Originals/buildings/doors/` into
  `godot/asset/MAPS/Houses/doors/` (2 px per unit): the level-1 mushroom house's leaf and the interior
  ways out (timber, mushroom); it prints each interior picture's leaf rect for the scene's `door_rect`
  ([godot/CONVENTIONS.md](godot/CONVENTIONS.md#doors)).
- `python scripts/props/pack-gulp-art.py` (**numpy**) — the Gulp's things to suck and throw (2026-10-09), from the
  Magnific stills in `asset/Originals/gulp/generated/` ([its README](../asset/Originals/gulp/README.md)):
  - the liftables into `godot/asset/MAPS/props/192x192-tile_8x9-gulp-liftables.webp` (8 columns × 9 rows of
    192 px). Rows 0-7 are the 64 objects of `grid-1.png` .. `grid-4.png` (4 x 4 grids, two grid rows per sheet
    row): each grid cell is cut out (the see-through haze over grid-4's background is keyed out) and cleared
    of specks under 40 px. Row 8 is the mossy rock, puffball and pinecone, two variants each (frames 64-69). Every
    object is trimmed, fitted into its cell (never upscaled) and stood on the cell's bottom centre. It deletes
    the old 6 x 1 sheet;
  - the catalog `godot/game/data/liftables.json` that `game/scripts/liftable.gd` reads: per kind its name,
    material, frames and art size. The kinds, names and materials are authored in the script's `GRIDS` and
    `FIRST`, not in the JSON;
  - the essences into `godot/asset/MAPS/items/128x128-tile_3x1-gulp-essences.webp` (stone, silk, swim: on the
    ground, in the mouth and as bag icons).

  `res://tools/render_gulp_art.gd` (windowed: `--path godot -s res://tools/render_gulp_art.gd -- --out=<dir>`)
  renders the Gulp art with the game's own scenes on one sheet (`<dir>/gulp-art.png`): the slime's suck, spit,
  full and ball clips, the Clod Stomper, Tom and his web, a sample of the liftables and the essences.
- `python scripts/effects/pack-stretch-lash.py` — packs the Stretch Lash goo tendril from
  `asset/Originals/effects/stretch-lash/` into `godot/asset/MAPS/effects/384x96-tile_4x2-stretch-lash.webp`.
- `python scripts/characters/build-gulp-form-skins.py` — builds the Gulp form skins
  `godot/asset/characters/slime-form-{heavy,sticky}.webp` (the old side-view sheet re-textured; the
  top-down slime draws its forms with a shader instead).
- `python scripts/characters/pack-slime-v2-page.py [--page N] [--preview out.gif]` (**numpy**, Node,
  Brave) — packs a page of the three-quarter top-down player slime (1 = idle, walk, doze and sleep; 2 =
  rolls, the stretch lash and the defeat; 3 = swim; 4 = the Gulp's suck and spit and the Roll's ball; 5 =
  the full slime's waddle; pages 4 and 5 take page 1's scale from its manifest, `PAGE_1_SCALE`) from the Seedance clips in
  `asset/Originals/characters/slime-v2/videos/` into
  `godot/asset/characters/256x256-tile_8x8-slime-v2-page-<n>.webp` and `slime-v2/page-<n>.json` (loop
  choice, fps and looping per row). Rows listed in its `SPINS` are baked from a still, rows in `PICKS` use
  hand-picked source frames, rows in `SHIFTS` are drawn shifted in their cells (the manifest records the
  shift) and rows in `ROW_SCALES` smaller than the page scale. A page is always packed whole. It extracts
  frames with `node scripts/characters/extract-video-frames.mjs <outDir> <fps> <size> <name>=<file.mp4> ...`
  (headless Brave through Playwright; no ffmpeg needed). Then run `tools/build_player_clips.gd`.
- `python scripts/characters/pack-slime-shape-poses.py` — the body-shapes art of 2026-10-12
  ([its README](../asset/Originals/characters/slime-v2/shapes/README.md), [godot/BODY_SHAPES.md](godot/BODY_SHAPES.md#art-2026-10-12)),
  from `asset/Originals/characters/slime-v2/shapes/`: the slime's attack key poses
  (`poses-<shape>-<direction>.png`, 2 x 2 sheets) into page 6,
  `godot/asset/characters/256x256-tile_8x8-slime-v2-page-6.webp` (page 1's cells and baseline, each sheet
  scaled to cover page 1's idle area), and `slime-v2/page-6.json` (where each pose landed); the jelly
  weapons into `godot/asset/characters/shapes/<shape>.webp` and `shapes.json` (the Spear's shaft width, root
  end and head start, each head's start: the axe's and the hammer's are measured constants, `HEAD_STARTS`); the goo
  splat (a 4 x 1 strip of 256 px), the Axe swoosh, the Spear glint and the energy shard into
  `godot/asset/MAPS/effects/`; and the shape icons (each weapon turned 45 degrees, 128 px) into
  `godot/asset/UI/shapes/<shape>-icon.webp`. Then run `tools/build_player_clips.gd -- --only=shape-` (it
  builds the poses the game shows: the War Axe's, for its Spin).
- `python scripts/characters/pack-slime-strikes.py [--preview <dir>]` (**numpy**) — the Spear's strike frames
  of 2026-10-12 ([its README](../asset/Originals/characters/slime-v2/shapes/README.md#strike-sheet-2026-10-12),
  [godot/BODY_SHAPES.md](godot/BODY_SHAPES.md#the-spears-strike-frames-2026-10-12)): the six-frame body-only
  strips `asset/Originals/characters/slime-v2/shapes/strikes/spear-<jab|finisher>-<side|down|up>.png` into
  `godot/asset/characters/512x416-tile_8x8-slime-v2-strikes.webp` (8 x 8 cells of 512 x 416 centred like
  page 1's; rows 0-2 spear-jab side / down / up, rows 3-5 spear-finisher, columns 0-5 = frames 1-6; one
  scale per strip, set by its rest frame against page 1's idle; the jelly neck baked into frames 3 and 4)
  and `godot/game/data/shape-strikes.json` (per strike, direction and frame the socket, the bump tip and the
  spear's state; the cell's origin and scale; the spear's tint). It stops when a frame does not fit and
  prints the cell size the art needs. `--preview` writes check images (the sheet on grass with the
  sockets, the joins with the spear behind the body, the rest frames beside page 1's idle). The manifest
  is merged: its own top-level keys and strikes are replaced, the War Axe's and the Hammer's stay. The game
  reads the sheet and the manifest at run time (there are no strike clips to build).
- `python scripts/characters/pack-slime-weapon-strikes.py [--preview [<dir>]] [--knobs-only]` (**numpy**) —
  the War Axe's and the Hammer's strike frames of 2026-10-12 ([its README](../asset/Originals/characters/slime-v2/shapes/README.md#war-axe-and-hammer-strike-sheets-2026-10-12),
  the contract [design/2026-10-12-weapon-strike-frames.md](design/2026-10-12-weapon-strike-frames.md)), with
  pack-slime-strikes.py's helpers: the strips `strikes/axe-<sweep|chop>-<side|down|up>.png`,
  `axe-backswing-side.png` (its front and back views are the sweep's rows, mirrored) and
  `hammer-<thud|boom>-<side|down|up>.png` into `godot/asset/characters/512x416-tile_8x8-slime-v2-strikes-axe.webp`
  (rows 0-2 sweep, 3 backswing side, 4-6 chop) and `...-strikes-hammer.webp` (rows 0-2 thud, 3-5 boom), the
  Spear's grid, cell and scale, no neck baked in; the code neck `godot/asset/characters/shapes/neck.webp`; the
  weapon views `weapon-<axe|hammer>-<toward|away>.png` into `godot/asset/characters/shapes/<axe|hammer>-views.webp`
  (the front and back chop and smashes turn through them); and,
  merged into `godot/game/data/shape-strikes.json` (the Spear's entries stay), per strike its sheet and weapon,
  per direction the row (or `flip` of the sweep's), the jelly arm `arm_px` (solved so the reach at contact
  meets the game's hit numbers, `REACH_TARGETS`), per frame the knob's socket and `knob_w`, the timeline
  `keys`, the art's `contact` reach, plus the `weapons` and `neck` blocks. `--preview` (default
  `asset/Originals/characters/slime-v2/shapes/prototypes/strikes-preview/`) simulates what the game draws
  from the manifest (GIFs per strike and direction, chains, contact, knob and neck sheets); `--knobs-only`
  writes only the knob sheets. The game reads the sheets and the manifest at run time (no clips to build). Since round 3
  (2026-10-12) the motion is the strike animations (below) and the manifest has no `keys`: the packer's
  timelines, its reach solving against them and its previews of them are legacy (a re-run writes keys
  back; the game ignores them).
- `godot/game/characters/strikes/*.tres` (the body shapes' strike files, rounds 4 and 5 of
  docs/design/2026-10-12-weapon-strike-frames.md): seven resources, one per strike, edited in the Inspector with
  the strike preview above their fields (`godot/addons/strike_preview/`, under Godot above; docs/godot/BODY_SHAPES.md
  "Editing the strike animations"). They hold the chain steps' hit reach (`hit_reach` per direction, measured from its
  `hit_center`; since round 5 game-constants.json has none for them), each direction's drawn reach (`arm_px`, negative
  pulls the weapon in) and its `socket_nudge`. Nothing generates them:
  `game/shapes/strike_library.gd` builds the player's `strikes` library from them at run time. The Round 3 converter
  `tools/build_strike_animations.gd` and its library were removed; the one-off Round 3 to Round 4 migration was
  removed after it ran (the round 5 key thinning was a one-off scratch run, never in the project).
- `python scripts/characters/pack-clod-stomper.py` (**numpy**) — the Clod Stomper's five poses (idle, crouch,
  air, slam, defeated; one scale for all) from `asset/Originals/enemies/clod-stomper/` into
  `godot/asset/MAPS/enemies/256x256-tile_5x1-clod-stomper.webp`.
- `python scripts/characters/pack-tom.py` (**numpy**) — Tom from `asset/Originals/characters/tom/` into
  `godot/asset/characters/authored/npcs/tom.webp`, and the web he is caught in (the cocoon, then the torn web
  at the cocoon's scale) into `godot/asset/MAPS/props/256x256-tile_2x1-tom-web.webp`.
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
- `python scripts/art/build-water-wake-sheet.py` (**numpy**) — the water at walkers' feet: the wading
  splash and the swim ripple (`asset/Originals/water/generated/wade-splash.png`, `swim-ripple.png`, 2 x 2
  grids from Magnific), each frame aligned on its ring, into
  `godot/asset/MAPS/water/224x128-tile_4x2-water-wake.webp`, which `game/world/water_wake.gd` draws
  ([godot/specs/water.md](godot/specs/water.md#9-wading-godot-only)).
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

### Sound Picker rounds

New sounds are chosen on the
[Slime Isa Sound Picker](https://claude.ai/artifact/RDDoJKEVByiJCSsRvzwLHZ) page before they ship. A
round is one manifest, `scripts/audio/picker/round-<n>.json`: its cues, each with options (a label,
a kind, source takes), the option the game plays meanwhile (`inGame`), the player node it drives
and where it ships. These Python tools need `pip install miniaudio lameenc numpy`; none needs ffmpeg.

- `python scripts/audio/slice-steps.py <out-prefix> <walk.mp3>...` — cuts single steps out of
  generated walks (Magnific gives textures, not clean steps). It keeps the clearest onsets, each
  shaped into one percussive step (`--count`, `--length`, `--decay`).
- `python scripts/audio/prep-takes.py <manifest>` — writes each take as a trimmed, peak-normalised
  mono WAV and a 96 kbps MP3 into the manifest's `takes` folder (`temp/` while a round is open).
  One-shots keep only their loudest event.
- `python scripts/audio/picker/build-picker.py <manifest> <out.html>` — builds the picker page from
  `scripts/audio/picker/picker.html` with the takes embedded. It is published to the picker
  artifact, which saves the owner's picks to its database document `picks/<round>`.
- `python scripts/audio/stage-round.py <manifest> [--picks <picks.json>]` — ships each cue's game
  option into `godot/asset/audio/sfx/library/` and writes the players. Files are named
  `<cue>-<n>.wav`, or `<cue>.wav` for a single take, as the bake names them. It writes
  `game/scenes/audio/footsteps.tscn` whole when the round has steps, and adds or updates the
  players under `Effects` in `global.tscn`. Volumes come from measured loudness (`TARGET_DB`).
  - Without `--picks`, it also copies every option's MP3s and `audition.json` to
    `godot/asset/audio/sfx/audition/` for the in-game audition (`?audition`, F7/F8;
    [audio spec §10](godot/specs/audio.md#10-steps-water-and-the-round-3-cues)). The release
    Web export leaves that folder out.
  - With the saved picks, it applies them. The picks are the `picks/<round>` document as JSON,
    kept as `scripts/audio/picker/round-<n>-picks.json`.
    - The shipped takes are also copied to
      `asset/Originals/audio/magnific/<category>-<cue>-r<n>-<k>.wav`.
    - Cues picked silent lose their players and files.
    - The audition folder is removed. Stage the next open round afterwards.

  After applying, register the shipped takes in `scripts/audio/cues.mjs` (library only, no synth
  recipe) and `picks.json` so `pnpm audio:bake -- --library` keeps them.

## Story

- `pnpm story:map` (`node scripts/story/world-map/server.mjs`, `--port=<n>`; also `.claude/launch.json`
  "world-map") — the world map sketch tool at http://127.0.0.1:3210. It edits the world layout,
  `godot/game/data/world-map.json` (format version 2; read in Godot through
  `godot/game/world/atlas/world_map_data.gd`), and is used to plan which region sits where and what
  connects to what ([story/03-world.md](story/03-world.md#world-map)).
  - **Layers.** It paints four layers on a grid of cells:
    - terrain (grass, forest, water, swamp, snow, lava, …);
    - elevation (0–4; cliffs are drawn where it drops);
    - regions, each with its chapter, status, `id`, `world` (the overworld scene id), `interiors`,
      `placeholder` (built by `godot/tools/build_region_worlds.gd`, safe to rebuild), `theme` and boss;
    - markers (gates, caves, warps, dungeons, bosses, towns, NPCs, secrets, notes).

    The layers sit over a chunk grid: 8 × 8 by default, named A1 in the north-west to H8, and
    "More… → Chunk count" changes it.
  - **Connections.** A gate, cave or warp connects the regions within two cells of it, plus its
    "leads to" region. The `passages` the region builder writes (the openings between touching
    regions) are drawn as white gaps on the borders; the "passages" checkbox hides them. The tool never
    edits them by hand. The right panel lists every border with its passages and openings, flags a
    shared border with neither, and flags an opening whose regions no longer touch.
  - **Layout tools.** These move whole blocks of chunks with every layer, marker and passage on them,
    exactly as `world_map_data.gd` does, and Ctrl+Z undoes each one.
    - The region inspector's Move buttons slide a region one chunk. The strip of chunks it slides
      onto goes to the side it left.
    - Its "Swap with" control exchanges two regions of the same size.
    - The Swap chunks tool (X) swaps two blocks: drag block A, then drag a block of the same size
      (or click its north-west chunk). Escape cancels.

    A move is refused, with the reason, when the region does not fill a rectangle of whole chunks,
    when it would leave the map, or when it would cut another region apart (leave it in more pieces
    than it had, or a rectangle of whole chunks no longer whole). The Swap chunks tool swaps anyway
    and says which regions it cut apart.
  - **Saving.** Save (Ctrl+S) writes three things:
    - `godot/game/data/world-map.json`, with one text row per grid row so diffs stay readable;
    - `docs/story/world-map.png`;
    - the generated block between the `world-map` markers in `docs/story/03-world.md`.

    Keys and fields the tool does not know are written back unchanged. Grid values it does not know
    (a terrain character, a height above 4, a region key with no region) are not: it says so when it
    opens the file, and a save writes them as unplanned ground, height 4 (0 for a height that is not
    a digit) and no region. A version 1 file (the old `docs/story/world-map.json`, whose regions had
    a `maps` text) still opens: a list of plain ids becomes the region's `world` and `interiors`,
    anything else (candidates) goes to its notes and leaves `world` empty.

    Save asks before overwriting the file when it changed on disk since the page loaded it (the
    Godot world atlas or the region builder wrote it), and when the page could not load it (a
    half-written or broken file: the page starts blank, says why and shows "Map file not loaded").
    With no file yet, the page starts blank and Save writes one. "More… → Reload from disk" loads
    the file again, and Undo brings the drawing back. The server takes saves only from its own page
    (a JSON request from `http://127.0.0.1:<port>` or `http://localhost:<port>`).
  - **Other features.** A reference image can be laid over the map for tracing (it is not saved).
    Opened as a plain file, without the server, Save downloads the JSON and PNG instead.
  - **Trying it on a copy.** `--map=<file> --png=<file> --doc=<file>` point the server at copies,
    so it can be tried without touching the real files:
    `node scripts/story/world-map/server.mjs --port=3299 --map=<copy>.json --png=<copy>.png --doc=<copy>.md`.
- `"<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_region_worlds.gd
  [-- --only=<region key or world id>,... --dry-run --force]` — builds the placeholder region worlds
  from the layout (every region with `"placeholder": true`): ground, heights, tree borders with one
  opening per shared border, roads, stairs, bridges, no dead-end ledge drops, exits both ways
  between placeholders (one-way into a hand-made world until it has its own exit there); writes the
  layout's `passages`,
  `scene_index.json` and the release export's exclude list ([godot/WORLD_ATLAS.md](godot/WORLD_ATLAS.md)).
  It never touches a hand-made world.
- `"<Godot 4.7.2 console exe>" --path godot -s res://tools/render_world_atlas.gd -- --out=<dir>`
  (windowed: it renders) — draws the world atlas (`godot/game/dev/world_atlas.tscn`: every region's
  world on the chunk grid) to PNGs and prints its warnings.
