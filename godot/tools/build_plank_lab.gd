extends SceneTree
## Builds the plank lab (docs/godot/DUNGEONS.md "Falling planks over water"): a small dev world of
## its own (not a playground corner), a lake with two plank bridges to an island and the heart
## chests on it, so the owner and the map builders can try them.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_plank_lab.gd [-- --force]
## Writes res://game/dev/planks/playground-planks.tscn (world.playground-planks; launch it with
## `?map=playground-planks` or `-- --map=playground-planks`: a `playground-` world, so it plays in
## the body-shapes mode like the playground unless `classic` is given). It does not overwrite an
## existing lab unless given --force. No elevation (nothing to bake).
##
## 24 x 16 cells of grass; deep water rows 4-11 (the lake), the island north of it (rows 0-3):
##   - the long bridge (x 5): eight falling planks and no landing: only a continuous Roll crosses
##     (the classic Roll held; in the body-shapes mode the charged Roll, the `roll-charge` upgrade);
##   - the stepped bridge (x 12): two planks, a landing, two planks, a landing, two planks: one
##     quick Roll a stretch, as a slab bridge;
##   - on the island: a world chest with only a Goo Heart (no window), a world chest with a heart
##     and wood (the window shows the wood), a dungeon chest with only a heart.
## Each bridge has a water hazard over its lane with a return point on each bank.

const LAB_PATH := "res://game/dev/planks/playground-planks.tscn"
const MAP_ID := "playground-planks"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const KIT := "res://game/scenes/objects/dungeon/"
const WORLD_CHEST := "res://game/scenes/objects/chest-wooden.tscn"
const CELL := 64
const COLUMNS := 24
const ROWS := 16
const SHEET_CELLS := 19
## terrain_tileset.tres sources: deep-water 3, grass-a 7.
const DEEP_WATER := 3
const GRASS := 7
const LAKE_TOP := 4
const LAKE_BOTTOM := 11
const LONG_X := 5
const STEPPED_X := 12
## The stepped bridge's landings (rows).
const LANDINGS := [9, 6]
const SPAWN := Vector2(8.5, 13.5)

var _root: Node2D


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("plank lab: %s exists; not overwritten (add -- --force to rebuild it)" % LAB_PATH)
		quit(0)
		return
	_root = Node2D.new()
	_root.name = MAP_ID
	_root.y_sort_enabled = true
	_paint()
	_place()
	for child in _root.get_children():
		_own(child)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAB_PATH.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, LAB_PATH)
	_root.free()
	print("plank lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


func _own(node: Node) -> void:
	node.owner = _root
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_own(child)


func _at(cells: Vector2) -> Vector2:
	return cells * CELL


func _paint() -> void:
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			var water := y >= LAKE_TOP and y <= LAKE_BOTTOM
			ground.set_cell(Vector2i(x, y), DEEP_WATER if water else GRASS, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_script(load(WORLD_GROUND))
	_root.add_child(ground)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := _at(SPAWN)
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	_root.add_child(definition)
	var marker := Node2D.new()
	marker.name = "player-spawn"
	marker.position = spawn
	_root.add_child(marker)


func _kit(scene: String, name: String, at: Vector2, props: Dictionary = {}) -> Node2D:
	var node := (load(KIT + scene + ".tscn") as PackedScene).instantiate() as Node2D
	node.name = name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	_root.add_child(node)
	return node


## A water hazard over the lane of column `x` (the lake's rows), a return point on each bank.
func _lane_hazard(name: String, x: int) -> void:
	var hazard := _kit("hazard", name, _at(Vector2(x, LAKE_TOP)), {"kind": "water",
		"size": Vector2(1, LAKE_BOTTOM - LAKE_TOP + 1) * CELL})
	for side: String in ["South", "North"]:
		var back := Node2D.new()
		back.name = "Return" + side
		var row := LAKE_BOTTOM + 1.6 if side == "South" else LAKE_TOP - 0.6
		back.position = _at(Vector2(x + 0.5, row)) - hazard.position
		hazard.add_child(back)
		back.owner = _root


func _chest(scene: String, name: String, at: Vector2, heart: String, contents: Dictionary) -> void:
	var chest := (load(scene) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	chest.name = name
	chest.position = at
	_root.add_child(chest)
	_root.set_editable_instance(chest, true)
	var script_node := chest.get_node("ChestScript")
	script_node.set(&"map_id", MAP_ID)
	script_node.set(&"instance_id", name)
	script_node.set(&"initial_contents", contents)
	script_node.set(&"goo_heart_id", heart)


func _place() -> void:
	# The hazards first: decks draw over them.
	_lane_hazard("long-water", LONG_X)
	_lane_hazard("stepped-water", STEPPED_X)
	for y in range(LAKE_TOP, LAKE_BOTTOM + 1):
		_kit("falling-plank", "long-plank-%d" % y, _at(Vector2(LONG_X, y)))
		if LANDINGS.has(y):
			_kit("plank-landing", "stepped-landing-%d" % y, _at(Vector2(STEPPED_X, y)))
		else:
			_kit("falling-plank", "stepped-plank-%d" % y, _at(Vector2(STEPPED_X, y)))
	_chest(WORLD_CHEST, "heart-chest", _at(Vector2(8, 3.2)), "plank-lab-heart", {})
	_chest(WORLD_CHEST, "heart-wood-chest", _at(Vector2(10.5, 3.2)), "plank-lab-heart-2", {"wood": 3})
	_chest(KIT + "dungeon-chest.tscn", "heart-dungeon-chest", _at(Vector2(15, 3.2)), "plank-lab-heart-3", {})
