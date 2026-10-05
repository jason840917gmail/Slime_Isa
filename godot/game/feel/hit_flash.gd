extends RefCounted
class_name HitFlash
## Helpers for the solid hit flash (res://game/feel/hit_flash.gdshader). Combat spec 11.
## Who times the flash: the enemy on SimClock (120 ms, restarted by each hit), the player on real
## time (120 ms, ignored while one runs). This file only applies the look.
##
## Owner: combat builder.

const SHADER := preload("res://game/feel/hit_flash.gdshader")


const PARAM_COLOR := &"flash_color"
const PARAM_AMOUNT := &"flash_amount"


## Gives `visual` its own ShaderMaterial with SHADER (flash_amount 0). Call once in `_ready`.
## Returns the material. Re-installing keeps an existing hit-flash material.
static func install(visual: CanvasItem) -> ShaderMaterial:
	if visual == null:
		return null
	var existing := _material_of(visual)
	if existing != null:
		return existing
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(PARAM_AMOUNT, 0.0)
	visual.material = material
	return material


## Solid fill with `color` (flash_amount 1). Installs the material on first use.
static func flash(visual: CanvasItem, color: Color) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var material := install(visual)
	material.set_shader_parameter(PARAM_COLOR, color)
	material.set_shader_parameter(PARAM_AMOUNT, 1.0)


## Back to the normal look (flash_amount 0).
static func clear(visual: CanvasItem) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var material := _material_of(visual)
	if material != null:
		material.set_shader_parameter(PARAM_AMOUNT, 0.0)


## True while `visual` shows the fill.
static func is_flashing(visual: CanvasItem) -> bool:
	if visual == null or not is_instance_valid(visual):
		return false
	var material := _material_of(visual)
	return material != null and float(material.get_shader_parameter(PARAM_AMOUNT)) > 0.0


static func _material_of(visual: CanvasItem) -> ShaderMaterial:
	var material := visual.material as ShaderMaterial
	if material != null and material.shader == SHADER:
		return material
	return null
