extends RefCounted
## Splits the three dungeon worlds into editable room scenes and a shared shell.
## Runtime assembly preserves the dungeon ids, coordinates, object paths and persistent signals.
const SceneSave := preload("res://tools/lib/scene_save.gd")
const ROOM_SCENE := preload("res://game/dungeon/room_scene.gd")
const SHELL := preload("res://game/dungeon/room_scene_shell.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
const WORLDS: Array[String] = ["fatty-lair", "weaver-hollow-trunk", "weaver-hollow-roots", "weaver-hollow-boughs", "weaver-hollow-crown", "crystal-mine"]
var _world: Node2D
var _rooms: Array[Dictionary] = []
var _path := ""

func split(id: String) -> Error:
	_path = "res://game/scenes/worlds/%s.tscn" % id
	var before := FileAccess.get_file_as_string(_path)
	_world = (ResourceLoader.load(_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	_rooms.clear()
	_partition_burr_cell(id)
	_partition_hidden_rooms(id)
	var cameras := _world.get_node_or_null("CameraRooms")
	if cameras == null:
		_world.free()
		return ERR_DOES_NOT_EXIST
	var links: Array[Dictionary] = []
	_connections(_world, links)
	for camera: Node in cameras.get_children():
		if not camera is CameraRoom:
			continue
		var room := Node2D.new()
		room.name = camera.name
		room.set_script(ROOM_SCENE)
		room.set(&"world_id", id)
		room.set(&"room_id", str(camera.name))
		room.y_sort_enabled = true
		room.set_meta(&"room_rect", (camera as CameraRoom).rect())
		_rooms.append({"rect": (camera as CameraRoom).rect(), "root": room, "camera": camera})
	# Each room gets its terrain and local objects. Coordinates remain in dungeon space.
	for layer: Node in _world.get_children():
		if layer is TileMapLayer:
			_split_layer(layer as TileMapLayer)
	for container: Node in _world.get_children():
		if container is TileMapLayer or container.scene_file_path != "" or container.get_script() != null:
			continue
		if container.name in [&"CameraRooms", &"Objects", &"Scenery", &"Enemies", &"Hazards", &"Lair", &"Doors", &"DarkRooms", &"RoomArenas", &"Rails", &"KitMarkers"]:
			_split_objects(container)
	var dir := "res://game/scenes/worlds/rooms/" + id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var holder := Node2D.new()
	holder.name = "RoomScenes"
	_world.add_child(holder)
	holder.owner = _world
	for record: Dictionary in _rooms:
		var room := record["root"] as Node2D
		var room_path := dir.path_join(str(room.name) + ".tscn")
		var old := FileAccess.get_file_as_string(room_path) if FileAccess.file_exists(room_path) else ""
		var error := SceneSave.save(room, room_path, old)
		if error != OK:
			_world.free()
			return error
		room.free()
		var instance := (ResourceLoader.load(room_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		holder.add_child(instance)
		instance.owner = _world
	_world.set_script(SHELL)
	_world.set(&"room_connections", links)
	var error := SceneSave.save(_world, _path, before)
	print(id, ": ", _rooms.size(), " room scenes; ", links.size(), " persistent connections; ", error_string(error))
	_world.free()
	return error

func _room_at(at: Vector2) -> Node2D:
	for record: Dictionary in _rooms:
		if (record["camera"] as CameraRoom).contains(at):
			return record["root"] as Node2D
	return null

func _holder(room: Node2D, source: Node) -> Node:
	var existing := room.get_node_or_null(NodePath(str(source.name)))
	if existing != null:
		return existing
	var holder := Node2D.new() if source is Node2D else Node.new()
	holder.name = source.name
	if holder is Node2D:
		(holder as Node2D).y_sort_enabled = (source as Node2D).y_sort_enabled
	room.add_child(holder)
	holder.owner = room
	return holder

func _split_layer(layer: TileMapLayer) -> void:
	var copies := {}
	for cell: Vector2i in layer.get_used_cells():
		var point := layer.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Vector2(layer.tile_set.tile_size)
		var room := _room_at(point)
		if room == null:
			continue
		if not copies.has(room):
			var copy := layer.duplicate() as TileMapLayer
			copy.clear()
			room.add_child(copy)
			copy.owner = room
			copies[room] = copy
		var target := copies[room] as TileMapLayer
		target.set_cell(cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell))
		layer.erase_cell(cell)

func _split_objects(container: Node) -> void:
	for child: Node in container.get_children():
		if child.scene_file_path == "res://game/scenes/objects/dungeon/dungeon.tscn":
			continue # Shared dungeon identity must be readable from the shell without instantiating rooms.
		if not child is Node2D:
			continue
		var at := (child as Node2D).position + (container as Node2D).position if container is Node2D else (child as Node2D).position
		if child is CameraRoom:
			at = (child as CameraRoom).rect().get_center()
		var room := _room_at(at)
		if room == null:
			continue
		var destination := _holder(room, container)
		_detach_owner(child, _world)
		child.reparent(destination, false)
		_own(child, room)
		# Child overrides of scene instances must remain editable to survive packing.
		if not child.scene_file_path.is_empty():
			room.set_editable_instance(child, true)

func _own(node: Node, room: Node) -> void:
	if node.owner == _world or node.owner == null:
		node.owner = room
	for child: Node in node.get_children():
		_own(child, room)

func _connections(node: Node, output: Array[Dictionary]) -> void:
	for signal_info: Dictionary in node.get_signal_list():
		for link: Dictionary in node.get_signal_connection_list(signal_info["name"]):
			if int(link["flags"]) & CONNECT_PERSIST == 0:
				continue
			var callback: Callable = link["callable"]
			var target := callback.get_object() as Node
			if target == null or not _world.is_ancestor_of(target):
				continue
			output.append({"source": str(_world.get_path_to(node)), "target": str(_world.get_path_to(target)),
				"signal": str(signal_info["name"]), "method": str(callback.get_method()),
				"binds": callback.get_bound_arguments(), "flags": int(link["flags"])})
	for child: Node in node.get_children():
		_connections(child, output)


func _detach_owner(node: Node, previous: Node) -> void:
	if node.owner == previous:
		node.owner = null
	for child: Node in node.get_children():
		_detach_owner(child, previous)


## Burr's closed cell is its own room; the Pit Hall wraps around it as an L.
func _partition_burr_cell(id: String) -> void:
	if id != "fatty-lair" or _world.has_node("CameraRooms/burr-cell"):
		return
	var holder := _world.get_node("CameraRooms")
	var hub := holder.get_node("r3-pit-hall") as CameraRoom
	var cell := CameraRoom.new()
	cell.name = "burr-cell"
	cell.position = hub.position
	cell.size = Vector2(256, 512)
	holder.add_child(cell)
	cell.owner = _world
	var entry := Node2D.new()
	entry.name = "RoomEntry"
	entry.position = Vector2(128, 416)
	cell.add_child(entry)
	entry.owner = _world
	hub.outline = PackedVector2Array([Vector2(256, 0), Vector2(hub.size.x, 0), hub.size,
		Vector2(0, hub.size.y), Vector2(0, 512), Vector2(256, 512)])


## Closed treasure pockets get their own outlines, so curiosity does not reveal their contents early.
func _partition_hidden_rooms(id: String) -> void:
	var holder := _world.get_node_or_null("CameraRooms")
	if holder == null:
		return
	if id == "fatty-lair" and not holder.has_node("r1-store"):
		var gatehouse := holder.get_node("r1-gatehouse") as CameraRoom
		var origin := gatehouse.position
		_add_camera(holder, "r1-store", origin + Vector2(704, 0), Vector2(320, 384))
		gatehouse.outline = PackedVector2Array([Vector2.ZERO, Vector2(704, 0), Vector2(704, 384),
			Vector2(1024, 384), Vector2(1024, 896), Vector2(0, 896)])
		var hall := holder.get_node("r5-eye-hall") as CameraRoom
		origin = hall.position
		hall.size.y = 512
		var lower := _add_camera(holder, "r5-lower-hall", origin + Vector2(0, 512), Vector2(1024, 384))
		lower.outline = PackedVector2Array([Vector2.ZERO, Vector2(1024, 0), Vector2(1024, 384),
			Vector2(320, 384), Vector2(320, 128), Vector2(0, 128)])
		_add_camera(holder, "r5-key-alcove", origin + Vector2(0, 640), Vector2(320, 256))
	if id == "weaver-hollow-trunk" and not holder.has_node("T3a-map-nook"):
		var well := holder.get_node("T4-well-room") as CameraRoom
		var nook := _add_camera(holder, "T3a-map-nook", well.position, Vector2(320, 896))
		(nook.get_node("RoomEntry") as Node2D).position = Vector2(160, 736)
		well.position.x += 320
		well.size.x -= 320
		well.set_meta(&"wall_bands", false)

func _add_camera(holder: Node, room_name: String, at: Vector2, size: Vector2) -> CameraRoom:
	var camera := CameraRoom.new()
	camera.name = room_name
	camera.position = at
	camera.size = size
	camera.set_meta(&"wall_bands", false)
	holder.add_child(camera)
	camera.owner = _world
	var entry := Node2D.new()
	entry.name = "RoomEntry"
	entry.position = size * 0.5
	camera.add_child(entry)
	entry.owner = _world
	return camera
