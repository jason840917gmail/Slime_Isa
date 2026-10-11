@tool
extends Node2D
## The ground at 128 px of art per cell (docs/godot/TERRAIN_LAB.md "Ground at 128 px"): the ground
## TileMapLayer stays the gameplay grid of 64-unit cells with its 64 px sheets, and this node draws
## over it, in world space, every cell whose ground has a 128 px sheet
## (`res://asset/MAPS/grounds/128x128-tile_19x19_<name>.webp`, the same 19 x 19 sheet-wrap layout
## at twice the pixels). Water is left to the water surface and grounds without a sharp sheet to
## the tiles.
##
## `GroundSurface.mount(ground)` adds it as the first child "GroundSurface" of the ground layer
## (under the water surface and the terrain edges), with one texel per cell saying which sheet
## draws there. One rectangle, ground_surface.gdshader; no per-frame work.
##
## Owner: world.

const SHADER := preload("res://game/world/ground_surface.gdshader")
const Self := preload("res://game/world/ground_surface.gd")
const NODE_NAME := "GroundSurface"
const SHARP_PREFIX := "128x128-tile_19x19_"
const SHEET_PREFIX := "64x64-tile_19x19_"
## Sheets the shader can hold at once (ground_surface.gdshader `sheet0` ... `sheet7`).
const MAX_SHEETS := 8
## A texel value for a cell no sharp sheet draws.
const NONE := 255

## Grid size in cells and the number of cells drawn.
var columns: int = 0
var rows: int = 0
var cells: int = 0
## Sharp sheets in use, by slot.
var sheets: Array[Texture2D] = []


## Mounts (or rebuilds) the surface on `ground`. Null, and any old surface removed, when no cell's
## ground has a 128 px sheet.
static func mount(ground: TileMapLayer) -> Self:
	if ground == null or ground.tile_set == null:
		return null
	var surface := ground.get_node_or_null(NodePath(NODE_NAME)) as Self
	if surface == null:
		surface = Self.new()
		surface.name = NODE_NAME
		if not surface.build(ground):
			surface.free()
			return null
		ground.add_child(surface)
		ground.move_child(surface, 0)
		return surface
	if not surface.build(ground):
		surface.queue_free()
		return null
	return surface


## Builds the cell map and the material from `ground`'s cells. False when nothing is drawn.
func build(ground: TileMapLayer) -> bool:
	var used := ground.get_used_rect()
	columns = int(ground.get_meta("columns", used.end.x))
	rows = int(ground.get_meta("rows", used.end.y))
	cells = 0
	sheets.clear()
	if columns <= 0 or rows <= 0:
		return false
	var map := Image.create_empty(columns, rows, false, Image.FORMAT_R8)
	map.fill(Color8(NONE, 0, 0))
	var slot_by_source := {}
	for cell: Vector2i in ground.get_used_cells():
		if cell.x < 0 or cell.y < 0 or cell.x >= columns or cell.y >= rows:
			continue
		var source_id := ground.get_cell_source_id(cell)
		if not slot_by_source.has(source_id):
			slot_by_source[source_id] = _slot_for(ground.tile_set.get_source(source_id) as TileSetAtlasSource)
		var slot: int = slot_by_source[source_id]
		if slot != NONE:
			map.set_pixelv(cell, Color8(slot, 0, 0))
			cells += 1
	if cells == 0:
		return false
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	shader_material.set_shader_parameter(&"cell_map", ImageTexture.create_from_image(map))
	shader_material.set_shader_parameter(&"tile_size", float(ground.tile_set.tile_size.x))
	shader_material.set_shader_parameter(&"texture_period", float(ground.tile_set.tile_size.x * 19))
	for i in sheets.size():
		shader_material.set_shader_parameter(StringName("sheet%d" % i), sheets[i])
	material = shader_material
	queue_redraw()
	return true


## The 128 px sheet of a 64 px ground sheet, or null when it has none (also for water).
static func sharp_sheet(sheet: Texture2D) -> Texture2D:
	if sheet == null:
		return null
	var file := sheet.resource_path.get_file()
	if not file.begins_with(SHEET_PREFIX) or file.contains("water"):
		return null
	var sharp_path := sheet.resource_path.get_base_dir().path_join(SHARP_PREFIX + file.trim_prefix(SHEET_PREFIX))
	return load(sharp_path) as Texture2D if ResourceLoader.exists(sharp_path) else null


## The slot of a source's sharp sheet (loaded and added on first use), or NONE: water, sources
## that are not 19 x 19 ground sheets, grounds without a sharp sheet, or no slot left.
func _slot_for(source: TileSetAtlasSource) -> int:
	var sharp := sharp_sheet(source.texture) if source != null else null
	if sharp == null:
		return NONE
	var file := source.texture.resource_path.get_file()
	var slot := sheets.find(sharp)
	if slot == -1:
		if sheets.size() >= MAX_SHEETS:
			push_warning("GroundSurface: more than %d sharp ground sheets; '%s' stays at 64 px" % [MAX_SHEETS, file])
			return NONE
		sheets.append(sharp)
		slot = sheets.size() - 1
	return slot


func _draw() -> void:
	if cells > 0 and material != null:
		var tile := float((material as ShaderMaterial).get_shader_parameter(&"tile_size"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(columns, rows) * tile), Color.WHITE)
