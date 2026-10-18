# Doorways in walls, doors on the room's edge

> **Status:** review choices received and implementation built (2026-10-17). The owner
> chose separate room scenes and two-cell arches. There are 60 editable room scenes,
> an outline mask, the L-shaped Pit Hall/Burr cell split and wall-owned doorway art.
> See [Dungeon room scenes](../godot/DUNGEON_ROOMS.md). Owner visual acceptance remains.

## The owner's words (2026-10-17)

1. "we need to really work in doors as part of the walls, they need to integrate with the wall
   seamless, see in zelda how the door looks like part of the map while in our case it just looks
   like the tile that was dropped there for no reason. see the different examples for door and wall
   holes in zelda they all make part of the map."
2. "what also works in zelda is that doors are always at the edge of the scenes or chunks so you
   never see what is behind them. they cut dungeons in several scenes, not like us that have 1 big
   scene for the whole lair, and that is why doors seem off place."
3. (Correction, relayed) Rooms do not have to be one screen. Rooms can be bigger and the camera moves
   inside them. The golden rule is only: doors always sit at the edges of the room (in its outer
   wall, where the room's camera area ends), so crossing a door goes to the next room with a scroll
   and nothing behind a door is seen.
4. (Relayed) Rooms do not have to be squares: L-shapes, long halls, irregular caves. The
   doors-on-the-room's-edge rule fixes 90% of the problem; the rest is doors whose art really
   matches the wall.

His references (session images 7, 11, 12: Link's Awakening): a door set into a north wall with the
wall's top and frame running round it; a north wall with an open doorway, a shutter, a bombed hole
and a stair opening, all cut into the wall's own art; an east wall with a doorway and a bombed hole
seen from the side. His pictures of ours (8, 9, 10): Fatty's Lair doors standing in a gap between
two rounded wall ends, a door picture pasted in.

## What we have (findings)

**How a dungeon wall is made.** All three dungeons are one world each (the Weaver Hollow one per
floor) painted on the elevation layer: a mass of rock at level 2 with each room carved out to level
0, keeping a one-cell rim, so two rooms are parted by a two-cell band (DUNGEONS.md "The paint" for
each dungeon). The "walls" are therefore **cliffs** (ELEVATION.md "Side walls"):

- a room's **north wall** is the front face of the band above it: two courses (128 units) of the
  style's wall art hanging below a one-cell rock top (the Lair's top is forest floor, the dark green
  band in every picture);
- its **east and west walls** are side strips 24 units wide;
- its **south wall** has no face at all: it is the back edge of the band below (a top edge and a
  shadow);
- every **doorway** is a two-cell gap carved through the band (an east-west one also clears the two
  rows its lintel hangs over). Side walls have round corners (`RADIUS_OUTER` 40), so each gap is a
  little corridor between two rounded wall ends: the "wall caps either side" of his picture 8.

**How a door is drawn.** The kit draws no walls (DUNGEONS.md "Walls and doorways"). Each door is a
free-standing picture placed in the gap (`game/dungeon/dungeon_door.gd`, `shutter.gd`,
`dungeon_seal.gd`), turned with `wall` (east, south and west turn the front art; side walls also
squash it to `SIDE_DEPTH` 0.55). Why each reads as pasted:

| Piece | Art | What is wrong |
|---|---|---|
| Small-key door (1 and 2 locks), bolted door | `door-2x1.webp`: an oak leaf in its own grey carved-stone arch, 233 x 214 units | its arch is a different stone from every wall (grey carved fort stone, not the Lair's cream masonry, the Hollow's root rock or the Mine's crystal rock); it is 3.6 cells wide in a 2-cell gap, so its jambs lie over the rounded wall ends; it stands 3.3 rows tall, over the face and the rock top, past the room's top edge; no lintel, the wall's courses stop at the gap |
| Boss door | `boss-door-2x1.webp`, 265 x 231 units | the same, bigger; on the hub's north wall its arch rises over the dark rock band |
| Doors in a south wall | the front art turned 180° | an upside-down arch in an empty gap of the back edge (the hub's bolted door to R1, R11's way back, seen from the hub as an upside-down door on top of the masonry face) |
| Doors in an east or west wall | the front art turned 90°, squashed | a sideways door sticking out of a 24-unit strip into the next room (R5's way back, R7's, the Hollow's east key door, the Mine's boss door) |
| Shutter | `shutter.webp`, a loose stone block | sits in the gap like a crate; turned for south and side walls |
| The seal | `dungeon-seal.webp` (white block, dark pearl) | a white block in front of the face (R13), upside down at a south doorway (R1, T1, M1), half under the HUD |
| Cracked wall | `crack-overlay.webp` decal on a face | fine on a north face (the Hollow's Larder); on a side strip (R5's west wall, the sally port) the decal lies on the rock top, not on a wall |
| Blown hole | `hole-overlay.webp`, a round dark decal with a rubble rim | a black disc on the face (Larder) or on the rock top (R5), not a hole through the wall's courses |
| Stone doors (`latch-door`) | `stone-door-frame.webp` at 0.55 | a tall pale frame in a one-cell gap of a built fieldstone wall: a third stone style in the same room (R5, the Weigh House) |
| Plank barricade | `plank-barricade-2x1.webp`, its own wood frame | stands on the face (the Larder's north doorway) |
| Floor ways (the Inner Stair hatch, the Hollow's latched hatch, ladders) | props on the floor | fine as floor objects; not wall openings |
| The Mine's own (lantern gate, rotten timbers, iron shutter) | own frames | the same frame-in-a-gap look; the iron shutter is the kit's turned block |

Every kit door uses the same grey stone arch in all three dungeons, so in the Hollow (root rock) and
the Mine (crystal rock) it matches nothing at all.

**How rooms meet the screen** (`game/world/camera_room.gd`, `world_camera.gd`). Camera rooms are
rectangles (each dungeon room is one, 16 x 14 cells or a whole number of screens) and the view keeps
inside the room, sliding over `ROOM_SLIDE_MS` (450) when the slime walks into another: the scroll is
already there. The room's edge runs through the middle of the band, so the doors already sit on
room edges in the cells. But:

- `fit_to_view` grows a room to the view when the window is wider than 16 tiles. The viewport is
  1024 x 1024 with `stretch/aspect = expand`, the HUD takes the bottom 128: the play area is 1024 x
  896 only at an 8:7 window. The default window (2048 x 1792) shows 18.3 cells across; a **16:9**
  screen (the web build in a normal browser) shows **28.4 cells**: six cells of each neighbouring
  room on either side. In `current-view-lair-r1-16x9.png` R5 and R2 are in view beside R1; in
  `current-view-lair-r5-16x9.png` the sally port and its chest show behind the cracked wall that is
  meant to hide them. A wall's door is seen from both rooms at once, with the room behind it.
- The zoom keys (0.5 to 1.25) grow the view further.
- North doors stand three rows into the room and rise over the band past the room's top edge, so
  part of every north door is drawn in the room above too (`current-01`: the bolted door of R11 seen
  from the hub as an upside-down arch over the hub's wall).
- Camera rooms are rectangles only; no L-shaped or irregular room.

## The proposal

### 1. The room-edge structure (the 90%)

- **A room is any shape**: a CameraRoom gets an outline (a polygon, or a list of rectangles joined),
  the camera clamps to its bounding box and moves inside it as today.
- **Nothing outside the room is drawn on screen**: where the view is wider or taller than the room
  (a wide window, zoom out, an L's missing corner), everything past the room's outline is covered by
  the dungeon's darkness (a screen-space mask in the world camera's layer, drawn from the room's
  outline, under the HUD). This is what makes "you never see what is behind a door" true on every
  screen; Zelda gets it from a fixed screen size, we get it from the mask.
- **Doors only in a room's outer wall**, on its outline, half the doorway in each room's wall. The
  slime walks into the doorway, the view scrolls to the next room (the existing room slide; at the
  same time the mask switches from one outline to the other), and the slime steps out on the far
  side. No door ever stands inside a room or in a wall between two parts of one room.
- **Way (a) recommended: keep one scene per dungeon**, with room outlines and the mask. It keeps the
  dungeon map, keys, DungeonState records, the seal, room fights, the builders and the tests as they
  are; the room slide already exists. Cost: CameraRoom outlines, the mask, the builders write
  outlines (each builder's room table already knows each room's cells), RoomFight's `size` takes the
  outline. About 2 to 3 days with the three builders and tests.
- **Way (b), one scene per room** like the overworld's chunks (the owner's "they cut dungeons in
  several scenes"): every door a world travel with the chunk scroll (`chunk_scroll.gd`). Breaks or
  must change: the dungeon map (draws only the world it is in: it would need every room's scene
  read), the minimap, DungeonState records (already per map id; they would span many map ids), the
  seal (its glimpse cuts to a seal in another scene: not possible; the take's camera cut would go),
  room fights spanning two scenes, the Lair's director (Burr, the drawbridge, the counterweight cross
  rooms), drop gates and winches with targets in other rooms, the elevation bake per scene, load on
  every door (a chunk build is 0.3 to 0.7 s on desktop, longer on the web), 30+ new scenes and the
  tests. About 1 to 2 weeks. It gives nothing the mask does not, so (a) is the proposal; (b) stays
  open if he wants separate scenes for editing.

### 2. Doorways that are part of the wall (the 10%)

- **The wall paints its doorways.** The builder (or a new `doorways` paint on the elevation layer,
  as the `cliffs` layer paints styles) marks a doorway cell pair in a wall; the wall then draws a
  doorway piece there instead of its plain courses: the wall's own top course running over the
  opening as the lintel, jambs in the wall's own stone, the dark of the passage, a threshold. The
  rounded wall ends at a doorway go (the gap is no longer a corridor between two cliff ends).
- **Door objects draw only what changes inside the opening** and keep all their logic: the leaf
  (oak, the boss door's gilded double leaf), the padlocks, the bolt, the shutter block rising out of
  the threshold, the seal's block and ring, an open doorway's darkness. Their art is cut to the
  opening, so it never overlaps the wall.
- **Cracked walls and blown holes become wall pieces**: a cracked stretch of the wall's courses,
  and a ragged hole through them with rubble at the foot (no decal on a rock top).
- **Per wall direction, the Zelda way (the box room):** Link's Awakening draws all four walls of a
  room as one wall art turned to face into the room (the north face at full height, the side and
  south walls the same art turned), and a door is the same piece turned with its wall. So one set of
  north pieces per style gives every direction, and a door always matches its wall because it is
  cut from it. Our side walls would grow from a 24-unit strip to about a cell (the rim plus a short
  face), and the south wall would show its face turned (short, mostly its top course). The other way,
  keeping our 3/4 cliffs, needs a second and third piece set per style (a side view and a back view),
  which Magnific does badly (the side view tried in `lair-side-south-a.png` came out as a leaning
  pillar).
- **Styles:** the Lair's cream masonry (the fort) and its root rock (the arena, the Burrow) and cave
  rock (the Deep); the Hollow's root rock; the Mine's crystal rock with timber frames (its cave rock
  shares the crystal pieces with another wall strip). Five styles: masonry, root-rock, cave-rock,
  crystal-rock with timber, plus the Hollow's root arches (root-rock with a different doorway shape).

**What changes in code** (when built): `camera_room.gd` (an outline), `world_camera.gd` (clamp to
the outline's box, the outside mask, the switch on a room slide), the elevation side walls
(`elevation_sides.gd`: skip the rounded ends at a marked doorway, draw the doorway piece, or the box
room's own wall drawing for dungeon rooms), `dungeon_door.gd`, `key_door.gd`, `bolted_door.gd`,
`shutter.gd`, `dungeon_seal.gd`, `cracked_wall.gd` (draw only the leaf or block; per-direction
pieces instead of turning), the three builders (`build_fattys_lair.gd`, `tools/weaver_hollow/`,
`build_crystal_mine.gd`) and `build_dungeon_lab.gd` (room outlines, doorway marks), tests. **Art:**
per style a plain wall piece, an arched doorway, a square doorway, a cracked stretch, a blown hole
(generated for three styles already, below), the leaves (generated) and corner pieces (not yet).
**Size:** part 1 about 2 to 3 days; part 2 about 4 to 6 days (the box-room walls are the big part),
plus the owner's look reviews.

## Pictures

In the session scratchpad `doorways/` (`C:/Users/User/AppData/Local/Temp/claude/D--projects-Slime-isa/d7bd2373-3736-4954-b268-3118bdde4560/scratchpad/doorways/`),
rendered with the game's own drawing at 2 px a unit (the views at 1 px a unit):

- `current-view-lair-r1-16x9.png`, `current-view-lair-r5-16x9.png` (show these first): what a 16:9
  screen shows of R1 and R5: the rooms beside them, the sally port's chest behind the crack.
  Also `current-view-lair-hub-16x9.png`, `-r13-16x9.png`, `current-view-hollow-t1-16x9.png`,
  `current-view-mine-m1-16x9.png`, `current-view-lair-r1-default-window.png` (the default window).
- `current-01-lair-hub-north-south-west.png`: the boss door, Burr's two-lock door, the bolted door in
  the south wall, R11's bolted door upside down over the hub's wall, the open west doorway.
- `current-02-lair-r5-east-bolt-west-blown-hole.png`: the bolted door turned in the east wall, the
  blown hole on the west wall's rock top, the stone doors in the built wall.
- `current-03-lair-r13-seal-north.png`, `current-04-lair-r1-r12-r7.png` (the seal south, the Larder's
  barricade and shutter, R7's turned bolted door), `current-05-hollow.png`, `current-06-mine.png`
  (shutters and seals raised, cracked walls blown: the "shut" renders).
- `current-00-kit-door-art.png`: the kit's door, boss door, shutter, seal, bolt, padlocks, the Lair's
  stone door, barricade, hatch and drop gate.
- `mockup-00-generated-doorway-pieces.png`: the new pieces (below), not yet composited.

`work/` holds every raw render (`*-built.png`, `*-shut.png`); `render_doors.gd` there renders any
world rect (windowed: `--path godot -s <it> -- --scene=res://... --out=<dir> --rect=name:x,y,w,h
[--zoom=1] [--built-only]`).

## Art generated (Magnific GPT 2.5, `gpt-2-mini`, 1k, transparent, the Lili creation as style reference)

Six generations, **600 credits** (balance before: 356,341). Sources in
`asset/Originals/dungeon-kit/doorways/`, each a 2 x 2 sheet unless said, the second reference our
own wall rendered in the game:

| File | What | Verdict |
|---|---|---|
| `lair-north-pieces-a.png` | masonry: arched doorway, blown hole, cracked wall, plain wall | good; doorway too narrow |
| `lair-north-pieces-b.png` | masonry, three courses: arched doorway, square lintel doorway, cracked, blown hole | the one to use; the openings are about 0.5 of the wall's height, so widen them (stretch the middle) to the two-cell gap |
| `lair-leaves-a.png` | leaves alone, round top: oak with iron bands (a space for padlocks), the gilded boss double leaf with the sapphire lock, a limestone shutter block with a thorn border, oak with a sliding bolt | good, to fit into the arch |
| `lair-side-south-a.png` (one wide sheet) | an east-wall doorway and a south-wall doorway | rejected: a leaning pillar and a front view; supports the box-room way |
| `hollow-north-pieces-a.png` | root rock: root-arch doorway, the same with a bark leaf, cracked, blown hole | good |
| `mine-north-pieces-a.png` | crystal rock: timbered doorway, the same with an iron shutter, cracked, blown hole | good |

The reference uploads (crops of our renders and the kit door) are throwaway working assets.

## Open choices for the owner

1. Way (a), one scene per dungeon with room outlines and the darkness past them, or way (b), one
   scene per room?
2. Past a room's outline: darkness (as proposed), or the rock top drawn plain?
3. The box room (all four walls drawn as the north wall turned, Zelda's way) or keep our cliffs and
   draw separate side and back doorway pieces?
4. Arched or square (lintel) doorways for the Lair; root arches for the Hollow; timber frames for
   the Mine?
5. Doorway width: keep two cells (the art widened) or narrow to one and a half cells to fit the
   pieces as drawn?

## Next steps (for whoever continues)

1. Composite the mockups (not done): `scratchpad/doorways/build/pieces.py` has the cutting helpers
   (`quad` cuts a sheet's quarter, `widen` stretches a band, `fit_h` scales; `opening` does not work
   yet: find the opening by hand). Build at 128 px a cell: floors cut from the renders in `work/`
   (the Lair's cobble from `work/lair/r13-built.png`'s middle, mirror-tiled; the Hollow's leaves from
   `work/hollow/larder-built.png`; the Mine's cavern from `work/mine/foreman-built.png`); the north
   wall three rows (coping and two courses) from `lair-north-pieces-b.png`, its plain piece repeated
   and the doorway pieces set in; side and south walls the same pieces turned (and foreshortened),
   corners from coping blocks; leaves from `lair-leaves-a.png` scaled into the arch; padlocks from
   `godot/asset/MAPS/objects/dungeon/padlock-2x1.webp`, the seal from `dungeon-seal.webp`; a soft
   shadow under the north wall.
2. Mockups wanted: `mockup-lair-room.png`: an **L-shaped** Lair room bigger than a screen, its four
   walls with an open doorway, a small-key door (two locks), the boss door, a shutter, a bolted
   door, a cracked wall and a blown hole, side by side with `current-01`; `mockup-lair-screen.png`:
   one screen of it at 1024 x 896 and at 16:9 with the darkness past the outline, beside
   `current-view-lair-r1-16x9.png`; one sample each for the Hollow and the Mine from their sheets.
3. Show him the pictures first (the views, then the mockups), ask the open choices, then build.


## Continuation review (2026-10-17)

`python scripts/art/build-doorway-mockups.py` composites the existing pieces at 128 px per cell.
Review `output/doorway-review/doorway-comparison.png`, `mockup-lair-room.png` (an L larger
than a screen with open, key, boss, shutter, bolt, cracked and blown openings), the
`mockup-lair-screen-8x7.png` and `mockup-lair-screen-16x9.png` viewport crops, plus
`mockup-hollow-room.png` and `mockup-mine-room.png`. These are art/structure studies, not
screenshots of implemented gameplay. The Lair's openings still need final width/corner polish.
The five design choices above remain open; the review asks for scene/mask direction and
arch/lintel/width preference before replacing the game's dungeon walls.
No additional image generations or credits were used.


## Owner choices and implementation (2026-10-17 continuation)

The owner selected **separate scenes per room** and **arches, two cells wide**. The
implementation uses separately authored room scenes assembled by a shared dungeon shell;
the dungeon ids, cross-room puzzle targets and records remain stable. Darkness hides the
room beyond on wide screens and at every zoom. Burr's cell is a separate scene and the
Pit Hall has an L-shaped outline. Runtime captures: `output/doorway-review/live-*-wide.png`.
The Hollow uses root arches, the Mine timber frames. No additional generation credits.
The earlier open-choices list and estimates above are the original study, superseded by
these choices. The shell and room files are detailed in `docs/godot/DUNGEON_ROOMS.md`.


## Owner's idea: interior walls on all four sides (2026-10-17, next to build)

The owner, after the room scenes: "the other agents haven't been able to figure out a right way to
build interior walls, i have an idea, we will use a different script for interior walls and all
four sides will show, that will make south gates easy to place and bend with the walls, take
Zelda's idea of interior walls." His reference, a Zelda sprite sheet of interior walls in every
direction with their doors and corners: `asset/Originals/dungeon-kit/doorways/reference/zelda-interior-walls-sheet.png`.

What it asks for (the box room, open choice 3 above):

- **A new wall script for interiors only**, separate from the overworld's elevation cliffs and the
  stone WallLayer: a painted (or outlined) interior wall layer that draws a room's border wall on
  **all four sides**, each facing into the room as in Zelda (north seen from the front, south seen
  from its back with its top course towards the camera, east and west in their own side view),
  with inner and outer corners, and the dungeons' walls stop being elevation cliffs.
- **Doors and openings are pieces of that layer** for each side: open doorway, key door, boss door,
  shutter, bolted door, the seal, cracked wall and blown hole, stairs; a south door is drawn as
  part of the south wall (no upside-down north door), and every piece bends with the wall's
  corners. Door objects keep their logic and draw only what changes (leaf, padlocks, bolt, block).
- **Shapes and the edge rule stay:** rooms of any shape and size, doors on the room's edge (the
  room scenes and outline mask built above).
- **Art:** one sheet per wall style (the Lair's fort stone first, then the Hollow's roots and the
  Mine's timber), laid out like the reference: straight runs for each side, inner and outer
  corners, and each opening in all four directions, at 128 px per 64-unit cell.

Next step: a mockup of one Lair room with all four walls and a door on each side for the owner's
approval, then the script, then the Lair, the Hollow and the Mine.

