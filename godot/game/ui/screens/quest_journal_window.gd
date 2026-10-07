extends "res://game/ui/screens/game_window.gd"
## The quest journal, "Quest Book" (Phaser `features/ui/QuestJournalSurfacePort.ts` on
## `ui/quest-journal.scene.json`; docs/godot/specs/journal-and-chest.md 1, 3.3). Godot-owned, built
## in code; main adds it to GameWindows (surface "quest-journal": the `modal` pause). Group
## `quest_journal`. The model is res://game/ui/screens/quest_journal_model.gd.
##
## Left: the quests the player has taken on (two-line rows; finished ones dimmed). Right: the
## selected quest's name, state line, page (description, steps, requirements, reward), the status
## line, the action (Abandon / Retry / No action) and Close. Each opening shows the first quest and
## a clear status; the selection follows its quest across changes, and any selection clears the
## status. The page follows the quest service live (`quest_changed`, `quest_completed`).
##
## Opening: the menu's Journal tab (MenuWindows `register_tab`, done here) and the pause menu's
## Journal button (Shell action `journal`, set here); no key of its own. The menu key and Escape
## close it. Opening plays JournalOpen instead of MenuOpen (AudioEventBridge.ts:107); closing plays
## MenuClose. GameWindows' `window_opened` makes the quest service tick "Read your Journal" before
## the first page shows.
##
## Abandon asks first [DIFF] (owner decision J1): an in-window confirm instead of the browser's
## `window.confirm`, Cancel focused; Escape cancels it only. `confirm_abandon` (tests) answers at
## once instead.
##
## Keys on a focused row: up / left and down / right select the previous / next quest, Home / End
## the first / last (the focus follows); Enter and Space press the focused row.
##
## Owner: quests (UI).

const QuestJournalModel := preload("res://game/ui/screens/quest_journal_model.gd")
const ItemCell := preload("res://game/ui/screens/item_cell.gd")
const Services := preload("res://game/shared/services.gd")
const WindowStyle := preload("res://game/ui/screens/window_style.gd")

const SURFACE_ID := &"quest-journal"
const GROUP := &"quest_journal"
const QUESTS_GROUP := &"quests"
const MENU_WINDOWS_GROUP := &"menu_windows"
const MENU_TAB := &"journal"
const SHELL_ACTION := &"journal"
## AudioEventBridge.ts:107: the book's own opening cue.
const OPEN_CUE := &"JournalOpen"
## quest-journal.scene.json and styles.css:3613-3645.
const ROW_HEIGHT := 48.0
const ROW_GAP := 8
const ROW_FONT := 12
const ROW_PADDING := 8
const CORNER_RADIUS := 6
const FINISHED_ALPHA := 0.5
## Line pitch of the page: 14 px at line-height 1.45.
const DETAILS_FONT := 14
const DETAILS_PITCH := 20.3
const CONFIRM_SIZE := Vector2(420.0, 150.0)
const CONFIRM_DIM := Color(0.0, 0.0, 0.0, 0.35)
const PANEL_RADIUS := 12

## An action ran. Payload: {"action", "questId", "ok", "status"} (test hook).
signal action_finished(payload: Dictionary)

## The quest service (quest_service.gd); found through its group when unset.
var service: Node
## Tests: (title: String) -> bool, answered at once (Phaser `confirmAbandon`). Unset: the confirm.
var confirm_abandon: Callable = Callable()

var title_label: Label
var quest_scroll: ScrollContainer
var quest_list: GridContainer
var details_name_label: Label
var details_status_label: Label
var details_scroll: ScrollContainer
var details_label: Label
var status_label: Label
var action_button: Button
var close_button: Button
var confirm_layer: Control
var confirm_label: Label
var confirm_accept_button: Button
var confirm_cancel_button: Button

var _selected_id: String = ""
var _status: String = ""
var _model: Dictionary = {}
## The quest the confirm asks about ("" while it is hidden).
var _confirm_quest_id: String = ""


func _init() -> void:
	super()
	name = "QuestJournal"
	surface_id = SURFACE_ID
	max_size = Vector2(940.0, 620.0)
	content_height = 620.0


func _ready() -> void:
	super()
	add_to_group(GROUP)
	var shell := Services.shell()
	if shell != null:
		shell.set_action(SHELL_ACTION, _open_from_pause)
	var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP)
	if menu != null and menu.has_method(&"register_tab"):
		menu.call(&"register_tab", MENU_TAB, self)
	quest_service()


func _exit_tree() -> void:
	var shell := Services.shell()
	if shell != null and is_instance_valid(shell):
		shell.set_action(SHELL_ACTION, Callable())
	var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP)
	if menu != null and menu.has_method(&"register_tab"):
		menu.call(&"register_tab", MENU_TAB, null)
	if service != null and is_instance_valid(service):
		for changed: StringName in [&"quest_changed", &"quest_completed"]:
			if service.is_connected(changed, _on_quests_changed):
				service.disconnect(changed, _on_quests_changed)


## GameWindow.open with a quiet push: the book plays JournalOpen, not MenuOpen. The push's
## `window_opened` reaches the quest service ("Read your Journal") while the book is open, so the
## page already shows it ticked.
func open() -> void:
	if _open:
		return
	_open = true
	_on_opening()
	visible = true
	_layout_panel()
	refresh()
	var windows := game_windows()
	if windows != null:
		windows.call(&"push", self, surface_id, true)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(OPEN_CUE)
	focus_initial()
	opened.emit(self)


## Hides the confirm, closes (MenuClose) and clears the status.
func close() -> void:
	_hide_confirm(false)
	super()
	_status = ""


## The quest service (group `quests`), connected to this window's refresh; null without one.
func quest_service() -> Node:
	if (service == null or not is_instance_valid(service)) and is_inside_tree():
		service = get_tree().get_first_node_in_group(QUESTS_GROUP)
	if service != null and is_instance_valid(service):
		for changed: StringName in [&"quest_changed", &"quest_completed"]:
			if service.has_signal(changed) and not service.is_connected(changed, _on_quests_changed):
				service.connect(changed, _on_quests_changed)
		return service
	return null


## The last model (quest_journal_model.gd `snapshot` keys).
func model() -> Dictionary:
	return _model


# --- actions (QuestJournalSurfacePort.invoke) -----------------------------------------------------

## `select-quest {index}`: selects a listed quest and clears the status.
func select_quest(index: int) -> void:
	if not is_open():
		return
	var rows: Array = _model.get("rows", [])
	if index < 0 or index >= rows.size():
		return
	_selected_id = str((rows[index] as Dictionary)["id"])
	_status = ""
	refresh()


## `quest-action` (the Action button): abandons (after the confirm) or retries the selected quest;
## the status then says how it went.
func quest_action() -> void:
	if not is_open() or is_confirming():
		return
	var view := _selected_view()
	var action := QuestJournalModel.action_for(view)
	if action.is_empty():
		return
	if action == "abandon":
		var title := QuestJournalModel.title_of(view)
		if not confirm_abandon.is_valid():
			_show_confirm(str(view["quest_id"]), title)
			return
		if not bool(confirm_abandon.call(title)):
			return
	_run(action, view)


func is_confirming() -> bool:
	return confirm_layer != null and confirm_layer.visible


## The confirm's buttons (Escape = false): Abandon runs the abandon, Cancel changes nothing.
func answer_confirm(accept: bool) -> void:
	if not is_confirming():
		return
	var quest_id := _confirm_quest_id
	_hide_confirm(true)
	if not accept:
		return
	var view := _selected_view()
	if str(view.get("quest_id", "")) == quest_id and QuestJournalModel.action_for(view) == "abandon":
		_run("abandon", view)


# --- view ---------------------------------------------------------------------------------------

func refresh() -> void:
	if content == null:
		return
	var quests := quest_service()
	var views: Array = quests.call(&"list") if quests != null else []
	_model = QuestJournalModel.snapshot(views, _selected_id, _status)
	_selected_id = str(_model["selected_id"])
	var rows: Array = _model["rows"]
	_sync_rows(rows.size())
	for index in rows.size():
		var row: Dictionary = rows[index]
		var cell := quest_list.get_child(index) as ItemCell
		cell.set_content(str(row["label"]))
		cell.set_selected(index == int(_model["selected_index"]))
		cell.modulate.a = FINISHED_ALPHA if bool(row["finished"]) else 1.0
	details_name_label.text = str(_model["details_name"])
	details_status_label.text = str(_model["details_status"])
	details_label.text = str(_model["details"])
	status_label.text = str(_model["status"])
	action_button.text = str(_model["action_label"])
	action_button.disabled = bool(_model["action_disabled"])
	action_button.focus_mode = Control.FOCUS_NONE if action_button.disabled else Control.FOCUS_ALL
	# A row that left the list or an Action button that became disabled drops the focus: it goes
	# back to the first row (else Close).
	if is_open() and not is_confirming():
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or not is_ancestor_of(focused):
			focus_initial()


func _build() -> void:
	title_label = _label("Title", &"PanelTitle", 24)
	title_label.text = QuestJournalModel.TITLE
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quest_scroll = _scroll("QuestsScroll")
	quest_list = GridContainer.new()
	quest_list.name = "Quests"
	quest_list.columns = 1
	quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_list.add_theme_constant_override(&"v_separation", ROW_GAP)
	quest_scroll.add_child(quest_list)
	details_name_label = _label("DetailsName", &"PanelTitle", 22)
	details_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	details_name_label.clip_text = true
	details_status_label = _label("DetailsStatus", &"AccentLabel", 14)
	details_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bold := WindowStyle.bold_font(self)
	if bold != null:
		details_status_label.add_theme_font_override(&"font", bold)
	details_scroll = _scroll("DetailsScroll")
	details_label = Label.new()
	details_label.name = "Details"
	details_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_label.add_theme_font_size_override(&"font_size", DETAILS_FONT)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.add_child(details_label)
	WindowStyle.set_line_pitch(details_label, DETAILS_FONT, DETAILS_PITCH)
	status_label = _label("Status", &"InfoLabel", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_button = _button("Action", str(QuestJournalModel.ACTION_LABELS[""]), &"DangerButton", 16, quest_action)
	close_button = _button("Close", QuestJournalModel.CLOSE_TEXT, &"MutedButton", 16, close)
	for button: Button in [action_button, close_button]:
		_style_button(button, bold)
	_build_confirm(bold)


func _layout(width: float) -> void:
	var w := width
	var left := 0.44 * w
	_place(title_label, _rect(20.0, 14.0, w - 20.0, 56.0))
	_place(quest_scroll, _rect(20.0, 66.0, 0.42 * w - 12.0, 600.0))
	_place(details_name_label, _rect(left, 66.0, w - 20.0, 96.0))
	_place(details_status_label, _rect(left, 98.0, w - 20.0, 120.0))
	_place(details_scroll, _rect(left, 126.0, w - 20.0, 488.0))
	_place(status_label, _rect(left, 498.0, w - 20.0, 526.0))
	_place(action_button, _rect(left, 568.0, 0.70 * w, 608.0))
	_place(close_button, _rect(0.74 * w, 568.0, 0.98 * w, 608.0))


func _on_opening() -> void:
	_selected_id = ""
	_status = ""
	_hide_confirm(false)


## Escape while the confirm shows cancels it only (before GameWindows closes the book).
func _input(event: InputEvent) -> void:
	if not is_confirming() or event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		answer_confirm(false)


# --- private ------------------------------------------------------------------------------------

func _open_from_pause() -> void:
	open()


func _on_quests_changed(_payload: Dictionary) -> void:
	if is_open():
		refresh()


## The listed quest the selection points at ({} when none).
func _selected_view() -> Dictionary:
	var quests := quest_service()
	if quests == null or _selected_id.is_empty():
		return {}
	for view: Dictionary in QuestJournalModel.listed(quests.call(&"list")):
		if str(view.get("quest_id", "")) == _selected_id:
			return view
	return {}


func _run(action: String, view: Dictionary) -> void:
	var quests := quest_service()
	if quests == null:
		return
	var quest_id := str(view["quest_id"])
	var result: Dictionary
	if action == "abandon":
		result = quests.call(&"abandon", quest_id)
	elif str(view.get("status", "")) == "failed":
		result = quests.call(&"retry_failed", quest_id)
	else:
		result = quests.call(&"retry_abandoned_automatic", quest_id)
	var ok := bool(result.get("ok", false))
	if ok:
		_status = QuestJournalModel.ABANDONED_STATUS if action == "abandon" else QuestJournalModel.RESTARTED_STATUS
	else:
		_status = str(result.get("reason", ""))
	refresh()
	action_finished.emit({"action": action, "questId": quest_id, "ok": ok, "status": _status})


func _on_row_pressed(cell: ItemCell) -> void:
	play_select()
	select_quest(cell.index)


## Arrow keys, Home and End on a focused row (ControlNodes.ts:340-362, one column).
func _on_row_input(event: InputEvent, cell: ItemCell) -> void:
	if not event.is_pressed():
		return
	var count := quest_list.get_child_count()
	var current := int(_model.get("selected_index", -1))
	var target := -1
	if event.is_action_pressed(&"ui_up", true) or event.is_action_pressed(&"ui_left", true):
		target = current - 1 if current >= 0 else count - 1
	elif event.is_action_pressed(&"ui_down", true) or event.is_action_pressed(&"ui_right", true):
		target = current + 1 if current >= 0 else 0
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
	select_quest(target)
	(quest_list.get_child(target) as Control).grab_focus()


func _make_row() -> ItemCell:
	var cell := ItemCell.new(ItemCell.Layout.TEXT, 0, ROW_FONT)
	cell.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.pressed.connect(_on_row_pressed.bind(cell))
	cell.gui_input.connect(_on_row_input.bind(cell))
	return cell


## Keeps `count` rows, indexed in order; new rows get the journal's padding and corners.
func _sync_rows(count: int) -> void:
	while quest_list.get_child_count() > count:
		var last := quest_list.get_child(quest_list.get_child_count() - 1)
		quest_list.remove_child(last)
		last.queue_free()
	while quest_list.get_child_count() < count:
		var cell := _make_row()
		quest_list.add_child(cell)
		var margin := cell.get_node_or_null(^"Margin") as MarginContainer
		if margin != null:
			for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
				margin.add_theme_constant_override(side, ROW_PADDING)
		WindowStyle.round_corners(cell, CORNER_RADIUS)
	for index in quest_list.get_child_count():
		(quest_list.get_child(index) as ItemCell).index = index


func _scroll(node_name: String) -> ScrollContainer:
	var list_scroll := ScrollContainer.new()
	list_scroll.name = node_name
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	content.add_child(list_scroll)
	return list_scroll


## The in-window abandon confirm: a dimmed layer over the whole panel (it stops the mouse) with a
## ModalPanel in the middle: the question, Abandon (danger) and Cancel (muted).
func _build_confirm(bold: Font) -> void:
	confirm_layer = Panel.new()
	confirm_layer.name = "Confirm"
	confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := StyleBoxFlat.new()
	dim.bg_color = CONFIRM_DIM
	dim.set_corner_radius_all(PANEL_RADIUS)
	confirm_layer.add_theme_stylebox_override(&"panel", dim)
	confirm_layer.visible = false
	panel.add_child(confirm_layer)
	var box := PanelContainer.new()
	box.name = "Box"
	box.theme_type_variation = &"ModalPanel"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -CONFIRM_SIZE.x / 2.0
	box.offset_right = CONFIRM_SIZE.x / 2.0
	box.offset_top = -CONFIRM_SIZE.y / 2.0
	box.offset_bottom = CONFIRM_SIZE.y / 2.0
	confirm_layer.add_child(box)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override(&"separation", 16)
	box.add_child(rows)
	confirm_label = Label.new()
	confirm_label.name = "Question"
	confirm_label.add_theme_font_size_override(&"font_size", 14)
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(confirm_label)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 12)
	rows.add_child(buttons)
	confirm_accept_button = _confirm_button(buttons, "Accept", QuestJournalModel.CONFIRM_ACCEPT, &"DangerButton", true, bold)
	confirm_cancel_button = _confirm_button(buttons, "Cancel", QuestJournalModel.CONFIRM_CANCEL, &"MutedButton", false, bold)
	# Tab and the arrows stay on the confirm's two buttons.
	for pair: Array in [[confirm_accept_button, confirm_cancel_button], [confirm_cancel_button, confirm_accept_button]]:
		var from: Button = pair[0]
		var other := from.get_path_to(pair[1])
		var itself := from.get_path_to(from)
		from.focus_next = other
		from.focus_previous = other
		from.focus_neighbor_left = other
		from.focus_neighbor_right = other
		from.focus_neighbor_top = itself
		from.focus_neighbor_bottom = itself


func _confirm_button(parent: Control, node_name: String, text: String, variation: StringName, accept: bool, bold: Font) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(140.0, 36.0)
	button.add_theme_font_size_override(&"font_size", 15)
	button.pressed.connect(play_click)
	button.pressed.connect(answer_confirm.bind(accept))
	parent.add_child(button)
	_style_button(button, bold)
	return button


func _show_confirm(quest_id: String, title: String) -> void:
	_confirm_quest_id = quest_id
	confirm_label.text = QuestJournalModel.CONFIRM_FORMAT % title
	confirm_layer.visible = true
	confirm_cancel_button.grab_focus()


## Hides the confirm; `refocus` gives the focus back to the Action button (else Close).
func _hide_confirm(refocus: bool) -> void:
	_confirm_quest_id = ""
	if confirm_layer == null or not confirm_layer.visible:
		return
	confirm_layer.visible = false
	if refocus and is_open():
		if action_button.focus_mode != Control.FOCUS_NONE:
			action_button.grab_focus()
		else:
			close_button.grab_focus()


## Bold text and radius-6 corners (modal window buttons, styles.css:3619-3645).
func _style_button(button: Button, bold: Font) -> void:
	if bold != null:
		button.add_theme_font_override(&"font", bold)
	WindowStyle.round_corners(button, CORNER_RADIUS)

