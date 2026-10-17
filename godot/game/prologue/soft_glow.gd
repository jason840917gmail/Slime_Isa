@tool
extends Node2D
## A soft round light or shade (docs/godot/PROLOGUE.md "The Wellspring"): an ellipse of `radius` that
## fades from `color` at its middle to nothing at its edge, drawn added to what is under it
## (`additive`: the Wellspring's glow, the dawn light through the gap in the trees, the mist) or
## over it (a shadow). It can breathe (`pulse`, the share of its alpha that comes and goes over
## `period_s`) and drift (`drift`, px, over `drift_period_s`). Presentation only, on real time; it
## shows in the editor too.
##
## Owner: prologue.

@export var radius: Vector2 = Vector2(64, 32):
	set(value):
		radius = value
		queue_redraw()
@export var color: Color = Color(0.6, 1.0, 0.4, 0.5):
	set(value):
		color = value
		queue_redraw()
@export var additive: bool = true:
	set(value):
		additive = value
		_apply_material()
@export_range(0.0, 1.0) var pulse: float = 0.3
@export var period_s: float = 3.0
@export var drift: Vector2 = Vector2.ZERO
@export var drift_period_s: float = 9.0
## Where the breathing starts in its cycle (0..1), so glows side by side do not breathe together.
@export_range(0.0, 1.0) var phase: float = 0.0

static var _gradient: GradientTexture2D

var _clock := 0.0
var _home := Vector2.ZERO


func _ready() -> void:
	_home = position
	_clock = phase * maxf(0.01, period_s)
	_apply_material()


func _process(delta: float) -> void:
	_clock += delta
	if drift != Vector2.ZERO and not Engine.is_editor_hint():
		var t := _clock * TAU / maxf(0.01, drift_period_s)
		position = _home + Vector2(sin(t) * drift.x, sin(t * 0.73 + 1.3) * drift.y)
	if pulse > 0.0:
		queue_redraw()


func _draw() -> void:
	var tint := color
	if pulse > 0.0:
		var t := _clock * TAU / maxf(0.01, period_s)
		tint.a *= 1.0 - pulse * (0.5 + 0.5 * sin(t))
	draw_texture_rect(glow_texture(), Rect2(-radius, radius * 2.0), false, tint)


func _apply_material() -> void:
	if not additive:
		material = null
		return
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend


static func glow_texture() -> GradientTexture2D:
	if _gradient == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.55, Color(1, 1, 1, 0.45))
		_gradient = GradientTexture2D.new()
		_gradient.gradient = gradient
		_gradient.fill = GradientTexture2D.FILL_RADIAL
		_gradient.fill_from = Vector2(0.5, 0.5)
		_gradient.fill_to = Vector2(1.0, 0.5)
		_gradient.width = 128
		_gradient.height = 128
	return _gradient
