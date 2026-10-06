extends Node2D
## The Gulp quick wheel (Phaser `features/gulp/GulpWheel.ts` + `GulpWheelLayout.ts`; abilities spec
## 11.4 and 11.6): holding Q for 250 ms opens a ring of the carried Gulp materials round the slime;
## a direction (movement keys, else the pointer) picks a slot, and letting go of Q eats that
## material from the bag. Drawn in the world over everything; nothing pauses while it is open.
##
## Look: a ring backdrop between radii 72 ± 33 (fill rgba(11, 20, 38, 0.58), 2 px #ffe89a at 60 %
## on both edges); one disc (r 25) per entry, slot `i` of `n` at -90 + i * 360 / n degrees (first at
## the top, clockwise); the chosen disc is larger (x 1.15), green (#3a5a2c) with a 3 px #ffe89a
## edge, the others #1b2a45 with a 2 px #6d7fa6 edge (both 95 %); in each the form's badge
## (46 px; alpha 1 chosen, 0.75 otherwise), the count at the slot + (14, 12) (12 px, outline 3);
## the chosen form's name upper-case (or "GULP") 115 px below the centre (13 px #ffe89a, outline 4).
##
## Owner: abilities.

const RING_RADIUS := 72.0
const SLOT_RADIUS := 25.0
const ICON_SIZE := 46.0
const RING_PADDING := 8.0
const CHOSEN_SCALE := 1.15
## GULP_WHEEL_HOLD_MS (GulpWheelLayout.ts:2).
const HOLD_MS := 250.0
const BADGE_SHEET := "res://asset/UI/ui-gulp-form-icons-3x1.webp"
const BADGE_CELL := 128
const RING_FILL := Color(11.0 / 255.0, 20.0 / 255.0, 38.0 / 255.0, 0.58)
const RING_EDGE := Color(1.0, 232.0 / 255.0, 154.0 / 255.0, 0.6)
const DISC := Color(Color("#1b2a45"), 0.95)
const DISC_CHOSEN := Color(Color("#3a5a2c"), 0.95)
const EDGE := Color("#6d7fa6")
const EDGE_CHOSEN := Color("#ffe89a")
const TITLE_COLOR := Color("#ffe89a")
const TEXT_COLOR := Color("#f5f7ff")
const SHADOW := Color("#081022")
const TITLE_SIZE := 13
const COUNT_SIZE := 12

## [{"item_id": String, "form": Dictionary (gulp_forms.gd), "count": int}] in table order.
var entries: Array = []
## The chosen slot (-1 = none).
var selected: int = -1
var _badge_sheet: Texture2D


func _ready() -> void:
	top_level = true
	z_index = 101
	visible = false
	if ResourceLoader.exists(BADGE_SHEET):
		_badge_sheet = load(BADGE_SHEET)


func is_open() -> bool:
	return visible


func open(new_entries: Array, chosen: int) -> void:
	entries = new_entries.duplicate()
	selected = chosen
	visible = true
	queue_redraw()


## Follows the slime (`centre`) and lights slot `chosen`.
func follow(centre: Vector2, chosen: int) -> void:
	global_position = centre
	if chosen != selected:
		selected = chosen
	queue_redraw()


func close() -> void:
	visible = false
	entries = []
	selected = -1


## The chosen form's name upper-case, or "GULP".
func title_text() -> String:
	if selected >= 0 and selected < entries.size():
		return str((entries[selected]["form"] as Dictionary).get("name", "")).to_upper()
	return "GULP"


## `gulpWheelSlotAngle`: degrees, 0 = right, 90 = down; the first slot at the top, clockwise.
static func slot_angle(index: int, count: int) -> float:
	return -90.0 + index * 360.0 / maxf(1.0, float(count))


## `pickGulpWheelSlot`: the slot nearest `direction`'s angle; -1 without a direction.
static func pick_slot(direction: Vector2, count: int) -> int:
	if count < 1 or direction.length() < 1e-6:
		return -1
	var angle := rad_to_deg(atan2(direction.y, direction.x))
	var best := 0
	var best_distance := INF
	for index in count:
		var raw := fmod(absf(angle - slot_angle(index, count)), 360.0)
		var distance := minf(raw, 360.0 - raw)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


func _draw() -> void:
	if entries.is_empty():
		return
	var outer := RING_RADIUS + SLOT_RADIUS + RING_PADDING
	var inner := RING_RADIUS - SLOT_RADIUS - RING_PADDING
	_draw_ring(inner, outer)
	var font := ThemeDB.fallback_font
	for index in entries.size():
		var chosen := index == selected
		var at := Vector2.from_angle(deg_to_rad(slot_angle(index, entries.size()))) * RING_RADIUS
		var radius := SLOT_RADIUS * (CHOSEN_SCALE if chosen else 1.0)
		draw_circle(at, radius, DISC_CHOSEN if chosen else DISC)
		draw_arc(at, radius, 0.0, TAU, 40, EDGE_CHOSEN if chosen else EDGE, 3.0 if chosen else 2.0, true)
		var form: Dictionary = entries[index]["form"]
		if _badge_sheet != null:
			var region := Rect2(int(form.get("badge_frame", 0)) * BADGE_CELL, 0, BADGE_CELL, BADGE_CELL)
			draw_texture_rect_region(_badge_sheet, Rect2(at - Vector2.ONE * ICON_SIZE / 2.0, Vector2.ONE * ICON_SIZE), region,
				Color(1, 1, 1, 1.0 if chosen else 0.75))
		_draw_centred(font, at + Vector2(14.0, 12.0), str(entries[index]["count"]), COUNT_SIZE, TEXT_COLOR, 3)
	_draw_centred(font, Vector2(0.0, RING_RADIUS + SLOT_RADIUS + 18.0), title_text(), TITLE_SIZE, TITLE_COLOR, 4)


## The backdrop: an annulus between `inner` and `outer`, both edges stroked.
func _draw_ring(inner: float, outer: float) -> void:
	var segments := 64
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		draw_colored_polygon(PackedVector2Array([Vector2.from_angle(a0) * inner, Vector2.from_angle(a0) * outer,
			Vector2.from_angle(a1) * outer, Vector2.from_angle(a1) * inner]), RING_FILL)
	draw_arc(Vector2.ZERO, outer, 0.0, TAU, segments, RING_EDGE, 2.0, true)
	draw_arc(Vector2.ZERO, inner, 0.0, TAU, segments, RING_EDGE, 2.0, true)


## Text centred on `at` (both axes) with a dark outline.
func _draw_centred(font: Font, at: Vector2, text: String, size: int, color: Color, outline: int) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var baseline := at + Vector2(-text_size.x / 2.0, font.get_ascent(size) - text_size.y / 2.0)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, SHADOW)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
