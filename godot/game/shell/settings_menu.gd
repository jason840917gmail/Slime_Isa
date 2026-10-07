extends "res://game/shell/shell_menu.gd"
## The Settings window, from the title or the pause menu (Phaser `features/shell/
## SettingsSurfacePort.ts`, `ui/settings.scene.json`): master, effects and music volume, screen
## shake, mute, reduce motion, defaults and the controls list. Edits go straight to the
## GameSettings (`settings`), which saves and applies them; the window redraws on `changed`.
##
## Owner: shell.

const GameSettings := preload("res://game/shell/game_settings.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

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


func _on_reset() -> void:
	if settings != null:
		settings.reset()


func _on_settings_changed(_values: Dictionary) -> void:
	if is_node_ready():
		refresh()

