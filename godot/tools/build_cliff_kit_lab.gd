extends SceneTree
## Builds the cliff builder lab (docs/godot/CLIFFS.md "Cliff builder"):
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_cliff_kit_lab.gd
## Writes res://game/scenes/worlds/cliff-kit-lab.tscn (world.cliff-kit-lab): a grass field with
## cliff builders of several sizes from both kits. Rebuilding overwrites the lab.

const LAB_PATH := "res://game/scenes/worlds/cliff-kit-lab.tscn"
const BUILDER := "res://game/world/cliffs/cliff_builder.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CELL := 64
const COLUMNS := 76
const ROWS := 124
const GRASS_SOURCE := 7   # grass-a in terrain_tileset.tres
const SHEET_CELLS := 19
## name, kit, cell position, size in cells, variation
const CLIFFS := [
	["plateau smallest", "plateau", Vector2i(2, 2), Vector2i(12, 14), 0],
	["plateau 20 x 16", "plateau", Vector2i(16, 2), Vector2i(20, 16), 1],
	["plateau long 34 x 14", "plateau", Vector2i(38, 2), Vector2i(34, 14), 2],
	["dip smallest", "dip", Vector2i(2, 22), Vector2i(12, 12), 0],
	["dip 18 x 18", "dip", Vector2i(16, 22), Vector2i(18, 18), 1],
	["dip wide 30 x 14", "dip", Vector2i(38, 22), Vector2i(30, 14), 2],
]
const SPAWN_CELL := Vector2i(36, 19)
const SHAPE := "res://game/world/cliffs/cliff_shape.gd"
const PAINT_TILESET := "res://game/world/cliffs/cliff_paint_tileset.tres"
## Painted shapes for the cliff-shape node: rectangles [x, y, w, h] added, then cut away.
const SHAPE_ADD := [
	[2, 44, 6, 6],                    # square
	[10, 44, 14, 4],                  # rectangle
	[27, 44, 4, 10], [27, 50, 10, 4], # L
	[40, 44, 14, 10],                 # U (notch cut from the north)
	[57, 44, 14, 10],                 # upside-down U (notch cut from the south)
]
const SHAPE_CUT := [[44, 44, 6, 6], [61, 49, 6, 5]]
## Octagons [x, y, w, h, corner steps] and diamonds [centre x, centre y, radius], painted as
## staircases of single-cell steps (45 degrees).
const SHAPE_OCTAGONS := [[2, 64, 12, 10, 3], [17, 64, 20, 12, 4]]
const SHAPE_DIAMONDS := [[46, 70, 6]]
## A terrace in one node: [x, y, w, h, level], painted in order (later ones over earlier ones).
const TERRACE := [[2, 103, 30, 16, 2], [6, 105, 20, 7, 4], [10, 107, 10, 2, 6]]
## Wall heights: [x, y, w, h, painted level], each its own cliff shape node.
const HEIGHTS := [[2, 84, 10, 5, 1], [16, 84, 10, 5, 2], [30, 84, 10, 5, 3], [44, 84, 10, 5, 5]]


func _initialize() -> void:
	var root := Node2D.new()
	root.name = "cliff-kit-lab"
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
	ground.set_script(load(WORLD_GROUND))
	root.add_child(ground)
	for spec: Array in CLIFFS:
		var builder := Node2D.new()
		builder.name = spec[0]
		builder.z_index = -1
		builder.set_script(load(BUILDER))
		builder.position = Vector2(spec[2]) * CELL
		builder.set(&"kit", spec[1])
		builder.set(&"width_cells", (spec[3] as Vector2i).x)
		builder.set(&"height_cells", (spec[3] as Vector2i).y)
		builder.set(&"variation", spec[4])
		root.add_child(builder)
	var shape := Node2D.new()
	shape.name = "cliff shapes"
	shape.z_index = -1
	shape.set_script(load(SHAPE))
	root.add_child(shape)
	var paint := TileMapLayer.new()
	paint.name = "paint"
	paint.tile_set = load(PAINT_TILESET)
	var cut := {}
	for r: Array in SHAPE_CUT:
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				cut[Vector2i(x, y)] = true
	for r: Array in SHAPE_ADD:
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				if not cut.has(Vector2i(x, y)):
					paint.set_cell(Vector2i(x, y), 0, Vector2i(1, 0))
	for o: Array in SHAPE_OCTAGONS:
		for y in range(o[1], o[1] + o[3]):
			for x in range(o[0], o[0] + o[2]):
				var dx := mini(x - o[0], o[0] + o[2] - 1 - x)
				var dy := mini(y - o[1], o[1] + o[3] - 1 - y)
				if dx + dy >= o[4]:
					paint.set_cell(Vector2i(x, y), 0, Vector2i(1, 0))
	for d: Array in SHAPE_DIAMONDS:
		for y in range(d[1] - d[2], d[1] + d[2] + 1):
			for x in range(d[0] - d[2], d[0] + d[2] + 1):
				if absi(x - d[0]) + absi(y - d[1]) <= d[2]:
					paint.set_cell(Vector2i(x, y), 0, Vector2i(1, 0))
	shape.add_child(paint)
	for h: Array in HEIGHTS:
		var tall := Node2D.new()
		tall.name = "level %d wall" % h[4]
		tall.z_index = -1
		tall.set_script(load(SHAPE))
		root.add_child(tall)
		var cells := TileMapLayer.new()
		cells.name = "paint"
		cells.tile_set = load(PAINT_TILESET)
		for y in range(h[1], h[1] + h[3]):
			for x in range(h[0], h[0] + h[2]):
				cells.set_cell(Vector2i(x, y), 0, Vector2i(int(h[4]) - 1, 0))
		tall.add_child(cells)
	var terrace := Node2D.new()
	terrace.name = "terrace levels 2-4-6"
	terrace.z_index = -1
	terrace.set_script(load(SHAPE))
	root.add_child(terrace)
	var steps := TileMapLayer.new()
	steps.name = "paint"
	steps.tile_set = load(PAINT_TILESET)
	for t: Array in TERRACE:
		for y in range(t[1], t[1] + t[3]):
			for x in range(t[0], t[0] + t[2]):
				steps.set_cell(Vector2i(x, y), 0, Vector2i(int(t[4]) - 1, 0))
	terrace.add_child(steps)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(SPAWN_CELL) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", "cliff-kit-lab")
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
		for grandchild in child.get_children():
			grandchild.owner = root
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, LAB_PATH)
	root.free()
	print("cliff kit lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)
