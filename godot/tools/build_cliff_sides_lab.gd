extends SceneTree
## Builds the cliff sides lab (docs/godot/ELEVATION.md "Side walls"): cliffs painted on the world's
## `elevation` layer and drawn with walls on every side (the ground layer's metadata `cliff_look` =
## "sides"), in the storybook art cut from the approved H plateau painting.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_cliff_sides_lab.gd [-- --force]
## Writes res://game/scenes/worlds/cliff-sides-lab.tscn (world.cliff-sides-lab). It does not
## overwrite an existing lab (where you may have painted) unless given --force.

const LAB_PATH := "res://game/scenes/worlds/cliff-sides-lab.tscn"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CELL := 64
const COLUMNS := 70
const ROWS := 82
const GRASS_SOURCE := 7   # grass-a (highland) in terrain_tileset.tres
## Terrain tile set sources of the other grounds (terrain_tileset.tres, as
## scripts/maps/build-elevation-park.py names them).
const SNOW := 6
const SAND := 10
const FOREST_FLOOR := 4
const FOREST_MOSS := 5
const AMBERLEAF := 0
const CAVERN := 1
const CRYSTAL := 2
const COBBLE := 19
const WATER := 11
## The grounds row (rows 52-80): a level-2 plateau per block, with a step cut at its front left (an
## inner corner) — [name, ground on top, ground around it], in rows of GROUND_BLOCKS_PER_ROW
## blocks GROUND_BLOCK cells wide. Each top takes its ground's own wall style (elevation.gd
## GROUND_WALL_STYLES; grass takes the lab's storybook rock).
const GROUND_BLOCKS := [
	["snow", SNOW, SNOW], ["sand", SAND, SAND], ["forest floor", FOREST_FLOOR, FOREST_FLOOR],
	["forest moss", FOREST_MOSS, FOREST_MOSS], ["fallen leaves", AMBERLEAF, AMBERLEAF], ["cavern", CAVERN, CAVERN],
	["crystal", CRYSTAL, CRYSTAL], ["cobble", COBBLE, COBBLE], ["grass on sand", GRASS_SOURCE, SAND],
	["sand on grass", SAND, GRASS_SOURCE], ["snow on grass", SNOW, GRASS_SOURCE], ["grass in water", GRASS_SOURCE, WATER],
]
const GROUND_BLOCKS_PER_ROW := 6
const GROUND_BLOCK := 11
const GROUND_ROWS_AT := [54, 68]
const SHEET_CELLS := 19
## The lab's cliff art and look for its highland ground (elevation.gd WORLD_WALL_STYLES_META,
## WORLD_FRINGE_META, WORLD_CLIFF_LOOK_META).
const WALL_STYLES := {"highland": "storybook-rock"}
const FRINGE := {"highland": "storybook-grass"}
const LOOK := "sides"
## One shape each: name, rectangles painted [x, y, w, h, level] in order (a later one over an
## earlier one), rectangles cut away [x, y, w, h], ramps [x, y, direction, length, width] and
## stairs [x, y, direction, width] (elevation_tileset.tres rows 3 and 1; the arrow points down).
const SHAPES := [
	# The owner's reference (2026-10-13): a notch in the top-right corner, a step at the bottom left.
	["reference", [[2, 3, 13, 10, 1]], [[11, 3, 4, 2], [2, 10, 4, 3]]],
	["block 1", [[18, 4, 8, 6, 1]], [], [], [[21, 10, "s", 2]]],
	["block 2", [[29, 4, 8, 6, 2]], []],
	["block 3", [[40, 4, 8, 6, 3]], []],
	["L 2", [[51, 3, 5, 9, 2], [51, 8, 13, 4, 2]], []],
	["U from the north", [[2, 18, 12, 9, 2]], [[6, 18, 4, 5]]],
	["U from the south", [[17, 18, 12, 8, 2]], [[21, 23, 4, 3]]],
	["octagon", [[32, 18, 12, 8, 2]], [[32, 18, 2, 1], [32, 19, 1, 1], [42, 18, 2, 1], [43, 19, 1, 1],
			[32, 25, 2, 1], [32, 24, 1, 1], [42, 25, 2, 1], [43, 24, 1, 1]]],
	["terrace 1-2-3", [[48, 17, 19, 14, 1], [51, 19, 13, 9, 2], [54, 20, 7, 4, 3]], []],
	["hole", [[3, 37, 10, 6, -1]], []],
	# The owner's open cliff (cliff-shapes-lab): a level-2 U of single cells whose 45° arms open
	# into the ground through ramps along their feet.
	["open U", [[17, 38, 1, 1, 2], [18, 39, 1, 1, 2], [19, 40, 10, 1, 2], [29, 39, 1, 1, 2], [30, 38, 1, 1, 2]], [],
			[[17, 41, "se", 2, 1], [30, 41, "sw", 2, 1]]],
	["ramps along a south face", [[35, 37, 14, 4, 1]], [], [[35, 42, "e", 3, 1], [48, 42, "w", 3, 1]]],
	["diamond", [[54, 37, 4, 1, 2], [53, 38, 6, 1, 2], [52, 39, 8, 1, 2], [53, 40, 6, 1, 2], [54, 41, 4, 1, 2]], []],
]
const DIRECTIONS := ["s", "sw", "w", "nw", "n", "ne", "e", "se"]
const STEPS := {
	"s": Vector2i(0, 1), "sw": Vector2i(-1, 1), "w": Vector2i(-1, 0), "nw": Vector2i(-1, -1),
	"n": Vector2i(0, -1), "ne": Vector2i(1, -1), "e": Vector2i(1, 0), "se": Vector2i(1, 1),
}
const SPAWN_CELL := Vector2i(16, 15)


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("cliff sides lab: %s exists; not overwritten (add -- --force to rebuild it)" % LAB_PATH)
		quit(0)
		return
	var root := Node2D.new()
	root.name = "cliff-sides-lab"
	root.y_sort_enabled = true
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	var grounds := _ground_blocks()
	for y in ROWS:
		for x in COLUMNS:
			var source := int(grounds.get(Vector2i(x, y), GRASS_SOURCE))
			ground.set_cell(Vector2i(x, y), source, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_meta(&"cliff_wall_styles", WALL_STYLES)
	ground.set_meta(&"cliff_fringe", FRINGE)
	ground.set_meta(&"cliff_look", LOOK)
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
			var step: Vector2i = STEPS[ramp[2]]
			# Side by side: across the direction (along the other diagonal for a 45° ramp), as
			# elevation.gd groups them.
			var side := Vector2i(1, 0) if step.x == 0 else (Vector2i(0, 1) if step.y == 0 else Vector2i(1, -step.x * step.y))
			var tile := Vector2i(DIRECTIONS.find(ramp[2]), 3)
			for w in int(ramp[4]):
				for k in int(ramp[3]):
					elevation.set_cell(Vector2i(ramp[0], ramp[1]) + side * w + step * k, 0, tile)
		for flight: Array in (spec[4] if spec.size() > 4 else []):
			var step: Vector2i = STEPS[flight[2]]
			var side := Vector2i(1, 0) if step.x == 0 else Vector2i(0, 1)
			for w in int(flight[3]):
				elevation.set_cell(Vector2i(flight[0], flight[1]) + side * w, 0, Vector2i(DIRECTIONS.find(flight[2]), 1))
	# The grounds row: a level-2 plateau per block (elevation_tileset.tres: level 2 at (4, 0)).
	for i in GROUND_BLOCKS.size():
		var origin := _block_origin(i)
		for y in range(origin.y, origin.y + 4):
			for x in range(origin.x + 1, origin.x + 7):
				if y == origin.y + 3 and x < origin.x + 3:
					continue
				elevation.set_cell(Vector2i(x, y), 0, Vector2i(4, 0))
	elevation.set_script(load(ELEVATION_LAYER))
	root.add_child(elevation)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(SPAWN_CELL) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", "cliff-sides-lab")
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
	print("cliff sides lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


## The top-left cell of grounds block `i`'s plateau.
func _block_origin(i: int) -> Vector2i:
	return Vector2i(2 + (i % GROUND_BLOCKS_PER_ROW) * GROUND_BLOCK, int(GROUND_ROWS_AT[i / GROUND_BLOCKS_PER_ROW]))


## Cell -> terrain source of the grounds row: each block's ground around its plateau, its top's on it.
func _ground_blocks() -> Dictionary:
	var out := {}
	for i in GROUND_BLOCKS.size():
		var block: Array = GROUND_BLOCKS[i]
		var origin := _block_origin(i)
		for y in range(origin.y - 2, origin.y + 9):
			for x in range(origin.x - 1, origin.x + 9):
				out[Vector2i(x, y)] = int(block[2])
		for y in range(origin.y, origin.y + 4):
			for x in range(origin.x + 1, origin.x + 7):
				out[Vector2i(x, y)] = int(block[1])
	return out
