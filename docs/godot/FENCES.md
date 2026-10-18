# Paintable fences

> **Status:** seven styles in **Fence Park** (`?map=fence-park`, `-- --map=fence-park`). Paint every
> fence on one `fences` layer, on ordinary ground or any elevation. The picture palette shows the
> material and connection direction. Fences add their own shadows and level-matched collision;
> elevation rims remain independent.

## The rule

There is one `fences` TileMapLayer and one renderer everywhere. A fence tile chooses a material and
one of eight directions, connects to neighboring painted cells, and brings its own collision and
ground shadow. Fences never paint or change elevation rims. Placement is explicit in the scene; the
runtime does not infer fences from cliff edges.

## What you see

A fence is built at the cells painted on the `fences` layer. A post stands at each painted cell
(its foot at the cell's centre); rails span to the neighbours it links to. The eight arrow pictures
show which neighbour a tile selects; the all-neighbour picture joins every all-neighbour neighbour.
Cells on different elevation levels never join. Each of the seven columns is one fixed style: wood,
snow-capped wood, stone, sandstone, twig, picket and crystal (the ground never chooses it).

| Direction | What shows |
|---|---|
| North, east, south or west | rails join the selected neighboring cell along that direction |
| North-east, south-east, south-west or north-west | rails join the diagonal neighbor; posts stay upright and the rail face is shaded with the direction of the light |

Posts and rails Y-sort with bodies and write a silhouette into the elevation depth map. Shadows fall
to the lower right, with a contact shadow at each post. A fence in a hole darkens with depth like
the cliffs ([ELEVATION.md](ELEVATION.md)).

## Authoring fences

Each world has one `fences` TileMapLayer beside `ground` (and `elevation`, when it has one), using
`game/world/fences/fence_tileset.tres` and `game/world/fences/fence_layer.gd`. Paint one tile in
every cell where a fence post should stand. Choose its style by the column and its connection by the
row. The renderer uses that paint for art, soft shadows, depth and collision. Fences never create or
reshape cliff rims, and leave elevation painting and caches alone.

The palette (`scripts/art/build-fence-paint-tiles.py` writes it and the TileSet) has one column per
style. Its top row is the all-neighbour tile; the eight rows below are the north, north-east, east,
south-east, south, south-west, west and north-west arrows.

**When two cells link** (`Fences._can_link`): never across levels; two all-neighbour tiles always;
otherwise only where an arrow points, the first cell's arrow at the second or the second's arrow
back at the first. An arrow tile therefore refuses every neighbour it does not point to and that
does not point at it, all-neighbour tiles included. Paint arrows where two runs pass one cell apart
(two all-neighbour runs one row apart would join across); a run of east arrows joins only along its
row. A diagonal link is skipped when a two-link cardinal route already joins the same cells, so
corners do not get a doubled brace; it stays where direction or level blocks that route.

**Mixed styles:** a link's rails take the style of the cell whose arrow asks for it; between two
all-neighbour tiles (or two arrows pointing at each other) the north-west cell's style (the first
in reading order, north to south then west to east). Each post keeps its own cell's style.

**A lone tile** (no links) is a short fence of two posts: its own at the cell's centre and a second
half a cell the way its arrow points (on the cell's edge; a diagonal's on its corner), the rail
between them. A lone all-neighbour tile has no arrow and points east (`Fences.lone_stub`).

**Level:** a fence takes the level of its cell on the `elevation` layer (level 0 in a flat world). A
fence on a stairs or ramp cell takes the level that cell is built at, the ground the flight leads
down to (`Elevation.painted_levels`); avoid painting fences on stairs.

**Collision** is thin and sits at the rails' feet, so a body stops where the art says
(`game-constants.json` `fences`, read once per build): every link is one band from post foot to post
foot, from `bandAbove` (10) to `bandBelow` (2) units above the posts' foot line (8 thick; a 45° link
the same band, rotated); a north-south link is `sideHalfWidth` (7) each side of the post column
instead; every post is a 14 × 8 rect at the band's height; a lone tile is its two posts and the
band between them. From the north a body's feet stop 10 above the posts' feet, its lower part hidden behind the
rails; from the south its head stops 2 above them, overlapping the feet a little (the Zelda overlap).
Run ends are open; corners are closed by the posts. Each level's collision is a static body on its
`level <n>` physics layer. `Fences.blocks_rect` and `blocks_sweep` test the same boxes, so
`Elevation.body_fits` (landings, hop steps) checks a body's whole rect and `ledge_below` the whole
way from its side to its ledge probe: a hop or a drop never passes a band thinner than the body.

In the editor, a paint stroke rebuilds only the fences (on the Elevation's grid and depth map when
the world has one); hide the `fences` layer (eye icon) to see the generated fence without its paint
figures. The game hides the paint layer.

World scenes now use this same `fences` layer for every painted fence. There is no separate ground
layer or cliff-edge mode.

## How it works

`Elevation.rebuild()` calls `Fences.mount(ground, self, grid, occlusion, collide)`
(`game/world/fences/fences.gd`); a flat world (no `elevation` layer) calls the same mount from
`Elevation.mount` with no elevation, and the fences go beside the ground layer on a level-0 grid of
the map's size. Only the node's parent, the cell levels and the depth map differ; paint, links, art,
shadows and collision all use one path. Of the elevation the fences use only `ElevationGrid` (a
cell's level), `ElevationOcclusion` (the depth map), the mesh helper and the shader includes.

- **Connections** (`connected_links`): each linked neighbouring pair (above) is drawn once.
- **Pieces and depth.** Posts and rails are generated `MeshInstance2D` nodes under a Y-sorted
  `FencePieces` holder beside the ground layer. Their material comes from the style kit and
  `fence.gdshader`. Each opaque piece writes its level and height into the depth map
  (`fence_depth.gdshader`, `ElevationOcclusion.add_occluder`; a rebuild of the fences alone takes
  its old silhouettes out again), so fences sort with bodies and terrain.
- **Shadows and collision.** Posts cast contact and soft shadows; the collision boxes are above.

## Making the art

A style is one Magnific image (`gpt-2-mini`, `transparentBackground: true`, 21:9,
[Magnific guide](../assets/magnific-mcp-guide.md)), the style block first, then: "A game sprite of
one long straight rustic wooden rail fence seen from the front, running horizontally across the whole
width of the image: five thick round wooden posts evenly spaced, each with a rounded weathered top
that shows a little of its top face, joined by two chunky horizontal split-log rails (an upper rail
and a lower rail) that run behind the posts from the left edge of the image to the right edge. The
posts stand perfectly upright, the rails are perfectly straight and horizontal, the bottoms of all
posts sit on one straight baseline. Same wood, colours and painting as the wooden fence in the
reference sheet. Isolated on a transparent background, no ground, no grass, no ground shadow plate,
no scenery." References: the decorations sheet with the game's wooden fences
(`godot/asset/MAPS/decorations/128x128-tile_8x3.webp`) and the mushroom furniture style sheet.

The other styles were generated with the wood front view (`wood-front-b.png`) as their first
reference, "exactly the same layout", and the material in the prompt: snow caps and icicles; square
stone pillars with a lower dry-stone wall between them (the cliff sample as a second reference);
rounded sandstone pillars with an adobe-brick wall; gnarled branch posts with vine-wrapped branch
rails; tall pointed posts with a row of shorter pickets; crystal clusters on rock bases with two taut
ropes. Every source is in `asset/Originals/fences/` (`<style>-front-a.png` is used, `-b` is
the spare).

`python scripts/art/build-fence-art.py [style ...] [--preview DIR]` (numpy, Pillow) finds the posts
(the most opaque columns, `post_share` of the most opaque one) and the rails (rows opaque between the
posts), scales the post to `post_height` (40 units for wood) at 2 px per unit and writes the kit into
`godot/asset/MAPS/fences/`: `<style>-posts.png` (every post, feet on one row, the rails
behind them removed, moss kept), `<style>-rails.png` (the rails between posts joined into a strip that
repeats sideways), `<style>-rails-side.png` (the upper rail turned a quarter left: seen from above,
lit on its left; for a wall its whole band, for pickets their tips, squeezed to `side_width`) and
`<style>.json` (the measures). A new style is a new entry in its `STYLES` and a new palette column:
add it at the end of `STYLES` in `scripts/art/build-fence-paint-tiles.py` and run it (it writes the
palette picture and `fence_tileset.tres`; do not edit the TileSet by hand, and do not insert a
column before others: painted scenes store the column).

The wood set used 400 credits (two front views, of which `wood-front-b.png` is used, and two rails
seen from above, unused: the turned front rail matches the front better); the other six styles 1,200
(two front views each).

## Styles

| Palette style | Look | Post height, spacing |
|---|---|---|
| `wood` | round posts, two split-log rails, moss at the feet | 40, 64 |
| `snow` | the same with snow caps on posts and rails, icicles, drifts | 40, 64 |
| `stone` | square stone pillars, a low dry-stone wall between them | 34, 80 |
| `sandstone` | rounded sandstone pillars, a low adobe-brick wall | 36, 80 |
| `twig` | gnarled branch posts, vine-wrapped branch rails, tiny mushrooms | 40, 64 |
| `picket` | tall pointed posts, a row of shorter pickets, fallen leaves | 42, 64 |
| `crystal` | crystal clusters on rock bases, two taut ropes | 44, 64 |

Walls fit the same kit: their pillars are the posts, the wall between them the rails, the wall seen
from above its side rail. All seven await the owner's verdict.

## Test world

`python scripts/maps/build-fence-park.py` writes `godot/game/scenes/worlds/fence-park.tscn` (a dev
world, left out of the release export): connected fences on a level-1 square (with an east gap and
stairs down its south and west sides; the player spawns on it), a level-2 diamond, a level-1 octagon
with a level-2 octagon on top, a square and an octagon hole, a level-2 square fenced on its south
side only, a diamond fenced on its east half and a level-3 block, all wood. Below them are two rows
of plots on different grounds, each with its own hill (octagons, diamonds, squares, a terrace, a
hole) and explicitly painted materials, including styles that contrast with their ground.
`res://tools/render_fence_park.gd` renders it with the game's own drawing (windowed:
`--path godot -s res://tools/render_fence_park.gd -- --out=<dir>`), test slimes placed in front of and
behind the painted fences, and prints where a body with the player's collision stops at each kind of
fence and whether it can drop or hop there. Its connected-fence sample includes eight isolated directions on
ordinary ground, a connected twig run, and an all-neighbor wood run on a raised platform whose
other edges are not fenced. `asset/Originals/fences/wood-review.png` (the wood set)
and `styles-review.jpg` (every style, and bodies behind fences) are its output. `godot/tests/test_fences.gd` checks the same in the game.

## Limits and next steps

- Gates are not built into fence tiles; leave an opening in the painted run for a gate.
- Walls on a 45° run show only their front face, sheared, so they look thinner than on a straight
  run (no top face is drawn along the diagonal).
- The cut-away part of a body behind a fence follows the depth map's 2-unit grid, so its edge along
  a rail can step by a pixel or two where the sort could not put the body first.
- Enemies collide with fences on their level; navigation does not path around them yet.
- A fence's depth silhouette counts as ground of its level for the cast shadows (fences do not cast
  their own long shadows on lower ground yet).

## Files

| Path | What |
|---|---|
| `godot/game/world/fences/fences.gd` | Links, pieces, shadows, depth silhouettes, collision, `blocks_point` / `blocks_rect` / `blocks_sweep` (`@tool`) |
| `godot/game/world/fences/fence.gdshader`, `fence_depth.gdshader` | The fence art; its silhouette in the depth map |
| `godot/game/world/fences/fence_layer.gd`, `fence_tileset.tres`; `godot/asset/MAPS/fences/fence_paint_tiles.png` | The painted layer and its tiles (`scripts/art/build-fence-paint-tiles.py`) |
| `godot/asset/MAPS/fences/` | Kits (`scripts/art/build-fence-art.py`) |
| `asset/Originals/fences/` | Generated sources and the review sheet |
| `scripts/maps/build-fence-park.py`, `godot/game/scenes/worlds/fence-park.tscn` | The Fence Park |
| `godot/tools/render_fence_park.gd` | Renders and probes the Fence Park |
| `godot/tests/test_fences.gd` | Mounting (Fence Park, C4, a flat world), links, the bands (straight, diagonal, a lone tile), movement, hops and drops |
