extends "res://game/shell/shell_menu.gd"
## The Settings window, from the title or the pause menu (Phaser `features/shell/
## SettingsSurfacePort.ts`, `ui/settings.scene.json`): master, effects and music volume, screen
## shake, mute, reduce motion, the mouse control scheme, defaults and the controls list. Edits go straight to the
## GameSettings (`settings`), which saves and applies them; the window redraws on `changed`.
## In the body-shapes rework mode (docs/godot/BODY_SHAPES.md "Juice") a "Damage numbers" row under
## the scheme row turns the rework's damage numbers on and off; outside it the row is hidden and the
## window is as before.
##
## Owner: shell.

const GameSettings := preload("res://game/shell/game_settings.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ControlScheme := preload("res://game/player/mouse/control_scheme.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
## The control scheme row: its height, and how much taller the panel gets (row + separation).
const SCHEME_ROW_HEIGHT := 38.0
const SCHEME_ROW_GROWTH := 48.0

## "controls": the Controls button (the Shell opens the controls list on top).
signal action_requested(action_id: StringName)

const STATUS_MUTED := "All sound is muted"
const STATUS_SAVED := "Changes apply immediately and are saved on this device"
## Slider row -> [setting key, caption].
const SLIDERS := {
	^"Panel/Margin/Rows/Sliders/Master": ["master", "Master volume"],
	^"Panel/Margin/Rows/Sliders/Effects": ["effects", "Sound effects"],
	^"Panel/Margin/Rows/Sliders/Music": ["music", "Music"],
	^"Panel/Margin/Rows/Sliders/Shake": ["screen_shake", "Screen shake"],
}

## The settings this window edits (the Shell's). Null shows the defaults read-only.
var settings: GameSettings:
	set(value):
		if settings != null and settings.changed.is_connected(_on_settings_changed):
			settings.changed.disconnect(_on_settings_changed)
		settings = value
		if settings != null:
			settings.changed.connect(_on_settings_changed)
		if is_node_ready():
			refresh()

@onready var motion_button: Button = $Panel/Margin/Rows/Toggles/Motion
@onready var controls_button: Button = $Panel/Margin/Rows/Toggles/Controls
@onready var status_label: Label = $Panel/Margin/Rows/Status
@onready var mute_button: Button = $Panel/Margin/Rows/Bottom/Mute
@onready var reset_button: Button = $Panel/Margin/Rows/Bottom/Reset
@onready var close_button: Button = $Panel/Margin/Rows/Bottom/Close
## "Mouse: Click to move (Diablo)" (`_add_scheme_button`).
var scheme_button: Button
## "Damage numbers: On" (`_add_numbers_button`; rework mode only), and whether the panel grew for it.
var numbers_button: Button
var _numbers_row_shown: bool = false


func _ready() -> void:
	super()
	for row_path: NodePath in SLIDERS:
		var slider := slider_for(str(SLIDERS[row_path][0]))
		slider.value_changed.connect(_on_slider_changed.bind(str(SLIDERS[row_path][0])))
	motion_button.pressed.connect(_toggle.bind("reduce_motion"))
	mute_button.pressed.connect(_toggle.bind("muted"))
	reset_button.pressed.connect(_on_reset)
	controls_button.pressed.connect(func() -> void: action_requested.emit(&"controls"))
	close_button.pressed.connect(close)
	_add_scheme_button()
	_add_numbers_button()


## SettingsSurfacePort.model: captions with percentages, the shake slider off under reduce motion,
## the mute / motion labels and the status line.
func refresh() -> void:
	var values: Dictionary = settings.values() if settings != null else GameSettings.DEFAULTS.duplicate()
	var reduce_motion := bool(values["reduce_motion"])
	var muted := bool(values["muted"])
	for row_path: NodePath in SLIDERS:
		var key := str(SLIDERS[row_path][0])
		var slider := slider_for(key)
		var caption := get_node(String(row_path) + "/Caption") as Label
		slider.set_value_no_signal(float(values[key]))
		caption.text = "%s  %s" % [SLIDERS[row_path][1], percent(float(values[key]))]
	var shake := slider_for("screen_shake")
	shake.editable = not reduce_motion
	shake.modulate.a = UiTokens.DISABLED_ALPHA if reduce_motion else 1.0
	if reduce_motion:
		(get_node(^"Panel/Margin/Rows/Sliders/Shake/Caption") as Label).text = "Screen shake  off (reduce motion)"
	mute_button.text = "Unmute" if muted else "Mute all"
	motion_button.text = "Reduce motion: On" if reduce_motion else "Reduce motion: Off"
	if scheme_button != null:
		scheme_button.text = "Mouse: %s" % ControlScheme.display_name(str(values.get("control_scheme", "")))
	if numbers_button != null:
		_show_numbers_row(ReworkMode.is_on())
		numbers_button.text = "Damage numbers: On" if bool(values.get("damage_numbers", true)) else "Damage numbers: Off"
	status_label.text = STATUS_MUTED if muted else STATUS_SAVED


## The slider that edits `key` ("master", "effects", "music", "screen_shake").
func slider_for(key: String) -> HSlider:
	for row_path: NodePath in SLIDERS:
		if str(SLIDERS[row_path][0]) == key:
			return get_node(String(row_path) + "/Slider") as HSlider
	return null


## "80%" (`Math.round(value * 100)`).
static func percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _on_slider_changed(value: float, key: String) -> void:
	if settings != null:
		settings.update({key: clampf(value, 0.0, 1.0)})


func _toggle(key: String) -> void:
	if settings != null:
		settings.update({key: not bool(settings.value(key))})


## The control scheme row under the toggles (game/player/mouse/control_scheme.gd): one button that
## cycles keyboard -> click to move -> right-click to move. Built here, so the panel grows by it.
func _add_scheme_button() -> void:
	var toggles := get_node(^"Panel/Margin/Rows/Toggles") as Control
	scheme_button = Button.new()
	scheme_button.name = "ControlScheme"
	scheme_button.custom_minimum_size = Vector2(toggles.custom_minimum_size.x, SCHEME_ROW_HEIGHT)
	scheme_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toggles.add_sibling(scheme_button)
	scheme_button.pressed.connect(_on_scheme_pressed)
	var panel := get_node(^"Panel") as Control
	panel.offset_top -= SCHEME_ROW_GROWTH / 2.0
	panel.offset_bottom += SCHEME_ROW_GROWTH / 2.0
	refresh()


## The rework's damage numbers row under the scheme row: built hidden; `refresh` shows it (and grows
## the panel by a row) only while the rework mode is on.
func _add_numbers_button() -> void:
	var toggles := get_node(^"Panel/Margin/Rows/Toggles") as Control
	numbers_button = Button.new()
	numbers_button.name = "DamageNumbers"
	numbers_button.custom_minimum_size = Vector2(toggles.custom_minimum_size.x, SCHEME_ROW_HEIGHT)
	numbers_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	numbers_button.visible = false
	scheme_button.add_sibling(numbers_button)
	numbers_button.pressed.connect(_toggle.bind("damage_numbers"))
	refresh()


func _show_numbers_row(shown: bool) -> void:
	if shown == _numbers_row_shown:
		return
	_numbers_row_shown = shown
	numbers_button.visible = shown
	var growth := SCHEME_ROW_GROWTH / 2.0 if shown else -SCHEME_ROW_GROWTH / 2.0
	var panel := get_node(^"Panel") as Control
	panel.offset_top -= growth
	panel.offset_bottom += growth


func _on_scheme_pressed() -> void:
	if settings != null:
		settings.update({"control_scheme": ControlScheme.next(str(settings.value("control_scheme")))})


func _on_reset() -> void:
	if settings != null:
		settings.reset()


func _on_settings_changed(_values: Dictionary) -> void:
	if is_node_ready():
		refresh()

