extends SceneTree
## Builds the terrain lab (docs/godot/TERRAIN_LAB.md): res://game/dev/terrain_lab/terrain_lab.tscn
## with two tile sets and two materials, and paints the same test shape twice:
##   - HardEdges (x 0): today's look. 64 px sheets, Phaser's sheet-wrap frames, hard cell edges.
##   - EdgeTiles (x 1216): 128 px art (layer scale 0.5, so cells stay 64 units). `Ground` holds
##     one swatch tile per ground, drawn from its sheet in world space (ground_world.gdshader);
##     `SnowEdges` is the dual-grid overlay (game/world/terrain_edges/terrain_edges.gd) that
##     picks the hand-made snow edge tiles from the Ground cells around each corner.
## The art comes from scripts/art/build-terrain-edge-tiles.py. Edge tile index =
## TL + 2*TR + 4*BL + 8*BR (1 = that ground cell is snow), at atlas (index % 4, index / 4).
##
## Run with the Godot 4.7.2 console exe (the art must be imported first; an open editor
## imports it on its next filesystem scan):
##     --headless --path godot -s res://tools/build_terrain_lab.gd
## Safe to re-run: it rewrites the lab scene, tile sets and materials (paint you added is lost).

const LAB_DIR := "res://game/dev/terrain_lab/"
const SCENE_PATH := LAB_DIR + "terrain_lab.tscn"
const LAB_SCRIPT := LAB_DIR + "terrain_lab.gd"
const HARD_TILESET_PATH := LAB_DIR + "terrain_lab_hard.tres"
const EDGE_TILESET_PATH := LAB_DIR + "terrain_lab_edges.tres"
const EDGE_MATERIAL_PATH := LAB_DIR + "terrain_lab_snow_over_sand.tres"
const SAND_MATERIAL_PATH := LAB_DIR + "terrain_lab_sand_world.tres"
const FROZEN_MATERIAL_PATH := LAB_DIR + "terrain_lab_frozen_world.tres"
const EDGES_SCRIPT := "res://game/world/terrain_edges/terrain_edges.gd"
const EDGES_SHADER := "res://game/world/terrain_edges/terrain_edges.gdshader"
const GROUND_SHADER := "res://game/world/terrain_edges/ground_world.gdshader"

const SAND_64 := "res://asset/MAPS/grounds/64x64-tile_19x19_sanddessert.webp"
const FROZEN_64 := "res://asset/MAPS/grounds/64x64-tile_19x19_frozen.webp"
const SAND_128 := LAB_DIR + "art/128x128-tile_19x19_sanddessert.webp"
const FROZEN_128 := LAB_DIR + "art/128x128-tile_19x19_frozen.webp"
const EDGES := LAB_DIR + "art/128x128-tile_4x4_snow-edges.png"
const EDGES_RIM := LAB_DIR + "art/128x128-tile_4x4_snow-edges-rim.png"

## World units per cell; the ground sheets repeat every 19 cells.
const CELL := 64
const SHEET_CELLS := 19
const GROUND_PERIOD := float(CELL * SHEET_CELLS)
## The second panel starts one sheet period to the right.
const EDGE_PANEL_X := CELL * SHEET_CELLS
const GUTTER := 2

## Source ids (both tile sets).
const SAND := 0
const FROZEN := 1
const SNOW_EDGES := 2

## The painted test shape ("#" = snow): straight sides, convex and concave corners, a ring
## around a one-cell hole, a one-cell gap, a lone cell and two cells touching at a corner.
const SHAPE := [
	"..................",
	"..####............",
	"..#####.....##....",
	"..######...###....",
	"...#####...###....",
	"....###...........",
	"..........#....#..",
	"...####....#......",
	"...#.##...........",
	"...####...........",
	"..................",
	"..................",
]


func _initialize() -> void:
	quit(0 if _build() else 1)


func _build() -> bool:
	for path: String in [SAND_64, FROZEN_64, SAND_128, FROZEN_128, EDGES, EDGES_RIM,
			EDGES_SCRIPT, EDGES_SHADER, GROUND_SHADER, LAB_SCRIPT]:
		if not ResourceLoader.exists(path):
			push_error("build_terrain_lab: %s is missing (not imported yet?)" % path)
			return false

	var sand_material := _world_material(SAND_128, SAND_MATERIAL_PATH)
	var frozen_material := _world_material(FROZEN_128, FROZEN_MATERIAL_PATH)
	var edge_material := ShaderMaterial.new()
	edge_material.shader = load(EDGES_SHADER) as Shader
	edge_material.set_shader_parameter(&"upper_texture", load(FROZEN_128))
	edge_material.set_shader_parameter(&"lower_texture", load(SAND_128))
	edge_material.set_shader_parameter(&"rim_weight", load(EDGES_RIM))
	edge_material.set_shader_parameter(&"ground_period", GROUND_PERIOD)
	edge_material = _saved(edge_material, EDGE_MATERIAL_PATH) as ShaderMaterial
	if sand_material == null or frozen_material == null or edge_material == null:
		return false

	var hard_set := _saved(_sheet_tile_set(), HARD_TILESET_PATH) as TileSet
	var edge_set := _saved(_edge_tile_set(sand_material, frozen_material), EDGE_TILESET_PATH) as TileSet
	if hard_set == null or edge_set == null:
		return false

	var root := Node2D.new()
	root.name = "TerrainLab"
	root.set_script(load(LAB_SCRIPT))
	var snow_cells := _shape_cells()
	var size := Vector2i(SHAPE[0].length(), SHAPE.size())

	# Panel 1: today's hard edges (Phaser sheet-wrap frames).
	var hard := _panel(root, "HardEdges", Vector2.ZERO, "Today: 64 px art, hard cell edges")
	var hard_ground := _layer(hard, "Ground", hard_set, 1.0)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			hard_ground.set_cell(cell, FROZEN if cell in snow_cells else SAND,
					Vector2i(posmod(x, SHEET_CELLS), posmod(y, SHEET_CELLS)))

	# Panel 2: 128 px swatches + the dual-grid snow edges.
	var edges := _panel(root, "EdgeTiles", Vector2(EDGE_PANEL_X, 0), "128 px art + hand-made snow edge tiles")
	var ground := _layer(edges, "Ground", edge_set, 0.5)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			ground.set_cell(cell, FROZEN if cell in snow_cells else SAND, Vector2i.ZERO)
	var snow := _layer(edges, "SnowEdges", edge_set, 0.5)
	snow.set_script(load(EDGES_SCRIPT))
	snow.set(&"upper_sources", PackedInt32Array([FROZEN]))
	snow.set(&"edge_source", SNOW_EDGES)
	snow.set(&"ground", ground)
	snow.material = edge_material
	var placed: int = snow.call(&"rebuild")

	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2((EDGE_PANEL_X + size.x * CELL) * 0.5, size.y * CELL * 0.5)
	camera.zoom = Vector2(0.55, 0.55)
	root.add_child(camera)

	_own(root, root)
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result == OK:
		result = ResourceSaver.save(scene, SCENE_PATH)
	root.free()
	if result != OK:
		push_error("build_terrain_lab: saving the scene failed (%d)" % result)
		return false
	print("build_terrain_lab: saved %s (%d snow cells, %d edge tiles)" % [SCENE_PATH, snow_cells.size(), placed])
	return true


## Today's sheets: every frame of the 64 px sand and frozen sheets (sources SAND, FROZEN).
func _sheet_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(CELL, CELL)
	for entry: Array in [[SAND, SAND_64], [FROZEN, FROZEN_64]]:
		var source := TileSetAtlasSource.new()
		source.texture = load(entry[1]) as Texture2D
		source.texture_region_size = Vector2i(CELL, CELL)
		tile_set.add_source(source, entry[0])
		for y in SHEET_CELLS:
			for x in SHEET_CELLS:
				source.create_tile(Vector2i(x, y))
	return tile_set


## 128 px tile set: one swatch per ground (SAND, FROZEN; drawn in world space by their
## materials) and the 16 snow edge tiles (SNOW_EDGES).
func _edge_tile_set(sand_material: Material, frozen_material: Material) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(128, 128)
	for entry: Array in [[SAND, SAND_128, sand_material], [FROZEN, FROZEN_128, frozen_material]]:
		var source := TileSetAtlasSource.new()
		source.texture = load(entry[1]) as Texture2D
		source.texture_region_size = Vector2i(128, 128)
		tile_set.add_source(source, entry[0])
		source.create_tile(Vector2i.ZERO)
		source.get_tile_data(Vector2i.ZERO, 0).material = entry[2]
	var edges := TileSetAtlasSource.new()
	edges.texture = load(EDGES) as Texture2D
	edges.texture_region_size = Vector2i(128, 128)
	edges.margins = Vector2i(GUTTER, GUTTER)
	edges.separation = Vector2i(2 * GUTTER, 2 * GUTTER)
	# The shader reads rim weights at the same UV, so the atlas must not be re-padded.
	edges.use_texture_padding = false
	tile_set.add_source(edges, SNOW_EDGES)
	for index in 16:
		edges.create_tile(Vector2i(index % 4, index / 4))
	return tile_set


func _world_material(texture_path: String, save_path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(GROUND_SHADER) as Shader
	material.set_shader_parameter(&"ground_texture", load(texture_path))
	material.set_shader_parameter(&"ground_period", GROUND_PERIOD)
	return _saved(material, save_path) as ShaderMaterial


## Saves `resource` at `path` and returns the loaded copy (so scenes reference the file).
func _saved(resource: Resource, path: String) -> Resource:
	if ResourceSaver.save(resource, path) != OK:
		push_error("build_terrain_lab: cannot save %s" % path)
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


func _panel(root: Node2D, panel_name: String, at: Vector2, caption: String) -> Node2D:
	var panel := Node2D.new()
	panel.name = panel_name
	panel.position = at
	root.add_child(panel)
	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.position = Vector2(0, -72)
	label.add_theme_font_size_override(&"font_size", 40)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 8)
	panel.add_child(label)
	return panel


func _layer(parent: Node, layer_name: String, tile_set: TileSet, layer_scale: float) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.scale = Vector2(layer_scale, layer_scale)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(layer)
	return layer


func _shape_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in SHAPE.size():
		var line: String = SHAPE[y]
		for x in line.length():
			if line[x] == "#":
				cells.append(Vector2i(x, y))
	return cells


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
