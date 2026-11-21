extends RefCounted
## The quest journal (docs/godot/specs/journal-and-chest.md 1, 3.3, 3.7; quests spec 14.7): the
## fresh-run book (the main quest "Win back the Pearls" first, then Slime Basics), the layout at
## 1280 x 720, row order and dimming, the main quest's steps and Pearl slots, abandon and retry of
## Slime Basics (with the test hook and with the in-window confirm), the Tips and War journal rows,
## the empty book, and the ways in and out (pause menu, tab strip, menu key, Escape, row keys).
## Glyphs are the J2 look-alikes (quest_journal_model.gd MARK_*).
## Rewritten 2026-11-20: the chapter quests are retired, and with them the tests of a turn-in line,
## the retry quirk after A Place to Work (J3) and an abandoned NPC quest.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestService := preload("res://game/quests/quest_service.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")
const QuestJournalWindow := preload("res://game/ui/screens/quest_journal_window.gd")
const QuestJournalModel := preload("res://game/ui/screens/quest_journal_model.gd")
const ItemCell := preload("res://game/ui/screens/item_cell.gd")
const MenuWindows := preload("res://game/ui/screens/menu_windows.gd")

const MAIN := "win-back-the-pearls"
const BASICS := "slime-basics"
const MAIN_ROW := "★ Win back the Pearls\nMain · In progress · Step 1/3"
const SLIME_BASICS_ROW := "◆ Slime Basics\nSide · In progress"
const BASICS_CONTROLS := ["menu:inventory", "menu:crafting", "menu:journal", "menu:map", "pause"]


func test_open_fresh_run(t: TestContext) -> void:
	var journal := _journal(t)
	var windows := _windows(t)
	var journal_cue := _cue(&"JournalOpen")
	var menu_cue := _cue(&"MenuOpen")
	journal.open()
	t.check(bool(windows.call(&"is_open", &"quest-journal")), "GameWindows does not list the journal")
	t.check(t.world().has_pause_reason(&"modal"), "the world is not paused")
	t.equal(journal.title_label.text, "Quest Book", "title")
	t.equal(_row_labels(journal), [MAIN_ROW, SLIME_BASICS_ROW], "rows")
	var row := _row(journal, 0)
	t.check(row != null and row.is_selected() and row.has_focus(), "row 0 is not selected and focused")
	t.equal(journal.details_name_label.text, "Win back the Pearls", "details name")
	t.equal(journal.details_status_label.text, "Main · In progress · Step 1/3", "details status")
	t.check(journal.details_label.text.contains(QuestJournalModel.PEARLS_HEADING % [0, 8]),
		"the main quest's page lacks its Pearl slots:\n%s" % journal.details_label.text)
	t.equal(journal.action_button.text, "No action", "action of the main quest")
	t.check(journal.action_button.disabled, "the main quest's action is enabled")
	t.equal(journal.status_label.text, "", "status")
	t.equal(journal.close_button.text, "Close (Esc)", "close label")
	t.check(journal_cue != null and TestContext.played(journal_cue), "JournalOpen is not playing")
	t.check(menu_cue == null or not TestContext.played(menu_cue), "MenuOpen played")
	t.equal(_progress(t, BASICS).get("read-journal"), 1, "read-journal progress")
	journal.select_quest(1)
	t.equal(journal.details_name_label.text, "Slime Basics", "details name of row 1")
	t.equal(journal.details_status_label.text, "Side · In progress", "details status of row 1")
	t.equal(journal.action_button.text, "Abandon", "action of Slime Basics")
	t.check(not journal.action_button.disabled, "Abandon is disabled")
	journal.close()
	t.check(not t.tree.paused, "the world stayed paused")


## The panel follows the viewport (headless runs have a small one); the content is placed for the
## 940 px panel of a 1280 × 720 viewport, on screen (170, 50)-(1110, 670).
func test_layout_1280(t: TestContext) -> void:
	var journal := _journal(t)
	journal.open()
	_near_rect(t, journal.panel.get_global_rect(), _panel_rect(journal, Vector2(940.0, 620.0)), "panel")
	journal.call(&"_layout", 940.0)
	# The small headless viewport squeezed the wrapping labels; they reshape at the new width
	# on the next frame, then the layout fits them again.
	await t.steps(1)
	journal.call(&"_layout", 940.0)
	_near_rect(t, _content_rect(journal.title_label), _corners(20.0, 14.0, 920.0, 56.0), "Title")
	_near_rect(t, _content_rect(journal.quest_scroll), _corners(20.0, 66.0, 382.8, 600.0), "Quests")
	# A 22 px line is 32 px tall in Source Sans 3 (two more than Phaser's 30 px row).
	_near_rect(t, _content_rect(journal.details_name_label), _corners(413.6, 66.0, 920.0, 98.0), "DetailsName", 1.0)
	_near_rect(t, _content_rect(journal.details_status_label), _corners(413.6, 98.0, 920.0, 120.0), "DetailsStatus")
	_near_rect(t, _content_rect(journal.details_scroll), _corners(413.6, 126.0, 920.0, 488.0), "Details")
	_near_rect(t, _content_rect(journal.status_label), _corners(413.6, 498.0, 920.0, 526.0), "Status")
	_near_rect(t, _content_rect(journal.action_button), _corners(413.6, 568.0, 658.0, 608.0), "Action")
	_near_rect(t, _content_rect(journal.close_button), _corners(695.6, 568.0, 921.2, 608.0), "Close")
	t.equal(journal.content.custom_minimum_size.y, 620.0, "content height")
	await t.steps(1)
	var row := _row(journal, 0)
	if row != null:
		t.check(row.size.y >= 48.0, "row height %s" % row.size.y)
	journal.close()


func test_row_order(t: TestContext) -> void:
	var quests := _quests(t)
	for control_id: String in BASICS_CONTROLS:
		quests.handle_event(QuestEvents.CONTROL_USED, {"controlId": control_id})
	var journal := _journal(t)
	journal.open()
	t.equal(_row_labels(journal), [MAIN_ROW, "✓ Slime Basics\nSide · Done"], "rows")
	var alphas: Array = []
	for index in journal.quest_list.get_child_count():
		alphas.append(_row(journal, index).modulate.a)
	t.equal(alphas, [1.0, 0.5], "row alphas")
	journal.close()


## The main quest's page at its second step: the first done, the second's objectives, the slots.
func test_multi_stage_details(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	run.set_flag("pearl.fatty-one-eye")
	quests.handle_event(QuestEvents.BOSS_DEFEATED, {"bossId": "fatty-one-eye"})
	run.set_flag("pearl.fatty-one-eye.home")
	run.set_flag("pearl.orb-weaver-matron")
	var journal := _journal(t)
	journal.open()
	t.equal(_row_labels(journal)[0], "★ Win back the Pearls\nMain · In progress · Step 2/3", "row 0")
	t.equal(journal.details_status_label.text, "Main · In progress · Step 2/3", "details status")
	var page := journal.details_label.text
	t.check(page.contains("✓ Step 1: Fatty's Pearl"), "step 1 is not done on the page:\n%s" % page)
	t.check(page.contains("▶ Step 2: The Matron's Pearl"), "step 2 is not the current one on the page:\n%s" % page)
	t.check(page.contains("✓ Find the Pearl in the Weaver Hollow"), "the Matron's Pearl taken is not ticked:\n%s" % page)
	t.check(page.contains("• Beat the Orb-Weaver Matron"), "the Matron's fight is not open:\n%s" % page)
	t.check(page.contains(QuestJournalModel.PEARLS_HEADING % [1, 8]), "one Pearl home is not counted:\n%s" % page)
	t.equal(journal.action_button.text, "No action", "action label")
	journal.close()


func test_abandon_and_retry(t: TestContext) -> void:
	var quests := _quests(t)
	var journal := _journal(t)
	var titles: Array = []
	journal.confirm_abandon = func(title: String) -> bool:
		titles.append(title)
		return true
	var abandoned: Array = []
	var accepted: Array = []
	quests.quest_abandoned.connect(func(payload: Dictionary) -> void: abandoned.append(payload))
	quests.quest_accepted.connect(func(payload: Dictionary) -> void: accepted.append(payload))
	journal.open()
	journal.select_quest(1)
	journal.quest_action()
	t.equal(titles, ["Slime Basics"], "confirm titles")
	t.equal(journal.status_label.text, "Quest abandoned.", "status after Abandon")
	var record := _record(t, "slime-basics")
	t.equal(record["status"], "abandoned", "status")
	t.equal(record.get("resume_stage_id"), "learn-the-basics", "resume stage")
	t.equal(_row_labels(journal), [MAIN_ROW, "◆ Slime Basics\nSide · Abandoned"], "rows after Abandon")
	t.check(_row(journal, 1).is_selected(), "the abandoned row is not selected")
	t.equal(_row(journal, 1).modulate.a, 0.5, "abandoned row alpha")
	t.equal(journal.action_button.text, "Retry", "action after Abandon")
	t.equal(abandoned, [{"questId": "slime-basics"}], "quest_abandoned")
	journal.quest_action()
	t.equal(journal.status_label.text, "Quest restarted.", "status after Retry")
	record = _record(t, "slime-basics")
	t.equal(record["status"], "active", "status after Retry")
	t.check((record["progress"] as Dictionary).values().all(func(value: Variant) -> bool: return int(value) == 0),
		"progress after Retry %s" % [record["progress"]])
	t.equal(_row_labels(journal), [MAIN_ROW, SLIME_BASICS_ROW], "rows after Retry")
	t.equal(accepted, [{"questId": "slime-basics", "source": "automatic"}], "quest_accepted")
	journal.close()


func test_abandon_cancelled(t: TestContext) -> void:
	var quests := _quests(t)
	var journal := _journal(t)
	journal.confirm_abandon = func(_title: String) -> bool: return false
	var abandoned: Array = []
	quests.quest_abandoned.connect(func(payload: Dictionary) -> void: abandoned.append(payload))
	journal.open()
	journal.select_quest(1)
	journal.quest_action()
	t.equal(quests.status("slime-basics"), "active", "status")
	t.equal(journal.status_label.text, "", "status line")
	t.equal(abandoned, [], "quest_abandoned")
	journal.close()


## Owner decision J1: the in-window confirm, Cancel focused, Escape cancels it only.
func test_confirm_overlay(t: TestContext) -> void:
	var quests := _quests(t)
	var journal := _journal(t)
	journal.open()
	journal.select_quest(1)
	journal.quest_action()
	if not t.check(journal.is_confirming(), "no confirm"):
		return
	t.equal(journal.confirm_label.text, "Abandon \"Slime Basics\"? You can retry it later.", "confirm text")
	t.check(journal.confirm_cancel_button.has_focus(), "Cancel does not have the focus")
	t.tap(&"ui_cancel")
	await t.steps(1)
	t.check(not journal.is_confirming(), "Escape left the confirm open")
	t.check(journal.is_open(), "Escape closed the journal")
	t.equal(quests.status("slime-basics"), "active", "status after Escape")
	t.check(journal.action_button.has_focus(), "the Action button did not get the focus back")
	journal.quest_action()
	t.check(journal.is_confirming(), "no second confirm")
	journal.confirm_accept_button.pressed.emit()
	t.check(not journal.is_confirming(), "Abandon left the confirm open")
	t.equal(quests.status("slime-basics"), "abandoned", "status after Abandon")
	t.equal(journal.status_label.text, "Quest abandoned.", "status line")
	journal.close()


## The Tips row (once a tip is heard) and the War journal row (once a page is found) follow the
## active quests; each opens its own page.
func test_tips_and_war_journal_rows(t: TestContext) -> void:
	var run := Services.run()
	run.hear_tip("lili.yoi-hideout")
	run.quiet_items = true
	run.add_item("war-journal-page-1", 1)
	run.quiet_items = false
	var journal := _journal(t)
	journal.open()
	var rows := _row_labels(journal)
	t.equal(rows.size(), 4, "rows with a tip and a page: %s" % [rows])
	if rows.size() == 4:
		t.check(str(rows[2]).contains(QuestJournalModel.TIPS_TITLE) and str(rows[2]).contains(QuestJournalModel.TIPS_COUNT % 1),
			"the Tips row: %s" % rows[2])
		t.check(str(rows[3]).contains(QuestJournalModel.WAR_TITLE), "the War journal row: %s" % rows[3])
	journal.select_quest(2)
	t.equal(journal.details_name_label.text, QuestJournalModel.TIPS_TITLE, "the Tips page's name")
	t.check(journal.details_label.text.contains("Lili"), "the Tips page does not name Lili")
	t.check(journal.action_button.disabled, "the Tips row has an action")
	journal.select_quest(3)
	t.equal(journal.details_name_label.text, QuestJournalModel.WAR_TITLE, "the War journal page's name")
	t.check(journal.details_label.text.contains("Page 1:"), "the War journal lacks page 1:\n%s" % journal.details_label.text)
	journal.close()


func test_empty_journal(t: TestContext) -> void:
	var run := Services.run()
	for record: Dictionary in run.quests:
		record["status"] = "locked"
		record["active_stage_id"] = ""
	# Opening reports `control.used`, which re-evaluates the prerequisites: with the prologue running
	# (started, not done), the main quest and Slime Basics stay locked.
	run.set_flag("prologue.started")
	var journal := _journal(t)
	journal.open()
	t.equal(_row_labels(journal), [], "rows")
	t.equal(journal.details_name_label.text, QuestJournalModel.EMPTY_NAME, "details name")
	t.equal(journal.details_status_label.text, "", "details status")
	t.equal(journal.details_label.text, QuestJournalModel.EMPTY_DETAILS, "details")
	t.check(journal.action_button.disabled, "the action is enabled")
	t.check(journal.close_button.has_focus(), "Close does not have the focus")
	journal.close()


func test_open_paths_and_close(t: TestContext) -> void:
	var journal := _journal(t)
	var shell := Services.shell()
	if shell == null:
		t.note("no Shell autoload: the pause menu path was not driven")
		return
	t.check(shell.open_pause(), "the pause menu did not open")
	var button := shell.pause_menu.button_for(&"journal")
	if not t.check(button != null and not button.disabled, "the pause menu's Journal button is disabled"):
		shell.pause_menu.close()
		return
	button.pressed.emit()
	t.check(not shell.is_any_open(), "the pause menu stayed open")
	t.check(journal.is_open(), "the Journal button did not open the journal")
	var progress := _progress(t, "slime-basics")
	t.equal([progress.get("pause"), progress.get("read-journal")], [1, 1], "pause and read-journal progress")
	var close_cue := _cue(&"MenuClose")
	t.tap(&"menu")
	t.check(not journal.is_open(), "the menu key did not close the journal")
	t.check(close_cue != null and TestContext.played(close_cue), "MenuClose is not playing")
	t.check(not t.tree.paused, "the world stayed paused")
	journal.open()
	var select_cue := journal.select_sfx
	TestContext.silence(select_cue)
	var row := _row(journal, 1)
	if t.check(row != null, "no second row"):
		row.pressed.emit()
		t.equal(int(journal.model()["selected_index"]), 1, "selected after a click")
		t.check(TestContext.played(select_cue), "SelectSfx is not playing")
	journal.close()
	journal.open()
	t.equal(int(journal.model()["selected_index"]), 0, "selected after reopening")
	t.equal(journal.status_label.text, "", "status after reopening")
	t.tap(&"pause")
	await t.steps(1)
	t.check(not journal.is_open(), "Escape did not close the journal")
	t.check(not shell.is_any_open(), "Escape opened %s" % [shell.open_menus()])


## The menu's tab strip: Journal is enabled with the journal; switching closes the bag.
func test_journal_tab(t: TestContext) -> void:
	var menu := t.tree.get_first_node_in_group(&"menu_windows") as MenuWindows
	var journal := _journal(t)
	if not t.check(menu != null, "no MenuWindows"):
		return
	menu.open_bag()
	t.check(not menu.tabs.is_tab_disabled(&"journal"), "the Journal tab is disabled")
	var journal_cue := _cue(&"JournalOpen")
	menu.tabs.buttons[&"journal"].pressed.emit()
	t.check(journal.is_open() and not menu.bag.is_open(), "the Journal tab did not switch")
	t.equal(menu.current_tab(), &"journal", "current tab")
	t.check(menu.tabs.visible and menu.tabs.is_tab_disabled(&"journal"), "the strip does not show the journal as open")
	t.check(journal_cue != null and TestContext.played(journal_cue), "JournalOpen is not playing")
	menu.tabs.buttons[&"inventory"].pressed.emit()
	t.check(menu.bag.is_open() and not journal.is_open(), "the Bag tab did not switch back")
	menu.bag.close()


## The journal key (J, owner 2026-10-08): opens the Journal, closes it, and switches the open bag
## to it.
func test_journal_key(t: TestContext) -> void:
	var menu := t.tree.get_first_node_in_group(&"menu_windows") as MenuWindows
	var journal := _journal(t)
	if not t.check(menu != null, "no MenuWindows"):
		return
	t.tap(&"journal")
	await t.steps(1)
	t.check(journal.is_open(), "the journal key did not open the journal")
	t.tap(&"journal")
	await t.steps(1)
	t.check(not journal.is_open(), "the journal key did not close the journal")
	menu.open_bag()
	t.tap(&"journal")
	await t.steps(1)
	t.check(journal.is_open() and not menu.bag.is_open(), "the journal key did not switch the bag to the journal")
	journal.close()


## Up / down on a focused row select the neighbour and move the focus there; End / Home the ends.
func test_row_keys(t: TestContext) -> void:
	# A tip heard makes a third row (Tips).
	Services.run().hear_tip("lili.yoi-hideout")
	var journal := _journal(t)
	journal.open()
	if not t.check(journal.quest_list.get_child_count() == 3, "rows %s" % [_row_labels(journal)]):
		journal.close()
		return
	_row(journal, 0).gui_input.emit(_action(&"ui_down"))
	t.equal(int(journal.model()["selected_index"]), 1, "selected after down")
	t.check(_row(journal, 1).has_focus(), "the focus did not follow down")
	_row(journal, 1).gui_input.emit(_action(&"ui_end"))
	t.equal(int(journal.model()["selected_index"]), 2, "selected after End")
	_row(journal, 2).gui_input.emit(_action(&"ui_down"))
	t.equal(int(journal.model()["selected_index"]), 2, "down past the last row")
	_row(journal, 2).gui_input.emit(_action(&"ui_home"))
	t.equal(int(journal.model()["selected_index"]), 0, "selected after Home")
	t.check(_row(journal, 0).has_focus(), "the focus did not follow Home")
	journal.close()


# --- helpers ----------------------------------------------------------------------------------

func _journal(t: TestContext) -> QuestJournalWindow:
	return t.tree.get_first_node_in_group(&"quest_journal") as QuestJournalWindow


func _windows(t: TestContext) -> Node:
	return t.tree.get_first_node_in_group(&"game_windows")


func _quests(t: TestContext) -> QuestService:
	return t.tree.get_first_node_in_group(&"quests") as QuestService


## The live record of `quest_id` in RunState.quests.
func _record(_t: TestContext, quest_id: String) -> Dictionary:
	for record: Dictionary in Services.run().quests:
		if str(record["quest_id"]) == quest_id:
			return record
	return {}


func _progress(t: TestContext, quest_id: String) -> Dictionary:
	return _record(t, quest_id).get("progress", {})


func _row(journal: QuestJournalWindow, index: int) -> ItemCell:
	if index < 0 or index >= journal.quest_list.get_child_count():
		return null
	return journal.quest_list.get_child(index) as ItemCell


func _row_labels(journal: QuestJournalWindow) -> Array:
	var labels: Array = []
	for cell: Node in journal.quest_list.get_children():
		labels.append((cell as ItemCell).label_text())
	return labels


static func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
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


static func _near_rect(t: TestContext, actual: Rect2, expected: Rect2, label: String, tolerance: float = 0.5) -> void:
	t.check(actual.position.distance_to(expected.position) <= tolerance and actual.end.distance_to(expected.end) <= tolerance,
		"%s: got %s, expected %s" % [label, actual, expected])
