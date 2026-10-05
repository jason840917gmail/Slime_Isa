extends SceneTree
## Builds the terrain layers lab (docs/godot/TERRAIN_LAB.md): res://game/dev/terrain_lab/
## terrain_layers_lab.tscn, the terrain lab's layout drawn with Godot's own Terrains instead of
## TerrainEdges, to compare the two.
##
## Its tile set (terrain_layers_tileset.tres) has one terrain set in Match Corners mode with a
## terrain per ground. Each ground's 16 hand-made edge tiles are tagged the way you would tag them
## by hand in the TileSet editor: the centre is the ground, and a corner is the ground where the
## tile's art covers it. Every ground has its own TileMapLayer, stacked in TerrainMaterials.ORDER
## (water at the bottom, crystal on top). The cells are painted with set_cells_terrain_connect,
## which is what the TileMap panel's Terrains tab does in Connect mode, so Godot picks every tile.
## Water has no edge art: its layer holds plain full tiles (paint it from the Tiles tab).
##
## Two copies of the layout: A paints each ground only on its own cells; B also paints every
## ground under the grounds above it (a base layer under each patch).
##
## Run with the Godot 4.7.2 console exe (needs the art imported):
##     --headless --path godot -s res://tools/build_terrain_layers_lab.gd
## Safe to re-run: it rewrites the scene and its tile set (paint you added is lost).

const TerrainLab := preload("res://tools/build_terrain_lab.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const LAB_DIR := "res://game/dev/terrain_lab/"
const SCENE_PATH := LAB_DIR + "terrain_layers_lab.tscn"
const TILESET_PATH := LAB_DIR + "terrain_layers_tileset.tres"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const EDGE_SHADER := "res://game/world/terrain_edges/terrain_edge.gdshader"
const TILE_ID_DATA_LAYER := "tile_id"
const CELL := 64
## Edge art: 128 px tiles with a 2 px gutter (as TerrainEdges), drawn at half scale.
const ART_TILE := 128
const GUTTER := 2
const SHEET_CELLS := 19
const TERRAIN_SET := 0
## Empty rows between copy A and copy B.
const GAP_ROWS := 3
## The full tile of a 4 x 4 edge sheet (all four corners covered); water uses it as a plain tile.
const FULL := Vector2i(3, 3)
## Water alternatives of the full tile.
const SHALLOW := 0
const DEEP := 1
## The edge sheet whose full tile carries the water material (any ground's would do).
const WATER_TILE_SHEET := "sanddessert"
## An edge tile's corners, in the order of the bits of its sheet index (TL + 2 TR + 4 BL + 8 BR).
const CORNERS: Array[TileSet.CellNeighbor] = [
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
]
## Ground -> layer and terrain name.
const NAMES := {
	"water": "Water", "cavern-floor": "Cavern floor", "forest-floor": "Forest floor",
	"sanddessert": "Sand", "highland": "Grass", "amberleaf": "Fallen leaves", "frozen": "Snow",
	"town-cobble": "Cobble", "forest-moss": "Moss", "crystal-floor": "Crystal",
}
## Ground -> the colour the editor paints its terrain bits with.
const COLORS := {
	"cavern-floor": Color("4a5468"), "forest-floor": Color("6b4a2b"), "sanddessert": Color("e8c25a"),
	"highland": Color("6fb03a"), "amberleaf": Color("d2702a"), "frozen": Color("e8f2ff"),
	"town-cobble": Color("a59a86"), "forest-moss": Color("2f6b2a"), "crystal-floor": Color("8a5ad8"),
}


func _initialize() -> void:
	quit(0 if _build() else 1)


func _build() -> bool:
	for path: String in [TERRAIN_TILESET, EDGE_SHADER]:
		if not ResourceLoader.exists(path):
			push_error("build_terrain_layers_lab: %s is missing" % path)
			return false
	var sheets := _ground_sheets(load(TERRAIN_TILESET) as TileSet)
	for ground: String in TerrainMaterials.ORDER:
		if not sheets.has(ground):
			push_error("build_terrain_layers_lab: no ground sheet for '%s'" % ground)
			return false
		if ground != TerrainMaterials.WATER and not ResourceLoader.exists(TerrainMaterials.edges_path(ground)):
			push_error("build_terrain_layers_lab: no edge art for '%s'" % ground)
			return false

	var built := _tile_set(sheets)
	var tile_set: TileSet = built.tile_set
	var result := ResourceSaver.save(tile_set, TILESET_PATH)
	if result != OK:
		push_error("build_terrain_layers_lab: saving the tile set failed (%d)" % result)
		return false
	# The scene refers to the saved file instead of embedding a copy.
	tile_set.take_over_path(TILESET_PATH)

	var root := Node2D.new()
	root.name = "TerrainLayersLab"
	var grounds := Node2D.new()
	grounds.name = "Grounds"
	grounds.scale = Vector2.ONE * (float(CELL) / ART_TILE)
	root.add_child(grounds)
	var layers := {}
	for order in TerrainMaterials.ORDER.size():
		var ground := TerrainMaterials.ORDER[order]
		var layer := TileMapLayer.new()
		layer.name = "%d %s" % [order, NAMES[ground]]
		layer.tile_set = tile_set
		grounds.add_child(layer)
		layers[ground] = layer

	var size := Vector2i(TerrainLab.MAP[0].length(), TerrainLab.MAP.size())
	var top_b := size.y + GAP_ROWS
	_paint(layers, built, Vector2i.ZERO, false)
	_paint(layers, built, Vector2i(0, top_b), true)

	_add_label(root, "A: each ground painted only on its own cells", Vector2(0, -96))
	_add_label(root, "B: each ground also painted under the grounds above it", Vector2(0, top_b * CELL - 96))
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2(size.x * CELL * 0.5, (top_b + size.y) * CELL * 0.5 - 48)
	camera.zoom = Vector2(0.32, 0.32)
	# Physics interpolation is on: the camera would switch itself to physics mode with a warning.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(camera)

	_own(root, root)
	var scene := PackedScene.new()
	result = scene.pack(root)
	if result == OK:
		result = ResourceSaver.save(scene, SCENE_PATH)
	for ground: String in TerrainMaterials.ORDER:
		var layer: TileMapLayer = layers[ground]
		print("  %s: %d tiles" % [layer.name, layer.get_used_cells().size()])
	root.free()
	if result != OK:
		push_error("build_terrain_layers_lab: saving the scene failed (%d)" % result)
		return false
	print("build_terrain_layers_lab: saved %s and %s" % [SCENE_PATH, TILESET_PATH])
	return true


## Ground -> its 19 x 19 sheet in the converted terrain tile set, plus "deep-water".
func _ground_sheets(terrain_tile_set: TileSet) -> Dictionary:
	var sheets := {}
	for i in terrain_tile_set.get_source_count():
		var source := terrain_tile_set.get_source(terrain_tile_set.get_source_id(i)) as TileSetAtlasSource
		if source == null or source.get_tiles_count() == 0:
			continue
		var tile_id := str(source.get_tile_data(source.get_tile_id(0), 0).get_custom_data(TILE_ID_DATA_LAYER))
		var ground := "deep-water" if tile_id == "deep-water" else TerrainMaterials.ground_of(tile_id)
		if ground != "" and not sheets.has(ground) and tile_id in TerrainLab.KEY.values():
			sheets[ground] = source.texture
	return sheets


## The lab's tile set: one Match Corners terrain set (a terrain per land ground), a source per land
## ground with its 16 edge tiles tagged, and a water source (the full tile, shallow and deep).
## Returns {tile_set, water_source, terrain_of (ground -> terrain index)}.
func _tile_set(sheets: Dictionary) -> Dictionary:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(ART_TILE, ART_TILE)
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(TERRAIN_SET, TileSet.TERRAIN_MODE_MATCH_CORNERS)

	var water_source := _add_source(tile_set, TerrainMaterials.edges_path(WATER_TILE_SHEET))
	var water := tile_set.get_source(water_source) as TileSetAtlasSource
	water.resource_name = NAMES[TerrainMaterials.WATER]
	water.create_tile(FULL)
	water.create_alternative_tile(FULL, DEEP)
	water.get_tile_data(FULL, SHALLOW).material = _material(sheets[TerrainMaterials.WATER], WATER_TILE_SHEET)
	water.get_tile_data(FULL, DEEP).material = _material(sheets["deep-water"], WATER_TILE_SHEET)

	var terrain_of := {}
	for ground: String in TerrainMaterials.ORDER:
		if ground == TerrainMaterials.WATER:
			continue
		var terrain := tile_set.get_terrains_count(TERRAIN_SET)
		tile_set.add_terrain(TERRAIN_SET)
		tile_set.set_terrain_name(TERRAIN_SET, terrain, NAMES[ground])
		tile_set.set_terrain_color(TERRAIN_SET, terrain, COLORS[ground])
		terrain_of[ground] = terrain

		var source := tile_set.get_source(_add_source(tile_set, TerrainMaterials.edges_path(ground))) as TileSetAtlasSource
		source.resource_name = NAMES[ground]
		var material := _material(sheets[ground], ground)
		for index in 16:
			var atlas := Vector2i(index % 4, index / 4)
			source.create_tile(atlas)
			var data := source.get_tile_data(atlas, 0)
			data.material = material
			data.terrain_set = TERRAIN_SET
			data.terrain = terrain
			for bit in CORNERS.size():
				if index & (1 << bit):
					data.set_terrain_peering_bit(CORNERS[bit], terrain)
	return {"tile_set": tile_set, "water_source": water_source, "terrain_of": terrain_of}


func _add_source(tile_set: TileSet, edges_path: String) -> int:
	var source := TileSetAtlasSource.new()
	source.texture = load(edges_path) as Texture2D
	source.texture_region_size = Vector2i(ART_TILE, ART_TILE)
	source.margins = Vector2i(GUTTER, GUTTER)
	source.separation = Vector2i(2 * GUTTER, 2 * GUTTER)
	# The shader reads the rim weights at the same UV, so the atlas must not be re-padded.
	source.use_texture_padding = false
	return tile_set.add_source(source)


## The edge shader on `sheet` (the ground drawn in world space), with `rim_ground`'s rim weights.
func _material(sheet: Texture2D, rim_ground: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(EDGE_SHADER)
	material.set_shader_parameter(&"ground_texture", sheet)
	material.set_shader_parameter(&"rim_weight", load(TerrainMaterials.rim_path(rim_ground)))
	material.set_shader_parameter(&"ground_period", float(CELL * SHEET_CELLS))
	material.set_shader_parameter(&"ground_origin", Vector2.ZERO)
	return material


## Paints the terrain lab's map at `offset` (cells): water as plain tiles, every land ground with
## Godot's terrain painter on its own layer. `under` also paints each ground under the grounds
## stacked above it. Rock wall has no edge art and is painted as cavern floor.
func _paint(layers: Dictionary, built: Dictionary, offset: Vector2i, under: bool) -> void:
	var order_at := {}
	var deep := {}
	for y in TerrainLab.MAP.size():
		var line: String = TerrainLab.MAP[y]
		for x in line.length():
			var tile_id: String = TerrainLab.KEY[line[x]]
			var ground := TerrainMaterials.ground_of(tile_id)
			var cell := offset + Vector2i(x, y)
			order_at[cell] = TerrainMaterials.order_of(ground if ground != "" else "cavern-floor")
			deep[cell] = tile_id == "deep-water"
	var water: TileMapLayer = layers[TerrainMaterials.WATER]
	for cell: Vector2i in order_at:
		if order_at[cell] == 0 or under:
			water.set_cell(cell, built.water_source, FULL, DEEP if deep[cell] else SHALLOW)
	for order in range(1, TerrainMaterials.ORDER.size()):
		var ground := TerrainMaterials.ORDER[order]
		var cells: Array[Vector2i] = []
		for cell: Vector2i in order_at:
			if order_at[cell] == order or (under and order_at[cell] > order):
				cells.append(cell)
		if not cells.is_empty():
			(layers[ground] as TileMapLayer).set_cells_terrain_connect(cells, TERRAIN_SET, built.terrain_of[ground])


func _add_label(root: Node, text: String, at: Vector2) -> void:
	var label := Label.new()
	label.name = "Label%d" % root.get_child_count()
	label.text = text
	label.position = at
	label.add_theme_font_size_override(&"font_size", 56)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 10)
	root.add_child(label)


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
