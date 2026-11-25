# Dungeon room scenes

Built 2026-10-17 after the doorway review: the owner chose separate scenes per room and
Lair arches with two-cell openings. Since 2026-11-25 all three dungeons (Fatty's Lair, the Weaver
Hollow, the Crystal Mine) are one world per room, drawn by interior walls.

## Fatty's Lair: one world per room (2026-10-18)

The owner's decision of 2026-10-18 (the plan and its list of every link between rooms:
[docs/design/2026-10-18-lair-rooms-as-worlds.md](../design/2026-10-18-lair-rooms-as-worlds.md)):
**every room of Fatty's Lair is its own world**, built when the slime walks in, as Zelda does. Its
22 room scenes in `godot/game/scenes/worlds/rooms/fatty-lair/` are the worlds themselves; there is
no shell any more (the old `fatty-lair.tscn` that laid them side by side is gone). Nothing has to
fit together: a room's door names the room and the door it leads to. One world may hold several
rooms parted by low dividers inside it (the Zelda rule for divisions): R5's eye hall, lower hall and
key alcove are one world, `fatty-lair-r5-eye-hall`, three CameraRooms (the owner's choice,
2026-10-19). 50 room doors in 25 pairs join the worlds.

- **The worlds.** Each room scene has a `world-definition` (its map id, its size in cells), a
  `player-spawn` (at its `RoomEntry`), the Lair's Dungeon node (an instance of
  `game/scenes/objects/dungeon/fatty-lair-dungeon.tscn`, which holds the Lair's settings once: the
  seal, the roar, the entrance world, the records' id, the layout, the glimpse's pictures) and its
  room doors under `RoomDoors`. R1 the Gatehouse is the world `fatty-lair` (the way in: D5's mouth,
  old saves and the quests name it); every other room is `fatty-lair-<room scene name>`
  (`fatty-lair-r3-pit-hall`, `fatty-lair-r1-store`, ...), each a `world.<id>` line in
  `scene_index.json`. Rooms are **local**: a room's top-left corner is at its scene's origin.
- **F6 on a room** plays that room's world with the dungeon's direct-run powers (the Spear, the
  Roll and the Heavy skin: `dungeon.devPowers.fatty-lair`, looked up by the dungeon's id).
  `?map=fatty-lair-<room>` starts there too, and `?room=<room>` travels to that room's world, at its
  `RoomEntry`; the other dev options (`keys=<n>`, `bigkey`, `dmap`, `sealed`) apply there, once.
- **Going from room to room: the room doors** (`object.room-door`, `game/dungeon/room_door.gd`, its
  travel `game/dungeon/room_travel.gd`). A room door stands in a doorway's passage, on the room's
  edge (its position is the middle of the opening on the wall's outer edge). Pushing on through the
  passage into the edge **scrolls the screen** into the next room, as between chunks
  (`main.gd` `travel_through_room_door`, `game/world/chunk_scroll.gd`): the old room's picture slides
  out while the next room is built, laid so the two doors meet, and the slime walks in to the far
  door's arrival spot. Set in the Inspector, no typing of paths:
  - `door_id` (unique in the dungeon), `side` (the wall it is in);
  - `transition`: `scroll` (default, the slide) or `iris` (the closing and opening circle, for a
    closet or any room not beside this one: R1's store uses it on both its doors, 2026-10-18, owner:
    the slide showed the store's small room against the black around it);
  - `target_room`: a list of the dungeon's rooms (from the layout); `target_door`: a list of the
    doors in that room's scene;
  - `requires` (a list of the records this room's scene knows) and `locked_text`: a record that must
    be set before the door lets the slime through, when what holds the passage stands in the other
    room: `done:<door id>` (a kit door opened for good: the bolts' far sides, Burr's door),
    `gate:<gate id>` (a gate opened for good: R5's stone doors), `flag:<flag>` (a barricade
    smashed, the crack blown), `session:<name>` (R10's plate held down). While the
    record is not set the door refuses (`is_blocked`), saying `locked_text`, or nothing when it is
    empty (the crack or the barricade in the passage speaks for itself);
  - `width`, `depth` (the trigger in the passage), `arrival_inset` (how far in the slime arrives).
  In the editor it draws its passage, an arrow out and "door -> room / door", **red**, with what is
  wrong under it and a warning on the node (`pairing_problem`), while its target is not set, that
  door does not exist there, is not in the opposite wall (the slide would run the wrong way) or does
  not lead back to this door; in the game such a slide is warned too. What stands in the passage on
  this side (a bolted door, a barricade, a shutter, the seal, a stone door) blocks it as before: the
  trigger lies behind it. **Shut on one side, shut on both** (owner, 2026-10-19): what holds a
  passage from the other room shows on this side too, opening with it: a bolted door's far side is
  a `bolted-door` with `bolt_here` off and `link_id` set to the bolt's `door_id` (R1's north and
  west doors, R2's east, the hub's north, R8's west), and R10's south doorway has its own stone door
  (gate `fatty-lair-r9-north`, `open_while_record` the plate's record) that R10's plate opens and
  shuts with R9's. The passage of a north or south doorway is the middle 64 units of its two
  cells (the wall's collision), so the slime goes through it centred. The music carries on from room
  to room (as between a region's chunks). The Inner Stair and the crypt's stair back up (stair
  doors, `stair_door.gd` on `stair_hatch.gd`) go between worlds too (`target_world`,
  `target_door`: each names the other), with their walk and fade, and come out of the other stair
  facing into the room (docs/design/2026-10-31-crossings-and-arrivals.md).
- **Records instead of links.** Anything that ties two rooms is a record the other room reads when
  it is built. The kit keeps "done for good" under the dungeon's id, not the room's world
  (`Dungeon.record_map_id` = `fatty-lair`; `DungeonState.object_key`), so every bolt, door, bridge,
  risen chest and key keeps its record whatever room it is in, and saves made before the switch
  still fit. Gates, flags, chests (their `map_id` is `fatty-lair`), keys, the map and the seal were
  records already. A **session record** (`DungeonState.session_value`, RunState `dungeon_session`:
  kept while the run plays, never saved) carries what one room tells the next only while it lasts:
  R10's plate (`heavy_plate.gd` `hold_record`) holds R9's stone door (`gate.gd` `open_while_record`)
  under the same name, `fatty-lair.r10-plate-held`; the next far-off roar.
- **One area banner**: the rooms share their records' id as their title (`shell.gd`,
  `DungeonState.world_record_id`), so the banner shows once on the way in, not at every room door
  (specs/shell.md §4).
- **Each room built afresh**: ordinary enemies, pots, crates and pushed statues are back each time a
  room is entered (the owner's decision); won fights (`once`), the mini-boss and Fatty stay beaten
  by their records.
- **The map: the layout** (`game/scenes/worlds/rooms/fatty-lair/layout.tscn`, a DungeonLayout,
  `game/dungeon/dungeon_layout.gd`). Open it and **drag the rooms** (LayoutRoom nodes,
  `game/dungeon/layout_room.gd`, snapping to the 64-unit grid) where they lie on the map; a room's
  `room_scene` is picked in the Inspector and its world, CameraRoom name, size and outline are read
  from the scene (`read_again` reads it once more after its CameraRoom changed). A world of several
  rooms (R5) has a map room per CameraRoom, each naming the one scene and its `camera_room`; where
  that CameraRoom lies in the scene (`camera_offset`) places the world on the map. Drag rooms freely:
  `test_interior_walls.gd` checks that every pair of sliding room doors meets on the map. LayoutMark nodes
  (`layout_mark.gd`) put the skull over Fatty's room (once the map is held) and the seals' red bars
  on the map.
  The map screen and the minimap draw every room of the layout (`Dungeon.rooms`), the slime's own
  room where the layout puts it. The compass's chest dots cover every room too: the other rooms'
  chests are read from their scenes once a session (`Dungeon.layout_rooms_elsewhere`,
  `DungeonMapDraw.scene_chests`) and their records say which are opened. The world map counts every
  room world as the Lair, an interior of D5's region ("Current area").
- **The seal's glimpse** (the owner's decision): the take in the Larder no longer cuts the camera
  to R1; for an instant the screen shows **a picture of R1's doorway made in advance**, open, then
  with the boom the seal up (`Dungeon.glimpse_pictures`, `seal_moment.gd`). The pictures are
  `asset/MAPS/objects/fattys-lair/seal-glimpse-open.res` and `-shut.res`, captured by
  `tools/capture_lair_seal.gd` (windowed; run it again after repainting R1).
- **The pockets.** R1's store (through R1's barricade), Burr's cell (through his two-key door in
  the hub) and the map nook (R4's west gap) are worlds of their own, each a full box: its own two-cell bevel rim on every
  side, its way out a doorway block in it, the room door on the block's outer edge. In the parent
  world the pocket is rock behind the parent's own faces, the door cut into the parent's face (the
  hub's notch, columns 0-6 by rows 0-8, with Burr's key2 block at (2..3, 7..8); Burr waits in that
  door's passage behind the shut leaf and walks out into the hub when it opens). R5's lower hall and
  key alcove are not pockets but rooms of R5's world behind its two dividers (the eye gate under the
  eye latch, the alcove's eye gate under the timed pair; FENCES.md "Dungeon dividers"); the map
  shows them as rooms of their own (LayoutRoom `camera_room`).
- **The Lair's director** stands in each room that needs it, with that room's paths: the hub (Burr,
  his cell door, the Inner Stair), the arena (Fatty, his clods, his heart, the shutters; the
  map's boss mark), the Larder (the Pearl's glow). R4's has none set since its room fight
  (2026-10-28): its Squints (two since 2026-11-21), and its west shutter (to the map nook) and south
  one (to R5), shut (`starts_shut`) each time the room is built, sink once no living enemy is left in
  the room (DUNGEONS.md "Shutters and room fights": however many the scene holds).
- **Elevation**: each room world with painted holes has its own baked cache
  (`elevation_cache/rooms__fatty-lair__<room>.res`; `tools/bake_elevation.gd -- --world=<id>`).

Tests: `tests/test_lair_rooms.gd` (the layout and the door pairs, every door both ways with the
scroll, the doors that wait for a record, what is done kept across rooms and a quit and a load,
enemies back with their room, a walk from D5's mouth to Fatty's arena and out by the bolt-hole) and
`tests/test_fattys_lair.gd` (each piece in its room's world).

**Editing by hand.** The room scenes are the source of truth (owner, 2026-10-18): edit them in the
editor; `tools/build_fattys_lair.gd` is retired for the Lair and refuses to write (it would bring
back the old shell); the room splitter is deleted (2026-11-25).

## The Weaver Hollow and the Crystal Mine: one world per room (2026-11-25)

Both are built as the Lair is (above): the Weaver Hollow's 23 room worlds in
`godot/game/scenes/worlds/rooms/weaver-hollow/` (step 3 of the dungeons rework) and the Crystal
Mine's 15 in `rooms/crystal-mine-rooms/` (step 4), each `world.<id>` in `scene_index.json`, with
their Dungeon nodes instances of `weaver-hollow-dungeon.tscn` and `crystal-mine-dungeon.tscn`, their
map `layout.tscn`, room doors that scroll and interior walls ([DUNGEONS.md](DUNGEONS.md#the-weaver-hollow-built),
[the Mine](DUNGEONS.md#the-crystal-mine-built)). `tools/build_weaver_hollow_rooms.gd` and
`tools/build_crystal_mine_rooms.gd` wrote their first versions and refuse to overwrite a hand-edited
room without `--force`: **the scenes are edited by hand.**

*Until 2026-11-25 the Hollow was four floor worlds, each a shell assembling its rooms (22 room
scenes in `rooms/weaver-hollow-{trunk,roots,boughs,crown}/`), and the Mine one world
(`crystal-mine.tscn`, its 14 `rooms/crystal-mine/M*.tscn` copies unused), written by their builders
through a room splitter (`tools/lib/dungeon_room_splitter.gd`, `tools/split_dungeon_rooms.gd`, which
kept a `written.json` of hashes to skip hand-edited rooms). Step 5 of the rework deleted all of them
([the archive](../archive/2026-11-25-old-hollow-and-mine.md)).* The shell itself
(`room_scene_shell.gd`: room scene instances under `RoomScenes`, assembled before gameplay nodes
enter the tree, each instance's `position` its offset in cells) stays for the box-room lab
(`?map=box-room-lab`); `tools/verify_scenes.gd` checks a shell as saved, its rooms not assembled
(`assemble_on_instantiate`).

## Room outlines and visibility

A CameraRoom's optional `outline` is a simple local polygon with up to 64 vertices; empty
uses its `size` rectangle. Camera and Dungeon use `contains` for room membership. Camera
movement clamps to the outline's bounding box, and the dungeon map draws the polygon.
The Pit Hall is an L round Burr's cell (its own world since 2026-10-18); the Hollow's map nook has a
separate outline to conceal its contents.

`room_mask.gd` draws darkness outside the current outline on CanvasLayer 4, beneath the
arrival fade and HUD. Its screen-space shader follows window size, camera motion, shake
and zoom. During a room scroll it shows the destination outline; a scripted seal glimpse
uses the camera's room. A room drawn by interior walls shows nothing past its outline: its own rim
is its edge. *Until 2026-11-25 the mask also left the cliff-wall doorway frames of the four-floor
Hollow and the one-scene Mine (`doorway_art.gd`) visible at a room's edge; that went with them.*

## Doorway pieces (the cliff-wall look, retired)

Before interior walls, the four-floor Hollow and the one-scene Mine drew continuous wall courses
round each room with wall-owned arches in their openings (`doorway_art.gd`: key, boss and bolt
doors moving only their leaves, shutters and seal blocks inside a fixed arch, cracks as whole pieces
of the wall's style, in masonry, root rock, cave rock or crystal rock). That script went with those
worlds at step 5 of the dungeons rework (2026-11-25). Its textures stay in
`godot/asset/MAPS/objects/dungeon/doorways/`: the shared `object.latch-door` prefab uses the
masonry arch and shutter leaf (in the Lair the only latch door left is R9's, drawn by the room's
wall; the others became dividers, FENCES.md "Dungeon dividers"), and the runaway carts' tunnels the
mine gate's leaves (`ram_cart.gd`). `python scripts/art/pack-doorway-art.py` cuts the generated
sheets into those pieces and `tools/pack_doorway_textures.gd` saves them as native compressed
ImageTexture `.res` resources (no editor import). The two-cell door collision is 128 units.

## Verification

`test_dungeon_rooms.gd` checks that the Lair's rooms are worlds that keep their links (the Inner
Stair, Burr's director in the hub), Burr's hidden cell and the hub's L-shaped mask, the stone
arch/leaf split, two-cell collision, and that every room world of the rebuilt Hollow and Mine reads
its dungeon's id and record (and no retired world is left in the scene index). The Lair, Hollow,
Mine, seal, kit and camera tests cover the shared gameplay. The walks of
`tools/film_weaver_hollow_rooms.gd` and `tools/film_crystal_mine_rooms.gd` play the two rebuilt
dungeons room by room (`--film=look` takes a still of a room in the game). *The wide-screen review
captures of the old doorways (`output/doorway-review/live-*-wide.png`, by the retired
`tools/render_dungeon_room_views.gd`) are history.*

## Interior walls

The owner rejected the walls' art and how they are painted (elevation cliffs plus
`doorway_art.gd`'s frames round the room's rectangle), not the room scenes. Their replacement is the
InteriorWallLayer ([INTERIOR_WALLS.md](INTERIOR_WALLS.md)), painted in each room scene. **Fatty's Lair
is converted** (2026-10-18): each room world paints its own rim on its `interior-walls` layer in the
room's style (first painted by the builder, retired since: the scenes are edited by hand), and the
Lair never went through `doorway_art.gd`. The Hollow and the Mine converted with their rebuild
(2026-11-25), and `doorway_art.gd` went with their old worlds.

## Camera rooms in the editor

The **Camera Room Handles** plugin is on (`project.godot`; Project > Project Settings > Plugins;
`godot/addons/camera_room_handles/`). Select a room's node under `CameraRooms`:
- without an `outline`, a dot sits on each corner of its `size` rectangle: drag one to resize (the
  opposite corner stays put; the top-left one moves the node; one 64-unit cell at least, and a room
  smaller than a screen is fine: the camera grows it about its middle to the view);
- with an `outline` (it wins over `size`), a dot sits on each point: drag it, double-click an edge to
  add a point (up to 64, the most the room mask cuts; a room with more shows a warning), right-click
  a point to remove it (three at least).
Moves snap to the world's 64-unit grid, also in a room or under a parent placed off the grid (hold
Alt for free moves); each drag that changes something is one undo step. Escape during a drag puts
the room back; a release outside the 2D view ends the drag where it was.

