extends SceneTree
## Builds the cliff shapes lab (docs/godot/ELEVATION.md "Storybook art"): right-angled and 45°
## cliffs painted on the world's `elevation` layer (docs/godot/ELEVATION.md), drawn by the elevation
## system with the art cut from the approved H plateau painting
## (scripts/art/build-elevation-art-from-painting.py): the ground layer's metadata picks the
## `storybook-rock` walls and `storybook-grass` lip and foot for its highland ground.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_cliff_shapes_lab.gd [-- --force]
## Writes res://game/scenes/worlds/cliff-shapes-lab.tscn (world.cliff-shapes-lab). It does not
## overwrite an existing lab (where you may have painted) unless given --force. The last row holds
## ramps (docs/godot/ELEVATION.md "Ramps"): walls that taper to nothing beside a slope.

const LAB_PATH := "res://game/scenes/worlds/cliff-shapes-lab.tscn"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CELL := 64
const COLUMNS := 82
const ROWS := 92
const GRASS_SOURCE := 7   # grass-a (highland) in terrain_tileset.tres
const SHEET_CELLS := 19
## The lab's own cliff art for its highland ground (elevation.gd WORLD_WALL_STYLES_META, WORLD_FRINGE_META).
const WALL_STYLES := {"highland": "storybook-rock"}
const FRINGE := {"highland": "storybook-grass"}
## One shape each: name, rectangles painted [x, y, w, h, level] in order (a later one over an
## earlier one), rectangles cut away [x, y, w, h], and optionally ramps [x, y, direction, length,
## width]: the top cell (the first of its run side by side), the way down the slope
## (elevation_tileset.tres row 3), the cells along it and side by side. Levels −3 … 3; a level is one
## stone course.
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
	# Ramps. A Link to the Past: a ramp down beside a 45° face, the wall tapering to the tip.
	["ramp beside a south-west 45° face", [[6, 69, 10, 6, 1]], [[6, 73, 1, 1], [6, 74, 2, 1]], [[6, 74, "se", 2, 1]]],
	["ramp beside a south-east 45° face", [[20, 69, 10, 6, 1]], [[29, 73, 1, 1], [28, 74, 2, 1]], [[29, 74, "sw", 2, 1]]],
	["ramps along a south face, both ends", [[38, 69, 16, 5, 1]], [], [[38, 75, "e", 3, 1], [53, 75, "w", 3, 1]]],
	["two-level ramp along a south face", [[58, 69, 20, 4, 2]], [], [[58, 75, "e", 6, 1]]],
	["ramps leaving a rim: front (two wide) and back", [[4, 81, 12, 4, 1]], [], [[8, 86, "s", 3, 2], [11, 80, "n", 3, 1]]],
	["two-level ramp beside a 45° face", [[22, 79, 12, 9, 2]], [[22, 84, 1, 1], [22, 85, 2, 1], [22, 86, 3, 1], [22, 87, 4, 1]], [[22, 86, "se", 4, 1]]],
]
## Ramp directions in the order of their tiles (elevation_tileset.tres row 3).
const RAMP_DIRECTIONS := ["s", "sw", "w", "nw", "n", "ne", "e", "se"]
const RAMP_STEPS := {
	"s": Vector2i(0, 1), "sw": Vector2i(-1, 1), "w": Vector2i(-1, 0), "nw": Vector2i(-1, -1),
	"n": Vector2i(0, -1), "ne": Vector2i(1, -1), "e": Vector2i(1, 0), "se": Vector2i(1, 1),
}
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
		for ramp: Array in (spec[3] if spec.size() > 3 else []):
			var step: Vector2i = RAMP_STEPS[ramp[2]]
			# Side by side: across the direction (along the other diagonal for a 45° ramp), as
			# elevation.gd groups them.
			var side := Vector2i(1, 0) if step.x == 0 else (Vector2i(0, 1) if step.y == 0 else Vector2i(1, -step.x * step.y))
			var tile := Vector2i(RAMP_DIRECTIONS.find(ramp[2]), 3)
			for w in int(ramp[4]):
				for k in int(ramp[3]):
					elevation.set_cell(Vector2i(ramp[0], ramp[1]) + side * w + step * k, 0, tile)
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
