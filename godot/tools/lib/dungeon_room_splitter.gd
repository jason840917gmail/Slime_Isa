extends RefCounted
## Splits the three dungeon worlds into editable room scenes and a shared shell.
## Runtime assembly preserves the dungeon ids, coordinates, object paths and persistent signals.
## In the worlds of LOCAL_WORLDS every room is written local: its top-left corner at the scene's
## origin, its tile layers and nodes moved by the room's offset, the offset kept on the room's
## instance in the shell (`position`, a whole number of cells), which adds it back when it assembles
## the dungeon (room_scene_shell.gd). Fatty's Lair was the first (2026-10-18), then became one world
## per room and is never split again (RETIRED); the Hollow and the Mine follow when their walls are
## converted to interior walls (docs/godot/DUNGEON_ROOMS.md).
##
## Hand edits are safe (DUNGEON_ROOMS.md "Editing rooms by hand"): every room scene and the shell it
## writes is recorded with the hash of the file as written, in `rooms/<world>/written.json`; a file
## that no longer matches its hash (edited in the editor since) is not rewritten, and the run prints
## it. Command-line options (`-- ...`): `--force` rewrites them anyway (with a warning), `--only=<a,b>`
## writes only those rooms (and the shell only when `shell` is listed), `--dry` writes nothing and
## prints what a run would write and skip, `--record-hashes` only records the files as they are.
const SceneSave := preload("res://tools/lib/scene_save.gd")
const ROOM_SCENE := preload("res://game/dungeon/room_scene.gd")
const SHELL := preload("res://game/dungeon/room_scene_shell.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
const LOCAL_WORLDS: Array[String] = []
const CELL := 64
const WORLDS: Array[String] = ["weaver-hollow-trunk", "weaver-hollow-roots", "weaver-hollow-boughs", "weaver-hollow-crown", "crystal-mine"]
var _world: Node2D
var _rooms: Array[Dictionary] = []
var _path := ""

var _force := false
var _dry := false
var _only := PackedStringArray()
var _record := {}
var _record_path := ""


## The written-files record of world `id`: {"rooms": {room: hash}, "shell": hash}.
static func record_path(id: String) -> String:
	return "res://game/scenes/worlds/rooms/%s/written.json" % id


static func file_hash(path: String) -> int:
	return FileAccess.get_file_as_string(path).hash() if FileAccess.file_exists(path) else 0


func _read_options() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--force":
			_force = true
		elif arg == "--dry":
			_dry = true
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)


func _load_record(id: String) -> void:
	_record_path = record_path(id)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_record_path)) if FileAccess.file_exists(_record_path) else null
	_record = parsed if parsed is Dictionary else {}
	if not _record.has("rooms"):
		_record["rooms"] = {}


func _save_record() -> void:
	if _dry:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_record_path.get_base_dir()))
	var file := FileAccess.open(_record_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_record, "\t", true) + "\n")


## True when the tool may write `path` (recorded as `key`, or the shell): not edited by hand since it
## wrote it, or `--force`; prints why when it may not.
func _may_write(path: String, recorded: Variant, label: String) -> bool:
	if not FileAccess.file_exists(path) or recorded == null:
		return true
	if file_hash(path) == int(recorded):
		return true
	if _force:
		print("WARNING: %s was edited by hand since the tool wrote it; --force rewrites it" % label)
		return true
	print("skipped %s: edited by hand since the tool wrote it (-- --force rewrites it)" % label)
	return false


## Records every room scene and the shell of world `id` as they are on disk now.
func record_hashes(id: String) -> Error:
	if id in RETIRED:
		print("%s: its room scenes are edited in the editor; no hashes to record" % id)
		return OK
	_load_record(id)
	var dir := "res://game/scenes/worlds/rooms/" + id
	var rooms := {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			rooms[file.get_basename()] = file_hash(dir.path_join(file))
	_record["rooms"] = rooms
	_record["shell"] = file_hash("res://game/scenes/worlds/%s.tscn" % id)
	_save_record()
	print(id, ": recorded ", rooms.size(), " room scenes and the shell")
	return OK


## Worlds whose scenes are the source of truth (edited in the editor): never split again.
## (Fatty's Lair is one world per room since 2026-10-18: no shell to split into.)
const RETIRED: Array[String] = ["fatty-lair"]


## Splits world `id` (read from `source`, else its own scene) into room scenes and its shell.
func split(id: String, source: String = "") -> Error:
	_read_options()
	if id in RETIRED:
		print("%s: its room scenes are edited in the editor; one world per room, never split" % id)
		return OK
	_load_record(id)
	_path = "res://game/scenes/worlds/%s.tscn" % id
	var before := FileAccess.get_file_as_string(_path)
	var from := source if not source.is_empty() else _path
	_world = (ResourceLoader.load(from, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	_rooms.clear()
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
	var local := id in LOCAL_WORLDS
	var rooms_record: Dictionary = _record["rooms"]
	var written := 0
	var skipped: PackedStringArray = []
	for record: Dictionary in _rooms:
		var room := record["root"] as Node2D
		var offset := Vector2.ZERO
		if local:
			var rect: Rect2 = record["rect"]
			offset = (rect.position / CELL).floor() * CELL
			_make_local(room, offset)
		# the doors standing in closed-door openings are the walls' (adopted, tagged)
		var walls := room.get_node_or_null(^"interior-walls")
		if walls != null and walls.has_method(&"sync_doors"):
			walls.call(&"sync_doors", false)
		var room_path := dir.path_join(str(room.name) + ".tscn")
		var key := str(room.name)
		var wanted := _only.is_empty() or _only.has(key)
		var allowed := wanted and _may_write(room_path, rooms_record.get(key), "room " + key)
		if not allowed and wanted:
			skipped.append(key)
		if allowed and not _dry:
			var old := FileAccess.get_file_as_string(room_path) if FileAccess.file_exists(room_path) else ""
			var error := SceneSave.save(room, room_path, old)
			if error != OK:
				_world.free()
				return error
			rooms_record[key] = file_hash(room_path)
			# kept at once: a run that fails later must not leave a file it wrote looking hand-edited
			_save_record()
		if allowed:
			written += 1
		room.free()
		if not FileAccess.file_exists(room_path):
			continue
		var instance := (ResourceLoader.load(room_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		holder.add_child(instance)
		instance.owner = _world
		if instance is Node2D:
			(instance as Node2D).position = offset
	_world.set_script(SHELL)
	_world.set(&"room_connections", links)
	var error := OK
	var shell_wanted := _only.is_empty() or _only.has("shell")
	var shell_allowed := shell_wanted and _may_write(_path, _record.get("shell"), "the shell " + _path.get_file())
	if shell_allowed and not _dry:
		error = SceneSave.save(_world, _path, before)
		if error == OK:
			_record["shell"] = file_hash(_path)
	_save_record()
	print("%s: %s %d of %d room scenes%s; the shell %s; %d persistent connections; %s" % [id,
		"would write" if _dry else "wrote", written, _rooms.size(),
		(" (skipped, edited by hand: %s)" % ", ".join(skipped)) if not skipped.is_empty() else "",
		("would be written" if _dry else "written") if shell_allowed else "kept", links.size(), error_string(error)])
	_world.free()
	return error

## Moves room `room`'s contents by -`offset` (world units, whole cells): its tile layers by the
## cells, every node of its holders by the units.
func _make_local(room: Node2D, offset: Vector2) -> void:
	room.set_meta(&"dungeon_offset", offset)
	for child: Node in room.get_children():
		if child is TileMapLayer:
			var layer := child as TileMapLayer
			var shift := Vector2i(offset / Vector2(layer.tile_set.tile_size))
			var cells := []
			for cell: Vector2i in layer.get_used_cells():
				cells.append([cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)])
			layer.clear()
			for c: Array in cells:
				layer.set_cell((c[0] as Vector2i) - shift, c[1], c[2], c[3])
		elif child is Node2D:
			for item: Node in child.get_children():
				if item is Node2D:
					(item as Node2D).position -= offset


## The room scene that holds `room`'s interior walls: its camera room's `walls_in` (a pocket cut
## from another room), else itself.
func _walls_room(room: Node2D) -> Node2D:
	for record: Dictionary in _rooms:
		if record["root"] == room:
			var parent := str((record["camera"] as Node).get_meta(&"walls_in", ""))
			if parent.is_empty():
				return room
			for other: Dictionary in _rooms:
				if str((other["root"] as Node).name) == parent:
					return other["root"] as Node2D
	return room


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
	# a pocket room's walls stay with the room it is cut from (its `walls_in`), so each room scene's
	# interior walls enclose its whole floor
	var walls := layer.name == &"interior-walls"
	for cell: Vector2i in layer.get_used_cells():
		var point := layer.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Vector2(layer.tile_set.tile_size)
		var room := _room_at(point)
		if walls and room != null:
			room = _walls_room(room)
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


## Closed treasure pockets get their own outlines, so curiosity does not reveal their contents early.
func _partition_hidden_rooms(id: String) -> void:
	var holder := _world.get_node_or_null("CameraRooms")
	if holder == null:
		return
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
