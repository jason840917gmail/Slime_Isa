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
- `godot/addons/strike_preview/` (editor plugin "Strike Preview", enabled in `project.godot` next to godot_ai
  and the Scenery dock) —
  click a body-shape strike file (`game/characters/strikes/*.tres`) and the Inspector plays it above its fields: the
  slime large in side, down and up as the game draws it (the strike sheet's body frame, the StrikeRig's weapon,
  neck and views, the hit area, the reach readouts and the socket), a Play / Pause loop in real time and a time bar
  with the windup, active and recovery bands and every key. In each view the hit centre's cross and the reach ring's
  handle can be dragged (`hit_center`, `hit_reach`; each drag one step in the editor's undo history); edits show at
  once, Ctrl+Z undoes them and Ctrl+S saves. It reads the step's timing from `game/data/game-constants.json`, writes
  only through those drags and does not touch the player scene
  ([godot/BODY_SHAPES.md](godot/BODY_SHAPES.md#editing-the-strike-animations-2026-10-12)).
- `res://tools/build_ui_theme.gd` — rebuilds `game/ui/theme/slime_theme.tres` and its icons (`game/ui/theme/icons/`) from `ui_tokens.gd`
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
  a seamless wall per wall style (nine: meadow rock, snow rock, sandstone, cave rock, crystal rock,
  mossy rock, masonry, root rock, red rock) and the stairs kit (treads, risers, a coping per wall
  style), from `asset/Originals/elevation/generated/` into `godot/asset/MAPS/elevation/` (the corner-stone
  wall ends and the grounds' lips and feet it once made belonged to the front-only cliff look, removed
  on 2026-10-17)
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
- `python scripts/art/build-tree-sets.py [set ...]` (**numpy**) — the trees of every region set (forest,
  autumn, frost, desert, volcano, swamp, crystal, ruins, village): cuts the Magnific renders in
  `asset/Originals/trees/<set>/generated/` (a medium and a tall tree each), grades leaves where set,
  sizes them at 2 px per unit and packs `godot/asset/MAPS/trees/sets/<set>.webp` with the shared
  `trees.json` (each tree's atlas, rectangle, foot, whether it sways and its cover mask; keep mipmaps on
  in a new atlas's import). Run
  `build-forest-paint-tiles.py` after it ([godot/FORESTS.md](godot/FORESTS.md)). Godot tools:
  `res://tools/render_forest.gd` (windowed: `--path godot -s res://tools/render_forest.gd --
  --scene=<world scene> --out=<dir> [--solid]`) renders a world's forest with the game's own drawing
  (`--solid` tints the walls' solid cells);
  `res://tools/retree_scenes.gd` (headless) gives the placed tree scenes their trees from the table;
  `res://tools/absorb_wall_trees.gd` (headless, `-- --scene=<world> "--groups=<node>:<mix>,..."`) turns
  placed wall trees into forest paint.
- Prop palettes ([godot/PROPS.md](godot/PROPS.md)): `res://tools/build_prop_palettes.gd` (windowed, with the
  editor closed: `--path godot -s res://tools/build_prop_palettes.gd`) renders every scenery scene at its true
  size, in a block of whole cells, into wide sheets in `godot/asset/MAPS/palettes/`, writes the `cell-props`
  and `details` palettes (`game/world/props/props_cell_tileset.tres`, `props_detail_tileset.tres`) and
  `prop_palettes.json`, and moves painted cells whose tile moved (open the editor to import the images
  after); `res://tools/build_old_prop_palettes.gd` (the same way) builds the free-placement `old-props`
  palette (`props_tileset.tres`: true-size tiles, at least 64 px, 32 for ground details);
  `res://tools/paint_to_nodes.gd` (headless, `-- --scene=<world> [--keep=<prefixes>] [--dry]`) turns painted
  props back into nodes under the world's `Scenery` node (the ground details and water life stay painted);
  `res://tools/absorb_props.gd` (headless,
  `-- --scene=<world> [--scene=...] [--dry]`) turns a world's placed scenery into paint on its prop layers.
  Both headless converters save through `res://tools/lib/scene_save.gd`, which puts back the uids Godot's
  headless save drops.
- `python scripts/art/build-wall-kit.py [style ...] [--palette]` (**numpy**) — the built walls
  ([godot/WALLS.md](godot/WALLS.md)): composes each style's 16 shapes in 4 pattern parities from its three
  Magnific kit pieces (`asset/Originals/walls/<style>/kit/`: a horizontal run, a vertical run, a pillar) into
  `godot/asset/MAPS/walls/sets/<style>.webp` with `walls.json` (frames, foot, collision per shape), and the
  WallLayer palette (`palette.png`, `godot/game/world/walls/wall_tileset.tres`: an auto tile per style, then
  every shape and every exact piece; `--palette` rebuilds only the palette); keep mipmaps on in a new
  sheet's import. `res://tools/convert_stone_walls.gd` (headless, `-- --scene=<world> [--scene=...] [--dry]`)
  turns a world's old stone walls into WallLayer cells.
- `python scripts/art/build-forest-paint-tiles.py` — the forest layer's palette: a tile per mix and per
  tree, into
  `godot/asset/MAPS/forest/forest_paint_tiles.png` and `godot/game/world/forest/forest_tileset.tres`
  ([godot/FORESTS.md](godot/FORESTS.md)).
- `python scripts/art/build-cliff-kit.py [--preview DIR]` (**numpy**) — the cliff kits the elevation's
  storybook wall is cut from: aligns the approved H plateau paintings (`asset/Originals/elevation/cliff-concepts/`)
  to 128 px per cell, cuts the outside ground away, matches their colours and labels every cell, into
  `asset/Originals/elevation/cliff-kit/kit-h2.png`, `kit-h3.png` and their `.json` (art-tool inputs, kept
  out of the Godot project since 2026-10-17 so they do not ship in the game)
  ([godot/ELEVATION.md](godot/ELEVATION.md#storybook-art)).
- `python scripts/art/build-elevation-art-from-painting.py [--preview DIR]` (**numpy**) — elevation art cut from
  the aligned H painting (`asset/Originals/elevation/cliff-kit/kit-h3.png`) instead of generated: the wall
  style `storybook-rock` (wall, stairs coping) in `godot/asset/MAPS/elevation/`; a world picks it with its
  ground layer's metadata `cliff_wall_styles`; `--headless --path godot -s res://tools/build_cliff_shapes_lab.gd
  -- --force` rebuilds the cliff shapes lab that shows it ([godot/ELEVATION.md](godot/ELEVATION.md#storybook-art)).
- `"<Godot console exe>" --path godot -s res://tools/render_stairs_walk.gd -- --out=<dir> [--map=<id>]
  [--feet=<x>,<y>] [--key=move_up] [--then=move_down] [--ms=2600]` (windowed) — records the stairs walk
  in the running game: it puts the slime at `--feet`, holds the key(s) and saves a frame every 80 ms
  of game time with the time, feet, level and whether the walk carries it in the log
  ([ELEVATION.md](godot/ELEVATION.md#stairs-walk)). The default is the playground park's two-level
  flight, walked up and back down.
- `"<Godot console exe>" --headless --path godot -s res://tools/bake_elevation.gd [-- --world=<id>,...]` —
  bakes each world's elevation (drawing, depth map, collision) into
  `godot/game/scenes/worlds/elevation_cache/`, so worlds load without building it (a save the open
  editor holds for a moment is tried again); run (and commit)
  after changing elevation art or before exporting ([godot/ELEVATION.md](godot/ELEVATION.md#baked-cache)).
- `python scripts/art/build-side-wall-art.py [--style storybook-rock] [--source PNG]` (**numpy**) — the
  cliffs' side walls ([godot/ELEVATION.md](godot/ELEVATION.md#side-walls)): a wall style's side strip
  and corner stones (`godot/asset/MAPS/elevation/<style>-side.png`, `-corners.png`) from a Magnific
  sheet of four rounded stones; `--headless --path godot -s res://tools/build_cliff_sides_lab.gd`
  builds the cliff sides lab and `--path godot -s res://tools/render_cliff_sides_lab.gd -- --out=<dir>
  [--collision] [--scene=res://... [--rect=x,y,w,h]]` renders it (or any world, whole or a close-up in
  cells), with each level's collision outline on request. Every world draws side walls: a world made
  later needs no setting or conversion, only a bake of its cache.
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
- `python scripts/art/pack-dungeon-art.py` (**numpy**) — the dungeon kit's art from
  `asset/Originals/dungeon-kit/generated/` (Magnific GPT 2.5, 2026-10-17): the doors (shut, and open
  with the doorway cut see-through), padlock, bolt, winch, shutter, drawbridge (down, up), slabs,
  the seamless spike tile, glow-moss, the big chest, the pickups and the dungeon item icons, at 2 px
  per unit, into `godot/asset/MAPS/objects/dungeon/` and `godot/asset/UI/items/dungeon-items.webp`
  ([godot/DUNGEONS.md](godot/DUNGEONS.md#art)).
- `python scripts/art/pack-prologue-art.py` — the prologue's art from `asset/Originals/prologue/generated/`
  (Magnific GPT 2.5, 2026-10-16): the Wellspring's pool, the barred gate cut into its frame and its
  rising grate, the lever (shut, pulled), Yoi's three poses and Plop's satchel icon; it prints the
  placement numbers the gate scene uses ([godot/PROLOGUE.md](godot/PROLOGUE.md#art)).
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
- `python scripts/art/pack-bomb-lantern-art.py` — packs the Goo Bomb and Lantern art from
  `asset/Originals/abilities/generated/` into `godot/asset/abilities/` (the bomb, its blast, the rubble, the
  Lantern's flame and the deadthorn hedge; the crack and hole overlays the game lays on a cracked wall) and
  their HUD icons into `godot/asset/UI/hud-console/` ([design](design/2026-10-14-bomb-lantern-and-secrets.md)).
  It no longer writes the painted `cracked-wall-2x1.webp`, which no scene used (clean-out wave 1, 2026-10-17).
- `python scripts/art/pack-weaver-bomb-art.py` — the Weaver Hollow's Goo Bomb pieces (2026-10-17) from
  `asset/Originals/weaver-hollow/bomb-pieces/` (Magnific GPT 2.5; prompts in its README) into
  `godot/asset/abilities/goo-bomb/`: `blast-keg-2x1.webp` (intact | burst) and `winch-post-2x1.webp`
  (intact | broken stump), each with the cracked wall's crack decal laid on (only over the keg's wood,
  with a pale rim; only over the post's stone), and `floor-hole.webp` (squashed flat); 2 px per unit. It
  prints each sheet's frame and the sprite offset of its feet for the scenes
  ([godot/BODY_SHAPES.md](godot/BODY_SHAPES.md#the-goo-bomb-2026-10-14)).
- `python scripts/art/pack-web-art.py` — the Weaver Hollow's webs (2026-10-17) from
  `asset/Originals/weaver-hollow/webs/` (Magnific GPT 2.5; prompts in its README) into
  `godot/asset/MAPS/webs/`, 2 px per unit: `floor-webs-6x1.webp` (six flat floor webs, 192 px frames,
  their milky fill thinned) and the WebLayer's `palette.png` (the tile set
  `godot/game/world/webs/web_tileset.tres` is written by hand: an auto tile, then one per web),
  `web-wall-across-2x1.webp` and `web-wall-side-2x1.webp` (intact | cut), `silk-parcel-3x1.webp` (closed |
  torn open | the glint star it paints); it prints the glint's place in its frame for
  `silk_parcel.gd` ([godot/WEBS.md](godot/WEBS.md)).
- `python scripts/art/pack-matron-art.py` (**numpy**) — the Orb-Weaver Matron's cocoon fight (2026-10-17)
  from `asset/Originals/enemies/matron/` (Magnific GPT 2.5; prompts in its README), 2 px per unit:
  `godot/asset/MAPS/enemies/256x416-tile_2x1-matron-cocoon.webp` (whole | torn, hung from the cells'
  top middle), `384x384-tile_4x1-matron.webp` (dazed, dazed, flinch, climbing), Pearl 2
  (`MAPS/props/256x256-pearl-silk.webp`), her thread's spool (`MAPS/props/128x128-matron-spool.webp`)
  and its bag icon (`MAPS/items/64x64-matron-thread.webp`); it prints where the cocoon's eyes and bottom
  are for `game/bosses/matron_cocoon_look.gd` ([godot/specs/matron.md](godot/specs/matron.md) section 8).
  `godot/tools/render_matron.gd` renders the fight's moments in the running game (run windowed).
- `python scripts/art/pack-mine-art.py` (**numpy**) — the Crystal Mine's art (2026-10-17) from
  `asset/Originals/mine/` (Magnific GPT 2.5, seven 2 x 2 sheets; prompts in its README): the Crystal
  Colossus's eight poses (`godot/asset/MAPS/enemies/384x384-tile_8x1-crystal-colossus.webp`, one
  scale, standing on y 376), the mine's props into `godot/asset/MAPS/props/mine/` (the lens and the
  veil as 2 x 1 strips, the rotten timbers also with a smashed frame drawn from them) and the smith
  (`godot/asset/characters/authored/npcs/smith.webp`, four poses with their feet centred)
  ([godot/DUNGEONS.md "The Crystal Mine (built)"](godot/DUNGEONS.md#the-crystal-mine-built)).
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
- `python scripts/characters/pack-bestiary-enemies.py` (**numpy**) — the bestiary's first batch
  (docs/godot/BESTIARY.md "Art"): each enemy's Magnific 2 x 2 pose sheet from
  `asset/Originals/enemies/bestiary/` cut along its empty lines, its four poses drawn at one scale
  into `godot/asset/MAPS/enemies/256x256-tile_4x1-<enemy>.webp` (the Spitcap's three poses into
  `256x256-tile_3x1-spitcap.webp`, its fourth image, the spore seed, into `64x64-spore-seed.webp`).
  Fatty's Lair's: the Pipe Worm's pipe poses hang from the pipe's top (`HUNG`) so the pipe stays put,
  and single pictures (`SINGLES`: the mud glob) go to `64x64-<name>.webp`. Chapter 2's: the brood
  props sheet (`brood-props`: the egg sac's three states and the real cocoon) came with a faint
  background haze, so a sheet in `HAZY` has it cleared and each pose keeps only its main body. The
  worm soldiers (rows 1 to 3) have more poses than four, from `<enemy>-sheet.png`, `-sheet-2.png`,
  ... (`SHEET_POSES` a sheet) into `256x256-tile_<n>x1-<enemy>.webp`, and stand by their weight
  (`MASS_CENTRED`, the prologue worm too) so a weapon thrust out does not push the body back; a
  sheet with no empty row across it is cut by columns first; their arrow and the brawler's hit come
  from the `worm-army-props` sheet (`PROP_SHEETS`). The skeletons (rows 30 to 32) are 2 x 2 sheets
  too (`HAZY`), and their remains (the bone, the two skulls, the bone pile) come from the
  `skeleton-props` sheet (`PROP_SHEETS`). The Caverns' seven and the Watcher Eye (rows 23 to 29,
  33) are 2 x 2 sheets (the Crystal Crawler's poses centred in their cells, `CENTRED`, as it turns
  round its middle), and the `caverns-props` sheet gives the crystal pillar and the brazier (unlit,
  lit) to `godot/asset/MAPS/props/caverns/` and the pickaxe to `64x64-pickaxe.webp`
  (`PROP_SHEETS`). The Gloop Forest's spiders (rows 15 and 16) have twelve poses from three sheets
  each, placed by their body (`BODY_ANCHORED`; a pose hanging lower than the idle one is lifted,
  `BODY_FLOOR_PX`), plus their front scuttle mirrored (`MIRRORED`), into
  `256x256-tile_13x1-<enemy>.webp`; their faint haze is cleared (`FAINT_HAZE`), and the
  `spider-webs` sheet gives the web (`64x64-tile_3x1-spider-web.webp`) and the web cover
  (`128x128-spider-web-cover.webp`). Name enemies to pack only those
  (`... pack-bestiary-enemies.py squint mud-glob`).
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
- `python scripts/art/build-ambient-decoration-sheets.py` and `build-water-life-sheets.py` (**numpy**) —
  the idle-loop sheets (campfire, cauldron, lantern post, banner, birdbath; water life) in `godot/asset/MAPS/`; the scenes' AnimationPlayers
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
  One-shots keep only their loudest event. An option with `"even": true` has its takes levelled to
  its quietest take's loudness (the loudest 100 ms), so none of them stands out when the game picks
  among them.
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

  The game plays staged takes only once Godot has imported them (the editor does when it gets
  focus; with the editor closed, one headless `--import`, never while it is open): until then a run
  started outside the editor cannot load `global.tscn` and every global cue is silent. While a
  round that replaces cues already in `cues.mjs` is open (as round 7 did the Gulp's suck, catch and
  throw), the staged files do not match their entries, so leave `pnpm audio:bake` until the picks
  are applied and registered.
  The owner's own sounds join a round as options of their own
  ([audio spec §12.2](godot/specs/audio.md#122-bringing-your-own-sounds)).

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
