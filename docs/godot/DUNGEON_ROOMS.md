# Dungeon room scenes

Built 2026-10-17 after the doorway review: the owner chose separate scenes per room and
Lair arches with two-cell openings. The Hollow uses root arches; the Mine timber frames.

## Fatty's Lair: one world per room (2026-10-18)

The owner's decision of 2026-10-18 (the plan and its list of every link between rooms:
[docs/design/2026-10-18-lair-rooms-as-worlds.md](../design/2026-10-18-lair-rooms-as-worlds.md)):
**every room of Fatty's Lair is its own world**, built when the slime walks in, as Zelda does. Its
24 room scenes in `godot/game/scenes/worlds/rooms/fatty-lair/` are the worlds themselves; there is
no shell any more (the old `fatty-lair.tscn` that laid them side by side is gone). Nothing has to
fit together: a room's door names the room and the door it leads to.

- **The worlds.** Each room scene has a `world-definition` (its map id, its size in cells), a
  `player-spawn` (at its `RoomEntry`), the Lair's Dungeon node (an instance of
  `game/scenes/objects/dungeon/fatty-lair-dungeon.tscn`, which holds the Lair's settings once: the
  seal, the roar, the entrance world, the records' id, the layout, the glimpse's pictures) and its
  room doors under `RoomDoors`. R1 the Gatehouse is the world `fatty-lair` (the way in: D5's mouth,
  old saves and the quests name it); every other room is `fatty-lair-<room scene name>`
  (`fatty-lair-r3-pit-hall`, `fatty-lair-r1-store`, ...), each a `world.<id>` line in
  `scene_index.json`. Rooms are **local**: a room's top-left corner is at its scene's origin.
- **F6 on a room** plays that room's world with the dungeon's direct-run powers (the Spear and the
  Roll: `dungeon.devPowers.fatty-lair`, looked up by the dungeon's id). `?map=fatty-lair-<room>`
  starts there too, and `?room=<room>` travels to that room's world, at its `RoomEntry`.
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
    smashed, the crack blown, the nook's gap), `session:<name>` (R10's plate held down);
  - `width`, `depth` (the trigger in the passage), `arrival_inset` (how far in the slime arrives).
  In the editor it draws its passage, an arrow out and "door -> room / door", **red** while its
  target is not set or that door does not exist there. What stands in the passage on this side (a
  bolted door, a barricade, a shutter, the seal, a stone door) blocks it as before: the trigger lies
  behind it. The passage of a north or south doorway is the middle 64 units of its two cells (the
  wall's collision), so the slime goes through it centred. The Inner Stair and the crypt's ladder go
  between worlds too (`stair_hatch.gd` `target_world`, `target_marker`), with their fade.
- **Records instead of links.** Anything that ties two rooms is a record the other room reads when
  it is built. The kit keeps "done for good" under the dungeon's id, not the room's world
  (`Dungeon.record_map_id` = `fatty-lair`; `DungeonState.object_key`), so every bolt, door, bridge,
  risen chest and key keeps its record whatever room it is in, and saves made before the switch
  still fit. Gates, flags, chests (their `map_id` is `fatty-lair`), keys, the map and the seal were
  records already. A **session record** (`DungeonState.session_value`, RunState `dungeon_session`:
  kept while the run plays, never saved) carries what one room tells the next only while it lasts:
  R10's plate (`heavy_plate.gd` `hold_record`) holds R9's stone door (`gate.gd` `open_while_record`)
  under the same name, `fatty-lair.r10-plate-held`; the next far-off roar.
- **Each room built afresh**: ordinary enemies, pots, crates and pushed statues are back each time a
  room is entered (the owner's decision); won fights (`once`), the mini-boss and Fatty stay beaten
  by their records.
- **The map: the layout** (`game/scenes/worlds/rooms/fatty-lair/layout.tscn`, a DungeonLayout,
  `game/dungeon/dungeon_layout.gd`). Open it and **drag the rooms** (LayoutRoom nodes,
  `game/dungeon/layout_room.gd`, snapping to the 64-unit grid) where they lie on the map; a room's
  `room_scene` is picked in the Inspector and its world, CameraRoom name, size and outline are read
  from the scene (`read_again` reads it once more after its CameraRoom changed). LayoutMark nodes
  (`layout_mark.gd`) put the compass's skull over Fatty's room and the seals' red bars on the map.
  The map screen and the minimap draw every room of the layout (`Dungeon.rooms`), the slime's own
  room where the layout puts it.
- **The seal's glimpse** (the owner's decision): the take in the Larder no longer cuts the camera
  to R1; for an instant the screen shows **a picture of R1's doorway made in advance**, open, then
  with the boom the seal up (`Dungeon.glimpse_pictures`, `seal_moment.gd`). The pictures are
  `asset/MAPS/objects/fattys-lair/seal-glimpse-open.res` and `-shut.res`, captured by
  `tools/capture_lair_seal.gd` (windowed; run it again after repainting R1).
- **The pockets** are rooms of their own: R1's store (through R1's barricade), R5's lower hall
  (through the stone door under the eye latch: the eye hall has its own leaf of that door), R5's key
  alcove (through the alcove's stone door), Burr's cell (through his door in the hub; Burr himself
  stands in the hub's world behind it, so he walks out into the hub), the map nook (R4's west gap)
  and the sally port (R5's crack; the sally port has its own blown side of it). The lower hall, the
  alcove and Burr's cell were given an `interior-walls` layer of their own, a copy of the rim they
  used to share with the eye hall and the hub.
- **The Lair's director** stands in each room that needs it, with that room's paths: the hub (Burr,
  his cell door, the Inner Stair), the arena (Fatty, his clods, his heart, the shutters; the
  compass's mark), the Larder (the Pearl's glow), R4 (the nook's gap, kept by
  `fatty-lair.nook-gap-open`).
- **Elevation**: each room world with painted holes has its own baked cache
  (`elevation_cache/rooms__fatty-lair__<room>.res`; `tools/bake_elevation.gd -- --world=<id>`).

Tests: `tests/test_lair_rooms.gd` (the layout and the door pairs, every door both ways with the
scroll, the doors that wait for a record, what is done kept across rooms and a quit and a load,
enemies back with their room, a walk from D5's mouth to Fatty's arena and out by the bolt-hole) and
`tests/test_fattys_lair.gd` (each piece in its room's world).

**Editing by hand.** The room scenes are the source of truth (owner, 2026-10-18): edit them in the
editor; `tools/build_fattys_lair.gd` and the splitter are retired for the Lair and refuse to write
(they would bring back the old shell).

## The Weaver Hollow and the Crystal Mine: rooms of a shell

The authored rooms are in `godot/game/scenes/worlds/rooms/<world>/<room>.tscn`: 22 across the
Hollow's four floors and 14 in the Mine. Open a room to edit its terrain, walls, objects and
CameraRoom. F6 starts that room in the full game with the dungeon's normal direct-run powers.

Their rooms are written in dungeon coordinates (instance offset zero). The parent world is a shell
holding the world definition, Dungeon node, shared logic and room scene instances.
`room_scene_shell.gd` assembles those instances before gameplay nodes enter the tree, preserving
object paths, persistent signal connections, map ids and save keys. A room instance's `position` is
its offset in the dungeon (zero for these): the shell adds it back to every tile cell and node as it
assembles the dungeon. Room changes inside a shell use the camera scroll.

The Hollow's and the Mine's builders generate their room scenes through
`tools/lib/dungeon_room_splitter.gd`. Rebuilding overwrites their authored rooms, as the builders
previously overwrote the whole world. To repartition an assembled dungeon after structural changes,
run `tools/split_dungeon_rooms.gd`. Reload changed scenes in an open editor before saving. Bake the
worlds' elevation after changing their paint.

The splitter records the hash of every file it writes in
`game/scenes/worlds/rooms/<world>/written.json` (commit it with the scenes). A file edited in the
editor since no longer matches its hash, and the next run **keeps it**: it prints `skipped room
<name>: edited by hand ...` (or the shell) and writes the others. Options after `--` on the
builders and `tools/split_dungeon_rooms.gd`:

- `--dry`: writes nothing, prints what it would write and skip;
- `--only=<room,room,shell>`: writes only those (by room scene name; `shell` for the dungeon scene);
- `--force`: rewrites hand-edited files too, after a warning (their edits are lost).

A world with no `written.json` yet is unprotected until its first run writes one. A hand-edited room
keeps its own contents, so a rebuild that changes that room's layout does not reach it: rebuild it
with `--only=<room> --force` when wanted.

## Room outlines and visibility

A CameraRoom's optional `outline` is a simple local polygon with up to 64 vertices; empty
uses its `size` rectangle. Camera and Dungeon use `contains` for room membership. Camera
movement clamps to the outline's bounding box, and the dungeon map draws the polygon.
The Pit Hall is an L round Burr's cell (its own world since 2026-10-18); the Hollow's map nook has a separate outline to conceal its contents.

`room_mask.gd` draws darkness outside the current outline on CanvasLayer 4, beneath the
arrival fade and HUD. Its screen-space shader follows window size, camera motion, shake
and zoom. During a room scroll it shows the destination outline; a scripted seal glimpse
uses the camera's room. Doorway frames close to the room edge remain visible in the mask.
The closed Burr cell is checked specifically. `doorway_art.gd` draws the room's wall
courses and openings around its rectangular bounds.

## Wall pieces and leaves

`doorway_art.gd` draws continuous courses around each room and replaces opening stretches
with wall-owned arches. The same wall pieces turn onto side and south walls, compressed
to a one-cell band there. Key/boss/bolt doors move only their leaves; locks and bolts stay
on them. Shutters and seal blocks sit inside a fixed arch. Cracks and blown holes use
whole pieces of the wall's own style instead of a decal on its top. Latch doors, plank
barricades, rotten timbers and mine gates use the same fixed wall frames; their existing
open/smashed states change only the central slab, boards or leaf.

The shared `object.latch-door` prefab also uses the masonry arch and shutter leaf in the editor.
The five Lair instances have no legacy stone-frame overrides. The former outdoor C4 instance
is replaced by a keeper's storehouse and a separate furnished interior; it is no longer a
freestanding dungeon doorway with a visible coffer behind it.

The collision and lock rules remain on the existing gameplay objects; the two-cell door
collision is 128 units. The visual integration uses masonry, root rock, cave rock and
crystal rock, sampled from the world's painted cliff style.

`python scripts/art/pack-doorway-art.py` cuts the existing generated sheets into runtime
pieces. It uses the game's existing cave-rock art for the cave-rock set. Then run
`tools/pack_doorway_textures.gd` to save native compressed ImageTexture `.res` resources;
this does not run an editor import or touch the shared import cache. Keep these resources
with the WebP source pieces and any `.import`/`.gd.uid` files the editor creates.
No new image generations or credits were used for this continuation.

## Verification

`test_dungeon_rooms.gd` checks that the Lair's rooms are worlds that keep their links (the Inner
Stair, Burr's director in the hub), Burr's hidden cell and the hub's L-shaped mask, the stone arch/leaf split, two-cell collision, and shared Hollow floor identity. The existing
Lair, Hollow, Mine, seal, kit and camera tests cover the shared gameplay. Live wide-screen
review captures are in `output/doorway-review/live-*-wide.png`. To refresh them, run
`tools/render_dungeon_room_views.gd -- --out=<directory>` windowed.

## Next: interior walls

The owner rejected the walls' art and how they are painted (elevation cliffs plus
`doorway_art.gd`'s frames round the room's rectangle), not the room scenes. Their replacement is the
InteriorWallLayer ([INTERIOR_WALLS.md](INTERIOR_WALLS.md)), painted in each room scene and gathered
on the shell's `interior-walls` layer; `doorway_art.gd` and the doorway textures go once the Lair is
converted. **Fatty's Lair is converted** (2026-10-18): its builder paints every room's rim on
`interior-walls` in the room's style and the Lair no longer goes through `doorway_art.gd` (its camera
rooms have `wall_bands` off, so the room mask shows no old frames). The doorway textures stay for the
Hollow and the Mine.

## Camera rooms in the editor

Enable **Camera Room Handles** once (Project > Project Settings > Plugins;
`godot/addons/camera_room_handles/`). Select a room's node under `CameraRooms`:
- without an `outline`, a dot sits on each corner of its `size` rectangle: drag one to resize (the
  opposite corner stays put; the top-left one moves the node);
- with an `outline` (it wins over `size`), a dot sits on each point: drag it, double-click an edge to
  add a point, right-click a point to remove it (three at least).
Moves snap to the 64-unit grid (hold Alt for free moves); each drag is one undo step.

