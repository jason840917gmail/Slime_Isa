extends SceneTree
## Builds the cliff pieces lab (docs/godot/CLIFFS.md "Cliff pieces"):
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_cliff_pieces_lab.gd
## Writes res://game/scenes/worlds/cliff-pieces-lab.tscn (world.cliff-pieces-lab): a grass field
## with stretchable cliffs (CliffBuilder) of every kind and a two-level stack. Rebuilding overwrites
## the lab: make your own cliffs in another scene.

const LAB_PATH := "res://game/scenes/worlds/cliff-pieces-lab.tscn"
const BUILDER := "res://game/world/cliffs/cliff_builder.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CELL := 64
const COLUMNS := 80
const ROWS := 70
const GRASS_SOURCE := 7
const SHEET_CELLS := 19
## name, kind, cell position, size in cells, variation (later ones draw over earlier ones)
const CLIFFS := [
	["octagon 20 x 16", "octagon", Vector2i(2, 2), Vector2i(20, 16), 0],
	["octagon 30 x 14", "octagon", Vector2i(26, 2), Vector2i(30, 14), 1],
	["rectangle 1 level 12 x 11", "rectangle 1 level", Vector2i(60, 2), Vector2i(12, 11), 0],
	["rectangle 2 levels 16 x 13", "rectangle 2 levels", Vector2i(2, 22), Vector2i(16, 13), 0],
	["rectangle 3 levels 20 x 14", "rectangle 3 levels", Vector2i(22, 22), Vector2i(20, 14), 0],
	["octagon dip 18 x 18", "octagon dip", Vector2i(46, 22), Vector2i(18, 18), 0],
	["stack: base rectangle 30 x 22", "rectangle 2 levels", Vector2i(2, 44), Vector2i(30, 22), 2],
	["stack: upper rectangle 14 x 11", "rectangle 1 level", Vector2i(9, 46), Vector2i(14, 11), 1],
]
const SPAWN_CELL := Vector2i(40, 50)


func _initialize() -> void:
	var root := Node2D.new()
	root.name = "cliff-pieces-lab"
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
		var node := Node2D.new()
		node.name = spec[0]
		node.z_index = -1
		node.set_script(load(BUILDER))
		node.position = Vector2(spec[2]) * CELL
		node.set(&"kind", spec[1])
		node.set(&"width_cells", (spec[3] as Vector2i).x)
		node.set(&"height_cells", (spec[3] as Vector2i).y)
		node.set(&"variation", spec[4])
		root.add_child(node)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(SPAWN_CELL) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", "cliff-pieces-lab")
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
	print("cliff pieces lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)
