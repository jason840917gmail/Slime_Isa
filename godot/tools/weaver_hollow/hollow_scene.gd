extends RefCounted
## Turns a Weaver Hollow floor (hollow_canvas.gd) into its world scene, laid out like the other
## worlds (docs/godot/CONVENTIONS.md, ELEVATION.md): the root (named after the world, y-sorted,
## with the builder's metadata), the `ground` layer (world_ground.gd), the
## `elevation` layer, the `cliffs` layer, the `world-definition` and the `player-spawn`; and helpers
## for what the floors place: camera rooms, doors, markers, scenes and placed enemies.
##
## Owner: world (dungeons).

const HollowCanvas := preload("res://tools/weaver_hollow/hollow_canvas.gd")

const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const CLIFF_TILESET := "res://game/world/elevation/cliffs/cliff_tileset.tres"
const CLIFF_LAYER := "res://game/world/elevation/cliffs/cliff_layer.gd"
const WEB_TILESET := "res://game/world/webs/web_tileset.tres"
const WEB_LAYER := "res://game/world/webs/web_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const DOOR := "res://game/scripts/door.gd"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const ROOM_ARENAS := "res://game/scripts/room_arenas.gd"
const CELL := 64
## Root metadata: built by tools/build_weaver_hollow.gd (rebuilding overwrites hand edits).
const BUILT_META := &"weaver_hollow_built"
const DUNGEON_META := &"dungeon_id"
const DUNGEON_ID := "weaver-hollow"


static func build(canvas: HollowCanvas, spawn: Vector2) -> Node2D:
	var root := Node2D.new()
	root.name = canvas.world
	root.y_sort_enabled = true
	root.set_meta(BUILT_META, true)
	root.set_meta(DUNGEON_META, DUNGEON_ID)
	root.add_child(_ground(canvas))
	root.add_child(_elevation(canvas))
	if canvas.cliffs.count(-1) < canvas.cliffs.size():
		root.add_child(_cliffs(canvas))
	if canvas.webs.has(1):
		root.add_child(_webs(canvas))
	root.add_child(_definition(canvas, spawn))
	root.add_child(marker("player-spawn", spawn))
	var arenas := Node.new()
	arenas.name = "RoomArenas"
	arenas.set_script(load(ROOM_ARENAS))
	root.add_child(arenas)
	for group_name in ["CameraRooms", "Doors", "Objects", "Scenery", "Enemies", "DarkRooms"]:
		var group := Node2D.new()
		group.name = group_name
		group.y_sort_enabled = group_name in ["Doors", "Objects", "Scenery", "Enemies"]
		root.add_child(group)
	return root


## Gives every node under `node` the owner `root`, except the insides of instanced scenes.
static func own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			own(child, root)


static func _ground(canvas: HollowCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "ground"
	layer.z_index = -2
	layer.tile_set = load(TERRAIN_TILESET)
	for ty in canvas.rows:
		for tx in canvas.cols:
			var source := canvas.ground[canvas.index(tx, ty)]
			if source >= 0:
				layer.set_cell(Vector2i(tx, ty), source, Vector2i(tx % HollowCanvas.SHEET_TILES, ty % HollowCanvas.SHEET_TILES))
	layer.set_meta(&"columns", canvas.cols)
	layer.set_meta(&"rows", canvas.rows)
	layer.set_script(load(WORLD_GROUND))
	return layer


static func _elevation(canvas: HollowCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "elevation"
	layer.z_index = -1
	layer.tile_set = load(ELEVATION_TILESET)
	for ty in canvas.rows:
		for tx in canvas.cols:
			var i := canvas.index(tx, ty)
			var tile := Vector2i(tx, ty)
			if canvas.stairs[i] >= 0:
				layer.set_cell(tile, 0, Vector2i(canvas.stairs[i], HollowCanvas.STAIRS_ROW))
				continue
			var value := canvas.level[i]
			# elevation_tileset.tres: levels -3 ... -1 at (0 ... 2, 0), 1 ... 3 at (3 ... 5, 0).
			if value != 0:
				layer.set_cell(tile, 0, Vector2i(value + 3 if value < 0 else value + 2, 0))
	layer.set_script(load(ELEVATION_LAYER))
	return layer


static func _cliffs(canvas: HollowCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "cliffs"
	layer.z_index = -1
	layer.tile_set = load(CLIFF_TILESET)
	for ty in canvas.rows:
		for tx in canvas.cols:
			var style := canvas.cliffs[canvas.index(tx, ty)]
			if style >= 0:
				layer.set_cell(Vector2i(tx, ty), 0, Vector2i(style, 0))
	layer.set_script(load(CLIFF_LAYER))
	return layer


## The floor webs (game/world/webs/web_layer.gd, docs/godot/WEBS.md): every painted cell the auto web.
static func _webs(canvas: HollowCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "webs"
	layer.z_index = -1
	layer.tile_set = load(WEB_TILESET)
	for ty in canvas.rows:
		for tx in canvas.cols:
			if canvas.webs[canvas.index(tx, ty)] == 1:
				layer.set_cell(Vector2i(tx, ty), 0, Vector2i(0, 0))
	layer.set_script(load(WEB_LAYER))
	return layer


static func _definition(canvas: HollowCanvas, spawn: Vector2) -> Node:
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	definition.set(&"map_id", canvas.world)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", canvas.cols)
	definition.set(&"rows", canvas.rows)
	definition.set(&"camera_mode", "follow")
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": roundi(spawn.x), "y": roundi(spawn.y)},
			"entries": {}}})
	return definition


static func marker(marker_name: String, position: Vector2) -> Node2D:
	var node := Node2D.new()
	node.name = marker_name
	node.y_sort_enabled = true
	node.position = position
	return node


## A camera room over the room at room cell (x, y), w x h rooms.
static func camera_room(root: Node2D, room_name: String, x: int, y: int, w: int = 1, h: int = 1) -> Node2D:
	var rect := HollowCanvas.room_world_rect(x, y, w, h, CELL)
	var room := Node2D.new()
	room.name = room_name
	room.set_script(load(CAMERA_ROOM))
	room.position = rect.position
	room.set(&"size", rect.size)
	root.get_node("CameraRooms").add_child(room)
	return room


## A door (game/scripts/door.gd) at `position` (world units): its trigger `trigger` around it.
static func door(root: Node2D, node_name: String, position: Vector2, settings: Dictionary) -> Node2D:
	var holder := Node2D.new()
	holder.name = node_name
	holder.y_sort_enabled = true
	holder.position = position
	var script_node := Node.new()
	script_node.name = "DoorScript"
	script_node.set_script(load(DOOR))
	script_node.set(&"map_id", str(root.name))
	for key: String in settings:
		script_node.set(StringName(key), settings[key])
	holder.add_child(script_node)
	root.get_node("Doors").add_child(holder)
	return holder


## An instance of `scene_path` under `group` at `position`, its properties `props` set on its root
## (or on the node path before ":" for "Child:prop" keys).
static func place(root: Node2D, group: String, node_name: String, scene_path: String, position: Vector2,
		props: Dictionary = {}) -> Node2D:
	var instance := (load(scene_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	instance.name = node_name
	instance.position = position
	var persistence := "%s.%s" % [str(root.name), node_name]
	instance.set_meta(&"instance_id", "%s-%s" % [str(root.name), node_name])
	instance.set_meta(&"persistence_key", persistence)
	var children_set := false
	for key: String in props:
		var target: Node = instance
		var property := key
		if key.contains(":"):
			target = instance.get_node(key.get_slice(":", 0))
			property = key.get_slice(":", 1)
			children_set = true
		target.set(StringName(property), props[key])
	root.get_node(group).add_child(instance)
	if children_set:
		root.set_editable_instance(instance, true)
	return instance


## Lets the scene keep what was set on the insides of `instance` (a chest's ChestScript, a ladder's
## DoorScript): an editable instance.
static func editable(root: Node2D, instance: Node) -> void:
	root.set_editable_instance(instance, true)


## A placed enemy (game/enemy/placed_enemy.gd) of `enemy_type` with its own wander circle.
static func enemy(root: Node2D, node_name: String, enemy_type: String, position: Vector2, radius: float = 160.0,
		overrides: Dictionary = {}) -> Node2D:
	var instance := (load(PLACED_ENEMY) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	instance.name = node_name
	instance.position = position
	instance.set(&"enemy_type", enemy_type)
	instance.set(&"wander_radius", radius)
	instance.set(&"overrides", overrides)
	root.get_node("Enemies").add_child(instance)
	return instance


## Cell (x, y)'s top-left corner, centre or a point in cell units, in world units.
static func at(x: float, y: float) -> Vector2:
	return Vector2(x * CELL, y * CELL)
