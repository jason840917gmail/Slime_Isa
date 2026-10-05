extends Node
## The title screen, the project's main scene (Phaser `features/shell/TitleSurfacePort.ts`,
## `ui/title-screen.scene.json`, WorldScene title mode; docs/godot/specs/shell.md section 1).
##
## A test launch (`--map`, `--spawn`, `--weapon` or `--skip-title`; `?map=` ... on the web) goes
## straight to res://game/main.tscn. Otherwise the menu shows over level-1, which drifts slowly
## behind it (WorldScene.panTitleCamera: ±360 px around the spawn + (160, 120), one sweep per
## minute) with no player, HUD or enemies, on a throwaway run; the music plays ducked. Unlike
## Phaser (where the title is a pause source) the backdrop is not paused, so NPCs wander.
##
## New Game starts a new run (asking first when a save would be replaced), Continue (shown only
## when `RunState.has_save()`) loads slot 0, Load appears when a save window registered the Shell
## action "load", Settings and Credits open the Shell's windows. Escape never closes the title.
## Uses `Services.shell()`, or its own Shell child while the autoload is not registered.
##
## Owner: shell.

const Services := preload("res://game/shared/services.gd")
const LaunchOptions := preload("res://game/shell/launch_options.gd")
const ShellScript := preload("res://game/shell/shell.gd")

const MAIN_SCENE := "res://game/main.tscn"
## GAME_VERSION (WorldScene.ts:166); `application/config/version` wins when set.
const GAME_VERSION := "0.1.0"
const BACKDROP_MAP_ID := "level-1"
const WORLD_SCENE_PREFIX := "world."
## WorldScene.ts:161-164.
const TITLE_PAN_PERIOD_MS := 60000.0
const TITLE_PAN_RANGE_PX := 360.0
const TITLE_PAN_OFFSET := Vector2(160.0, 120.0)
## TitleSurfacePort.model / start texts.
const CONFIRM_TEXT := "Start a new game? Your autosave will be replaced. Save slots are kept."
const STARTING_TEXT := "Starting…"
const LOAD_FAILED_TEXT := "That save could not be loaded."
const SAVE_SLOT := 0
const NPC_GROUP := &"npc"

## Builds the drifting world behind the menu (off in tests).
@export var backdrop_enabled: bool = true
## Launch options skip the title (off in tests).
@export var skip_for_launch_options: bool = true

## Replaces the current scene; tests replace it.
var change_scene: Callable = func(path: String) -> void: get_tree().change_scene_to_file(path)

var _shell: Node
var _confirming: bool = false
var _status: String = ""
var _pan_ms: float = 0.0
var _pan_anchor: Vector2 = Vector2.ZERO
var _backdrop_world: Node2D
var _leaving: bool = false
## The menu button that opened the current shell window; focused again when it closes.
var _return_focus: Button

@onready var backdrop: Node2D = $Backdrop
@onready var camera: Camera2D = $Camera
@onready var menu_panel: Panel = $Ui/Screen/Menu
@onready var menu_margin: MarginContainer = $Ui/Screen/Menu/Margin
@onready var new_game_button: Button = $Ui/Screen/Menu/Margin/Rows/Buttons/NewGame
@onready var continue_button: Button = $Ui/Screen/Menu/Margin/Rows/Buttons/Continue
@onready var load_button: Button = $Ui/Screen/Menu/Margin/Rows/Buttons/Load
@onready var settings_button: Button = $Ui/Screen/Menu/Margin/Rows/Buttons/Settings
@onready var credits_button: Button = $Ui/Screen/Menu/Margin/Rows/Buttons/Credits
@onready var status_label: Label = $Ui/Screen/Menu/Margin/Rows/Status
@onready var confirm_row: HBoxContainer = $Ui/Screen/Menu/Margin/Rows/Confirm
@onready var confirm_button: Button = $Ui/Screen/Menu/Margin/Rows/Confirm/ConfirmNew
@onready var cancel_button: Button = $Ui/Screen/Menu/Margin/Rows/Confirm/Cancel
@onready var version_label: Label = $Ui/Screen/Menu/Margin/Rows/Version


func _ready() -> void:
	if skip_for_launch_options and LaunchOptions.should_skip_title():
		_enter_game.call_deferred()
		return
	apply_viewport_scale()
	get_tree().root.size_changed.connect(apply_viewport_scale)
	_shell = _find_shell()
	# A shell window (Settings, Credits, the save slots) hides the title's menu while it is open,
	# so the menu does not show through it (shell windows hide the windows they cover likewise).
	_shell.connect(&"menu_opened", _on_shell_menus_changed)
	_shell.connect(&"menu_closed", _on_shell_menus_changed)
	new_game_button.pressed.connect(_on_new_game)
	continue_button.pressed.connect(_on_continue)
	load_button.pressed.connect(_on_load)
	settings_button.pressed.connect(_on_settings)
	credits_button.pressed.connect(_on_credits)
	confirm_button.pressed.connect(_begin_new_game)
	cancel_button.pressed.connect(_on_cancel)
	for button: Button in [new_game_button, continue_button, load_button, settings_button, credits_button,
			confirm_button, cancel_button]:
		button.pressed.connect(_play_click)
	if backdrop_enabled:
		_build_backdrop()
	# Phaser's title screen is a pause source, so its music plays ducked (MusicDirector).
	_set_music_ducked(true)
	refresh()
	new_game_button.grab_focus()


func _exit_tree() -> void:
	_set_music_ducked(false)
	if get_tree().root.size_changed.is_connected(apply_viewport_scale):
		get_tree().root.size_changed.disconnect(apply_viewport_scale)
	# The Shell autoload outlives the title.
	if _shell != null and is_instance_valid(_shell):
		for signal_name: StringName in [&"menu_opened", &"menu_closed"]:
			if _shell.is_connected(signal_name, _on_shell_menus_changed):
				_shell.disconnect(signal_name, _on_shell_menus_changed)


func _process(delta: float) -> void:
	if _backdrop_world != null:
		_pan_ms += delta * 1000.0
		camera.position = pan_position(_pan_anchor, _pan_ms)


## The Shell used for Settings / Credits / Load (the autoload, else this screen's own).
func get_shell() -> Node:
	return _shell


## TitleSurfacePort.model: Continue only with a save, Load only with a save window, the menu or
## the new-game confirmation, the status line and the version.
func refresh() -> void:
	var run := Services.run()
	var has_save := run != null and run.has_save(SAVE_SLOT)
	var can_load := _shell != null and bool(_shell.call(&"has_action", &"load"))
	new_game_button.visible = not _confirming
	continue_button.visible = not _confirming and has_save
	load_button.visible = not _confirming and can_load
	load_button.disabled = not has_save
	settings_button.visible = not _confirming
	credits_button.visible = not _confirming
	confirm_row.visible = _confirming
	status_label.text = CONFIRM_TEXT if _confirming else _status
	status_label.visible = not status_label.text.is_empty()
	version_label.text = "v" + version()
	_fit_menu.call_deferred()


## The menu panel keeps Phaser's 380 px width and shrinks to the buttons shown (Continue and Load
## only appear when they can be used), centred on the screen.
func _fit_menu() -> void:
	if not is_inside_tree():
		return
	var height := ceilf(menu_margin.get_combined_minimum_size().y)
	menu_panel.offset_top = -roundf(height * 0.5)
	menu_panel.offset_bottom = menu_panel.offset_top + height


## `application/config/version`, else GAME_VERSION.
static func version() -> String:
	var configured := str(ProjectSettings.get_setting("application/config/version", ""))
	return configured if not configured.is_empty() else GAME_VERSION


## The title camera centre after `elapsed_ms` (WorldScene.panTitleCamera).
static func pan_position(anchor: Vector2, elapsed_ms: float) -> Vector2:
	var drift := sin(elapsed_ms / TITLE_PAN_PERIOD_MS * TAU) * TITLE_PAN_RANGE_PX
	return anchor + TITLE_PAN_OFFSET + Vector2(drift, 0.0)


## main.gd's `apply_viewport_scale` (world spec 1.2): 1 game px = 1 CSS px, so the title and the
## game draw the UI at the same size.
func apply_viewport_scale() -> void:
	var root := get_tree().root
	var dpr := 1.0
	if OS.has_feature("web"):
		dpr = DisplayServer.screen_get_scale()
		if not is_finite(dpr) or dpr <= 0.0:
			dpr = 1.0
	var window_size := Vector2(root.size)
	var base := Vector2i(maxi(1, roundi(window_size.x / dpr)), maxi(1, roundi(window_size.y / dpr)))
	if root.content_scale_size != base:
		root.content_scale_size = base


# --- actions ------------------------------------------------------------------------------------

func _on_new_game() -> void:
	var run := Services.run()
	if run != null and run.has_save(SAVE_SLOT):
		_confirming = true
		refresh()
		cancel_button.grab_focus()
		return
	_begin_new_game()


func _begin_new_game() -> void:
	_confirming = false
	_status = STARTING_TEXT
	refresh()
	var run := Services.run()
	if run != null:
		run.new_run()
	_enter_game()


func _on_cancel() -> void:
	_confirming = false
	refresh()
	new_game_button.grab_focus()


func _on_continue() -> void:
	var run := Services.run()
	if run == null or not run.has_save(SAVE_SLOT):
		return
	_status = STARTING_TEXT
	refresh()
	if run.load_slot(SAVE_SLOT):
		_enter_game()
	else:
		_status = LOAD_FAILED_TEXT
		refresh()


func _on_load() -> void:
	if _shell != null and bool(_shell.call(&"has_action", &"load")):
		_return_focus = load_button
		_shell.call(&"run_action", &"load")


func _on_settings() -> void:
	if _shell != null:
		_return_focus = settings_button
		_shell.call(&"open_settings")


func _on_credits() -> void:
	if _shell != null:
		_return_focus = credits_button
		_shell.call(&"open_credits")


## Hides the menu while a shell window is open; when the last one closes, shows it again
## refreshed (a save may have been written or deleted) with focus back on the button that
## opened the window.
func _on_shell_menus_changed(_surface_id: StringName) -> void:
	if _leaving or not is_inside_tree():
		return
	var covered := bool(_shell.call(&"is_any_open"))
	if menu_panel.visible != covered:
		return
	menu_panel.visible = not covered
	if covered:
		return
	refresh()
	var target := _return_focus if _return_focus != null and _return_focus.is_visible_in_tree() and not _return_focus.disabled else new_game_button
	_return_focus = null
	target.grab_focus.call_deferred()


## Leaves the title for main.tscn: the backdrop world is unregistered first.
func _enter_game() -> void:
	if _leaving:
		return
	_leaving = true
	var world := Services.world()
	if world != null and _backdrop_world != null:
		world.clear()
	_backdrop_world = null
	_set_music_ducked(false)
	get_tree().paused = false
	change_scene.call(MAIN_SCENE)


func _set_music_ducked(ducked: bool) -> void:
	var music := Services.music()
	if music != null:
		music.set_menu_paused(ducked)


func _play_click() -> void:
	var sfx := get_node_or_null(^"Ui/ClickSfx")
	if sfx != null and sfx.has_method(&"play_cue"):
		sfx.call(&"play_cue")


# --- backdrop -----------------------------------------------------------------------------------

## The Shell autoload, or a Shell made for this screen.
func _find_shell() -> Node:
	var shell: Node = Services.shell()
	if shell != null:
		return shell
	shell = ShellScript.new()
	shell.name = "Shell"
	add_child(shell)
	return shell


## Instances level-1 under Backdrop on a throwaway run (RunState.ensure_started), registers it
## (water, areas), lets the NPCs wander and points the camera at the drift path.
func _build_backdrop() -> void:
	var world := Services.world()
	if world == null:
		return
	var run := Services.run()
	if run != null:
		run.ensure_started()
	var instance := world.instantiate_scene(WORLD_SCENE_PREFIX + BACKDROP_MAP_ID) as Node2D
	if instance == null:
		return
	backdrop.add_child(instance)
	if not world.register_world(instance):
		instance.queue_free()
		return
	_backdrop_world = instance
	for node: Node in get_tree().get_nodes_in_group(NPC_GROUP):
		if node.has_method(&"configure_wander") and node.has_method(&"get_instance_id_key"):
			var record := world.npc_wander_area(str(node.call(&"get_instance_id_key")))
			node.call(&"configure_wander", record.get("perimeter", {}))
	var rect := world.world_rect()
	camera.limit_left = floori(rect.position.x)
	camera.limit_top = floori(rect.position.y)
	camera.limit_right = ceili(rect.end.x)
	camera.limit_bottom = ceili(rect.end.y)
	_pan_anchor = world.player_spawn_point()
	camera.position = pan_position(_pan_anchor, 0.0)
	camera.make_current()
	camera.reset_smoothing()
