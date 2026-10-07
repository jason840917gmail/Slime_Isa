@tool
extends Node2D
class_name WaterSurface
## Animated water over the ground layer's `water` and `deep-water` tiles (visual only): Phaser
## `features/world/WaterSurfaceLayer.ts`, mounted by `TileMapLayer2DNode.mountTerrainPresentation`
## (docs/godot/specs/water.md).
##
## `WaterSurface.mount(ground)` builds a mask with one texel per tile (r = shallow, g = deep,
## sampled with linear filtering, so the shore is soft) and adds this node as the child
## "WaterSurface" of the ground TileMapLayer. It draws one rectangle with water_surface.gdshader;
## no per-tile nodes and no per-frame script work (the shader reads TIME).
##
## Draw order (spec section 4): Phaser draws the surface at ground-decals + 0.5, above the
## terrain and below everything else. Here the node keeps z_index 0 relative to the ground layer
## (-2), so it draws right after the tiles; the underwater life (explicit ground-decals depth,
## converted to z -2) y-sorts after the ground layer and so draws over the surface, and the
## world-sorted decals (-1, lily pads, bubbles) and entities (0, reeds) draw above both.
##
## Owner: world builder.

const SHADER := preload("res://game/world/water_surface.gdshader")
## This script, for the static factory and its return type: headless runs know a new script's
## class_name only after the editor has registered it, so the file never names itself.
const Self := preload("res://game/world/water_surface.gd")
const NODE_NAME := "WaterSurface"
## Custom data layer of the converted terrain TileSet that holds the terrain tile id.
const TILE_ID_DATA_LAYER := "tile_id"
## Water tiles. Phaser keys the kind by the tile's asset (TileMapLayer2DNode.ts:18:
## `sheet.grounds.19x19.water` shallow, `sheet.grounds.19x19.deep-water` deep); exactly these two
## terrain tiles use those sheets (terrain.tile-set.resource.json).
const SHALLOW_TILE_ID := "water"
const DEEP_TILE_ID := "deep-water"
## World size of one repeat of the water ground texture: the 19 x 19 sheet of 64 px tiles
## (WaterSurfaceLayer.ts:36). Presentation constant.
const TEXTURE_PERIOD := 1216.0
## Tiles drawn around the water's bounding box. The noisy edge and the foam reach at most 0.36
## tile past a water tile (a pixel draws when mask + edge >= 0.3 and edge <= 0.16), so one tile of
## margin covers every pixel Phaser's full-layer quad would draw.
const DRAW_MARGIN_TILES := 1

enum Kind { NONE, SHALLOW, DEEP }

## Mask size in tiles (Phaser: the tile data's columns and rows).
var columns: int = 0
var rows: int = 0
var tile_size: float = 64.0
## The mask: Color(1, 0, 0) shallow, Color(0, 1, 0) deep, black elsewhere, alpha 1.
var mask_image: Image
var shallow_cells: int = 0
var deep_cells: int = 0
## Layer-local rectangle the quad covers (the water's bounding box plus DRAW_MARGIN_TILES).
var water_rect: Rect2 = Rect2()


## Mounts the water surface on `ground` (once; a second call returns the existing node). Null when
## the layer has no water, no tile set, or a rotated or scaled transform (Phaser mounts terrain
## presentation only on unrotated, unscaled layers, TileMapLayer2DNode.ts:259).
static func mount(ground: TileMapLayer) -> Self:
	if ground == null or ground.tile_set == null:
		return null
	var existing := ground.get_node_or_null(NodePath(NODE_NAME)) as Self
	if existing != null:
		return existing
	var transform := ground.get_global_transform() if ground.is_inside_tree() else ground.transform
	if not is_zero_approx(transform.get_rotation()) or not transform.get_scale().is_equal_approx(Vector2.ONE):
		return null
	var surface: Self = Self.new()
	if not surface.build(ground):
		surface.free()
		return null
	surface.name = NODE_NAME
	ground.add_child(surface)
	return surface


## Builds the mask, the material and the drawn rectangle from `ground`'s cells. False when the
## layer has no water tile (or its tile set has no `tile_id` data layer).
func build(ground: TileMapLayer) -> bool:
	tile_size = float(ground.tile_set.tile_size.x)
	shallow_cells = 0
	deep_cells = 0
	if not ground.tile_set.has_custom_data_layer_by_name(TILE_ID_DATA_LAYER):
		return false
	var used := ground.get_used_rect()
	columns = int(ground.get_meta("columns", used.end.x))
	rows = int(ground.get_meta("rows", used.end.y))
	if columns <= 0 or rows <= 0:
		return false
	mask_image = Image.create_empty(columns, rows, false, Image.FORMAT_RGBA8)
	mask_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	var textures := {Kind.SHALLOW: null, Kind.DEEP: null}
	var kind_by_source := {}
	var first := Vector2i(columns, rows)
	var last := Vector2i(-1, -1)
	for cell: Vector2i in ground.get_used_cells():
		if cell.x < 0 or cell.y < 0 or cell.x >= columns or cell.y >= rows:
			continue
		var source_id := ground.get_cell_source_id(cell)
		if not kind_by_source.has(source_id):
			kind_by_source[source_id] = _kind_of(ground.get_cell_tile_data(cell))
		var kind: int = kind_by_source[source_id]
		if kind == Kind.NONE:
			continue
		if kind == Kind.SHALLOW:
			mask_image.set_pixelv(cell, Color(1.0, 0.0, 0.0, 1.0))
			shallow_cells += 1
		else:
			mask_image.set_pixelv(cell, Color(0.0, 1.0, 0.0, 1.0))
			deep_cells += 1
		if textures[kind] == null:
			var source := ground.tile_set.get_source(source_id) as TileSetAtlasSource
			if source != null:
				textures[kind] = source.texture
		first = Vector2i(mini(first.x, cell.x), mini(first.y, cell.y))
		last = Vector2i(maxi(last.x, cell.x), maxi(last.y, cell.y))
	if shallow_cells + deep_cells == 0:
		return false
	var from := (first - Vector2i.ONE * DRAW_MARGIN_TILES).clamp(Vector2i.ZERO, Vector2i(columns, rows))
	var to := (last + Vector2i.ONE * (1 + DRAW_MARGIN_TILES)).clamp(Vector2i.ZERO, Vector2i(columns, rows))
	water_rect = Rect2(Vector2(from) * tile_size, Vector2(to - from) * tile_size)
	# A world with one kind samples that sheet in both slots, as Phaser does (WaterSurfaceLayer.ts:206-207).
	var shallow: Texture2D = textures[Kind.SHALLOW] if textures[Kind.SHALLOW] != null else textures[Kind.DEEP]
	var deep: Texture2D = textures[Kind.DEEP] if textures[Kind.DEEP] != null else textures[Kind.SHALLOW]
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	shader_material.set_shader_parameter(&"water_mask", ImageTexture.create_from_image(mask_image))
	shader_material.set_shader_parameter(&"shallow_texture", shallow)
	shader_material.set_shader_parameter(&"deep_texture", deep)
	shader_material.set_shader_parameter(&"grid_size", Vector2(columns, rows))
	shader_material.set_shader_parameter(&"tile_size", tile_size)
	shader_material.set_shader_parameter(&"texture_period", TEXTURE_PERIOD)
	material = shader_material
	queue_redraw()
	return true


## The mask kind of tile (x, y): Kind.SHALLOW, Kind.DEEP or Kind.NONE (outside the mask too).
func kind_at(x: int, y: int) -> Kind:
	if mask_image == null or x < 0 or y < 0 or x >= columns or y >= rows:
		return Kind.NONE
	var texel := mask_image.get_pixel(x, y)
	if texel.r > 0.5:
		return Kind.SHALLOW
	if texel.g > 0.5:
		return Kind.DEEP
	return Kind.NONE


func _draw() -> void:
	if water_rect.has_area():
		draw_rect(water_rect, Color.WHITE)


static func _kind_of(tile_data: TileData) -> Kind:
	if tile_data == null:
		return Kind.NONE
	var tile_id: Variant = tile_data.get_custom_data(TILE_ID_DATA_LAYER)
	if tile_id == SHALLOW_TILE_ID:
		return Kind.SHALLOW
	if tile_id == DEEP_TILE_ID:
		return Kind.DEEP
	return Kind.NONE
