extends Control
class_name ShellMenu
## Base of the shell windows: pause, settings, controls, credits, game over and end card
## (Phaser `features/shell/MenuSurface.ts`). One full-screen Control that stops the mouse (the
## world behind takes no clicks) holding a themed panel. `open()` shows it, focuses its first
## button and emits `opened`; `close()` hides it and emits `closed`. The Shell keeps the stack of
## open windows, pauses the game while one is open (`pauses_game`) and routes Escape to the top
## one (`closable_by_escape`). Every button plays the click cue; sliders play the select cue.
##
## Subclasses override `refresh()` (fill the window from the current state) and connect their
## buttons in `_ready()` after calling `super()`.
##
## Owner: shell.

signal opened(menu: ShellMenu)
signal closed(menu: ShellMenu)

## Phaser surface id; also the WorldService pause reason while the window is open.
@export var surface_id: StringName = &""
## False for windows Escape must not close (game over, end card).
@export var closable_by_escape: bool = true
## The simulation pauses while the window is open.
@export var pauses_game: bool = true
## Focused when the window opens; the first visible enabled button when empty or unusable.
@export var initial_focus: NodePath

var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	for node: Node in find_children("*", "BaseButton", true, false):
		(node as BaseButton).pressed.connect(_play_click)
	for node: Node in find_children("*", "Range", true, false):
		if node is Slider:
			(node as Slider).value_changed.connect(_play_select)


func is_open() -> bool:
	return _open


## Shows the window (no-op when open): `_on_opening()`, `refresh()`, focus, `opened`.
func open() -> void:
	if _open:
		return
	_open = true
	_on_opening()
	refresh()
	visible = true
	opened.emit(self)
	focus_initial()


## Hides the window (no-op when closed) and emits `closed`.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit(self)


## Fills the window from the current state; called on open and whenever the state changes.
func refresh() -> void:
	pass


## Resets per-opening state (MenuSurface.onOpened).
func _on_opening() -> void:
	pass


## Focuses `initial_focus`, or the first visible enabled button.
func focus_initial() -> void:
	var target := get_node_or_null(initial_focus) as Control
	if target == null or not _focusable(target):
		target = null
		for node: Node in find_children("*", "BaseButton", true, false):
			if _focusable(node as Control):
				target = node as Control
				break
	if target != null:
		target.grab_focus()


static func _focusable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return false
	var button := control as BaseButton
	return button == null or not button.disabled


func _play_click() -> void:
	var sfx := get_node_or_null(^"ClickSfx")
	if sfx != null and sfx.has_method(&"play_cue"):
		sfx.call(&"play_cue")


func _play_select(_value: float) -> void:
	var sfx := get_node_or_null(^"SelectSfx")
	if sfx != null and sfx.has_method(&"play_cue") and visible:
		sfx.call(&"play_cue")
