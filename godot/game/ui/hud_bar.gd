extends Control
class_name HudBar
## One labelled progress bar of the HUD (Phaser `.scene-control--progressbar`, src/styles.css;
## world spec 6.2). Drawn from the UI theme (docs/godot/UI_THEME.md): the `background` and `fill`
## styleboxes, `font`, `font_size`, `font_color` and `font_shadow_color` of its type variation —
## `HudBar` by default (the pills of the top-left HUD: transparent, 1 px border at 42 % white, a
## dark 1 px ring, full radius), `BossBar` for the boss bar (inset well, radius 5). The fill is
## the theme's fill tinted with the bar's tone over clamp(value/max, 0, 1) of the width inside the
## border; the text "<label> <ceil(value)> / <ceil(max)>" sits left at the background's content
## margin, with a 1 px drop shadow. Draws itself; mouse_filter IGNORE.
##
## Owner: world builder (styling: shell / UI theme).

## Text prefix ("HP", "Energy").
var label_text: String = ""
## Fill tone.
var fill_color: Color = Color.WHITE
var value: float = 0.0
var max_value: float = 0.0

## The theme's fill tinted with `fill_color`; rebuilt when the theme or the tone changes.
var _fill_box: StyleBox


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"HudBar"


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_fill_box = null
		queue_redraw()


## Sets the label and the fill tone.
func configure(label: String, tone: Color) -> void:
	label_text = label
	fill_color = tone
	_fill_box = null
	queue_redraw()


## Sets value and maximum, and redraws when either changed.
func set_values(current: float, maximum: float) -> void:
	if is_equal_approx(current, value) and is_equal_approx(maximum, max_value):
		return
	value = current
	max_value = maximum
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var background := get_theme_stylebox(&"background")
	background.draw(get_canvas_item(), rect)
	var inner := rect.grow(-1.0)
	var ratio := clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	if ratio > 0.0 and inner.size.x > 0.0:
		_tinted_fill().draw(get_canvas_item(), Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)))
	var font := get_theme_font(&"font")
	if font == null:
		return
	var font_size := get_theme_font_size(&"font_size")
	var text := "%s %d / %d" % [label_text, ceili(value), ceili(max_value)]
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := Vector2(background.get_margin(SIDE_LEFT) + 1.0, (size.y + ascent - descent) * 0.5)
	var shadow := get_theme_color(&"font_shadow_color")
	if shadow.a > 0.0:
		draw_string(font, baseline + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, shadow)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, get_theme_color(&"font_color"))


func _tinted_fill() -> StyleBox:
	if _fill_box == null:
		_fill_box = get_theme_stylebox(&"fill").duplicate() as StyleBox
		var flat := _fill_box as StyleBoxFlat
		if flat != null:
			flat.bg_color = fill_color
	return _fill_box
