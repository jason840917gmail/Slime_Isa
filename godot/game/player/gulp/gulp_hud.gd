extends Node2D
## The Gulp HUD (Phaser `features/gulp/GulpHud.ts`; abilities spec 11.5): in a form, "HEAVY 1:00"
## over the slime (seconds rounded up); near a spot, "[Q] Gulp" (#ffe89a) over that spot. World
## space, drawn over everything. The form badge icon is not ported yet (text only, Phaser's
## fallback when the badge texture is missing).
##
## Owner: abilities.

const TIMER_RISE := 76.0
const FONT_SIZE := 14
const OUTLINE := 4
const TIMER_COLOR := Color("#e7fff5")
const HINT_COLOR := Color("#ffe89a")
const OUTLINE_COLOR := Color("#101a31")

## player.gd: get_centre, current_form, form_remaining_ms, nearest_gulp_spot, is_dead.
var player: Node
var _timer: Label
var _hint: Label


func _ready() -> void:
	top_level = true
	z_index = 100
	_timer = _make_label("Timer", TIMER_COLOR)
	_hint = _make_label("Hint", HINT_COLOR)
	_hint.text = "[%s] Gulp" % _eat_key()


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var dead := bool(player.call(&"is_dead"))
	var form: Dictionary = player.call(&"current_form")
	_timer.visible = not form.is_empty() and not dead
	if _timer.visible:
		var seconds := ceili(float(player.call(&"form_remaining_ms")) / 1000.0)
		_timer.text = "%s %d:%02d" % [str(form["name"]).to_upper(), seconds / 60, seconds % 60]
		_place(_timer, (player.call(&"get_centre") as Vector2) - Vector2(0.0, TIMER_RISE))
	var spot: Node = player.call(&"nearest_gulp_spot") if not dead else null
	_hint.visible = spot != null
	if spot != null:
		_place(_hint, (spot.call(&"origin") as Vector2) - Vector2(0.0, float(spot.get(&"badge_rise"))))


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
