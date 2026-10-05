extends Node
class_name MapUi
## The minimap and the world map (docs/godot/specs/map.md): made by the HUD (one line in hud.gd
## `_build`), kept across worlds, group "map_ui", PROCESS_MODE_ALWAYS.
##
## - `minimap` (Minimap): a Control child, so it draws on the HUD's CanvasLayer.
## - `world_map` (WorldMapWindow, res://game/ui/map/world_map_window.tscn): handed to GameWindows
##   (main's CanvasLayer 40, group "game_windows") with `add_window` as soon as GameWindows exists
##   (main makes it after the HUD is ready), which then owns its pause, Escape and cues.
## - `markers` (MapMarkers): shared by both views; `set_marker` / `clear_marker` here, on the
##   minimap or on the window all reach it.
## - The menu's tab strip: when a MenuWindows node exists (group "menu_windows",
##   game/ui/screens/menu_windows.gd) the window is its Map tab (`register_tab(&"map", window)`).
##
## Input: the `map` action (when the InputMap has it) opens the world map from `_unhandled_input`
## (GameWindows swallows keys while one of its windows is open); the window itself closes on `map`.
## The pause menu's Map button: `Shell.set_action(&"map", open_world_map)`.
##
## Owner: map (game/ui/map).

const Services := preload("res://game/shared/services.gd")
const MapMarkers := preload("res://game/ui/map/map_markers.gd")
const Minimap := preload("res://game/ui/map/minimap.gd")
const WorldMapWindow := preload("res://game/ui/map/world_map_window.gd")
const WORLD_MAP_SCENE := preload("res://game/ui/map/world_map_window.tscn")

const GROUP := &"map_ui"
const GAME_WINDOWS_GROUP := &"game_windows"
const MENU_WINDOWS_GROUP := &"menu_windows"
const MENU_TAB := &"map"
const WORLD_MAIN_GROUP := &"world_main"
const MAP_ACTION := &"map"
## The pause menu action the Shell's Map button runs.
const SHELL_ACTION := &"map"

var markers := MapMarkers.new()
var minimap: Minimap
var world_map: WorldMapWindow
var _tab_registered: bool = false


func _init() -> void:
	name = "MapUi"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_to_group(GROUP)
	minimap = Minimap.new()
	minimap.markers = markers
	add_child(minimap)
	world_map = WORLD_MAP_SCENE.instantiate() as WorldMapWindow
	world_map.markers = markers
	var shell := Services.shell()
	if shell != null:
		shell.set_action(SHELL_ACTION, open_world_map)
	var world := Services.world()
	if world != null:
		world.world_registered.connect(_on_world_registered)
	_attach_world_map()


func _exit_tree() -> void:
	var world := Services.world()
	if world != null and world.world_registered.is_connected(_on_world_registered):
		world.world_registered.disconnect(_on_world_registered)
	var shell := Services.shell()
	if shell != null and is_instance_valid(shell):
		shell.set_action(SHELL_ACTION, Callable())
	var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP) if is_inside_tree() else null
	if menu != null and menu.has_method(&"register_tab"):
		menu.call(&"register_tab", MENU_TAB, null)
	if is_instance_valid(world_map):
		world_map.close()
		if world_map.get_parent() != null:
			world_map.queue_free()
		else:
			world_map.free()


# --- public API ---------------------------------------------------------------------------------

## Opens the world map (the pause menu's Map button, the menu tab strip's Map tab). True if open.
func open_world_map() -> bool:
	_attach_world_map()
	return world_map.open()


func close_world_map() -> void:
	world_map.close()


## Opens or closes the world map; true when it is open afterwards.
func toggle_world_map() -> bool:
	_attach_world_map()
	return world_map.toggle()


func is_world_map_open() -> bool:
	return world_map.is_open()


## Adds or moves a marker on both views (docs/godot/specs/map.md 3.3).
func set_marker(id: StringName, world_point: Vector2, kind: StringName = MapMarkers.KIND_WAYPOINT, map_id: String = "") -> void:
	markers.set_marker(id, world_point, kind, map_id)


func clear_marker(id: StringName) -> void:
	markers.clear_marker(id)


func clear_markers() -> void:
	markers.clear_markers()


## The `map` key may open the world map (WorldMapSurfacePort.ts:99-106): a world runs (group
## `world_main`, not travelling), no Shell window and no other game window is open.
func can_open_from_key() -> bool:
	if not is_inside_tree() or world_map.is_open():
		return false
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	if main == null or (main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning"))):
		return false
	var shell := Services.shell()
	if shell != null and shell.is_any_open():
		return false
	var windows := get_tree().get_first_node_in_group(GAME_WINDOWS_GROUP)
	if windows == null or (windows.has_method(&"is_any_open") and bool(windows.call(&"is_any_open"))):
		return false
	return true


# --- internals ----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(MAP_ACTION) or event.is_echo() or not event.is_pressed():
		return
	if not event.is_action_pressed(MAP_ACTION):
		return
	if event is InputEventWithModifiers:
		var keys := event as InputEventWithModifiers
		if keys.ctrl_pressed or keys.alt_pressed or keys.meta_pressed:
			return
	if can_open_from_key() and open_world_map():
		get_viewport().set_input_as_handled()


## Parents the window under GameWindows once it exists (main makes it after the HUD is ready) and
## makes it the menu's Map tab once MenuWindows exists.
func _attach_world_map() -> void:
	if not is_inside_tree() or world_map == null:
		return
	if world_map.get_parent() == null:
		var windows := get_tree().get_first_node_in_group(GAME_WINDOWS_GROUP)
		if windows != null and windows.has_method(&"add_window"):
			windows.call(&"add_window", world_map)
	if world_map.get_parent() != null and not _tab_registered:
		var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP)
		if menu != null and menu.has_method(&"register_tab"):
			menu.call(&"register_tab", MENU_TAB, world_map)
			_tab_registered = true


func _on_world_registered(_payload: Dictionary) -> void:
	_attach_world_map()
	if world_map.is_open():
		world_map.refresh()
