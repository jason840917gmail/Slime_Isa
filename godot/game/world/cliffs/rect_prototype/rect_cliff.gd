@tool
extends Node2D
## Independent visual prototype. Dimensions are in 64-unit cells.
## Corners and cap/foot remain fixed; grass depth and rock height extend separately.
## No gameplay collision or elevation integration yet.

const MASTER := preload("res://asset/MAPS/cliffs/rect-prototype/plateau-master.png")
const SHADER := preload("res://game/world/cliffs/rect_prototype/rect_cliff.gdshader")
const CELL := 64.0

@export_range(4, 32) var width_cells: int = 12:
	set(value):
		width_cells = value
		queue_redraw()
@export_range(2, 24) var depth_cells: int = 4:
	set(value):
		depth_cells = value
		queue_redraw()
@export_range(1, 8) var wall_levels: int = 2:
	set(value):
		wall_levels = value
		queue_redraw()

var _art_material: ShaderMaterial


func _draw() -> void:
	if _art_material == null:
		_art_material = ShaderMaterial.new()
		_art_material.shader = SHADER
		material = _art_material
	var size := Vector2(width_cells * CELL, (depth_cells + wall_levels) * CELL)
	_art_material.set_shader_parameter("output_size", size)
	_art_material.set_shader_parameter("top_depth", depth_cells * CELL)
	draw_texture_rect(MASTER, Rect2(Vector2.ZERO, size), false)
