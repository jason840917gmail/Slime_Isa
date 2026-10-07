extends SceneTree
## Compares the two ways to draw the hand-made terrain edges (docs/godot/TERRAIN_LAB.md):
## - dual: TerrainEdges, the game's system: edge tiles on a dual grid over the ground layer, picked
##   from the ground cells (index = TL + 2 TR + 4 BL + 8 BR).
## - godot: Godot's own Terrains with the terrain layers lab's tile set (tagged as the owner set it
##   up in the TileSet editor): a TileMapLayer per ground, painted the way the Terrains tab paints.
##   A paints each ground only on its own cells; B also paints it under the grounds above it.
##
## Four tests, written to <out>/report.md with PNGs:
## 1. Shapes: the same cells drawn both ways; where each ground shows against its own cells.
## 2. Shores: land drawn over solid water cells, water drawn over walkable cells.
## 3. Paint order: one shape painted in different orders (strokes, cell by cell, erase).
## 4. A real world (level-1): build time, tiles, draw calls and the same coverage numbers.
##
## Coverage is measured from the art, not from screenshots: SAMPLES x SAMPLES points per cell, each
## taking the ground of the topmost tile whose art covers it (alpha >= 0.5), else what is under the
## tiles (dual: the cell's own ground tile; godot: nothing, a hole).
##
## Run windowed (it renders), with the Godot 4.7.2 console exe:
##     --path godot -s res://tools/compare_terrain_edges.gd -- [--out=<dir>]
## The default output directory is user://terrain-compare.

const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const WaterSurface := preload("res://game/world/water_surface.gd")
const LayersLab := preload("res://tools/build_terrain_layers_lab.gd")
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const LAYERS_TILESET := "res://game/dev/terrain_lab/terrain_layers_tileset.tres"
const WORLD := "res://game/scenes/worlds/level-1.tscn"
const WORLD_GROUND := "ground"
const DEFAULT_OUT := "user://terrain-compare"
const CELL := 64
const ART := 128
const GUTTER := 2
const SHEET_CELLS := 19
const TILE_ID := "tile_id"
## What a sample shows: a ground name, HARD (a tile without edges: rock wall, floors) or NONE.
const HARD := "hard"
const NONE := ""
const WATER := "water"
const SAMPLES := 8
const WORLD_SAMPLES := 4
## The busiest window of the world drawn up close (cells).
const CROP := Vector2i(20, 12)
const BACKGROUND := Color("0b1020")
const COLLISION_LINE := Color(1.0, 0.15, 0.15, 0.75)
const GROUND_LINE := Color(1.0, 1.0, 1.0, 0.45)
const KEY := {
	"w": "water", "d": "deep-water", "s": "sanddessert-ground", "g": "grass-a", "z": "frozen-ground",
	"t": "town-cobble", "r": "rock-wall",
}
const SHAPES := [
	["one cell", ["wwwwwwww", "wwwwwwww", "wwwswwww", "wwwwwwww", "wwwwwwww", "wwwwwwww"]],
	["line, one wide", ["wwwwwwww", "wwwwwwww", "wssssssw", "wwwwwwww", "wwwwwwww", "wwwwwwww"]],
	["diagonal", ["wwwwwwww", "wswwwwww", "wwswwwww", "wwwswwww", "wwwwswww", "wwwwwwww"]],
	["2 x 2", ["wwwwwwww", "wwwwwwww", "wwwsswww", "wwwsswww", "wwwwwwww", "wwwwwwww"]],
	["L, one wide", ["wwwwwwww", "wswwwwww", "wswwwwww", "wswwwwww", "wsssssww", "wwwwwwww"]],
	["ring, one-cell hole", ["wwwwwwww", "wwssswww", "wwswswww", "wwssswww", "wwwwwwww", "wwwwwwww"]],
	["checkerboard", ["wwwwwwww", "wswswsww", "wwswswww", "wswswsww", "wwswswww", "wwwwwwww"]],
	["island 5 x 3", ["wwwwwwww", "wsssssww", "wsssssww", "wsssssww", "wwwwwwww", "wwwwwwww"]],
	["three grounds", ["wwwwssss", "wwwwssss", "wwwwssss", "gggggggg", "gggggggg", "gggggggg"]],
	["four grounds", ["wwwwssss", "wwwwssss", "wwwwssss", "ggggzzzz", "ggggzzzz", "ggggzzzz"]],
	["cobble road", ["gggggggg", "tttttggg", "ggggtggg", "ggggtttt", "gggggggg", "gggggggg"]],
	["map border", ["sssswwww", "sssswwww", "sssswwww", "wwwwwwww", "wwwwwwww", "wwwwwwww"]],
	["rock wall", ["wwwwwwww", "wsssrrrw", "wsssrrrw", "wsssrrrw", "wwwwwwww", "wwwwwwww"]],
]
## Test 3: sand on water, painted in each order.
const ORDER_SHAPES := [
	["one cell", ["wwwwww", "wwwwww", "wwswww", "wwwwww", "wwwwww", "wwwwww"]],
	["line", ["wwwwww", "wwwwww", "wsssss", "wwwwww", "wwwwww", "wwwwww"]],
	["3 x 3", ["wwwwww", "wsssww", "wsssww", "wsssww", "wwwwww", "wwwwww"]],
	["L, two wide", ["wwwwww", "wsswww", "wsswww", "wsssss", "wsssss", "wwwwww"]],
	["blob", ["wwwwww", "wwssww", "wsssss", "wssssw", "wwsssw", "wwwwww"]],
]
const ORDERS := ["one stroke", "cell by cell", "reversed", "random", "twice", "erase and repaint", "erase half", "script default"]

var _out := DEFAULT_OUT
var _terrain_tiles: TileSet
var _layers_tiles: TileSet
## Terrain tile id -> source id in the terrain tile set.
var _source_of := {}
## Ground -> its edge art (Image), for the coverage samples.
var _art := {}
## Ground -> terrain index, and the water source, in the layers tile set.
var _terrain_of := {}
var _water_source := -1
var _report := PackedStringArray()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	if not _load():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_report.append("# Terrain edges: dual grid vs Godot Terrains")
	_report.append("")
	_report.append("Built by `godot/tools/compare_terrain_edges.gd` (%s). Coverage is in cells (64 x 64 units); a sample shows the ground of the topmost tile whose art covers it." % Time.get_datetime_string_from_system())
	_report.append("")
	await _test_shapes()
	await _test_orders()
	await _test_world()
	var file := FileAccess.open(_out.path_join("report.md"), FileAccess.WRITE)
	file.store_string("\n".join(_report) + "\n")
	file.close()
	print("compare_terrain_edges: wrote %s" % ProjectSettings.globalize_path(_out.path_join("report.md")))
	quit(0)


func _load() -> bool:
	_terrain_tiles = load(TERRAIN_TILESET) as TileSet
	_layers_tiles = load(LAYERS_TILESET) as TileSet
	if _terrain_tiles == null or _layers_tiles == null:
		push_error("compare_terrain_edges: missing %s or %s (run tools/build_terrain_layers_lab.gd)" % [TERRAIN_TILESET, LAYERS_TILESET])
		return false
	for i in _terrain_tiles.get_source_count():
		var id := _terrain_tiles.get_source_id(i)
		var source := _terrain_tiles.get_source(id) as TileSetAtlasSource
		if source == null or source.get_tiles_count() == 0:
			continue
		var tile_id := str(source.get_tile_data(source.get_tile_id(0), 0).get_custom_data(TILE_ID))
		if not _source_of.has(tile_id):
			_source_of[tile_id] = id
	for ground: String in TerrainMaterials.ORDER:
		if ground == WATER:
			continue
		var image := (load(TerrainMaterials.edges_path(ground)) as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		_art[ground] = image
	for terrain in _layers_tiles.get_terrains_count(LayersLab.TERRAIN_SET):
		var name := _layers_tiles.get_terrain_name(LayersLab.TERRAIN_SET, terrain)
		for ground: String in LayersLab.NAMES:
			if LayersLab.NAMES[ground] == name:
				_terrain_of[ground] = terrain
	for i in _layers_tiles.get_source_count():
		var id := _layers_tiles.get_source_id(i)
		if _layers_tiles.get_source(id).resource_name == LayersLab.NAMES[WATER]:
			_water_source = id
	return _water_source >= 0 and _terrain_of.size() == TerrainMaterials.ORDER.size() - 1


# --- Test 1 and 2: shapes ------------------------------------------------------------------------

func _test_shapes() -> void:
	_report.append("## 1. Shapes (and 2. shores)")
	_report.append("")
	_report.append("The same cells drawn three ways. *Right* is the share of the drawing that shows each cell's own ground; *wrong ground* is ground drawn over another ground's cells; *holes* show nothing. *Land on water* is land drawn over solid water cells (the slime is stopped there although it looks like land), *water on land* the reverse. *Shore offset* is how far the visible shore sits from the collision line, on average (units; + = into the water). *Seams* counts neighbouring Godot tiles that disagree on a shared corner or side (Godot found no exact tile).")
	_report.append("")
	_report.append("| Shape | System | Right | Wrong ground | Holes | Land on water | Water on land | Shore offset | Seams | Painted cells lost |")
	_report.append("|---|---|---|---|---|---|---|---|---|---|")
	var rows: Array[Image] = []
	var totals := {}
	for shape: Array in SHAPES:
		print("compare_terrain_edges: shape %s" % shape[0])
		var map := LayersLab.map_cells(shape[1], KEY)
		var size := Vector2i(shape[1][0].length(), shape[1].size())
		var panels: Array[Image] = []
		for system: String in ["dual", "godot A", "godot B"]:
			var built := _build(system, map, size)
			var metrics := _coverage(built.stack, map, size, SAMPLES)
			metrics["seams"] = built.get("seams", 0)
			metrics["lost"] = built.get("lost", 0)
			_report.append(_metrics_row(str(shape[0]), system, metrics, true))
			if not totals.has(system):
				totals[system] = {}
			_add(totals[system], metrics)
			_outline(built.content, map, size)
			panels.append(await _grab(built.viewport, built.camera, Rect2(Vector2(-CELL, -CELL), Vector2(size + Vector2i(2, 2)) * CELL), 0.75, "%s: %s" % [shape[0], _system_title(system)]))
			built.viewport.free()
		rows.append(_compose(panels, 3))
	for system: String in totals:
		_report.append(_metrics_row("**all shapes**", system, totals[system], true))
	_report.append("")
	var sheet := _compose(rows, 1)
	sheet.save_png(ProjectSettings.globalize_path(_out.path_join("1-shapes.png")))
	_report.append("![shapes](1-shapes.png) Red lines: the collision line (water cells against walkable cells); white: other ground changes.")
	_report.append("")


## Builds `system` ("dual", "godot A", "godot B") for `map` in its own viewport.
## Returns {viewport, camera, content, stack, seams?, lost?}.
func _build(system: String, map: Dictionary, size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	viewport.add_child(camera)
	var content := Node2D.new()
	viewport.add_child(content)
	var built := {"viewport": viewport, "camera": camera, "content": content}
	var truth := _truth(map)
	if system == "dual":
		var ground := TileMapLayer.new()
		ground.tile_set = _terrain_tiles
		ground.set_meta("columns", size.x)
		ground.set_meta("rows", size.y)
		content.add_child(ground)
		for cell: Vector2i in map:
			ground.set_cell(cell, _source_of[map[cell]], Vector2i(posmod(cell.x, SHEET_CELLS), posmod(cell.y, SHEET_CELLS)))
		var started := Time.get_ticks_usec()
		WaterSurface.mount(ground)
		var edges := TerrainEdges.mount(ground)
		built["msec"] = (Time.get_ticks_usec() - started) / 1000.0
		var by_source := {}
		for name_of_ground: String in edges.sources:
			by_source[edges.sources[name_of_ground]] = name_of_ground
		var levels := []
		for layer in edges.layers:
			levels.append({"layer": layer, "origin": edges.position, "sources": by_source})
		built["stack"] = {"levels": levels, "base": truth}
		built["tiles"] = edges.placed
		built["layers"] = edges.layers.size()
	else:
		var godot := _godot_layers(content, map, system == "godot B", LayersLab.IGNORE_EMPTY)
		built["stack"] = godot.stack
		built["seams"] = godot.seams
		built["lost"] = godot.lost
		built["tiles"] = godot.tiles
		built["layers"] = godot.layers
		built["msec"] = godot.msec
	return built


## Godot Terrains under `parent`: a plain layer for the hard-edged tiles, then a TileMapLayer per
## ground (layers tile set at half scale), water as plain tiles, each land ground painted with one
## set_cells_terrain_connect call. `under` also paints each ground under the grounds above it.
func _godot_layers(parent: Node2D, map: Dictionary, under: bool, ignore_empty: bool) -> Dictionary:
	var hard := TileMapLayer.new()
	hard.tile_set = _terrain_tiles
	parent.add_child(hard)
	var grounds := Node2D.new()
	grounds.scale = Vector2.ONE * (float(CELL) / ART)
	parent.add_child(grounds)
	var layers := {}
	for ground: String in TerrainMaterials.ORDER:
		var layer := TileMapLayer.new()
		layer.tile_set = _layers_tiles
		grounds.add_child(layer)
		layers[ground] = layer
	var order_at := {}
	var base := {}
	for cell: Vector2i in map:
		var ground := TerrainMaterials.ground_of(map[cell])
		order_at[cell] = TerrainMaterials.order_of(ground) if ground != "" else -1
		if ground == "":
			hard.set_cell(cell, _source_of[map[cell]], Vector2i(posmod(cell.x, SHEET_CELLS), posmod(cell.y, SHEET_CELLS)))
			base[cell] = HARD
	var water: TileMapLayer = layers[WATER]
	for cell: Vector2i in map:
		if order_at[cell] == 0 or (under and order_at[cell] > 0):
			water.set_cell(cell, _water_source, LayersLab.FULL, LayersLab.DEEP if map[cell] == "deep-water" else LayersLab.SHALLOW)
	var started := Time.get_ticks_usec()
	var painted := {}
	for order in range(1, TerrainMaterials.ORDER.size()):
		var ground := TerrainMaterials.ORDER[order]
		var cells: Array[Vector2i] = []
		for cell: Vector2i in order_at:
			if order_at[cell] == order or (under and order_at[cell] > order):
				cells.append(cell)
		painted[ground] = cells
		if not cells.is_empty():
			(layers[ground] as TileMapLayer).set_cells_terrain_connect(cells, LayersLab.TERRAIN_SET, _terrain_of[ground], ignore_empty)
	var msec := (Time.get_ticks_usec() - started) / 1000.0
	var by_source := {}
	for i in _layers_tiles.get_source_count():
		var id := _layers_tiles.get_source_id(i)
		var source_name := _layers_tiles.get_source(id).resource_name
		for ground: String in LayersLab.NAMES:
			if LayersLab.NAMES[ground] == source_name:
				by_source[id] = ground
	var levels := []
	var seams := 0
	var lost := 0
	var tiles := 0
	for ground: String in TerrainMaterials.ORDER:
		var layer: TileMapLayer = layers[ground]
		levels.append({"layer": layer, "origin": Vector2.ZERO, "sources": by_source})
		tiles += layer.get_used_cells().size()
		if ground == WATER:
			continue
		seams += _seams(layer)
		for cell: Vector2i in painted[ground]:
			var data := layer.get_cell_tile_data(cell)
			if data == null or data.terrain != _terrain_of[ground]:
				lost += 1
	tiles += hard.get_used_cells().size()
	return {"stack": {"levels": levels, "base": base}, "seams": seams, "lost": lost, "tiles": tiles, "layers": TerrainMaterials.ORDER.size() + 1, "msec": msec, "layer_of": layers}


## Neighbouring tiles of `layer` that disagree on a shared side or corner (a missing tile counts as
## no terrain on every bit).
func _seams(layer: TileMapLayer) -> int:
	var cells := {}
	for cell: Vector2i in layer.get_used_cells():
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				cells[cell + Vector2i(dx, dy)] = true
	var pairs := {
		Vector2i(1, 0): [[TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE],
			[TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER],
			[TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER]],
		Vector2i(0, 1): [[TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE],
			[TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER],
			[TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER]],
		Vector2i(1, 1): [[TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER]],
		Vector2i(-1, 1): [[TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER]],
	}
	var seams := 0
	for cell: Vector2i in cells:
		var data := _terrain_data(layer, cell)
		for offset: Vector2i in pairs:
			var other := _terrain_data(layer, cell + offset)
			if data == null and other == null:
				continue
			for pair: Array in pairs[offset]:
				var mine := data.get_terrain_peering_bit(pair[0]) if data != null else -1
				var theirs := other.get_terrain_peering_bit(pair[1]) if other != null else -1
				if mine != theirs:
					seams += 1
	return seams


func _terrain_data(layer: TileMapLayer, cell: Vector2i) -> TileData:
	var data := layer.get_cell_tile_data(cell)
	return data if data != null and data.terrain_set >= 0 else null


## Cell -> what the cell is: its ground, or HARD for a tile without edges.
func _truth(map: Dictionary) -> Dictionary:
	var truth := {}
	for cell: Vector2i in map:
		var ground := TerrainMaterials.ground_of(map[cell])
		truth[cell] = ground if ground != "" else HARD
	return truth


## What shows at point `p`: the topmost tile whose art covers it, else the stack's base.
func _visible(stack: Dictionary, p: Vector2) -> String:
	var levels: Array = stack.levels
	for i in range(levels.size() - 1, -1, -1):
		var level: Dictionary = levels[i]
		var layer: TileMapLayer = level.layer
		var local: Vector2 = p - level.origin
		var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		var source := layer.get_cell_source_id(cell)
		if source == -1:
			continue
		var ground: String = level.sources.get(source, NONE)
		if ground == NONE:
			continue
		if ground == WATER:
			return ground
		var atlas := layer.get_cell_atlas_coords(cell)
		var x := GUTTER + atlas.x * (ART + 2 * GUTTER) + int((local.x - cell.x * CELL) * ART / CELL)
		var y := GUTTER + atlas.y * (ART + 2 * GUTTER) + int((local.y - cell.y * CELL) * ART / CELL)
		if (_art[ground] as Image).get_pixel(x, y).a >= 0.5:
			return ground
	return str(stack.base.get(Vector2i(floori(p.x / CELL), floori(p.y / CELL)), NONE))


## Coverage of `map` (cells) by `stack`, in samples, plus the shore length (cell sides).
func _coverage(stack: Dictionary, map: Dictionary, size: Vector2i, samples: int) -> Dictionary:
	var truth := _truth(map)
	var m := {"samples": 0, "right": 0, "wrong": 0, "holes": 0, "land_on_water": 0, "water_on_land": 0, "shore": 0, "per_cell": samples * samples}
	for cell: Vector2i in truth:
		var t: String = truth[cell]
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if truth.has(cell + offset) and _is_shore(t, truth[cell + offset]):
				m.shore += 1
		for sy in samples:
			for sx in samples:
				var p := (Vector2(cell) + Vector2((sx + 0.5) / samples, (sy + 0.5) / samples)) * CELL
				var v := _visible(stack, p)
				m.samples += 1
				if v == t:
					m.right += 1
				elif v == NONE:
					m.holes += 1
				else:
					m.wrong += 1
					if t == WATER and v != HARD:
						m.land_on_water += 1
					elif v == WATER and t != HARD:
						m.water_on_land += 1
	return m


func _is_shore(a: String, b: String) -> bool:
	return (a == WATER and b != WATER and b != HARD) or (b == WATER and a != WATER and a != HARD)


func _add(total: Dictionary, metrics: Dictionary) -> void:
	for key: String in metrics:
		if key == "per_cell":
			total[key] = metrics[key]
		else:
			total[key] = total.get(key, 0) + metrics[key]


func _metrics_row(shape: String, system: String, m: Dictionary, with_godot: bool) -> String:
	var per_cell: float = m.per_cell
	var offset := "-"
	if m.shore > 0:
		offset = "%+.1f" % ((m.land_on_water - m.water_on_land) / per_cell * CELL / m.shore)
	var row := "| %s | %s | %.1f%% | %.2f | %.2f | %.2f | %.2f | %s |" % [
		shape, _system_title(system), 100.0 * m.right / m.samples, m.wrong / per_cell, m.holes / per_cell,
		m.land_on_water / per_cell, m.water_on_land / per_cell, offset]
	if with_godot:
		row += " %s | %s |" % [str(m.get("seams", "-")) if system != "dual" else "-", str(m.get("lost", "-")) if system != "dual" else "-"]
	return row


func _system_title(system: String) -> String:
	match system:
		"dual":
			return "dual grid (game)"
		"godot A":
			return "Godot Terrains A (own cells)"
		"godot B":
			return "Godot Terrains B (+ under)"
	return system


# --- Test 3: paint order -------------------------------------------------------------------------

func _test_orders() -> void:
	_report.append("## 3. Paint order")
	_report.append("")
	_report.append("Sand on water, Godot Terrains, painted in different orders. *One stroke* paints every cell in one call (the rectangle tool, or one drag that the editor applies at once); *cell by cell* calls once per cell (a slow drag), in row order, reversed or shuffled; *twice* goes over the cells a second time; *erase and repaint* erases one inner cell with the Terrains eraser and paints it again; *erase half* paints the shape, then erases its right half in one stroke, compared with painting only the left half; *script default* is one stroke with `ignore_empty_terrains = true` (GDScript's default; the editor votes with empty cells). *Differs* counts cells whose tile is not the one-stroke tile. *Empty tiles* are leftover tiles with no art. The dual grid builds its tiles from the final cells, so every order gives the same tiles (checked: %s)." % ("yes" if _dual_order_free() else "NO"))
	_report.append("")
	var variants := {"owner tagging": _layers_tiles, "empty tile out of the terrain set": _without_empty_tile(_layers_tiles)}
	var rows: Array[Image] = []
	for variant: String in variants:
		var tile_set: TileSet = variants[variant]
		_report.append("**%s**" % variant.capitalize())
		_report.append("")
		_report.append("| Shape | " + " | ".join(ORDERS) + " |")
		_report.append("|---|" + "---|".repeat(ORDERS.size()))
		for shape: Array in ORDER_SHAPES:
			var map := LayersLab.map_cells(shape[1], KEY)
			var size := Vector2i(shape[1][0].length(), shape[1].size())
			var cells: Array[Vector2i] = []
			for cell: Vector2i in map:
				if map[cell] == "sanddessert-ground":
					cells.append(cell)
			cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
			var reference := _paint_order(tile_set, cells, "one stroke")
			var row := "| %s |" % shape[0]
			var panels: Array[Image] = []
			for order: String in ORDERS:
				var layer := _paint_order(tile_set, cells, order)
				var expected := _paint_order(tile_set, _left_half(cells), "one stroke") if order == "erase half" else reference
				var differs := _diff(expected, layer)
				if expected != reference:
					expected.free()
				var empty := 0
				for cell in layer.get_used_cells():
					if layer.get_cell_atlas_coords(cell) == Vector2i.ZERO:
						empty += 1
				row += " %d differ, %d seams%s |" % [differs, _seams(layer), (", %d empty tiles" % empty) if empty > 0 else ""]
				if variant == "owner tagging":
					panels.append(await _grab_order(layer, map, size, "%s: %s" % [shape[0], order]))
				else:
					layer.free()
			reference.free()
			_report.append(row)
			if not panels.is_empty():
				rows.append(_compose(panels, ORDERS.size()))
		_report.append("")
	_compose(rows, 1).save_png(ProjectSettings.globalize_path(_out.path_join("3-paint-order.png")))
	_report.append("![paint order](3-paint-order.png)")
	_report.append("")


func _paint_order(tile_set: TileSet, cells: Array[Vector2i], order: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	var sand: int = _terrain_of["sanddessert"]
	var ignore := LayersLab.IGNORE_EMPTY
	var sequence: Array[Vector2i] = cells.duplicate()
	match order:
		"one stroke", "erase and repaint", "script default":
			layer.set_cells_terrain_connect(cells, LayersLab.TERRAIN_SET, sand, true if order == "script default" else ignore)
			if order == "erase and repaint":
				var inner: Array[Vector2i] = [cells[cells.size() / 2]]
				layer.set_cells_terrain_connect(inner, LayersLab.TERRAIN_SET, -1, ignore)
				layer.set_cells_terrain_connect(inner, LayersLab.TERRAIN_SET, sand, ignore)
			return layer
		"erase half":
			layer.set_cells_terrain_connect(cells, LayersLab.TERRAIN_SET, sand, ignore)
			var right: Array[Vector2i] = []
			var left := _left_half(cells)
			for cell in cells:
				if not cell in left:
					right.append(cell)
			layer.set_cells_terrain_connect(right, LayersLab.TERRAIN_SET, -1, ignore)
			return layer
		"reversed":
			sequence.reverse()
		"random":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in range(sequence.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var keep := sequence[i]
				sequence[i] = sequence[j]
				sequence[j] = keep
		"twice":
			sequence.append_array(cells)
	for cell in sequence:
		var one: Array[Vector2i] = [cell]
		layer.set_cells_terrain_connect(one, LayersLab.TERRAIN_SET, sand, ignore)
	return layer


## The cells left of the shape's middle column (all of them for a one-cell shape).
func _left_half(cells: Array[Vector2i]) -> Array[Vector2i]:
	var low := cells[0].x
	var high := cells[0].x
	for cell in cells:
		low = mini(low, cell.x)
		high = maxi(high, cell.x)
	var middle := (low + high + 1) / 2
	var left: Array[Vector2i] = []
	for cell in cells:
		if cell.x < middle or low == high:
			left.append(cell)
	return left


func _diff(a: TileMapLayer, b: TileMapLayer) -> int:
	var cells := {}
	for cell in a.get_used_cells():
		cells[cell] = true
	for cell in b.get_used_cells():
		cells[cell] = true
	var differs := 0
	for cell: Vector2i in cells:
		if a.get_cell_source_id(cell) != b.get_cell_source_id(cell) or a.get_cell_atlas_coords(cell) != b.get_cell_atlas_coords(cell):
			differs += 1
	return differs


## The layers tile set with each ground's empty tile (no corner covered) taken out of the terrain
## set, so Godot cannot place it as a leftover.
func _without_empty_tile(tile_set: TileSet) -> TileSet:
	var copy := tile_set.duplicate(true) as TileSet
	for i in copy.get_source_count():
		var source := copy.get_source(copy.get_source_id(i)) as TileSetAtlasSource
		if source.has_tile(Vector2i.ZERO):
			source.get_tile_data(Vector2i.ZERO, 0).terrain_set = -1
	var original := tile_set.get_source(tile_set.get_source_id(1)) as TileSetAtlasSource
	if original.get_tile_data(Vector2i.ZERO, 0).terrain_set < 0:
		push_error("compare_terrain_edges: duplicating the tile set changed the original")
	return copy


## The dual grid's tiles do not depend on the order the cells were set in.
func _dual_order_free() -> bool:
	var shape: Array = ORDER_SHAPES[4]
	var map := LayersLab.map_cells(shape[1], KEY)
	var keys: Array = map.keys()
	var results := []
	for pass_index in 2:
		var ground := TileMapLayer.new()
		ground.tile_set = _terrain_tiles
		ground.set_meta("columns", shape[1][0].length())
		ground.set_meta("rows", shape[1].size())
		if pass_index == 1:
			keys.reverse()
		for cell: Vector2i in keys:
			ground.set_cell(cell, _source_of[map[cell]], Vector2i(posmod(cell.x, SHEET_CELLS), posmod(cell.y, SHEET_CELLS)))
		var edges := TerrainEdges.mount(ground)
		var tiles := {}
		for level in edges.layers.size():
			for cell in edges.layers[level].get_used_cells():
				tiles[Vector3i(cell.x, cell.y, level)] = [edges.layers[level].get_cell_source_id(cell), edges.layers[level].get_cell_atlas_coords(cell)]
		results.append(tiles)
		ground.free()
	return results[0] == results[1]


func _grab_order(layer: TileMapLayer, map: Dictionary, size: Vector2i, title: String) -> Image:
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	viewport.add_child(camera)
	var content := Node2D.new()
	viewport.add_child(content)
	var water := TileMapLayer.new()
	water.tile_set = _layers_tiles
	var grounds := Node2D.new()
	grounds.scale = Vector2.ONE * (float(CELL) / ART)
	content.add_child(grounds)
	grounds.add_child(water)
	for cell: Vector2i in map:
		water.set_cell(cell, _water_source, LayersLab.FULL, LayersLab.SHALLOW)
	grounds.add_child(layer)
	_outline(content, map, size)
	var image := await _grab(viewport, camera, Rect2(Vector2.ZERO, Vector2(size) * CELL), 0.5, title)
	viewport.free()
	return image


# --- Test 4: a real world ------------------------------------------------------------------------

func _test_world() -> void:
	_report.append("## 4. A real world: level-1")
	_report.append("")
	var scene := load(WORLD) as PackedScene
	var world := scene.instantiate()
	var source := world.get_node(WORLD_GROUND) as TileMapLayer
	var map := {}
	for cell in source.get_used_cells():
		map[cell] = str(source.get_cell_tile_data(cell).get_custom_data(TILE_ID))
	var size := Vector2i(int(source.get_meta("columns")), int(source.get_meta("rows")))
	world.free()

	var systems := {}
	for system: String in ["dual", "godot A", "godot B"]:
		print("compare_terrain_edges: level-1, %s" % system)
		systems[system] = _build(system, map, size)
	var crop := _busiest(map, size)
	var calls := await _draw_calls(systems, crop)
	_report.append("%d x %d cells. *Build* is the time to place every tile (dual: the water surface and TerrainEdges.mount; Godot: one set_cells_terrain_connect per ground). *Draw calls* are for a game-sized view (cells %s at zoom 1, 1280 x 768) minus an empty frame; the dual grid's include the plain ground layer under the edges." % [size.x, size.y, crop])
	_report.append("")
	_report.append("| System | Build (ms) | Tiles | Layers | Draw calls |")
	_report.append("|---|---|---|---|---|")
	for system: String in systems:
		var built: Dictionary = systems[system]
		_report.append("| %s | %.0f | %d | %d | %d |" % [_system_title(system), built.msec, built.tiles, built.layers, calls[system]])
		if system == "dual":
			_report.append("| ... of which the plain ground layer and water surface | - | - | - | %d |" % calls["dual ground only"])
	_report.append("")
	_report.append("| Shape | System | Right | Wrong ground | Holes | Land on water | Water on land | Shore offset | Seams | Painted cells lost |")
	_report.append("|---|---|---|---|---|---|---|---|---|---|")
	for system: String in systems:
		var built: Dictionary = systems[system]
		var metrics := _coverage(built.stack, map, size, WORLD_SAMPLES)
		metrics["seams"] = built.get("seams", 0)
		metrics["lost"] = built.get("lost", 0)
		_report.append(_metrics_row("level-1", system, metrics, true))
	_report.append("")

	var overview: Array[Image] = []
	var close: Array[Image] = []
	for system: String in systems:
		var built: Dictionary = systems[system]
		overview.append(await _grab(built.viewport, built.camera, Rect2(Vector2.ZERO, Vector2(size) * CELL), 0.18, _system_title(system)))
		_outline(built.content, map, size)
		close.append(await _grab(built.viewport, built.camera, Rect2(Vector2(crop.position) * CELL, Vector2(crop.size) * CELL), 0.75, "%s, cells %s" % [_system_title(system), crop]))
		built.viewport.free()
	_compose(overview, 3).save_png(ProjectSettings.globalize_path(_out.path_join("4-level-1.png")))
	_compose(close, 1).save_png(ProjectSettings.globalize_path(_out.path_join("4-level-1-close.png")))
	_report.append("![level-1](4-level-1.png)")
	_report.append("")
	_report.append("![level-1 up close](4-level-1-close.png) Red lines: the collision line; white: other ground changes.")
	_report.append("")


## Draw calls with `view` (cells) on screen at zoom 1, per system, minus a frame with nothing on it.
func _draw_calls(systems: Dictionary, view: Rect2i) -> Dictionary:
	var calls := {}
	var baseline := await _frame_draw_calls(null, view)
	for system: String in systems:
		calls[system] = maxi(0, await _frame_draw_calls(systems[system], view) - baseline)
	# The dual grid's plain ground layer and water surface alone, edges hidden.
	var edges := (systems["dual"].content as Node).get_child(0).get_node(^"TerrainEdges") as CanvasItem
	edges.visible = false
	calls["dual ground only"] = maxi(0, await _frame_draw_calls(systems["dual"], view) - baseline)
	edges.visible = true
	return calls


func _frame_draw_calls(built: Variant, view: Rect2i) -> int:
	if built != null:
		var viewport: SubViewport = built.viewport
		var camera: Camera2D = built.camera
		viewport.size = view.size * CELL
		camera.position = Vector2(view.position * CELL)
		camera.zoom = Vector2.ONE
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var most := 0
	for i in 6:
		await process_frame
		if i >= 3:
			most = maxi(most, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	if built != null:
		(built.viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	return most


## The CROP-sized window with the most ground changes between neighbouring cells.
func _busiest(map: Dictionary, size: Vector2i) -> Rect2i:
	var truth := _truth(map)
	var best := Rect2i(Vector2i.ZERO, CROP)
	var most := -1
	for y in range(0, maxi(1, size.y - CROP.y + 1), 2):
		for x in range(0, maxi(1, size.x - CROP.x + 1), 2):
			var changes := 0
			for cy in range(y, y + CROP.y):
				for cx in range(x, x + CROP.x):
					var cell := Vector2i(cx, cy)
					for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
						if truth.has(cell + offset) and truth.get(cell) != truth[cell + offset]:
							changes += 1
			if changes > most:
				most = changes
				best = Rect2i(Vector2i(x, y), CROP)
	return best


# --- Pictures ------------------------------------------------------------------------------------

## Renders `rect` (world units) of a built viewport at `zoom`, with `title` written in the corner.
func _grab(viewport: SubViewport, camera: Camera2D, rect: Rect2, zoom: float, title: String) -> Image:
	viewport.size = Vector2i(ceili(rect.size.x * zoom), ceili(rect.size.y * zoom) + 28)
	camera.position = rect.position - Vector2(0, 28 / zoom)
	camera.zoom = Vector2(zoom, zoom)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = title
	label.position = Vector2(6, 2)
	label.add_theme_font_size_override(&"font_size", 18)
	layer.add_child(label)
	viewport.add_child(layer)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in 4:
		await process_frame
	var image := viewport.get_texture().get_image()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	layer.free()
	return image


## Lines along the cell sides where the ground changes: red where water meets walkable ground (the
## collision line), white elsewhere.
func _outline(parent: Node, map: Dictionary, size: Vector2i) -> void:
	var truth := _truth(map)
	var collision := PackedVector2Array()
	var other := PackedVector2Array()
	for cell: Vector2i in truth:
		var right := cell + Vector2i(1, 0)
		var below := cell + Vector2i(0, 1)
		if right.x < size.x and truth[cell] != truth[right]:
			var segment := [Vector2(right) * CELL, Vector2(right + Vector2i(0, 1)) * CELL]
			if _is_shore(truth[cell], truth[right]):
				collision.append_array(segment)
			else:
				other.append_array(segment)
		if below.y < size.y and truth[cell] != truth[below]:
			var segment := [Vector2(below) * CELL, Vector2(below + Vector2i(1, 0)) * CELL]
			if _is_shore(truth[cell], truth[below]):
				collision.append_array(segment)
			else:
				other.append_array(segment)
	for lines: Array in [[other, GROUND_LINE], [collision, COLLISION_LINE]]:
		var drawer := Node2D.new()
		drawer.set_script(_line_script())
		drawer.set(&"segments", lines[0])
		drawer.set(&"color", lines[1])
		drawer.z_index = 10
		parent.add_child(drawer)


var _lines: GDScript


func _line_script() -> GDScript:
	if _lines == null:
		_lines = GDScript.new()
		_lines.source_code = "extends Node2D\nvar segments := PackedVector2Array()\nvar color := Color.WHITE\nfunc _draw() -> void:\n\tif not segments.is_empty():\n\t\tdraw_multiline(segments, color, 1.5)\n"
		_lines.reload()
	return _lines


## Puts `images` on a grid of `columns`, with a gap.
func _compose(images: Array[Image], columns: int) -> Image:
	var gap := 12
	var cell_size := Vector2i.ZERO
	for image in images:
		cell_size = Vector2i(maxi(cell_size.x, image.get_width()), maxi(cell_size.y, image.get_height()))
	var rows := ceili(float(images.size()) / columns)
	var out := Image.create_empty(columns * cell_size.x + (columns + 1) * gap, rows * cell_size.y + (rows + 1) * gap, false, Image.FORMAT_RGBA8)
	out.fill(BACKGROUND)
	for i in images.size():
		var image := images[i]
		image.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(gap + (i % columns) * (cell_size.x + gap), gap + (i / columns) * (cell_size.y + gap))
		out.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	return out
