# Cliffs: handoff (2026-10-09, updated 2026-10-10)

What one long session tried for cliffs and raised ground, what worked, what failed and why, the
assets and labs it left behind, and where the owner stands. Read this before touching cliffs again.
The technical reference for each approach is [CLIFFS.md](CLIFFS.md); the older automatic system is
[ELEVATION.md](ELEVATION.md).

**Nothing from this session is committed.** `git status` shows every file below as new (`??`),
except `godot/game/world/world_ground.gd`. Do not commit unless the owner asks.

## 1. The owner's goals and rules

- Zelda-like top-down (three-quarter view, camera looking north) with **cliffs, raised plateaus,
  dips and several levels**, and **control over their shapes**.
- **Keep the hand-painted storybook style** (docs/assets/visual-style-guide.md). Pixel art was
  considered and rejected on 2026-10-09.
- Grid: one cell = **64 units**, art at **128 px per cell** (layers at scale 0.5).
- Borders and walls must be **irregular, never flat**: an irregularity never reaches more than 1 cell
  outside the cliff, nor runs more than 2 cells along a side. A border must reach the very edge of
  its cell (no short gap next to the wall).
- Runtime art lives in **`godot/asset/MAPS/`**, never next to code.
- Tile sheets must be readable by hand: one cell per tile, laid out like a classic 3 x 3 sheet.
- The ground belongs in the art, with several plain and decorated variants so it does not repeat.
  **Low ground darker than raised tops**, so the eye reads height.
- **Concept art is approved by the owner before anything is cut from it.**
- **Never run tests** (pnpm test:godot, filtered tests, verify_scenes) unless asked; `--check-only`
  compiles are fine.

## 2. Where things stand

- **Latest (2026-10-10): painted elevation** (section 4.6): the elevation system's cliffs (any shape
  painted on an `elevation` layer) with art cut from the approved H painting. It replaced the shape
  painter in `cliff-shapes-lab.tscn` (L, T, plus, U both ways, joined rectangles, a 1-2-3 terrace, an
  octagon, a hole, walls of 1-3 courses, flush-front terrace); awaiting the owner's verdict.
- **Kept:** the **cliff builder** (`CliffBuilder`, section 4.4) for single rectangles and octagons
  stretched from one painting. The **cliff shape** node (section 4.5) was rejected ("still not
  good": seams where walls end and along side borders) and is used by no scene now.
- **Terrace concepts** `terrace-a.png` / `terrace-b.png` (asset/Originals/elevation/cliff-concepts/)
  generated for the owner's approval: an upper plateau whose wall stands on the lower top. Not cut
  yet; once approved, add it as a kit so level steps come from a real example.
- Next: the owner's verdict on painted elevation; then low ground darker than tops for elevation
  worlds, a `storybook-rock` tile on the `cliffs` paint layer, more stone variety in the wall (it
  repeats every two stones); delete the unused experiments when the owner agrees (keep
  `cliff-lab.tscn`: it holds the owner's layer).
## 3. What we learned

1. **AI paintings are never on the grid.** One stone course measured 90-100 px across generations
   (113 px was an early wrong guess); edges sit at different places in every cell, and light and
   grass tone differ between paintings. **Any cell-by-cell mix of pieces from different paintings
   (or different spots of one painting) shows seams.** Aligning helps (section 4.5) but does not
   remove them, least of all on diagonals.
2. **Stretching one painting works.** Keeping its corners and repeating runs of its straight middle,
   with a short crossfade, looks like the painting at any size. Its limit: the shape is the
   painting's shape.
3. **Measurement, not guesswork.** A per-cell check (does every cell of a shape have an exact 3 x 3
   example in the paintings?) found ~99% exact matches on the shapes that still looked wrong: the
   seams came from the art, not the matching algorithm.
4. **Godot terrains** (TileSet terrain sets):
   - Sides and corners are shared between neighbouring tiles; **the terrain painted last owns a
     shared side**, so paint order changes the result. Tiles need alternatives for each answer.
   - A 45 degree chamfer and a square corner have the same neighbours: diagonals can only be placed
     by hand.
   - "Match Corners and Sides" needs up to 47 tile combinations per terrain.
   - Empty cells match no tile: paint the low ground too.
5. **Cutting generated islands/holes into border tiles makes flat, short borders** (the cutter
   assumes a straight rim). The owner rejected this twice.
6. **Why the playground's elevation always works** (2026-10-10): it never copies a picture cell by
   cell. It traces the painted outline and lays continuous strips along it: a wall texture that
   repeats sideways and down from the wall's own coordinates, corner stones where a wall ends, and
   lip, rim and foot strips whose art runs on around every corner. Nothing has to meet a neighbour
   from another spot of a painting, so nothing can misalign. Art from a painting works in it once it
   is cut into those strips.
7. **Pixel art and asset stores:** an Aseprite MCP and PixelLab (which makes grid tilesets) exist,
   but break the style. A web search for painted cliff packs found nothing that matches; the closest
   is *2D Hand Painted - Grassland Tileset* by Daniel Thomas (128 px, semi-realistic, no outlines,
   no diagonals). The schwarnhild hand-drawn pack's licence bans AI-made derivatives.

## 4. The attempts, in order

### 4.1 Automatic elevation (before this session)

Painted levels -3..3 on an `elevation` layer; a script builds walls, lips, feet, stairs, ledge drops,
walking behind and collision ([ELEVATION.md](ELEVATION.md)). **Works, but the owner rejected it: no
control over the art.** Still in the code; the playground's Elevation Park uses it, and level-1 now
has an `elevation` layer the owner painted.

### 4.2 Hand-paintable tile sheet with Godot terrains (`cliff-lab`)

Three rounds, all rejected:
- **v1:** tiles larger than a cell (2 x 2 tops, 1 x 3 walls) cut from generated islands, holes, lips,
  feet and decorations. Owner: borders flat, sheet a mess.
- **v2:** a classic one-cell-per-tile sheet with the ground inside, 8 plain + 8 decorated ground
  tiles, border variants, 45 degree pieces, labelled guide picture (`docs/godot/cliffs-sheet-guide.png`);
  terrains Top / Rock wall top / Rock wall / Wall foot with paint-order alternatives. Owner: "not
  good", borders short and flat.
- **v3:** the sheet cut from the approved concept paintings (section 7). Seams; diagonals read as
  steps.
- **The owner's own try:** a `My cliffs` layer in `cliff-lab.tscn` using his
  `godot/asset/MAPS/cliffs/256x256-8x8-clif.png` (plateau B cut into 8 x 8 cells of 256 px) with an
  embedded TileSet. 24 tiles had no centre terrain and the outside was marked "wall"; I fixed its
  terrain data (terrains: `ground bot 0`, `wall`, `groud top 4`). It now paints that octagon right,
  but only that shape: the painting is not on the grid. The owner then said "too hard".

### 4.3 Asset search and pixel-art tools

See lesson 6. Outcome: keep our own painted art.

### 4.4 Cliff builder: stretch one painting (CHOSEN)

`godot/game/world/cliffs/cliff_builder.gd` (`class_name CliffBuilder`, `@tool`) +
`cliff_builder.gdshader`. Add Node > CliffBuilder; Inspector: `kind` (octagon, rectangle 1 / 2 / 3
levels, octagon dip), `width_cells`, `height_cells`, `variation`, `behind_depth`.
- Each kit's head / middle / tail slices are in `scripts/art/build-cliff-kit.py` (`columns`, `rows`,
  `tails`); the empty margin is trimmed to one cell. A "rectangle" is an H painting stretched
  (left leg, the leg's middle, right leg).
- Collision: walls solid + a 12-unit rim strip inside the top's open sides (physics layer 1, world;
  the player's mask includes it), shared with `cliff_piece.gd` (`CliffPiece.rects_for`). The north
  strip sits `behind_depth` (32) in and an overlay above bodies redraws that band, so bodies go
  behind the cliff.
- Levels: stack builders (a smaller one on a bigger one's top, later in the tree).
- Limits: minimum size is the painting's corners (about 10 x 13 cells for rectangles); no shapes
  other than the painting's; the dip has no collision; no stairs; the 3-level painting's bottom
  course is thin and half hidden by ferns.
- `cliff_piece.gd` places a painting unstretched (same collision).

### 4.5 Paint-the-shape builder (`cliff-kit-lab`)

`godot/game/world/cliffs/cliff_shape.gd` + `cliff_shape.gdshader`. Paint cells on its child
`paint` TileMapLayer with `cliff_paint_tileset.tres` (squares numbered 1-8): **the number is the
ground's height in stone courses** (a step from 6 to 4 gets a 2-course wall; `courses_per_level`
scales it).
- Each level's cells get labels (T top, W / M / V wall courses, F foot, L low); every cell shows a
  kit cell with the same 3 x 3 labels, preferring the one continuing its neighbour; walls take
  pieces only from the painting of their height (h1, h2, h3+, a middle course repeats for taller
  walls); crossfade where cells do not continue each other.
- Collision per level and walking behind, as in 4.4.
- **Results after aligning the paintings:** squares, rectangles, L, U, notches and wall heights
  1 / 2 / 3 / 5 looked clean; terraces crowd their rims when levels are one row apart; **octagons
  and diamonds keep visible jumps** (only one painting has diagonals, drawn freely). Owner: "not
  good enough" (for the whole set, diagonals included).
- Known gaps: one row between a wall's foot and the next top loses that top's ferns; very sharp
  diamond points come out thin.
- An earlier stretch-only version of the octagon and dip lives in the same lab (the original
  "plateau 20 x 16" the owner liked).

### 4.6 Painted elevation (`cliff-shapes-lab`, 2026-10-10)

The elevation system ([ELEVATION.md](ELEVATION.md)) with a new wall style and fringe cut from the
approved H painting, no generation: `scripts/art/build-elevation-art-from-painting.py` makes
`storybook-rock-wall.png` (two stone courses, periodic: the clean middle course of `kit-h3.png`, two
spans of one joint each, the second row mirrored and shifted), `-wall-end-left/right.png` (the
course's end stones), `-stairs-coping.png`, and `storybook-grass-lip.png` / `-foot.png` (the fern
bands of `kit-h2.png` at 0.75 scale, the stone between hanging plants cut away). `elevation.gd` reads
two new ground layer metadata so one world can use them without changing the others:
`cliff_wall_styles` {"highland": "storybook-rock"} and `cliff_fringe` {"highland": "storybook-grass"}.
`elevation_rims.gd` now mitres the over-the-top side of concave corners (the old single triangle
smeared one column of art into stripes, invisible with thin grass but plain with ferns).
Rendered in the lab: every shape joins without a seam; levels are one course each (−3 … 3).

## 5. Labs (playgrounds) and their builder tools

All four are dev worlds: in `game/scenes/scene_index.json` and excluded from the release "Web"
export preset. **Each is rebuilt by its tool, which overwrites the whole scene**: the owner lost an
8-level cliff he had painted in `cliff-kit-lab` that way. Owners' work goes in other scenes.

| Scene (world id) | Built by | Shows | Status |
|---|---|---|---|
| `cliff-shapes-lab.tscn` | `godot/tools/build_cliff_shapes_lab.gd` (refuses to overwrite without `-- --force`) | painted elevation in the storybook art: L, T, plus, U both ways, joined rectangles, terrace 1-2-3, octagon, hole, walls 1 / 2 / 3, flush front | **latest**, awaiting verdict |
| `cliff-pieces-lab.tscn` | `godot/tools/build_cliff_pieces_lab.gd` | CliffBuilder: octagons 20 x 16 and 30 x 14, rectangles 1 / 2 / 3 levels, dip, a 2-level stack | **current** |
| `cliff-kit-lab.tscn` | `godot/tools/build_cliff_kit_lab.gd` | stretch builder (old octagon/dip), shape builder: shapes row, octagons + diamond, level 1/2/3/5 walls, terrace 2-4-6 | experiment |
| `cliff-lab.tscn` | `godot/tools/build_cliff_lab.gd` | the tile sheet painted with terrains + **the owner's `My cliffs` layer** | experiment; **do not rebuild** (it would delete the owner's layer) |

Run a tool with the console exe, for example:
`"C:/Users/User/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" --headless --path godot -s res://tools/build_cliff_pieces_lab.gd`,
then `scene_open(path, force_reload=true)` in the editor.

## 6. Other changes made on the way (in use, in every world)

- **`game/world/world_ground.gd`** on the `ground` layer of all 22 world scenes: in the editor it
  mounts what the game mounts (128 px ground, water, terrain edges, ground shade), so worlds look
  like the game while editing. New worlds need it (CONVENTIONS.md).
- **Runtime art moved** from `game/world/elevation/art`, `elevation/fences/art`,
  `terrain_edges/art` to `godot/asset/MAPS/elevation`, `/fences`, `/terrain-edges` (code, tile
  sets, tools, docs updated).
- **128 px ground** (`game/world/ground_surface.gd` + shader, mounted first by
  `WorldService.register_world`): grass (HighlandGreen), sand and snow have
  `godot/asset/MAPS/grounds/128x128-tile_19x19_<sheet>.webp` (Magnific 2x upscale, colour-matched to
  the 64 px sheets); terrain edges sample them too. The other six grounds are still 64 px
  ([TERRAIN_LAB.md](TERRAIN_LAB.md#ground-at-128-px)).
- **Light by height** (`game/world/ground_shade.gd` + shader): warm multiply on ground that is not a
  raised top. **It only reads layers using `cliff_tileset.tres`, so it does nothing with
  CliffBuilder yet** (gap to fix).

## 7. Assets

**Concept paintings** (`asset/Originals/elevation/cliff-concepts/`, Magnific GPT 2.5, 2048 px):

| File | Status | Notes |
|---|---|---|
| `octagon-plateau-b.png` | approved | 2-course wall, 45 degree sides; course ~100 px |
| `octagon-dip-a.png` | approved | wall on the far (north) side; not aligned, no labels, no collision |
| `h-plateau-a.png` | approved | H shape: square outer corners, rim inner corners (north notch), wall inner corners (south notch); 2 courses, ~95 px |
| `h-plateau-level1.png` | approved | same H, 1 course, ~90 px |
| `h-plateau-level3.png` | approved | same H, 3 courses (~95 px, bottom course thin); its notch's back wall came out 2 courses |
| `octagon-plateau-a.png`, `octagon-dip-b.png`, `h-plateau-b.png` | not chosen | |

Their alignment (scale so one course = one cell, shift to cell lines, colours matched to h2,
labels from measured outlines, busy interior cells dropped) is in `KITS` in
`scripts/art/build-cliff-kit.py`, which writes `godot/asset/MAPS/cliffs/kit-<name>.png/.json`
(plateau 22, h1 25, h2 24, h3 24 cells; dip 18, unaligned).

**Tile-sheet sources** (`asset/Originals/elevation/cliff-tiles/`): `top-island-a..d`,
`top-hole-a..d` (c/d are the chunky ones), `lip-a/b`, `foot-a/b`, `wall-features-a/b` (4 x 2
grids), `foot-rubble-a`, `ground-decor-a` (4 x 3). Used by `scripts/art/build-cliff-tiles.py`
-> `godot/asset/MAPS/cliffs/meadow-rock-highland.png/.json` (+ `cliff_tileset.tres`). Unused now.

**Other runtime files in `godot/asset/MAPS/cliffs/`:** `256x256-8x8-clif.png` (the owner's),
`cliff_paint_tiles.png` (shape-builder paint squares).

**Credits:** about 3,200 Magnific credits this session (tile-sheet sources ~1,600, ground upscale
180, octagon concepts 720, H concepts 360, height versions 360). GPT 2.5: 1k = 100, 2k = 180.

## 8. Practical gotchas

- **Magnific:** `gpt-2-mini`, `transparentBackground: true` always; full-frame paintings come back
  with alpha ~0.95: force them opaque. References must be uploaded creations (re-upload the local
  files; the approved concepts are good style references).
- **Editor imports:** after rewriting a PNG, `touch` it, `filesystem_manage reimport` + `scan`, and
  check `.godot/imported/<file>-*.md5` `source_md5` against the file's md5 before trusting a render;
  renders made earlier use the old picture.
- **Seeing results:** `editor_screenshot` often times out on these scenes. Render instead with a
  small SceneTree script that instances the world in a SubViewport, calls
  `Services.world().register_world(world)` and saves `viewport.get_texture().get_image()`; run it with
  the console exe **without** `--headless` (`--path godot -s <script> -- --out=<dir>`). The same script
  can move a `CharacterBody2D` (30 x 26 rect, mask 1) to probe collision. The session's render and
  probe scripts lived in a temp folder and are gone.
- **Windows shell:** inline Python heredocs containing apostrophes break in Git Bash: write patch
  scripts to a file and run them.
- **Open editor:** it keeps its own copy of open scenes; after a tool rewrites a scene,
  `scene_open(path, force_reload=true)` (it only reloads the current scene).
