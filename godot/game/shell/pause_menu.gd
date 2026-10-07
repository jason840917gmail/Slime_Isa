extends "res://game/shell/shell_menu.gd"
## The pause menu (Phaser `features/shell/PauseMenuSurfacePort.ts`, `ui/pause-menu.scene.json`):
## Resume, Journal, Inventory, Map, Settings, Save, Load and Quit to Title, with "Esc resumes".
## Every button but Resume emits `action_requested(id)` for the Shell, which closes the menu first
## for journal / inventory / map / quit (they replace it) and opens settings / save / load on top.
## Buttons whose action nobody provides yet are disabled (`can_run`, set by the Shell).
##
## Owner: shell.

## A button was pressed: "resume", "journal", "inventory", "map", "settings", "save", "load", "quit".
signal action_requested(action_id: StringName)

## PauseMenuSurfacePort.model `hint`.
const HINT_TEXT := "Esc resumes"
## Button node -> action id.
const BUTTON_ACTIONS := {
	^"Panel/Margin/Rows/Buttons/Resume": &"resume",
	^"Panel/Margin/Rows/Buttons/Journal": &"journal",
	^"Panel/Margin/Rows/Buttons/Inventory": &"inventory",
	^"Panel/Margin/Rows/Buttons/Map": &"map",
	^"Panel/Margin/Rows/Buttons/Settings": &"settings",
	^"Panel/Margin/Rows/Buttons/Save": &"save",
	^"Panel/Margin/Rows/Buttons/Load": &"load",
	^"Panel/Margin/Rows/Buttons/QuitToTitle": &"quit",
}

## (action_id: StringName) -> bool: whether a button can run now. Default: every one.
var can_run: Callable = func(_action_id: StringName) -> bool: return true

@onready var hint_label: Label = $Panel/Margin/Rows/Hint


func _ready() -> void:
	super()
	for path: NodePath in BUTTON_ACTIONS:
		var button := get_node(path) as Button
		button.pressed.connect(_on_button.bind(BUTTON_ACTIONS[path]))


func refresh() -> void:
	hint_label.text = HINT_TEXT
	for path: NodePath in BUTTON_ACTIONS:
		var action_id: StringName = BUTTON_ACTIONS[path]
		(get_node(path) as Button).disabled = action_id != &"resume" and not bool(can_run.call(action_id))


## The button for `action_id` (tests, focus).
func button_for(action_id: StringName) -> Button:
	for path: NodePath in BUTTON_ACTIONS:
		if BUTTON_ACTIONS[path] == action_id:
			return get_node(path) as Button
	return null


func _on_button(action_id: StringName) -> void:
	if action_id == &"resume":
		close()
		return
	action_requested.emit(action_id)
