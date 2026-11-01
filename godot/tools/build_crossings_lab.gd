extends SceneTree
## Builds the playground's crossings corner and its three little worlds (docs/design/
## 2026-10-31-crossings-and-arrivals.md "The playground test corner"): every kind of crossing
## between worlds, each way, with its leaving and its arrival, in one place on the playground.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_crossings_lab.gd [-- --force]
## Writes res://game/dev/corners/crossings_corner.tscn (instanced in the playground east of the
## webs corner, x 5500-7936, y 5900-8200) and the worlds `playground-crossings-hut`,
## `playground-crossings-cellar` and `playground-crossings-annex` in
## res://game/scenes/worlds/rooms/playground/. It does not overwrite them unless given --force; after
## that they are scenes to edit by hand.
##
## - **The yard and the hut:** a room frame (InteriorWallLayer, Zelda's bevelled walls) on the
##   playground with a doorway in each of its four walls, and a hut world framed the same way with a
##   doorway in each of its walls. Each yard doorway leads to the hut's opposite one (north to south,
##   east to west) and back: the slime walks into a doorway while the iris closes and walks out of
##   the paired one, on all four sides.
## - **The stairs:** a stair door down on the playground to the cellar's stair door up, paired.
## - **The ladder:** a hole with a ladder down to the cellar's ladder and back.
## - **The drop:** a hole without a ladder that drops the slime onto the cellar's landing (one way).
## - **The border:** the playground's east edge beside the corner leads into the annex, laid beside
##   the playground on a shared frame (`along_offset`): the screen scrolls and the slime comes out at
##   the same height; the annex's west edge leads back.
##
## Owner: world objects.

const SceneSave := preload("res://tools/lib/scene_save.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")

const CORNER_PATH := "res://game/dev/corners/crossings_corner.tscn"
const ROOMS_DIR := "res://game/scenes/worlds/rooms/playground/"
const HUT := "playground-crossings-hut"
const CELLAR := "playground-crossings-cellar"
const ANNEX := "playground-crossings-annex"
const PLAYGROUND := "playground"
const PLAYGROUND_SCENE := "res://game/scenes/worlds/playground.tscn"

const CELL := 64
const STYLE := "lair-stone"
const COBBLE := 19
const SHEET_CELLS := 19
const DEPTH := 2
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const INTERIOR_TILESET := "res://game/world/interior/interior_wall_tileset.tres"
const INTERIOR_LAYER := "res://game/world/interior/interior_wall_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const WORLD_EXIT := "res://game/scripts/world_exit.gd"
const DOOR := "res://game/scripts/door.gd"
const STAIR_DOOR := "res://game/scenes/objects/stair-door.tscn"
const CAVE_LADDER := "res://game/scenes/objects/cave-ladder.tscn"
const LANDING := "res://game/scenes/objects/landing.tscn"
const HOLE_ART := "res://asset/MAPS/props/256x256-tile_8x1-gulp-props.webp"

## The yard's frame on the playground (cells) and the hut's (its whole world).
const YARD := Rect2i(86, 96, 16, 14)
const HUT_ROOM := Rect2i(0, 0, 16, 14)
## The doorway on each side: where along that wall its two cells start (cells, from the room's corner).
const DOORWAYS := {"north": 7, "south": 7, "west": 6, "east": 6}
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
## How deep the trigger at the doorway's outer end is, and how far inside that end the door node stands.
const TRIGGER_DEPTH := 48.0
const DOOR_INSET := 24.0

## The stations east of the yard (world units, the playground).
const STAIR_AT := Vector2(6912, 6400)
const LADDER_AT := Vector2(7296, 6400)
const DROP_AT := Vector2(7616, 6400)
## The playground's east edge beside the corner, and the annex laid against it (world units).
const EDGE_TOP := 7168.0
const ANNEX_TILES := Vector2i(16, 16)
const CELLAR_TILES := Vector2i(20, 14)
## Exits along an edge: a line this deep at the very edge (as the chunks' seams).
const EXIT_DEPTH := 4.0
const EXIT_LAYER := 512
const EXIT_MASK := 130

var _tiles: Dictionary = {}


func _initialize() -> void:
	var force := OS.get_cmdline_user_args().has("--force")
	for path: String in [CORNER_PATH, _world_path(HUT), _world_path(CELLAR), _world_path(ANNEX)]:
		if FileAccess.file_exists(path) and not force:
			print("crossings lab: %s exists; not overwritten (add -- --force to rebuild)" % path)
			quit(0)
			return
	_read_palette()
	var err := _save(_corner(), CORNER_PATH)
	if err == OK:
		err = _save(_hut(), _world_path(HUT))
	if err == OK:
		err = _save(_cellar(), _world_path(CELLAR))
	if err == OK:
		err = _save(_annex(), _world_path(ANNEX))
	print("crossings lab: ", "ok" if err == OK else "failed (%s)" % error_string(err))
	quit(0 if err == OK else 1)


func _world_path(world_id: String) -> String:
	return ROOMS_DIR + world_id + ".tscn"


func _save(root: Node, path: String) -> Error:
	for child: Node in root.get_children():
		_own(child, root)
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := SceneSave.save(root, path, before)
	root.free()
	return err


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	if node.scene_file_path.is_empty():
		for child: Node in node.get_children():
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


# --- the corner on the playground ---------------------------------------------------------------

func _corner() -> Node2D:
	var root := Node2D.new()
	root.name = "crossings-corner"
	root.y_sort_enabled = true
	root.add_child(_label("title", Vector2(5504, 5900), Vector2(2400, 96),
		"Crossings corner (docs/design/2026-10-31-crossings-and-arrivals.md): every way between worlds, each way.\n" +
		"You come out of the end paired with the one you went in by, and the arrival plays the leaving backwards.\n" +
		"Check the links of every world: tools/check_crossings.gd."))
	# The yard: four doorways into the hut, one per wall.
	root.add_child(_frame(YARD, "yard-walls"))
	for side: String in DOORWAYS:
		root.add_child(_doorway(YARD, side, PLAYGROUND, "playground-yard-%s" % side, HUT, "hut-%s" % OPPOSITE[side]))
	root.add_child(_label("yard-sign", Vector2(5632, 6300), Vector2(800, 80),
		"The yard: walk out of any doorway (push into it).\nIt leads into the hut through the opposite wall; the hut's doorways lead back."))
	# The stairs down to the cellar.
	var stair := _instance(STAIR_DOOR)
	stair.name = "stair-down"
	stair.position = STAIR_AT
	stair.set(&"direction", "down")
	stair.set(&"hatch_id", "playground-crossings-stair-down")
	stair.set(&"start_open", true)
	stair.set(&"target_world", CELLAR)
	stair.set(&"target_door", "cellar-stair-up")
	root.add_child(stair)
	root.add_child(_label("stair-sign", STAIR_AT + Vector2(-160, 112), Vector2(320, 60), "Stairs down to the cellar\n(and up again there)"))
	# The ladder down, and the drop.
	root.add_child(_hole("ladder-hatch", LADDER_AT, "playground-crossings-ladder-hatch", "ladder_down", CELLAR, "cellar-ladder"))
	root.add_child(_label("ladder-sign", LADDER_AT + Vector2(-140, 112), Vector2(280, 60), "A ladder down to the cellar\n(climb back up there)"))
	root.add_child(_hole("drop-hole", DROP_AT, "playground-crossings-drop", "fall", CELLAR, "cellar-landing"))
	root.add_child(_label("drop-sign", DROP_AT + Vector2(-140, 112), Vector2(300, 60), "A drop onto the cellar's landing\n(one way: take the stairs back)"))
	# The border: the playground's east edge beside the corner, into the annex.
	var size := _playground_size()
	root.add_child(_edge_exit("annex-edge", Rect2(size.x - EXIT_DEPTH, EDGE_TOP, EXIT_DEPTH, ANNEX_TILES.y * CELL),
		PLAYGROUND, "playground-to-crossings-annex", ANNEX, "west", -EDGE_TOP))
	root.add_child(_label("edge-sign", Vector2(size.x - 560, EDGE_TOP + 420), Vector2(520, 80),
		"The border: walk east off the playground's edge here.\nThe screen scrolls into the annex at the same height."))
	return root


## The world size of the playground (world units).
func _playground_size() -> Vector2:
	var root := (load(PLAYGROUND_SCENE) as PackedScene).instantiate()
	var definition := root.get_node(^"world-definition")
	var size := Vector2(int(definition.get(&"columns")), int(definition.get(&"rows"))) * float(int(definition.get(&"tile_size")))
	root.free()
	return size


# --- the worlds ---------------------------------------------------------------------------------

func _hut() -> Node2D:
	var root := _world(HUT, Vector2i(HUT_ROOM.size), Vector2(HUT_ROOM.get_center()) * CELL)
	_fill_cobble(root.get_node(^"ground") as TileMapLayer, Vector2i(HUT_ROOM.size))
	root.add_child(_frame(HUT_ROOM, "interior-walls"))
	for side: String in DOORWAYS:
		root.add_child(_doorway(HUT_ROOM, side, HUT, "hut-%s" % side, PLAYGROUND, "playground-yard-%s" % OPPOSITE[side]))
	root.add_child(_label("sign", Vector2(5, 5.5) * CELL, Vector2(6, 2) * CELL,
		"The hut: each doorway leads back to the yard,\nthrough the yard's opposite wall."))
	return root


func _cellar() -> Node2D:
	var size := CELLAR_TILES
	var root := _world(CELLAR, size, Vector2(10, 9) * CELL)
	_fill_cobble(root.get_node(^"ground") as TileMapLayer, size)
	var stair := _instance(STAIR_DOOR)
	stair.name = "stair-up"
	stair.position = Vector2(4, 4) * CELL
	stair.set(&"direction", "up")
	stair.set(&"hatch_id", "cellar-stair-up")
	stair.set(&"start_open", true)
	stair.set(&"target_world", PLAYGROUND)
	stair.set(&"target_door", "playground-crossings-stair-down")
	root.add_child(stair)
	var ladder := _instance(CAVE_LADDER)
	ladder.name = "ladder"
	ladder.position = Vector2(10, 4) * CELL
	root.add_child(ladder)
	# Its door's link is an override on the ladder scene's DoorScript (editable children).
	root.set_editable_instance(ladder, true)
	var ladder_door := ladder.get_node(^"DoorScript")
	ladder_door.set(&"map_id", CELLAR)
	ladder_door.set(&"door_id", "cellar-ladder")
	ladder_door.set(&"target_area_id", PLAYGROUND)
	ladder_door.set(&"target_door_id", "playground-crossings-ladder-hatch")
	var landing := _instance(LANDING)
	landing.name = "landing"
	landing.position = Vector2(15.5, 8) * CELL
	landing.set(&"door_id", "cellar-landing")
	root.add_child(landing)
	root.add_child(_label("sign", Vector2(1, 11) * CELL, Vector2(18, 2) * CELL,
		"The cellar: the stairs (left) and the ladder (middle) lead back up to the crossings corner;\nthe drop lands on the right."))
	return root


func _annex() -> Node2D:
	var size := ANNEX_TILES
	var root := _world(ANNEX, size, Vector2(size) * 0.5 * CELL)
	_copy_playground_ground(root.get_node(^"ground") as TileMapLayer, size)
	root.add_child(_edge_exit("playground-edge", Rect2(0, 0, EXIT_DEPTH, size.y * CELL), ANNEX,
		"crossings-annex-to-playground", PLAYGROUND, "east", EDGE_TOP))
	root.add_child(_label("sign", Vector2(3, 3) * CELL, Vector2(10, 2) * CELL,
		"The annex, laid east of the playground's edge.\nWalk off the west edge to scroll back at the same height."))
	return root


## A world root with its ground layer, world-definition, spawn and holders.
func _world(world_id: String, size: Vector2i, spawn: Vector2) -> Node2D:
	var root := Node2D.new()
	root.name = world_id
	root.y_sort_enabled = true
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	ground.set_meta(&"source_cell_count", size.x * size.y)
	ground.set_meta(&"columns", size.x)
	ground.set_meta(&"rows", size.y)
	ground.set_script(load(WORLD_GROUND))
	root.add_child(ground)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	definition.set(&"map_id", world_id)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", size.x)
	definition.set(&"rows", size.y)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	root.add_child(definition)
	var marker := Node2D.new()
	marker.name = "player-spawn"
	marker.position = spawn
	root.add_child(marker)
	for holder: String in ["Objects", "Scenery", "Enemies"]:
		var node := Node2D.new()
		node.name = holder
		node.y_sort_enabled = true
		root.add_child(node)
	return root


func _fill_cobble(ground: TileMapLayer, size: Vector2i) -> void:
	for y in size.y:
		for x in size.x:
			ground.set_cell(Vector2i(x, y), COBBLE, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))


## The annex's grass: the playground's own ground east of the corner, copied cell for cell.
func _copy_playground_ground(ground: TileMapLayer, size: Vector2i) -> void:
	var playground := (load(PLAYGROUND_SCENE) as PackedScene).instantiate()
	var source := playground.get_node(^"ground") as TileMapLayer
	var from := Vector2i(104, 112)
	for y in size.y:
		for x in size.x:
			var cell := from + Vector2i(x, y)
			ground.set_cell(Vector2i(x, y), source.get_cell_source_id(cell), source.get_cell_atlas_coords(cell),
				source.get_cell_alternative_tile(cell))
	playground.free()


# --- pieces -------------------------------------------------------------------------------------

## A room frame (InteriorWallLayer) over `room` (cells), two cells deep, with a doorway in each wall.
func _frame(room: Rect2i, layer_name: String) -> TileMapLayer:
	var walls := TileMapLayer.new()
	walls.name = layer_name
	walls.tile_set = load(INTERIOR_TILESET)
	walls.set_script(load(INTERIOR_LAYER))
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			var rim := x < room.position.x + DEPTH or x >= room.end.x - DEPTH or y < room.position.y + DEPTH or y >= room.end.y - DEPTH
			if rim:
				walls.set_cell(Vector2i(x, y), 0, _tiles[""])
	for side: String in DOORWAYS:
		for cell: Vector2i in _block(room, side):
			walls.set_cell(cell, 0, _tiles["doorway"])
	return walls


## The four cells of the doorway in `room`'s `side` wall: two along, two deep.
func _block(room: Rect2i, side: String) -> Array[Vector2i]:
	var along := int(DOORWAYS[side])
	var out: Array[Vector2i] = []
	for d in DEPTH:
		for i in 2:
			match side:
				"north":
					out.append(Vector2i(room.position.x + along + i, room.position.y + d))
				"south":
					out.append(Vector2i(room.position.x + along + i, room.end.y - 1 - d))
				"west":
					out.append(Vector2i(room.position.x + d, room.position.y + along + i))
				_:
					out.append(Vector2i(room.end.x - 1 - d, room.position.y + along + i))
	return out


## A door (door.gd, "opening") at the outer end of `room`'s `side` doorway, leading to
## `target_world`'s door `target_door`: its node `DOOR_INSET` inside that end, its trigger the last
## `TRIGGER_DEPTH` of the passage.
func _doorway(room: Rect2i, side: String, world_id: String, door_id: String, target_world: String, target_door: String) -> Node2D:
	var along := float(int(DOORWAYS[side]) + 1) * CELL
	var node := Node2D.new()
	node.name = door_id
	var trigger: Rect2
	match side:
		"north":
			node.position = Vector2(room.position.x * CELL + along, room.position.y * CELL + DOOR_INSET)
			trigger = Rect2(-CELL, -DOOR_INSET, CELL * 2, TRIGGER_DEPTH)
		"south":
			node.position = Vector2(room.position.x * CELL + along, room.end.y * CELL - DOOR_INSET)
			trigger = Rect2(-CELL, DOOR_INSET - TRIGGER_DEPTH, CELL * 2, TRIGGER_DEPTH)
		"west":
			node.position = Vector2(room.position.x * CELL + DOOR_INSET, room.position.y * CELL + along)
			trigger = Rect2(-DOOR_INSET, -CELL, TRIGGER_DEPTH, CELL * 2)
		_:
			node.position = Vector2(room.end.x * CELL - DOOR_INSET, room.position.y * CELL + along)
			trigger = Rect2(DOOR_INSET - TRIGGER_DEPTH, -CELL, TRIGGER_DEPTH, CELL * 2)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", world_id)
	door.set(&"door_id", door_id)
	door.set(&"target_area_id", target_world)
	door.set(&"target_door_id", target_door)
	door.set(&"kind", "opening")
	door.set(&"side", side)
	door.set(&"trigger_rect", trigger)
	node.add_child(door)
	return node


## A hole in the ground (the gulp props' hole picture) with a door: "ladder_down" or "fall".
func _hole(node_name: String, at: Vector2, door_id: String, kind: String, target_world: String, target_door: String) -> Node2D:
	var node := Node2D.new()
	node.name = node_name
	node.position = at
	node.y_sort_enabled = true
	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.z_index = -1
	visual.scale = Vector2(0.62, 0.62)
	visual.texture = load(HOLE_ART)
	visual.centered = false
	visual.offset = Vector2(-128, -194)
	visual.hframes = 8
	visual.frame = 1
	node.add_child(visual)
	var wall := StaticBody2D.new()
	wall.name = "Wall"
	wall.collision_mask = 0
	node.add_child(wall)
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	shape.position = Vector2(2, -28)
	var circle := CircleShape2D.new()
	circle.radius = 39.0
	shape.shape = circle
	wall.add_child(shape)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", PLAYGROUND)
	door.set(&"door_id", door_id)
	door.set(&"target_area_id", target_world)
	door.set(&"target_door_id", target_door)
	door.set(&"kind", kind)
	door.set(&"trigger_shape", shape)
	if kind == "ladder_down":
		door.set(&"use_cue", &"FallDown")
	node.add_child(door)
	var arrival := Node2D.new()
	arrival.name = "arrival"
	arrival.position = Vector2(-3, 41)
	node.add_child(arrival)
	return node


## A world exit along an edge: `rect` (world units) is its trigger; the slime comes out at its place
## along the edge plus `along_offset` in `target_world`, at its `entry` edge.
func _edge_exit(node_name: String, rect: Rect2, world_id: String, exit_id: String, target_world: String, entry: String, along_offset: float) -> Area2D:
	var area := Area2D.new()
	area.name = node_name
	area.position = rect.get_center()
	area.collision_layer = EXIT_LAYER
	area.collision_mask = EXIT_MASK
	area.monitorable = false
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	area.add_child(shape)
	var exit := Node.new()
	exit.name = "world-exit-script"
	exit.set_script(load(WORLD_EXIT))
	exit.set(&"map_id", world_id)
	exit.set(&"exit_id", exit_id)
	exit.set(&"target_area_id", target_world)
	exit.set(&"entry", entry)
	exit.set(&"keep_along", true)
	exit.set(&"along_offset", along_offset)
	exit.set(&"area", area)
	area.add_child(exit)
	return area


## An instance of the scene at `path` that keeps its own values (only what is set on it is saved).
func _instance(path: String) -> Node2D:
	return (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D


func _label(node_name: String, at: Vector2, size: Vector2, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", 14)
	label.text = text
	return label
