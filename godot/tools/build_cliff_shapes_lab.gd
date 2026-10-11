extends SceneTree
## Builds the cliff shapes lab (docs/godot/CLIFFS.md "Painted elevation"): right-angled and 45°
## cliffs painted on the world's `elevation` layer (docs/godot/ELEVATION.md), drawn by the elevation
## system with the art cut from the approved H plateau painting
## (scripts/art/build-elevation-art-from-painting.py): the ground layer's metadata picks the
## `storybook-rock` walls and `storybook-grass` lip and foot for its highland ground.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_cliff_shapes_lab.gd [-- --force]
## Writes res://game/scenes/worlds/cliff-shapes-lab.tscn (world.cliff-shapes-lab). It does not
## overwrite an existing lab (where you may have painted) unless given --force.

const LAB_PATH := "res://game/scenes/worlds/cliff-shapes-lab.tscn"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CELL := 64
const COLUMNS := 82
const ROWS := 66
const GRASS_SOURCE := 7   # grass-a (highland) in terrain_tileset.tres
const SHEET_CELLS := 19
## The lab's own cliff art for its highland ground (elevation.gd WORLD_WALL_STYLES_META, WORLD_FRINGE_META).
const WALL_STYLES := {"highland": "storybook-rock"}
const FRINGE := {"highland": "storybook-grass"}
## One shape each: name, rectangles painted [x, y, w, h, level] in order (a later one over an
## earlier one), rectangles cut away [x, y, w, h]. Levels −3 … 3; a level is one stone course.
const SHAPES := [
	["L", [[2, 2, 5, 11, 2], [2, 9, 14, 4, 2]], []],
	["T", [[20, 2, 16, 4, 2], [25, 6, 6, 7, 2]], []],
	["plus", [[44, 2, 6, 11, 2], [39, 5, 16, 4, 2]], []],
	["U (notch from the north)", [[58, 2, 14, 11, 2]], [[63, 2, 4, 6]]],
	["U (notch from the south)", [[2, 19, 14, 11, 2]], [[7, 25, 4, 5]]],
	["joined rectangles", [[20, 19, 12, 8, 2], [26, 23, 12, 7, 2]], []],
	["terrace levels 1-2-3", [[42, 19, 28, 21, 1], [46, 22, 20, 12, 2], [50, 24, 12, 5, 3]], []],
	["octagon", [[4, 34, 14, 9, 2]], [[4, 34, 2, 1], [4, 35, 1, 1], [16, 34, 2, 1], [17, 35, 1, 1],
			[4, 42, 2, 1], [4, 41, 1, 1], [16, 42, 2, 1], [17, 41, 1, 1]]],
	["hole", [[23, 35, 10, 6, -1]], []],
	["wall 1 level", [[2, 49, 10, 6, 1]], []],
	["wall 2 levels", [[16, 49, 10, 6, 2]], []],
	["wall 3 levels", [[30, 49, 10, 6, 3]], []],
	["terrace with a flush front", [[44, 49, 20, 10, 1], [48, 51, 12, 8, 3]], []],
]
const SPAWN_CELL := Vector2i(40, 45)


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("cliff shapes lab: %s exists; not overwritten (add -- --force to rebuild it)" % LAB_PATH)
		quit(0)
		return
	var root := Node2D.new()
	root.name = "cliff-shapes-lab"
	root.y_sort_enabled = true
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			ground.set_cell(Vector2i(x, y), GRASS_SOURCE, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_meta(&"cliff_wall_styles", WALL_STYLES)
	ground.set_meta(&"cliff_fringe", FRINGE)
	ground.set_script(load(WORLD_GROUND))
	root.add_child(ground)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.tile_set = load(ELEVATION_TILESET)
	for spec: Array in SHAPES:
		var cut := {}
		for r: Array in spec[2]:
			for y in range(r[1], r[1] + r[3]):
				for x in range(r[0], r[0] + r[2]):
					cut[Vector2i(x, y)] = true
		for r: Array in spec[1]:
			var level := int(r[4])
			# elevation_tileset.tres: levels −3 … −1 at (0 … 2, 0), 1 … 3 at (3 … 5, 0).
			var tile := Vector2i(level + 3 if level < 0 else level + 2, 0)
			for y in range(r[1], r[1] + r[3]):
				for x in range(r[0], r[0] + r[2]):
					if not cut.has(Vector2i(x, y)):
						elevation.set_cell(Vector2i(x, y), 0, tile)
	elevation.set_script(load(ELEVATION_LAYER))
	root.add_child(elevation)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(SPAWN_CELL) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", "cliff-shapes-lab")
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
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, LAB_PATH)
	root.free()
	print("cliff shapes lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)
