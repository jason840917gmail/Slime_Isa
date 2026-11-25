extends RefCounted
## Wall-owned doorway pieces. Only leaves, locks, bolts and seal blocks move inside the arch.
const DungeonDoor := preload("res://game/dungeon/dungeon_door.gd")
const Shutter := preload("res://game/dungeon/shutter.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const ART := "res://asset/MAPS/objects/dungeon/doorways/%s.res"
const FRAME_NAME := &"WallDoorway"
const CELL := 64.0
const FRAME_SIZE := Vector2(352, 192)
const LEAF_SIZE := Vector2(128, 128)

static func apply(world: Node2D) -> void:
	var definition := world.get_node_or_null("world-definition")
	var map_id := str(definition.get(&"map_id")) if definition != null else ""
	# Fatty's Lair draws its walls and doorways with interior walls (docs/godot/INTERIOR_WALLS.md)
	if not (map_id == "crystal-mine" or map_id.begins_with("weaver-hollow-")):
		return
	# nor do the rebuilt Weaver Hollow's room worlds (2026-11-25, step 3 of the dungeons rework: their
	# ids also begin with "weaver-hollow-"); any world with interior walls draws its own doorways
	if world.get_node_or_null(^"interior-walls") is TileMapLayer:
		return
	for node: Node in world.find_children("*", "Node2D", true, false):
		if node.has_meta(&"wall_doorway_applied"):
			continue
		# a door in a room whose InteriorWallLayer draws its opening (docs/godot/INTERIOR_WALLS.md)
		if node.get(&"frame_drawn_by_wall") == true:
			continue
		if node is DungeonDoor:
			_door(world, node as DungeonDoor, map_id)
		elif node is Shutter:
			_shutter(world, node as Shutter, map_id)
		elif node.scene_file_path.ends_with("/latch-door.tscn"):
			_latch(world, node as Node2D, map_id)
		elif node.scene_file_path.get_file() in ["plank-barricade.tscn", "rotten-timbers.tscn", "lantern-gate.tscn"]:
			_board_gate(world, node as Node2D, map_id)
		elif node.get_script() != null and (node.get_script() as Script).resource_path == "res://game/scripts/cracked_wall.gd":
			_crack(world, node as Node2D, map_id)
	_walls(world, map_id)

static func _depth(wall: String) -> float:
	return 1.0 if wall == "north" else 1.0 / 3.0

static func _style(world: Node2D, at: Vector2, turn: float, map_id: String) -> String:
	var layer := Elevation.find_cliff_in(world)
	if layer != null:
		var sample := at + Vector2(0, -160).rotated(turn)
		var cell := Vector2i(floori(sample.x / CELL), floori(sample.y / CELL))
		var data := layer.get_cell_tile_data(cell)
		if data != null:
			var style := str(data.get_custom_data("wall_style"))
			if style in ["masonry", "root-rock", "cave-rock", "crystal-rock"]:
				return style
	return "crystal-rock" if map_id == "crystal-mine" else ("root-rock" if map_id.begins_with("weaver-hollow") else "masonry")

static func _texture(name: String) -> Texture2D:
	return load(ART % name) as Texture2D

static func _frame(root: Node2D, style: String, wall: String) -> void:
	var frame := Sprite2D.new()
	frame.name = FRAME_NAME
	frame.texture = _texture(style + "-arch")
	var depth := _depth(wall)
	frame.position = Vector2(0, -FRAME_SIZE.y * depth * 0.5)
	frame.scale = FRAME_SIZE * Vector2(1, depth) / frame.texture.get_size()
	root.add_child(frame)
	root.move_child(frame, 0)
	root.set_meta(&"wall_doorway_applied", true)

static func _leaf(sprite: Sprite2D, name: String) -> void:
	if sprite == null:
		return
	sprite.texture = _texture(name)
	sprite.hframes = 1
	sprite.vframes = 1
	sprite.frame = 0
	sprite.region_enabled = false
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	sprite.position = Vector2(0, -LEAF_SIZE.y * 0.5)
	sprite.scale = LEAF_SIZE / sprite.texture.get_size()

static func _door(world: Node2D, door: DungeonDoor, map_id: String) -> void:
	_frame(door, _style(world, door.global_position, door.rotation, map_id), door.wall)
	if door.open_look != null:
		door.open_look.visible = false
	var leaf := door.closed_look as Sprite2D
	if leaf == null and door.closed_look != null:
		leaf = door.closed_look.get_node_or_null("Door") as Sprite2D
	var kind := "boss-leaf" if &"lock" in door and str(door.get(&"lock")) == "big" else "oak-leaf"
	if &"bolt" in door:
		kind = "bolt-leaf"
	_leaf(leaf, kind)
	if door.closed_look is Node2D:
		(door.closed_look as Node2D).scale.y = _depth(door.wall)
	var locks := door.get_node_or_null("Shut/Locks") as Node2D
	if locks != null:
		locks.position.y = -64
	var bolt := door.get_node_or_null("Shut/Bolt") as Node2D
	if bolt != null:
		bolt.position.y = -64

static func _shutter(world: Node2D, shutter: Shutter, map_id: String) -> void:
	_frame(shutter, _style(world, shutter.global_position, shutter.rotation, map_id), shutter.wall)
	var look := shutter.look
	if look == null:
		return
	# A seal keeps its Pearl block/ring; the stone shutter uses the matching arch's leaf.
	if not shutter.has_signal(&"clinked") and not shutter.is_in_group(&"dungeon_seal"):
		look.texture = _texture("shutter-leaf")
	look.hframes = 1
	look.vframes = 1
	look.centered = false
	look.offset = Vector2(-look.texture.get_width() * 0.5, -look.texture.get_height())
	look.scale = LEAF_SIZE * Vector2(1, _depth(shutter.wall)) / look.texture.get_size()
	shutter.set(&"_rest", look.offset)
	shutter.call(&"_place_look", float(shutter.get(&"_height")))

static func _crack(world: Node2D, crack: Node2D, map_id: String) -> void:
	var side := "north"
	var best := INF
	var passage: Rect2 = crack.get(&"passage")
	var middle := crack.global_position + passage.get_center()
	for room: Node in world.get_node("CameraRooms").get_children():
		if not room is CameraRoom or not (room as CameraRoom).rect().grow(CELL).has_point(crack.global_position):
			continue
		var rect := (room as CameraRoom).rect()
		for edge: Array in [["west", absf(middle.x - rect.position.x)], ["east", absf(middle.x - rect.end.x)], ["north", absf(middle.y - rect.position.y)], ["south", absf(middle.y - rect.end.y)]]:
			if float(edge[1]) < best:
				best = float(edge[1])
				side = str(edge[0])
	var turn := float(DungeonDoor.WALL_TURNS[side])
	var style := _style(world, crack.global_position, turn, map_id)
	var size := FRAME_SIZE * Vector2(1, _depth(side))
	var offset := Vector2(0, -size.y * 0.5).rotated(turn)
	if side in ["east", "west"]:
		offset.y = passage.get_center().y
	for state: String in ["Crack", "Hole"]:
		var sprite := crack.get_node_or_null(state) as Sprite2D
		if sprite != null:
			sprite.texture = _texture(style + ("-cracked" if state == "Crack" else "-blown"))
			sprite.rotation = turn
	crack.set(&"crack_size", size)
	crack.set(&"hole_size", size)
	crack.set(&"crack_offset", offset)
	crack.set(&"hole_offset", offset)
	crack.set(&"hole_tint", Color.WHITE)
	crack.call(&"_apply_look")
	crack.set_meta(&"wall_doorway_applied", true)


## The same wall courses continue along every side; openings replace a stretch of those courses.
static func _walls(world: Node2D, map_id: String) -> void:
	if world.has_node("DoorwayWalls"):
		return
	var holder := Node2D.new()
	holder.name = "DoorwayWalls"
	holder.z_index = -1
	world.add_child(holder)
	var elevation := Elevation.find_paint_in(world)
	for camera: Node in world.get_node("CameraRooms").get_children():
		if not camera is CameraRoom or not bool(camera.get_meta(&"wall_bands", true)):
			continue
		var room := camera as CameraRoom
		var room_rect := room.rect()
		var points := PackedVector2Array([
			room_rect.position,
			Vector2(room_rect.end.x, room_rect.position.y),
			room_rect.end,
			Vector2(room_rect.position.x, room_rect.end.y),
		])
		var area := 0.0
		for i in points.size():
			var next: Vector2 = points[(i + 1) % points.size()]
			area += points[i].x * next.y - next.x * points[i].y
		var winding := 1.0 if area >= 0.0 else -1.0
		for i in points.size():
			var start := points[i]
			var finish: Vector2 = points[(i + 1) % points.size()]
			var edge := finish - start
			var side := _edge_side(edge, winding)
			if side.is_empty():
				continue
			var horizontal := side in ["north", "south"]
			var outward := Vector2(signf(edge.y), -signf(edge.x)) * winding
			var inward := -outward
			var edge_length := edge.length()
			var cell_count := roundi(edge_length / CELL)
			if cell_count <= 0:
				continue
			var direction := edge / edge_length
			var band := Sprite2D.new()
			band.name = "WallBand_%s_%02d" % [side, i]
			band.set_meta(&"camera_room", String(room.name))
			band.set_meta(&"wall_band", true)
			var edge_middle := (start + finish) * 0.5
			var turn := float(DungeonDoor.WALL_TURNS[side])
			var style := _style(world, edge_middle + inward * (CELL * 3.0), turn, map_id)
			var plain := _texture(style + "-plain")
			band.texture = plain
			band.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			band.region_enabled = true
			band.region_rect = Rect2(0, 0, edge_length * 2.0, plain.get_height())
			band.scale = Vector2(0.5, 0.5 * _depth(side))
			band.rotation = turn
			band.position = edge_middle + inward * (96.0 * _depth(side))
			holder.add_child(band)
			var run_start := -1
			for cell_index in cell_count + 1:
				var open := false
				if cell_index < cell_count:
					var at := start + direction * ((cell_index + 0.5) * CELL) + inward * (CELL * 0.5)
					var cell := Vector2i(floori(at.x / CELL), floori(at.y / CELL))
					var data := elevation.get_cell_tile_data(cell)
					open = data == null or int(data.get_custom_data("elevation_level")) <= 0

				if open and run_start < 0:
					run_start = cell_index
				elif not open and run_start >= 0:
					var count := cell_index - run_start
					if count >= 2 and not _has_dynamic_doorway(world, start, direction, inward, side, run_start, count):
						var along := (run_start + count * 0.5) * CELL
						if not horizontal and count >= 4:
							along += CELL
						var opening := Node2D.new()
						opening.name = "WallOpening_%s_%02d_%d" % [side, i, run_start]
						opening.set_meta(&"camera_room", String(room.name))
						opening.rotation = float(DungeonDoor.WALL_TURNS[side])
						holder.add_child(opening)
						opening.global_position = start + direction * along + inward * (192.0 * _depth(side))
						_frame(opening, style, side)
					run_start = -1

static func _edge_side(edge: Vector2, winding: float) -> String:
	if absf(edge.y) < 0.01 and absf(edge.x) >= 0.01:
		return "north" if edge.x * winding > 0.0 else "south"
	if absf(edge.x) < 0.01 and absf(edge.y) >= 0.01:
		return "east" if edge.y * winding > 0.0 else "west"
	return ""


static func _has_dynamic_doorway(world: Node2D, start: Vector2, direction: Vector2, inward: Vector2,
		side: String, run_start: int, count: int) -> bool:
	var from := float(run_start) * CELL
	var to := float(run_start + count) * CELL
	var turn := float(DungeonDoor.WALL_TURNS[side])
	for node: Node in world.find_children("WallDoorway", "Sprite2D", true, false):
		var frame := node as Sprite2D
		var parent := frame.get_parent()
		if not (parent.has_method(&"is_open") or parent.has_method(&"is_shut") or parent.has_method(&"is_smashed") or parent.has_node("GateScript")):
			continue
		if absf(wrapf(frame.global_rotation - turn, -PI, PI)) > 0.01:
			continue
		var relative := frame.global_position - start
		var along := relative.dot(direction)
		var across := absf(relative.dot(inward))
		if along >= from and along <= to and across <= FRAME_SIZE.y:
			return true
	return false



static func _latch(world: Node2D, root: Node2D, map_id: String) -> void:
	var old_frame := root.get_node_or_null("Frame") as Sprite2D
	if old_frame != null:
		old_frame.visible = false
	_frame(root, _style(world, root.global_position, root.rotation, map_id), "north")
	var slab := root.get_node_or_null("Slab") as Sprite2D
	if slab == null:
		return
	slab.texture = _texture("shutter-leaf")
	slab.centered = false
	slab.offset = Vector2(-128, -256)
	slab.position = Vector2.ZERO
	slab.scale = Vector2(0.5, 0.5)
	var region := Rect2(Vector2.ZERO, slab.texture.get_size())
	slab.set(&"_region", region)
	slab.region_enabled = true
	slab.region_rect = region
	slab.call(&"_settle")

static func _board_gate(world: Node2D, root: Node2D, map_id: String) -> void:
	_frame(root, _style(world, root.global_position, root.rotation, map_id), "north")
	var visual := root.get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	var state := visual.frame
	var kind := "barricade-leaves"
	if root.scene_file_path.ends_with("/lantern-gate.tscn"):
		kind = "mine-gate-leaves"
	elif root.scene_file_path.ends_with("/rotten-timbers.tscn"):
		kind = "rotten-leaves"
	visual.texture = _texture(kind)
	visual.hframes = 2
	visual.vframes = 1
	visual.centered = false
	visual.offset = Vector2(-128, -256)
	visual.position = Vector2.ZERO
	visual.scale = Vector2(0.5, 0.5)
	visual.frame = state
