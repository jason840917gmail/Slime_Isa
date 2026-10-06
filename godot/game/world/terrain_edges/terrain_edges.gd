@tool
extends Node2D
## Hand-made terrain transitions over a ground TileMapLayer (docs/godot/TERRAIN_LAB.md).
##
## `TerrainEdges.mount(ground)` adds this node as the child "TerrainEdges" of the ground layer
## (after the water surface, so it draws over it) with LEVELS TileMapLayers on a dual grid: each
## of their cells sits on a corner shared by four ground cells (the node is half a cell up and
## left; 128 px art at scale 0.5). Where different grounds meet at a corner, level 0 fills the
## corner with the lowest of them (its fully covered tile, or the animated water) and each higher
## ground draws its edge tile on the next level: index = TL + 2*TR + 4*BL + 8*BR, with 1 where the
## cell's ground stacks at least that high (TerrainMaterials.ORDER). Corners touching a tile without
## edges (walls, interior floors), the map's border, or a ground without art keep hard edges, and
## so do corners where the elevation layer has different levels (the cliff draws its own rims there,
## docs/godot/ELEVATION.md).
##
## This script only picks tiles; the art (scripts/art/build-terrain-edge-tiles.py) and the shaders
## (terrain_edge.gdshader, terrain_edge_water.gdshader) do the rest. Visual only: the ground cells
## stay the gameplay truth. Built on mount; in the editor also whenever the ground is painted, which
## first snaps painted sheet frames to the cell's sheet-wrap frame (x mod 19, y mod 19).
##
## Owner: world (terrain edges).

const Self := preload("res://game/world/terrain_edges/terrain_edges.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const LAND_SHADER := preload("res://game/world/terrain_edges/terrain_edge.gdshader")
const WATER_SHADER := preload("res://game/world/terrain_edges/terrain_edge_water.gdshader")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const NODE_NAME := "TerrainEdges"
const WATER_SURFACE_NODE := "WaterSurface"
## The most grounds that can meet at one corner.
const LEVELS := 4
## Edge art: 128 px tiles with a 2 px gutter (atlas margins 2, separation 4).
const ART_TILE := 128
const GUTTER := 2
const TILE_ID_DATA_LAYER := "tile_id"
## Ground sheets wrap every 19 cells (Phaser sheet-wrap).
const SHEET_CELLS := 19
const TL := 1
const TR := 2
const BL := 4
const BR := 8
const FULL := 15

## The ground layer (the parent).
var ground: TileMapLayer
## The dual-grid layers, bottom first.
var layers: Array[TileMapLayer] = []
## Edge tiles placed by the last build, over all levels.
var placed: int = 0
## Corners that got edge tiles by the last build.
var corners: int = 0
## ground -> source id in the edge tile set (grounds with art present in this world).
var sources: Dictionary = {}

var _queued := false
var _snapping := false


## Mounts the edges on `layer` (a second call rebuilds the existing node). Null when the layer has
## no tile set with `tile_id` data, or a rotated or scaled transform (as the water surface).
static func mount(layer: TileMapLayer) -> Self:
	if layer == null or layer.tile_set == null or not layer.tile_set.has_custom_data_layer_by_name(TILE_ID_DATA_LAYER):
		return null
	var transform := layer.get_global_transform() if layer.is_inside_tree() else layer.transform
	if not is_zero_approx(transform.get_rotation()) or not transform.get_scale().is_equal_approx(Vector2.ONE):
		return null
	var edges := layer.get_node_or_null(NodePath(NODE_NAME)) as Self
	if edges == null:
		edges = Self.new()
		edges.name = NODE_NAME
		edges.ground = layer
		layer.add_child(edges)
	edges.ground = layer
	edges.rebuild()
	return edges


func _enter_tree() -> void:
	if Engine.is_editor_hint() and ground != null and not ground.changed.is_connected(_on_ground_changed):
		ground.changed.connect(_on_ground_changed)


func _exit_tree() -> void:
	if ground != null and ground.changed.is_connected(_on_ground_changed):
		ground.changed.disconnect(_on_ground_changed)


## Rebuilds every edge tile from the ground's cells. Returns the number of tiles placed.
func rebuild() -> int:
	_queued = false
	placed = 0
	corners = 0
	if ground == null or ground.tile_set == null:
		return 0
	var cell_size := Vector2(ground.tile_set.tile_size)
	position = -cell_size * 0.5
	var used := ground.get_used_rect()
	var columns := int(ground.get_meta("columns", used.end.x))
	var rows := int(ground.get_meta("rows", used.end.y))

	# Each cell's ground, through its source's tile id (one lookup per source).
	var ground_by_source := {}
	var sheets := {}
	var cell_ground := {}
	for cell: Vector2i in ground.get_used_cells():
		var source_id := ground.get_cell_source_id(cell)
		if not ground_by_source.has(source_id):
			var data := ground.get_cell_tile_data(cell)
			var tile_id := str(data.get_custom_data(TILE_ID_DATA_LAYER)) if data != null else ""
			var name_of_ground := TerrainMaterials.ground_of(tile_id)
			ground_by_source[source_id] = name_of_ground
			if name_of_ground != "" and not sheets.has(name_of_ground):
				var source := ground.tile_set.get_source(source_id) as TileSetAtlasSource
				if source != null:
					sheets[name_of_ground] = source.texture
		cell_ground[cell] = ground_by_source[source_id]

	var tile_set := _edge_tile_set(sheets)
	_ensure_layers(tile_set)
	# Stack order per cell; -1 = no edges (wall, floor, no art) and -2 = no cell.
	var order_of := {}
	for name_of_ground: String in sheets:
		order_of[name_of_ground] = TerrainMaterials.order_of(name_of_ground) if sources.has(name_of_ground) else -1
	var levels := Elevation.painted_levels(ground)
	for cy in range(1, rows):
		for cx in range(1, columns):
			if not levels.is_empty() and not _same_level(levels, Vector2i(cx, cy)):
				continue
			var around: Array[int] = [
				_order_at(cell_ground, order_of, Vector2i(cx - 1, cy - 1)), _order_at(cell_ground, order_of, Vector2i(cx, cy - 1)),
				_order_at(cell_ground, order_of, Vector2i(cx - 1, cy)), _order_at(cell_ground, order_of, Vector2i(cx, cy)),
			]
			if around.min() < 0:
				continue
			var stack: Array[int] = []
			for order in around:
				if not stack.has(order):
					stack.append(order)
			if stack.size() < 2:
				continue
			stack.sort()
			var corner := Vector2i(cx, cy)
			for level in stack.size():
				var name_of_ground := TerrainMaterials.ORDER[stack[level]]
				var index := FULL
				if level > 0:
					index = 0
					var bits: Array[int] = [TL, TR, BL, BR]
					for i in 4:
						if around[i] >= stack[level]:
							index |= bits[i]
				var atlas := Vector2i.ZERO if name_of_ground == TerrainMaterials.WATER else Vector2i(index % 4, index / 4)
				layers[level].set_cell(corner, sources[name_of_ground], atlas)
				placed += 1
			corners += 1
	return placed


## Queues a rebuild for the end of the frame (painting sends many changes).
func queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	rebuild.call_deferred()


## True when the four cells around corner `corner` share one painted elevation level.
static func _same_level(levels: Dictionary, corner: Vector2i) -> bool:
	var level := int(levels.get(corner, 0))
	for cell: Vector2i in [corner + Vector2i(-1, -1), corner + Vector2i(0, -1), corner + Vector2i(-1, 0)]:
		if int(levels.get(cell, 0)) != level:
			return false
	return true


func _order_at(cell_ground: Dictionary, order_of: Dictionary, cell: Vector2i) -> int:
	if not cell_ground.has(cell):
		return -2
	var name_of_ground: String = cell_ground[cell]
	return int(order_of.get(name_of_ground, -1)) if name_of_ground != "" else -1


## The edge tile set for this world: one source per ground with art (16 tiles, the land shader on
## that ground's sheet) plus one water source (one opaque tile, the water shader) when the ground
## has a mounted water surface. Fills `sources`.
func _edge_tile_set(sheets: Dictionary) -> TileSet:
	sources.clear()
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(ART_TILE, ART_TILE)
	var origin := ground.global_position if ground.is_inside_tree() else ground.position
	for name_of_ground: String in sheets:
		if name_of_ground == TerrainMaterials.WATER:
			var water := _water_material(origin)
			if water != null:
				sources[name_of_ground] = _add_source(tile_set, _opaque_texture(), water, [Vector2i.ZERO])
			continue
		var edges_path := TerrainMaterials.edges_path(name_of_ground)
		var rim_path := TerrainMaterials.rim_path(name_of_ground)
		if not ResourceLoader.exists(edges_path) or not ResourceLoader.exists(rim_path):
			push_warning("TerrainEdges: no edge art for '%s' (%s); it keeps hard edges" % [name_of_ground, edges_path])
			continue
		var land := ShaderMaterial.new()
		land.shader = LAND_SHADER
		land.set_shader_parameter(&"ground_texture", sheets[name_of_ground])
		land.set_shader_parameter(&"rim_weight", load(rim_path))
		land.set_shader_parameter(&"ground_period", float(ground.tile_set.tile_size.x * SHEET_CELLS))
		land.set_shader_parameter(&"ground_origin", origin)
		var atlases: Array[Vector2i] = []
		for index in 16:
			atlases.append(Vector2i(index % 4, index / 4))
		sources[name_of_ground] = _add_source(tile_set, load(edges_path) as Texture2D, land, atlases)
	return tile_set


func _add_source(tile_set: TileSet, texture: Texture2D, material_for_tiles: Material, atlases: Array[Vector2i]) -> int:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(ART_TILE, ART_TILE)
	source.margins = Vector2i(GUTTER, GUTTER)
	source.separation = Vector2i(2 * GUTTER, 2 * GUTTER)
	# The shaders read the rim weights at the same UV, so the atlas must not be re-padded.
	source.use_texture_padding = false
	var id := tile_set.add_source(source)
	for atlas in atlases:
		source.create_tile(atlas)
		source.get_tile_data(atlas, 0).material = material_for_tiles
	return id


## The water fill: the water surface's own parameters (mask, sheets, grid) on the edge shader.
func _water_material(origin: Vector2) -> ShaderMaterial:
	var surface := ground.get_node_or_null(NodePath(WATER_SURFACE_NODE)) as CanvasItem
	var surface_material := surface.material as ShaderMaterial if surface != null else null
	if surface_material == null:
		return null
	var water := ShaderMaterial.new()
	water.shader = WATER_SHADER
	for parameter: StringName in [&"water_mask", &"shallow_texture", &"deep_texture", &"grid_size", &"tile_size", &"texture_period"]:
		water.set_shader_parameter(parameter, surface_material.get_shader_parameter(parameter))
	water.set_shader_parameter(&"ground_origin", origin)
	return water


static func _opaque_texture() -> Texture2D:
	var image := Image.create_empty(ART_TILE + 2 * GUTTER, ART_TILE + 2 * GUTTER, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _ensure_layers(tile_set: TileSet) -> void:
	if layers.size() != LEVELS:
		for layer in layers:
			if is_instance_valid(layer):
				layer.free()
		layers.clear()
		for level in LEVELS:
			var layer := TileMapLayer.new()
			layer.name = "Level%d" % level
			layer.scale = Vector2(0.5, 0.5)
			add_child(layer)
			layers.append(layer)
	for layer in layers:
		layer.clear()
		layer.tile_set = tile_set


## Editor: snaps painted sheet frames to the cell's sheet-wrap frame, then rebuilds.
func _on_ground_changed() -> void:
	if _snapping:
		return
	_snap_frames()
	queue_rebuild()


func _snap_frames() -> void:
	_snapping = true
	for cell: Vector2i in ground.get_used_cells():
		var source := ground.tile_set.get_source(ground.get_cell_source_id(cell)) as TileSetAtlasSource
		if source == null or source.get_atlas_grid_size() != Vector2i(SHEET_CELLS, SHEET_CELLS):
			continue
		var frame := Vector2i(posmod(cell.x, SHEET_CELLS), posmod(cell.y, SHEET_CELLS))
		if ground.get_cell_atlas_coords(cell) != frame:
			ground.set_cell(cell, ground.get_cell_source_id(cell), frame)
	_snapping = false
