extends Control
class_name HudBar
## One pill progress bar of the trial HUD (Phaser `.game-ui--hud .scene-control--progressbar`,
## src/styles.css; world spec 6.2): transparent background, 1 px border rgba(245,247,255,0.42),
## outer 1 px ring #0810224d, corner radius 9, fill = tone colour over clamp(value/max, 0, 1) of
## the inner width, text "<label> <ceil(value)> / <ceil(max)>" 11 px #f5f7ff left-aligned with
## 6 px padding and a #081022 shadow. Draws itself; mouse_filter IGNORE.
##
## Owner: world builder.

const BORDER_COLOR := Color(245.0 / 255.0, 247.0 / 255.0, 1.0, 0.42)
const OUTER_RING_COLOR := Color("#0810224d")
const TEXT_COLOR := Color("#f5f7ff")
const SHADOW_COLOR := Color("#081022")
const CORNER_RADIUS := 9
const FONT_SIZE := 11
const PADDING_X := 6.0

## Text prefix ("HP", "Energy").
var label_text: String = ""
## Fill tone.
var fill_color: Color = Color.WHITE
var value: float = 0.0
var max_value: float = 0.0

var _border_box: StyleBoxFlat
var _outer_box: StyleBoxFlat
var _fill_box: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border_box = _box(Color(0, 0, 0, 0), BORDER_COLOR, CORNER_RADIUS)
	_outer_box = _box(Color(0, 0, 0, 0), OUTER_RING_COLOR, CORNER_RADIUS + 1)
	_fill_box = _box(fill_color, Color(0, 0, 0, 0), CORNER_RADIUS - 1)
	_fill_box.border_width_left = 0
	_fill_box.border_width_top = 0
	_fill_box.border_width_right = 0
	_fill_box.border_width_bottom = 0


## Sets label, tone, value and maximum, and redraws when anything changed.
func configure(label: String, tone: Color) -> void:
	label_text = label
	fill_color = tone
	_fill_box.bg_color = tone
	queue_redraw()


func set_values(current: float, maximum: float) -> void:
	if is_equal_approx(current, value) and is_equal_approx(maximum, max_value):
		return
	value = current
	max_value = maximum
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_outer_box.draw(get_canvas_item(), rect.grow(1.0))
	var inner := rect.grow(-1.0)
	var ratio := clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if ratio > 0.0 and inner.size.x > 0.0:
		_fill_box.draw(get_canvas_item(), Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)))
	_border_box.draw(get_canvas_item(), rect)
	var font := get_theme_default_font()
	if font == null:
		return
	var text := "%s %d / %d" % [label_text, ceili(value), ceili(max_value)]
	var ascent := font.get_ascent(FONT_SIZE)
	var descent := font.get_descent(FONT_SIZE)
	var baseline := Vector2(PADDING_X + 1.0, (size.y + ascent - descent) * 0.5)
	draw_string(font, baseline + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SHADOW_COLOR)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)


static func _box(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.anti_aliasing = true
	return box
