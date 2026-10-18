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

A fence is built at the cells painted on the `fences` layer. A post stands at each painted cell;
rails span to compatible neighboring cells. The eight arrow pictures show which neighbor a tile
selects. The first connection picture joins every neighboring painted cell. Cells on different
elevation levels never join. The first material picture lets the ground choose a matching style;
the other pictures show wood, snow-capped wood, stone, sandstone, twig, picket and crystal.

| Direction | What shows |
|---|---|
| North, east, south or west | rails join the selected neighboring cell along that direction |
| North-east, south-east, south-west or north-west | rails join the diagonal neighbor; posts stay upright and the rail face is shaded with the direction of the light |

Posts and rails Y-sort with bodies and write a silhouette into the elevation depth map. Shadows fall
to the lower right, with a contact shadow at each post. A fence in a hole darkens with depth like
the cliffs ([ELEVATION.md](ELEVATION.md)).

## Authoring fences

Each world has one `fences` TileMapLayer beside `ground` and `elevation`, using
`game/world/elevation/fences/fence_tileset.tres` and
`game/world/elevation/fences/fence_layer.gd`. Paint one tile in every cell where a fence should
stand. Choose its material by the fence picture and its connection by the arrow picture. An arrow
from either tile can join two neighboring cells; the all-neighbor connector accepts every same-level
neighbor. The renderer uses that paint for art, soft shadows, depth and collision. Fences never
create or reshape cliff rims.

The palette has one figure per material and connection. Its top row connects to every same-level
neighbor; the eight rows below show north, north-east, east, south-east, south, south-west, west and
north-west arrows. A diagonal link is skipped only when a compatible two-link cardinal route already
connects the same cells. This avoids doubled rails at corners while preserving a diagonal where the
cardinal route is blocked by direction or elevation. Every material column is a fixed fence style:
the ground never chooses or changes it.

Each connected rail has rectangular collision 16 units wide, centered on the rail, on the physics
layer for its elevation. A lone painted tile gets square collision over its full cell, so it cannot
leave a gap around the post. Collision also blocks drops and hops from bypassing a rail. Raised
fences use the painted cell's level and leave elevation painting, caches and rims alone. In the
editor, hide the `fences` layer (eye icon) to see the generated fence without its paint figures; the
game hides the paint layer.

World scenes now use this same `fences` layer for every painted fence. There is no separate ground
layer or cliff-edge mode.

## How it works

`Elevation.rebuild()` calls `ElevationFences.mount(ground, self, grid, occlusion, collide)`
(`game/world/elevation/fences/elevation_fences.gd`). Flat worlds call the same mount with a level-0
grid. Only the renderer's parent and the cell elevation differ; paint, connections, art, shadows and
collision all use one path.

- **Connections.** A painted cell contributes its fixed style, direction and level. Each compatible
  neighboring pair is rendered once. The all-neighbor tile accepts every same-level neighbor; an
  arrow tile joins the cell it points toward, and a neighbor can point back. Connections never
  cross elevation levels. Diagonal links are skipped only when a compatible cardinal route already
  connects those cells.
- **Pieces and depth.** Posts and rails are generated `MeshInstance2D` nodes under a Y-sorted
  `ElevationFences` holder. Their material comes from the style kit and the fence shader. Each
  opaque piece writes its level and height into the elevation depth map, so fences sort with bodies
  and terrain.
- **Shadows and collision.** Posts cast contact and soft shadows. Each level with fences gets one
  static body on the matching `level <n>` physics layer. Connected links use a 16-unit-wide
  rectangular collider centered on the rail; an isolated painted cell has one 64-by-64 square
  collider. `blocks_point(point, level)` uses the same half-width to prevent drops and hops from
  passing through the connected rail or isolated tile.

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
ropes. Every source is in `asset/Originals/elevation/fences/` (`<style>-front-a.png` is used, `-b` is
the spare).

`python scripts/art/build-fence-art.py [style ...] [--preview DIR]` (numpy, Pillow) finds the posts
(the most opaque columns, `post_share` of the most opaque one) and the rails (rows opaque between the
posts), scales the post to `post_height` (40 units for wood) at 2 px per unit and writes the kit into
`godot/asset/MAPS/fences/`: `<style>-posts.png` (every post, feet on one row, the rails
behind them removed, moss kept), `<style>-rails.png` (the rails between posts joined into a strip that
repeats sideways), `<style>-rails-side.png` (the upper rail turned a quarter left: seen from above,
lit on its left; for a wall its whole band, for pickets their tips, squeezed to `side_width`) and
`<style>.json` (the measures). A new style is a new entry in its `STYLES` and a paint tile
(`scripts/art/build-fence-paint-tiles.py` and `fence_tileset.tres`).

The wood set used 400 credits (two front views, of which `wood-front-b.png` is used, and two rails
seen from above, unused: the turned front rail matches the front better); the other six styles 1,200
(two front views each).

## Styles

| Palette style | Look | Post height, spacing |
|---|---|---|---|
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
behind fences, and prints where a body with the player's collision stops at each kind of fence and
whether it can drop or hop there. Its connected-fence sample includes eight isolated directions on
ordinary ground, a connected twig run, and an all-neighbor wood run on a raised platform whose
other edges are not fenced. `asset/Originals/elevation/fences/wood-review.png` (the wood set)
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
| `godot/game/world/elevation/fences/elevation_fences.gd` | Connected pieces, shadows, depth silhouettes, collision, `blocks_point` (`@tool`) |
| `godot/game/world/elevation/fences/elevation_fence.gdshader`, `elevation_fence_depth.gdshader` | The fence art; its silhouette in the depth map |
| `godot/game/world/elevation/fences/fence_layer.gd`, `fence_tileset.tres`, `fence_paint_tiles.png` | The painted layer and its tiles |
| `godot/asset/MAPS/fences/` | Kits (`scripts/art/build-fence-art.py`) |
| `asset/Originals/elevation/fences/` | Generated sources and the review sheet |
| `scripts/maps/build-fence-park.py`, `godot/game/scenes/worlds/fence-park.tscn` | The Fence Park |
| `godot/tools/render_fence_park.gd` | Renders and probes the Fence Park |
| `godot/tests/test_fences.gd` | Unified mounting, neighbor connections, square single-tile collision, movement and elevation behavior |
