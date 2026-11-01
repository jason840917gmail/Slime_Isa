extends SceneTree
## Builds the box-room lab (docs/godot/INTERIOR_WALLS.md "The box-room lab"): a small dev dungeon
## whose walls are an InteriorWallLayer, authored as separate room scenes under a room-scene shell
## the way the dungeons are (docs/godot/DUNGEON_ROOMS.md), so it proves the real structure.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_box_room_lab.gd [-- --force]
## Writes res://game/dev/interior/box-room-lab.tscn (world.box-room-lab; `?map=box-room-lab` or
## `-- --map=box-room-lab`) and its rooms in res://game/dev/interior/rooms/. It does not overwrite an
## existing lab unless given --force. It paints no elevation (no cache to bake).
##
## Three rooms in dungeon space (cells; a two-cell rim each, the bevelled faces, so rooms side by
## side are parted by a four-cell band, a doorway a two-by-two opening in each room's face):
##
##   a-square  16 x 14 at (0, 0): a shut shutter north, a cracked wall west (bomb it), a key door
##             with two locks east (into the L), an open doorway south (to the hall)
##   b-l-room  an L, 32 x 28 at (16, 0) without its lower-left quarter (bigger than a screen, an
##             outline): the boss door north, stairs in the east wall, a blown hole south, the
##             bolted door west in its lower arm (bolt on its side), the inner corner
##   c-hall    a long hall 32 x 14 at (0, 14): the entrance; an open doorway north, a key door with
##             one lock west, the seal and the way out south, a shutter south, the back of the
##             bolted door east
##
## Each room's floor is trimmed along its walls on a `floor-trim` layer (ROOM_TRIMS; the shell has an
## empty one its rooms' cells join).
##
## Owner: world (interior walls).

const SceneSave := preload("res://tools/lib/scene_save.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")

const SHELL_PATH := "res://game/dev/interior/box-room-lab.tscn"
const ROOMS_DIR := "res://game/dev/interior/rooms/"
const MAP_ID := "box-room-lab"
const STYLE := "lair-stone"
const CELL := 64
const COLUMNS := 48
const ROWS := 28
const COBBLE := 19
const SHEET_CELLS := 19
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const INTERIOR_TILESET := "res://game/world/interior/interior_wall_tileset.tres"
const INTERIOR_LAYER := "res://game/world/interior/interior_wall_layer.gd"
const TRIM_TILESET := "res://game/world/interior/interior_trim_tileset.tres"
const TRIM_LAYER := "res://game/world/interior/interior_trim_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const ROOM_SCENE := "res://game/dungeon/room_scene.gd"
const SHELL := "res://game/dungeon/room_scene_shell.gd"
const DOOR := "res://game/scripts/door.gd"
const KIT := "res://game/scenes/objects/dungeon/"
const OBJECTS := "res://game/scenes/objects/"
const BANNER_ART := "res://asset/MAPS/objects/fattys-lair/war-banner.webp"

## Rooms: name -> {cells: [Rect2i...] the room's area (union), camera: Rect2i, entry: cell}.
var ROOMS := {
	"a-square": {"areas": [Rect2i(0, 0, 16, 14)], "entry": Vector2(8, 9)},
	"b-l-room": {"areas": [Rect2i(16, 0, 32, 14), Rect2i(32, 14, 16, 14)], "entry": Vector2(24, 8)},
	"c-hall": {"areas": [Rect2i(0, 14, 32, 14)], "entry": Vector2(12, 22)},
}
## Openings: [room, side, the first cell along the wall (x for north/south, y for west/east), kind];
## an opening is the two-by-two block of its face there (two along, two deep).
var OPENINGS := [
	["a-square", "n", 7, "doorway"],
	["a-square", "w", 6, "cracked"],
	["a-square", "e", 6, "doorway"],
	["a-square", "s", 7, "doorway"],
	["b-l-room", "w", 6, "doorway"],
	["b-l-room", "n", 31, "doorway"],
	["b-l-room", "e", 4, "stairs"],
	["b-l-room", "s", 39, "blown"],
	["b-l-room", "w", 20, "doorway"],
	["c-hall", "n", 7, "doorway"],
	["c-hall", "e", 20, "doorway"],
	["c-hall", "s", 7, "doorway"],
	["c-hall", "s", 21, "doorway"],
	["c-hall", "w", 20, "doorway"],
]
## The face's depth, cells (the rim each room paints).
const DEPTH := 2
## Each room's floor trim (docs/godot/INTERIOR_WALLS.md "Floor trim"), painted on its floor cells
## along the walls.
const ROOM_TRIMS := {"a-square": "framed-cream", "b-l-room": "studded-slate", "c-hall": "bricks-umber"}

var _shell: Node2D
var _rooms: Dictionary = {}
var _tiles: Dictionary = {}


func _initialize() -> void:
	if FileAccess.file_exists(SHELL_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("box-room lab: %s exists; not overwritten (add -- --force to rebuild it)" % SHELL_PATH)
		quit(0)
		return
	_read_palette()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOMS_DIR))
	for room: String in ROOMS:
		_rooms[room] = _room(room)
	_place()
	var err := OK
	var instances: Array[String] = []
	for room: String in ROOMS:
		var root := _rooms[room] as Node2D
		for child in root.get_children():
			_own(child, root)
		var path := ROOMS_DIR + room + ".tscn"
		var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		err = SceneSave.save(root, path, before)
		root.free()
		if err != OK:
			break
		instances.append(path)
	if err == OK:
		err = _save_shell(instances)
	print("box-room lab: ", "ok" if err == OK else "failed (%s)" % error_string(err))
	quit(0 if err == OK else 1)


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_own(child, owner_node)


## The palette tile of each opening kind ("" the plain wall) for the style.
func _read_palette() -> void:
	var tile_set := load(INTERIOR_TILESET) as TileSet
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if str(data.get_custom_data(InteriorWalls.STYLE_DATA)) == STYLE:
			_tiles[str(data.get_custom_data(InteriorWalls.OPENING_DATA))] = coords


func _in_room(room: String, cell: Vector2i) -> bool:
	for area: Rect2i in ROOMS[room]["areas"]:
		if area.has_point(cell):
			return true
	return false


func _bounds(room: String) -> Rect2i:
	var bounds := Rect2i()
	for area: Rect2i in ROOMS[room]["areas"]:
		bounds = area if not bounds.has_area() else bounds.merge(area)
	return bounds


## One room scene: its ground, its wall rim on the interior wall layer (with its openings), its
## camera room.
func _room(room: String) -> Node2D:
	var root := Node2D.new()
	root.name = room
	root.set_script(load(ROOM_SCENE))
	root.set(&"world_id", MAP_ID)
	root.set(&"room_id", room)
	root.y_sort_enabled = true
	var ground := _ground_layer()
	var walls := _wall_layer()
	var bounds := _bounds(room)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			if not _in_room(room, cell):
				continue
			ground.set_cell(cell, COBBLE, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
			var rim := false
			for dy in range(-DEPTH, DEPTH + 1):
				for dx in range(-DEPTH, DEPTH + 1):
					if not _in_room(room, cell + Vector2i(dx, dy)):
						rim = true
			if rim:
				walls.set_cell(cell, 0, _tiles[""])
	for opening: Array in OPENINGS:
		if opening[0] != room:
			continue
		for cell: Vector2i in _block(room, str(opening[1]), int(opening[2])):
			walls.set_cell(cell, 0, _tiles[str(opening[3])])
	var trim := _trim_layer()
	var trim_tile := _trim_tile(str(ROOM_TRIMS[room]))
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			if not _in_room(room, cell) or walls.get_cell_source_id(cell) >= 0:
				continue
			# a floor cell beside the rim (or at its inner corner)
			var edge := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					edge = edge or walls.get_cell_source_id(cell + Vector2i(dx, dy)) >= 0
			if edge:
				trim.set_cell(cell, 0, trim_tile)
	root.add_child(ground)
	root.add_child(walls)
	root.add_child(trim)
	var cameras := Node2D.new()
	cameras.name = "CameraRooms"
	root.add_child(cameras)
	var camera := Node2D.new()
	camera.set_script(load(CAMERA_ROOM))
	camera.name = room
	camera.position = Vector2(bounds.position * CELL)
	camera.set(&"size", Vector2(bounds.size * CELL))
	if (ROOMS[room]["areas"] as Array).size() > 1:
		camera.set(&"outline", _outline(room, bounds))
	cameras.add_child(camera)
	var entry := Node2D.new()
	entry.name = "RoomEntry"
	entry.position = (ROOMS[room]["entry"] as Vector2) * CELL - camera.position
	camera.add_child(entry)
	for holder in ["Objects", "Scenery"]:
		var node := Node2D.new()
		node.name = holder
		node.y_sort_enabled = true
		root.add_child(node)
	return root


## The L's outline (local to its camera room): its area's corners, clockwise from the top left.
func _outline(room: String, bounds: Rect2i) -> PackedVector2Array:
	var w := float(bounds.size.x * CELL)
	var h := float(bounds.size.y * CELL)
	# b-l-room: the upper band over the whole width, the lower arm on the east half
	return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.5, h),
		Vector2(w * 0.5, h * 0.5), Vector2(0, h * 0.5)])


func _ground_layer() -> TileMapLayer:
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_script(load(WORLD_GROUND))
	return ground


func _wall_layer() -> TileMapLayer:
	var walls := TileMapLayer.new()
	walls.name = "interior-walls"
	walls.tile_set = load(INTERIOR_TILESET)
	walls.set_script(load(INTERIOR_LAYER))
	return walls


func _trim_layer() -> TileMapLayer:
	var trim := TileMapLayer.new()
	trim.name = "floor-trim"
	trim.tile_set = load(TRIM_TILESET)
	trim.set_script(load(TRIM_LAYER))
	return trim


## The palette tile of the floor trim `name` ("<shape>-<colour>").
func _trim_tile(name: String) -> Vector2i:
	var source := (load(TRIM_TILESET) as TileSet).get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if str(source.get_tile_data(coords, 0).get_custom_data("floor_trim")) == name:
			return coords
	return Vector2i.ZERO


# --- the pieces in the gaps --------------------------------------------------------------------

## The area of `room` whose `side` the opening at `along` is in.
func _area_at(room: String, side: String, along: int) -> Rect2i:
	for area: Rect2i in ROOMS[room]["areas"]:
		var on := (along >= area.position.x and along < area.end.x) if side == "n" or side == "s" 			else (along >= area.position.y and along < area.end.y)
		if not on:
			continue
		# the side must be an outer edge of the room there
		var probe := Vector2i(along, area.position.y - 1) if side == "n" else Vector2i(along, area.end.y) if side == "s" 			else Vector2i(area.position.x - 1, along) if side == "w" else Vector2i(area.end.x, along)
		if not _in_room(room, probe):
			return area
	return (ROOMS[room]["areas"] as Array)[0]


## The four cells of an opening's block: two along from `along`, two deep into the rim.
func _block(room: String, side: String, along: int) -> Array[Vector2i]:
	var area := _area_at(room, side, along)
	var out: Array[Vector2i] = []
	for d in DEPTH:
		for i in 2:
			match side:
				"n":
					out.append(Vector2i(along + i, area.position.y + d))
				"s":
					out.append(Vector2i(along + i, area.end.y - 1 - d))
				"w":
					out.append(Vector2i(area.position.x + d, along + i))
				_:
					out.append(Vector2i(area.end.x - 1 - d, along + i))
	return out


## Where a door object stands for the opening: the middle of its passage on the room's floor line
## (DungeonDoor's place: the face's foot).
func _gap(room: String, side: String, along: int) -> Vector2:
	var area := _area_at(room, side, along)
	match side:
		"n":
			return Vector2((along + 1) * CELL, (area.position.y + DEPTH) * CELL)
		"s":
			return Vector2((along + 1) * CELL, (area.end.y - DEPTH) * CELL)
		"w":
			return Vector2((area.position.x + DEPTH) * CELL, (along + 1) * CELL)
	return Vector2((area.end.x - DEPTH) * CELL, (along + 1) * CELL)


func _kit(room: String, scene: String, name: String, at: Vector2, props: Dictionary = {}) -> Node2D:
	var node := (load(KIT + scene + ".tscn") as PackedScene).instantiate() as Node2D
	node.name = name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	(_rooms[room] as Node2D).get_node("Objects").add_child(node)
	return node


func _object(room: String, scene: String, name: String, at: Vector2, holder: String = "Scenery") -> Node2D:
	var node := (load(OBJECTS + scene + ".tscn") as PackedScene).instantiate() as Node2D
	node.name = name
	node.position = at
	(_rooms[room] as Node2D).get_node(holder).add_child(node)
	return node


func _chest(room: String, scene: String, name: String, at: Vector2, contents: Dictionary) -> void:
	var chest := _kit(room, scene, name, at)
	var root := _rooms[room] as Node2D
	root.set_editable_instance(chest, true)
	var script_node := chest.get_node("ChestScript")
	script_node.set(&"instance_id", name)
	script_node.set(&"initial_contents", contents)


func _banner(room: String, name: String, cell_x: float, wall_row: int) -> void:
	var banner := _object(room, "decoration-world-solid--war-banner", name, Vector2(cell_x * CELL, (wall_row + 1) * CELL + 20))
	var visual := banner.get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.texture = load(BANNER_ART) if ResourceLoader.exists(BANNER_ART) else visual.texture
		(_rooms[room] as Node2D).set_editable_instance(banner, true)


func _place() -> void:
	# a-square: a shutter north (shut), a cracked wall west (bomb it), a two-lock key door east
	_kit("a-square", "shutter", "a-shutter-north", _gap("a-square", "n", 7),
		{"wall": "north", "starts_shut": true, "shutter_id": "a-north", "frame_drawn_by_wall": true})
	var crack := _object("a-square", "cracked-wall", "a-cracked-west", _gap("a-square", "w", 6), "Objects")
	crack.set(&"frame_drawn_by_wall", true)
	crack.set(&"flag_id", "box-room-lab.a-west-blown")
	crack.set(&"passage", Rect2(-128, -32, 128, 64))
	_kit("a-square", "key-door", "a-key-door-east", _gap("a-square", "e", 6),
		{"wall": "east", "door_id": "a-east", "keyholes": 2, "frame_drawn_by_wall": true})
	_banner("a-square", "a-banner-west", 4.5, 1)
	_banner("a-square", "a-banner-east", 11.5, 1)
	_chest("a-square", "dungeon-chest", "a-key-chest", Vector2(5, 5) * CELL, {"dungeon-small-key": 1})
	for i in 3:
		_kit("a-square", "dungeon-pot", "a-pot-%d" % i, Vector2(10.5 + i * 1.1, 11.4) * CELL)
	# b-l-room: the boss door north, the bolted door west in the lower arm (bolt on its side)
	_kit("b-l-room", "boss-door", "b-boss-door", _gap("b-l-room", "n", 31),
		{"wall": "north", "door_id": "b-boss", "frame_drawn_by_wall": true})
	_kit("b-l-room", "bolted-door", "b-bolted-door", _gap("b-l-room", "w", 20),
		{"wall": "west", "door_id": "b-bolt", "frame_drawn_by_wall": true})
	_banner("b-l-room", "b-banner-1", 22.5, 1)
	_banner("b-l-room", "b-banner-2", 40.5, 1)
	_chest("b-l-room", "dungeon-big-chest", "b-big-chest", Vector2(40, 19) * CELL, {"dungeon-big-key": 1})
	# c-hall: a one-lock key door west, the seal and a shutter south
	_kit("c-hall", "key-door", "c-key-door-west", _gap("c-hall", "w", 20),
		{"wall": "west", "door_id": "c-west", "keyholes": 1, "frame_drawn_by_wall": true})
	_kit("c-hall", "dungeon-seal", "c-seal", _gap("c-hall", "s", 7),
		{"wall": "south", "glimpse": true, "frame_drawn_by_wall": true})
	_kit("c-hall", "shutter", "c-shutter-south", _gap("c-hall", "s", 21),
		{"wall": "south", "starts_shut": true, "shutter_id": "c-south", "frame_drawn_by_wall": true})
	_chest("c-hall", "dungeon-chest", "c-key-chest", Vector2(16, 19) * CELL, {"dungeon-small-key": 2})
	_banner("c-hall", "c-banner-1", 4.5, 15)
	_banner("c-hall", "c-banner-2", 26.5, 15)


func _save_shell(instances: Array[String]) -> Error:
	_shell = Node2D.new()
	_shell.name = MAP_ID
	_shell.y_sort_enabled = true
	_shell.set_script(load(SHELL))
	var ground := _ground_layer()
	_shell.add_child(ground)
	_shell.add_child(_wall_layer())
	_shell.add_child(_trim_layer())
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(ROOMS["c-hall"]["entry"]) * CELL
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	_shell.add_child(definition)
	for marker in ["player-spawn", "dungeon-entrance"]:
		var node := Node2D.new()
		node.name = marker
		node.position = spawn
		_shell.add_child(node)
	for holder in ["CameraRooms", "Objects", "Scenery", "Enemies"]:
		var node := Node2D.new()
		node.name = holder
		node.y_sort_enabled = holder != "CameraRooms"
		_shell.add_child(node)
	var dungeon := (load(KIT + "dungeon.tscn") as PackedScene).instantiate() as Node2D
	dungeon.name = "Dungeon"
	dungeon.position = spawn
	dungeon.set(&"dungeon_id", MAP_ID)
	dungeon.set(&"display_name", "Box-Room Lab")
	dungeon.set(&"entrance_marker", "dungeon-entrance")
	dungeon.set(&"resume_saves", false)
	_shell.add_child(dungeon)
	# the way out: the hall's south doorway, behind the seal
	var way_out := Node2D.new()
	way_out.name = "c-way-out"
	way_out.position = Vector2(8, 27.4) * CELL
	_shell.add_child(way_out)
	var door := Node.new()
	door.name = "Door"
	door.set_script(load(DOOR))
	door.set(&"map_id", MAP_ID)
	door.set(&"door_id", "box-room-lab-way-out")
	door.set(&"target_area_id", "playground")
	door.set(&"kind", "opening")
	door.set(&"side", "south")
	door.set(&"trigger_rect", Rect2(-64, 0, 128, 24))
	way_out.add_child(door)
	var holder := Node2D.new()
	holder.name = "RoomScenes"
	_shell.add_child(holder)
	for child in _shell.get_children():
		_own(child, _shell)
	for path in instances:
		var instance := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		holder.add_child(instance)
		instance.owner = _shell
	var before := FileAccess.get_file_as_string(SHELL_PATH) if FileAccess.file_exists(SHELL_PATH) else ""
	var err := SceneSave.save(_shell, SHELL_PATH, before)
	_shell.free()
	return err
