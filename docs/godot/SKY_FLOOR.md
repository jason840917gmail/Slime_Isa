# Sky Floor: islands over the clouds

Owner request (2026-11-01), from an *A Link to the Past* screenshot: high-mountain or sky areas where
the play area is islands of ground floating high up, with layered clouds and a far-off ground below
that scroll at different speeds from the playfield, so the sky reads as high above a fixed ground.

**His decisions (2026-11-01):**

- The mockup (`asset/Originals/sky/mockups/sky-floor-mockup.png` and `sky-floor-parallax.webp`)
  approved.
- A fall off a sky edge **respawns**: the slime is put back on the spot it fell from and loses a
  little health. A drop into a world below was the other option, not taken.
- "The walls need a cloud hedge with the sky so it looks better, not like a flying block but
  mountains that go over the clouds": the **cloud bank** round every island's foot.

**Later (2026-11-02):** the dark wedges at the 45° corners had to go; the side walls show their stone
as the front walls do, with the bank only near their bottom, "almost at the bottoms of the wall", so a
3-level wall looks right too (the corner's islet at level 1 tests it); and the slime must not be able to
fall from a bridge.

**Later (2026-11-11):** "random artifacts that don't look good on sky ground" (the ledge dressing's
rocks, roots and mushrooms at the walls' feet, with the lower ground's plants along them) and
"sometimes clouds start from the top edge on lateral walls" (the bank covered most of a side wall's
strip, from the top's back corner down). A wall that hangs into the sky now has no foot and no
dressing, and the bank leaves the side walls' strips alone.

The try-out is the playground's [sky corner](#the-playgrounds-sky-corner).

## What you see

- **Islands** are ordinary ground with ordinary cliffs: their walls hang into the sky as any hole's
  walls do ([ELEVATION.md](ELEVATION.md)), one stone course per level above the sky. Each wall's style
  follows its top's ground or the `cliffs` layer.
- **No ground at the walls' feet.** A wall that hangs into the sky stands on nothing: it has no foot
  (no plants of the ground below, no foot strip, no shadow) and no ledge dressing (rocks, roots,
  mushrooms). Walls that end on real ground inside the area (a lower terrace) keep theirs.
- **The cloud bank** hugs every island's foot. It covers the bottom `bank_cover` (20) units of every
  front and 45° face the elevation draws into the sky (whatever the wall's height) and spreads
  `bank_reach` (40) units out over the sky, with puffy edges that follow the bank picture's puffs.
  A side wall's strip shows its stone all the way: the bank comes round the front corner and thins
  out up the strip, and the clouds beside the strip lie behind it. Near the islands the bank takes a
  little of their shade (`bank_shade`). It drifts slowly (`bank_drift`), so its puffs churn along
  the walls.
- Where a wall piece would hang out over the open sky (the slanted start of a side wall at a back
  45° corner), the sky is drawn over it: the corners show a clean 45° edge against the sky.
- **The backdrop** lies far below, under the bank. It is up to four pictures that tile, far to near.
  - The playground's default: the far forest seen from very high (scroll 0.2, under a teal haze), two
    layers of big clouds (0.45 and 0.62), and thin wisps (0.8).
  - Each layer moves with the camera by its own **scroll factor**: 1 sticks to the islands, 0 never
    moves.
  - Each also **drifts** on its own (world units a second).
  - The far ground hardly moves while the islands pass over it, so the sky reads as high above a
    fixed ground.
- **Rope bridges** cross the sky between islands ([below](#rope-bridges)). They draw over the sky
  and the bank.
- Bodies draw over all of it: a slime falling spins and shrinks over the clouds.

## Making a sky floor

1. **Paint the sky as holes** on the world's `elevation` layer, at level -2 (or lower), wherever the
   sky should be, inside the SkyFloor's area (step 2). Leave the islands at the ground's level (0), or paint them higher. Every cell at the
   SkyFloor's `sky_level` (-2) or lower is sky. Its cliffs are as many courses tall as their tops are
   levels above it. The usual elevation rules hold:
   - rims hold the slime;
   - a 45° corner makes a 45° face;
   - stairs and ramps join levels.

   Leave as many free sky rows below an island's south edge as levels its wall drops (a wall whose
   foot lands right on the next island's corner shows its own foot there, uncovered). The ground layer
   under the sky can stay whatever it is: the backdrop covers it.
2. **Add a SkyFloor node** to the world scene (Add Node → `SkyFloor`, script
   `game/world/sky/sky_floor.gd`) and set its **area**: its position is the area's top-left corner and
   `size` its width and height (world units); the editor outlines it in blue. Only cells whose middle
   lies inside the area are sky: holes outside it (a pit, a pond, the park's holes) stay holes. It
   draws over its sky at once, in the editor too:
   - the layers drift there;
   - they follow the editor's view as it pans;
   - it redraws as you paint, or move or resize the area.
3. **Tune it in the Inspector.** All its settings are scene properties:

   | Group | Properties |
   | --- | --- |
   | (top) | `sky_level` (-2): cells of the area painted at it or lower are sky; `size`: the area |
   | Layer 1 (farthest) … Layer 4 (nearest) | `picture` (a picture that tiles; empty: the layer is off), `scroll` (0 … 1), `drift` (units/s), `scale` (1 = 128 px a cell), `tint`, `haze` (a colour mixed over it, alpha how much), `opacity` |
   | Cloud bank | `picture` (a sea of cloud tops that tiles; empty: no bank), `scale`, `drift`, `tint`, `shade`, `cover` (units up a wall), `reach` (units out over the sky), `soft` (edge softness), `puff` (how far the puffs push its edges) |
   | Edges | `side_strip` (24: the side wall strip, [ELEVATION.md "Side walls"](ELEVATION.md#side-walls)), `rim_soft`, `base_colour` (under every layer) |
   | (bottom) | `falls` (on): the game lays a SkyFall over the sky |

4. **Lay rope bridges** across the gaps ([Rope bridges](#rope-bridges)), after the SkyFloor in the
   scene tree.

## Falls

In the game the SkyFloor lays a **SkyFall** over its area (`falls`; `game/world/sky/sky_fall.gd`):
the dungeon kit's void `Hazard`, its look off
([DUNGEONS.md "The void, slabs and spikes"](DUNGEONS.md#the-void-slabs-and-spikes)), pinned to the
sky instead of the paint. It covers exactly the sky cells (the area's cells at `sky_level` or lower)
and its rim is `sky_level` + 1, so an ordinary hole on an island (a -1 pond or pit, a lower terrace
reached by stairs) is never a fall, and sky painted at two levels catches at both. (A plain Hazard
reads its floor and rim from the paint, which would turn every hole on a level-0 island into a fall.)

- A rim holds the slime. Pushing on for `elevation.dropPushMs` drops it over (the ledge drop).
- It lands in the sky, where the hazard catches it: it spins and shrinks away
  (`dungeon.void.fallMs`, the `FallDown` cue).
- It is put back on the spot it fell from, the last safe ground it stood on, and loses
  `dungeon.void.damage` (10). A fall that faints it wakes it as any faint does.
- To send every fall to fixed spots instead, give the SkyFloor a `SkyFall` child of its own: it is
  used instead, with its `return_points` (or children named `Return...`) or `fixed_return`. Wherever it is placed, its rectangle is the SkyFloor's area.
- Enemies never fall: they keep to their wander areas and do not drop off rims, as in the dungeons.

## Rope bridges

`RopeBridge` (`game/world/sky/rope_bridge.gd`) is the dungeon kit's drawbridge
([DUNGEONS.md "Doors and room logic"](DUNGEONS.md#doors-and-room-logic)), always down:

- Its deck is safe ground over the SkyFall.
- It opens its passage over the elevation hole at its `level` (the rims' level), so the slime walks
  onto it from the rim.
- **The slime cannot fall from it** (`railings`, on): a solid railing (a wall on the world layer)
  runs along each side of the lane, so nothing walks or rolls off. Its deck reaches a unit past the
  lane each side, so the passage takes the cell rows beside the lane too, and a push against a railing
  never starts a ledge drop. A cap closes each of those side rows at both ends, on the rims' lines.
  So the rim one cell either side of a bridge's head holds the slime as a wall, without a drop. With
  `railings` off, the lane's sides are rims, and a push off them is a fall.

**Placing one:**
- The node stands at the hinge: the middle of the deck's end on the rim it leaves.
- `toward`: the way it runs.
- `length`: the sky cells it crosses.
- `width`: the lane (64, one row).

**How it draws:** the rope bridge along the deck, from the art's two ends with its middle stretch
repeated between them, `overhang` (28) units past each end so the anchor posts stand on the rims.
East–west bridges use the east–west art and north–south bridges the north–south art, always upright.

## How it works

`sky_floor.gd` and `sky_floor.gdshader` (`game/world/sky/`) draw the sky in two kinds of draw, both
with one shader, and both made again whenever the elevation's drawing is rebuilt:

- **The backdrop** is the elevation's own mesh of the holes' floors (the Shade's `holes`), drawn
  again with the sky as the last child of the Shade. That is where a dungeon pit's spikes are drawn
  (`hazard.gd` `_attach_look`): over the holes' floors and under every wall, rim and top. The shader
  keeps the triangles inside the area at `sky_level` or lower (their level is in the mesh's vertex
  colour; it stops before reading anything else off them). So the sky fills exactly the floor the elevation leaves in view, and the islands, their
  45° corners and their cliffs draw over it as they are. It draws the layers and the bank out over the
  sky from the islands. Under a wall it shows rock, so a crack between two wall meshes never shows
  the sky.
- **The lip** is each of the elevation's wall meshes (its `Sides`) that reaches the area, drawn again
  right after itself:
  - on its walls and corner stones, the bank up its bottom: the mesh's vertex colour holds each
    point's height in levels, so the bank covers exactly `bank_cover` units up from each wall's foot,
    as drawn, at any height. A side wall's strip is the wall seen from the side, its height running
    across it: there the bank thins out as the wall turns into a side's (the mesh says how much each
    point is a side's), none on the strip itself;
  - where a wall piece hangs out over the open sky (the slanted start of a side wall at a back 45°
    corner), the sky itself, as the backdrop would;
  - on its foot pieces (which the elevation does not draw in the sky), the sky in a thin band past
    the foot line: the wall's drawn foot wobbles a few units round the straight line the floor ends
    on, and this closes the gap between them.

  It never draws on a top.

**The walls' feet** are the elevation's own work (`elevation.gd` `_sky_floors`, `_foot_in_sky`): it
finds the world's SkyFloor nodes (they are in the group `sky_floor`) and asks each its area's cells
(`sky_cells_on`). An edge whose wall ends in an area, at its `sky_level` or lower, gets the lower
ground `sky`: its walls are meshes of their own, whose material draws no foot (`has_foot` 0 in
`elevation_sides.gdshader`), and no foot set of the ledge dressing lists that ground. The areas are
part of the world's elevation cache key, so **bake the world's cache after moving or resizing a
SkyFloor** (`tools/bake_elevation.gd -- --world=<id>`); in the editor the elevation builds its walls
again when the area's cells change.

The backdrop and the lip read a **field** that the SkyFloor builds from the paint inside its area, one texel per 16 units
(`_build_field`; the per-cell work, such as which corners are cut at 45°, is done once per cell). For
each point it holds:

- the sky cell's level;
- its distance out from the islands' silhouettes, or its height up a wall from the wall's foot (the
  silhouettes are the tops with their cut corners, their south walls as many levels deep as they
  drop, and their side strips);
- its height up a side wall's strip (the strip's outer edge counts as the strip, so the whole strip is
  a wall to the lip, not open sky);
- its distance to the nearest top.

They also read the world elevation's **depth map** (`elevation_occlusion.gd`): what the elevation draws
at each point, its level, and how far below its wall's top edge.

Without an elevation drawing to sit in, one draw over the area (a child of the SkyFloor, z -1) does
both from the field alone, cut round its silhouettes.

The parallax is in the shader: each layer is sampled at `world − camera · (1 − scroll) − drift · time`,
so nothing moves in the scene.

- The camera is the world point at the middle of the screen, handed over every frame.
- Drift runs on the shader's real time: it is presentation.
- The pictures are loaded with `SheetSprite.load_picture`: the imported texture, or the file itself
  until the editor has imported it.

**Why not Parallax2D:** a sky floor is cut to the painted cells. With `Parallax2D` that needs clip
children (back-buffer copies on WebGL 2) or ground that draws nothing there. Reusing the elevation's
own meshes keeps it to one extra draw for the floor and one per wall mesh, with four layer samples
and one bank sample, on the web.

## Art

Generated with Magnific GPT 2.5 (`gpt-2-mini`, transparent background, the mushroom furniture sheet as
style reference) on 2026-11-01. The sources are in `asset/Originals/sky/generated/` and the mockups in
`asset/Originals/sky/mockups/` (with the two scripts that composed the mockup from playground renders).
`python scripts/art/build-sky-art.py` packs them into `godot/asset/MAPS/sky/` at 128 px a cell
([TOOLING.md](../TOOLING.md)):

- `far-forest.webp`: the forest from very high, made seamless.
- `clouds-big-a.webp`, `clouds-big-b.webp`, `clouds-wisps.webp`: on transparency. No cloud touches an
  edge, so they tile.
- `cloud-sea.webp`: the bank, made seamless.
- `rope-bridge-ew-{west,mid,east}.webp` and `rope-bridge-ns-{north,mid,south}.webp`: each bridge cut
  into its two ends and one repeat of its railing.

Another sky (sunset, storm, a far sea) is new pictures on the same node.

## The playground's sky corner

On the playground's east side, south of the Bestiary's east pens and north of the Crossings corner:
cells 100-123 × 67-88, x 6400-7936, y 4288-5696. The playground did not grow for it.

- **Get there:** `?map=playground&spawn=6300,4640` (web) or `-- --map=playground --spawn=6300,4640`
  (desktop), or walk east past the Bestiary.
- **What it holds:**
  - the sky painted at level -2 on the playground's `elevation` layer;
  - three islands at level 0 with their corners cut (45° faces), and an islet at level 1, whose walls
    drop three levels;
  - a `SkyFloor` over the corner (its area x 6400-7936, y 4288-5696) with the default layers and bank;
    the park's own holes, west of it, are outside the area and stay holes;
  - three rope bridges: west to the first island, east from it, south from it;
  - a sign.
- **Its scene:** `game/dev/corners/sky_corner.tscn`, instanced in `game/scenes/worlds/playground.tscn`.
- **Its builder:** `"<Godot console exe>" --headless --path godot -s res://tools/build_sky_corner.gd`
  paints the sky, writes the corner and instances it, once. It stops when the area is painted or the
  corner exists, unless given `-- --force`. From then on both are edited by hand. Bake the
  playground's elevation cache after painting there
  (`tools/bake_elevation.gd -- --world=playground`).

## Not done yet

- No real world has a sky floor yet.
- No sound of wind, and no cloud shadows on the islands.
- No clouds drift over the islands.
- Nothing yet falls to a world below.
- The default layers are tuned on the corner's narrow gaps (four cells). A wide sky may want fewer
  clouds or a smaller `bank_reach`.
- Where a wall's foot lands right on another island's cut corner (two sky rows under a two-level
  wall), the last units of the wall show there as a thin dark line, uncovered by the bank (the corner
  is the island's own cell, where the lip never draws). The corner's top-right island shows it at its
  two back corners.
- The rim one cell either side of a bridge's head holds the slime as a wall, without a drop (the
  railings' side rows).
- A deck that can stop holding (a falling slab, a drawbridge that rises) put over the sky would leave
  the slime standing on the sky at the deck's level until it walks off the open passage: SkyFall
  catches only a body below its rim (`sky_level` + 1), which is right for the cut corners and the
  rope bridges. Only always-down decks (rope bridges) are meant for the sky so far.
- **Not checked:**
  - the web build;
  - the field's build time on a whole chunk of sky (it is GDScript at load, about 80 000 texels for
    a 64 × 64 chunk);
  - how it looks in the editor (the blue area, the redraw as you paint or move the area);
  - the tests.

## Files

| File | What |
| --- | --- |
| `godot/game/world/sky/sky_floor.gd`, `sky_floor.gdshader` | the SkyFloor: its area, the field, the backdrop, the lip |
| `godot/game/world/sky/sky_fall.gd` | the SkyFall: the void hazard pinned to the sky cells and `sky_level` |
| `godot/game/world/sky/rope_bridge.gd` | the rope bridge (a drawbridge always down, with solid railings) |
| `godot/asset/MAPS/sky/` | the packed art |
| `scripts/art/build-sky-art.py` | packs the art |
| `godot/tools/build_sky_corner.gd` | builds the playground's sky corner |
| `godot/tools/render_sky_corner.gd` | renders the corner (whole at 1x, four close-ups at 2x, or any cells with `--cells=` and `--zoom=`; `--no-lip` hides the lips): run windowed, `-- --out=<dir>` |
| `godot/game/world/elevation/elevation.gd` (`_sky_floors`, `_foot_in_sky`), `sides/elevation_sides.gdshader` (`has_foot`) | no foot and no dressing where a wall hangs into the sky |
| `godot/game/dev/corners/sky_corner.tscn` | the playground's sky corner |
