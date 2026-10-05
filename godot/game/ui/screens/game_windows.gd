extends CanvasLayer
## The game windows' owner (Phaser `ModalStack` + `setSimulationPaused` for the world's windows):
## a CanvasLayer (layer 40: above the HUD 10, below the Shell 50) made once as main's child
## "GameWindows", kept across worlds. Every game window (the bag, crafting, the menu tabs, the
## dialogue box, the quest offer window, later the chest, journal and map) is a Control child of
## it and reports itself with `push` when it opens and `pop` when it closes.
##
## While any window is open this node holds the `modal` pause reason (WorldService.PAUSE_MODAL):
## the tree pauses, the player clears its input and stops (player.gd `_update_modal_pause`) and the
## music ducks (MusicDirector). One owner for the reason, so one window closing never unpauses
## another; a hand-over inside one call (a tab switch, dialogue to offer window) never runs the tree
## in between. When the last window closes the player's input is cleared again (presses buffered
## while paused must not fire).
##
## Input: Escape (`ui_cancel` / `pause`) reaching `_unhandled_input` closes the top window (main's
## children hear unhandled input before the Shell autoload, so the pause menu does not open); every
## other key and mouse button press that reaches it while a window is open is swallowed (the DOM
## modal key trap), so the player buffers nothing. Windows that use keys themselves (the dialogue
## box) handle them in `_input`.
##
## Cues: MenuOpen on a push, MenuClose on a pop (AudioEventBridge.ts:104-109), unless the window
## asks for silence.
##
## Owner: UI (game windows).

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const LAYER := 40
const GROUP := &"game_windows"

## A window opened. Payload: the surface id ("inventory", "crafting", "npc-dialogue", ...).
signal window_opened(surface_id: StringName)
## A window closed.
signal window_closed(surface_id: StringName)

## Open windows, oldest first: [{"window": Node, "surface_id": StringName}].
var _stack: Array[Dictionary] = []
## Full-screen Control parent of the windows (theme root).
var root: Control


func _init() -> void:
	name = "GameWindows"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_to_group(GROUP)
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTokens.theme()
	add_child(root)


## Adds a window (a Control) under the shared root.
func add_window(window: Control) -> void:
	root.add_child(window)


## `window` opened as `surface_id`. The first open window pauses the world.
func push(window: Node, surface_id: StringName, quiet: bool = false) -> void:
	if is_window_open(window):
		return
	_stack.append({"window": window, "surface_id": surface_id})
	_sync_pause()
	if not quiet:
		_cue(&"MenuOpen")
	window_opened.emit(surface_id)


## `window` closed. The last one to close unpauses the world and clears the player's input.
func pop(window: Node, quiet: bool = false) -> void:
	for index in _stack.size():
		if _stack[index]["window"] == window:
			var surface_id: StringName = _stack[index]["surface_id"]
			_stack.remove_at(index)
			_sync_pause()
			if not quiet:
				_cue(&"MenuClose")
			if _stack.is_empty():
				_clear_player_input()
			window_closed.emit(surface_id)
			return


func is_any_open() -> bool:
	return not _stack.is_empty()


func is_window_open(window: Node) -> bool:
	for entry in _stack:
		if entry["window"] == window:
			return true
	return false


## True when a window with `surface_id` is open.
func is_open(surface_id: StringName) -> bool:
	for entry in _stack:
		if entry["surface_id"] == surface_id:
			return true
	return false


## The surface ids of the open windows, oldest first.
func open_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in _stack:
		ids.append(entry["surface_id"])
	return ids


## The newest open window, or null.
func top() -> Node:
	return _stack.back()["window"] if not _stack.is_empty() else null


## Closes every open window, newest first (world teardown, a load). Each window's `close()` pops
## itself; a window that does not is dropped.
func close_all() -> void:
	var guard := _stack.size() + 1
	while not _stack.is_empty() and guard > 0:
		guard -= 1
		var window: Node = _stack.back()["window"]
		if is_instance_valid(window) and window.has_method(&"close"):
			window.call(&"close")
		if not _stack.is_empty() and _stack.back()["window"] == window:
			pop(window, true)


func _unhandled_input(event: InputEvent) -> void:
	if _stack.is_empty():
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventAction):
		return
	if event.is_pressed() and not event.is_echo() and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		var window := top()
		if is_instance_valid(window) and window.has_method(&"close"):
			window.call(&"close")
		else:
			pop(window)
	get_viewport().set_input_as_handled()


func _sync_pause() -> void:
	var world := Services.world()
	if world != null:
		world.set_pause_reason(Services.WorldServiceType.PAUSE_MODAL, not _stack.is_empty())


func _clear_player_input() -> void:
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	if player != null and is_instance_valid(player) and player.has_method(&"clear_input"):
		player.call(&"clear_input")


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


func _exit_tree() -> void:
	if not _stack.is_empty():
		_stack.clear()
		_sync_pause()
