extends SceneTree
## Builds the level collision lab (game/dev/level-collision/level-collision-lab.tscn,
## world.level-collision-lab; docs/godot/ELEVATION.md "Painting collision"): a cobbled floor
## (level 0) with a raised platform (level 1, north-east) and a pit (level -1, south-west), its
## collision painted by hand on a `level-collision` layer: the platform's rim and the pit's rim
## (orange) hold and drop, the platform's foot and the pit's walls (red) block, a ring round the map
## keeps the slime in. The pit's east rim has a gap on purpose: a level-0 body walks on over the pit
## there (only what is painted collides). tests/test_level_collision.gd plays it. It does not
## overwrite the lab (add -- --force).
##     "<Godot console exe>" --headless --path godot -s res://tools/build_level_collision_lab.gd

const LAB_PATH := "res://game/dev/level-collision/level-collision-lab.tscn"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const LayerScript := preload("res://game/world/elevation/level_collision_layer.gd")
const COLLISION_TILESET := "res://game/world/elevation/level_collision_tileset.tres"
const CELL := 64
const Q := 16
const COLUMNS := 16
const ROWS := 13
const COBBLE := 19
const SHEET_CELLS := 19
## The platform (level 1) and the pit (level -1), in cells.
const PLATFORM := Rect2i(9, 2, 6, 4)
const PIT := Rect2i(2, 7, 5, 4)
## The rows of the pit's east rim left unpainted (quarter cells).
const RIM_GAP := Vector2i(32, 36)
const SPAWN_CELL := Vector2i(8, 9)


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("level collision lab: %s exists; not overwritten (add -- --force)" % LAB_PATH)
		quit(0)
		return
	var root := Node2D.new()
	root.name = "level-collision-lab"
	root.y_sort_enabled = true
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			ground.set_cell(Vector2i(x, y), COBBLE, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_script(load(WORLD_GROUND))
	root.add_child(ground)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.tile_set = load(ELEVATION_TILESET)
	# elevation_tileset.tres: levels −3 … −1 at (0 … 2, 0), 1 … 3 at (3 … 5, 0)
	for y in range(PLATFORM.position.y, PLATFORM.end.y):
		for x in range(PLATFORM.position.x, PLATFORM.end.x):
			elevation.set_cell(Vector2i(x, y), 0, Vector2i(3, 0))
	for y in range(PIT.position.y, PIT.end.y):
		for x in range(PIT.position.x, PIT.end.x):
			elevation.set_cell(Vector2i(x, y), 0, Vector2i(2, 0))
	elevation.set_script(load(ELEVATION_LAYER))
	root.add_child(elevation)
	var collision := TileMapLayer.new()
	collision.name = LayerScript.NODE_NAME
	collision.tile_set = load(COLLISION_TILESET)
	_paint(collision)
	collision.set_script(LayerScript)
	root.add_child(collision)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(SPAWN_CELL) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", "level-collision-lab")
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	root.add_child(definition)
	var marker := Node2D.new()
	marker.name = "player-spawn"
	marker.y_sort_enabled = true
	marker.position = spawn
	root.add_child(marker)
	for child in root.get_children():
		child.owner = root
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAB_PATH.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, LAB_PATH)
	root.free()
	print("level collision lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


## The hand-painted collision, in quarter cells (16 units), as an owner would paint it.
func _paint(layer: TileMapLayer) -> void:
	var per := CELL / Q
	var p := Rect2i(PLATFORM.position * per, PLATFORM.size * per)
	var h := Rect2i(PIT.position * per, PIT.size * per)
	# the platform's rim, on its own edge (level 1): held there, pushing on drops
	_rect(layer, Rect2i(p.position.x, p.end.y - 1, p.size.x, 1), "rim", 1)
	_rect(layer, Rect2i(p.position.x, p.position.y, 1, p.size.y), "rim", 1)
	_rect(layer, Rect2i(p.end.x - 1, p.position.y, 1, p.size.y), "rim", 1)
	_rect(layer, Rect2i(p.position.x, p.position.y, p.size.x, 1), "rim", 1)
	# its face's foot and sides for level 0: one cell of face below the south edge
	_rect(layer, Rect2i(p.position.x - 1, p.end.y + per - 1, p.size.x + 2, 1), "base", 0)
	_rect(layer, Rect2i(p.position.x - 1, p.position.y - 1, 1, p.size.y + per), "base", 0)
	_rect(layer, Rect2i(p.end.x, p.position.y - 1, 1, p.size.y + per), "base", 0)
	_rect(layer, Rect2i(p.position.x, p.position.y - 1, p.size.x, 1), "base", 0)
	# the pit's rim for level 0, round it on the floor (a gap in its east side)
	_rect(layer, Rect2i(h.position.x - 1, h.position.y - 1, h.size.x + 2, 1), "rim", 0)
	_rect(layer, Rect2i(h.position.x - 1, h.end.y, h.size.x + 2, 1), "rim", 0)
	_rect(layer, Rect2i(h.position.x - 1, h.position.y, 1, h.size.y), "rim", 0)
	for y in range(h.position.y, h.end.y):
		if y < RIM_GAP.x or y >= RIM_GAP.y:
			_rect(layer, Rect2i(h.end.x, y, 1, 1), "rim", 0)
	# the pit's walls for level -1: the north face one cell deep, the sides and the south lip
	_rect(layer, Rect2i(h.position.x, h.position.y + per - 1, h.size.x, 1), "base", -1)
	_rect(layer, Rect2i(h.position.x, h.position.y, 1, h.size.y), "base", -1)
	_rect(layer, Rect2i(h.end.x - 1, h.position.y, 1, h.size.y), "base", -1)
	_rect(layer, Rect2i(h.position.x, h.end.y - 1, h.size.x, 1), "base", -1)
	# a ring round the map for level 0
	var w := COLUMNS * per
	var r := ROWS * per
	_rect(layer, Rect2i(0, 0, w, 1), "base", 0)
	_rect(layer, Rect2i(0, r - 1, w, 1), "base", 0)
	_rect(layer, Rect2i(0, 0, 1, r), "base", 0)
	_rect(layer, Rect2i(w - 1, 0, 1, r), "base", 0)


func _rect(layer: TileMapLayer, r: Rect2i, kind: String, level: int) -> void:
	var tile := Vector2i(LayerScript.KINDS.find(kind), level - LayerScript.MIN_LEVEL)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			layer.set_cell(Vector2i(x, y), 0, tile)
