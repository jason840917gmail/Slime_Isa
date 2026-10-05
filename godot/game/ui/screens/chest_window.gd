extends "res://game/ui/screens/game_window.gd"
## The chest window (Phaser `features/ui/ChestInventorySurfacePort.ts` on
## `ui/chest-inventory-panel.scene.json`; docs/godot/specs/journal-and-chest.md 2, 3.4).
## Godot-owned, built in code; main adds it to GameWindows (surface "chest-inventory": the `modal`
## pause). Group `chest_window`: a chest (chest.gd) hands itself over with `open_chest` and closes it
## with `close_for`. The model is res://game/ui/screens/chest_model.gd.
##
## Left: the chest's stacks, five to a row (icon and count; the name is the tooltip). Right: the
## selected stack's details. Below: the status line, Take Stack and Close. A left click selects a
## stack; a right click (or the context-menu key / Shift+F10 on a focused cell) selects and takes
## it; Take Stack takes the selected one. A take moves as much as fits in the bag; the window stays
## open (also on an empty chest). Stacks are re-read from the chest's record on every refresh.
##
## Silent window: no MenuOpen / MenuClose (AudioEventBridge `SILENT_MODALS`); the chest scene's own
## players sound (OpenSfx, TakeSfx, CloseSfx). Closing it (Close, Escape, a world teardown) tells
## the chest (`closed`); the chest leaving the tree closes it without that.
##
## Owner: interaction (UI).

const ChestModel := preload("res://game/ui/screens/chest_model.gd")
const ChestScript := preload("res://game/scripts/chest.gd")
const ItemCell := preload("res://game/ui/screens/item_cell.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const WindowStyle := preload("res://game/ui/screens/window_style.gd")

const SURFACE_ID := &"chest-inventory"
const GROUP := &"chest_window"
## chest-inventory-panel.scene.json and styles.css:3529-3564.
const COLUMNS := 5
const CELL_GAP := 10
const CELL_HEIGHT := 52.0
const CELL_ICON := 30
const COUNT_FONT := 10
const UNDEFINED_FONT := 11
const CORNER_RADIUS := 5
## Line pitch of the details: 13 px at line-height 1.4.
const DETAILS_FONT := 13
const DETAILS_PITCH := 18.2

var title_label: Label
var item_scroll: ScrollContainer
var item_list: GridContainer
var details_scroll: ScrollContainer
var details_label: Label
var status_label: Label
var take_button: Button
var close_button: Button

var _chest: ChestScript
var _selected_id: String = ""
var _status: String = ""
var _model: Dictionary = {}
## One grid column's width (CSS `repeat(5, 1fr)`: five equal columns however many stacks).
var _cell_width: float = 0.0


func _init() -> void:
	super()
	name = "ChestWindow"
	surface_id = SURFACE_ID
	max_size = Vector2(920.0, 620.0)
	content_height = 620.0


func _ready() -> void:
	super()
	add_to_group(GROUP)


## `open(model)`: shows `chest` (a chest already open is finished first), its first stack selected
## and the opening status.
func open_chest(chest: ChestScript) -> void:
	if chest == null:
		return
	if _chest != null:
		_finish(true)
	_chest = chest
	var stacks := ChestModel.entries(chest.remaining())
	_selected_id = str(stacks[0][0]) if not stacks.is_empty() else ""
	_status = ChestModel.INITIAL_STATUS
	open()


## GameWindow.open with a quiet push (the chest sounds itself). Nothing without a chest.
func open() -> void:
	if _open or _chest == null or not is_instance_valid(_chest):
		return
	_open = true
	visible = true
	_layout_panel()
	refresh()
	var windows := game_windows()
	if windows != null:
		windows.call(&"push", self, surface_id, true)
	focus_initial()
	opened.emit(self)


## Close, Escape and world teardown: closes and tells the chest (`closed`, CloseSfx).
func close() -> void:
	_finish(true)


## `ChestViewPort.close`: the chest `instance_id` went away; closes without telling it.
func close_for(instance_id: String) -> void:
	if _chest != null and is_instance_valid(_chest) and _chest.instance_id == instance_id:
		_finish(false)


## The open chest, null when closed.
func current_chest() -> ChestScript:
	return _chest if _chest != null and is_instance_valid(_chest) else null


## The last model (chest_model.gd `snapshot` keys).
func model() -> Dictionary:
	return _model


# --- actions (ChestInventorySurfacePort.invoke) ---------------------------------------------------

## `select-item {index}`: selects a stack (the status stays).
func select_item(index: int) -> void:
	var item_id := _item_at(index)
	if item_id.is_empty():
		return
	_selected_id = item_id
	refresh()


## `take-stack` (Take Stack): takes the selected stack.
func take_selected() -> void:
	if current_chest() == null or _selected_id.is_empty():
		return
	_take(_selected_id)


## `take-selected-stack {index}` (right click): selects the stack, then takes it.
func take_at(index: int) -> void:
	var item_id := _item_at(index)
	if item_id.is_empty():
		return
	_selected_id = item_id
	_take(item_id)


# --- view ---------------------------------------------------------------------------------------

func refresh() -> void:
	if content == null:
		return
	var chest := current_chest()
	_model = ChestModel.snapshot(chest.remaining() if chest != null else {}, _selected_id, _status)
	_selected_id = str(_model["selected_id"])
	var cells: Array = _model["cells"]
	_sync_cells(cells.size())
	for index in cells.size():
		var entry: Dictionary = cells[index]
		var cell := item_list.get_child(index) as ItemCell
		var defined := bool(entry["defined"])
		if defined:
			cell.set_content(str(entry["count_text"]), ItemIcons.icon(str(entry["id"])))
			cell.set_text_color(UiTokens.WARNING)
		else:
			cell.set_content(str(entry["label"]), null)
			cell.set_text_color(null)
		cell.name_label.add_theme_font_size_override(&"font_size", COUNT_FONT if defined else UNDEFINED_FONT)
		cell.tooltip_text = str(entry["label"])
		cell.set_selected(index == int(_model["selected_index"]))
	details_label.text = str(_model["details"])
	status_label.text = str(_model["status"])
	take_button.disabled = bool(_model["take_disabled"])
	take_button.focus_mode = Control.FOCUS_NONE if take_button.disabled else Control.FOCUS_ALL


func _build() -> void:
	var bold := WindowStyle.bold_font(self)
	title_label = _label("Title", &"PanelTitle", 22)
	title_label.text = ChestModel.TITLE
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_scroll = _scroll("ItemsScroll")
	item_list = GridContainer.new()
	item_list.name = "Items"
	item_list.columns = COLUMNS
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override(&"h_separation", CELL_GAP)
	item_list.add_theme_constant_override(&"v_separation", CELL_GAP)
	item_scroll.add_child(item_list)
	details_scroll = _scroll("DetailsScroll")
	details_label = Label.new()
	details_label.name = "Details"
	details_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_label.theme_type_variation = &"MutedLabel"
	details_label.add_theme_font_size_override(&"font_size", DETAILS_FONT)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.add_child(details_label)
	WindowStyle.set_line_pitch(details_label, DETAILS_FONT, DETAILS_PITCH)
	status_label = _label("Status", &"InfoLabel", 12)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	take_button = _button("Take", ChestModel.TAKE_TEXT, &"PrimaryButton", 14, take_selected)
	close_button = _button("Close", ChestModel.CLOSE_TEXT, &"MutedButton", 14, close)
	for button: Button in [take_button, close_button]:
		if bold != null:
			button.add_theme_font_override(&"font", bold)
		WindowStyle.round_corners(button, CORNER_RADIUS)


func _layout(width: float) -> void:
	var w := width
	_place(title_label, _rect(24.0, 14.0, w - 24.0, 54.0))
	_place(item_scroll, _rect(24.0, 68.0, 0.62 * w - 8.0, 530.0))
	_cell_width = maxf(1.0, (item_scroll.size.x - (COLUMNS - 1) * CELL_GAP) / COLUMNS)
	for cell: Node in item_list.get_children():
		(cell as Control).custom_minimum_size.x = _cell_width
	_place(details_scroll, _rect(0.64 * w, 72.0, w - 24.0, 530.0))
	_place(status_label, _rect(24.0, 542.0, w - 24.0, 568.0))
	_place(take_button, _rect(24.0, 574.0, 160.0, 612.0))
	_place(close_button, _rect(w - 112.0, 574.0, w - 24.0, 612.0))


# --- private ------------------------------------------------------------------------------------

## Forgets the chest, closes without a cue (the last window unpauses), then `notify`: the chest's
## `close()` (`closed`, CloseSfx).
func _finish(notify: bool) -> void:
	var chest := current_chest()
	_chest = null
	_selected_id = ""
	if _open:
		_open = false
		visible = false
		var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()
		var windows := game_windows()
		if windows != null:
			windows.call(&"pop", self, true)
		closed.emit(self)
	if notify and chest != null:
		chest.close()


## `take(itemId)`: moves what fits (the chest emits `stack_transferred`, TakeSfx), says how it
## went; a stack that is gone gives the selection to the first one left.
func _take(item_id: String) -> void:
	var chest := current_chest()
	if chest == null:
		return
	var moved := chest.transfer_stack(item_id)
	_status = ChestModel.moved_text(moved, item_id)
	if not chest.remaining().has(item_id):
		_selected_id = ""
	refresh()
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if is_open() and (focused == null or not is_ancestor_of(focused)):
		focus_initial()


## The item id of stack `index`, "" when there is none (or no chest).
func _item_at(index: int) -> String:
	var chest := current_chest()
	if chest == null:
		return ""
	var stacks := ChestModel.entries(chest.remaining())
	return str(stacks[index][0]) if index >= 0 and index < stacks.size() else ""


func _on_cell_pressed(cell: ItemCell) -> void:
	play_select()
	select_item(cell.index)


## Right click: select and take (no click cue; the select cue as the selection plays). The
## context-menu key or Shift+F10 takes the selected stack; the arrows, Home and End move the
## selection on the 5-column grid (ControlNodes.ts:334-362).
func _on_cell_input(event: InputEvent, cell: ItemCell) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null:
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			cell.accept_event()
			play_select()
			take_at(cell.index)
		return
	if not event.is_pressed():
		return
	var key := event as InputEventKey
	var current := int(_model.get("selected_index", -1))
	if key != null and not key.echo and (key.keycode == KEY_MENU or (key.keycode == KEY_F10 and key.shift_pressed)):
		cell.accept_event()
		if current >= 0:
			play_select()
			take_at(current)
		return
	var count := item_list.get_child_count()
	var step := 0
	if event.is_action_pressed(&"ui_left", true):
		step = -1
	elif event.is_action_pressed(&"ui_right", true):
		step = 1
	elif event.is_action_pressed(&"ui_up", true):
		step = -COLUMNS
	elif event.is_action_pressed(&"ui_down", true):
		step = COLUMNS
	var target := -1
	if step != 0:
		target = current + step if current >= 0 else (0 if step > 0 else count - 1)
	elif event.is_action_pressed(&"ui_home"):
		target = 0
	elif event.is_action_pressed(&"ui_end"):
		target = count - 1
	else:
		return
	cell.accept_event()
	if target < 0 or target >= count:
		return
	play_select()
	select_item(target)
	(item_list.get_child(target) as Control).grab_focus()


func _make_cell() -> ItemCell:
	var cell := ItemCell.new(ItemCell.Layout.TILE, CELL_ICON, COUNT_FONT)
	cell.custom_minimum_size = Vector2(_cell_width, CELL_HEIGHT)
	cell.pressed.connect(_on_cell_pressed.bind(cell))
	cell.gui_input.connect(_on_cell_input.bind(cell))
	return cell


## Keeps `count` cells, indexed in order; new cells get radius-5 corners.
func _sync_cells(count: int) -> void:
	while item_list.get_child_count() > count:
		var last := item_list.get_child(item_list.get_child_count() - 1)
		item_list.remove_child(last)
		last.queue_free()
	while item_list.get_child_count() < count:
		var cell := _make_cell()
		item_list.add_child(cell)
		WindowStyle.round_corners(cell, CORNER_RADIUS)
	for index in item_list.get_child_count():
		(item_list.get_child(index) as ItemCell).index = index


func _scroll(node_name: String) -> ScrollContainer:
	var list_scroll := ScrollContainer.new()
	list_scroll.name = node_name
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	content.add_child(list_scroll)
	return list_scroll

