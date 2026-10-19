extends RefCounted
## Interior walls (docs/godot/INTERIOR_WALLS.md), the bevel model: a room's two-cell rim draws a
## two-deep face behind every floor edge, mitred corners where the floor turns (outer and inner), an
## opening piece over each painted opening; every wall cell is solid but an opening's passage (a
## cracked stretch until blown); a door object with `frame_drawn_by_wall` draws only its leaf,
## filling its opening upright; the box-room lab's room scenes assemble under the shell.

const TestContext := preload("res://tests/lib/test_context.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const TILESET := preload("res://game/world/interior/interior_wall_tileset.tres")
const KEY_DOOR := preload("res://game/scenes/objects/dungeon/key-door.tscn")
const SHUTTER := preload("res://game/scenes/objects/dungeon/shutter.tscn")
const LAB := "res://game/dev/interior/box-room-lab.tscn"
const STYLE := "lair-stone"
const CELL := 64.0
const DEPTH := 2
## The tests need no world of their own: they start in the playground, not level-1.
const MAP_ID := "playground"


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
## scene's origin; each room is its own world, and the map's layout lays it at its dungeon offset.
func test_the_lair_rooms_are_local_and_laid_out_in_place(t: TestContext) -> void:
	var dir := "res://game/scenes/worlds/rooms/fatty-lair/"
	var expected := {}
	var count := 0
	for file: String in DirAccess.get_files_at(dir):
		# the map's layout is not a room
		if not file.ends_with(".tscn") or file == "layout.tscn":
			continue
		count += 1
		var room := (load(dir + file) as PackedScene).instantiate() as Node2D
		t.check(room.has_meta(&"dungeon_offset"), "%s has no dungeon offset" % file)
		var offset: Vector2 = room.get_meta(&"dungeon_offset", Vector2.ZERO)
		t.check(posmod(int(offset.x), 64) == 0 and posmod(int(offset.y), 64) == 0, "%s's offset is not whole cells" % file)
		for camera: Node in room.get_node("CameraRooms").get_children():
			var at := (camera as Node2D).position
			t.check(at.x >= 0.0 and at.y >= 0.0 and at.x < 2304.0 and at.y < 2048.0, "%s's room is not near its origin (%s)" % [file, at])
			expected[String(camera.name)] = offset + at
		room.free()
	t.equal(count, 24, "the Lair's room scenes")
	var layout := (load(dir + "layout.tscn") as PackedScene).instantiate() as Node2D
	for name: String in expected:
		var placed := layout.get_node_or_null(name) as Node2D
		if t.check(placed != null, "%s is not on the layout" % name):
			t.near_vec(placed.position, expected[name] as Vector2, 0.5, "%s is not laid where it lies in the dungeon" % name)
	layout.free()
	var r7 := (load(dir + "r7-bell-bridge.tscn") as PackedScene).instantiate() as Node2D
	var walls := r7.get_node("interior-walls") as TileMapLayer
	t.check(walls.get_cell_source_id(Vector2i(0, 0)) >= 0, "R7's rim corner is not at its scene's origin")
	r7.free()


## Painting a closed door makes its door object, repainting another kind swaps it, erasing it removes
## it; a door placed by hand is never removed (docs/godot/INTERIOR_WALLS.md "Painting a room").
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
	room.free()

