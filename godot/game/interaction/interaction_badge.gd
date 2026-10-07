extends Node2D
## The key badge over the chosen target (Phaser `InteractionRouter.ts:33-35, 145-197`;
## interaction spec 2.6, 7.5): a 22 px rounded plate (#101a31 at 0.92, 2 px #9dffc8 border, a soft
## shadow 1 px right and 2 px down) with a mouse glyph whose right button is lit, its bottom
## centre at the target's anchor. It bobs 2.5 px every 1400 ms and pops in (scale 0.5 -> 1, alpha
## 0 -> 1, 140 ms, back-out) whenever the target changes. World space, z_index 1 (above every
## world sprite), so it zooms and fades with the world. PAUSABLE.
##
## Owner: interaction.

const SIZE := 22.0
const RADIUS := 5
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)
const PLATE := Color(Color("#101a31"), 0.92)
const BORDER := Color("#9dffc8")
const GLYPH := Color("#e7fff5")
const BOB_PERIOD_MS := 1400.0
const BOB_PX := 2.5
const POP_MS := 140.0

var _pop: Tween
var _shadow_box: StyleBoxFlat
var _plate_box: StyleBoxFlat
var _lit_box: StyleBoxFlat
var _mouse_box: StyleBoxFlat


func _ready() -> void:
	z_index = 1
	visible = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_shadow_box = _box(SHADOW, Color.TRANSPARENT, 0, RADIUS)
	_plate_box = _box(PLATE, BORDER, 2, RADIUS)
	_lit_box = _box(BORDER, Color.TRANSPARENT, 0, 0)
	_lit_box.corner_radius_top_right = 4
	_mouse_box = _box(Color.TRANSPARENT, GLYPH, 1, 4)


## Places the badge's bottom centre at `anchor` (rounded, plus the bob); `pop` restarts the pop-in.
func show_at(anchor: Vector2, pop: bool) -> void:
	var bob := sin(Time.get_ticks_msec() / BOB_PERIOD_MS * TAU) * BOB_PX
	global_position = Vector2(floorf(anchor.x + 0.5), floorf(anchor.y + bob + 0.5))
	visible = true
	if pop:
		if _pop != null and _pop.is_valid():
			_pop.kill()
		scale = Vector2(0.5, 0.5)
		modulate.a = 0.0
		_pop = create_tween().set_parallel(true)
		_pop.tween_property(self, "scale", Vector2.ONE, POP_MS / 1000.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pop.tween_property(self, "modulate:a", 1.0, POP_MS / 1000.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_badge() -> void:
	visible = false
	if _pop != null and _pop.is_valid():
		_pop.kill()


func _draw() -> void:
	var item := get_canvas_item()
	_shadow_box.draw(item, Rect2(-10.0, -20.0, SIZE, SIZE))
	_plate_box.draw(item, Rect2(-11.0, -22.0, SIZE, SIZE))
	# Mouse glyph, right button lit (drawMouseGlyph(centerY -11, button 2)).
	_lit_box.draw(item, Rect2(0.0, -18.5, 5.5, 6.75))
	_mouse_box.draw(item, Rect2(-5.5, -18.5, 11.0, 15.0))
	draw_line(Vector2(0.0, -18.5), Vector2(0.0, -11.75), GLYPH, 1.5)
	draw_line(Vector2(-5.5, -11.75), Vector2(5.5, -11.75), GLYPH, 1.5)


static func _box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	return box
