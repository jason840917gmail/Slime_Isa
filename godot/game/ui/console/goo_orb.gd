extends Control
class_name GooOrb
## One orb of the HUD console (docs/design/2026-10-07-hud-console-mockup.md, roadmap 4.12): goo up
## to the value's level inside the wooden ring (`orb-ring.webp`), drawn by `goo_orb.gdshader`. The
## life orb is red, the energy orb gold.
##
## Numbers (owner, 2026-10-08): the value shows in the middle only when it changes (a hit, a heal,
## energy spent or refilled), with the change floating beside the orb, then both fade; nothing shows
## while it stays the same. `set_value(..., announce = false)` (binding a player, a respawn) changes
## the level quietly.
##
## Heart pips (life orb): `set_heart_quarters([4, 4, 2])` draws one pip per heart on the ring's
## left arc, its quarters filled clockwise from the top left; an empty list draws none (the run
## starts with no hearts).
##
## Size: the ring's own size at 2 px per unit (144 x 149 units). Presentation runs on real time.
## Takes no mouse input.
##
## Owner: UI (HUD console).

const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const SHADER := preload("res://game/ui/console/goo_orb.gdshader")
const RING_PATH := "res://asset/UI/hud-console/orb-ring.webp"
## orb-ring.webp: 288 x 298 px, drawn at 0.5 (scripts/art/pack-hud-console.py prints the hole).
const RING_SIZE := Vector2(144.0, 149.0)
const HOLE_CENTRE := Vector2(73.25, 77.25)
const HOLE_RADIUS := 49.75
## The goo reaches this far under the ring, so no gap shows between them.
const GOO_TUCK := 3.0
const NUMBER_FONT_SIZE := 26
const CHANGE_FONT_SIZE := 20
## How long a changed number stays, then how long it fades (ms, real time).
const NUMBER_HOLD_MS := 1400.0
const NUMBER_FADE_MS := 400.0
## The change floats up this far while it shows, from above the orb (clear of the weapon carousel).
const CHANGE_RISE := 18.0
const CHANGE_OFFSET := Vector2(0.0, -96.0)
## Heart pips on the ring's left arc: size, first angle and step (degrees, counter-clockwise from
## the right), distance from the hole's edge.
const PIP_SIZE := 18.0
const PIP_FIRST_DEG := 142.0
const PIP_STEP_DEG := 27.0
const PIP_OUTSET := 8.0
const PIP_OUTLINE := Color("#ffecdc")
const PIP_EMPTY := Color("#28161a")
const PIP_FILL := Color("#ff5c6e")
const OUTLINE := Color("#180e08")

var value: float = 0.0
var max_value: float = 0.0
var quarters: Array[int] = []

var _goo: ColorRect
var _material: ShaderMaterial
var _ring: TextureRect
var _number: Label
var _change: Label
var _pips: Control
var _shown_at_ms: float = -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = RING_SIZE
	custom_minimum_size = RING_SIZE


## Colours of the goo: `top` and `bottom` of the gradient, `rim` for the surface and the bubbles.
func configure(top: Color, bottom: Color, rim: Color, seed: float) -> void:
	_build()
	_material.set_shader_parameter(&"top_color", top)
	_material.set_shader_parameter(&"bottom_color", bottom)
	_material.set_shader_parameter(&"rim_color", rim)
	_material.set_shader_parameter(&"seed", seed)


## Sets the level; with `announce` and a real change the number and the change show for a moment.
func set_value(new_value: float, new_max: float, announce: bool = true) -> void:
	_build()
	var old := value
	var had_value := max_value > 0.0
	value = maxf(0.0, new_value)
	max_value = maxf(0.0, new_max)
	_material.set_shader_parameter(&"level", clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0)
	var delta := roundf(value) - roundf(old)
	if announce and had_value and delta != 0.0:
		_number.text = str(int(roundf(value)))
		_change.text = ("+%d" if delta > 0.0 else "−%d") % int(absf(delta))
		_change.add_theme_color_override(&"font_color", UiTokens.ACCENT if delta > 0.0 else UiTokens.DANGER)
		_shown_at_ms = float(Time.get_ticks_msec())
		_update_numbers()


## The hearts on the ring, in quarters per heart (4 = a whole heart).
func set_heart_quarters(hearts: Array[int]) -> void:
	quarters = hearts.duplicate()
	if _pips != null:
		_pips.queue_redraw()


## True while the number shows (tests).
func is_number_shown() -> bool:
	return _number != null and _number.visible


func _process(_delta: float) -> void:
	if _shown_at_ms >= 0.0:
		_update_numbers()


func _update_numbers() -> void:
	var age := float(Time.get_ticks_msec()) - _shown_at_ms
	if _shown_at_ms < 0.0 or age >= NUMBER_HOLD_MS + NUMBER_FADE_MS:
		_shown_at_ms = -1.0
		_number.visible = false
		_change.visible = false
		return
	var alpha := 1.0 - clampf((age - NUMBER_HOLD_MS) / NUMBER_FADE_MS, 0.0, 1.0)
	_number.visible = true
	_change.visible = true
	_number.modulate.a = alpha
	_change.modulate.a = alpha
	_change.position = CHANGE_OFFSET + HOLE_CENTRE - _change.size * 0.5 \
		- Vector2(0.0, CHANGE_RISE * clampf(age / (NUMBER_HOLD_MS + NUMBER_FADE_MS), 0.0, 1.0))


func _build() -> void:
	if _goo != null:
		return
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var goo_radius := HOLE_RADIUS + GOO_TUCK
	_goo = ColorRect.new()
	_goo.name = "Goo"
	_goo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goo.material = _material
	_goo.position = HOLE_CENTRE - Vector2(goo_radius + 1.0, goo_radius + 1.0)
	_goo.size = Vector2.ONE * (goo_radius + 1.0) * 2.0
	_material.set_shader_parameter(&"radius", goo_radius / _goo.size.x)
	add_child(_goo)
	_ring = TextureRect.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring.stretch_mode = TextureRect.STRETCH_SCALE
	_ring.size = RING_SIZE
	if ResourceLoader.exists(RING_PATH):
		_ring.texture = load(RING_PATH) as Texture2D
	add_child(_ring)
	_pips = Control.new()
	_pips.name = "HeartPips"
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.size = RING_SIZE
	_pips.draw.connect(_draw_pips)
	add_child(_pips)
	_number = _make_label("Number", NUMBER_FONT_SIZE, UiTokens.TEXT)
	_number.size = Vector2(HOLE_RADIUS * 2.0, 34.0)
	_number.position = HOLE_CENTRE - _number.size * 0.5
	_change = _make_label("Change", CHANGE_FONT_SIZE, UiTokens.DANGER)
	_change.size = Vector2(64.0, 26.0)
	_number.visible = false
	_change.visible = false


func _make_label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", OUTLINE)
	label.add_theme_constant_override(&"outline_size", 6)
	add_child(label)
	return label


## Each heart: the outline, the empty inside, then its quarters filled clockwise from the top left.
func _draw_pips() -> void:
	var outline := heart_polygon(PIP_SIZE)
	var inner := heart_polygon(PIP_SIZE * 0.72)
	var quadrants := [Rect2(-PIP_SIZE, -PIP_SIZE, PIP_SIZE, PIP_SIZE), Rect2(0.0, -PIP_SIZE, PIP_SIZE, PIP_SIZE),
		Rect2(0.0, 0.0, PIP_SIZE, PIP_SIZE), Rect2(-PIP_SIZE, 0.0, PIP_SIZE, PIP_SIZE)]
	var distance := HOLE_RADIUS + PIP_OUTSET
	for index in quarters.size():
		var angle := deg_to_rad(PIP_FIRST_DEG + PIP_STEP_DEG * index)
		var at := HOLE_CENTRE + Vector2(cos(angle), -sin(angle)) * distance
		_pips.draw_set_transform(at)
		_pips.draw_colored_polygon(outline, PIP_OUTLINE)
		_pips.draw_colored_polygon(inner, PIP_EMPTY)
		for quarter in clampi(quarters[index], 0, 4):
			var box: Rect2 = quadrants[quarter]
			var clip := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end,
				Vector2(box.position.x, box.end.y)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(inner, clip):
				_pips.draw_colored_polygon(piece, PIP_FILL)
	_pips.draw_set_transform(Vector2.ZERO)


## A heart `width` wide centred on its middle (the classic heart curve, y down).
static func heart_polygon(width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 40
	for step in steps:
		var t := TAU * step / steps
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		points.append(Vector2(x, -y - 2.5) * (width / 34.0))
	return points
