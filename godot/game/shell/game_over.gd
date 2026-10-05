extends "res://game/shell/shell_menu.gd"
## The defeat screen (Phaser `features/shell/GameOverSurfacePort.ts`, `ui/game-over.scene.json`):
## what defeated the slime and the time played, then "Wake at your bed" (or "Wake in Slimeshire")
## and "Load a save". Escape never skips it. Shown by `Shell.show_defeat()`; in the trial the
## player still respawns by itself after 1.4 s (ARCHITECTURE O5), so the Shell only shows it
## for a player that hands the respawn over (docs/godot/specs/shell.md section 6).
##
## Owner: shell.

## "wake" or "load".
signal action_requested(action_id: StringName)

## (action_id: StringName) -> bool, set by the Shell: whether "load" has something to load.
var can_run: Callable = func(_action_id: StringName) -> bool: return false

var _info: Dictionary = {}
var _waking: bool = false

@onready var cause_label: Label = $Panel/Margin/Rows/Cause
@onready var play_time_label: Label = $Panel/Margin/Rows/PlayTime
@onready var wake_button: Button = $Panel/Margin/Rows/Buttons/Wake
@onready var load_button: Button = $Panel/Margin/Rows/Buttons/Load


func _ready() -> void:
	super()
	wake_button.pressed.connect(_on_wake)
	load_button.pressed.connect(_on_load)


## `GameOverSurfacePort.show`: {"cause"?: String, "play_time_ms": float, "has_bed": bool}.
func show_defeat(info: Dictionary) -> void:
	_info = info.duplicate()
	_waking = false
	if is_open():
		refresh()
	else:
		open()


func refresh() -> void:
	var cause := str(_info.get("cause", ""))
	cause_label.text = "Defeated by %s" % cause if not cause.is_empty() else "You were defeated"
	play_time_label.text = format_play_time(float(_info.get("play_time_ms", 0.0)))
	wake_button.text = "Wake at your bed" if bool(_info.get("has_bed", false)) else "Wake in Slimeshire"
	wake_button.disabled = _waking
	load_button.disabled = _waking or not bool(can_run.call(&"load"))


## `formatPlayTime` (SaveSlotsSurfacePort.ts:39-42): "H:MM played".
static func format_play_time(ms: float) -> String:
	var minutes := floori(maxf(0.0, ms) / 60000.0)
	return "%d:%02d played" % [minutes / 60, minutes % 60]


func _on_wake() -> void:
	if _waking:
		return
	_waking = true
	close()
	action_requested.emit(&"wake")


func _on_load() -> void:
	if not _waking:
		action_requested.emit(&"load")
