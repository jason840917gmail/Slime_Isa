@tool
extends Node2D
## Hand-made terrain transitions over a ground TileMapLayer (docs/godot/TERRAIN_LAB.md).
##
## `TerrainEdges.mount(ground)` adds this node as the child "TerrainEdges" of the ground layer
## (after the water surface, so it draws over it) with LEVELS TileMapLayers on a dual grid: each
## of their cells sits on a corner shared by four ground cells (the node is half a cell up and
## left; 128 px art at scale 0.5). Where different grounds meet at a corner, level 0 fills the
## corner with the lowest of them (its fully covered tile, or the animated water, which draws the
## deep-water bank from one of 16 shapes picked by the corner's land cells) and each higher
## ground draws its edge tile on the next level: index = TL + 2*TR + 4*BL + 8*BR, with 1 where the
## cell's ground stacks at least that high (TerrainMaterials.ORDER). Corners touching a tile without
## edges (walls, interior floors) or a ground without art keep hard edges, and so do corners where
## the elevation layer has different levels (the cliff draws its own rims there,
## docs/godot/ELEVATION.md). Corners on the map's border take the border cells carried on past it
## (`_inside`), so a shore or a road running off the map (into the next chunk) keeps its edge to the
## border instead of a straight cut half a cell short of it.
##
## This script only picks tiles; the art (scripts/art/build-terrain-edge-tiles.py) and the shaders
## (terrain_edge.gdshader, terrain_edge_water.gdshader) do the rest. Visual only: the ground cells
## stay the gameplay truth. Built on mount; in the editor also whenever the ground is painted, which
## first snaps painted sheet frames to the cell's sheet-wrap frame (x mod 19, y mod 19).
##
## Owner: world (terrain edges).

const Self := preload("res://game/world/terrain_edges/terrain_edges.gd")
const NodeFind := preload("res://game/shared/node_find.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const LAND_SHADER := preload("res://game/world/terrain_edges/terrain_edge.gdshader")
const WATER_SHADER := preload("res://game/world/terrain_edges/terrain_edge_water.gdshader")
## The deep-water bank (docs/godot/specs/water.md §11, scripts/art/build-water-bank.py): the water
## fill's 16 shapes (the edge sheets' layout, indexed by the corner's land cells) and its earth.
const BANK_SHAPES := "res://asset/MAPS/water/water-bank-shapes.png"
const BANK_EARTH := "res://asset/MAPS/water/water-bank-earth.png"
const Elevation := preload("res://game/world/elevation/elevation.gd")
const ElevationSides := preload("res://game/world/elevation/sides/elevation_sides.gd")
const GroundSurface := preload("res://game/world/ground_surface.gd")
const WaterSurface := preload("res://game/world/water_surface.gd")
const NODE_NAME := "TerrainEdges"
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
## The bits of a corner's four cells, in the order TL, TR, BL, BR.
const BITS: Array[int] = [TL, TR, BL, BR]

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
## True when the water fill has the bank's 16 shapes (else one plain tile, no bank).
var _bank_shapes := false

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
	var edges := find_in(layer)
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
					# The 128 px sheet where there is one, as the ground surface draws it.
					var sharp := GroundSurface.sharp_sheet(source.texture)
					sheets[name_of_ground] = sharp if sharp != null else source.texture
		cell_ground[cell] = ground_by_source[source_id]

	var tile_set := _edge_tile_set(sheets)
	_ensure_layers(tile_set)
	# Stack order per cell; -1 = no edges (wall, floor, no art) and -2 = no cell.
	var order_of := {}
	for name_of_ground: String in sheets:
		order_of[name_of_ground] = TerrainMaterials.order_of(name_of_ground) if sources.has(name_of_ground) else -1
	var levels := Elevation.painted_levels(ground)
	var bounds := Rect2i(0, 0, columns, rows)
	for cy in range(0, rows + 1):
		for cx in range(0, columns + 1):
			var quad: Array[Vector2i] = [
				_inside(bounds, Vector2i(cx - 1, cy - 1)), _inside(bounds, Vector2i(cx, cy - 1)),
				_inside(bounds, Vector2i(cx - 1, cy)), _inside(bounds, Vector2i(cx, cy)),
			]
			if not levels.is_empty() and not _same_level(levels, quad):
				continue
			var around: Array[int] = [
				_order_at(cell_ground, order_of, quad[0]), _order_at(cell_ground, order_of, quad[1]),
				_order_at(cell_ground, order_of, quad[2]), _order_at(cell_ground, order_of, quad[3]),
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
					index = _covered(around, stack[level])
				elif name_of_ground == TerrainMaterials.WATER:
					# The bank's shape: the land cells (above the water), as level 1's edge tile,
					# which covers the bank's top.
					index = _covered(around, stack[1]) if _bank_shapes else 0
				layers[level].set_cell(corner, sources[name_of_ground], _atlas_of(index))
				placed += 1
			corners += 1
	return placed


## Queues a rebuild for the end of the frame (painting sends many changes).
func queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	rebuild.call_deferred()


## True when the four cells `quad` around a corner share one painted elevation level.
static func _same_level(levels: Dictionary, quad: Array[Vector2i]) -> bool:
	var level := int(levels.get(quad[0], 0))
	for cell: Vector2i in quad:
		if int(levels.get(cell, 0)) != level:
			return false
	return true


## The bits of the cells in `around` (TL, TR, BL, BR) that stack at least as high as `order`.
static func _covered(around: Array[int], order: int) -> int:
	var index := 0
	for i in 4:
		if around[i] >= order:
			index |= BITS[i]
	return index


## Where tile `index` (TL + 2*TR + 4*BL + 8*BR) lies in a 16-tile sheet.
static func _atlas_of(index: int) -> Vector2i:
	return Vector2i(index % 4, index / 4)


## `cell` moved onto the map's border cells when it lies past them (the map's ground carried on).
static func _inside(bounds: Rect2i, cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, bounds.position.x, bounds.end.x - 1), clampi(cell.y, bounds.position.y, bounds.end.y - 1))


func _order_at(cell_ground: Dictionary, order_of: Dictionary, cell: Vector2i) -> int:
	if not cell_ground.has(cell):
		return -2
	var name_of_ground: String = cell_ground[cell]
	return int(order_of.get(name_of_ground, -1)) if name_of_ground != "" else -1


## The edge tile set for this world: one source per ground with art (16 tiles, the land shader on
## that ground's sheet) plus one water source (the 16 bank shapes, the water shader) when the
## ground has a mounted water surface. Fills `sources`.
func _edge_tile_set(sheets: Dictionary) -> TileSet:
	sources.clear()
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(ART_TILE, ART_TILE)
	var origin := ground.global_position if ground.is_inside_tree() else ground.position
	var sheet_tiles: Array[Vector2i] = []
	for index in 16:
		sheet_tiles.append(_atlas_of(index))
	for name_of_ground: String in sheets:
		if name_of_ground == TerrainMaterials.WATER:
			var water := _water_material(origin)
			if water != null:
				_bank_shapes = ResourceLoader.exists(BANK_SHAPES) and ResourceLoader.exists(BANK_EARTH)
				if _bank_shapes:
					water.set_shader_parameter(&"bank_texture", load(BANK_EARTH))
					# The side walls in the cliffs' side light; the front keeps the earth strip's own.
					water.set_shader_parameter(&"bank_shade_east", ElevationSides.SHADE_EAST)
					water.set_shader_parameter(&"bank_shade_west", ElevationSides.SHADE_WEST)
					sources[name_of_ground] = _add_source(tile_set, load(BANK_SHAPES) as Texture2D, water, sheet_tiles)
				else:
					push_warning("TerrainEdges: no bank art (%s); deep water keeps a flat shore" % BANK_SHAPES)
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
		sources[name_of_ground] = _add_source(tile_set, load(edges_path) as Texture2D, land, sheet_tiles)
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
	var surface := WaterSurface.find_in(ground)
	var water := ShaderMaterial.new()
	water.shader = WATER_SHADER
	if surface == null or not surface.share_water(water):
		return null
	water.set_shader_parameter(&"ground_origin", origin)
	return water


## One water fill tile with no bank: no land within reach (r 1), a front wall (g 0.5), no bank near
## (b 0).
static func _opaque_texture() -> Texture2D:
	var image := Image.create_empty(ART_TILE + 2 * GUTTER, ART_TILE + 2 * GUTTER, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.5, 0.0, 1.0))
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
	snap_frames(ground)
	_snapping = false


## The sheet-wrap frame of `cell` on a ground layer whose tile set is `tile_set`, for a tile of
## source `source_id`: (x mod 19, y mod 19), counted from the layer's own corner, where the edges and
## the 128 px ground draw the sheet from; null when the source is no 19 x 19 ground sheet (the
## cell keeps its frame). In a chunk scene that corner is the chunk's, as the game draws it; an area
## counts from its own corner (game/dev/area_edit/area_edit.gd gives each written chunk its own).
static func sheet_frame(tile_set: TileSet, source_id: int, cell: Vector2i) -> Variant:
	var source := tile_set.get_source(source_id) as TileSetAtlasSource if tile_set != null and tile_set.has_source(source_id) else null
	if source == null or source.get_atlas_grid_size() != Vector2i(SHEET_CELLS, SHEET_CELLS):
		return null
	return Vector2i(posmod(cell.x, SHEET_CELLS), posmod(cell.y, SHEET_CELLS))


## Sets every ground-sheet cell of `layer` to its sheet-wrap frame (sheet_frame); returns how many
## cells changed.
static func snap_frames(layer: TileMapLayer) -> int:
	var changed_cells := 0
	for cell: Vector2i in layer.get_used_cells():
		var source_id := layer.get_cell_source_id(cell)
		var frame: Variant = sheet_frame(layer.tile_set, source_id, cell)
		if frame != null and layer.get_cell_atlas_coords(cell) != frame:
			layer.set_cell(cell, source_id, frame, layer.get_cell_alternative_tile(cell))
			changed_cells += 1
	return changed_cells

## The terrain edges under `parent`, found by class (a node's name is typed by hand in the editor).
static func find_in(parent: Node) -> Self:
	return NodeFind.child_of(parent, Self) as Self
