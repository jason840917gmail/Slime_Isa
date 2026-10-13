# Forests: tree walls painted like a terrain

> **Status:** first version 2026-10-10; on 2026-10-12 every tree became the new top-down art of the
> region sets (below). level-1's wall trees (Forest Border, Gate Pocket, Webwood, Fatty Maze) and
> gloop-forest's border are painted on their forest layers; the generated placeholder region worlds
> and their chunks paint their woods and border walls on a `forest` layer too
> ([WORLD_ATLAS.md](WORLD_ATLAS.md)). Single trees placed as scenes (resource trees, a few wall
> trees, the Matron's arena) keep their nodes and show the new art. Crystal Caverns' four chunks
> have crystal groves (crystal trees and cave mushrooms) painted on their open cavern floor.

A tree wall placed tree by tree is hard to keep in order: hundreds of nodes, and with Editable
Children on, a click in the 2D view picks a tree's picture (`Visual`), so a drag moves the picture
away from its collision. The **forest layer** stores only painted cells; the trees, their sway,
their shade and their collision follow the paint.

## The trees

84 trees in nine region sets, each kind in two variants (a, b) and two sizes (medium, tall),
2 px of art per world unit (drawn at 0.5), seen from a high three-quarter top-down camera:

| Set | Kinds | Where (region theme) | Sways |
|---|---|---|---|
| forest | oak, beech, birch, pine | forest, meadow, the Wilds | yes |
| autumn | maple (red), ginkgo (gold) | the Wilds | yes |
| frost | fir (snow-laden), frost (icy leaves) | frost | yes |
| desert | saguaro, pear (prickly pear), organ (organ pipe) cacti | desert | no |
| volcano | ember (glowing leaves), ash (charred, bare) | volcano | ember only |
| swamp | cypress (hanging moss), mangrove (stilt roots) | swamp | yes |
| crystal | crystal (amethyst canopy), mushroom (glowing cave mushroom) | crystal | no |
| ruins | gnarled (dead, bare), ivy (ivy-wrapped, with fallen stones) | ruins | ivy only |
| village | apple, cherry (blossom) | village | yes |

Names are `<kind>-<variant>-<size>`, e.g. `oak-a-tall`. Widths run from 90 units (a medium saguaro)
to 210 (a tall cypress); a tree is two to four cells tall.

They were generated on Magnific (GPT 2.5, transparent background, the mushroom furniture sheet as
style reference; prompts follow [the Magnific guide](../assets/magnific-mcp-guide.md)): one render
per kind holding a medium and a tall tree, two renders per kind, in
`asset/Originals/trees/<set>/generated/<kind>-<a|b>.png`. `scripts/art/build-tree-sets.py` cuts
them, grades the forest set's leaves toward the style guide's greens (its renders came out
yellow-olive), sizes them, pads them for the sway and packs `godot/asset/MAPS/trees/sets/<set>.webp`
with the shared table `trees.json` (per tree: its atlas, rectangle, foot, whether it sways, and
its cover: a mask of 16-unit blocks where the tree hides the ground). The atlases import with
mipmaps and the tree sprites draw with mipmapped filtering: at half size or less, plain filtering
made the leaf outlines shimmer while the view moved and the canopy swayed.
`game/world/forest/big_trees.gd` reads the table and sets a sprite up as a tree (and its shade).

## Using it

1. In a world scene, **Add Node > ForestLayer**, beside the `ground` layer (same grid, position
   (0, 0)). It takes `game/world/forest/forest_tileset.tres` by itself.
2. Paint with the palette (TileMap panel at the bottom):
   - **top row, mixes** (light frame), by column: 0 mixed (oak, beech, birch, pine), 1 pine,
     2 green (oak, beech), 3 light green (birch, oak), 4 autumn, 5 dead (gnarled), 6 snow (fir,
     frost), 7 oak, 8 beech, 9 birch, 10 dark (beech, pine), 11 desert, 12 volcano, 13 swamp,
     14 crystal, 15 village, 16 ruins (gnarled, ivy), 17 forest medium (the forest kinds, medium
     only: for mazes and tight spots). Each tree picks a tree of its cell's mix.
   - **rows below, single trees:** the cell takes exactly that tree, and always grows it.
   - Erase cells to cut a gap or a path; paint over a cell to change its trees.
3. Inspector: `variation` (another number rerolls every tree's pick, shift, size and flip, and
   which cells of a wood grow one), `shift` (how far a tree may stand from its place, units across
   and down; across goes 1.6 times as far), `size_range`, `paint_opacity` (the squares over the
   trees in the editor; 0 hides them; always hidden in the game).
4. A one-off tree (a landmark, a resource tree) is a placed scene: `game/scenes/objects/tree-*.tscn`.

**Spacing.** The trees are two to three cells wide, so a wood grows about one tree per three
painted cells: one seeded candidate per 2 x 2 block, kept when no tree grows beside it (diagonal
neighbours may), then every painted cell with no tree in or around it gets one, so a one-cell row
still shows a tree on every other cell. Collision does not thin: every painted cell is solid.

**No open spots.** A wall must look as solid as it is, so `_fill_gaps` then checks six points of
every painted cell's solid part (as the collision shapes it) against the grown trees' cover masks,
bottom rows first (a tree hides the ground above its foot); a cell where the ground would still
show grows its own tree. Woods come out denser where thinning left a hole, a thin wall or a
cactus row needs more of them.

**Shade.** Under each tree a soft dark ellipse (`tree_shadow.tres`, `BigTrees.SHADOW_*`) lies on
the ground at z -1 (above the ground layer at -2, below everything standing), a little to the lower
right as the light comes from the upper left. The shades of a wood overlap into a dark floor, so the
ground between trunks reads as the inside of the wood, not a path.

**Absorb trees:** set `absorb_from` (Inspector, group "Absorb trees") to the node holding placed
wall trees (`tree-forest-wall--*` instances), set `absorb_into_mix` to a mix's column, and press
**Absorb trees**: each wall tree's cell is painted with the mix and the tree is removed (Ctrl+Z
undoes it). Its cell is the one whose tree place is nearest the tree's foot; other children are
left alone and listed in the Output. Save, and delete the empty group.
`res://tools/absorb_wall_trees.gd` does the same headless (`-- --scene=<world>
"--groups=<node path>:<mix>,..."`); level-1 and gloop-forest were converted with it.

## How it works

`game/world/forest/forest_layer.gd` (`ForestLayer`, `@tool`, a TileMapLayer):

- Each growing cell grows one Sprite2D standing at (32, 54) in its cell (where the old wall tree
  scenes stood on the grid), shifted, sized and flipped by a random number seeded with the cell and
  `variation`: a region of its set's atlas with its foot as origin. The sprites live in an unowned
  child `Trees` (y-sorted, so trees sort with the player like placed trees) and their shades in
  `Shadows`; the scene saves only the cells.
- **Sway:** `game/world/forest/tree_sway.gdshader` (material `tree_sway_material.tres`, shared so
  the trees batch): each pixel row shifts sideways by an amount that is 0 up to `hinge` texture px
  above the foot and grows toward the crown in one slow, even swing (a ripple travelling up the
  canopy was dropped: big canopies wobbled like jelly), the phase a smooth function of where the
  tree stands (real time, presentation only). Never a hash of the position: at whole zooms the
  camera's pixel snapping moves the shader's origin by a fraction of a pixel as the view moves,
  and a hash of it jumped every tree to a new phase, so the sway reset whenever the screen moved. Tune `amplitude`, `hinge`, `reach` and `speed` on the material in the
  Inspector; it sways in the editor too. Rigid trees get no material.
- **Collision (game only):** a StaticBody2D `Collision` (layer 1, world) with one rectangle per run
  of cells along a row: from the trunks' tops (44 units above the foot, as the old trunk boxes) to
  their feet, reaching the cell's top or bottom where the next row is painted too, so a painted area
  is solid with no gaps between rows.
- The tile's custom data `forest_trees` holds its trees' names and `forest_mix` its name;
  `scripts/art/build-forest-paint-tiles.py` writes the palette
  (`godot/asset/MAPS/forest/forest_paint_tiles.png`) and the tile set from the list of mixes in it.
  The mixes keep their columns: worlds are painted with them and the region world builder paints
  them by column (`tools/region_worlds/region_canvas.gd`, `_mix_at`).

**Placed tree scenes** (`tree-forest-wall--*`, `tree-world-solid--*`): `res://tools/retree_scenes.gd`
gave each its tree from the table (its list maps every scene to a tree: green trees to oak, beech
and birch, pines to pines, the snow pine to a fir, autumn and red trees to maples, golden trees to
ginkgos, bare ancient trees to gnarled trees...): the `Visual` is that region at scale 0.5 on its
foot with the sway material, a `Shadow` sprite lies under it, and the old frame animations are gone
(a resource tree's idle and on-hit clips with them). Worlds that set a tree instance's `Visual`
scale keep it as a factor of 0.5; the old per-instance offsets were dropped.

**Seeing it:** `res://tools/render_forest.gd` renders a world's forest with the game's own drawing
and a slime for scale (windowed: `--path godot -s res://tools/render_forest.gd --
--scene=res://game/scenes/worlds/chunks/gloop-forest-e5.tscn --out=<dir>`, optional
`--rect=x,y,w,h` in cells; `--solid` tints the painted cells' solid parts, to spot open ground
in a wall): the view at 1x, its middle at 2x and four moments of the sway.

## Adding a set or a kind

1. Generate the kind on Magnific with the style block, "two <kind> trees of the same kind side by
   side ... a medium one on the left, a tall one about one and a half times taller ... high
   three-quarter top-down camera looking down at about 60 degrees ... isolated on a transparent
   background", 3:2 at 2k, count 2; save them as `asset/Originals/trees/<set>/generated/<kind>-a.png`
   and `-b.png`.
2. Add the kind to `SETS` in `scripts/art/build-tree-sets.py` (its widths, whether it sways, a leaf
   grade if needed) and run it for the set; then add or extend a mix in
   `scripts/art/build-forest-paint-tiles.py` (append new mixes: columns are fixed) and run it.
3. A new region theme: map it to its mix in `region_canvas.gd` `_mix_at`.

## Limits

- At most one tree per cell on the 64-unit grid, thinned from there.
- Chunks keep forest cells a little past their edges (`FOREST_MARGIN` in
  `tools/split_region_chunks.gd`), and each chunk thins its own cells, so a tree near a chunk's
  edge may stand elsewhere, or not at all, on the other side of the screen transition.
- Trees on raised ground (the elevation) stand at level 0's collision layer, as placed trees do.

## Files

| Path | What |
|---|---|
| `godot/game/world/forest/forest_layer.gd` | The layer: trees, spacing, shade, collision, Absorb trees |
| `godot/game/world/forest/big_trees.gd` | The trees' table: sets a sprite up as a tree, makes its shade |
| `godot/game/world/forest/forest_tileset.tres` | The palette tile set (tool output) |
| `godot/game/world/forest/tree_sway.gdshader`, `tree_sway_material.tres` | The canopy sway |
| `godot/game/world/forest/tree_shadow.tres` | The shade's soft ellipse |
| `godot/asset/MAPS/forest/forest_paint_tiles.png` | The palette art (tool output) |
| `godot/asset/MAPS/trees/sets/<set>.webp`, `trees.json` | The trees' atlases and table (tool output) |
| `asset/Originals/trees/<set>/generated/` | The trees' Magnific renders |
| `scripts/art/build-tree-sets.py` | Builds the atlases and table from the renders |
| `scripts/art/build-forest-paint-tiles.py` | Builds the palette from the table and its mixes |
| `godot/tools/retree_scenes.gd` | Gives the placed tree scenes their trees |
| `godot/tools/absorb_wall_trees.gd` | Turns placed wall trees into forest paint, headless |
| `godot/tools/render_forest.gd` | Renders a world's forest for checking the art |
