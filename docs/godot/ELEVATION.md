# Elevation: hills, holes and ground levels

> **Status:** first version, 2026-10-05, in the playground only (the **Elevation Park**, rows
> 28-121 south of the old playground). No real world uses it yet. The owner asked to retake
> elevation after the Phaser-era attempt (branch `feat/elevation-levels`, not merged) failed on
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

## What you see

A raised area is drawn where it is painted. Below its south-facing edges hangs a rock wall, **one
stone course (one cell, 64 units) per level of drop**, so a 3-level wall shows three courses with
their joints lined up across every face. The higher ground's **lip** (grass tufts, soil and roots;
a snow cornice with icicles; a crumbling sandy edge) hangs over the wall's top; the lower ground's
**foot** (tufts and ferns, a snow drift, a sand drift) grows up its base. All nine grounds have
their own (grass, snow, sand, forest soil, moss, fallen leaves, cavern rock, crystal rock, cobble
with a curb). The same tufts run around the **whole top** as one strip: over the walls they hang
with their soil and roots, along the north, east and west rims (and a hole's near rim) only the
tufts show, and they turn every corner in a round curve. Where a wall ends, a column of rounded
**corner stones** finishes it (lit on a west end, shaded on an east end). Where a wall stands in
**water**, the water line laps up and down the rock in a travelling wave with a band of foam,
leaving the rock above it dark and wet. Raised ground **casts a shadow** to the lower right (the
light comes from the upper left): along a hill's east side and in a thin band at its wall's foot,
three times as long for a level-3 hill as for a level-1 one, none on the lit north and west sides;
a hole's west rim shades its floor. Rims facing the light catch a thin light along their edge.
Faces are shaded by the way they look (south-west lit, south mid, south-east dark). The ground of a
hole and the lower courses of its walls darken with every level of depth.

**Stairs** are stone flights that leave a rim in any of 8 directions: a landing on the higher
ground, 3 steps per level down onto the lower ground, railings on both sides with a newel post at
each end (flush with the walkway, standing proud on the outside only), in sandstone with railings of the cliff's own rock (approved mockups:
`asset/Originals/elevation/stairs-mockups/`). Front flights run out a cell per level past the wall
(45°), side flights a cell per level beside the hill (seen from the side), back flights are
foreshortened (north 1.5 cells per level, 45° ones a diagonal cell) and what of them lies behind the
hill's top is hidden by it. A flight is one or two cells wide, its landing railed (entered from its
far end) or open (railings start at the rim, posts in front of the wall).

**Behind the hills.** A hill hides the ground right behind it: from the north, a body can walk
`behindDepth` (32 units on screen) into a hill's top, and the hill covers what of it is behind; a
body in a hole walks as far under its near rim. The depth is the same for every height (in 3D it
would be 64 units per level, which buries the slime behind a tall hill); what shows of the body
still follows the height. The hidden part of a body shows as a **ghost**: its own colours tinted
blue and see-through (the player at 0.6, enemies and NPCs fainter at 0.35). East and west sides
hide nothing (the camera looks north).

**Moving between levels.**

- **Stairs** join two levels; a body takes the level of the stretch it stands on (the landing is
  the top level, the last step the bottom one) and its railings hold it on the steps.
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
  wall, from the strip behind a hill into the hill, or off stairs (their railings are solid).
- **The jump** is a low hop (`hopArcHeight` 36 units, below one level) that **never climbs**: it
  stops before higher ground and walls, and over a rim it drops to the lower ground, landing as far
  out as the hop carries it. Without elevation it is Phaser's jump.
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
flights two cells wide and open landings.

## Authoring

1. Give the world an `elevation` TileMapLayer beside its ground layer (same grid), with the tile
   set `game/world/elevation/elevation_tileset.tres` and the script
   `game/world/elevation/elevation_layer.gd`.
2. Paint the **top you walk on** with a level tile (−3 … 3; unpainted cells are level 0). The wall
   appears by itself below the area's south edges and covers the cells there: leave as many free
   rows below a south edge as the levels it drops. A hole is painted the same way with a negative
   level; its far wall covers its first rows.
3. Shapes come from the steps of the paint: **single-cell steps make a straight 45° edge**, steps
   of two cells or more keep a square corner. A staircase of single steps is a diamond's side; a
   rectangle with its corners cut by single steps is an octagon.
4. Paint **stairs** with the arrow tiles (row 2 of the palette: railed landing; row 3: open
   landing; the arrow points down the stairs) on the **first cell past the rim**, on the lower side,
   in the flight's direction: below a south edge the wall's first row, beside a side the cell next
   to it, north of a back rim the cell above it, at a 45° rim the lower cell whose corner the
   chamfer fills. Two such cells side by side along the rim make one flight two cells wide. The
   flight joins the higher ground behind the cell to the level of the cell (the ground it leads
   down to) and needs room on that ground: a cell per level beyond the wall (front, sides, 45°),
   1.5 cells per level to the north, keep other hills out of it. The old `S` tile is a front flight.
5. The ground on top and below is the ground layer's: paint sand on a plateau and its lip is sand.

In the editor the cliffs follow the paint at once (the layer's script mounts the drawing under the
ground layer, never saved with the scene); hide the `elevation` layer (eye icon) to see the result
without its numbered squares. The game hides the layer.

`scripts/maps/build-elevation-park.py` builds the park and is the worked example; it rewrites the
playground's park rows, so hand edits to the park are lost when it runs again.

**Fences** that stop the player dropping off a rim are painted on their own `fences` layer and
documented in [FENCES.md](FENCES.md).

## How it works

`WorldService.register_world` calls `Elevation.mount(ground, true)` after the water and the terrain
edges: `game/world/elevation/elevation.gd` adds the node `Elevation` under the ground layer, builds
the model and draws it.

**The model** (`elevation_grid.gd`, pure data). The map is authored as the camera sees it. Every
cell is split into 8 triangles ("tris"): its 4 corner triangles and the 4 quarters of its centre
diamond, which meet on the 45° lines. A **chamfer** gives a corner triangle the level across the
corner where a convex corner and a concave one form one step of a staircase (they pair along the
45° line), so single steps become straight diagonal edges and lone corners stay square.
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
how far below a wall's top edge; then the stairs' faces at their height, marked as a structure
(the cast shadows read its height, level − dy / 64). The body shaders (`hit_flash.gdshader`
on enemies and NPCs, `form_skin.gdshader` on the player) read it: a pixel whose terrain is nearer
than the body's feet (feet y + 64 · level) by more than 12 units is drawn as the ghost: its colour
mixed 45 % with the blue tint, at `elevation_silhouette` opacity. Every physics step `Elevation` sets
each tracked body's depth and ghost opacity on its sprites' materials (sprites without one get the
neutral hit-flash material); a body in the air (`set_flight`) gets the depth its flight gives it.

**Cast shadows** (`elevation_cast_shadow.gdshader`): drawn over the ground up to two cells right of
and one below anything higher, before the walls. Each pixel looks back towards the light along
three rays through the depth map for ground high enough to shade it (`SHADOW_UNITS` = 20 units of
shadow per level), so shapes, corners and heights all come out right without per-edge pieces.

**The drawing** (children of `Elevation`, bottom to top; all world-space, so nothing has seams):

| Node | What | Art |
|---|---|---|
| `Patches` | chamfered corner triangles that take the ground across the corner; the top's ground over the water surface's soft edge along a rim over water | the ground's sheet (`elevation_ground.gdshader`) |
| `Shade` | the ground of holes, darker per level of depth | multiply (`elevation_shade.gdshader`) |
| `Shadows` | what raised ground casts on lower ground | multiply (`elevation_cast_shadow.gdshader`, reads the depth map) |
| `Walls` | covered tris, UV = (world x, depth below the top edge + the course of the top level), shaded by face; corner stones at every wall end (beside lower ground) on the wall's own UV | `art/<style>-wall.png` (`elevation_wall.gdshader`), `art/<style>-wall-end-right.png` / `-left.png` (`elevation_wall_end.gdshader`) |
| `Rims` | the light a rim facing the upper left catches | vertex colours, `elevation_glow.gdshader` |
| `Water` | water at the foot of walls standing in water: the water surface's own maths sampled in front of the wall, its line lapping up the rock, foam, wet rock | `elevation_water_foot.gdshader` (shares `water_surface.gdshaderinc`) |
| `Feet` | the lower ground's foot along each wall foot | `art/<ground>-foot.png` (`elevation_fringe.gdshader`), else the ground's terrain edge tiles |
| `Lips` | every top's border as one strip (`elevation_rims.gd`): lip over its walls, rim of tufts elsewhere | `art/<ground>-lip.png` (`elevation_fringe.gdshader`), else `<ground>-edges.png` per edge (`elevation_strip.gdshader`) |
| `Stairs` | every flight's faces, back to front in one mesh: treads, landing, risers, railings and posts | `art/<style>-stairs-tread.png`, `-riser.png`, `-coping.png` and the wall (`elevation_stairs.gdshader`) |
| `StairsFeet` | the lower ground's foot where a flight's railings and posts stand on it in sight | `art/<ground>-foot.png` (`elevation_fringe.gdshader`) |

**Rims** (`elevation_rims.gd`): a top's boundary edges (where it meets lower ground, or a wall at
or below its level) are chained into loops and lines with the top on the left. Along a south face
the strip is the lip, swept straight down (also on diagonal faces, so it follows the wall); along
every other edge it is the rim, swept perpendicular to the edge, its art cut below the soil line
(vertex colour b; `rim_cut` in the shader). The art's u runs on along the chain, convex corners turn
in a round fan and concave ones meet in a mitre, so lip and rim flow into each other around every
corner. The feet and the wall's texture are swept vertically: a diagonal face continues the same
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
level below. A body's level changes only on stairs (it takes the level of the stretch it stands on,
the upper half of a one-level flight the top level, so it climbs and descends by walking) and when
a jump or drop lands (`track(body, level)` sets the new layer). While a flight runs it owns the body and
places it every step, so nothing collides on the way. `WorldService.elevation` answers `level_at`,
`is_walkable`, `level_of(body)`, `track`, `body_fits`, `drop_target` (the ledge push in
`player.gd`) and `hop_target` (the jump in `player_abilities.gd`).

**Stairs** (`elevation_stairs.gd`). A flight is built in 3D in its own frame (s along its
direction from the rim, t across, h up) with the mockup's geometry (`stairs_mockup.py` `Flight`);
a point at ground (x, y) and height H is drawn at (x, y − H) and its depth is its ground y.
`Elevation` finds the flights in the painted stairs cells (`painted_stairs`; a run of cells side by
side along the rim with one kind is one flight; its rim is where the higher ground behind the cells
begins) and asks each for:
- `walk`, the walkable surface on screen (the landing and the steps' nosing line between the
  railings): walkable by every level the flight joins, the landing by the top level only
  (`walks_level`; other levels meet it as a wall, so nothing steps onto an open landing from the
  hidden strip beside it); a body there takes the level of its stretch (`level_at`) and its depth
  (`depth_at`, the true ground position under it, so the near railing hides its feet);
- its blockers per level: what of the structure stands at that level's height, drawn at that
  height (`blockers`: the landing's railings and posts for the top level; the bases of the railings,
  posts and steps for the bottom one), and the railings along the nosing line for every level it
  joins (a body on the steps stands at their height). Collision comes from these footprints, never
  from what is drawn: what of a flight stands higher, over ground behind it, only hides a body
  there (the depth map), so the posts and railings never close a flight's ends on screen;
- its silhouette, the whole structure as drawn (`occupies`; fences leave a gap there);
- its faces, back to front for the camera (the far railing's inner face, the landing and the steps
  from the far end, then each railing between its posts), drawn in one mesh and written to the depth
  map. Godot's 2D drawing has no depth test, so what of a flight lies below its top level where the
  hill's top is drawn (`occlude`: a back flight's foot and first steps behind the rim) is cut out of
  its faces, its depth, its silhouette and its foot strips (feet only show where a railing or the
  near posts stand on the lower ground in sight).

Each level's collision then traces the stairs too (`_with_stairs`): near a flight, the terrain's
outline, the flight's outlines and those of flights it touches are cut where they cross, a piece
is kept where it parts walkable from blocked ground, pieces on one line merge and ends a hair apart
are welded into one point (a body sliding along an edge would catch on the next one's end). About 45 ms for
the park's 39 flights and 180 ms for all levels' collision, once at load.

Teleport and the Stretch Lash treat ground off the slime's level like a solid tile
(`ability_terrain.gd`). Terrain edges skip corners whose cells have different levels (the cliff
draws its own rims there). Visual only otherwise: the ground cells stay the gameplay truth for
footsteps and water.

## Making the art

All art is generated with Magnific (`gpt-2-mini`, `transparentBackground: true`,
[Magnific guide](../assets/magnific-mcp-guide.md)), saved in `asset/Originals/elevation/generated/`
and turned into runtime textures by `python scripts/art/build-elevation-art.py [name ...] [--preview
DIR]` (numpy, Pillow) into `godot/game/world/elevation/art/`.

- **Wall** (1:1): "a seamless tileable texture of a natural stone cliff wall seen straight from the
  front … exactly four horizontal courses … separated by thin dark straight crevices", references:
  the rock props sheet (`asset/MAPS/rocks/96x96-tile_8x3.webp`) and the style sheet. The tool finds
  the crevices, resamples each complete course to 128 px and makes it periodic (`WALLS`).
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
  one). In `WALL_ENDS` give each the source column of the crevice between the wall and its stones;
  the tool cuts the column, fits its courses to the wall's and matches its colours.
- **Stairs** (2026-10-06, the stairs session): rows of cut sandstone with the wall and the old stairs
  as references, `stairs-tread-a.png` (treads seen from above) and `stairs-riser-b.png` (risers and
  copings). In `STAIRS` give each part the source rows of one step, crevice to crevice; the tool
  makes it opaque, periodic and one rise (43 px) tall, darkens the risers and tints the coping
  towards the wall (`<style>-stairs-tread.png`, `-riser.png`, `-coping.png`). Railings and posts use
  the wall.
- The editor's paint tiles: `python scripts/art/build-elevation-paint-tiles.py`.

Then let the editor import them. The 2026-10-05 sets (one wall, its two ends, stairs, nine grounds'
lips and feet, with spare candidates) used about 4,300 credits. The rims reuse the lips' art.

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
- One wall style (`meadow-rock`) for every cliff. Next: styles per biome (snow rock, sandstone,
  cave), picked by the ground on top.
- A flight needs room on the lower ground: one that runs into another hill or a hole is built
  anyway and looks wrong. Two flights side by side along one rim must share a kind to be one; two
  of different kinds that touch work but each keeps its own railings.
- On stairs a body's depth follows the steps' nosing line, not each step: it may float or sink a
  few units against a tread (a third of a level at most).
- A body may stand behind a flight where the flight only hides it (its footprint at the body's
  level blocks it, not its picture): there is no cap like the strip behind a hill.
- Only the player changes level (stairs, ledge drops, a jump off a rim); nothing climbs but stairs.
  Bodies walk the stairs (enemies too, when they get there), but no path finding knows them.
  Enemies collide with their level but neither drop nor path to stairs. Projectiles, melee reach,
  sight, interactions and spawns do not know levels yet. These are the next gameplay steps (the
  old branch's rules in `git show feat/elevation-levels:docs/ELEVATION.md` are a reference, not a
  plan).
- A drop off a back rim lands in the capped strip, nearer the rim than a real fall would; a side
  rim shows no wall, so a fall beside a hill drops past plain ground.
- Waterfalls, ladders, ramps and pits are not built. Water only laps at a wall's foot: a hill's
  rim beside water (no wall) gets the usual shore tiles of the terrain edges where it is flat.
- The level light only darkens holes; hills are not lightened.

## Files

| Path | What |
|---|---|
| `godot/game/world/elevation/elevation_grid.gd` | The model: tris, chamfers, walls, the 3D ground, walkability, collision segments |
| `godot/game/world/elevation/elevation.gd` | `Elevation`: mount, drawing, collision bodies (stairs merged in), body levels, drop and hop targets, jump flights (`@tool`) |
| `godot/game/world/elevation/elevation_stairs.gd`, `elevation_stairs.gdshader` | A flight of stairs: geometry, walkable surface, silhouette, levels and depth along it, faces back to front, occlusion by the hill |
| `godot/game/player/abilities/jump_sequence.gd` | The flight of a jump or a ledge drop (`player.gd` `_press_ledge` starts a drop) |
| `godot/game/world/elevation/elevation_rims.gd` | Every top's border as one chained strip (lips, rims, round corners), glow and depth cores |
| `godot/game/world/elevation/elevation_occlusion.gd`, `elevation_occlusion.gdshaderinc` | The depth map and the bodies hidden behind higher ground (included by `game/feel/hit_flash.gdshader` and `game/player/gulp/form_skin.gdshader`) |
| `godot/game/world/elevation/elevation_mesh.gd` | Mesh data the builders fill |
| `godot/game/world/elevation/elevation_layer.gd` | The painted layer: hides itself in the game, previews the cliffs in the editor (`@tool`) |
| `godot/game/world/elevation/elevation_tileset.tres`, `elevation_paint_tiles.png` | Paint tiles: levels −3 … 3 and stairs in 8 directions, railed or open landing (`elevation_level`, `elevation_kind`) |
| `godot/game/world/elevation/*.gdshader`, `elevation_light.gdshaderinc` | Wall, wall end, fringe, strip, water foot, ground, shade, cast shadow and glow shaders |
| `godot/game/world/elevation/art/` | Tool output (`scripts/art/build-elevation-art.py`) |
| `asset/Originals/elevation/generated/` | Generated sources |
| `asset/Originals/elevation/stairs-mockups/` | The approved stairs design: spec (README.md), renderer, mockups |
| `scripts/maps/build-elevation-park.py` | Builds the park in the playground |
| `godot/tests/test_elevation.gd` | Shapes, holes, a flight's geometry and levels, stairs on every side (railings, landing, hidden parts), every showcase flight walked through both ends, climbing and walking up a side flight, the capped strip, closed collision outlines (stairs included), the park's walls, wall ends, water foot, lips, shadows, stairs, drop and hop targets on every shape, a rim that holds then drops (a square and a diamond), sliding down a back face past a tip, walking behind a hill and the ghost |
