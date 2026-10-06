# Fences along hill rims

> **Status:** 2026-10-06, seven styles (wood first, then the other six the same day when the owner
> asked for more examples), in the dev world **Fence Park** only (`?map=fence-park`,
> `-- --map=fence-park`). No real world uses fences yet.

## Owner request (2026-10-06)

- Fences on the elevation borders: on some hills, a fence so the player does not fall.
- A fence has **8 faces** (the 8 directions a rim can take: north, south, east, west and the four
  45° diagonals), and its **collision follows the same logic as the hill**, so it never looks
  wrong.
- **Styles per ground**: wood, stone blocks, wood with snow on top for snow maps, and so on. Start
  with one set; continue with the rest once it is approved.
- Later the same day: a body behind a fence was drawn in front of it (its ghost over the fence);
  fix the sort. And "more fence examples, put them all in the scene": every style, each on its
  ground, in the Fence Park.

## What you see

A fence stands a little inside a hill's rim (`inset`, 10 units for wood, 12 for walls and crystal)
and follows the rim around
every corner. Posts stand at every corner and evenly along each straight stretch (about one per
cell of ground, `spacing` 64 units, measured on the ground, so a 45° stretch gets as many posts as
its true length asks); rails join them. How each of the 8 faces looks:

| Rim | What shows |
|---|---|
| South (over a wall) and north (the back) | the fence from the front, as painted |
| South-west and north-east (`\`) | the same rails sheared along the 45° line, posts upright; the face looks south-west, into the light (× 1.1) |
| South-east and north-west (`/`) | sheared the other way; the face looks south-east, away from the light (× 0.8) |
| East and west | a column of posts with the upper rail seen from above beside them, a little inside the posts' line |

Fences around a **hole** stand on the ground around it, so nothing falls in. A fence's posts and rails
**Y-sort with bodies**: a slime on the hilltop behind a south fence is behind its rails, a slime
inside a north fence is in front of it, and a slime on the lower ground walking behind a back fence
(in the strip behind the hill) is behind it. Wherever the sort cannot tell (a body behind a fence on
higher ground beside it, in a hole under its near rim, near the south end of a long diagonal), the
fence still shows in front: the part of the body behind the fence's posts and rails is cut away (not
ghosted), so the body shows only through the gaps between them; the part behind the hill's top still
shows as its ghost ([ELEVATION.md](ELEVATION.md)). Posts and rails cast a soft shadow to the lower
right and a contact shadow at each post's foot. A fence in a hole darkens with depth like the cliffs.

## Authoring

1. Give the world a `fences` TileMapLayer beside its `ground` and `elevation` layers (same grid),
   with the tile set `game/world/elevation/fences/fence_tileset.tres` and the script
   `game/world/elevation/fences/fence_layer.gd`.
2. Paint a style on the cells of a hill's top (all of them, or only the border cells you want
   fenced): a fence stands inside every rim of those cells where a body could drop to lower ground
   (a wall's top, the back, the sides). For a hole, paint the ground cells around it. A rim between
   two levels is fenced by the top it belongs to.
3. Tiles: **`A`** auto, the style of the ground on top (`GROUND_STYLES` in `elevation_fences.gd`,
   the table in [Styles](#styles)); **`W`** wood, **`S`** snowy wood, **`B`** stone blocks, **`D`**
   sandstone, **`T`** twigs (vine branches), **`P`** pickets, **`C`** crystal.
4. A flight of stairs leaves a gap by itself: where its landing, railings or posts would stand on
   the fence line, the fence ends in a post beside them. Where only part of a rim is painted, the
   fence ends in a post and the rest of the rim still drops.

In the editor the fences follow the paint at once (the layer's script rebuilds the elevation drawing);
hide the `fences` layer (eye icon) to see them without its squares. The game hides the layer.

## How it works

`Elevation.rebuild()` ends with `ElevationFences.mount(self, grid, occlusion, collide)`
(`game/world/elevation/fences/elevation_fences.gd`), which adds the node `Fences` under the
`Elevation` node:

- **Runs.** The rims come from the elevation model (`ElevationRims.boundary_edges()`: every border
  edge of every top, the top on its left). An edge is fenced when the cell its top belongs to is
  painted (for a corner triangle a chamfer raised, the painted cell across the corner at its level)
  and no flight of stairs occupies its fence line (`Elevation.stairs`, `ElevationStairs.occupies`).
  Fenced edges of one level and style are chained into runs (loops or lines) and merged into
  straight stretches. The fence line is the run moved `inset` into the top, mitred at corners.
- **Pieces.** Each post and each stretch of rails between two posts is a `MeshInstance2D` under
  `ElevationFences`, a y-sorted Node2D beside the ground layer (never saved with the scene). A post
  sorts at its foot; rails on a front run (the top north of them) sort at their south end, on a back
  run at their north end, and stop at the posts' sides, so posts always stand in front of them. A
  back run (rails, and posts that stand only on back runs) sorts `elevation.behindDepth - inset + 6`
  further south (28 units for wood): past the strip behind the hill, so a body walking there sorts
  first and the fence covers it, but short of where a body on the top can stand (its collision stops
  `clearance` + its height, 34 units, past the fence line). East and west rails sort just before
  their north post, which covers their start. The art comes from the
  style's kit through `elevation_fence.gdshader` (posts from an atlas; rails in world space, so they
  run on seamlessly behind the posts).
- **Depth.** Every piece's silhouette goes into the depth map (`ElevationOcclusion.add_occluder`,
  `elevation_fence_depth.gdshader`), encoded like terrain: the fence's level and how far above its
  foot line a pixel is (east and west rails take their north post's depth), written without blending
  with alpha 0.5, the mark of a fence. A body's pixel behind a fence pixel (nearer by more than the
  margin, elevation_occlusion.gdshaderinc) is cut away instead of ghosted, so the fence shows in front
  of it whichever sorts first. A fence pixel behind nearer terrain is not drawn.
- **Collision.** Per level, a static body (`Fences/Collision/Level<n>`, on the physics layer
  project.godot names `level <n>`) along every run `inset + fences.clearance` inside its rim
  (`clearance` 8 in game-constants.json: 18 units for wood), closed back to the rim at an open run's
  ends. Only bodies of that level collide with it, as with the hill's own collision.
- **No drops.** `blocks_point(point, level)` is true between a fence's collision line and its rim.
  `Elevation.body_fits` rejects such points (no landing there) and `Elevation.ledge_below` finds no
  ledge when a probe lands there, so the rim never holds-then-drops a body at a fence and the hop
  stops before it.

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
`godot/game/world/elevation/fences/art/`: `<style>-posts.png` (every post, feet on one row, the rails
behind them removed, moss kept), `<style>-rails.png` (the rails between posts joined into a strip that
repeats sideways), `<style>-rails-side.png` (the upper rail turned a quarter left: seen from above,
lit on its left; for a wall its whole band, for pickets their tips, squeezed to `side_width`) and
`<style>.json` (the measures). A new style is a new entry in its `STYLES`, a
paint tile (`scripts/art/build-fence-paint-tiles.py` and `fence_tileset.tres`) and, for `auto`, its
grounds in `GROUND_STYLES`.

The wood set used 400 credits (two front views, of which `wood-front-b.png` is used, and two rails
seen from above, unused: the turned front rail matches the front better); the other six styles 1,200
(two front views each).

## Styles

| Style (tile) | Look | Grounds (`auto`) | Post height, spacing |
|---|---|---|---|
| `wood` (W) | round posts, two split-log rails, moss at the feet | highland (meadow grass) | 40, 64 |
| `snow` (S) | the same with snow caps on posts and rails, icicles, drifts | frozen | 40, 64 |
| `stone` (B) | square stone pillars, a low dry-stone wall between them | cavern floor, town cobble | 34, 80 |
| `sandstone` (D) | rounded sandstone pillars, a low adobe-brick wall | sand | 36, 80 |
| `twig` (T) | gnarled branch posts, vine-wrapped branch rails, tiny mushrooms | forest floor, moss | 40, 64 |
| `picket` (P) | tall pointed posts, a row of shorter pickets, fallen leaves | fallen leaves | 42, 64 |
| `crystal` (C) | crystal clusters on rock bases, two taut ropes | crystal floor | 44, 64 |

Walls fit the same kit: their pillars are the posts, the wall between them the rails, the wall seen
from above its side rail. All seven await the owner's verdict.

## Test world

`python scripts/maps/build-fence-park.py` writes `godot/game/scenes/worlds/fence-park.tscn` (a dev
world, left out of the release export): a level-1 square (with a gap in its east fence and a flight
of stairs down its south wall and its west side; the player spawns on it), a level-2 diamond, a
level-1 octagon with a level-2 octagon on top, a square and an octagon hole, a level-2 square fenced
on its south rim only, a diamond fenced on its east half and a level-3 block, all wood; below them
two rows of plots, one per ground, each with its own hill (octagons, diamonds, squares, a terrace, a
hole) fenced "auto", so every style shows on its ground. `res://tools/render_fence_park.gd` renders it with the game's own drawing (windowed:
`--path godot -s res://tools/render_fence_park.gd -- --out=<dir>`), test slimes placed in front of and
behind fences, and prints where a body with the player's collision stops at each kind of fence and
whether it can drop or hop there. `asset/Originals/elevation/fences/wood-review.png` (the wood set)
and `styles-review.jpg` (every style, and bodies behind fences) are its output. `godot/tests/test_fences.gd` checks the same in the game.

## Limits and next steps

- Fences only stand along rims. A fence on flat ground (a pen, a garden) and gates are not built.
- Walls on a 45° run show only their front face, sheared, so they look thinner than on a straight
  run (no top face is drawn along the diagonal).
- The cut-away part of a body behind a fence follows the depth map's 2-unit grid, so its edge along
  a rail can step by a pixel or two where the sort could not put the body first.
- Props and enemies do not path around fences any differently from the rim; enemies collide with
  them on their level.
- A fence's depth silhouette counts as ground of its level for the cast shadows (fences do not cast
  their own long shadows on lower ground yet).

## Files

| Path | What |
|---|---|
| `godot/game/world/elevation/fences/elevation_fences.gd` | Runs, pieces, shadows, depth silhouettes, collision, `blocks_point` (`@tool`) |
| `godot/game/world/elevation/fences/elevation_fence.gdshader`, `elevation_fence_depth.gdshader` | The fence art; its silhouette in the depth map |
| `godot/game/world/elevation/fences/fence_layer.gd`, `fence_tileset.tres`, `fence_paint_tiles.png` | The painted layer and its tiles |
| `godot/game/world/elevation/fences/art/` | Kits (`scripts/art/build-fence-art.py`) |
| `asset/Originals/elevation/fences/` | Generated sources and the review sheet |
| `scripts/maps/build-fence-park.py`, `godot/game/scenes/worlds/fence-park.tscn` | The Fence Park |
| `godot/tools/render_fence_park.gd` | Renders and probes the Fence Park |
| `godot/tests/test_fences.gd` | Mounting, walking into fences, no drop or hop over them, every face |
