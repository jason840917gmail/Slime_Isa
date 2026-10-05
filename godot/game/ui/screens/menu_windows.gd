extends Node
## The menu key and the menu's windows (Phaser `WorldScene.toggleMenu`, `openCraftingStation`,
## `MenuTabsSurfacePort`; crafting spec 4.1, 5): a child "MenuWindows" of GameWindows, made once by
## main.gd, group `menu_windows`, PROCESS_MODE_ALWAYS. It makes the bag (inventory_screen.gd), the
## crafting window (crafting_screen.gd) and the tab strip (menu_tabs.gd) and adds them to
## GameWindows, which holds the pause and Escape.
##
## Menu key (`menu`, E; heard in `_input`, so it works while a window holds the focus): ignored
## with Ctrl / Alt / Meta, on echo and with no world; with a shell window open nothing happens; an
## open tab window (bag, crafting, journal, map) closes; else the bag opens unless the slime is
## mid-swing, the game is paused by another window or menu, or a travel runs (it opens while dead,
## K15). The pause menu's Inventory button opens the bag (Shell action "inventory").
##
## Tabs: Bag and Crafting (the Crafting tab opens the portable site: a station is not reached
## back through the tabs, K4); Journal and Map stay disabled until their windows are registered
## with `register_tab` (a window with open / close / is_open, or three callables). Without a
## registration the Map tab falls back on the map UI (group `map_ui`: `open_world_map`,
## `close_world_map`, `is_world_map_open`). The first-time coach under the strip is learned
## (story flag `hint.menu-tabs`) by a tab click or by closing the menu after reading it 3 s.
##
## Owner: crafting / inventory (UI).

const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const InventoryScreen := preload("res://game/ui/screens/inventory_screen.gd")
const CraftingScreen := preload("res://game/ui/screens/crafting_screen.gd")
const MenuTabs := preload("res://game/ui/screens/menu_tabs.gd")

const GROUP := &"menu_windows"
const MAIN_GROUP := &"world_main"
const TABS: Array[StringName] = [&"inventory", &"crafting", &"journal", &"map"]
## MenuTabsSurfacePort: the coach's story flag and how long it must be read (wall clock).
const COACH_FLAG := "hint.menu-tabs"
const COACH_READ_MS := 3000.0
const PAUSE_QUIT := &"shell:quit"
const MAP_UI_GROUP := &"map_ui"

var bag: InventoryScreen
var crafting: CraftingScreen
var tabs: MenuTabs
## tab id -> {"open": Callable, "close": Callable, "is_open": Callable}.
var _tabs: Dictionary = {}
var _coach_shown_at_ms: float = -1.0


func _init() -> void:
	name = "MenuWindows"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_to_group(GROUP)
	var windows := _game_windows()
	bag = InventoryScreen.new()
	crafting = CraftingScreen.new()
	tabs = MenuTabs.new()
	if windows != null:
		windows.call(&"add_window", bag)
		windows.call(&"add_window", crafting)
		windows.call(&"add_window", tabs)
		windows.connect(&"window_opened", _on_windows_changed)
		windows.connect(&"window_closed", _on_windows_changed)
	register_tab(&"inventory", bag)
	register_tab(&"crafting", func() -> void: open_crafting(RecipeCatalog.PORTABLE_SITE), crafting.close, crafting.is_open)
	tabs.tab_pressed.connect(switch_tab)
	var shell := Services.shell()
	if shell != null:
		shell.set_action(&"inventory", _open_bag_from_pause)
	_sync_tabs()


func _exit_tree() -> void:
	var shell := Services.shell()
	if shell != null and shell.has_action(&"inventory"):
		shell.set_action(&"inventory", Callable())


## The menu key (crafting spec 5.1, 11.7).
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"menu") or event.is_echo():
		return
	var modifiers := event as InputEventWithModifiers
	if modifiers != null and (modifiers.ctrl_pressed or modifiers.alt_pressed or modifiers.meta_pressed):
		return
	if get_tree().get_first_node_in_group(MAIN_GROUP) == null:
		return
	if toggle_menu():
		get_viewport().set_input_as_handled()


# --- API -------------------------------------------------------------------------------------------

## `toggleMenu`: closes the open tab window, else opens the bag when allowed. True when it acted.
func toggle_menu() -> bool:
	var shell := Services.shell()
	if shell != null and shell.is_any_open():
		return false
	var open_tab := current_tab()
	if open_tab != &"":
		(_tab(open_tab)["close"] as Callable).call()
		return true
	if not can_open_menu():
		return false
	return open_bag()


## The menu key may open the bag: a player that is not mid-swing, no other window or menu
## pausing the game, no travel under way.
func can_open_menu() -> bool:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if bool(player.call(&"is_action_locked")):
		return false
	if _paused_by_menu():
		return false
	# Not while placing furniture (WorldScene.ts:2077).
	var furniture := get_tree().get_first_node_in_group(&"furniture_placement")
	if furniture != null and bool(furniture.call(&"is_active")):
		return false
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	return main == null or not main.has_method(&"is_transitioning") or not bool(main.call(&"is_transitioning"))


## Opens the bag; false when it was already open.
func open_bag() -> bool:
	if bag.is_open():
		return false
	bag.open()
	return bag.is_open()


## Opens the crafting window at `site` (the Crafting tab: portable); false when already open.
func open_crafting(site: Dictionary = RecipeCatalog.PORTABLE_SITE) -> bool:
	if crafting.is_open():
		return false
	crafting.open_site(site)
	return crafting.is_open()


## `openCraftingStation` (WorldScene.ts:1279-1285): a station's window, refused while the game is
## paused by a window or menu, or crafting or the bag is open.
func open_station(site: Dictionary) -> bool:
	if crafting.is_open() or bag.is_open() or _paused_by_menu():
		return false
	return open_crafting(site)


## The open tab window's id (first of bag, crafting, journal, map), &"" when none.
func current_tab() -> StringName:
	for tab: StringName in TABS:
		var entry := _tab(tab)
		if not entry.is_empty() and bool((entry["is_open"] as Callable).call()):
			return tab
	return &""


## The tab strip's `invoke(tab)`: closes the open window and opens `tab`'s (learning the coach).
## Ignored for the open tab, a tab without a window, or when no tab window is open.
func switch_tab(tab: StringName) -> void:
	var open_tab := current_tab()
	var target := _tab(tab)
	if open_tab == &"" or tab == open_tab or target.is_empty():
		return
	_learn_coach()
	(_tab(open_tab)["close"] as Callable).call()
	(target["open"] as Callable).call()
	_sync_tabs()


## Makes a window the one of tab `tab` ("journal", "map"): either `target` is the window (a Node
## with open(), close(), is_open(), added to GameWindows), or `target` is its open Callable with
## `close` and `is_open` (-> bool). null (or invalid callables) removes the tab's window. Callables
## of a freed object count as no window.
func register_tab(tab: StringName, target: Variant, close: Callable = Callable(), is_open: Callable = Callable()) -> void:
	if target is Node and is_instance_valid(target):
		var window: Node = target
		_tabs[tab] = {"open": Callable(window, &"open"), "close": Callable(window, &"close"),
			"is_open": Callable(window, &"is_open")}
	elif target is Callable and (target as Callable).is_valid() and close.is_valid() and is_open.is_valid():
		_tabs[tab] = {"open": target, "close": close, "is_open": is_open}
	else:
		_tabs.erase(tab)
	if tabs != null:
		_sync_tabs()


## Closes every tab window (world teardown is GameWindows.close_all).
func close_tab_windows() -> void:
	for tab: StringName in TABS:
		var entry := _tab(tab)
		if not entry.is_empty() and bool((entry["is_open"] as Callable).call()):
			(entry["close"] as Callable).call()


# --- private ------------------------------------------------------------------------------------

## The registered window of `tab` ({"open", "close", "is_open"}); for the map, the map UI's
## methods when nothing registered; {} when the tab has no window.
func _tab(tab: StringName) -> Dictionary:
	var entry: Dictionary = _tabs.get(tab, {})
	if not entry.is_empty():
		for key: String in ["open", "close", "is_open"]:
			if not (entry[key] as Callable).is_valid():
				return {}
		return entry
	if tab == &"map" and is_inside_tree():
		var map_ui := get_tree().get_first_node_in_group(MAP_UI_GROUP)
		if map_ui != null and map_ui.has_method(&"open_world_map") and map_ui.has_method(&"close_world_map") 				and map_ui.has_method(&"is_world_map_open"):
			return {"open": Callable(map_ui, &"open_world_map"), "close": Callable(map_ui, &"close_world_map"),
				"is_open": Callable(map_ui, &"is_world_map_open")}
	return {}


func _open_bag_from_pause() -> void:
	open_bag()


func _on_windows_changed(_surface_id: StringName) -> void:
	_sync_tabs()


## Strip visibility, disabled tabs and the coach (MenuTabsSurfacePort.snapshot). The strip stays
## the last child of the windows' root so it draws and clicks above every window.
func _sync_tabs() -> void:
	if tabs == null:
		return
	var open_tab := current_tab()
	var available: Array[StringName] = []
	for tab: StringName in TABS:
		if not _tab(tab).is_empty():
			available.append(tab)
	var run := Services.run()
	var coach_visible := open_tab != &"" and run != null and not run.has_flag(COACH_FLAG)
	var now := float(Time.get_ticks_msec())
	if coach_visible:
		if _coach_shown_at_ms < 0.0:
			_coach_shown_at_ms = now
	elif open_tab == &"" and _coach_shown_at_ms >= 0.0:
		if now - _coach_shown_at_ms >= COACH_READ_MS:
			_learn_coach()
		_coach_shown_at_ms = -1.0
	var parent := tabs.get_parent()
	if parent != null and tabs.get_index() != parent.get_child_count() - 1:
		parent.move_child(tabs, -1)
	tabs.refresh(open_tab, available, coach_visible)


func _learn_coach() -> void:
	var run := Services.run()
	if run != null and not run.has_flag(COACH_FLAG):
		run.set_flag(COACH_FLAG)


## The game is paused by something other than a hit-stop: a game window, a shell menu, the quit.
func _paused_by_menu() -> bool:
	var windows := _game_windows()
	if windows != null and bool(windows.call(&"is_any_open")):
		return true
	var shell := Services.shell()
	if shell != null and shell.is_any_open():
		return true
	var world := Services.world()
	if world != null and world.has_pause_reason(PAUSE_QUIT):
		return true
	return get_tree().paused and (world == null or not world.has_pause_reason(Services.WorldServiceType.PAUSE_HIT_STOP))


func _game_windows() -> Node:
	var parent := get_parent()
	if parent != null and parent.has_method(&"add_window"):
		return parent
	return get_tree().get_first_node_in_group(&"game_windows")
