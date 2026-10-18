# Dungeon room scenes

Built 2026-10-17 after the doorway review: the owner chose separate scenes per room and
Lair arches with two-cell openings. The Hollow uses root arches; the Mine timber frames.

## Editing and running

The authored rooms are in `godot/game/scenes/worlds/rooms/<world>/<room>.tscn`:
24 in Fatty's Lair, 22 across the Hollow's four floors, and 14 in the Mine (60 total).
Open a room to edit its terrain, walls, objects and CameraRoom. F6 starts that room in the
full game with the dungeon's normal direct-run powers. The room coordinates stay in the
dungeon's coordinate space; keep the room root at the origin.

The parent world is a shell holding the world definition, Dungeon node, shared logic and
room scene instances. `room_scene_shell.gd` assembles those instances before gameplay nodes
enter the tree, preserving object paths, persistent signal connections, map ids and save
keys. Shared puzzles, the dungeon map, entrance recovery and the Pearl/seal sequence keep
their existing relationships. Room changes use the existing camera scroll.

The three dungeon builders now generate their room scenes through
`tools/lib/dungeon_room_splitter.gd`. Rebuilding overwrites their authored rooms, as the
builders previously overwrote the whole world. To repartition an assembled dungeon after
structural changes, run `tools/split_dungeon_rooms.gd`. Reload changed scenes in an open
editor before saving. Bake the six worlds' elevation after changing their paint.

## Room outlines and visibility

A CameraRoom's optional `outline` is a simple local polygon with up to 64 vertices; empty
uses its `size` rectangle. Camera and Dungeon use `contains` for room membership. Camera
movement clamps to the outline's bounding box, and the dungeon map draws the polygon.
Burr's cell is now a separate room; the Pit Hall wraps around it as an L. The Gatehouse store, R5 key alcove and Hollow map nook also have separate outlines to conceal their contents.

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

`test_dungeon_rooms.gd` checks room scene instances and shared paths, Burr's hidden cell
and L-shaped mask, the stone arch/leaf split, two-cell collision, and shared Hollow floor identity. The existing
Lair, Hollow, Mine, seal, kit and camera tests cover the shared gameplay. Live wide-screen
review captures are in `output/doorway-review/live-*-wide.png`. To refresh them, run
`tools/render_dungeon_room_views.gd -- --out=<directory>` windowed.
