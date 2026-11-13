extends SceneTree
## Builds the climb lab (game/scenes/worlds/dev/climb-lab.tscn, world.climb-lab;
## docs/godot/ELEVATION.md "High levels", docs/godot/SKINS.md "Painting vines"): a first painting of
## walls over ten levels to climb with the Feral skin (the owner, 2026-11-12: "more than 10 levels
## for my new ideas of climbable chunks"), to repaint by hand in the editor.
## - West, **the sheer wall**: a level-12 top over one wall twelve courses tall, with a column of
##   vines from foot to rim, and two balconies (docs/godot/SKINS.md "Balconies"): one half-way up
##   with vines from the foot to it and from it on up to the rim, one higher to drop onto from the
##   rim above.
## - East, **the terraces**: level 12, then ledges at 8 and 4, four courses between each, a patch
##   of vines up every one.
## The lab lends the Feral skin (game-constants.json `skins.lends`). It does not overwrite the lab
## (add -- --force).
##     "<Godot console exe>" --headless --path godot -s res://tools/build_climb_lab.gd

const LAB_PATH := "res://game/scenes/worlds/dev/climb-lab.tscn"
const MAP_ID := "climb-lab"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const VINE_LAYER := "res://game/world/vines/vine_layer.gd"
const VINE_TILESET := "res://game/world/vines/vine_tileset.tres"
const CELL := 64
const COLUMNS := 34
const ROWS := 28
## The terrain tile set's grass source and how far its sheet runs before it wraps.
const GRASS := 7
const SHEET_CELLS := 19
## [level, cells] of every painted top, the higher ones over the lower: a top's wall hangs below its
## south edge, a row a level, over the cells of the ground it comes down to.
const TOPS: Array = [
	[12, Rect2i(3, 2, 10, 3)],
	[4, Rect2i(17, 2, 14, 15)],
	[8, Rect2i(17, 2, 14, 9)],
	[12, Rect2i(17, 2, 14, 3)],
]
## The balconies (cells, a row each): the sheer wall's two.
const BALCONIES: Array[Rect2i] = [Rect2i(6, 11, 4, 1), Rect2i(10, 8, 3, 1)]
## The vines' layer's tiles (vine_tileset.tres).
const VINES_TILE := Vector2i(0, 0)
const BALCONY_TILE := Vector2i(1, 0)
## The vines (cells): the sheer wall's column, from the foot to its first balcony and from it on to
## the rim; the terraces' three patches.
const VINES: Array[Rect2i] = [
	Rect2i(4, 5, 1, 12),
	Rect2i(7, 12, 1, 5), Rect2i(8, 5, 1, 6),
	Rect2i(19, 17, 2, 4), Rect2i(24, 11, 1, 4), Rect2i(27, 5, 2, 4),
]
const SPAWN_CELL := Vector2i(15, 24)


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("climb lab: %s exists; not overwritten (add -- --force)" % LAB_PATH)
		quit(0)
		return
	var root := Node2D.new()
	root.name = MAP_ID
	root.y_sort_enabled = true
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			ground.set_cell(Vector2i(x, y), GRASS, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_script(load(WORLD_GROUND))
	root.add_child(ground)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.visible = false
	elevation.tile_set = load(ELEVATION_TILESET)
	for top: Array in TOPS:
		var cells: Rect2i = top[1]
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				elevation.set_cell(Vector2i(x, y), 0, _level_tile(int(top[0])))
	elevation.set_script(load(ELEVATION_LAYER))
	root.add_child(elevation)
	var vines := TileMapLayer.new()
	vines.name = "vines"
	vines.z_index = -1
	vines.tile_set = load(VINE_TILESET)
	for cells: Rect2i in VINES:
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				vines.set_cell(Vector2i(x, y), 0, VINES_TILE)
	for cells: Rect2i in BALCONIES:
		for x in range(cells.position.x, cells.end.x):
			vines.set_cell(Vector2i(x, cells.position.y), 0, BALCONY_TILE)
	vines.set_script(load(VINE_LAYER))
	root.add_child(vines)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(SPAWN_CELL) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", MAP_ID)
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
	print("climb lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


## The elevation tile set's tile of `level` (elevation_tileset.tres: 1 … 3 in its first row, 4 … 16
## in rows 4 and 5, eight a row).
static func _level_tile(level: int) -> Vector2i:
	if level <= 3:
		return Vector2i(level + 2, 0)
	@warning_ignore("integer_division")
	return Vector2i((level - 4) % 8, 4 + (level - 4) / 8)
