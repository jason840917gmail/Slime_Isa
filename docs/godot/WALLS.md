# Walls: built walls painted cell by cell

> **Status:** first version, 2026-10-13. Three styles: `stone` (the fieldstone wall); since
> 2026-11-01, `hedge` (a clipped boxwood hedge for the West village's gardens, the second auto
> tile in the palette's top row; it joins and blocks exactly as the stone wall does); and since
> 2026-11-17, `picket` (the garden's picket fence, the third auto tile: thinner, it blocks only a
> band at its foot; not yet seen in the editor or played). The stone walls
> of level-1 and the chunk worlds (Gloop Forest E4, F4, F5, Northern Ruins D1, D2, E1, E2, Desert
> A7, A8) are painted on `walls` WallLayers; the old 70 px wall art is gone. The dev worlds still
> place the kept `wall-stone-solid` scenes, which now draw the new pieces.

The old stone walls were 31 separate scenes (eight horizontals, eight verticals, eight corners,
seven T junctions) placed one by one, and they never quite lined up. A **WallLayer** paints a wall
instead: paint the cells a wall stands on and each cell picks its shape from its painted neighbours.
The whole wall comes from three pieces of art per style (a horizontal run, a vertical run, a
pillar), so it joins seamlessly in every direction.

## Using it

1. In a world scene, **Add Node > WallLayer**, name it `walls`, beside the `ground` layer (same
   grid, position (0, 0)). It takes `game/world/walls/wall_tileset.tres` by itself.
2. Select it and paint from the palette (TileMap panel at the bottom). A drag or a line paints a
   run; erase a cell to open a gap (right-click or the eraser). The palette, by row:
   - **row 0, auto** (light frame), a tile per style: each cell takes one of 16 shapes from its
     four painted neighbours (north 1, east 2, south 4, west 8): a lone post, ends, straight runs,
     corners, T junctions and a cross. Straight runs are plain wall; every other shape stands a
     pillar where its arms meet.
   - **a row per style under it, shapes** (green frame; stone, hedge, then picket): the 16 shapes to pick
     yourself, in the order post; ends (north, east, south, west); straights (east-west,
     north-south); corners; T junctions; cross. The little diagram in each tile's corner shows its
     arms (the pillar hides them on the piece). The stones still follow the cell, so a run of
     picked pieces stays seamless.
   (Until 2026-11-17 each style also had four rows of exact pieces, each shape at one fixed stretch
   of the stone pattern. They read as copies of the shapes row, 11 rows for two styles, and one
   cell in all the worlds used one, in level-1-c5: removed, that cell now its shape tile.)
   An auto cell next to a picked one joins it only where the picked shape has an arm toward it,
   so an end piece really ends the wall. Nothing is random: the stone pattern repeats every two
   cells along a run.
3. `paint_opacity` (Inspector, 0.3 by default) shows the palette squares over the walls in the
   editor, as the forest layer does, so you see what you painted where (0 hides them; always hidden
   in the game).

A wall stands at its cell's bottom middle (its foot) and sorts with bodies there. In the game each
shape's footprint is solid (the runs' plan and the pillar's, `walls.json`); the editor draws no
collision.

**Off the grid:** a wall that must sit half a cell over (say, against a gate) goes on a second
WallLayer moved by that offset, named `walls-shifted-<x>-<y>` (Gloop Forest E4 and F5 have one,
32 units east). Walls on different layers do not join.

## The art

The concept was a fieldstone enclosure (`asset/Originals/walls/stone/concepts/fieldstone-a.png`,
the owner's pick among four). The kit was then generated on Magnific (GPT 2.5, transparent
background, the concept as reference; prompts follow [the Magnific guide](../assets/magnific-mcp-guide.md)),
two takes of each piece in `asset/Originals/walls/stone/kit/`:

| Piece | Asked for | Used |
|---|---|---|
| `run-h` | one long straight east-west run, no pillars: mossy cap stones over a front face of chunky fieldstones | `run-h-b` |
| `run-v` | one long straight north-south run seen from above: a column of cap stones | `run-v-a` |
| `pillar` | one short squat square pillar, about as tall as it is wide, a thick flat mossy cap stone | `pillar-c` |

The **hedge** (2026-11-01) has no concept of its own: its kit was generated with the town set's
garden sheet as reference (`asset/Originals/town/concepts/garden-a.png`, whose hedge the owner
picked) beside the interior mushroom furniture sheet, two takes each in
`asset/Originals/walls/hedge/kit/`:

| Piece | Asked for | Used |
|---|---|---|
| `run-h` | one long straight east-west run of the clipped boxwood hedge: a flat leafy top band over a front face of dense small leaves, a strip of soil at its foot, a few tiny white flowers | `run-h-a` |
| `run-v` | the same hedge running north-south seen from above: a long narrow even band of its flat leafy top | `run-v-a` |
| `pillar` | a squat square clipped boxwood block about as tall as it is wide, a softly rounded top | `pillar-a` (`pillar-b` came with a white halo) |

The **picket fence** (2026-11-17) is the town set's garden prop (`picket-fence`, Scenery dock,
Garden) as a painted wall: its kit was generated with that fence cut from the garden sheet as
reference, beside the interior mushroom furniture sheet, two takes each in
`asset/Originals/walls/picket/kit/`:

| Piece | Asked for | Used |
|---|---|---|
| `run-h` | one long straight run of the garden picket fence seen from the front: identical pale honey pickets with pointed tops on two rails, leaf tufts at their feet, no taller end posts | `run-h-a` |
| `run-v` | the same fence running north-south seen from above: a narrow column of the pickets' pointed tops with the two rails beside them | `run-v-a` (pickets overlapping down the column; in `run-v-b` they lie apart like a ladder) |
| `pillar` | one square corner post, a little taller than the pickets and about twice as thick, a pointed pyramid top | `pillar-a` |

A fence is thinner than a wall, so the style carries its own measures (`"measures"` in `STYLES`:
a 58-unit run, a north-south run 24 wide, a post 22 wide, a lighter and narrower cast shadow) and
its own plan: a band 10 units deep at the foot of an east-west run (as the prop's), 16 wide along a
north-south run, 20 x 12 under a post. A style without measures takes the wall's, at the top of the
script.

`scripts/art/build-wall-kit.py [style]` (**numpy**) cuts each run gap to gap and wraps it into a
seamless strip two cells long, then composes the 16 shapes for each of the four cell parities (x and
y even or odd) from half-arms of the strips and the pillar, with a soft cast shadow (light from the
upper left). It writes:

- `godot/asset/MAPS/walls/sets/<style>.webp`: 16 columns (shape) by 4 rows (parity) of 160 x 176 px
  frames (two pixels per unit, drawn at half size; it imports with mipmaps);
- `godot/asset/MAPS/walls/sets/walls.json`: per style, the frame size, the foot inside a frame and
  each shape's collision rectangles;
- `godot/asset/MAPS/walls/sets/palette.png` and `godot/game/world/walls/wall_tileset.tres`: the
  palette (custom data `wall_style`, `wall_shape` -1 for auto). `--palette` rebuilds only these,
  from the built sheets.

## Adding a style

1. Generate a concept, then the three kit pieces with the concept as reference, into
   `asset/Originals/walls/<style>/kit/` (transparent background, the same camera as the stone kit).
2. Add the style to `STYLES` in `scripts/art/build-wall-kit.py` (its three files) and run it; a new
   style is appended to the palette (its auto tile in the next column of row 0, its shapes row below
   the last style's), so painted styles keep their tiles. If a piece's proportions
   differ, give the style its own `"measures"` (wall height, run width, pillar size, shadow, plan),
   as `picket` has; the ones at the top of the script are the stone wall's.
3. Set `mipmaps/generate=true` in the new sheet's `.import` and let the editor import it.

## Placed wall scenes and old worlds

The 31 `game/scenes/objects/wall-stone-solid*.tscn` scenes are kept for the worlds that still place
them (the dev worlds, and the ruin walls `tools/build_region_worlds.gd` scatters into placeholder
regions). Their `Visual` is a `WallPiece` (`game/world/walls/wall_piece.gd`) showing one shape of a
style, with the pattern stretch of the cell it stands in, so pieces placed on the 64 grid join as
painted ones do; their collision is that shape's footprint. Each keeps its old shape: horizontals 10,
the base scene a west end (2), `horizontal-08` an east end (8), verticals 5, `vertical-08` a south end
(1), corners 6, 12, 3, 9 in pairs, junctions 14, 11, 7, 13, 15, 14, 11. They are no longer in the
prop palettes (retired sources).

**Converting a world:** `tools/convert_stone_walls.gd` (headless: `--path godot -s
res://tools/convert_stone_walls.gd -- --scene=<world> [--scene=...] [--dry]`) turns every old stone
wall of a world, painted on a prop layer or placed as a node, into the stone style on the `walls`
WallLayer (made when missing; the world's 64-grid prop layer, if still named `walls`, becomes
`large-props`). Walls off the 64 grid go on a shifted layer per offset, so every wall keeps its
place; the shapes follow the neighbours by themselves. It puts back the uids Godot's headless save
drops. Close or reload the world in the editor afterwards.

## Limits

- One style per cell; two styles meeting join as if they were one wall.
- A chunk cut from a bigger world should keep a one-cell margin of its wall cells past each edge and
  set the layer's `shown_cells` to the chunk's own cells: the margin cells only shape their
  neighbours (they are neither drawn nor solid), so the pieces at the edge still join. Without it a
  wall cut at the edge ends there in a post.
- The region builder still scatters ruin walls as placed scenes, one piece each.

## Files

| Path | What |
|---|---|
| `godot/game/world/walls/wall_layer.gd` | The layer: shapes, pieces, collision |
| `godot/game/world/walls/wall_piece.gd` | One piece as a placed scene's visual |
| `godot/game/world/walls/wall_tileset.tres` | The palette (tool output) |
| `godot/asset/MAPS/walls/sets/` | The style sheets, `walls.json`, `palette.png` (tool output) |
| `scripts/art/build-wall-kit.py` | Builds the sheets, table and palette from the kits |
| `asset/Originals/walls/<style>/` | Concepts and kit renders |
| `godot/tools/convert_stone_walls.gd` | Turns old stone walls into WallLayer cells |
| `godot/tools/lib/scene_save.gd` | Saves a scene from a headless tool without losing uids |
