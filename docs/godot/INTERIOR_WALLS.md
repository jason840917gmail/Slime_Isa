# Interior walls: Zelda's bevelled frame, painted cell by cell

> **Status:** 2026-10-18. The owner rejected the first look (walls with a top course, the south wall
> seen from behind) and approved Zelda's "cliff view of the 4 walls": the bevel, two cells deep. Three
> styles, each with its own plain floor: `lair-stone` (the fort's cream masonry), `cave-rock` (dark
> slate), `root-rock` (umber stone and roots). The box-room lab and all of Fatty's Lair use them; the
> Hollow and the Mine still have elevation-cliff walls with `doorway_art.gd`'s frames.

The owner (2026-10-17/18): doors must be part of the wall ("see in zelda how the door looks like
part of the map"); "remember how the sprite of zelda uses the cliff view of the 4 walls in
interiors? that is what i was hoping." His references: the Zelda sheet
`asset/Originals/dungeon-kit/doorways/reference/zelda-interior-walls-sheet.png` and its frames (the
session images 13 and 16). The plan: [the doorways design](../design/2026-10-17-doorways-in-walls.md).

An **InteriorWallLayer** (`game/world/interior/interior_wall_layer.gd`) draws a room's border as a
bevelled frame. Every side is the same kind of thing: a wall **face** seen from above, sloping up and
away from the floor, **two cells deep** on every side. A north face is horizontal courses seen from
the front; a south face the same, sloping the other way (toward the camera); east and west faces are
vertical courses. The faces meet on **45 degree mitres** at the corners: outer corners where the
floor turns convex, inner corners where it turns concave (an L's notch). The floor sits inside the
frame; the faces' foot lines are its edge. Doors and openings are cut **into** the face of their
side, and a door's leaf fills its opening exactly. Every opening is the **north** piece turned for
its side, as Zelda's sheet does (owner, 2026-10-18: the generated south and side doors came out as
perspective tunnels): south 180 degrees, west 90 counter-clockwise, east 90 clockwise, frame and
leaf (padlocks, bolt, the seal's pearl) turned together, each taking its side's light (a per-channel
gain from that side's run). It is separate from
the overworld's elevation cliffs and the fieldstone [WallLayer](WALLS.md).

## Painting a room

![The palette: a column per style (fort stone, cave rock, root rock), a row per tile](images/interior-walls-palette.png)

The palette (TileMap panel at the bottom, with the `interior-walls` layer selected) is a column per
style: **fort stone**, **cave rock**, **root rock**, and a row per tile, each a small picture of its
piece cut from the packed sheet: the **wall**; the openings: **doorway**, **cracked** wall, **blown
hole**, **stairs**; the closed doors: **key door with one lock**, **with two locks**, **boss door**,
**bolted door**, **shutter**, **the seal**, **plank barricade**.

1. In the room scene (a dungeon room: [DUNGEON_ROOMS.md](DUNGEON_ROOMS.md)), **Add
   Node > InteriorWallLayer** beside the `ground` layer (same grid, position (0, 0)), named
   `interior-walls`; it takes `game/world/interior/interior_wall_tileset.tres` by itself. A room of a
   shell (the box-room lab): the shell needs an empty `interior-walls` InteriorWallLayer too
   (`room_scene_shell.gd` gathers every room's cells on it when the dungeon is built). Fatty's Lair's
   rooms are each their own world (since 2026-10-18): a room's layer is its world's walls.
2. Pick the style's **wall** tile (row 0) and paint the room's **rim, two cells thick**, any shape: an
   L, a cross, a long hall, a room bigger than a screen (the camera moves inside it). Floor is every
   cell the painted walls enclose. Two rooms side by side each paint their own rim, so a band of four
   cells parts them.
3. For an **open way**, paint its **two-by-two block** of the rim (two cells along the wall, both rows
   of the rim) with the **doorway**, **cracked**, **blown hole** or **stairs** tile. A doorway between
   two rooms is painted in both rims.
4. For a **closed door**, paint the block with the door's tile instead (key door 1 or 2 locks, boss
   door, bolted door, shutter, seal, plank barricade). The layer at once makes the door object under
   the room's `Objects` node (made when missing), on the floor line in the middle of the passage,
   with `wall` set for its side, `frame_drawn_by_wall` on, the style, and a unique `door_id`
   (`<room>-<kind>-<x>-<y>`); the wall draws the frame, the door its leaf. Then select the door and set
   only what is its own in the Inspector: a shutter's `fight_id` or `starts_shut`, a barricade's
   `flag_id`, a door's `locked_text`. A **bolted door** opens from the room its face looks into, the
   room it is painted in: paint it in the rim of the room the bolt is on. Painting another door tile
   over the block swaps a door the layer made; painting the doorway (or wall) over it removes it.
   Only a door the layer made and nobody has changed since goes this way
   (`game/world/painted_objects.gd`): a door with a setting of its own (its `door_id`, a shutter's
   `fight_id`, a line), or one placed by hand, is never removed. Its block erased or repainted, the
   layer lets go of it with a warning (it loses the meta `interior_door_block`) and adopts it again,
   settings and all, when the block is painted back, so an erase undone with Ctrl+Z keeps the door and
   its save records (2026-10-19: before, erasing a cell of the hub's boss door block and undoing it gave
   the door a new id). Delete such a door by hand when it should go. A door of the right kind already
   standing at the spot is adopted. Doors may be grouped under a plain node in `Objects` (say
   `Objects/Doors`): the layer finds them there too, so a door moved into a group keeps its block and
   gets no twin. The builder's
   doors in the Lair's rims are adopted this way (all but R5's way back, which stands in the lower
   hall's painted doorway as a placed door).
5. The camera room keeps its rect or outline; the rim is inside it (doors stay on the room's edge).
6. In Fatty's Lair, put a **room door** (`object.room-door`) in every doorway that leads to another
   room and pick its target in the Inspector (DUNGEON_ROOMS.md "Fatty's Lair: one world per room").

A pocket room of a shell (CameraRoom meta `walls_in`) keeps no walls of its own: paint them in the
room it is cut from. Fatty's Lair's pockets (Burr's cell, the store, the map nook)
are their own worlds and each paints its own full rim, the parent world painting rock behind its own
faces round the pocket, the door cut into them (2026-10-19; DUNGEON_ROOMS.md "The pockets"). R5's lower
hall and key alcove are rooms of R5's world again, behind dividers: R5 has one rim.

The layer draws the style's **floor** (`draw_floor`, on by default; each style its own plain floor;
`floor_style` names another) over the floor cells; off, the ground layer shows. Nothing the layer
draws is saved (faces, floor, fronts, collision): the scene keeps its cells, its own settings and the
door objects with theirs. The palette squares show in the editor only (`paint_opacity`): there the
layer is always enabled, whatever the scene says (17 of the Lair's rooms were saved by a headless tool
with `enabled = false` and the squares at alpha 0; the editor shows their squares again since
2026-10-19), and in the game it is disabled and see-through. A void or pit inside a room still uses
the `elevation` layer's holes and their edges. `tools/render_interior_palette_room.gd` renders a room
painted with every closed-door tile.

## Editing rooms by hand

Fatty's Lair's rooms are the scenes to edit now: paint their `interior-walls`, place and move doors
in the editor. Its builder is retired and writes nothing (DUNGEON_ROOMS.md).

## How the pieces are laid

- **Faces:** behind every floor cell's wall side, a strip one cell along and two deep (`n0`..,
  `s0`.., `w0`.., `e0`..), the run's pieces alternating by the cell's place along the wall (the
  style's `run_period`: three), cut so they tile without a seam.
- **Outer corners:** at a vertex with one floor quadrant, the mitred 2 x 2 block (`nw`, `ne`, `sw`,
  `se`).
- **Inner corners:** at a vertex with three floor quadrants, the 2 x 2 block in the fourth (`in_se`,
  `in_sw`, `in_ne`, `in_nw`, named by the floor's side of the block): two faces folding round the
  floor's corner on a mitre; it replaces the strips over its cells.
- **Openings:** over the first strip of a painted block, `<side>_<kind>` (2 x 2: the north piece
  turned), its ends fading into the run under it.

The walls lie under every body (z -1): bodies walk over a face's foot, as in Zelda.

## Pits and holes

Paint them as outdoors ([ELEVATION.md](ELEVATION.md)): in the room scene, select the `elevation`
layer and paint the sunken cells with a hole level (-1 a spike or lava pit, -3 a void) and their
flights of stairs; the pit's rims, walls and stairs follow the paint by themselves and show in the
editor at once (the elevation layer's preview), as in the game. **Inside a room a level change is
drawn as the room's own wall face** (owner, 2026-10-19, after ALttP; ELEVATION.md "Faces in
rooms"): the faces looking down at the lower floor are the room style's bevel runs, one cell for
any drop, the sides the side wall's strip, mitred, their cap on the upper floor's edge; decks (slabs,
landings, drawbridges) draw over them. The collision, the ledge drops and the slabs are the
outdoor ones. The room's floor lies under the elevation's drawing (on the ground layer), so the
faces always show.
After painting, the next F5/F6 run that builds the world saves its cache by itself (ELEVATION.md
"Baked cache"); bake it by hand (`tools/bake_elevation.gd -- --world=<world>`) only when you will not
run it.

What hurts is a hazard (`object.hazard`, DUNGEONS.md "The void, slabs and spikes"). **One hazard per
floor level; it hurts only on its level**: its `level` (the floor it covers; -99, the default, is
`rim_level` - `pit_depth`) picks the painted cells it works on, so its rectangle may be as big as the
room. It catches the slime only on the cells the `elevation` layer paints at that level (not on
stairs), never on the levels above inside its rectangle, and a slime that falls onto that level from
above lands in it. Its spikes or lava are drawn only on those cells, as the bottom of the pit: the
look is drawn inside the elevation's drawing, over the pit's ground and under every wall, rim, stair
and higher floor, so only the open part of the pit floor shows them, and slabs and bodies draw over
it (`Hazard._attach_look`, in the editor and the game). `tools/render_room_collision.gd` fills the
cells a hazard catches on in orange.

## Painting collision

A room's level changes (a pit, a raised floor) collide as the elevation's automatic outline, unless
the room has a painted **`level-collision`** layer: then exactly what is painted collides. Orange
**rims** sit on an upper floor's edge: they hold a body there, and pushing on drops it. Red
**bases** sit at a wall's foot: they block bodies of their level. Each tile acts on its own level, on
a 16-unit grid. The interior walls collide by themselves; leave them out. Step by step, with the
palette and a painted room: [ELEVATION.md "Painting collision"](ELEVATION.md#painting-collision).
To start from today's collision, press "Fill from the automatic collision" on the layer (save the
scene first).

## Bodies in a doorway

Zelda draws a doorway's frame tiles over the sprites (they have priority over Link), so Link walks
under the lintel and between the jambs. The layer does the same: each way-through opening (a
doorway, a closed door, a blown hole, stairs; not a cracked stretch) draws its **front** again among
the bodies: the sheet's `<side>_<kind>_front`, the opening piece without its passage (the passage
runs from the lintel to the room-side edge), y-sorted at the bottom edge of the opening's block. A
body whose feet are in the passage is drawn under it, on every side: under a north door's lintel,
between a south door's jambs with the face in front of it, under a side door's upper jamb. A body
south of a north door (in the room) is drawn over it, so it still covers the face behind it; plain
walls are unchanged (under every body). `tools/render_doorway_passes.gd` captures the slime halfway
through a doorway on each side of a room.

## Which room a wall faces

Floor is a room's own cells: inside one of the scene's camera rooms and enclosed by its walls,
never empty space beside a wall outside the room (a pocket room whose walls enclose none of its
cells, painted on two sides only like R1's store, takes all its cells). When the dungeon shell
gathers the room scenes, it records which room painted each wall cell (`cell_rooms`), and a wall
draws its faces and corners only toward the floor of that room (or of a pocket room whose walls it
holds, `walls_in`): a two-cell wall between two rooms shows its painting room's face, and from the
other room it reads as the top of a wall. A room that is its own world (Fatty's Lair) has no
`cell_rooms`: its walls face its floor on every side. `tools/render_room_scene.gd` renders one room
scene alone, as the editor shows it.

## Collision

Every wall cell is solid but an opening's **passage**, through both rows of its block: in a north or
south block `interior.gapUnits` (64) wide in its middle, in an east or west block
`interior.sideGapUnits` (120) tall in its middle (taller than the drawn passage, about 64, as the
slime walks it at its feet); the jambs either side stay solid. A cracked stretch is solid until
blown. The door objects' bodies, on the floor line and turned with their `wall`, close the passage
while shut: a dungeon door's is 128 long, a plank barricade's 132 (it turns for an east or west wall
only while `frame_drawn_by_wall` is on; an old trunk or fence with the same script keeps the rotation
it was placed with). The overworld's `ArcadeMover` rules apply.

## The door objects in the opening

The door objects keep all their logic, exports, signals and records. Each has
**`frame_drawn_by_wall`** (default false: the dungeons look as before) and draws, when it is on, only
its **leaf**, a piece of the style's sheet cut from a render of the same frame with that door shut, so
it fills the opening exactly in its side's perspective (`InteriorWallLayer.leaf_at`):

| Object | Leaf (`leaf_kind`) |
|---|---|
| key door (`key_door.gd`) | `key2` while two padlocks are shut, `key1` with one (a keyhole opened swaps it) |
| boss door | `boss` (the gilded double door) |
| bolted door (`bolted_door.gd`) | `bolt` on the side the bolt slides from; on the far side (`bolt_here` off, R1's north door) `shutter`, the plain shut slab: the sheet has no wooden leaf without a bolt, and a door shut from the other side reads as a shutter, as in Zelda |
| shutter (`shutter.gd`) | `shutter` (the thorn-bordered block; it fades in and out as it rises and sinks) |
| the seal (`dungeon_seal.gd`) | `seal` (the white block with the dark pearl; its ring of light lies over the pearl) |
| plank barricade (`plank_barricade.gd`) | `barricade` (grey boards); smashed, nothing (the opening shows); the barricade turns with its `wall` like a door |
| cracked wall (`cracked_wall.gd`) | none: the wall's C block draws the crack; the blast turns every cracked block within three cells of it into H (`change_opening_at`; never a doorway or a door's block), which opens the passage; a wall already blown (its flag) is turned when the world is built |

The padlocks and the bolt are part of the leaf's picture (their old sprites hide); `interior_style`
names the sheet. Place a door object as today (DUNGEONS.md): on the floor line of the room its face
looks into, in the middle of the passage, `wall` that room's wall. With the rim two cells deep, for a
north opening whose block starts at column c on rows r, r + 1: (c + 1, r + 2) x 64; south (rows r,
r + 1): (c + 1, r) x 64; west (columns c, c + 1, from row r): (c + 2, r + 1) x 64; east: (c, r + 1) x 64.

## The sheet

`python scripts/art/pack-interior-walls.py [style]` cuts every piece from Magnific renders of whole
frames made from one reference frame, so their layouts match pixel for pixel and every piece shares
one stone, one scale and one light, and writes `godot/asset/MAPS/walls/interior/<style>.webp`,
`<style>-floor.webp`, `interior-walls.json` and the palette (`palette.png`, its tiles pictures of
the pieces, and `game/world/interior/interior_wall_tileset.tres`); then
`tools/pack_interior_palette.gd` saves the palette as `palette.res`, which the tileset uses (it needs
no editor import, so a repacked palette shows at once). 128 px per 64-unit cell, drawn at half size.
Each style has a fixed palette column (`column` in its `STYLES` entry: lair-stone 0, cave-rock 1,
root-rock 2), so a repack of one style never moves another's column (painted cells name their tile by
column), and the packer keeps the tileset's `uid`, so the room scenes that use it do not change.

The walls, the floor and every door's leaf share one read of each sheet (`InteriorWallLayer.picture`):
the packed file itself while it is newer than its import (an open editor imports it later), else the
import. In the editor the table and the sheets are read again once their files change (looked at
most once a second), so a repack shows on the layer's next redraw (paint a cell, or reopen the scene)
without restarting the editor; a door's leaf when the door is drawn again (reopen the scene). The
game reads them once.

`interior-walls.json`, per style: `model` ("bevel"), `texture`, `floor`, `floor_px`, `cell`,
`depth_cells` (2), `run_period` (per side), `pieces` (name -> sheet rect: the runs, the corners, the
inner corners, `<side>_<kind>` openings) and `leaves` (`<side>_<kind>` -> `region` and its top-left
inside its side's opening piece, `in_opening`).

**Cave rock and root rock** follow the same method: a doorway frame each made from the Lair's
(`cave-bevel-doorways-b`, `root-bevel-doorways-a`, with the style's elevation wall art as material
reference), one render per leaf and opening kind from it (`cave-bevel-*`, `root-bevel-*`), and a plain
floor each (`cave-floor.png`, `root-floor.png`; the busier first tries are `*-floor-busy.png`), which
keep their own colours (the Lair stone's cobble follows the Lair's ground).

**Lair stone** (GPT 2.5, `gpt-2-mini`, transparent, the Lili creation as style reference; the first
frame also took the owner's Zelda frame as structure reference), sources in
`asset/Originals/dungeon-kit/interior-walls/`:

| File | What | Used for |
|---|---|---|
| `lair-bevel-square-a`, `-b` | the plain bevel frame | the reference for the rest |
| `lair-bevel-doorways-b` (`-a` unused) | the frame with a doorway in each face | runs, outer corners, inner corners, doorways |
| `lair-bevel-doors-a` ... `-d` | first door trials | unused |
| `lair-bevel-leaf-key1`, `-key2`, `-boss`, `-bolt`, `-shutter`, `-seal`, `-barricade` | doorways-b with every doorway shut by one kind | the leaves |
| `lair-bevel-cracked`, `-blown`, `-stairs` | doorways-b with that opening in each face | those openings |
| `lair-floor-cobble` | a cobble texture | the floor (made seamless, colour-matched) |
| `lair-bevel-runs-wide`, `-runs-tall`, `-strip`, `-l`, `-plus-a`, `-plus-b` | long faces, an L and plus frames | unused: their blocks are another size, their inner corners too thin |

The earlier box-room renders (`lair-box-room-*`, `lair-l-room-*`, `lair-plus-room-*`) are the
rejected first look.

**Adding a style** (the Hollow's roots and oak, the Mine's rock and timber): generate its plain
bevel frame, then from it the frame with a doorway in each face, then from that one render per leaf
and per opening kind (the prompts say "exactly the first reference image ... the only change"), and a
floor texture; add the style to `STYLES` in the packer (its band edges, plain stretches, doorway boxes
and passages: measure them in the doorways render, and its `column`: the next free palette column)
and run it.

## The box-room lab

`game/dev/interior/box-room-lab.tscn` (`world.box-room-lab`; `?map=box-room-lab`), built by
`tools/build_box_room_lab.gd [-- --force]`: a shell with three room scenes in
`game/dev/interior/rooms/` (`a-square` 16 x 14; `b-l-room`, an L bigger than a screen with an
outline; `c-hall`, a long hall), every opening kind and door object, the Dungeon node, camera rooms,
the room mask. F6 on a room runs it. `tools/render_box_room_lab.gd -- --out=<dir> [--collision]`
(windowed) renders the whole lab, each room and close-ups.

## Fatty's Lair

The Lair is converted (2026-10-18; its scenes are edited in the editor since, the builder retired as a
writer: DUNGEON_ROOMS.md "Editing rooms by hand"): `tools/build_fattys_lair.gd` painted every room's rock (its
two-cell rim, R10's rock, the pockets of the map nook, the sally port and the bolt-hole) on the
`interior-walls` layer in the room's style, its doorways as opening blocks (`_opening`: both rooms'
rims, two along by two deep), the sally port's crack as a cracked block in both rims, and fits the
doors in the rims to the new floor lines (`_fit_doors_to_walls`: key, boss and bolted doors,
shutters, the seals, the Larder's and the Postern's plank barricades, R9's stone door with the
style's shutter as its slab). Since each room is its own world, the crack's two blocks are in two
worlds (R5's west rim, the sally port's east rim), each with its cracked wall on the one flag
(`fatty-lair.sally-port-open`): blown in one, the other is turned when its world is built (both
gone 2026-10-19: the sally port moved under C4, DUNGEONS.md "Secrets"). The Lair
has no latch doors left in built walls: R5's, R7's, C2's and the Old Armoury's became dividers
(FENCES.md "Dungeon dividers"), and R9's stone door, a latch door, is drawn by the room's wall (its
own frame hidden, its slab the style's shutter leaf: `sliding_slab.gd` `wall_leaf_style`). Burr's cell
door in the hub is a key2 block of the hub's rim (2026-10-19), its door drawn by the wall. Wall cells no piece covers
draw as the dark beyond the frame (`interior_wall_fill.gd`). Rooms grew to 18 x 16 cells rather than
shrinking their floors (DUNGEONS.md "Fatty's Lair (built)"). A side door's passage is
`interior.sideGapUnits` (120) tall, as the slime walks it at its feet; a north or south door's
`interior.gapUnits` (64) wide.

`test_interior_walls.gd` holds the Lair's rooms to their paint: every painted closed-door block has
exactly one door tagged with it, of its kind, wall and style, on its spot, and no opening cell lies
outside an opening block (the layer makes doors in the editor only, so a block a tool painted would
show a door and leave the passage open). Its `KNOWN_STALE_PAINT` is empty since R5 is one world
again (its rows 9-15 are its lower hall's and alcove's rim).

**Pits.** A spike or lava hazard draws its spikes only on the pit's visible floor
(`hazard.gd` `_pit_floor_cells`): under the far rim the wall hangs over the floor, beside a side rim
its strip; before 2026-10-18 the spikes covered the pit's walls and the pit read as flat floor.

## Limits

- The drawbridge and the Lair's drop gate do not draw wall leaves yet. A latch door takes the
  style's shutter leaf only through its slab's `wall_leaf_style`, its own frame hidden by hand (R9).
- A run's pieces under an opening show faintly through the opening's faded ends.
- The floor's quilting leaves a few joined stones where the texture wraps.
- Each floor cell takes the style of the nearest wall straight out from it (`floor_style` sets one
  for the whole layer), so a room painted in two styles shows two floors, parted where the nearest
  wall changes.

## Files

| Path | What |
|---|---|
| `godot/game/world/interior/interior_wall_layer.gd` | The layer: faces, corners, openings, floor, collision, leaves |
| `godot/game/world/interior/interior_wall_tileset.tres` | The palette (packer output) |
| `godot/asset/MAPS/walls/interior/` | The sheet, the floor, `interior-walls.json`, `palette.png` (packer output), `palette.res` (`pack_interior_palette.gd`) |
| `scripts/art/pack-interior-walls.py` | Builds them from the renders |
| `godot/tools/pack_interior_palette.gd` | Saves the packed `palette.png` as `palette.res`, the texture the tileset uses (no editor import) |
| `asset/Originals/dungeon-kit/interior-walls/` | The renders |
| `godot/tools/build_box_room_lab.gd`, `render_box_room_lab.gd` | The lab and its pictures |
| `godot/tools/render_interior_palette_room.gd` | A room painted with every closed-door tile, its doors made by the layer |
| `godot/tools/render_room_scene.gd` | One room scene alone, as the editor shows it |
| `godot/tools/render_doorway_passes.gd` | The slime halfway through a doorway on each side of a room, in the game |
| `godot/tools/render_room_collision.gd` | A room world in the game with its collision, decks and hazards drawn over it |
| `godot/game/world/interior/interior_wall_fill.gd` | The dark over wall cells no piece covers |
| `godot/game/world/painted_objects.gd` | What the layer may remove by itself: a door it made and nobody changed |
| `godot/tools/render_lair_room.gd` | In-game captures of a dungeon's rooms at a 16:9 window (`--all-rooms`) |
| `godot/tests/test_interior_walls.gd` | Faces and corners (the outer corners' fill and order), collision and passages, cracked to blown (every cracked block in reach), framed doors (the bolted door's far side, the barricade turned for a side wall), painted doors (also grouped under `Objects`), the Lair rooms' doors against their paint, the lab's assembly |
