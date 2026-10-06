extends Node2D
## The Gulp HUD (Phaser `features/gulp/GulpHud.ts`; abilities spec 11.5): in a form, the form's
## badge (36 px, `ui-gulp-form-icons`) and the time left "1:00" (seconds rounded up) centred over
## the slime: width = text width + 40, the badge's bottom-right at (left + 36, centre.y - 70), the
## text's bottom-left at (left + 40, centre.y - 76); without the badge sheet, "HEAVY 1:00" alone.
## Near a spot, "[Q] Gulp" (#ffe89a) over that spot. World space, drawn over everything.
##
## Owner: abilities.

const TIMER_RISE := 76.0
const FONT_SIZE := 14
const OUTLINE := 4
const TIMER_COLOR := Color("#e7fff5")
const HINT_COLOR := Color("#ffe89a")
const OUTLINE_COLOR := Color("#101a31")
## `ui.icons.gulp-forms.2x1`: frame 0 Heavy, 1 Sticky (128 px cells).
const BADGE_SHEET := "res://asset/UI/ui-gulp-form-icons-3x1.webp"
const BADGE_CELL := 128
const BADGE_SIZE := 36.0
const BADGE_GAP := 40.0
const BADGE_RISE := 70.0

## player.gd: get_centre, current_form, form_remaining_ms, nearest_gulp_spot, is_dead.
var player: Node
var _timer: Label
var _hint: Label
var _badge: TextureRect
var _badge_sheet: Texture2D


func _ready() -> void:
	top_level = true
	z_index = 100
	_timer = _make_label("Timer", TIMER_COLOR)
	_hint = _make_label("Hint", HINT_COLOR)
	_hint.text = "[%s] Gulp" % _eat_key()
	if ResourceLoader.exists(BADGE_SHEET):
		_badge_sheet = load(BADGE_SHEET)
	_badge = TextureRect.new()
	_badge.name = "Badge"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	_badge.visible = false
	add_child(_badge)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var dead := bool(player.call(&"is_dead"))
	var form: Dictionary = player.call(&"current_form")
	_timer.visible = not form.is_empty() and not dead
	_badge.visible = _timer.visible and _badge_sheet != null
	if _timer.visible:
		var seconds := ceili(float(player.call(&"form_remaining_ms")) / 1000.0)
		var clock := "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
		var centre: Vector2 = player.call(&"get_centre")
		if _badge.visible:
			_timer.text = clock
			_show_badge(int(form.get("badge_frame", 0)))
			var width := _timer.get_minimum_size().x + BADGE_GAP
			var left := roundf(centre.x - width / 2.0)
			_badge.position = Vector2(left + BADGE_SIZE, centre.y - BADGE_RISE) - _badge.size
			var text_size := _timer.get_minimum_size()
			_timer.position = Vector2(left + BADGE_GAP, roundf(centre.y - TIMER_RISE - text_size.y))
		else:
			_timer.text = "%s %s" % [str(form["name"]).to_upper(), clock]
			_place(_timer, centre - Vector2(0.0, TIMER_RISE))
	var spot: Node = player.call(&"nearest_gulp_spot") if not dead else null
	_hint.visible = spot != null
	if spot != null:
		_place(_hint, (spot.call(&"origin") as Vector2) - Vector2(0.0, float(spot.get(&"badge_rise"))))


func _show_badge(frame: int) -> void:
	var atlas := _badge.texture as AtlasTexture
	if atlas == null:
		atlas = AtlasTexture.new()
		atlas.atlas = _badge_sheet
		_badge.texture = atlas
	atlas.region = Rect2(frame * BADGE_CELL, 0, BADGE_CELL, BADGE_CELL)


## Bottom-centre of `label` at `at`.
func _place(label: Label, at: Vector2) -> void:
	var size := label.get_minimum_size()
	label.position = (at - Vector2(size.x / 2.0, size.y)).round()


func _make_label(label_name: String, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font_size = FONT_SIZE
	settings.font_color = color
	settings.outline_size = OUTLINE
	settings.outline_color = OUTLINE_COLOR
	label.label_settings = settings
	label.visible = false
	add_child(label)
	return label


static func _eat_key() -> String:
	for event: InputEvent in InputMap.action_get_events(&"eat"):
		if event is InputEventKey:
			var key := event as InputEventKey
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	return "Q"
