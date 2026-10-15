extends RefCounted
class_name HitFlash
## Helpers for the solid hit flash (res://game/feel/hit_flash.gdshader). Combat spec 11.
## Who times the flash: the enemy on SimClock (120 ms, restarted by each hit), the player on real
## time (120 ms, ignored while one runs). This file only applies the look.
## Body-shapes rework (combat-feel plan section 6 "Flash"; docs/godot/BODY_SHAPES.md "Juice"):
## `flash_curve` plays the white-then-tint curve on real time through a HitFlashCurve child of the
## visual (game/feel/hit_flash_curve.gd); the rework's hits use it through `GameFeel.flash_hit`.
## The old helpers below are unchanged.
##
## Owner: combat builder (the curve: juice).

const SHADER := preload("res://game/feel/hit_flash.gdshader")
const HitFlashCurve := preload("res://game/feel/hit_flash_curve.gd")


const PARAM_COLOR := &"flash_color"
const PARAM_AMOUNT := &"flash_amount"
## The child of a flashed visual that drives its curve.
const CURVE_NODE := &"HitFlashCurve"
## The rework's flash (combat-feel plan section 6, presentation): the hurt tint (the old enemy flash
## colour, enemy.gd HIT_FLASH_COLOR) and the curve's lengths in real ms. Taps: white for one frame,
## then the tint fades; finishers, charges, the Hammer and the Slam: a longer white and fade.
const HURT_TINT := Color("#ff6f88")
const TAP_WHITE_MS := 17.0
const TAP_TINT_MS := 90.0
const BIG_WHITE_MS := 50.0
const BIG_TINT_MS := 120.0


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


## The rework's white-then-tint flash on `visual` (real time): `white` at full strength for
## `white_ms`, then `tint` fading out over `tint_ms`. Installs the material on first use; a new call
## restarts the curve. `big` picks the finisher lengths when `white_ms` / `tint_ms` are < 0.
static func flash_curve(visual: CanvasItem, tint: Color = HURT_TINT, big: bool = false,
		white_ms: float = -1.0, tint_ms: float = -1.0, white: Color = Color.WHITE) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var material := install(visual)
	if material == null:
		return
	var driver := visual.get_node_or_null(NodePath(String(CURVE_NODE))) as HitFlashCurve
	if driver == null:
		driver = HitFlashCurve.new()
		driver.name = String(CURVE_NODE)
		visual.add_child(driver)
	var white_length := white_ms if white_ms >= 0.0 else (BIG_WHITE_MS if big else TAP_WHITE_MS)
	var tint_length := tint_ms if tint_ms >= 0.0 else (BIG_TINT_MS if big else TAP_TINT_MS)
	driver.start(material, white, tint, white_length, tint_length)


## A ShaderMaterial with this shader, or another shader that keeps its parameters and says so with
## the `hit_flash` meta (the player's form skin, game/player/gulp/form_skin.gdshader).
static func _material_of(visual: CanvasItem) -> ShaderMaterial:
	var material := visual.material as ShaderMaterial
	if material != null and (material.shader == SHADER or bool(material.get_meta(&"hit_flash", false))):
		return material
	return null
