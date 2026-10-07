extends RefCounted
## The chest window (docs/godot/specs/journal-and-chest.md 2, 3.4, 3.7) on level-1's chest in Fatty's
## camp (`level-1-fatty-guarded-chest`, a green key; the chest stands at (2528, 1077), inside the
## camp's 440 px activation circle around (2528, 1472)). Chests open through the interaction
## controller's `_use_chest`, so Fatty is never woken unless a test wants him.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ChestScript := preload("res://game/scripts/chest.gd")
const ChestWindow := preload("res://game/ui/screens/chest_window.gd")
const ItemCell := preload("res://game/ui/screens/item_cell.gd")
const InteractionController := preload("res://game/interaction/interaction_controller.gd")
const BossCampScript := preload("res://game/scripts/boss_camp.gd")
const MenuWindows := preload("res://game/ui/screens/menu_windows.gd")

const CHEST_ID := "level-1-fatty-guarded-chest"
const KEY := "green-key"
const INITIAL_STATUS := "Select a stack to inspect. Right-click or press Take Stack to collect it."
const KEY_DETAILS := "Verdant Key\nKEY · ×1\n\nA leaf-shaped green key carried by Fatty One Eye's guarded chest.\n\nTake Stack transfers as much as your inventory can hold."
const IRON_DETAILS := "Iron Ore\nMATERIAL · ×6\n\nDense iron-bearing ore ready to be refined into metal.\n\nTake Stack transfers as much as your inventory can hold."
const TONIC_DETAILS := "Slime Tonic\nCONSUMABLE · ×1\n\nRestores 40 HP.\n\nTake Stack transfers as much as your inventory can hold."
const MIXED := {"iron-ore": 6, "charcoal": 3, "hp-potion": 1}
## 87 px north of the chest and 472 px from the camp centre: in the chest's reach, out of the
## activation circle.
const CHEST_STAND := Vector2(2528.0, 990.0)
const CAMP_ID := "level-1-fatty-one-eye-camp"
## Inside Fatty's activation circle (test_boss.gd FAR_INSIDE).
const FAR_INSIDE := Vector2(2528.0, 1852.0)


func test_use_chest_opens_window(t: TestContext) -> void:
	var chest := _chest(t)
	if not t.check(chest != null, "no %s" % CHEST_ID):
		return
	_set_bag([])
	var interaction := _interaction(t)
	var messages: Array = []
	interaction.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	var requested: Array = []
	chest.open_requested.connect(func(payload: Dictionary) -> void: requested.append(payload))
	var open_sfx := _chest_sfx(chest, "OpenSfx")
	var menu_open := _cue(&"MenuOpen")
	var window := _window(t)
	t.check(interaction.call(&"_use_chest", chest), "using the chest failed")
	t.check(bool(_windows(t).call(&"is_open", &"chest-inventory")), "GameWindows does not list the chest window")
	t.check(window.current_chest() == chest, "the window does not show the chest")
	t.check(t.world().has_pause_reason(&"modal"), "the world is not paused")
	t.check(open_sfx != null and TestContext.played(open_sfx), "OpenSfx is not playing")
	t.check(menu_open == null or not TestContext.played(menu_open), "MenuOpen played")
	t.equal(requested.size(), 1, "open_requested")
	t.equal(Services.run().slots(), [], "bag")
	t.equal(messages, [], "messages")
	t.equal(window.title_label.text, "Chest", "title")
	t.equal(_counts(window), ["1"], "cells")
	var cell := _cell(window, 0)
	if t.check(cell != null, "no cell"):
		t.equal(cell.tooltip_text, "Verdant Key ×1", "tooltip")
		var icon := cell.icon_rect.texture as AtlasTexture
		t.check(icon != null and icon.region == Rect2(0.0, 0.0, 64.0, 64.0) and icon.atlas.resource_path.ends_with("keys-5x4.webp"),
			"icon %s" % [icon.region if icon != null else null])
		t.check(cell.is_selected() and cell.has_focus(), "cell 0 is not selected and focused")
	t.equal(window.details_label.text, KEY_DETAILS, "details")
	t.equal(window.status_label.text, INITIAL_STATUS, "status")
	t.check(not window.take_button.disabled, "Take Stack is disabled")
	window.close()


## The panel follows the viewport (headless runs have a small one); the content is placed for the
## 920 px panel of a 1280 × 720 viewport, on screen (180, 50)-(1100, 670).
func test_layout_1280(t: TestContext) -> void:
	var window := await _open(t, MIXED)
	if window == null:
		return
	_near_rect(t, window.panel.get_global_rect(), _panel_rect(window, Vector2(920.0, 620.0)), "panel")
	window.call(&"_layout", 920.0)
	# The small headless viewport squeezed the wrapping labels; they reshape at the new width
	# on the next frame, then the layout fits them again.
	await t.steps(1)
	window.call(&"_layout", 920.0)
	_near_rect(t, _content_rect(window.title_label), _corners(24.0, 14.0, 896.0, 54.0), "Title")
	_near_rect(t, _content_rect(window.item_scroll), _corners(24.0, 68.0, 562.4, 530.0), "Items")
	t.equal(window.item_list.columns, 5, "columns")
	t.equal([window.item_list.get_theme_constant(&"h_separation"), window.item_list.get_theme_constant(&"v_separation")], [10, 10], "separation")
	t.near(_cell(window, 0).custom_minimum_size.x, (538.4 - 40.0) / 5.0, 0.01, "column width")
	_near_rect(t, _content_rect(window.details_scroll), _corners(588.8, 72.0, 896.0, 530.0), "Details")
	_near_rect(t, _content_rect(window.status_label), _corners(24.0, 542.0, 896.0, 568.0), "Status")
	_near_rect(t, _content_rect(window.take_button), _corners(24.0, 574.0, 160.0, 612.0), "Take")
	_near_rect(t, _content_rect(window.close_button), _corners(808.0, 574.0, 896.0, 612.0), "Close")
	window.close()


func test_take_stack(t: TestContext) -> void:
	var chest := _chest(t)
	_set_bag([])
	var moves: Array = []
	chest.stack_transferred.connect(func(payload: Dictionary) -> void: moves.append(payload))
	var window := await _open(t, {})
	if window == null:
		return
	var take_sfx := _chest_sfx(chest, "TakeSfx")
	TestContext.silence(window.click_sfx)
	window.take_button.pressed.emit()
	t.equal(Services.run().item_count(KEY), 1, "keys in the bag")
	t.equal(chest.remaining(), {}, "chest contents")
	t.equal(moves, [{"itemId": KEY, "moved": 1}], "stack_transferred")
	t.check(take_sfx != null and TestContext.played(take_sfx), "TakeSfx is not playing")
	t.check(TestContext.played(window.click_sfx), "ClickSfx is not playing")
	t.equal(window.status_label.text, "Moved 1 × Verdant Key", "status")
	t.equal(_counts(window), [], "cells")
	t.equal(window.details_label.text, "The chest is empty.", "details")
	t.check(window.take_button.disabled, "Take Stack is enabled")
	t.check(window.is_open(), "the window closed")
	t.check(window.close_button.has_focus(), "Close does not have the focus")
	window.close()


func test_right_click_takes(t: TestContext) -> void:
	_set_bag([])
	var window := await _open(t, MIXED)
	if window == null:
		return
	t.equal(_counts(window), ["6", "3", "1"], "cells before")
	t.equal(_tooltips(window), ["Iron Ore ×6", "Charcoal ×3", "Slime Tonic ×1"], "tooltips")
	t.equal(window.details_label.text, IRON_DETAILS, "first details")
	TestContext.silence(window.select_sfx)
	_cell(window, 1).gui_input.emit(_right_click())
	t.check(TestContext.played(window.select_sfx), "SelectSfx is not playing")
	t.equal(Services.run().item_count("charcoal"), 3, "charcoal in the bag")
	t.equal(window.status_label.text, "Moved 3 × Charcoal", "status")
	t.equal(_counts(window), ["6", "1"], "cells after")
	t.equal(int(window.model()["selected_index"]), 0, "selected index")
	t.equal(window.details_label.text, IRON_DETAILS, "details after")
	window.close()


func test_partial_take_then_no_room(t: TestContext) -> void:
	var chest := _chest(t)
	var slots: Array = []
	for _i in 19:
		slots.append({"item_id": "stone", "count": 25})
	slots.append({"item_id": "hp-potion", "count": 7})
	_set_bag(slots)
	var moves: Array = []
	chest.stack_transferred.connect(func(payload: Dictionary) -> void: moves.append(payload))
	var window := await _open(t, {"hp-potion": 5})
	if window == null:
		return
	window.take_selected()
	t.equal(window.status_label.text, "Moved 2 × Slime Tonic", "first status")
	t.equal(chest.remaining(), {"hp-potion": 3}, "chest after the first take")
	t.equal(_counts(window), ["3"], "cells after the first take")
	t.check(_cell(window, 0).is_selected(), "the stack is not selected")
	window.take_selected()
	t.equal(window.status_label.text, "No inventory space for that item.", "second status")
	t.equal(chest.remaining(), {"hp-potion": 3}, "chest after the second take")
	t.equal(moves, [{"itemId": "hp-potion", "moved": 2}], "stack_transferred")
	window.close()


func test_select_keeps_status(t: TestContext) -> void:
	_set_bag([])
	var window := await _open(t, MIXED)
	if window == null:
		return
	window.take_at(1)
	_cell(window, 1).pressed.emit()
	t.equal(window.status_label.text, "Moved 3 × Charcoal", "status")
	t.equal(window.details_label.text, TONIC_DETAILS, "details")
	t.equal(int(window.model()["selected_index"]), 1, "selected index")
	window.close()


func test_close_button_and_escape(t: TestContext) -> void:
	var chest := _chest(t)
	var closed: Array = []
	chest.closed.connect(func(payload: Dictionary) -> void: closed.append(payload))
	var window := await _open(t, {})
	if window == null:
		return
	var close_sfx := _chest_sfx(chest, "CloseSfx")
	var menu_close := _cue(&"MenuClose")
	window.close_button.pressed.emit()
	_check_closed(t, window, closed, close_sfx, menu_close, "Close")
	closed.clear()
	TestContext.silence(close_sfx)
	_interaction(t).call(&"_use_chest", chest)
	t.check(window.is_open(), "the chest did not open again")
	menu_close = _cue(&"MenuClose")
	t.tap(&"ui_cancel")
	await t.steps(1)
	_check_closed(t, window, closed, close_sfx, menu_close, "Escape")


func test_empty_chest(t: TestContext) -> void:
	var chest := _chest(t)
	var run := Services.run()
	run.set_chest_remaining("level-1", CHEST_ID, {})
	var interaction := _interaction(t)
	t.teleport_player(CHEST_STAND)
	await t.steps(2)
	t.equal(interaction.get_prompt().get_text(), "Right-click: Inspect empty chest", "prompt")
	t.check(interaction.handle_interact(), "the interact button did nothing")
	var window := _window(t)
	if not t.check(window.is_open(), "an empty chest did not open the window"):
		return
	t.equal(_counts(window), [], "cells")
	t.equal(window.details_label.text, "The chest is empty.", "details")
	t.check(window.take_button.disabled, "Take Stack is enabled")
	t.check(window.close_button.has_focus(), "Close does not have the focus")
	var close_sfx := _chest_sfx(chest, "CloseSfx")
	window.close()
	t.check(close_sfx != null and TestContext.played(close_sfx), "CloseSfx is not playing")
	await t.steps(2)
	var visual := chest.get_parent().find_children("*", "Sprite2D", true, false)[0] as Sprite2D
	t.equal(visual.frame, 1, "empty chest frame")


func test_guarded_chest_has_no_window(t: TestContext) -> void:
	var camp: BossCampScript = null
	for node: Node in t.tree.get_nodes_in_group(BossCampScript.GROUP):
		if node is BossCampScript and (node as BossCampScript).camp_id == CAMP_ID:
			camp = node
	if not t.check(camp != null, "no camp %s" % CAMP_ID):
		return
	t.teleport_player(FAR_INSIDE)
	if not t.check(await t.until(func() -> bool: return camp.has_live_boss(), 200.0), "Fatty did not spawn"):
		return
	var chest := _chest(t)
	var interaction := _interaction(t)
	var messages: Array = []
	interaction.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	var locked_sfx := _chest_sfx(chest, "LockedSfx")
	t.check(interaction.call(&"_use_chest", chest), "using the chest failed")
	t.check(messages.size() == 1 and messages[0]["text"] == "Fatty One Eye is guarding this chest!", "messages %s" % [messages])
	t.check(locked_sfx != null and TestContext.played(locked_sfx), "LockedSfx is not playing")
	t.check(not _window(t).is_open(), "the guarded chest opened the window")
	t.check(not t.world().has_pause_reason(&"modal"), "the world is paused by a window")


func test_keys_while_open(t: TestContext) -> void:
	var menu := t.tree.get_first_node_in_group(&"menu_windows") as MenuWindows
	var interaction := _interaction(t)
	var interacted: Array = []
	interaction.interacted.connect(func(payload: Dictionary) -> void: interacted.append(payload))
	var window := await _open(t, {})
	if window == null:
		return
	t.tap(&"menu")
	t.tap(&"interact")
	t.tap(&"attack")
	await t.steps(2)
	t.check(window.is_open(), "a key closed the chest window")
	t.check(menu == null or not menu.bag.is_open(), "the menu key opened the bag")
	window.close()
	await t.steps(3)
	t.check(not t.player().is_action_locked(), "a press made while the window was open swung the sword")
	t.equal(interacted, [], "a press made while the window was open interacted")


func test_chest_leaves_tree(t: TestContext) -> void:
	var chest := _chest(t)
	var closed: Array = []
	chest.closed.connect(func(payload: Dictionary) -> void: closed.append(payload))
	var window := await _open(t, {})
	if window == null:
		return
	var root := chest.get_parent()
	root.get_parent().remove_child(root)
	t.check(not window.is_open(), "the window stayed open")
	t.check(window.current_chest() == null, "the window kept the chest")
	t.equal(closed, [], "closed signals")
	t.check(not t.world().has_pause_reason(&"modal"), "the world stayed paused")
	root.queue_free()


# --- helpers ----------------------------------------------------------------------------------

func _chest(t: TestContext) -> ChestScript:
	for node: Node in t.tree.get_nodes_in_group(&"chest"):
		if node is ChestScript and (node as ChestScript).instance_id == CHEST_ID:
			return node
	return null


func _window(t: TestContext) -> ChestWindow:
	return t.tree.get_first_node_in_group(&"chest_window") as ChestWindow


func _windows(t: TestContext) -> Node:
	return t.tree.get_first_node_in_group(&"game_windows")


func _interaction(t: TestContext) -> InteractionController:
	return t.tree.get_first_node_in_group(&"interaction") as InteractionController


## Fills the chest with `contents` ({} keeps the authored green key) and opens it.
func _open(t: TestContext, contents: Dictionary) -> ChestWindow:
	var chest := _chest(t)
	if not t.check(chest != null, "no %s" % CHEST_ID):
		return null
	if not contents.is_empty():
		Services.run().set_chest_remaining("level-1", CHEST_ID, contents)
	await t.steps(1)
	_interaction(t).call(&"_use_chest", chest)
	var window := _window(t)
	if not t.check(window != null and window.is_open(), "the chest window did not open"):
		return null
	return window


func _check_closed(t: TestContext, window: ChestWindow, closed: Array, close_sfx: AudioStreamPlayer2D,
		menu_close: AudioStreamPlayer, how: String) -> void:
	t.check(not window.is_open(), "%s: the window stayed open" % how)
	t.equal(closed, [{"instanceId": CHEST_ID}], "%s: closed signals" % how)
	t.check(close_sfx != null and TestContext.played(close_sfx), "%s: CloseSfx is not playing" % how)
	t.check(menu_close == null or not TestContext.played(menu_close), "%s: MenuClose played" % how)
	t.check(not t.tree.paused, "%s: the world stayed paused" % how)
	var shell := Services.shell()
	t.check(shell == null or not shell.is_any_open(), "%s: a shell window opened" % how)


func _cell(window: ChestWindow, index: int) -> ItemCell:
	if index < 0 or index >= window.item_list.get_child_count():
		return null
	return window.item_list.get_child(index) as ItemCell


func _counts(window: ChestWindow) -> Array:
	var counts: Array = []
	for cell: Node in window.item_list.get_children():
		counts.append((cell as ItemCell).label_text())
	return counts


func _tooltips(window: ChestWindow) -> Array:
	var tips: Array = []
	for cell: Node in window.item_list.get_children():
		tips.append((cell as ItemCell).tooltip_text)
	return tips


## One of the chest scene's sound players, stopped.
static func _chest_sfx(chest: ChestScript, node_name: String) -> AudioStreamPlayer2D:
	if chest == null:
		return null
	var player := chest.get_parent().get_node_or_null(NodePath(node_name)) as AudioStreamPlayer2D
	if player != null:
		TestContext.silence(player)
	return player


static func _set_bag(slots: Array) -> void:
	var run := Services.run()
	run.inventory["slots"] = slots.duplicate(true)
	run.inventory_changed.emit({})


static func _right_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	return event


## A cue player of GameFeel's `audio.global`, stopped (so `playing` tells whether it played since).
static func _cue(cue: StringName) -> AudioStreamPlayer:
	var feel := Services.feel()
	if feel == null:
		return null
	feel.warm_up()
	var player := feel.get_node_or_null(NodePath("GlobalAudio/Effects/" + String(cue))) as AudioStreamPlayer
	if player != null:
		TestContext.silence(player)
	return player


## GameWindow's centred panel for the current viewport: min(max, viewport - 32), halves rounded.
static func _panel_rect(window: Control, max_size: Vector2) -> Rect2:
	var viewport := window.get_viewport_rect().size
	var half := Vector2(roundf(minf(max_size.x, maxf(1.0, viewport.x - 32.0)) / 2.0),
		roundf(minf(max_size.y, maxf(1.0, viewport.y - 32.0)) / 2.0))
	return Rect2(viewport / 2.0 - half, half * 2.0)


static func _content_rect(control: Control) -> Rect2:
	return Rect2(control.position, control.size)


static func _corners(left: float, top: float, right: float, bottom: float) -> Rect2:
	return Rect2(left, top, right - left, bottom - top)


static func _near_rect(t: TestContext, actual: Rect2, expected: Rect2, label: String) -> void:
	t.check(actual.position.distance_to(expected.position) <= 0.5 and actual.end.distance_to(expected.end) <= 0.5,
		"%s: got %s, expected %s" % [label, actual, expected])
