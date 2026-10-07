extends Node
## Autoload `Shell` (registration pending: `Shell="*res://game/shell/shell.gd"`, after RunState):
## the game's frame around play (Phaser `features/shell/GameShell.ts`; docs/godot/specs/shell.md).
## Access: `Services.shell()`.
##
## Owns one CanvasLayer (layer 50, PROCESS_MODE_ALWAYS) with, bottom to top: the area title card,
## the pause menu, game over, settings, credits, controls, the end card and a fade. Keeps the
## stack of open windows; each window that pauses adds the WorldService pause reason
## `shell:<surface id>` while open (so a hit-stop ending never resumes a menu). Escape (`pause` /
## `ui_cancel`, heard in `_unhandled_input`, so a game window that consumes it closes first)
## closes the top window when it may be closed, else opens the pause menu while a world is
## running (a node in group `world_main`, not travelling, player alive).
##
## Listens, by signal only: `WorldService.world_registered` -> area title card (worlds of
## `world_main` only, not the title backdrop); `RunState.story_flag_changed` -> end cards;
## `WorldService.player_registered` -> game over for a player that hands its respawn over
## (`auto_respawn == false`; the trial player respawns itself).
##
## Works without autoload registration: instance it (`Shell.new()` from this script) under any
## node; the title screen does that while `Services.shell()` is null, and tests do too.
## Game windows owned by other features plug into the pause menu with `set_action(id, callable)`:
## "journal", "inventory", "map", "save", "load", "wake".
##
## Owner: shell.

const Services := preload("res://game/shared/services.gd")
const GameSettings := preload("res://game/shell/game_settings.gd")
const AreaTitles := preload("res://game/shell/area_titles.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ShellMenu := preload("res://game/shell/shell_menu.gd")
## The game windows' menu sounds, for the shell's own menus too.
const CUE_MENU_OPEN := &"MenuOpen"
const CUE_MENU_CLOSE := &"MenuClose"
const PauseMenu := preload("res://game/shell/pause_menu.gd")
const SettingsMenu := preload("res://game/shell/settings_menu.gd")
const ControlsMenu := preload("res://game/shell/controls_menu.gd")
const CreditsMenu := preload("res://game/shell/credits_menu.gd")
const GameOver := preload("res://game/shell/game_over.gd")
const EndCard := preload("res://game/shell/end_card.gd")
const AreaTitleCard := preload("res://game/shell/area_title_card.gd")
const PAUSE_MENU_SCENE := preload("res://game/shell/pause_menu.tscn")
const SETTINGS_MENU_SCENE := preload("res://game/shell/settings_menu.tscn")
const CONTROLS_MENU_SCENE := preload("res://game/shell/controls_menu.tscn")
const CREDITS_MENU_SCENE := preload("res://game/shell/credits_menu.tscn")
const GAME_OVER_SCENE := preload("res://game/shell/game_over.tscn")
const END_CARD_SCENE := preload("res://game/shell/end_card.tscn")
const AREA_TITLE_CARD_SCENE := preload("res://game/shell/area_title_card.tscn")

## A shell window opened / closed (its surface id).
signal menu_opened(surface_id: StringName)
signal menu_closed(surface_id: StringName)

const TITLE_SCENE := "res://game/shell/title.tscn"
const MAIN_SCENE := "res://game/main.tscn"
## main.gd joins this group; the pause menu and area cards only work while it exists.
const WORLD_MAIN_GROUP := &"world_main"
## Furniture placement (game/building/); no pause menu while it has a ghost out.
const FURNITURE_PLACEMENT_GROUP := &"furniture_placement"
## Above the HUD (10) and floating text (8), below the FPS readout (100).
const LAYER := 50
## Pause reasons are `shell:<surface id>`.
const PAUSE_REASON_PREFIX := "shell:"
const PAUSE_REASON_QUIT := &"shell:quit"
## `leaveAreaThen` fade before the reload to the title (WorldScene; AreaTravel.LEAVE_FADE_MS).
const QUIT_FADE_MS := 320.0
## The defeat screen appears 1400 ms after the killing blow (WorldScene.ts:1932).
const DEFEAT_SCREEN_DELAY_MS := 1400.0
## Phaser saves to the recovery autosave on quit; the port uses slot 0.
const AUTOSAVE_SLOT := 0
const SAVED_HINT := "Game saved"
const SAVE_FAILED_HINT := "Could not save"
## Test runs keep the default settings, so a player's settings (reduce motion turns hit-stop off)
## never change what the tests measure.
const TEST_RUNNER_SCRIPT := "res://tests/run_tests.gd"
const TEST_RUN_SETTINGS_PATH := "user://test_run_settings.cfg"

## Where the settings live; tests set another path before adding the node.
var settings_path: String = GameSettings.DEFAULT_PATH
## The player's preferences (loaded and applied in `_ready`).
var settings: GameSettings
## Replaces the current scene; tests replace it to stay in the test runner's scene.
var change_scene: Callable = func(path: String) -> void: get_tree().change_scene_to_file(path)

var layer: CanvasLayer
var root: Control
var area_title: AreaTitleCard
var pause_menu: PauseMenu
var settings_menu: SettingsMenu
var controls_menu: ControlsMenu
var credits_menu: CreditsMenu
var game_over: GameOver
var end_card: EndCard
var fade: ColorRect

var _stack: Array = []
var _actions: Dictionary = {}
var _quitting: bool = false
var _feel_applied: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var test_run := settings_path == GameSettings.DEFAULT_PATH and OS.get_cmdline_args().has(TEST_RUNNER_SCRIPT)
	if test_run:
		settings_path = TEST_RUN_SETTINGS_PATH
	settings = GameSettings.new(settings_path)
	if not test_run:
		settings.read()
	settings.apply_to_buses()
	settings.apply_to_input()
	_build()
	_connect_services()


func _exit_tree() -> void:
	for menu: ShellMenu in _stack.duplicate():
		menu.close()
	_set_paused(PAUSE_REASON_QUIT, false)


## Late-registered autoloads (and GameFeel) are picked up on the next frame.
func _process(_delta: float) -> void:
	_connect_services()


# --- public API ---------------------------------------------------------------------------------

## The player's settings (GameSettings).
func get_settings() -> GameSettings:
	return settings


## Registers the handler of a pause / game-over action that another feature owns: "journal",
## "inventory", "map" (the pause menu closes first), "save", "load" (opens a save window),
## "wake" (game over). An invalid callable removes it.
func set_action(action_id: StringName, handler: Callable) -> void:
	if handler.is_valid():
		_actions[action_id] = handler
	else:
		_actions.erase(action_id)


func has_action(action_id: StringName) -> bool:
	return _actions.has(action_id) and (_actions[action_id] as Callable).is_valid()


## True while any shell window is open.
func is_any_open() -> bool:
	return not _stack.is_empty()


## The top open window, or null.
func top_menu() -> ShellMenu:
	return _stack.back() as ShellMenu if not _stack.is_empty() else null


## Surface ids of the open windows, bottom first.
func open_menus() -> Array[StringName]:
	var ids: Array[StringName] = []
	for menu: ShellMenu in _stack:
		ids.append(menu.surface_id)
	return ids


## `canOpen` (WorldScene.ts:543-544): a world is running (group `world_main`), no shell window is
## open, no travel or quit is under way, no furniture is being placed and the player is not defeated.
func can_open_pause() -> bool:
	if is_any_open() or _quitting or not is_inside_tree():
		return false
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	if main == null:
		return false
	if main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning")):
		return false
	if _is_placing_furniture():
		return false
	var world := Services.world()
	if world != null and world.player != null and is_instance_valid(world.player) and world.player.is_dead():
		return false
	return true


## True while furniture placement (group `furniture_placement`, game/building/) has a ghost out.
func _is_placing_furniture() -> bool:
	if not is_inside_tree():
		return false
	for placement: Node in get_tree().get_nodes_in_group(FURNITURE_PLACEMENT_GROUP):
		if placement.has_method(&"is_active") and bool(placement.call(&"is_active")):
			return true
	return false


## Opens the pause menu when `can_open_pause()`; true if it opened.
func open_pause() -> bool:
	if not can_open_pause():
		return false
	pause_menu.hint_label.text = PauseMenu.HINT_TEXT
	_open(pause_menu)
	return true


func open_settings() -> void:
	_open(settings_menu)


func open_controls() -> void:
	_open(controls_menu)


func open_credits() -> void:
	_open(credits_menu)


## The area banner (also for "ability learned" lines): `title` in `color`.
func show_area_title(title: String, color: Color = AreaTitleCard.DEFAULT_COLOR) -> void:
	area_title.show_title(title, color)


## The defeat screen: {"cause"?: String, "play_time_ms": float, "has_bed": bool}.
func show_defeat(info: Dictionary) -> void:
	game_over.show_defeat(info)


## Escape: closes the top window (if it may be closed) or opens the pause menu. True if used.
func handle_escape() -> bool:
	var top := top_menu()
	if top != null:
		if top.closable_by_escape:
			top.close()
		return true
	return open_pause()


## `quitToTitle` (WorldScene.ts:645-650): closes the windows, saves the run (slot 0), fades the
## picture and the music out over 320 ms with the game paused, then clears the world and loads the
## title screen.
func quit_to_title() -> void:
	if _quitting:
		return
	_quitting = true
	for menu: ShellMenu in _stack.duplicate():
		menu.close()
	_set_paused(PAUSE_REASON_QUIT, true)
	var run := Services.run()
	if run != null:
		run.save_slot(AUTOSAVE_SLOT)
	# `leaveAreaThen` fades the music with the picture (MusicDirector.fadeOut).
	var music := Services.music()
	if music != null:
		music.fade_out(QUIT_FADE_MS)
	fade.visible = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(fade, "color:a", 1.0, QUIT_FADE_MS / 1000.0).from(0.0)
	tween.tween_callback(_finish_quit)


## Loads `path` as the current scene after clearing the world (pause reasons included).
func go_to_scene(path: String) -> void:
	for menu: ShellMenu in _stack.duplicate():
		menu.close()
	var world := Services.world()
	if world != null:
		world.clear()
	if is_inside_tree():
		get_tree().paused = false
	change_scene.call(path)


# --- input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if not (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		return
	if handle_escape():
		get_viewport().set_input_as_handled()


# --- windows ------------------------------------------------------------------------------------

func _build() -> void:
	layer = CanvasLayer.new()
	layer.name = "ShellLayer"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTokens.theme()
	layer.add_child(root)

	area_title = AREA_TITLE_CARD_SCENE.instantiate() as AreaTitleCard
	root.add_child(area_title)
	pause_menu = _add_menu(PAUSE_MENU_SCENE) as PauseMenu
	pause_menu.can_run = _can_run_pause_action
	pause_menu.action_requested.connect(_on_pause_action)
	game_over = _add_menu(GAME_OVER_SCENE) as GameOver
	game_over.can_run = _can_run_pause_action
	game_over.action_requested.connect(_on_game_over_action)
	settings_menu = _add_menu(SETTINGS_MENU_SCENE) as SettingsMenu
	settings_menu.settings = settings
	settings_menu.action_requested.connect(func(_action_id: StringName) -> void: open_controls())
	credits_menu = _add_menu(CREDITS_MENU_SCENE) as CreditsMenu
	controls_menu = _add_menu(CONTROLS_MENU_SCENE) as ControlsMenu
	end_card = _add_menu(END_CARD_SCENE) as EndCard
	end_card.action_requested.connect(func(_action_id: StringName) -> void: quit_to_title())

	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(UiTokens.PAGE, 0.0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.visible = false
	root.add_child(fade)


func _add_menu(scene: PackedScene) -> ShellMenu:
	var menu := scene.instantiate() as ShellMenu
	_attach_menu(menu)
	return menu


func _attach_menu(menu: ShellMenu) -> void:
	root.add_child(menu)
	if fade != null and fade.get_parent() == root:
		root.move_child(menu, fade.get_index())   # the quit fade stays on top of every window
	menu.opened.connect(_on_menu_opened)
	menu.closed.connect(_on_menu_closed)


func _open(menu: ShellMenu) -> void:
	if menu != null and not menu.is_open() and not _quitting:
		menu.open()


func _on_menu_opened(menu: ShellMenu) -> void:
	_stack.erase(menu)
	_stack.append(menu)
	# Only the top window shows: a covered one would show through the top panel and could take
	# keyboard focus. It stays open and shows again when the windows above it close.
	for other: ShellMenu in _stack:
		other.visible = other == menu
	if menu.pauses_game:
		_set_paused(StringName(PAUSE_REASON_PREFIX + String(menu.surface_id)), true)
	_menu_cue(CUE_MENU_OPEN)
	menu_opened.emit(menu.surface_id)


func _on_menu_closed(menu: ShellMenu) -> void:
	_stack.erase(menu)
	if menu.pauses_game:
		_set_paused(StringName(PAUSE_REASON_PREFIX + String(menu.surface_id)), false)
	if _stack.is_empty():
		_clear_player_input()
	else:
		var top := _stack.back() as ShellMenu
		top.visible = true
		top.focus_initial()
	_menu_cue(CUE_MENU_CLOSE)
	menu_closed.emit(menu.surface_id)


func _menu_cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


## WorldService pause reason; the tree directly when there is no WorldService.
func _set_paused(reason: StringName, active: bool) -> void:
	var world := Services.world()
	if world != null:
		world.set_pause_reason(reason, active)
	elif is_inside_tree():
		get_tree().paused = active


## Presses buffered while a window was open must not fire when play resumes.
func _clear_player_input() -> void:
	var world := Services.world()
	if world != null and world.player != null and is_instance_valid(world.player):
		world.player.clear_input()


func _can_run_pause_action(action_id: StringName) -> bool:
	if has_action(action_id):
		return true
	var run := Services.run()
	match action_id:
		&"settings", &"quit":
			return true
		&"save":
			return run != null
		&"load":
			return run != null and run.has_save(AUTOSAVE_SLOT)
	return false


func _on_pause_action(action_id: StringName) -> void:
	match action_id:
		&"settings":
			open_settings()
		&"quit":
			pause_menu.close()
			quit_to_title()
		&"journal", &"inventory", &"map":
			pause_menu.close()
			run_action(action_id)
		&"save":
			if has_action(&"save"):
				run_action(&"save")
				return
			var run := Services.run()
			var saved := run != null and run.save_slot(AUTOSAVE_SLOT)
			pause_menu.hint_label.text = SAVED_HINT if saved else SAVE_FAILED_HINT
		&"load":
			_load_save()


func _on_game_over_action(action_id: StringName) -> void:
	match action_id:
		&"wake":
			if has_action(&"wake"):
				run_action(&"wake")
				return
			var world := Services.world()
			if world != null and world.player != null and is_instance_valid(world.player):
				world.player.respawn()
		&"load":
			_load_save()


## The "load" action (a save-slots window), else the recovery autosave (slot 0): a running game
## reloads in place with `Main.load_run(0)`; without one, `load_slot(0)` and main.tscn boots at
## the saved spot.
func _load_save() -> void:
	if has_action(&"load"):
		run_action(&"load")
		return
	var run := Services.run()
	if run == null or not run.has_save(AUTOSAVE_SLOT):
		return
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP) if is_inside_tree() else null
	if main != null and main.has_method(&"load_run"):
		close_all_menus()
		main.call(&"load_run", AUTOSAVE_SLOT)
		return
	if run.load_slot(AUTOSAVE_SLOT):
		go_to_scene(MAIN_SCENE)


## Mounts a feature's window (a scene whose root is a ShellMenu) on the shell's layer and stack, so
## Escape, focus and its `shell:<surface id>` pause reason work as for the shell's own windows.
## Mount once (e.g. the save-slots window); it stays until the Shell leaves the tree. Null when the
## Shell is not built yet (before its `_ready`) or the scene's root is not a ShellMenu.
func mount_menu(scene: PackedScene) -> ShellMenu:
	if root == null or scene == null:
		push_warning("Shell.mount_menu: the shell is not ready or the scene is null")
		return null
	var node := scene.instantiate()
	var menu := node as ShellMenu
	if menu == null:
		push_warning("Shell.mount_menu: %s is not a ShellMenu" % scene.resource_path)
		node.free()
		return null
	_attach_menu(menu)
	return menu


## Opens a mounted window on top of the stack (ignored while quitting or when already open).
func open_menu(menu: ShellMenu) -> void:
	_open(menu)


## Closes every open shell window, top first (e.g. before loading a run in place).
func close_all_menus() -> void:
	var open_now := _stack.duplicate()
	open_now.reverse()
	for menu: ShellMenu in open_now:
		menu.close()


## Runs a registered action; false when none is registered.
func run_action(action_id: StringName) -> bool:
	if not has_action(action_id):
		return false
	(_actions[action_id] as Callable).call()
	return true


func _finish_quit() -> void:
	_set_paused(PAUSE_REASON_QUIT, false)
	go_to_scene(TITLE_SCENE)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(fade, "color:a", 0.0, QUIT_FADE_MS / 1000.0)
	tween.tween_callback(_end_quit)


func _end_quit() -> void:
	fade.visible = false
	_quitting = false


# --- service signals ------------------------------------------------------------------------------

func _connect_services() -> void:
	var world := Services.world()
	if world != null:
		if not world.world_registered.is_connected(_on_world_registered):
			world.world_registered.connect(_on_world_registered)
		if not world.player_registered.is_connected(_on_player_registered):
			world.player_registered.connect(_on_player_registered)
	var run := Services.run()
	if run != null and not run.story_flag_changed.is_connected(_on_story_flag_changed):
		run.story_flag_changed.connect(_on_story_flag_changed)
	if not _feel_applied and Services.feel() != null:
		settings.apply_to_feel()
		_feel_applied = true


func _in_world() -> bool:
	return is_inside_tree() and get_tree().get_first_node_in_group(WORLD_MAIN_GROUP) != null


## A world of the game loaded: its area banner (WorldScene.ts:515-517); end cards already earned
## in this run stay shown.
func _on_world_registered(payload: Dictionary) -> void:
	if not _in_world():
		return
	var map_id := str(payload.get("mapId", ""))
	show_area_title(AreaTitles.area_name(map_id), AreaTitles.title_color(map_id))
	var run := Services.run()
	if run != null:
		end_card.mark_existing(run.has_flag)


func _on_story_flag_changed(payload: Dictionary) -> void:
	var run := Services.run()
	if run == null or not bool(payload.get("set", true)) or not _in_world():
		return
	end_card.check_flags(run.has_flag)


## Game over only for a player that leaves its respawn to the shell (`auto_respawn == false`).
func _on_player_registered(payload: Dictionary) -> void:
	var player: Object = payload.get("player")
	if player == null or not player.has_signal(&"defeated") or player.get(&"auto_respawn") != false:
		return
	var handler := _on_player_defeated.bind(player)
	if not player.is_connected(&"defeated", handler):
		player.connect(&"defeated", handler)


func _on_player_defeated(_payload: Dictionary, player: Object) -> void:
	await get_tree().create_timer(DEFEAT_SCREEN_DELAY_MS / 1000.0, true).timeout
	if not is_instance_valid(player) or not _in_world():
		return
	var run := Services.run()
	show_defeat({
		"play_time_ms": run.play_time_ms if run != null else 0.0,
		"has_bed": run != null and not run.respawn_point().is_empty(),
	})
