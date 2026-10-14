# Elevation: hills, holes and ground levels

> **Side walls are the cliff look (owner, 2026-10-14: "I think it is the way to go").** The
> [Side walls](#side-walls) experiment is closed and kept: worlds draw their cliffs with
> `cliff_look = "sides"` on the ground layer. **The front-only look is deprecated, awaiting its final
> removal:** the Walls, Feet, Lips and Rims groups, the model's cast Shadows and Water at walls' feet
> (all drawn only without `cliff_look = "sides"`), the fern fringe art (`<ground>-lip.png`,
> `-foot.png`, `storybook-grass`, `elevation_fringe.gdshader`, `elevation_strip.gdshader`,
> `elevation_rims.gd`'s strips), the wall-end corner stones (`-wall-end-*.png`,
> `elevation_wall_end.gdshader`, RampEnds), the fern ramp feet (`_add_ramp_foot`) and the ramp's
> EDGE_FADE band. Do not build on them. Until they go, worlds without the metadata still draw them:
> on 2026-10-14 only the cliff sides lab and level-1's chunks (c4, c5, d4, d5) use side walls; the
> other 55 worlds with elevation still use the deprecated look. Removing it means setting
> `cliff_look = "sides"` everywhere (or making it the default), rebaking the caches, checking every
> world's cliffs, then deleting the code and art above and the sections of this document that
> describe them.

> **The cliff system (2026-10-12).** The hand-painted cliff experiments of 2026-10-09/10 (a tile
> sheet painted with Godot terrains, the cliff builder, the shape painter, the rectangle prototype)
> were removed: this system won, drawn with art cut from the approved painting
> ([Storybook art](#storybook-art)). Their code is in git history (commits `ded3c904`, `14aa891a`).
> The manual fixed-cell prototype stays ([CLIFF-MANUAL-PROTOTYPE.md](CLIFF-MANUAL-PROTOTYPE.md)).

> **Status:** first version, 2026-10-05, in the playground only (the **Elevation Park**, rows
> 28-121 south of the old playground). Since 2026-10-09 level-1 paints it too (its village plateaus,
> two flights of stairs, and from 2026-10-10 a wall along its north edge painted above the map). The
> owner asked to retake elevation after the Phaser-era attempt (branch `feat/elevation-levels`, never merged and
> deleted on 2026-10-14; its design is archived in [ELEVATION_LEVELS.md](../archive/phaser/ELEVATION_LEVELS.md)) failed on
> art that did not join at the top and foot of 2- and 3-level walls.

## Owner decisions (2026-10-05)

- Three pieces of art make a cliff: the **top edge** and the **bottom edge**, per terrain (the
  terrain is the master), and a **wall** that repeats seamlessly sideways and downwards.
- Hills and holes are **cubes, diamonds and octagons**, showing **only their front faces**: a
  square shows its south face, a diamond its south-west and south-east faces, an octagon all three.
  North, east and west sides are rims without a wall.
- Holes are hills upside down: the wall shows on their far (north) side.
- Later the same day: wall ends need an edge of their own (they looked cut out), every ground
  needs its own cliff foot, and water at a wall's foot laps back and forth against it.
- 2026-10-06: walls are taller than the slime, so it must be able to go **behind** them and be
  hidden, for any hill size, and a taller hill must hide more than a lower one. Corners and the
  top shadows looked fake. Focus on the art, the physics and the collisions.
- Later on 2026-10-06: going 64 units per level behind a hill looked wrong, so the walk-behind
  depth is **capped**. Hidden bodies show as a **mix of silhouette and see-through**, the player
  and the enemies alike. Rims **hold the slime like in Zelda** until it insists; then a short fall
  plays and it lands **where the picture says it falls** (in front of a wall, behind a hill, beside
  it). Jumping on and off hills broke the collisions, the camera snapped at landing and the shadow
  stayed behind; the jump also reached level-1 tops. The owner is unsure the jump fits the game: it
  stays as a low hop that never climbs (below), easy to drop later.
- 2026-10-08: the jump is removed from the game. Its code stays (no key runs it and nothing
  teaches it), so stairs and ledge drops are the only ways between levels in play. Ledge drops
  still fly with the jump's flight (`jump_sequence.gd`).
- 2026-10-11, from an *A Link to the Past* screenshot: "cliffs can connect to the ground with no
  stairs, giving the illusion of different levels; it works on 45 degree angles that converge the
  upper level and the lower level". Built as [ramps](#ramps), prototyped in the cliff shapes lab
  ([Storybook art](#storybook-art)).
- Later on 2026-10-11, after painting a U with two 45° arms and ramps along their feet: "the green
  arrows are only used in open cliffs, not in closed figure cliffs, since the corners join the wall
  with the ground. So if they are used the cliff is open and the shadow and other rules may not
  apply". A ramp marks where a cliff **opens**: the wall comes down to meet the ground and the top
  joins it, instead of turning a corner and closing the shape ([open ends](#open-ends)).

## What you see

A raised area is drawn where it is painted. Below its south-facing edges hangs a rock wall, **one
stone course (one cell, 64 units) per level of drop**, so a 3-level wall shows three courses with
their joints lined up across every face. The wall is of one of nine **wall styles** (meadow rock,
snow rock, sandstone, cave rock, crystal rock, mossy rock, masonry, root rock, red rock): the one
painted over its top, else its ground's ([Wall styles](#wall-styles)). The higher ground's **lip** (grass tufts, soil and roots;
a snow cornice with icicles; a crumbling sandy edge) hangs over the wall's top; the lower ground's
**foot** (tufts and ferns, a snow drift, a sand drift) grows up its base. All nine grounds have
their own (grass, snow, sand, forest soil, moss, fallen leaves, cavern rock, crystal rock, cobble
with a curb). The same tufts run around the **whole top** as one strip: over the walls they hang
with their soil and roots, along the north, east and west rims (and a hole's near rim) only the
tufts show, and they turn every corner in a round curve. A **one-row open cliff** (below) has no
back rim. Where a wall ends, a column of rounded
**corner stones** finishes it (lit on a west end, shaded on an east end). Where a wall stands in
**water**, the water line laps up and down the rock in a travelling wave with a band of foam,
leaving the rock above it dark and wet. Raised ground **casts a shadow** to the lower right (the
light comes from the upper left): along a hill's east side and in a thin band at its wall's foot,
three times as long for a level-3 hill as for a level-1 one, none on the lit north and west sides;
a hole's west rim shades its floor. Rims facing the light catch a thin light along their edge.
Faces are shaded by the way they look (south-west lit, south mid, south-east dark). The ground of a
hole and the lower courses of its walls darken with every level of depth.

**Stairs** (reworked 2026-10-11 after the stairs of *A Link to the Past*, at the owner's request:
"they do not pass the bottom and on the top only the top edge of the cliff") are flights of stone
steps between two posts of stone blocks, in one style everywhere, coloured after the road or ground
they lead to: pale green stone on grass, sandy on sand, grey on cobble, white on snow, blue-grey in
caves. They leave a rim in any of 8 directions:
- **front flights** (south, south-west, south-east) are set into the cliff's face, from its top edge
  down to its foot and no further: no landing on the top, nothing run out over the lower ground. The
  steps (4 per level, each a shaded riser under the nosing above, then a lit tread) and the posts
  beside them lie flat on the face, a column of blocks each side; the lip breaks where the flight
  leaves the top;
- **side flights** (east, west) run out a cell per level beside the hill (seen from the side) and
  **back flights** are foreshortened (north 1.5 cells per level, 45° ones a diagonal cell), as no
  face of the hill shows there: steps from the rim (no landing) down onto the lower ground, between
  two low side walls of blocks; what of a back flight lies behind the hill's top is hidden by it.

A flight is one or two cells wide. The flights of 2026-10-06 (a landing on the top, railings with
newel posts in the cliff's rock, front flights running a cell per level past the wall) are in git
history and `asset/Originals/elevation/stairs-mockups/`.

**Ramps** join the levels with no steps, as in *A Link to the Past*: ground that slopes from the
lower level up to the top beside or behind it, drawn as flat ground, so the two levels seem to
meet. Beside a ramp the cliff shows only the height left between the top and the slope: the wall
**tapers** from its full height to nothing where the slope reaches the top, on a straight south face
or a 45° one, its stone courses where they always are, the lip running on along the top edge to the
end and the foot following the slope up. Where the slope reaches the top at the end of the face and
the top ends there too (an arm's or a ridge's tip, a face's end) the cliff is **open**: no corner
stones, the top's rim does not turn around the end, and no shadow falls there; at a closed
plateau's corner the rim stays closed ([Open ends](#open-ends)). A **one-row open cliff** (owner,
2026-10-11) is a top one row thick (or, since 2026-10-14, one column thick: an arm running north)
that ramps join to the ground below, as the owner's U in the cliff shapes lab: it has no back rim (on so narrow a top it made a second top border) and casts no
shadow, and its ramps take none. Nor has it a hidden strip behind it (`ElevationGrid.no_strip`):
its back reads as flat ground, so nothing walks under it from behind. Around it **only walls
collide** (owner, 2026-10-12; `Elevation._find_open_zone`): in its cells, the lower cells touching
it and the cells its ramps stand on, a collision line with ground of the cliff's level on one side
and ground of its ramps' bottom level on the other (its back edge, an arm's side, a ramp's sides
and ends, the cliff's tip) is cut out (`_cut_open_seams`), no ledge drops over it, and a body
crossing it takes the level of where its feet are (`_level_across_open`). So the cliff, its ramps
and the ground around them are one walk, as they look: a body coming onto the top from anywhere
stands at its level by the time it reaches the front rim, the rim holds it there and a drop off it
lands at the right level, whatever level the ground behind is painted. The faces and the wall a
ramp tapers still collide, and their rims are jump borders: here a body drops over the tapered wall
too. Every other cliff, ramps or not, keeps its back rim, shadows, strip and
collision.

**Behind the hills.** A hill hides the ground right behind it: from the north, a body can walk
`behindDepth` (32 units on screen) into a hill's top, and the hill covers what of it is behind; a
body in a hole walks as far under its near rim. The depth is the same for every height (in 3D it
would be 64 units per level, which buries the slime behind a tall hill); what shows of the body
still follows the height. The hidden part of a body shows as a **ghost**: its own colours tinted
blue and see-through (the player at 0.6, enemies and NPCs fainter at 0.35). East and west sides
hide nothing (the camera looks north).

**Moving between levels.**

- **Stairs** join two levels and are a passage, not ground (owner, 2026-10-14, the
  [stairs walk](#stairs-walk)): the player stepping onto a flight along it is carried to the other
  end a step at a time, slower than walking and with a stair-step sound, and takes the level of that
  end as it steps off; it cannot stop on the way. Enemies and NPCs never set foot on stairs (they
  stay on their levels; ramps are ground to them). The posts or side walls hold a body on the steps;
  a body put on a flight takes the level of the height it stands at (the upper half of a level's
  stretch the level above).
- **Ramps** too: a body takes the level of the height it stands at (the upper half of a level's
  stretch the level above), and steps between the slope and the top beside it where the face left
  between them is low, at the top end. Their long sides are open ground: a body walks on and off
  them anywhere their side meets ground below the slope's highest part (taking that ground's level
  when it steps off). A free top end is the top's rim carried on: the top level is held there and drops
  over it, lower levels meet it as a wall. The tapered wall beside a ramp is solid and no ledge
  drops over it (except around a one-row open cliff, below); on the slope no ledge drops over a
  wall that rises above it either.
- **Open cliffs**: around a one-row open cliff a body walks on and off the top and its ramps
  anywhere no wall stands, taking the level of where its feet are ([What you see](#what-you-see)
  has the rule); its front rim holds and drops like any other.
- **Changing area**: the player is spawned in the new world and takes the level
  of the ground where it appears (`track` with no level).
- **Ledge drops.** A rim holds the slime, as in Zelda. Pushing against it for `dropPushMs`
  (280 ms) drops it over: a small hop off the edge, then a fall. Shape does not matter (a straight
  rim, a 45° one, a tip, a wall's top): the side of the body facing the push is probed a few units
  further (`Elevation.ledge_below`), and it is at a ledge when what is past it is lower ground (a
  lower top, or a wall whose top is at or below its level). The landing follows height alone: it
  is where a fall straight down looks like it lands from the camera, `dropOutward` (22 units) past
  where it stood and one cell lower on screen per level dropped. Over a south face (straight or
  45°) that is the wall's foot; over a back rim, the strip behind the hill (hidden); over a side rim
  or a tip, beside the hill. Where that spot has no room (a wall, deep water) the landing takes the
  nearest spot that has, up towards the rim or further out, so a side drop past a wall lands beside
  it, not hidden behind the hill; with no room at all the rim keeps holding. Nothing drops up a
  wall, from the strip behind a hill into the hill, or off stairs (their posts and side walls are
  solid).
- **The jump** (hidden since 2026-10-08: no key runs it; tests still do) is a low hop
  (`hopArcHeight` 36 units, below one level) that **never climbs**: it stops before higher ground
  and walls, and over a rim it drops to the lower ground, landing as far out as the hop carries
  it. Without elevation it is Phaser's jump.
- **The flight** (`jump_sequence.gd`, for both) is worked out in 3D: the point on the ground moves
  evenly from take-off to landing and the height falls under gravity. The body travels on screen
  with it, so the camera and the hurtbox follow smoothly; the art rides above the body, rising first
  and falling faster at the end. The shadow lies on the ground under the slime (on the top while it
  is over it, then on the lower ground, hidden behind a hill), smaller and fainter the higher the
  slime. The body's depth blends from take-off to landing, so it stays in front of the wall it falls
  down and slips behind the hill it drops behind. Pressure plates ignore a slime in the air.

The values live in `game-constants.json` `elevation`: `behindDepth` (rounded to half a cell),
`dropPushMs`, `dropOutward`,
`dropBaseMs` (260) and `dropMsPerLevel` (90) for a drop's time, `hopArcHeight`.

**The park** (`game/dev/playground.tscn` or the world `game/scenes/worlds/playground.tscn`, F6;
walk south from the spawn, or launch with
`?map=playground&spawn=1280,1950`): square hills at levels 1, 2 and 3, diamond hills, octagon hills,
a square hole (-1), a diamond hole (-2) and an octagon hole (-3), terraces (levels 1-3 nested), a
sand plateau and a snow plateau, a ridge of levels 1, 2 and 3 on one south edge, a flooded diamond
hole, a two-level cliff standing in a lake (with an island and a deep pool), and a row of plateaus on
forest soil, moss, fallen leaves, cavern, crystal and cobble. Every square and octagon hill, the
terraces, the plateaus, the ridge, the lake cliff and two holes have stairs. At the bottom, the
stairs showcase: a level-2 octagon with a flight on each of its 8 sides, and a level-1 octagon with
flights two cells wide. The plateaus' flights show the stairs' colours. Every wall style shows: the
plateaus take their ground's,
and the `cliffs` layer paints the diamonds (sandstone, mossy rock, crystal rock), the octagons
(masonry, red rock, cave rock), the octagon hole's far wall (root rock), the ridge (cave rock,
masonry and sandstone meeting on one edge), the lake cliff's east half (mossy rock) and the
showcase (red rock, masonry). The square hills, the terraces and the other holes keep meadow rock.

## Authoring

1. Give the world an `elevation` TileMapLayer beside its ground layer (same grid), with the tile
   set `game/world/elevation/elevation_tileset.tres` and the script
   `game/world/elevation/elevation_layer.gd`.
2. Paint the **top you walk on** with a level tile (−3 … 3; unpainted cells are level 0). The wall
   appears by itself below the area's south edges and covers the cells there: leave as many free
   rows below a south edge as the levels it drops. A hole is painted the same way with a negative
   level; its far wall covers its first rows. A wall along the map's north edge with its top off
   the map: paint the top on the rows **above the map** (row −1 and up, at most `MAX_ROWS_ABOVE` =
   6): the elevation starts its grid that many rows higher (`cell_offset`; its node moves up as far),
   so only the wall and the lip hang into the map. Its top takes the ground of the map's first row.
3. Shapes come from the steps of the paint: **single-cell steps make a straight 45° edge**, steps
   of two cells or more keep a square corner. A staircase of single steps is a diamond's side; a
   rectangle with its corners cut by single steps is an octagon; a diagonal line of single cells
   (each touching the next only at a corner) is a staircase on both sides, a **45° ridge** about
   45 units wide (two blocks touching only at a corner stay apart there).
4. Paint **stairs** with the arrow tiles (row 2 of the palette; row 3, once an open landing, paints
   the same flights; the arrow points down the stairs) on the **first cell past the rim**, on the
   lower side, in the flight's direction: below a south edge the wall's first row, beside a side the
   cell next to it, north of a back rim the cell above it, at a 45° rim the lower cell whose corner
   the chamfer fills. Two such cells side by side along the rim make one flight two cells wide. The
   flight joins the higher ground behind the cell to the level of the cell (the ground it leads
   down to). A front flight stays in its wall; the others need room on that ground: a cell per
   level beside the hill (sides), 1.5 cells per level to the north (a diagonal cell per level at a
   45° back rim), keep other hills out of it. The old `S` tile is a front flight. The flight's
   colour comes from a road at its foot or its top end (cobble, sand or forest soil), else the
   ground of the top it leaves: paint the road up to the stairs to give them the road's colour.
5. Paint **ramps** with the green wedge tiles (row 4 of the palette; the arrow points down the
   slope) on **every cell of lower ground the ramp runs over**: along the foot of a wall (the cells
   right below a south face's wall, or the diagonal of cells in front of a 45° face), or out from a
   rim like stairs (below a south face's wall, beside a side, north of a back rim). Its length is
   the cells painted along the arrow: along a 45° face one diagonal cell per level is enough (a
   diagonal cell is 1.4 cells long), along a straight face or out from a rim two per level (2-3
   read gentler); its width is the cells side by side. Ramps are for **open cliffs**: paint them
   where the cliff should come down to the ground, at an arm's or a ridge's tip or a face's end
   ([Ramps](#ramps) has an example); at a closed plateau's corner the wall still tapers, but the
   rim stays closed around it ([Open ends](#open-ends)).
6. The ground on top and below is the ground layer's: paint sand on a plateau and its lip is sand.
7. The **wall style** follows the ground on top; to choose another, paint it on a `cliffs` layer
   ([Wall styles](#wall-styles)).

In the editor the cliffs follow the paint at once (the layer's script mounts the drawing under the
ground layer, never saved with the scene); hide the `elevation` layer (eye icon) to see the result
without its numbered squares. The game hides the layer.

`scripts/maps/build-elevation-park.py` builds the park and is the worked example; it rewrites the
playground's park rows, so hand edits to the park are lost when it runs again.

**Fences** that stop the player dropping off a rim are painted on their own `fences` layer and
documented in [FENCES.md](FENCES.md).

## Wall styles

A wall and its corner stones are of one wall style (2026-10-08; before, every cliff was meadow
rock; flights of stairs take their colour from their ground instead, [Stairs](#how-it-works)). The
style of a wall is, in order:

1. the one painted on the world's **`cliffs` layer** over the top it hangs from: a TileMapLayer
   named `cliffs` beside the `ground` and `elevation` layers (same grid), with the tile set
   `game/world/elevation/cliffs/cliff_tileset.tres` and the script
   `game/world/elevation/cliffs/cliff_layer.gd`. Paint the cells of a hill's top (all of them, or
   only those along the walls you want to change). A hole's far wall hangs from the ground around
   the hole: paint those cells. Like the other layers it follows in the editor at once and hides
   itself in the game;
2. else the style of the **ground on top**: the world's own choice for that ground, if its ground
   layer has the metadata `cliff_wall_styles` (a Dictionary, ground → style, e.g.
   `{"highland": "storybook-rock"}`), else `GROUND_WALL_STYLES` in `elevation.gd` (below);
3. else meadow rock (`DEFAULT_WALL_STYLE`); a style without wall art also falls back to it.

The lips, rims and feet are their ground's (`<ground>-lip.png`, `-foot.png`) unless the ground
layer's metadata `cliff_fringe` (ground → art name, e.g. `{"highland": "storybook-grass"}`) names
other art. Both metadata are per world, so a world can try a style without changing the others
(the cliff shapes lab does, [Storybook art](#storybook-art)).

| Style | Tile | Look | Ground on top |
|---|---|---|---|
| `meadow-rock` | M | warm grey-brown boulders with tufts of moss | grass (`highland`), and any ground not listed |
| `snow-rock` | S | cold blue-grey granite with ice crystals in the cracks | snow (`frozen`) |
| `sandstone` | D | ochre and peach wind-smoothed blocks with layered strata | sand (`sanddessert`) |
| `cave-rock` | C | dark slate-blue slabs, pale cave mushrooms, specks of glowing moss | `cavern-floor` |
| `crystal-rock` | K | indigo slabs with violet and cyan crystal clusters | `crystal-floor` |
| `mossy-rock` | G | grey-green stones under cushions of moss, ferns | `forest-moss` |
| `masonry` | B | cut limestone blocks in a running bond, quoins at the ends | `town-cobble` |
| `root-rock` | R | dark umber stones in forest soil, threaded with roots | `forest-floor` |
| `red-rock` | A | terracotta and rust-red stones with fallen autumn leaves | `amberleaf` |
| `storybook-rock` | – | rounded grey-brown stones of the approved H plateau painting, cut from it (with `storybook-grass` lips and feet) | none; a world picks it by metadata |

Exactly where: a wall's style is read at the middle of its top edge, a little into its top (half a
cell in when the cell there is a corner triangle a chamfer raised, so it belongs to the painted cell
across the corner). Each half-cell column of wall takes its own style, so two styles meet on a
straight vertical line where a top's paint (or its ground) changes along a wall. The style of every
wall is `Elevation.band_styles` (per `grid.bands`).

## How it works

`WorldService.register_world` calls `Elevation.mount(ground, true)` after the water and the terrain
edges: `game/world/elevation/elevation.gd` adds the node `Elevation` under the ground layer, builds
the model and draws it.

**The model** (`elevation_grid.gd`, pure data). The map is authored as the camera sees it. Every
cell is split into 8 triangles ("tris"): its 4 corner triangles and the 4 quarters of its centre
diamond, which meet on the 45° lines. A **chamfer** gives a corner triangle the level across the
corner where a convex corner and a concave one form one step of a staircase (they pair along the
45° line), so single steps become straight diagonal edges and lone corners stay square. Where two
raised cells touch only at a corner (a saddle) and the two lower cells there each pair with a
convex corner beside them along the 45° line (the raised cells are part of a diagonal line of
single cells), the corner joins them into one 45° ridge (`_saddle_flips`; a lowered diagonal line
makes a trench the same way); two blocks touching at a corner pair with neither and stay apart.
**Walls** are swept per half-cell column, top to bottom: below an edge where the north tri is
higher (level a) than the south one (level b), the wall covers the next 4·(a − b) tris, one cell of
depth per level, unless a tri in front of the wall plane hides it first (a tri of level l at depth d
cells hides it when d ≥ a − l: the near rim of a hole, a lower platform standing in front). A wall
that reaches its depth has a foot. A covered tri is wall, walkable at no level. Stairs are not in the
model: a stairs cell counts as the ground it leads down to, and the flight stands on it.

**The ground in 3D** (`elevation_grid.gd`). One level up is 64 units up and drawn a cell higher,
so the ground of level L seen at screen point p lies at ground position p + L cells (south): that
is the depth of a body, feet y + 64 · level. A level walks on its own visible tops (not walls), on
stairs that reach it, and on the strip behind higher ground: below every **back rim** (an edge
where ground it walks on, north, meets a higher top, south: a hill's north and diagonal back rims,
a hole's near rim) it may go `behind` cells further (`behindDepth` / 64, rounded to half a
cell), into whatever higher ground is there: the top, and at a hill's tip (a diamond's or an
octagon's side corner) the top corner of its wall. So the strip's edge runs straight on to the tip
and turns down the wall's end to its foot: walking down a 45° back face slides past the tip, with
no notch to get caught in. The strip never reaches the hill's real footprint (a cell per level
below its back rims). `is_walkable_point` answers for a point: higher ground is walkable when the
point `behind` north of it is. The rest of a wall stays solid, east and west sides stay plain rims,
a diagonal back rim gets a slanted strip.

**Hiding** (`elevation_occlusion.gd`, `elevation_occlusion.gdshaderinc`). Depth is the ground
position of what a pixel shows (a wall shows its plane, the depth of its top edge). Every tri of
the elevated part of the world, plus a thin core past each rim, is drawn once into a SubViewport
(`Occlusion/DepthMap`, 2 world units per texel; coarser if a side would pass 4096 texels): level,
how far below a wall's top edge; then the stairs' faces at their height: a side or back flight
marked as a structure (the cast shadows read its height, level − dy / 64), a front flight as the
wall it is set into, and ramps' slopes as ground of their bottom
level, marked as ramps (they hide nothing, and cast no shadow except that of the wall they cover,
over which they keep their height). The body shaders (`hit_flash.gdshader`
on enemies and NPCs, `form_skin.gdshader` on the player) read it: a pixel whose terrain is nearer
than the body's feet (feet y + 64 · level) by more than 12 units is drawn as the ghost: its colour
mixed 45 % with the blue tint, at `elevation_silhouette` opacity. Every physics step `Elevation` sets
each tracked body's depth and ghost opacity on its sprites' materials (sprites without one get the
neutral hit-flash material); a body in the air (`set_flight`) gets the depth its flight gives it.

**Cast shadows** (`elevation_cast_shadow.gdshader`): drawn over the ground up to two cells right of
and one below anything higher, before the walls. Each pixel looks back towards the light along
three rays through the depth map for ground high enough to shade it (`SHADOW_UNITS` = 20 units of
shadow per level), so shapes, corners and heights all come out right without per-edge pieces. The
lookup is `elevation_cast_shadow.gdshaderinc`; a ramp's slope, drawn over that ground, takes the
shadows at its own height with it, and casts only the shadow of the wall it covers.

**The drawing** (children of `Elevation`, bottom to top; all world-space, so nothing has seams):

| Node | What | Art |
|---|---|---|
| `Patches` | chamfered corner triangles that take the ground across the corner; the top's ground over the water surface's soft edge along a rim over water | the ground's sheet (`elevation_ground.gdshader`) |
| `Shade` | the ground of holes, darker per level of depth | multiply (`elevation_shade.gdshader`) |
| `Shadows` | what raised ground casts on lower ground (none just beyond a ramp's open end: vertex colour r) | multiply (`elevation_cast_shadow.gdshader`, reads the depth map) |
| `Walls` | covered tris, UV = (world x, depth below the top edge + the course of the top level), shaded by face, one mesh per wall style; corner stones at every wall end (beside lower ground) on the wall's own UV, never above its top edge | `art/<style>-wall.png` (`elevation_wall.gdshader`), `art/<style>-wall-end-right.png` / `-left.png` (`elevation_wall_end.gdshader`) |
| `Rims` | the light a rim facing the upper left catches | vertex colours, `elevation_glow.gdshader` |
| `Water` | water at the foot of walls standing in water: the water surface's own maths sampled in front of the wall, its line lapping up the rock, foam, wet rock | `elevation_water_foot.gdshader` (shares `water_surface.gdshaderinc`) |
| `Feet` | the lower ground's foot along each wall foot | `art/<ground>-foot.png` (`elevation_fringe.gdshader`), else the ground's terrain edge tiles |
| `Lips` | every top's border as one strip (`elevation_rims.gd`): lip over its walls, rim of tufts elsewhere (none along a one-row open cliff's back rim) | `art/<ground>-lip.png` (`elevation_fringe.gdshader`), else `<ground>-edges.png` per edge (`elevation_strip.gdshader`) |
| `Ramps` | every ramp's slope and skirt as its lower ground, with the cast shadows at its height; an open end's cap over the strips' ends (lower ground, and the top's ground on the top); a rimmed ramp's landing as its top's ground over the lip ([Ramps](#ramps)); where a flight of stairs leaves a top, that top's ground over its lip (`add_approach`) | the ground's sheet (`elevation_ramp.gdshader`) |
| `RampEnds` | corner stones where a straight front ramp cuts through a wall | `art/<style>-wall-end-right.png` / `-left.png` (`elevation_wall_end.gdshader`) |
| `RampFeet` | the lower ground's foot along a slope's edge where it runs at a face, squeezed into the face's height, its top rows faded, leaning towards the face where the edge climbs steeper than 45° | `art/<ground>-foot.png` (`elevation_fringe.gdshader`, `top_fade`) |
| `Stairs` | every flight's faces, back to front: a front flight's steps and posts on its face, the others' treads, risers and side walls; flights in a row of one colour share a mesh (`<ground>-<n>`) | the grain of meadow rock's `meadow-rock-stairs-tread.png`, `-riser.png` and `-coping.png` (blocks) in the colour of the flight's ground (`elevation_stairs.gdshader`, `_stairs_material`) |
| `StairsFeet` | the lower ground's foot where a side or back flight's side walls stand on it in sight | `art/<ground>-foot.png` (`elevation_fringe.gdshader`) |

**Rims** (`elevation_rims.gd`): a top's boundary edges (where it meets lower ground, or a wall at
or below its level) are chained into loops and lines with the top on the left. Along a south face
the strip is the lip, swept straight down (also on diagonal faces, so it follows the wall); along
every other edge it is the rim, swept perpendicular to the edge, its art cut below the soil line
(vertex colour b; `rim_cut` in the shader). The art's u runs on along the chain, convex corners turn
in a round fan and concave ones meet in a mitre, so lip and rim flow into each other around every
corner. The part over the top meets the same way: at a convex corner in a mitre, at a concave one
both strips run on past the corner until they meet (a single triangle only where that point would
lie more than `MITRE_LIMIT` reaches out). The feet and the wall's texture are swept vertically: a diagonal face continues the same
strip as a straight one, its course joints bending at the corner; a foot reaches `WALL_END_FRINGE`
past a wall end. Depth darkening is shared by every shader (`elevation_light.gdshaderinc`).

**Collision and levels.** Each level has a static body (`Collision/Level<n>`) on its own physics
layer (12 + level + 3: `level -3` … `level 3` in project.godot) whose segments surround exactly
the ground that level can walk on (the 3D ground above). Nothing is placed by hand: the painted
tiles give the model and `collision_segments` traces the outline from it on a finer grid, every
cell quadrant cut by its two diagonals (16 parts per cell). Each tri is two of those parts and a
shift of half a cell maps the grid onto itself, so a part is walkable when its tri is, or when its
tri is a higher top and the part `behind` north of it is walkable. The outline is the border
between walkable and blocked parts, so it closes at every corner by construction (where a hole's
far-wall foot meets its lowered near rim it takes a small step). About 9 ms per level for the
park, once at load. Every player, enemy and NPC body in the world is
tracked (`Elevation.track`) and collides only with its own level's layer: walls block the lower
ground, rims keep a body on its hill or out of a hole, and the strip behind a hill is open to the
level below. A body's level changes only on stairs (one standing on a flight takes the level of the
height it stands at, the upper half of a one-level flight the top level; the player's stairs walk
sets the level of the end it steps off at) and when a jump or drop lands (`track(body, level)` sets
the new layer). While a flight (a jump's, a drop's or the stairs walk) runs it owns the body and
places it every step, so nothing collides on the way. `WorldService.elevation` answers `level_at`,
`is_walkable`, `level_of(body)`, `track`, `body_fits`, `drop_target` (the ledge push in
`player.gd`) and `hop_target` (the jump in `player_abilities.gd`).

**Stairs** (`elevation_stairs.gd`). A flight is built in 3D in its own frame (s along its
direction from the rim, t across, h up); a point at ground (x, y) and height H is drawn at
(x, y − H) and its depth is its ground y. A front flight (`in_face`) has no run: it is a vertical
surface in the plane of the face (as the wall is), from the rim (h = top) to the foot (h = 0), so a
body on it stands at the height it is drawn at, at the face's depth. The others run out
(`end` = a cell per level, a north one 1.5) with 4 steps per level and no landing. `Elevation`
finds the flights in the painted stairs cells (`painted_stairs`; a run of cells side by side along
the rim with one kind is one flight; its rim is where the higher ground behind the cells begins),
picks each one's colour (`_stairs_ground`: the grounds a quarter cell past its two ends, a road
first, `STAIRS_ROAD_GROUNDS`; `_stairs_colour`: that ground's average colour, MapTerrain's, made a
paler stone, `STAIRS_SATURATION`, `STAIRS_VALUE`) and asks each for:
- `walk`, the walkable surface on screen (the face between the posts; the steps' nosing line
  between the side walls): walkable by every level the flight joins; a body there takes the level
  of the height it stands at (`height_at`, `level_at`) and its depth (`depth_at`, the true ground
  position under it, so a near side wall hides its feet);
- the way just past its ends (`overhang`: `REACH` 32 units into the top, `BEYOND` 48 past a side or
  back flight's bottom end): walkable by every level it joins where the ground of that end is
  (`_stairs_rule`), without changing a body's level. A body's level follows its feet, but its body
  reaches further: over a 45° rim its upper corner meets the top before its feet are halfway up a
  level, and the end of a back flight is only 32 units (a third of its run) from its rim on screen;
- its blockers per level (`blockers`): a front flight's posts for every level it joins; else what
  of the structure stands at that level's height, drawn at that height (the side walls' and steps'
  bases for the bottom one), and the side walls along the nosing line for every level it joins (a
  body on the steps stands at their height). Collision comes from these footprints, never from what
  is drawn: what of a flight stands higher, over ground behind it, only hides a body there (the
  depth map);
- its silhouette, the whole structure as drawn, and `approach`, the top's ground just behind its
  rim (`occupies`; fences leave a gap there, and `add_approach` draws that ground over the lip);
- its faces, back to front for the camera (a front flight: its steps, then its posts; else the far
  side wall's inner face, the steps from the far end, then each side wall), drawn in one mesh per
  colour and written to the depth map. Godot's 2D drawing has no depth test, so what of a flight
  lies below its top level where the hill's top is drawn (`occlude`: a back flight's foot and first
  steps behind the rim) is cut out of its faces, its depth, its silhouette and its foot strips (feet
  only show where a side wall stands on the lower ground in sight).

Each level's collision then traces the stairs too (`_with_stairs`): near a flight, the terrain's
outline, the flight's outlines and those of flights it touches are cut where they cross, a piece
is kept where it parts walkable from blocked ground, pieces on one line merge and ends a hair apart
are welded into one point (a body sliding along an edge would catch on the next one's end). About 27 ms for
the park's 39 flights and 165 ms for all levels' collision, once at load (2026-10-11).

### Stairs walk

Stairs are a passage, not ground (owner, 2026-10-14: they "should feel like a transition, similar to
Zelda ... it take longer to cross them than normal terrain", and the player should not be able to
stay in the middle of them). Built on 2026-10-14; awaiting the owner's verdict.

- **Stepping on.** After each step of movement `player.gd` `_enter_stairs` asks for the flight
  whose steps hold the slime's feet (`Elevation.flight_at`: stairs, never a ramp). A move at least
  `stairsAlong` (0.35) along the flight's ground direction (`dir`: on a front flight the up or down
  key, on a side flight left or right, on a 45° flight either of its two keys) starts the walk down
  or up it (`PlayerAbilities.begin_stairs`). Partway up a flight (more than a step from either end:
  knocked there, or come on from the side) any move starts it towards the nearer end. A click
  order's route walks onto the stairs the same way.
- **The walk** (`stairs_sequence.gd`, an ability sequence like the jump's) locks actions and
  movement, faces the way it goes, plays the walk clip, keeps the line across the flight it came in
  on (its t, at least 14 units off the side walls) and climbs or descends in footsteps of
  `stairsFootstepMs` (400 ms), each covering `stairsPerFootstep` (2) stairs (4 stairs a level): a
  footstep eases in (smoothstep) under a hop of `stairsStepBob` (3 units) and lands with the
  `StairsStep` cue; then it walks `stairsExit` (22 units) off the end over `stairsExitMs` (160 ms).
  A two-level front flight takes about 1.8 s with 4 footsteps (walking the same 150 units takes about
  0.75 s). The owner tried two paces on 2026-10-14 (climbing should sound slower than walking,
  whose steps are 540 ms apart) and kept this one, footsteps with one hop and one sound each, over
  a hop on every stair with the sound on a pace of its own; the values are the owner's. The body's depth follows the steps (`set_flight`,
  in the flight's frame); its level stays the one it came from until it steps off, then it is
  tracked at the level of that end. The camera follows as usual; the footsteps stay quiet (the walk
  has its own sound).
- **On the way** the slime cannot stop, turn back, attack or use an ability; a hit still hurts but
  does not knock it off (`apply_knockback`). A travel or a death that tears the walk down puts it at
  the far end (`cancel`). A click order waits and plans again from where it stepped off
  (`ClickOrders.resume`).
- **Enemies and NPCs** (owner, 2026-10-14: they "don't walk stairs, they stay in their levels; they
  do walk ramps since it is normal ground"): the collision has a `Stairs` body (under `Collision`)
  on physics layer 19, `stairs` (`STAIRS_LAYER`), holding every flight's `walk` (ramps left out);
  `track` puts that layer in the mask of every tracked body but the player (`PLAYER_LAYER`), so they
  stop at a flight's foot or top and walk ramps as ground.
- **Tuning**: the `elevation` block of `game-constants.json` (`stairsFootstepMs`,
  `stairsPerFootstep`, `stairsStepBob`, `stairsExit`, `stairsExitMs`, `stairsAlong`). The sound (`footstep.stairs`, the `StairsStep`
  player in `game/scenes/audio/global.tscn`) is a stone tap, the owner's pick of six in Sound
  Picker round 6 ([audio spec §10.2](specs/audio.md#102-global-cues-added-effectscue-in-globaltscn)).
- **Probe**: `tools/render_stairs_walk.gd` records the walk in the running game
  ([TOOLING.md](../TOOLING.md)).

### Ramps

**How to paint one** (the owner's U in the cliff shapes lab, 2026-10-11): a level-2 U of single
cells, (42,84), (43,85), (44..53,86), (54,85), (55,84), is a main wall with two 45° arms rising to
tips at (42,84) and (55,84) (a diagonal line of cells is a 45° ridge, Authoring step 3), the west
arm's wall facing south-west, the east arm's south-east. Each arm opens into the ground at its tip:
the ramp tiles go on the lower ground along the **foot of the arm's wall**, the arrow pointing down
along the face towards the main wall: `ramp-se` at (42,87) and (43,88) under the west arm,
`ramp-sw` at (55,87) and (54,88) under the east arm. Two diagonal cells for two levels: the slope
runs from the tip (the top end, at the arm's height) down to where the arm meets the main wall (the
bottom end, on the ground), and the arm's wall tapers from nothing at the tip to its full two
courses there.

A ramp (`elevation_ramp.gd`, 2026-10-11) is a flight of stairs without its stone: the same frame
(s down its direction from its top end, t across, h up), a smooth surface whose height falls
evenly from the top level at s = 0 to the bottom level at its length, no steps, posts or side
walls. `Elevation._build_ramps` makes one ramp of each block of painted cells
(`painted_ramps`: kind `ramp-<direction>`, 8 directions; a cell counts as the ground past its
bottom end, like a stairs cell) and finds what it joins (`_make_ramp`):

- **a rim right behind its top cells** (searched back along the arrow past one wall course per
  level, as stairs find theirs): its top end lies on that rim (front ramps leave a south face like
  stairs and cover the wall there, side ramps leave a side, back ramps a back rim);
- else **the face of a top beside its cells**, searched across the arrow (along the other diagonal
  for a 45° arrow, through the wall) from the cells' middle and a quarter step either way along
  them: its near side is put on that wall's foot (the cells only say roughly where), its top end
  where the face begins when that is within a cell (a 45° tip, a plateau's corner), its bottom end
  where the face turns into another face of the top when that is within a cell (where a 45° arm
  meets the main wall), and the top's level is its top. This is the *Link to the Past* ramp: the
  wall above the slope tapers to nothing at the top end.

Its length runs from there to the far end of the painted cells (or that corner); a ramp that finds
neither is left out with a warning ("leads to no higher ground"). The ramp is part of
`Elevation.stairs` (it extends `ElevationStairs`), so everything that knows flights knows it:

- **Walking.** Its slope is walkable by every level it joins (`walks_level`), except its high end
  (`high_end`: its first `END_BAND`, 32 units of s, more on a back ramp, foreshortened), which
  only the top level walks; the high end stops `HIGH_END_MARGIN` (8 units) before a climbing body's
  front gets there while the body is still of the level below (its reach up the slope from where it
  takes the top level), but never shorter than `HIGH_END_MIN` (8 units), so a steep ramp, one
  diagonal cell per level, climbs without a catch (the U's ramps: 29.9 units). A body there takes
  the level of its height (`level_at`) and its true depth (`depth_at`); a body of a level that may
  not stand where its feet touch the slope (the high end: the feet of a level-0 body walking past a
  tip touch its top corner, beside the wall it meets there) keeps its level (`_physics_process`).
  Along the face beside it, where the wall left between the slope and the top is lower than
  `JOIN_HEIGHT` (20 units), and at least `JOIN_MIN` (44 units) along the slope (a body crossing a
  45° top edge needs about 36), the walk reaches over it to the top's edge: there the ramp and the
  top are one level, and a body climbing the slope walks on onto the top. The rest of the tapered
  face is wall (solid; `ledge_below` finds no ledge where the probe straight ahead of the body meets
  it, so a rim drops normally once the body is past the face's end). A body on the slope below its
  high end stands lower than its level's ground: a wall beside it whose top is higher than the
  slope there (the wall a front ramp cuts through) goes up for `ledge_below`, whatever its level,
  so pushing into it never drops the body.
- **Top end.** A ramp against a rim stands against its top. A free top end (a ramp along a face)
  is that top's rim carried on: the top level is held there and drops over it (`drop_target`),
  lower levels meet it, and the high end, as a wall, so nothing climbs onto a ramp's highest part
  from beside or behind it. A rimmed ramp's top corners reach `EAR` (16 units) over the rim beside
  them, so a body overhanging the slope's side slides onto it there; where a straight front ramp
  cuts through the wall it leaves, the corner of that wall's foot and the slope's side is cut at
  45° (`FOOT_EAR`, 18 units), so a body walking up with its side over the ground beside the slope
  slides onto it instead of stopping at the wall's foot.
- **Open sides.** A ramp has no side wall and no face of its own: what of its long sides faces the
  camera (`skirt`, from the slope's edge down to the ground) is drawn as ground and walked as ground
  of its bottom level; from the high end down (`soft_skirt`) a body on the slope steps onto it, and
  above that the levels over the bottom meet it as a rim. A long side facing no camera (a front or
  back ramp's) has a strip `SOFT_MARGIN` (32 units) wide past its edge, its start cut at 45° from
  the slope's top corner, where a body on the slope may step onto ground of any level from the
  bottom up to its own (`sides`, `lets_off`, `_stairs_rule`). Off the slope a body takes the level
  of the ground there (`_level_off_ramp`, every physics step). So a body walks on and off a ramp
  along its open sides, as the picture says, and the top's own rims stay rims.
- **Drops.** A drop lands on a slope only right where it falls, only below where it started, and
  never on a slope that leads back up to the level it falls from (off the tip of a 45° arm the body
  would land on its own ramp and climb straight back): at the slope's level there; never on the
  slope it starts from, and the search for room passes over slopes (`_landing_level`).
- **Collision.** `_with_stairs` traces it like a flight, with the borders of its slope, its open
  sides' strips, its skirt and the line where its high end begins, and the terrain outlines of the
  other levels it joins (`_ramp_borders`), since it makes their ground walkable; terrain edges as
  far as those outlines reach are traced with it, and a terrain edge that runs on from one ramp to
  another flight is cut by both (`_flights_further`). Every outline stays closed.
- **Drawing.** `Ramps` draws the slope and its skirt with the lower ground's own sheet in world space
  (`elevation_ramp.gdshader`, the 128 px sheet like the ground), after the walls, feet and lips: it
  covers the wall below the slope, the lip's hanging part and the wall's old foot, so of the wall
  only the part above the slope shows, with its own stone courses. Along the face the slope's edge
  fades out over `EDGE_FADE` (10 units), so the lip's hanging tufts and the stone end softly on it.
  A rimmed ramp's landing (`add_landing`) covers its top's lip where it leaves the rim with that
  top's ground, fading out at its sides: the lip breaks there, so the way down reads (the front
  ramp's cut through the wall, the back ramp's gap in the rim). The slope takes the cast shadows at
  its own height (`elevation_cast_shadow.gdshaderinc`, shared with the cast shadows), so the
  shadows of the face and the top beside it grow with the face's height. `RampFeet` lays the lower
  ground's foot along the slope's edge where it runs at the face (only where a wall really stands
  beside the slope, `_ramp_wall_span`: a repainted top may end the wall before the face found for
  the ramp does), squeezed into the face's height
  there (the fern tips end at the face's top however short it is) with its top rows faded out
  (`RAMP_FOOT_TOP_FADE`, `top_fade` in `elevation_fringe.gdshader`), and its ground below the edge
  no deeper than the face is tall, so it starts from nothing at the top end; where the edge climbs
  steeper than 45° on screen (a steep ramp along a 45° face: about 61° for the U) the sweep leans
  towards the face by the excess (16° there), so the art shears no more than along a 45° foot and
  its ferns stay ferns; wall feet the ramp covers entirely are left out. A straight front ramp
  cuts through the wall it leaves: `RampEnds` gives the wall beside it its corner stones there.
  Corner stones under a ramp or on its face (the tip of a taper) are left out.
- **Depth.** The slope and skirt go into the depth map as ground of the bottom level, marked as a
  ramp (`ElevationOcclusion.encode_ramp`, b = 0.875): they hide nothing (the slope reads as flat
  ground). For the cast shadows they are that ground too, except over the wall they cover, where
  they keep their height (g, `add_ramp_depth`): the shadow beside the slope is as long as the
  slope is high there, and the slope's free edges (drawn as ground) cast none.

#### Open ends

A ramp running along a face whose top end lies where that face begins (`at_face_end`: a 45° arm's
tip, the end of a straight face, a plateau's corner) and where the top ends too (`top_ends`,
`Elevation._top_ends_at`: within `RAMP_TOP_REACH`, a cell, of that corner no top lies more than
`RAMP_TOP_BEYOND`, 0.45 cells, beyond the top end; a 45° ridge's square tip reaches 0.35) marks
where the cliff **opens** (`ElevationRamp.opens`, the owner's rule of 2026-10-11): the wall comes
down to meet the ground and the top joins it, instead of turning a corner and closing the shape.
At a plateau's corner the top's side runs on past the top end: the shape stays closed there, and
its rim and shadow stay (the lab's three 45° plateau cases).

- **The wall** tapers to nothing at the end: no corner stones there (`_end_under_ramp`, under any
  ramp).
- **The rim** does not turn around the end: the top's boundary edges beyond the top end (s ≤ 0 at
  the top's height, not along it) whose middle lies within `OPEN_REACH` (40 units) of the end's
  corner are left out of the top's strip (`ElevationRamp.closes`, `Elevation._closes_open_end`, the
  `left_out` filter of `ElevationRims.build`: no strip, glow or depth core there). The lip runs on
  to the end and stops; on a 45° arm the rim along its back runs on to the end too. The **cap**
  covers the strips' ends with ground and fades out (`_cap_triangles`, a grid of 12-unit squares):
  opaque out to `CAP_RADIUS` (56 units) from the corner and from `CAP_BEYOND` (8) beyond the top
  end, clear `CAP_FADE` (16) further out and `CAP_INTO` (16) along the slope. Where edges were left
  out (`cuts_rim`, a ridge's or an arm's tip) the strips end right at the top end: the cap is opaque
  up to `CAP_SOLID` (4) along the slope, just past their ends, and clear at `CAP_INTO_CUT` (40), so
  they fade in from nothing instead of ending on a line. It is drawn with the lower ground, and with
  the top's own ground where it covers the top (`add_cap_top`).
- **No shadow** falls on the ground beyond the end near it (`shadow_take`): none within
  `OPEN_NEAR` (64 units) of the corner, all of it again `OPEN_FADE` (48) down the slope and
  `OPEN_FAR` (160) from the corner. The receivers of the cast shadows and the cap carry it in
  their vertex colour r (`elevation_cast_shadow.gdshader`, `elevation_ramp.gdshader`). Beside the
  slope the shadows of the face and the top fade with the face's height by themselves.
- **Walking**: a body climbing the slope walks on onto the top over the low face at the end (the
  join above); the tapered face stays solid. From the top near the end a body steps back onto the
  slope towards it (down-left on a south-west arm) and walks down it along the face.

Front and back ramps (against a rim) are not open ends: the wall beside a front ramp keeps its full
height and ends in corner stones at the cut.

Paint the tiles on the lower ground, along the wall's foot or out from a rim (Authoring, step 5).
The cliff shapes lab's last rows show each kind, and the owner's U beside them
([Storybook art](#storybook-art)).

Teleport and the Stretch Lash treat ground off the slime's level like a solid tile
(`ability_terrain.gd`). Terrain edges skip corners whose cells have different levels (the cliff
draws its own rims there). Visual only otherwise: the ground cells stay the gameplay truth for
footsteps and water.

## Making the art

All art is generated with Magnific (`gpt-2-mini`, `transparentBackground: true`,
[Magnific guide](../assets/magnific-mcp-guide.md)), saved in `asset/Originals/elevation/generated/`
and turned into runtime textures by `python scripts/art/build-elevation-art.py [name ...] [--preview
DIR]` (numpy, Pillow) into `godot/asset/MAPS/elevation/`.

- **Wall** (1:1): "a seamless tileable texture of a natural stone cliff wall seen straight from the
  front … exactly four horizontal courses … separated by thin dark straight crevices", references:
  the rock props sheet (`asset/MAPS/rocks/96x96-tile_8x3.webp`) and the style sheet. The tool finds
  the crevices, resamples two complete courses to 128 px each and makes them periodic (`WALLS`: the
  source, its courses, whether to even out its light). The other wall styles (2026-10-08) were made
  the same way with meadow rock's source (`wall-rock-a.png`) as the only reference: the style block,
  then "a seamless tileable texture of a <snowy mountain rock / desert sandstone / …> cliff wall seen
  straight from the front, like the reference wall … exactly four horizontal courses of equal
  height, separated by three thin dark straight horizontal crevices … at one quarter, one half and
  three quarters of the height; these crevices are the darkest lines in the image and nothing
  crosses them. <the rock> … Same painting, size of stones, camera and light as the reference",
  two candidates each (`<style>-wall-a.png`, `-b.png`). Masonry needed a second try without the
  reference (it copied the boulders) asking for "a single row of chunky rectangular cut stone
  blocks … laid in a running bond" (`masonry-wall-c.png`, `-d.png`); it came out with about 4.4
  courses, so its entry gives that count. The generator paints the light falling off from the upper
  left across the frame, which would repeat as a bright patch every period: the tool evens it out
  (divides out the brightness averaged over 4 × 4 blocks) for every style but meadow rock.
- **Lip and foot per ground** (2:1): "the straight front edge of a flat <ground> cliff top … ends in
  a <fringe> hanging over the edge … below it fully transparent" and "<ground> … rising into a
  <fringe> against a wall that is not shown … above it fully transparent", references: a 1024 px
  crop of the ground's sheet and the style sheet. In `STRIPS` give each source its edge row (the
  soil band the cliff edge or wall foot runs along), the fringe px kept on the ground side and a
  scale; the tool matches the ground's colours, makes the strip periodic and fades its own ground
  into the real one.
- **Wall ends** (1:1, one per side): "the right-hand (left-hand) end of a natural stone cliff wall
  … the courses end in a vertical column of rounded corner stones that turn away from the viewer …
  beyond the corner fully transparent", with the wall as reference (and the right end for the left
  one). In `WALL_ENDS` give each the source column of the crevice between the wall and its stones,
  or None to let the tool find it (the darkest column 50-230 px inside the art's edge); the tool
  cuts the column, fits its courses to the wall's and matches its colours. The 2026-10-08 ends had
  the style's chosen wall and meadow rock's right end (`wall-corner-b.png`; mirrored for a left end)
  as references: "the right-hand (left-hand) end of a <rock> cliff wall … built of the same stones,
  colours and painting as the first reference image. Composition exactly like the second reference
  image: the wall fills the left (right) two thirds of the frame … the courses end in a vertical
  column of rounded corner stones that turn away from the viewer, two stones per course. Beyond the
  corner the right (left) third of the frame is fully transparent and empty"
  (`<style>-end-right-a.png`, …). Masonry's ends ask for "a chunky cut corner block (a quoin)" per
  course.
- **Stairs** (2026-10-06, the stairs session): rows of cut sandstone with the wall and the old stairs
  as references, `stairs-tread-a.png` (treads seen from above) and `stairs-riser-b.png` (risers and
  copings). In `STAIRS` give each part the source rows of one step, crevice to crevice; the tool
  makes it opaque, periodic and one rise (43 px) tall, darkens the risers and tints the coping
  towards the wall (`<style>-stairs-tread.png`, `-riser.png`, `-coping.png`). Since 2026-10-11 the
  stairs use only meadow rock's three for their grain (the shader takes their luminance and colours
  it by the flight's ground; the coping row makes the blocks of the posts and side walls); the other
  styles' `-stairs-coping.png` (their old railings' caps) are no longer drawn.
- **Cut from a painting** (2026-10-10): `storybook-rock` (wall, ends, coping) and `storybook-grass`
  (lip, foot) are not generated: `python scripts/art/build-elevation-art-from-painting.py
  [--preview DIR]` cuts them from the approved H plateau paintings as aligned by
  `build-cliff-kit.py` (`godot/asset/MAPS/cliffs/kit-h3.png`, `kit-h2.png`): the wall from the clean
  middle course of the three-course painting (two spans, one joint each, joined and made periodic
  through stone faces; the second row mirrored and shifted), the ends from the same course's end
  stones, the lip and foot from the two-course painting's fern bands at 0.75 scale (the stone
  between the hanging plants cut away) ([Storybook art](#storybook-art)).
- The editor's paint tiles (levels, stairs, ramps in row 4, 2026-10-11):
  `python scripts/art/build-elevation-paint-tiles.py`, and for the
  `cliffs` layer `python scripts/art/build-cliff-paint-tiles.py` (a swatch of each wall).

Then let the editor import them. The 2026-10-05 sets (one wall, its two ends, stairs, nine grounds'
lips and feet, with spare candidates) used about 4,300 credits; the eight wall styles of 2026-10-08
(a wall and two ends each, two candidates of everything) 5,000. The rims reuse the lips' art.
A new wall style: generate its wall and ends as above, add it to `WALLS` and `WALL_ENDS`, run the
tool with its name, add it to `build-cliff-paint-tiles.py` `TILES` and a tile in
`cliff_tileset.tres` (the same order), and to `GROUND_WALL_STYLES` if a ground should take it.

`res://tools/render_elevation_park.gd` (windowed: `--path godot -s
res://tools/render_elevation_park.gd -- --out=<dir>`) renders the park's rows and a few close-ups
with the game's own drawing, for checking new art in place.

### Storybook art

The approved H plateau paintings (`asset/Originals/elevation/cliff-concepts/h-plateau-a.png` and
`h-plateau-level3.png`, Magnific GPT 2.5) are aligned by `python scripts/art/build-cliff-kit.py`
(one stone course to a 128 px cell, the outside ground cut away, the colours matched) into
`godot/asset/MAPS/cliffs/kit-h2.png` and `kit-h3.png`; `build-elevation-art-from-painting.py` cuts
`storybook-rock` and `storybook-grass` from them (above). A world uses them through its `ground`
layer's metadata (Inspector > Metadata > Add Metadata, type Dictionary): `cliff_wall_styles` =
`{"highland": "storybook-rock"}` and `cliff_fringe` = `{"highland": "storybook-grass"}`
([Wall styles](#wall-styles)). Limits: the lip and foot ferns are at 0.75 of the painting's scale,
the wall repeats every two stones (536 px), and `storybook-rock` has no tile on the `cliffs` paint
layer yet.

The **cliff shapes lab** (`godot/game/scenes/worlds/cliff-shapes-lab.tscn`,
`world.cliff-shapes-lab`, dev only) shows them: L, T, plus, U from the north and from the south,
joined rectangles, a 1-2-3 terrace, an octagon, a hole, walls of 1-3 courses, a terrace with a flush
front, and in its last rows (69-89) every kind of [ramp](#ramps); beside them (columns 42-55, rows
84-88) the owner's level-2 U, whose two 45° arms open into the ground through ramps. Its builder
`godot/tools/build_cliff_shapes_lab.gd` does not overwrite the lab unless given `-- --force`, which
drops the owner's U and anything else painted there.

## Side walls

> **Experiment (2026-10-13), the cliff sides lab only.** The owner, from a reference screenshot:
> "the cliff in our game does not have side view, only front view ... the game gains a lot when the
> player can identify a cliff right away". The goal: tops that read as raised blocks from all four
> sides, with round corners and walls that are not ruler-straight, in our current art, open cliffs
> included. Target concept (Magnific GPT 2.5, from the H painting and the owner's reference):
> `asset/Originals/elevation/side-walls/concept-d.png` (a-c are the other candidates).
> The owner's first review (same day): "I like how it looks", but the edges were too crowded with
> plants (they want the reference's simple borders: seamless and easy), the inner corners needed
> work, and a back corner whose rim curved into the side wall looked like you could not walk behind
> the hill ("the edge [should] clearly go behind the wall"). Second review: no black wall hint along
> the back edge ("the black border on the top makes no sense"), keep its shadow on the ground, a
> bigger contrast between the ground and the edge, and art for the inner corners. Third review: the
> corner stones and plant tufts tried in the inner corners "suck" ("not a straight wall covered with
> a plant to hide the bad look"): an inner corner is "a continuous seamless curve"; the straight
> band along the top edge was worse than the jagged grass edge; the side strips and corners should
> look like the concept. Fourth review: "I like this version better"; the top's corners a little more
> rounded, and new art for the side strip and corners. Fifth: does it work on other grounds (the
> lab's grounds row), and fix the square corners and stepped shadows seen on a grass plateau on
> sand. Sixth: the side wall should start higher, where the top's round begins, its collision with
> it; collision must follow the drawn walls ("edges that block movement when it shouldn't"); the
> open cliff's fern foot along a ramp no longer fits; level-1 keeps its own stones. All of it is
> what follows.

A world opts in with its ground layer's metadata `cliff_look` = `"sides"` (Inspector > Metadata,
type String; `Elevation.WORLD_CLIFF_LOOK_META`). Its cliffs keep the model, collision, stairs,
ramps, open cliffs and depth of this system; Walls, Feet, Lips, the model's cast Shadows, the
rims' light (`Rims`) and the water at walls' feet (`Water`), which all follow the model's square
cells, are replaced by **Sides** (`game/world/elevation/sides/elevation_sides.gd`, `elevation_sides.gdshader`; no fringe
art, the edges are drawn from the grounds' own sheets):

- **Every side has a wall.** Besides the front (south) wall, one stone course per level as before,
  the east and west sides show a narrow strip of the same wall seen from the side (`SIDE`, 24 units
  for one level, growing as the drop to the power `THIN_GROWTH` (0.7), so a tall side stays a strip:
  39 units for two levels, 52 for three). A back (north) edge shows no wall at all: the side's reach
  fades out as the normal turns north (`BACK_FADE`); its edge keeps its grass clumps, outlined in a
  dark green (`back_outline_colour`) instead of the walls' brown, and a shadow on the ground behind
  (`backness`). The west strip is lit, the east one in shade (`shade`). A side strip shows a single
  column of short rounded stones, as in the concept, whatever its height: one course across its
  width and the stones `SIDE_U_RATE` (2.6) times shorter along it (`side_of`), in the style's own
  side art (`<style>-side.png`, below) where it has one. Round a front corner the courses keep
  wrapping as the front's and merge into that column over `SIDE_RAMP` (56) units along the side
  (`_side_ramps`; the side art blends in by the same measure, vertex colour r). Over every front
  corner each course turns on a big rounded stone of its own (`_add_corner_stones`, the style's
  `<style>-corners.png`, one of `CORNER_STONES` (4) picked by place), `CORNER_LENGTH` (72) units long
  along that course's middle line and centred on the corner, so it has the same proportions at
  every height. Holes get the same: their inner side walls show, the far one as a
  front wall.
- **Round, wobbling edges.** A top's border (ElevationRims.boundary_edges, the top on the left) is
  chained per level, its corners rounded (`RADIUS_OUTER` 40, `RADIUS_INNER` 20 units, smaller where
  the runs are short) and resampled every `STEP` (6) units; corners are sampled finely so the walls
  turn smoothly. The top edge wobbles by up to `TOP_WOBBLE` (3.5) units and the foot by
  `FOOT_WOBBLE` (4), from a noise fixed in world space (repainting elsewhere changes nothing).
- **Back corners.** A front corner's wall turns smoothly onto the side. At an outer corner of a back
  edge and a side (`_is_back_corner`) the top's corner rounds with `RADIUS_BACK` (34) and the side
  wall starts where that round begins (the back edge's end), from nothing, widening `CAP_SLOPE` (0.65) per
  unit along the side to its full width (`_caps`): a slanted end, past which the back edge visibly
  runs on behind the wall, so the ground behind the hill reads as walkable (it is: the strip behind
  a hill).
- **Inner corners fold.** At an inner corner of a side and a front or back wall
  (`_is_side_inner_corner`; the top turns with `RADIUS_FOLD`, 14) the two walls are one wall folding
  round, as in the owner's reference: over the stretch of border round the corner (the other wall's
  reach plus `FOLD_RUN` (56) units each way, less where the runs are short) every fibre runs to the
  point as far along the foot's path (`FOLD_RUN` along one wall's foot, round a corner of
  `FOLD_FOOT_RADIUS` (28) where it meets the other's, on along that), so the fibres turn from
  straight down to straight out without crossing and every stone course runs on round the corner
  (`_fold_corners`); the light turns with them, and the feet there keep to the path (no wobble).
- **How a wall hangs.** From each point of the border a "fibre" runs to the foot along the point's
  outward normal, as far as the shape K reaches that way (`reach`: `FRONT` 64 per level down, the
  side and back reaches out and up, a superellipse of exponent `SHAPE` 2.5 between them). The wall
  art runs along the border (u, measured `U_DEPTH` (0.6) down the fibres so the stones keep their
  width where the fibres fan out at a corner; a loop is stretched to close on whole periods of the
  art) and down the fibres (v, a course per level). A wall something stands in front of (a cut band)
  ends where it does.
- **The style's side art.** `python scripts/art/build-side-wall-art.py [--style S] [--source PNG]`
  builds `<style>-side.png` (four rounded stones side by side on a joint's dark, a course tall,
  periodic) and `<style>-corners.png` (the same stones on transparency) in
  `godot/asset/MAPS/elevation/` from a Magnific sheet of four rounded stones
  (`asset/Originals/elevation/side-walls/corner-stones-a.png`, GPT 2.5 with the style's wall and
  concept-d as references), colour-matched to the style's wall art. Only `storybook-rock` has them;
  a style without them draws its sides and corners with its wall art (`Elevation._sides_material`).
- **Corner fills.** Between a corner's arc and the model's square corner the ground is the model's:
  past an outer corner the top's square cell would poke out past the round edge, inside an inner
  one the lower ground would show. `_add_corner_fills` draws the lower ground there (outer) or the
  top's (inner), first in the level's mesh. The top edge wobbles outward only, for the same reason.
- **Shadows.** The model's cast shadows are left out (they step along the square cells); the foot's
  shadow casts instead: `FOOT_OUT` (20) units past the foot plus `SHADOW_PER_LEVEL` (22) per level
  of the wall there, as the foot faces east (`SHADOW_EAST` 1) or south (`SHADOW_SOUTH` 0.3), so a
  hill throws a round shadow to the lower right, longer for a taller one, and none past a back
  corner's slanted end. A back edge keeps a short shadow on the ground behind.
- **Water.** Where the ground at a wall's foot is water (`_ground_below`) the foot is a band of
  foam lapping at the wall (`KIND_FOOT_WATER`, or `low_is_water` for a whole mesh; `foam_colour`;
  presentation time), and an outer corner beside water stays nearly square (`RADIUS_WATER`, 3): a
  round one would need the moving water surface between it and the model's square corner.
- **Simple edges, drawn.** Along the top edge (a piece from `EDGE_IN` (12) units over the top to
  `EDGE_OUT` (9) past the edge) the top's own ground (its sheet in world space, as the ground draws
  it: no seam) darkens over its last `band_width` (12) units (`band_shade` 0.22) and hangs a little
  over the wall in round clumps of two sizes (`overhang_front` 2.5 units plus up to `clump_height`
  4.5; less on sides), with a dark warm outline (`outline_width` 3) along them. Along the foot (`FOOT_UP` (7) up
  the wall, `FOOT_OUT` (20) over the ground) a few clumps of the lower ground grow up the wall's base
  under a dark line (`foot_outline`), and the ground takes a soft shadow, stronger facing the lower
  right (the clumps darken with it), fading out before a ramp's slope (`under_ramp`: the slope is
  drawn over it and would cut it on a line). These are uniforms of `elevation_sides.gdshader`; on a
  ground darker than `DARK_GROUND` (0.32, its average colour's value) the top edge's outline is a
  light rim of the ground's hue instead (`_sides_material`), the foot's line stays dark
  (`foot_line_colour`). The strip
  takes its way from neighbours `FOOT_SPAN` (8) units apart and shrinks where its offsets would
  cross, so it never folds over itself (its shadow would double there).
- **Painter's order.** One mesh per level, wall style and pair of grounds (the top's and the lower
  one, the most common along each chain), lowest level first; inside it every piece is drawn by the
  screen y of the border point it hangs from, so where faces overlap (an inner corner) the nearer
  face covers the farther one. A top edge is drawn `EDGE_LEAD` (8) and a foot `FOOT_LEAD` (24) units
  of depth later than its wall, so they stay over the walls they belong to.
- **Collision follows the drawing.** The model's cells are square and its walls hang only below
  front edges, so in this look each level walks by the drawn shapes (`ElevationSides.shapes`: per
  chain its wall polygons, from the smooth border to the foot, and the zones between each round
  outer corner and the model's square corner). `_terrain_walkable` (used by `is_walkable` and the
  collision tracing) asks the model, then `_sides_walkable`: a top's own level stops at its round
  corners (the zone past one is not walkable); a level below it cannot enter a drawn wall (a side
  strip stands on ground the model calls walkable), and where the model blocks it for that top (the
  zone past a round corner, the model's wall below the drawn foot) it is the ground below the wall
  (`_below_at`). Stairs and ramps decide first (`_stairs_rule`). Where a drawn wall's uneven foot
  dips under the bottom step of a front flight (up to `STAIRS_FOOT_SLACK`, 12 units), that strip is
  the ground the flight starts from (`_at_stairs_foot`; as wall it closed the foot of most of the
  lab's flights to their lower level until 2026-10-14). `_with_sides` then traces each
  level as `_with_stairs` traces flights: near the tops, the model's outline, the borders and the
  walls' outlines are cut where they cross (`_split_all`, `SPLIT_BUCKET` buckets) and each piece is
  kept where it parts walkable from blocked ground, so the collision runs along the drawn feet,
  side strips and round corners; the strip behind a hill stays open. A ledge push off a round corner
  finds the ground below there (`_lower_level_at`). Each border is simplified once
  (`SHAPE_TOLERANCE`, 0.5 units, keeping corner ends and where walls start or end, `_kept`) and its
  walls, zones and edges all take its points, so every test agrees with the line its pieces are cut
  along; the walls' feet are simplified the same. Shapes are looked up by place (`_side_cells`,
  `SHAPE_CELL`). Load (2026-10-14, desktop): level-1 0.74 s in all (0.5 s with front walls only;
  the sides' collision about 0.15 s), the lab 1.7 s (its collision 0.38 s, its side drawing about
  0.4 s over the front look's).
- **Open cliffs** keep their rules: the edges left out at an open end or along a one-row open
  cliff's back (`left_out`) get no wall either, so no side wall stands where the cliff opens into the
  ground. Its inner sides neither (owner, 2026-10-14: "when the structure is an open cliff ... do
  not paint the inner wall"): the lower ground right behind the cliff's cells, and what joins it
  inside the cliff's bounding box, is the ground it encloses (`_find_open_inner`, `_open_inner`; an
  L of single cells encloses the ground behind its row), and a side of the cliff facing it is left
  out like its back (`_is_inner_side`); its outer sides keep their walls. A ramp's slope covers the
  wall below it as before, but its edge along the face is hard (`ElevationRamp.hard_edge`, no
  EDGE_FADE band, at `edge_t`), so the tapered wall's stones stay whole up to it, and the foot line
  along the slope lies on that edge, where the stones end (fading in over `SIDES_RAMP_FOOT_FADE_IN`,
  6 units of face, at the top end). Along the slope's edge at the face the
  foot is the same dark line and clumps as every wall's, with a short shadow on the slope
  (`_add_sides_ramp_foot`, `SIDES_RAMP_FOOT_OUT`, `SIDES_RAMP_FOOT_SHADOW`), fading in from nothing
  where the face does, instead of the fern foot (RampFeet).

**The cliff sides lab** (`godot/game/scenes/worlds/cliff-sides-lab.tscn`, `world.cliff-sides-lab`,
dev only; F6, or `?map=cliff-sides-lab`) shows the owner's reference shape (a notch and a step),
blocks of 1, 2 and 3 levels (one with a front flight), an L, U shapes from the north and the south,
an octagon, a 1-2-3 terrace, a hole, the owner's open U with ramps, ramps along a south face and a
diamond; below them (rows 52-80) the grounds row: a level-2 plateau with a step on snow, sand,
forest floor, forest moss, fallen leaves, cavern, crystal and cobble (each top takes its ground's
wall style, `GROUND_WALL_STYLES`), then grass on sand, sand on grass, snow on grass and grass in
water. `godot/tools/build_cliff_sides_lab.gd` builds it (it does not overwrite the lab unless
given `-- --force`). Set the ground layer's `cliff_look` to anything else to compare with the
front-only look. `res://tools/render_cliff_sides_lab.gd` (windowed: `--path godot -s
res://tools/render_cliff_sides_lab.gd -- --out=<dir> [--only=<name prefix>] [--look=front] [--collision]`)
renders it with the game's drawing, whole and in close-ups at the art's resolution, with each
level's collision outline on request.

Limits (2026-10-13): round a front corner the wall's own courses still fan under the corner stones
and merge into the side's column past them (a 3-level corner shows thin wrapped courses for a
moment); only `storybook-rock` has side and corner art; the lab's walls are `storybook-rock` only;
styles other than `storybook-rock` draw their sides and corners with their wall art; a shadow strip
cast over a lower top does not climb the walls standing on it; a chain's edges use one top and one lower ground (a
plateau standing on two grounds draws its foot's clumps in the commoner); edges over ground in a cast
shadow are not shaded by it (the foot's clumps are darkened to match instead); inside a concave round corner the drawn
top bulges a little past the model's top, which the top's level cannot walk; the sides look's
collision is checked from renders of its outlines only (no walking probe or test yet); about
300,000 vertices for the lab, not yet measured on the web.

## Baked cache

(2026-10-14, at the owner's request: load time.) Building a world's elevation takes time (level-1:
the drawing about 260 ms and the collision about 110 ms of a 600 ms world load, desktop) and only
changes when its painting does, so a game build saves what it makes and later loads it instead:

- **What is stored** (`game/world/elevation/elevation_cache.gd`, one `ElevationCache` per world
  scene in `res://game/scenes/worlds/elevation_cache/<path under worlds/, "/" as "__">.res`,
  `Elevation.cache_path`): every drawing group's meshes in order, each with the key its material is
  made from (`_material_for`; materials hold textures and the live depth map, so they are made at
  load), the depth map's mesh and rect, the sides look's shapes (for walking) and each level's
  collision segments. The model (`ElevationGrid`), the stairs and ramps, the open cliffs and the
  fences are still built at load (about 50 ms for level-1): gameplay queries need them.
- **When it is used** (`_load_cache`): a game build (`mount(..., collide = true)`; the editor's
  live preview never uses it) loads the cache when its `key` matches: a hash of the `elevation`,
  `ground` and `cliffs` layers' cells, the ground's metadata (`cliff_look`, `cliff_wall_styles`,
  `cliff_fringe`, size), the elevation settings and `CACHE_VERSION` (`_cache_key`). In a debug run
  from the project it also must have been baked with the current sources of `CACHE_SCRIPTS`
  (`_code_hash`), so changing the build code rebuilds it there; an exported game trusts it. Else
  the world builds as before.
- **When it is written**: `"<Godot console exe>" --headless --path godot -s
  res://tools/bake_elevation.gd [-- --world=<id>[,<id>...]]` bakes every world of
  `scene_index.json` that paints elevation (`Elevation.ignore_cache`); and a game run from the
  project (F5/F6, not headless, not a tool script) saves the cache of any world it had to build
  (`_saves_on_its_own`). Commit the files; the release export ("Web") leaves out the dev worlds'
  caches with their scenes.
- **When to bake by hand**: after changing elevation art (a wall's width changes its meshes' UVs)
  or a ground's tiles, which the key does not see; bump `CACHE_VERSION` when what the build makes
  changes in code outside `CACHE_SCRIPTS`.

Measured (2026-10-14, desktop): level-1 loads in 233 ms instead of 600 ms (cache 278 KB), the
cliff sides lab in 385 ms instead of 1.7 s (2 MB). A cached and a freshly built level-1 render the
same cliffs and the same collision.

## Why this approach (what other games do)

- **Tile priority** (*A Link to the Past*, *Minish Cap*): the top row of a cliff's tiles is drawn
  over the hero, who can step a few pixels behind it. Cheap, but the overlap is the same for every
  height and only works on straight tile edges.
- **A layer per level** (many tile games, Godot tutorials): each level on its own layer, bodies
  sorted by level. Walking behind works, but how far does not follow the height, and props on
  different levels sort wrongly.
- **True heights** (*CrossCode*, *Eastward*): every point has a height, collision and drawing come
  from it, hidden characters show as a silhouette. Works for any shape and height; costs a depth
  pass. **This is what Slime Isa does** (ground model + depth map + ghost), keeping the map
  authored as the camera sees it.
- **Fading the thing in front** (roofs and tree crowns in *Stardew Valley* and many others): the
  occluder turns see-through around the hero. It suits props with something drawn behind them. A
  hill here is authored as the camera sees it, so nothing is drawn behind its top (those cells are
  the top): fading it would only show the same ground fainter, and would need back and side walls
  that the camera cannot see. Slime Isa fades the hidden part of the body instead.
- **Ledges** (*A Link to the Past*, *Minish Cap*): a ledge holds the hero, a push hops him off and
  he lands below. Slime Isa does the same at every rim, landing where the picture says he falls.
- **Real 3D** (*Octopath Traveler*, the 2019 *Link's Awakening*): sprites in a 3D scene.
  Everything comes for free, but it would be a rewrite of the renderer.

## Limits and next steps

- Every ground with terrain edges has its lip and foot. A new ground needs both (about 400 credits),
  else it falls back to its thin terrain edge rims.
- Only bodies (player, enemies, NPCs, and what is parented to them, like the swung weapon) hide
  behind hills. Props, effects, projectiles and loot do not: do not place props in the strip behind
  a hill. Two bodies on different levels that overlap on screen sort by their feet only.
- Depth and shadows use a 2-unit grid: their edges step by 2 units (hidden under the rims' tufts).
  Measured at about 1 ms a frame in the park on the owner's desktop GPU; phones are not measured.
- Two wall styles side by side meet on a straight vertical line (no corner stones between them).
  Every flight is the same stone in its ground's colour, whatever the cliff's style; the colour is
  an average, so a ground of strong contrasts (crystal, cobble) gives a plain stone.
  Masonry on a one-level wall shows a single row of large pale blocks with faint joints; the
  generated wall styles still await the owner's verdict (2026-10-08).
- A side or back flight needs room on the lower ground: one that runs into another hill or a
  hole is built anyway and looks wrong. Two flights side by side along one rim must share a kind to
  be one; two of different kinds that touch work but each keeps its own posts.
- A side flight is a heavy block beside the hill (its near side wall shows as a triangle of blocks
  from the steps down to the ground), and a 45° back flight's side walls read as level bars: the
  camera sees them that way. Front flights, set into the wall, are the light ones.
- On a side or back flight a body's depth follows the steps' nosing line, not each step: it may
  float or sink a few units against a tread (a quarter of a level at most). On a front flight it
  stands on the face, at the height it is drawn at.
- A body on a flight's steps may reach a little past its ends (`overhang`): a lower level's body
  stands with its top half over the hill's top for a moment as it climbs a 45° front flight.
- A body may stand behind a flight where the flight only hides it (its footprint at the body's
  level blocks it, not its picture): there is no cap like the strip behind a hill.
- Only the player changes level (the stairs walk, ledge drops, and the hidden jump off a rim) and
  only the player uses stairs: enemies and NPCs stop at them (`STAIRS_LAYER`) and walk ramps.
  Enemies collide with their level but neither drop nor find a way off it. Projectiles, melee reach,
  sight, interactions and spawns do not know levels yet. These are the next gameplay steps (the
  old branch's rules, archived in [ELEVATION_LEVELS.md](../archive/phaser/ELEVATION_LEVELS.md), are a
  reference, not a plan).
- The stairs walk keeps the line across the flight it stepped on at and runs straight along the
  flight whatever the keys (on a 45° flight either of its keys climbs it). A body knocked partway up
  a flight stands there until it moves (then it is carried to the nearer end). An enemy chasing the
  player up the stairs waits at their foot.
- A drop off a back rim lands in the capped strip, nearer the rim than a real fall would; a side
  rim shows no wall, so a fall beside a hill drops past plain ground.
- Ramps (2026-10-11, the cliff shapes lab only): a ramp's long sides are open ground, so a body
  walks off a high part of one onto the ground beside it with no fall (the illusion, as in *A Link
  to the Past*); nothing draws a raised ramp's own side (no causeway). Stepping onto a slope from
  its open side right where its level changes may take the level above for one physics step
  (0 → 2 → 1 on the U's ramps); nothing reacts to the change, only to the current level. A free top
  end is a rim with nothing drawn on it: the slope there reads as plain ground, yet a body is held at
  it and drops, and from below it is a wall: a level-0 body walking past an arm's tip slides along
  an invisible wall of up to a cell where the slope's top end is, and pressing straight down at the
  tip's corner it stops between that wall and the end of the strip behind the arm, as at any wall
  corner (its feet touching the slope's corner no longer lift it to the top). The join with the top
  beside a ramp is only where the face is lower than `JOIN_HEIGHT` (at least `JOIN_MIN` along the
  slope), and a 45° ridge of single cells is about 45 units wide, so a body (30 units) has little
  room between the slope and the arm: pressing straight down from the arm near its tip catches on
  the face's corner where the join ends (pressing towards the slope steps onto it), turning along
  the arm before the slope's top end slides back down it, and from the arm's middle pressing
  towards the face does nothing (no ledge drop over a tapered face, and a drop never lands on the
  slope it would climb straight back up; a one-row open cliff's tapered face does drop). The way down from an arm is to its tip, then along the
  face. 8-way keys do not follow a slope: pressing along a ramp's direction drifts off its open side
  (holding towards the face or the tip climbs it; down the slope, hold towards the face). On the
  storybook art the lip's hanging ferns cover most of a steep 45° taper's face, and the foot along a
  steep slope leans towards the face (16° on the U). A ramp is drawn after every lip and wall, so a
  higher hill in front of one is not drawn over it (only tops of its own level and higher hide it):
  keep ramps clear of other cliffs. A ramp must run along one face (or leave one rim): the snap to a
  face reads the wall beside its cells, and a 45° ramp along a straight face (or the reverse) does
  not taper right; a ramp that finds neither is left out with a warning. Breaking a top's strip at
  an open end restarts its art along the whole strip (the tufts fall differently, as after any
  repaint). The open end's cap and shadow cut are drawn around the corner whatever lies there, and
  the cap off the top is the ramp's own ground: keep other cliffs and other grounds a cell and a
  half from an open end. Only a straight front ramp gets corner stones where it cuts a wall, and
  the 45° cut at its sides. Paths (mouse orders) walk up and down ramps but never off their open
  sides.
- A top narrower than its lip's inner reach (`IN`, 48 units, elevation_rims.gd) draws its rim's
  inner art twisted where the strip turns around a short edge: a 45° ridge's closed tip (a diagonal
  line of single cells without a ramp) shows wedge-shaped tuft pieces. The same happens wherever a
  short edge meets a convex corner of a strip (17 places in the playground); a fix changes the lips
  of 10 worlds, so it awaits the owner (2026-10-11).
- Waterfalls, ladders and pits are not built. Water only laps at a wall's foot: a hill's
  rim beside water (no wall) gets the usual shore tiles of the terrain edges where it is flat.
- The level light only darkens holes; hills are not lightened.

## Files

| Path | What |
|---|---|
| `godot/game/world/elevation/elevation_grid.gd` | The model: tris, chamfers (45° edges and ridges), walls, the 3D ground, walkability, collision segments |
| `godot/game/world/elevation/elevation.gd` | `Elevation`: mount, drawing, collision bodies (stairs merged in), body levels, drop and hop targets, jump flights (`@tool`) |
| `godot/game/world/elevation/elevation_stairs.gd`, `elevation_stairs.gdshader` | A flight of stairs: geometry (set into a face, or running out), walkable surface and the way past its ends, silhouette, levels and depth along it, faces back to front, occlusion by the hill; the shader draws the steps, posts and side walls in the flight's colour |
| `godot/game/world/elevation/elevation_ramp.gd`, `elevation_ramp.gdshader` | A ramp (a flight without stone): its slope, the join over a low face, the high end, open sides (strips, skirt), the tapered face, an open end (the rim left out, the cap, no shadow beyond), a rimmed ramp's landing; the slope drawn as its ground with the shadows on it |
| `godot/game/world/elevation/elevation_cast_shadow.gdshaderinc` | The cast shadows' lookup through the depth map, shared by the cast shadows and the ramps |
| `godot/game/player/abilities/jump_sequence.gd` | The flight of a jump or a ledge drop (`player.gd` `_press_ledge` starts a drop) |
| `godot/game/player/abilities/stairs_sequence.gd` | The [stairs walk](#stairs-walk) (`player.gd` `_enter_stairs` starts it) |
| `godot/game/world/elevation/elevation_rims.gd` | Every top's border as one chained strip (lips, rims, round corners), glow and depth cores |
| `godot/game/world/elevation/sides/elevation_sides.gd`, `elevation_sides.gdshader` | The sides look ([Side walls](#side-walls)): walls on every side of a top, round front corners, slanted back ones, folded inner ones, wobbling borders, simple drawn top edges and feet in one painter's-order mesh per level, and the blockers of the side strips |
| `godot/game/world/elevation/elevation_occlusion.gd`, `elevation_occlusion.gdshaderinc` | The depth map and the bodies hidden behind higher ground (included by `game/feel/hit_flash.gdshader` and `game/player/gulp/form_skin.gdshader`) |
| `godot/game/world/elevation/elevation_mesh.gd` | Mesh data the builders fill |
| `godot/game/world/elevation/elevation_cache.gd`, `godot/game/scenes/worlds/elevation_cache/` | The baked cache of each world's elevation ([Baked cache](#baked-cache)) |
| `godot/tools/bake_elevation.gd` | Bakes the caches |
| `godot/game/world/elevation/elevation_layer.gd` | The painted layer: hides itself in the game, previews the cliffs in the editor (`@tool`) |
| `godot/game/world/elevation/elevation_tileset.tres`, `elevation_paint_tiles.png` | Paint tiles: levels −3 … 3, stairs in 8 directions (two rows, once a railed and an open landing; since 2026-10-11 the same flights), ramps in 8 directions (`elevation_level`, `elevation_kind`) |
| `godot/game/world/elevation/cliffs/cliff_layer.gd`, `cliff_tileset.tres`, `cliff_paint_tiles.png` | The `cliffs` layer: wall styles painted over tops (`wall_style`; tiles by `scripts/art/build-cliff-paint-tiles.py`) |
| `godot/game/world/elevation/*.gdshader`, `elevation_light.gdshaderinc` | Wall, wall end, fringe, strip, water foot, ground, shade, cast shadow and glow shaders |
| `godot/asset/MAPS/elevation/` | Tool output (`scripts/art/build-elevation-art.py`; `storybook-*` by `scripts/art/build-elevation-art-from-painting.py`) |
| `asset/Originals/elevation/generated/` | Generated sources |
| `asset/Originals/elevation/stairs-mockups/` | The stairs design of 2026-10-06 (landings, railings; replaced on 2026-10-11): spec (README.md), renderer, mockups |
| `scripts/maps/build-elevation-park.py` | Builds the park in the playground (levels, stairs, its `cliffs` paint) |
| `godot/tools/render_elevation_park.gd` | Renders the park's rows and close-ups with the game's drawing |
| `godot/tools/build_cliff_sides_lab.gd`, `render_cliff_sides_lab.gd` | Build and render the cliff sides lab ([Side walls](#side-walls)) |
| `godot/tools/render_stairs_walk.gd` | Records the [stairs walk](#stairs-walk) in the running game |
| `asset/Originals/elevation/side-walls/` | The side-wall concepts of 2026-10-13 (concept-d the target), two inner-corner concepts, and the side art's sources (`corner-stones-a.png` used; `-b`, `side-strip-a/-b` candidates) |
| `scripts/art/build-side-wall-art.py` | A style's side strip and corner stones for the sides look ([Side walls](#side-walls)) |
| `godot/tests/test_elevation.gd` | Shapes, holes, a flight's geometry and levels (set into a face, running out, the way past its ends), stairs on every side (posts and side walls, no landing, hidden parts), every showcase flight walked through both ends, climbing and walking up a side flight (the stairs walk: its time, a step sideways halfway carried to the foot), enemies kept off every flight, stairs coloured by their ground, the capped strip, closed collision outlines (stairs included), the park's walls in every style (painted or by ground), wall ends, water foot, lips, shadows, stairs, drop and hop targets on every shape, a rim that holds then drops (a square and a diamond), sliding down a back face past a tip, walking behind a hill and the ghost |
