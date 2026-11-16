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
##
## `-- --styles=<style>,<style>,...` builds the **style walls** instead, to see the pictures made per
## wall style (game/world/elevation/wall_pictures.gd): a wall eight courses tall per style, its top
## painted with that style on a `cliffs` layer, a balcony half-way up, a wall hole at the balcony's
## back edge and a cave mouth at the foot. It is written to `--out=<path>`
## (user://style-walls.tscn by default), never over the lab; render it with
## `tools/render_vines.gd -- --scene=<path> --cells=0,1,<columns>,14`.

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
## The style walls (`--styles`): the cliffs layer's tile set and script, the doors, where it is
## written, and each wall's block (cells): its top's level, width and depth, the gap between walls,
## the balcony's row and cells across the block.
const CLIFF_TILESET := "res://game/world/elevation/cliffs/cliff_tileset.tres"
const CLIFF_LAYER := "res://game/world/elevation/cliffs/cliff_layer.gd"
const CAVE_MOUTH := "res://game/scenes/objects/cave-mouth.tscn"
const WALL_HOLE := "res://game/scenes/objects/wall-hole.tscn"
const STYLE_WALLS_PATH := "user://style-walls.tscn"
const STYLE_LEVEL := 8
const STYLE_TOP := Rect2i(0, 2, 6, 3)
const STYLE_GAP := 2
const STYLE_BALCONY := Rect2i(1, 7, 4, 1)

var columns := COLUMNS
var rows := ROWS
var tops: Array = TOPS
var balconies: Array[Rect2i] = BALCONIES
var vine_cells: Array[Rect2i] = VINES
var spawn_cell := SPAWN_CELL
## cell -> wall style painted on the `cliffs` layer (the style walls only).
var styles_painted := {}
## [scene path, position] of the doors placed (the style walls only).
var doors: Array = []
## Styles the `cliffs` layer cannot paint (storybook-rock): one of them is given to the grass as the
## world's own wall style (Elevation WORLD_WALL_STYLES_META), so its unpainted top takes it.
var unpainted: PackedStringArray = []


func _initialize() -> void:
	var path := LAB_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--styles="):
			_plan_style_walls(arg.trim_prefix("--styles=").split(",", false))
			path = STYLE_WALLS_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out=") and path != LAB_PATH:
			path = arg.trim_prefix("--out=")
	if path == LAB_PATH and FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("climb lab: %s exists; not overwritten (add -- --force)" % LAB_PATH)
		quit(0)
		return
	var root := _build()
	if path.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	print("climb lab: %s %s (%d x %d cells)" % [path, "ok" if err == OK else "failed (%d)" % err, columns, rows])
	quit(0 if err == OK else 1)


## The style walls' plan: one block per style, west to east.
func _plan_style_walls(styles: PackedStringArray) -> void:
	var block := STYLE_TOP.size.x + STYLE_GAP
	columns = STYLE_GAP + styles.size() * block
	rows = STYLE_TOP.end.y + STYLE_LEVEL + 3
	tops = []
	balconies = []
	vine_cells = []
	spawn_cell = Vector2i(1, rows - 2)
	var foot := STYLE_TOP.end.y + STYLE_LEVEL
	for index in styles.size():
		var x0 := STYLE_GAP + index * block
		var top := Rect2i(STYLE_TOP.position + Vector2i(x0, 0), STYLE_TOP.size)
		tops.append([STYLE_LEVEL, top])
		for y in range(top.position.y, top.end.y):
			for x in range(top.position.x, top.end.x):
				styles_painted[Vector2i(x, y)] = styles[index]
		var balcony := Rect2i(STYLE_BALCONY.position + Vector2i(x0, 0), STYLE_BALCONY.size)
		balconies.append(balcony)
		var middle := (balcony.position.x + balcony.size.x * 0.5) * CELL
		doors.append([WALL_HOLE, Vector2(middle, balcony.position.y * CELL)])
		doors.append([CAVE_MOUTH, Vector2(middle, foot * CELL)])


func _build() -> Node2D:
	var root := Node2D.new()
	root.name = MAP_ID
	root.y_sort_enabled = true
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in rows:
		for x in columns:
			ground.set_cell(Vector2i(x, y), GRASS, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", columns * rows)
	ground.set_meta(&"columns", columns)
	ground.set_meta(&"rows", rows)
	ground.set_script(load(WORLD_GROUND))
	root.add_child(ground)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.visible = false
	elevation.tile_set = load(ELEVATION_TILESET)
	for top: Array in tops:
		var cells: Rect2i = top[1]
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				elevation.set_cell(Vector2i(x, y), 0, _level_tile(int(top[0])))
	elevation.set_script(load(ELEVATION_LAYER))
	root.add_child(elevation)
	if not styles_painted.is_empty():
		root.add_child(_cliffs_layer())
		if not unpainted.is_empty():
			ground.set_meta(&"cliff_wall_styles", {"highland": unpainted[0]})
		if unpainted.size() > 1:
			push_warning("climb lab: no cliffs tile for %s; build them apart" % ", ".join(unpainted.slice(1)))
	var vines := TileMapLayer.new()
	vines.name = "vines"
	vines.z_index = -1
	vines.tile_set = load(VINE_TILESET)
	for cells: Rect2i in vine_cells:
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				vines.set_cell(Vector2i(x, y), 0, VINES_TILE)
	for cells: Rect2i in balconies:
		for x in range(cells.position.x, cells.end.x):
			vines.set_cell(Vector2i(x, cells.position.y), 0, BALCONY_TILE)
	vines.set_script(load(VINE_LAYER))
	root.add_child(vines)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(spawn_cell) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", columns)
	definition.set(&"rows", rows)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	root.add_child(definition)
	var marker := Node2D.new()
	marker.name = "player-spawn"
	marker.y_sort_enabled = true
	marker.position = spawn
	root.add_child(marker)
	for child in root.get_children():
		child.owner = root
	for door: Array in doors:
		var object := (load(str(door[0])) as PackedScene).instantiate() as Node2D
		object.position = door[1]
		root.add_child(object)
		object.owner = root
	return root


## The `cliffs` layer painting each style wall's top with its style (cliff_tileset.tres: the tile
## whose `wall_style` data names it).
func _cliffs_layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "cliffs"
	layer.z_index = -1
	layer.tile_set = load(CLIFF_TILESET)
	var tiles := {}
	for index in layer.tile_set.get_source_count():
		var id := layer.tile_set.get_source_id(index)
		var atlas := layer.tile_set.get_source(id) as TileSetAtlasSource
		if atlas == null:
			continue
		for tile in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(tile)
			var data := atlas.get_tile_data(coords, 0)
			if data != null:
				tiles[str(data.get_custom_data("wall_style"))] = [id, coords]
	for cell: Vector2i in styles_painted:
		var style := str(styles_painted[cell])
		if tiles.has(style):
			layer.set_cell(cell, int(tiles[style][0]), tiles[style][1])
		elif not unpainted.has(style):
			unpainted.append(style)
	layer.set_script(load(CLIFF_LAYER))
	return layer


## The elevation tile set's tile of `level` (elevation_tileset.tres: 1 … 3 in its first row, 4 … 16
## in rows 4 and 5, eight a row).
static func _level_tile(level: int) -> Vector2i:
	if level <= 3:
		return Vector2i(level + 2, 0)
	@warning_ignore("integer_division")
	return Vector2i((level - 4) % 8, 4 + (level - 4) / 8)
