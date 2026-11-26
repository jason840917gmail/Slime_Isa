extends RefCounted
## Interior walls (docs/godot/INTERIOR_WALLS.md), the bevel model: a room's two-cell rim draws a
## two-deep face behind every floor edge, mitred corners where the floor turns (outer and inner), an
## opening piece over each painted opening; every wall cell is solid but an opening's passage (a
## cracked stretch until blown, every cracked block in a blast's reach); a door object with
## `frame_drawn_by_wall` draws only its leaf, filling its opening upright (a barricade turned for a
## side wall closes its taller passage); painted closed doors keep their objects, also grouped deeper
## under `Objects`, and every Fatty's Lair room has its doors; the box-room lab's room scenes assemble
## under the shell.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const TILESET := preload("res://game/world/interior/interior_wall_tileset.tres")
const KEY_DOOR := preload("res://game/scenes/objects/dungeon/key-door.tscn")
const BOLTED_DOOR := preload("res://game/scenes/objects/dungeon/bolted-door.tscn")
const SHUTTER := preload("res://game/scenes/objects/dungeon/shutter.tscn")
const BARRICADE := preload("res://game/scenes/objects/plank-barricade.tscn")
const LAB := "res://game/dev/interior/box-room-lab.tscn"
const LAIR_ROOMS := "res://game/scenes/worlds/rooms/fatty-lair/"
const STYLE := "lair-stone"
const CELL := 64.0
const DEPTH := 2
const OUTER_CORNERS: Array[String] = ["nw", "ne", "sw", "se"]
## The tests need no world of their own: they start in the playground, not level-1.
const MAP_ID := "playground"
## Stale paint in Fatty's Lair's room scenes, left out of "every opening cell is in an opening block"
## (test_the_lair_rooms_painted_doors_have_their_objects): room scene -> the cells. Empty since R5 is
## one world again (2026-10-19): its rows 9-15 are the lower hall's and the alcove's own rim.
const KNOWN_STALE_PAINT := {}


## The palette tile for `kind` ("" a plain wall) of the style.
static func _tile(kind: String) -> Vector2i:
	var source := TILESET.get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if str(data.get_custom_data(InteriorWalls.STYLE_DATA)) == STYLE and str(data.get_custom_data(InteriorWalls.OPENING_DATA)) == kind:
			return coords
	return Vector2i(-1, -1)


## A layer with a two-cell rim round `rect` (less `cut`, for an L), `openings` {cell: kind} over it,
## in the tree and built.
func _layer(t: TestContext, rect: Rect2i, openings: Dictionary = {}, cut: Rect2i = Rect2i()) -> InteriorWalls:
	var layer := InteriorWalls.new()
	layer.tile_set = TILESET
	var inside := func(c: Vector2i) -> bool:
		return rect.has_point(c) and not (cut.has_area() and cut.has_point(c))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not inside.call(cell):
				continue
			var rim := false
			for dy in range(-DEPTH, DEPTH + 1):
				for dx in range(-DEPTH, DEPTH + 1):
					if not inside.call(cell + Vector2i(dx, dy)):
						rim = true
			if rim:
				layer.set_cell(cell, 0, _tile(""))
	for cell: Vector2i in openings:
		layer.set_cell(cell, 0, _tile(str(openings[cell])))
	t.main.add_child(layer)
	return layer


static func _count(layer: InteriorWalls, piece: String) -> int:
	var n := 0
	for p in layer.pieces():
		if str(p["piece"]) == piece:
			n += 1
	return n


static func _at(layer: InteriorWalls, piece: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in layer.pieces():
		if str(p["piece"]) == piece:
			out.append(p["cell"] as Vector2i)
	return out


static func _solid_at(layer: InteriorWalls, point: Vector2) -> bool:
	var body := layer.get_node_or_null(InteriorWalls.COLLISION)
	if body == null:
		return false
	for node: Node in body.get_children():
		var shape := node as CollisionShape2D
		var size := (shape.shape as RectangleShape2D).size
		if Rect2(shape.position - size / 2.0, size).has_point(point):
			return true
	return false


func test_faces_run_round_the_room_and_corners_mitre(t: TestContext) -> void:
	# a 10 x 8 room: floor 6 x 4 inside a two-cell rim
	var layer := _layer(t, Rect2i(0, 0, 10, 8))
	t.check(layer.is_floor(Vector2i(2, 2)) and layer.is_floor(Vector2i(7, 5)), "the floor inside the rim")
	t.check(not layer.is_floor(Vector2i(1, 3)), "the rim is floor")
	var north := 0
	for i in 3:
		north += _count(layer, "n%d" % i)
	t.equal(north, 6, "a north face strip behind each of the six floor cells")
	t.equal(_at(layer, "nw"), [Vector2i(0, 0)] as Array[Vector2i], "the north-west mitre block")
	t.equal(_at(layer, "se"), [Vector2i(8, 6)] as Array[Vector2i], "the south-east mitre block")
	t.equal(_count(layer, "ne") + _count(layer, "sw"), 2, "the other two outer corners")
	t.check(_at(layer, "s0").has(Vector2i(2, 6)) or _at(layer, "s2").has(Vector2i(2, 6)) or _at(layer, "s1").has(Vector2i(2, 6)),
		"the south face hangs below the floor's last row")
	layer.free()
	# an L (its lower-right quarter cut out): an inner corner where the floor turns concave
	var l := _layer(t, Rect2i(0, 0, 12, 10), {}, Rect2i(6, 5, 6, 5))
	t.equal(_count(l, "in_nw"), 1, "the L's inner corner")
	t.equal(_at(l, "in_nw"), [Vector2i(4, 3)] as Array[Vector2i], "the inner corner sits at the notch")
	t.equal(_count(l, "nw") + _count(l, "ne") + _count(l, "sw") + _count(l, "se"), 5, "the L's five outer corners")
	l.free()


func test_every_wall_cell_is_solid_but_the_passage(t: TestContext) -> void:
	var layer := _layer(t, Rect2i(0, 0, 10, 8), {Vector2i(4, 0): "doorway", Vector2i(5, 0): "doorway",
		Vector2i(4, 1): "doorway", Vector2i(5, 1): "doorway"})
	t.check(_solid_at(layer, Vector2(1.5, 1.5) * CELL), "a corner cell is open")
	t.check(_solid_at(layer, Vector2(2.5, 0.5) * CELL), "a face cell is open")
	t.check(not _solid_at(layer, Vector2(5.0, 0.5) * CELL), "the doorway's passage is solid at its outer row")
	t.check(not _solid_at(layer, Vector2(5.0, 1.9) * CELL), "the doorway's passage is solid at the floor")
	t.check(_solid_at(layer, Vector2(4.1, 1.0) * CELL), "the doorway's west jamb is open")
	t.check(_solid_at(layer, Vector2(5.9, 1.0) * CELL), "the doorway's east jamb is open")
	t.check(not _solid_at(layer, Vector2(5.0, 4.0) * CELL), "the floor is solid")
	t.equal(_count(layer, "n_doorway"), 1, "one doorway piece for the two-by-two block")
	layer.free()


func test_a_cracked_stretch_is_solid_until_blown(t: TestContext) -> void:
	var openings := {}
	for d in DEPTH:
		for i in 2:
			openings[Vector2i(d, 3 + i)] = "cracked"
	var layer := _layer(t, Rect2i(0, 0, 10, 9), openings)
	t.equal(_count(layer, "w_cracked"), 1, "the cracked piece in the west face")
	t.check(_solid_at(layer, Vector2(1.0, 4.0) * CELL), "the cracked stretch is open before it is blown")
	t.check(layer.change_opening_at(Vector2(1.0, 4.0) * CELL, "blown"), "the cracked stretch did not change")
	t.equal(layer.opening_of(Vector2i(0, 3)), "blown", "the block's cells are not blown")
	t.equal(_count(layer, "w_blown"), 1, "the blown hole is drawn")
	t.check(not _solid_at(layer, Vector2(1.0, 4.0) * CELL), "the blown hole is still solid")
	layer.free()


func test_a_door_with_its_frame_drawn_by_the_wall_draws_only_its_leaf(t: TestContext) -> void:
	var plain := KEY_DOOR.instantiate() as Node2D
	t.main.add_child(plain)
	t.check((plain.get_node("Open") as CanvasItem).visible, "a door without the flag hid its own doorway")
	t.check(not (plain.get_node("Shut/Door") as Sprite2D).region_enabled, "a door without the flag lost its picture")
	plain.free()
	for wall in ["north", "south", "east", "west"]:
		for holes in [1, 2]:
			var door := KEY_DOOR.instantiate() as Node2D
			door.set(&"wall", wall)
			door.set(&"keyholes", holes)
			door.set(&"frame_drawn_by_wall", true)
			t.main.add_child(door)
			var leaf := door.get_node("Shut/Door") as Sprite2D
			var place := InteriorWalls.leaf_at(STYLE, wall, "key%d" % holes)
			t.check(not (door.get_node("Open") as CanvasItem).visible, "%s: the door still draws its doorway" % wall)
			t.check(leaf.region_enabled and leaf.region_rect == place["region"], "%s, %d locks: not the kit's leaf" % [wall, holes])
			t.near(wrapf(leaf.global_rotation, -PI, PI), 0.0, 0.01, "%s: the leaf is turned" % wall)
			t.near_vec(leaf.global_position - door.global_position, place["offset"] as Vector2, 0.5, "%s: the leaf is not in the opening" % wall)
			t.equal(((door.get_node("Body/Shape") as CollisionShape2D).shape as RectangleShape2D).size.x, 128.0, "%s: the door's body changed" % wall)
			door.free()
	var shutter := SHUTTER.instantiate() as Node2D
	shutter.set(&"wall", "south")
	shutter.set(&"frame_drawn_by_wall", true)
	t.main.add_child(shutter)
	var look := shutter.get_node("Look") as Sprite2D
	var place := InteriorWalls.leaf_at(STYLE, "south", "shutter")
	t.check(look.region_rect == place["region"], "the shutter's block is not the kit's")
	t.near(wrapf(look.global_rotation, -PI, PI), 0.0, 0.01, "a south shutter's block is turned")
	shutter.free()


func test_the_lab_rooms_assemble_under_the_shell(t: TestContext) -> void:
	var world := (load(LAB) as PackedScene).instantiate() as Node2D
	t.check(not world.has_node("RoomScenes"), "the room scenes were not assembled")
	var cameras := world.get_node("CameraRooms")
	t.equal(cameras.get_child_count(), 3, "camera rooms")
	var walls := world.get_node("interior-walls") as TileMapLayer
	t.check(walls.get_cell_source_id(Vector2i(0, 0)) >= 0 and walls.get_cell_source_id(Vector2i(47, 1)) >= 0
		and walls.get_cell_source_id(Vector2i(1, 27)) >= 0, "the rooms' rims were not gathered on the shell's layer")
	t.check(world.has_node("Objects/b-boss-door") and world.has_node("Objects/c-seal"), "the rooms' doors were not gathered")
	var l := cameras.get_node("b-l-room")
	var outline := l.get(&"outline") as PackedVector2Array
	var origin := (l as Node2D).position
	t.equal(outline.size(), 6, "the L's outline")
	t.check(not Geometry2D.is_point_in_polygon(Vector2(20, 20) * CELL - origin, outline), "the L contains its missing quarter")
	t.check(Geometry2D.is_point_in_polygon(Vector2(40, 20) * CELL - origin, outline), "the L lost its lower arm")
	world.free()


## Fatty's Lair's room scenes are local (docs/godot/DUNGEON_ROOMS.md): each room's corner is at its
## scene's origin; each room is its own world (R5's three parts one world), and the map's layout lays
## them so that every pair of room doors that slides (not the iris's closets) meets on the map: a
## room may be dragged on the layout, its doors with it (2026-10-19: no more old shell offsets).
func test_the_lair_rooms_are_local_and_laid_out_in_place(t: TestContext) -> void:
	var dir := "res://game/scenes/worlds/rooms/fatty-lair/"
	var count := 0
	var doors := {}
	for file: String in DirAccess.get_files_at(dir):
		# the map's layout is not a room
		if not file.ends_with(".tscn") or file == "layout.tscn":
			continue
		count += 1
		var room := (load(dir + file) as PackedScene).instantiate() as Node2D
		var world := str(room.get_node("world-definition").get(&"map_id"))
		for camera: Node in room.get_node("CameraRooms").get_children():
			var at := (camera as Node2D).position
			t.check(at.x >= 0.0 and at.y >= 0.0 and at.x < 2304.0 and at.y < 2048.0, "%s's room is not near its origin (%s)" % [file, at])
		for door: Node in room.get_node("RoomDoors").get_children():
			if &"door_id" in door:
				doors["%s/%s" % [world, door.get(&"door_id")]] = {"at": (door as Node2D).position, "world": world,
					"target_room": str(door.get(&"target_room")), "target_door": str(door.get(&"target_door")),
					"iris": str(door.get(&"transition")) == "iris"}
		room.free()
	# R5's eye hall, lower hall and key alcove are one world (2026-10-19); 19 since b4ca2a64
	# (2026-10-20): the Old Armoury, the Glow-Moss Burrow and the Sally Port moved out into Slimeshire
	t.equal(count, 19, "the Lair's room scenes")
	# each world's place on the map: a map room of it, less where its CameraRoom lies in the scene
	var layout := (load(dir + "layout.tscn") as PackedScene).instantiate() as Node2D
	var world_at := {}
	var world_of := {}
	for child: Node in layout.get_children():
		if not &"room_name" in child:
			continue
		var world := str(child.get(&"world_id"))
		world_of[str(child.get(&"room_name"))] = world
		if not world_at.has(world):
			world_at[world] = (child as Node2D).position - (child.get(&"camera_offset") as Vector2)
		t.check(posmod(int((child as Node2D).position.x), 64) == 0 and posmod(int((child as Node2D).position.y), 64) == 0,
			"%s is not on the map's 64-unit grid" % child.name)
	layout.free()
	var met := 0
	for key: String in doors:
		var door: Dictionary = doors[key]
		if bool(door["iris"]) or not world_of.has(door["target_room"]):
			continue
		var far_key := "%s/%s" % [world_of[door["target_room"]], door["target_door"]]
		if not t.check(doors.has(far_key), "%s's far door %s is missing" % [key, far_key]):
			continue
		var far: Dictionary = doors[far_key]
		var here := (world_at[door["world"]] as Vector2) + (door["at"] as Vector2)
		var there := (world_at[far["world"]] as Vector2) + (far["at"] as Vector2)
		met += 1
		t.near_vec(here, there, 0.5, "%s and %s do not meet on the map" % [key, far_key])
	t.check(met >= 40, "room doors checked on the map: %d" % met)
	var r7 := (load(dir + "r7-bell-bridge.tscn") as PackedScene).instantiate() as Node2D
	var walls := r7.get_node("interior-walls") as TileMapLayer
	t.check(walls.get_cell_source_id(Vector2i(0, 0)) >= 0, "R7's rim corner is not at its scene's origin")
	r7.free()


## Painting a closed door makes its door object, repainting another kind swaps it, erasing it removes
## it; a door placed by hand, or one whose settings were changed, is never removed: erased and painted
## back (Ctrl+Z) it is adopted again with its settings (docs/godot/INTERIOR_WALLS.md "Painting a
## room"; 2026-10-19 review: erasing a cell of the hub's boss door block and undoing it lost its id).
func test_painting_a_closed_door_makes_its_object(t: TestContext) -> void:
	var room := Node2D.new()
	room.name = "paint-room"
	t.main.add_child(room)
	var objects := Node2D.new()
	objects.name = "Objects"
	room.add_child(objects)
	var layer := InteriorWalls.new()
	layer.name = "interior-walls"
	layer.tile_set = TILESET
	for y in range(0, 10):
		for x in range(0, 12):
			if x < DEPTH or y < DEPTH or x >= 12 - DEPTH or y >= 10 - DEPTH:
				layer.set_cell(Vector2i(x, y), 0, _tile(""))
	for d in DEPTH:
		for i in 2:
			layer.set_cell(Vector2i(5 + i, d), 0, _tile("key2"))
	room.add_child(layer)
	# a door placed by hand elsewhere in the room
	var hand := KEY_DOOR.instantiate() as Node2D
	hand.name = "hand-door"
	hand.position = Vector2(3.0, 6.0) * CELL
	objects.add_child(hand)
	t.equal(layer.sync_doors(true), 1, "painting a key door made no door")
	var made := objects.get_node_or_null("paint-room-key2-5-0") as Node2D
	if t.check(made != null, "the painted door's object is missing"):
		t.equal(int(made.get(&"keyholes")), 2, "the painted key door's keyholes")
		t.equal(str(made.get(&"wall")), "north", "the painted door's wall")
		t.check(bool(made.get(&"frame_drawn_by_wall")), "the painted door draws its own frame")
		t.near_vec(made.position, Vector2(6.0, 2.0) * CELL, 0.5, "the painted door is not on the floor line")
	t.equal(layer.sync_doors(true), 0, "a second sync made another door")
	for d in DEPTH:
		for i in 2:
			layer.set_cell(Vector2i(5 + i, d), 0, _tile("boss"))
	layer._rebuild()
	layer.sync_doors(true)
	t.check(objects.get_node_or_null("paint-room-key2-5-0") == null, "repainting did not remove the key door")
	t.check(objects.get_node_or_null("paint-room-boss-5-0") != null, "repainting did not make the boss door")
	for d in DEPTH:
		for i in 2:
			layer.set_cell(Vector2i(5 + i, d), 0, _tile("doorway"))
	layer._rebuild()
	layer.sync_doors(true)
	t.check(objects.get_node_or_null("paint-room-boss-5-0") == null, "erasing the closed door did not remove its object")
	t.check(objects.get_node_or_null("hand-door") != null, "a hand-placed door was removed")
	# A door given a setting of its own (a door id: a save record) survives a cell of its block erased
	# and comes back with its block, settings and all.
	_paint_block(layer, Vector2i(5, 0), "boss")
	layer.sync_doors(true)
	var boss := objects.get_node_or_null("paint-room-boss-5-0") as Node2D
	if t.check(boss != null, "repainting the boss door made no door"):
		boss.set(&"door_id", "the-boss-door")
		layer.erase_cell(Vector2i(5, 1))
		layer._rebuild()
		layer.sync_doors(true)
		t.check(is_instance_valid(boss) and boss.get_parent() == objects, "a door with its own door id was removed when a cell of its block was erased")
		layer.set_cell(Vector2i(5, 1), 0, _tile("boss"))
		layer._rebuild()
		layer.sync_doors(true)
		if t.check(is_instance_valid(boss), "the door with its own door id is gone after its block came back"):
			t.equal(str(boss.get_meta(InteriorWalls.DOOR_BLOCK_META, "")), "5,0", "the door was not adopted again by its block")
			t.equal(str(boss.get(&"door_id")), "the-boss-door", "the door's id after its block came back")
			t.equal(_doors_of(objects, "res://game/scenes/objects/dungeon/boss-door.tscn"), 1, "boss doors after the block came back")
	# A door placed by hand at a block's spot is adopted, and never removed when its block is erased.
	var placed := KEY_DOOR.instantiate() as Node2D
	placed.name = "placed-key-door"
	placed.set(&"keyholes", 1)
	placed.position = Vector2(9.0, 2.0) * CELL
	objects.add_child(placed)
	_paint_block(layer, Vector2i(8, 0), "key1")
	t.equal(layer.sync_doors(true), 0, "a door was made beside the hand-placed one")
	t.equal(str(placed.get_meta(InteriorWalls.DOOR_BLOCK_META, "")), "8,0", "the hand-placed door was not adopted")
	_paint_block(layer, Vector2i(8, 0), "")
	layer._rebuild()
	layer.sync_doors(true)
	t.check(is_instance_valid(placed) and placed.get_parent() == objects, "an adopted hand-placed door was removed with its block")
	room.free()


func _paint_block(layer: InteriorWalls, top_left: Vector2i, kind: String) -> void:
	for d in DEPTH:
		for i in 2:
			layer.set_cell(top_left + Vector2i(i, d), 0, _tile(kind))
	layer._rebuild()


static func _doors_of(objects: Node, scene: String) -> int:
	var count := 0
	for node: Node in objects.get_children():
		if node.scene_file_path == scene:
			count += 1
	return count


## A room scene in the tree: `Objects` and an `interior-walls` layer with a two-cell rim round 12 x 10
## cells.
func _room(t: TestContext, room_name: String) -> Node2D:
	var room := Node2D.new()
	room.name = room_name
	t.main.add_child(room)
	var objects := Node2D.new()
	objects.name = "Objects"
	room.add_child(objects)
	var layer := InteriorWalls.new()
	layer.name = "interior-walls"
	layer.tile_set = TILESET
	_paint_rim(layer, Rect2i(0, 0, 12, 10))
	room.add_child(layer)
	return room


## A two-cell rim of plain wall round `rect` on `layer`.
static func _paint_rim(layer: InteriorWalls, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x < rect.position.x + DEPTH or y < rect.position.y + DEPTH or x >= rect.end.x - DEPTH or y >= rect.end.y - DEPTH:
				layer.set_cell(Vector2i(x, y), 0, _tile(""))


## The bounds of `shape`'s rectangle in world units, turned as the shape is.
static func _global_rect(shape: CollisionShape2D) -> Rect2:
	var half := (shape.shape as RectangleShape2D).size * 0.5
	var xform := shape.global_transform
	var bounds := Rect2(xform * -half, Vector2.ZERO)
	for corner in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		bounds = bounds.expand(xform * (corner as Vector2))
	return bounds


## `node`'s position in `root`'s space, through the nodes between them.
static func _position_in(node: Node2D, root: Node) -> Vector2:
	var xform := node.transform
	var up := node.get_parent()
	while up != null and up != root:
		if up is Node2D:
			xform = (up as Node2D).transform * xform
		up = up.get_parent()
	return xform.origin


## Doors grouped deeper under `Objects` (`Objects/Doors`) count: a door the layer made and that was
## moved into the group keeps its block, a door placed by hand in the group at a block's spot is
## adopted, and no second door is made beside either (2026-10-19 review M7).
func test_doors_grouped_under_objects_keep_their_blocks(t: TestContext) -> void:
	var room := _room(t, "group-room")
	var objects := room.get_node("Objects")
	var layer := room.get_node("interior-walls") as InteriorWalls
	var group := Node2D.new()
	group.name = "Doors"
	group.position = Vector2(CELL, 0.0)
	objects.add_child(group)
	_paint_block(layer, Vector2i(5, 0), "key2")
	t.equal(layer.sync_doors(true), 1, "painting a key door made no door")
	var made := objects.get_node_or_null("group-room-key2-5-0") as Node2D
	if t.check(made != null, "the painted door's object is missing"):
		made.reparent(group)
		t.equal(layer.sync_doors(true), 0, "a door moved into Objects/Doors got a second door beside it")
		t.check(is_instance_valid(made) and made.get_parent() == group, "the door moved into Objects/Doors was removed")
		t.equal(str(made.get_meta(InteriorWalls.DOOR_BLOCK_META, "")), "5,0", "the door moved into Objects/Doors lost its block")
	var placed := SHUTTER.instantiate() as Node2D
	placed.name = "grouped-shutter"
	placed.position = Vector2(9.0, 2.0) * CELL - group.position
	group.add_child(placed)
	_paint_block(layer, Vector2i(8, 0), "shutter")
	t.equal(layer.sync_doors(true), 0, "a shutter was made beside the one placed in Objects/Doors")
	t.equal(str(placed.get_meta(InteriorWalls.DOOR_BLOCK_META, "")), "8,0", "the shutter placed in Objects/Doors was not adopted")
	var key_doors := 0
	for node in InteriorWalls.objects_in(objects):
		if node.scene_file_path == str(InteriorWalls.DOOR_KINDS["key2"]["scene"]):
			key_doors += 1
	t.equal(key_doors, 1, "key doors under Objects")
	room.free()


## A plank barricade in an east or west rim turns with its wall, as a dungeon door does: its body and
## hurt shapes stand across the side's taller passage (`interior.sideGapUnits`) in the opening, its
## boards stay upright in the opening (2026-10-19 review M8).
func test_a_barricade_in_a_side_wall_closes_the_side_passage(t: TestContext) -> void:
	var side_gap := float(Services.constants().value("interior.sideGapUnits", 120.0))
	var spot := Vector2(10.0, 5.0) * CELL
	for wall in ["east", "west"]:
		var barricade := BARRICADE.instantiate() as Node2D
		barricade.set(&"frame_drawn_by_wall", true)
		barricade.set(&"wall", wall)
		barricade.position = spot
		t.main.add_child(barricade)
		var body := _global_rect(barricade.get_node("BodyShape") as CollisionShape2D)
		t.check(body.position.y <= spot.y - side_gap * 0.5 and body.end.y >= spot.y + side_gap * 0.5,
			"%s: the barricade's body leaves the side passage open (%s)" % [wall, body])
		var in_opening := body.position.x >= spot.x - 0.5 if wall == "east" else body.end.x <= spot.x + 0.5
		t.check(in_opening, "%s: the barricade's body stands in the room, not in its opening (%s)" % [wall, body])
		var hurt := _global_rect(barricade.get_node("DamageArea/HurtShape") as CollisionShape2D)
		t.check(hurt.size.y > hurt.size.x, "%s: the barricade's hurt shape is not turned (%s)" % [wall, hurt])
		var boards := barricade.get_node("Visual") as Sprite2D
		var place := InteriorWalls.leaf_at(STYLE, wall, "barricade")
		t.check(boards.region_rect == place["region"], "%s: the boards are not the kit's leaf" % wall)
		t.near(wrapf(boards.global_rotation, -PI, PI), 0.0, 0.01, "%s: the boards are turned" % wall)
		t.near_vec(boards.global_position - barricade.global_position, place["offset"] as Vector2, 0.5, "%s: the boards are not in the opening" % wall)
		barricade.free()


## A blast opens every cracked block within reach: a crack painted in both rooms' rims opens on both
## sides, a doorway beside it never changes, and the wall is built once (2026-10-19 review M9).
func test_a_blast_opens_every_cracked_block_in_reach(t: TestContext) -> void:
	var layer := InteriorWalls.new()
	layer.tile_set = TILESET
	# two rooms side by side, the crack in the west room's east rim and the east room's west rim
	_paint_rim(layer, Rect2i(0, 0, 10, 9))
	_paint_rim(layer, Rect2i(10, 0, 10, 9))
	for top_left: Vector2i in [Vector2i(8, 3), Vector2i(10, 3)]:
		for j in DEPTH:
			for i in DEPTH:
				layer.set_cell(top_left + Vector2i(i, j), 0, _tile("cracked"))
	for j in DEPTH:
		for i in DEPTH:
			layer.set_cell(Vector2i(8 + i, 5 + j), 0, _tile("doorway"))
	t.main.add_child(layer)
	# the layer's first build and the cells' own update are done before the blast
	await t.tree.process_frame
	await t.tree.process_frame
	t.equal(_count(layer, "e_cracked") + _count(layer, "w_cracked"), 2, "the crack in both rims")
	t.check(_solid_at(layer, Vector2(9.5, 4.0) * CELL) and _solid_at(layer, Vector2(10.5, 4.0) * CELL), "the crack is open before the blast")
	t.check(layer.change_opening_at(Vector2(10.0, 4.0) * CELL, "blown"), "the blast opened nothing")
	t.equal(layer.opening_of(Vector2i(9, 4)), "blown", "the west room's cracked block")
	t.equal(layer.opening_of(Vector2i(10, 4)), "blown", "the east room's cracked block")
	t.equal(layer.opening_of(Vector2i(8, 5)), "doorway", "the doorway in reach of the blast")
	t.check(not _solid_at(layer, Vector2(9.5, 4.0) * CELL) and not _solid_at(layer, Vector2(10.5, 4.0) * CELL), "the blown hole is still solid")
	t.check(not layer.change_opening_at(Vector2(10.0, 4.0) * CELL, "blown"), "a second blast found a cracked block")
	var built := layer.get_node(InteriorWalls.COLLISION)
	await t.tree.process_frame
	await t.tree.process_frame
	t.check(layer.get_node(InteriorWalls.COLLISION) == built, "the wall was built again after the blast's own build")
	layer.free()


## An outer corner covers its whole 2 x 2 block: no dark fill under it, and it is drawn over the runs
## (2026-10-19 review: `nw`.. were taken for runs, one cell wide).
func test_outer_corners_cover_their_whole_block(t: TestContext) -> void:
	var layer := _layer(t, Rect2i(0, 0, 10, 8))
	var fill := layer.get_node("%s/Fill" % InteriorWalls.HOLDER)
	t.equal((fill.get(&"cells") as Array).size(), 0, "wall cells under the pieces filled dark")
	var names := {}
	var pieces: Dictionary = (InteriorWalls.table()[STYLE] as Dictionary)["pieces"]
	for name: String in pieces:
		var r: Array = pieces[name]
		names[Rect2(r[0], r[1], r[2], r[3])] = name
	var last_run := -1
	var first_corner := -1
	var walls := layer.get_node(InteriorWalls.HOLDER)
	for i in walls.get_child_count():
		var sprite := walls.get_child(i) as Sprite2D
		if sprite == null:
			continue
		var name := str(names.get(sprite.region_rect, ""))
		if OUTER_CORNERS.has(name):
			first_corner = i if first_corner < 0 else first_corner
		elif name.length() == 2:
			last_run = i
	t.check(last_run >= 0 and first_corner > last_run, "an outer corner is drawn under a run")
	layer.free()


## A bolted door draws the bolt only on the side it is slid from: the far side (`bolt_here` off) shows
## the plain shut slab, also when the bolt is taken off in the Inspector (2026-10-19 review).
func test_a_bolted_doors_far_side_shows_no_bolt(t: TestContext) -> void:
	for bolt_here in [true, false]:
		var door := BOLTED_DOOR.instantiate() as Node2D
		door.set(&"bolt_here", bolt_here)
		door.set(&"frame_drawn_by_wall", true)
		t.main.add_child(door)
		var leaf := door.get_node("Shut/Door") as Sprite2D
		var kind := "bolt" if bolt_here else "shutter"
		t.check(leaf.region_rect == InteriorWalls.leaf_at(STYLE, "north", kind)["region"], "bolt here %s: the leaf is not the %s leaf" % [bolt_here, kind])
		if bolt_here:
			door.set(&"bolt_here", false)
			t.check(leaf.region_rect == InteriorWalls.leaf_at(STYLE, "north", "shutter")["region"], "the bolt taken off: the leaf still shows it")
		door.free()


## Fatty's Lair's room scenes as saved: every painted closed-door block has exactly one door tagged
## with it, of its kind, wall and style, on its spot; no opening cell lies outside an opening block
## (2026-10-19 review M6: the layer makes doors in the editor only, so a block a tool painted would
## show a door and leave the passage open).
func test_the_lair_rooms_painted_doors_have_their_objects(t: TestContext) -> void:
	var blocks := 0
	for file: String in DirAccess.get_files_at(LAIR_ROOMS):
		if not file.ends_with(".tscn") or file == "layout.tscn":
			continue
		var room := (load(LAIR_ROOMS + file) as PackedScene).instantiate() as Node2D
		var walls := room.get_node_or_null("interior-walls") as InteriorWalls
		if not t.check(walls != null, "%s has no interior-walls layer" % file):
			room.free()
			continue
		# the layer finds its floor with its camera rooms: both are built in a bare room in the tree
		var probe := Node2D.new()
		probe.name = room.name
		for part in ["interior-walls", "CameraRooms"]:
			var node := room.get_node_or_null(NodePath(part))
			if node != null:
				room.remove_child(node)
				node.owner = null
				probe.add_child(node)
		t.main.add_child(probe)
		var objects := room.get_node_or_null("Objects")
		var doors: Array[Node] = []
		if objects != null:
			doors = InteriorWalls.objects_in(objects)
		var in_blocks := {}
		for opening in walls.openings():
			var top_left := opening["cell"] as Vector2i
			for j in DEPTH:
				for i in DEPTH:
					in_blocks[top_left + Vector2i(i, j)] = true
			var kind := str(opening["kind"])
			if not InteriorWalls.DOOR_KINDS.has(kind):
				continue
			blocks += 1
			var key := "%d,%d" % [top_left.x, top_left.y]
			var label := "%s, the %s block at %s" % [file, kind, key]
			var tagged: Array[Node] = []
			for door in doors:
				if str(door.get_meta(InteriorWalls.DOOR_BLOCK_META, "")) == key:
					tagged.append(door)
			if not t.equal(tagged.size(), 1, "%s: doors tagged with it" % label):
				continue
			var door := tagged[0] as Node2D
			t.equal(str(door.get_meta(InteriorWalls.DOOR_KIND_META, "")), kind, "%s: the door's kind" % label)
			t.equal(door.scene_file_path, str(InteriorWalls.DOOR_KINDS[kind]["scene"]), "%s: the door's scene" % label)
			var props: Dictionary = InteriorWalls.DOOR_KINDS[kind]["props"]
			for prop: String in props:
				t.equal(door.get(prop), props[prop], "%s: the door's %s" % [label, prop])
			t.equal(str(door.get(&"wall")), str(InteriorWalls.SIDE_WALL[str(opening["side"])]), "%s: the door's wall" % label)
			t.equal(str(door.get(&"interior_style")), str(opening["style"]), "%s: the door's style" % label)
			t.check(bool(door.get(&"frame_drawn_by_wall")), "%s: the door draws its own frame" % label)
			t.near_vec(_position_in(door, room), walls._door_spot(opening), 0.5, "%s: the door is off its spot" % label)
		var stale: Rect2i = KNOWN_STALE_PAINT.get(file, Rect2i())
		for cell in walls.get_used_cells():
			var kind := walls.opening_of(cell)
			if not kind.is_empty() and not in_blocks.has(cell) and not stale.has_point(cell):
				t.fail("%s: the %s cell %s is in no opening block" % [file, kind, cell])
		probe.free()
		room.free()
	t.check(blocks >= 12, "the Lair's painted closed-door blocks: %d" % blocks)

