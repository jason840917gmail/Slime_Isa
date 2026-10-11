extends RefCounted
## Turns a placeholder region's canvas (region_canvas.gd) into its world scene, laid out like the
## other worlds (docs/godot/CONVENTIONS.md, ELEVATION.md, FORESTS.md, FENCES.md): the root (named
## after the world, y-sorted, with the placeholder metadata), the `ground` layer (world_ground.gd),
## the `forest` ForestLayer, the `elevation` layer (levels and stairs), the `fences` layer when it
## has fences, the `world-definition`, the `player-spawn`, `player-entry-<edge>` and
## `arrive-from-<world>-<n>` markers, one Area2D exit per opening (world_exit.gd), the `props` and
## the `notes` (MapNote).
##
## Owner: world (atlas).

const RegionCanvas := preload("res://tools/region_worlds/region_canvas.gd")

const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const FOREST_TILESET := "res://game/world/forest/forest_tileset.tres"
const FOREST_LAYER := "res://game/world/forest/forest_layer.gd"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const FENCE_TILESET := "res://game/world/elevation/fences/fence_tileset.tres"
const FENCE_LAYER := "res://game/world/elevation/fences/fence_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const WORLD_EXIT := "res://game/scripts/world_exit.gd"
const MAP_NOTE := "res://game/world/atlas/map_note.gd"
## Root metadata: built by the tool and safe to rebuild; the region key; the layout it was built
## from (world_map_data.gd `layout_hash`), so the atlas can tell a stale placeholder.
const PLACEHOLDER_META := &"world_map_placeholder"
const REGION_META := &"world_map_region"
const LAYOUT_META := &"world_map_layout_hash"
## World exits (as in every world): on the trigger layer, seeing the player and npc layers.
const EXIT_LAYER := 512
const EXIT_MASK := 130


## The scene's root, every node owned by it.
static func build(canvas: RegionCanvas, layout_hash: int) -> Node2D:
	var root := Node2D.new()
	root.name = canvas.world
	root.y_sort_enabled = true
	root.set_meta(PLACEHOLDER_META, true)
	root.set_meta(REGION_META, canvas.key)
	root.set_meta(LAYOUT_META, layout_hash)
	root.add_child(_ground(canvas))
	root.add_child(_forest(canvas))
	root.add_child(_elevation(canvas))
	if canvas.fences.has(1):
		root.add_child(_fences(canvas))
	root.add_child(_definition(canvas))
	root.add_child(_marker("player-spawn", canvas.spawn))
	for edge: String in canvas.entries:
		root.add_child(_marker("player-entry-" + edge, canvas.entries[edge]))
	for arrival in canvas.arrivals:
		root.add_child(_marker(arrival["name"], arrival["position"]))
	var exits: Array[Area2D] = []
	for exit in canvas.exits:
		var area := _exit(canvas, exit)
		root.add_child(area)
		exits.append(area)
	var props := Node2D.new()
	props.name = "props"
	props.y_sort_enabled = true
	root.add_child(props)
	for prop in canvas.props:
		var instance := (load(prop["scene"]) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		instance.name = prop["name"]
		instance.position = prop["position"]
		props.add_child(instance)
	var notes := Node2D.new()
	notes.name = "notes"
	root.add_child(notes)
	for note in canvas.notes:
		var node := Node2D.new()
		node.set_script(load(MAP_NOTE))
		node.name = "%s-%s" % [note["kind"], _slug(note["label"])]
		node.position = note["position"]
		node.set(&"kind", note["kind"])
		node.set(&"label", note["label"])
		node.set(&"notes", note["notes"])
		notes.add_child(node, true)
	_own(root, root)
	for area in exits:
		var script_node := area.get_node(^"world-exit-script")
		area.body_entered.connect(Callable(script_node, &"on_body_entered"), Object.CONNECT_PERSIST)
	return root


## Packs `root` (and frees it) into `path`.
static func save(root: Node2D, path: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	return err


static func _ground(canvas: RegionCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "ground"
	layer.z_index = -2
	layer.tile_set = load(TERRAIN_TILESET)
	for ty in canvas.size.y:
		for tx in canvas.size.x:
			var source := canvas.ground[ty * canvas.size.x + tx]
			if source >= 0:
				layer.set_cell(Vector2i(tx, ty), source, Vector2i(tx % RegionCanvas.SHEET_TILES, ty % RegionCanvas.SHEET_TILES))
	layer.set_meta(&"columns", canvas.size.x)
	layer.set_meta(&"rows", canvas.size.y)
	layer.set_script(load(WORLD_GROUND))
	return layer


static func _forest(canvas: RegionCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "forest"
	layer.y_sort_enabled = true
	layer.tile_set = load(FOREST_TILESET)
	for ty in canvas.size.y:
		for tx in canvas.size.x:
			var mix := canvas.trees[ty * canvas.size.x + tx]
			if mix >= 0:
				layer.set_cell(Vector2i(tx, ty), 0, Vector2i(mix, 0))
	layer.set_script(load(FOREST_LAYER))
	return layer


static func _elevation(canvas: RegionCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "elevation"
	layer.z_index = -1
	layer.tile_set = load(ELEVATION_TILESET)
	for ty in canvas.size.y:
		for tx in canvas.size.x:
			var index := ty * canvas.size.x + tx
			var tile := Vector2i(tx, ty)
			if canvas.stairs[index] >= 0:
				layer.set_cell(tile, 0, Vector2i(canvas.stairs[index], RegionCanvas.STAIRS_ROW))
				continue
			var level := canvas.level[index]
			# elevation_tileset.tres: levels -3 ... -1 at (0 ... 2, 0), 1 ... 3 at (3 ... 5, 0).
			if level != 0:
				layer.set_cell(tile, 0, Vector2i(level + 3 if level < 0 else level + 2, 0))
	layer.set_script(load(ELEVATION_LAYER))
	return layer


static func _fences(canvas: RegionCanvas) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "fences"
	layer.z_index = -1
	layer.tile_set = load(FENCE_TILESET)
	for ty in canvas.size.y:
		for tx in canvas.size.x:
			if canvas.fences[ty * canvas.size.x + tx] == 1:
				layer.set_cell(Vector2i(tx, ty), 0, RegionCanvas.FENCE_STONE)
	layer.set_script(load(FENCE_LAYER))
	return layer


static func _definition(canvas: RegionCanvas) -> Node:
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var entries := {}
	for edge: String in canvas.entries:
		entries[edge] = _point(canvas.entries[edge])
	definition.set(&"map_id", canvas.world)
	definition.set(&"tile_size", canvas.tile_size)
	definition.set(&"columns", canvas.size.x)
	definition.set(&"rows", canvas.size.y)
	definition.set(&"camera_mode", "follow")
	definition.set(&"metadata", {"objects": [], "player": {"spawn": _point(canvas.spawn), "entries": entries}})
	return definition


static func _marker(marker_name: String, position: Vector2) -> Node2D:
	var marker := Node2D.new()
	marker.name = marker_name
	marker.y_sort_enabled = true
	marker.position = position
	return marker


static func _exit(canvas: RegionCanvas, exit: Dictionary) -> Area2D:
	var rect: Rect2 = exit["rect"]
	var area := Area2D.new()
	area.name = exit["name"]
	area.position = rect.get_center()
	area.collision_layer = EXIT_LAYER
	area.collision_mask = EXIT_MASK
	area.monitorable = false
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	box.size = rect.size
	box.resource_scene_unique_id = "shape_" + str(area.name).replace("-", "_")
	shape.shape = box
	area.add_child(shape)
	var script_node := Node.new()
	script_node.name = "world-exit-script"
	script_node.set_script(load(WORLD_EXIT))
	script_node.set(&"map_id", canvas.world)
	script_node.set(&"exit_id", exit["exit_id"])
	script_node.set(&"target_area_id", exit["target"])
	script_node.set(&"entry", exit["entry"])
	script_node.set(&"entry_marker", exit["entry_marker"])
	script_node.set(&"area", area)
	script_node.set(&"gate", {})
	area.add_child(script_node)
	return area


static func _point(position: Vector2) -> Dictionary:
	return {"x": roundi(position.x), "y": roundi(position.y)}


static func _slug(text: String) -> String:
	var out := ""
	for character in text.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			out += character
		elif not out.ends_with("-") and out != "":
			out += "-"
	return out.trim_suffix("-") if out != "" else "note"


## Gives every node under `node` the owner `root`, except the insides of instanced scenes.
static func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			_own(child, root)
