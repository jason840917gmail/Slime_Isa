extends RefCounted
## Quests, NPC talk, the dialogue box, the tracker, the NPC markers and the toasts
## (docs/godot/specs/quests.md 10.10 and 14). level-1: the Elder (`level-1-npc-village-elder-plop`),
## Pip (`level-1-npc-red-slime-boy`, his `mission` talk in a new run: no tip; owner, 2026-11-20), Lili
## (`level-1-npc-lili`, her tip talk). NPCs are placed next to the player at (900, 1200), where nothing else is in reach,
## and stop wandering (no lock, so the conversation's lock is the only one).
## Rewritten 2026-11-20: the content is the main quest "Win back the Pearls" and Slime Basics; the
## Phaser-era chapter quests are retired, and with them the tests that needed an NPC quest to offer,
## accept, decline, turn in, abandon and reoffer, the waypoints to their givers and places, their kill,
## collect, place and restore objectives and their rewards (the machinery stays; no content uses it).
## The main quest's own tests are test_main_quest.gd's.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestService := preload("res://game/quests/quest_service.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")
const QuestNpcTalk := preload("res://game/quests/quest_npc_talk.gd")
const DialogueBox := preload("res://game/ui/screens/dialogue_box.gd")
const InteractionController := preload("res://game/interaction/interaction_controller.gd")
const QuestTracker := preload("res://game/ui/quest_tracker.gd")
const NpcQuestMarkers := preload("res://game/ui/npc_quest_markers.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const ELDER := "level-1-npc-village-elder-plop"
const ELDER_ID := "village-elder-plop"
const PIP := "level-1-npc-red-slime-boy"
const PIP_ID := "red-slime-boy"
const LILI := "level-1-npc-lili"
const LILI_ID := "lili"
const MAIN := "win-back-the-pearls"
const PIPS_WORKSHOP := "pips-workshop"
const BASICS := "slime-basics"
## Pip's Workshop waits locked until Pip's mission (test_main_quest.gd).
const CATALOG_ORDER: Array[String] = [MAIN, PIPS_WORKSHOP, BASICS]
const BASICS_CONTROLS := ["menu:inventory", "menu:crafting", "menu:journal", "menu:map", "pause"]


func test_new_run_states(t: TestContext) -> void:
	await t.steps(2)
	var run := Services.run()
	t.equal(run.quests.size(), CATALOG_ORDER.size(), "quest records")
	var ids: Array[String] = []
	for record: Dictionary in run.quests:
		ids.append(str(record["quest_id"]))
	t.equal(ids, CATALOG_ORDER, "record order")
	var quests := _quests(t)
	var basics := quests.state(BASICS)
	t.equal(basics.get("status"), "active", "slime-basics status")
	t.equal(basics.get("active_stage_id"), "learn-the-basics", "slime-basics stage")
	t.equal(basics.get("progress"), {"open-bag": 0, "see-crafting": 0, "read-journal": 0, "open-map": 0, "pause": 0},
		"slime-basics progress")
	t.equal(quests.status(MAIN), "active", "the main quest")
	t.check(run.is_quest_active(BASICS), "RunState does not see slime-basics active")
	t.check(run.is_quest_active(MAIN), "RunState does not see the main quest active")
	t.equal(quests.status(PIPS_WORKSHOP), "locked", "Pip's Workshop before Pip's mission")


## An NPC with no quest to give is a plain talk (priority 50, "Talk to <name>"), Pip's mission too; the
## markers show the gold "!" only over an NPC with a tip not heard yet.
func test_plain_talk_candidate_and_markers(t: TestContext) -> void:
	var pip := await _meet(t, PIP)
	if pip == null:
		return
	var interaction := _interaction(t)
	t.equal(interaction.current().get("id"), "quest-npcs:%s:talk" % PIP, "candidate id")
	t.equal(interaction.current().get("priority"), 50, "talk priority")
	t.equal(interaction.get_prompt().get_text(), "Right-click: Talk to Pip", "talk prompt")
	var quests := _quests(t)
	t.equal(quests.marker_for(PIP_ID), "", "Pip's marker")
	t.equal(quests.marker_for(ELDER_ID), "", "the Elder's marker before the prologue is over")
	t.equal(quests.marker_for(LILI_ID), "tip", "Lili's marker")
	await t.tree.process_frame
	await t.tree.process_frame
	t.equal(_markers(t).kind_for(PIP), "", "Pip's marker label")
	t.equal(_markers(t).kind_for(LILI), "tip", "Lili's marker label")


## Escape during a talk's lines closes the box and frees the NPC without opening the pause menu; a
## talk's gifts are given when its pages end, read or closed (quests spec 14.3).
func test_escape_during_lines(t: TestContext) -> void:
	var lili := await _meet(t, LILI)
	if lili == null:
		return
	var quests := _quests(t)
	_fake_clock(quests.dialogue)
	_interaction(t).handle_interact()
	if not t.check(quests.dialogue.is_open(), "no dialogue"):
		return
	t.check(not Services.run().has_heard_tip("lili.yoi-hideout"), "the tip came before the lines ended")
	t.tap(&"pause")
	await t.steps(1)
	t.check(not quests.dialogue.is_open(), "Escape left the dialogue open")
	t.check(Services.run().has_heard_tip("lili.yoi-hideout"), "closing the lines did not give the tip")
	t.check(Services.run().knows_recipe("brew-tonic"), "closing the lines did not teach the tonic")
	await t.steps(2)
	t.check(not lili.is_interaction_locked(), "Lili stayed locked")
	t.check(not t.tree.paused, "the world stayed paused")
	var shell := Services.shell()
	if shell != null:
		t.check(not shell.is_any_open(), "Escape opened %s" % [shell.open_menus()])


## Pip's mission (pages of 92, 133 and 173 characters since 2026-11-20) reveals at 45 characters a
## second; Space skips the typing, then turns the page; a held Space does nothing; Enter and keypad
## Enter advance too; Escape closes.
func test_reveal_speed(t: TestContext) -> void:
	var pip := await _meet(t, PIP)
	if pip == null:
		return
	var quests := _quests(t)
	var dialogue := quests.dialogue
	var clock := _fake_clock(dialogue)
	var talked: Array = []
	quests.npc_talked.connect(func(payload: Dictionary) -> void: talked.append(payload))
	var interaction := _interaction(t)
	t.equal(interaction.current().get("id"), "quest-npcs:%s:talk" % PIP, "Pip's candidate")
	interaction.handle_interact()
	if not t.check(dialogue.is_open(), "no dialogue"):
		return
	var pages := dialogue.pages()
	t.equal(str(QuestNpcTalk.matching_talk(PIP_ID).get("id", "")), "mission", "Pip's talk")
	if not t.equal(pages.size(), 3, "Pip's pages"):
		return
	t.equal([pages[0].length(), pages[1].length(), pages[2].length()], [92, 133, 173], "page lengths")
	t.equal(talked, [{"npcId": PIP_ID}], "npc_talked at open")
	t.equal(dialogue.page_label(), "1 / 3", "page label")
	t.equal(dialogue.next_label(), "Skip  ▸▸", "typing label")
	_key(t, KEY_SPACE)
	t.equal(dialogue.visible_text().length(), 92, "Space shows the page")
	t.equal(dialogue.next_label(), "Next  ▸", "label after the skip")
	_key(t, KEY_SPACE)
	t.equal(dialogue.page_index(), 1, "Space turns the page")
	t.equal(dialogue.visible_text().length(), 0, "page 2 starts empty")
	dialogue.advance_reveal(1000.0)
	t.equal(dialogue.visible_text().length(), 45, "characters after 1 s")
	_key(t, KEY_SPACE, true)
	t.equal(dialogue.page_index(), 1, "a held Space turned the page")
	t.equal(dialogue.visible_text().length(), 45, "a held Space skipped")
	_key(t, KEY_ENTER)
	t.equal(dialogue.visible_text().length(), 133, "Enter shows the page")
	_key(t, KEY_KP_ENTER)
	t.equal(dialogue.page_index(), 2, "keypad Enter turns the page")
	# 173 characters at 45 a second: shown within 4 s.
	clock["ms"] = float(clock["ms"]) + 4000.0
	dialogue.advance_reveal(0.0)
	t.equal(dialogue.next_label(), "Done  ✓", "last page label")
	_key(t, KEY_ESCAPE)
	t.check(not dialogue.is_open(), "Escape left the dialogue open")
	t.check(not pip.is_interaction_locked(), "Pip stayed locked")
	t.equal(talked.size(), 1, "talks recorded")


## Owner decision Q4: the interact button advances the dialogue too.
func test_interact_advances_dialogue(t: TestContext) -> void:
	var pip := await _meet(t, PIP)
	if pip == null:
		return
	var dialogue := _quests(t).dialogue
	_fake_clock(dialogue)
	_interaction(t).handle_interact()
	t.tap(&"interact")
	t.equal(dialogue.visible_text().length(), 92, "interact skips the typing")
	t.tap(&"interact")
	t.equal(dialogue.page_index(), 1, "interact turns the page")
	await t.steps(2)
	t.check(dialogue.is_open(), "an interact press reached the world and closed the dialogue")


## Slime Basics completes by itself once each control was used, and pays its reward.
func test_slime_basics_completes_and_pays(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	var coins := run.coins()
	var toasts: Array = []
	quests.notifications.toast_shown.connect(func(payload: Dictionary) -> void: toasts.append(payload))
	for control_id: String in BASICS_CONTROLS:
		quests.handle_event(QuestEvents.CONTROL_USED, {"controlId": control_id})
	t.equal(quests.status(BASICS), "completed", "Slime Basics after every control")
	t.equal(run.coins(), coins + 10, "Slime Basics' reward")
	var shown: Array = []
	for toast: Dictionary in toasts:
		shown.append(str(toast["text"]))
	var expected: Array = ["Stage complete: Slime Basics", "QUEST COMPLETE: Slime Basics"]
	for line: String in QuestCatalog.reward_lines({"coins": 10}):
		expected.append("+ " + line)
	t.equal(shown, expected, "completion toasts")


func test_tracker_fresh_run(t: TestContext) -> void:
	await t.steps(2)
	var tracker := _tracker(t)
	if not t.check(tracker != null, "no tracker"):
		return
	var model := tracker.model()
	t.check(tracker.visible, "the tracker is hidden")
	# One goal line (roadmap 4.12): the first tracked quest and its next step; the rest in the Journal.
	t.equal(model.get("title"), "Win back the Pearls", "the line's quest")
	t.equal((model.get("color") as Color).to_html(false), "ffd277", "main story colour")
	t.equal(model.get("step"), "Find the Pearl in Fatty's Lair", "the next step")
	t.equal([model.get("count"), model.get("more")], [2, 1], "tracked quests")
	t.equal(tracker.title_label.text, "WIN BACK THE PEARLS", "the title in small capitals")
	t.check(tracker.more_button.visible and tracker.more_button.text == "+1", "no +1 for the other quest")
	t.equal(model.get("bookHint"), "J · Journal", "book hint")
	var rect: Rect2 = model.get("rect")
	t.equal([tracker.position, tracker.size], [rect.position, rect.size], "the line's rect")
	t.equal(rect.position, Vector2(14, 46), "the line sits under the coin chip")
	t.check(rect.size.x >= QuestTracker.MIN_WIDTH and rect.size.x <= QuestTracker.MAX_WIDTH, "line width %s" % rect.size.x)
	# The "+1" shows the next quest: Slime Basics, its first step.
	tracker.show_next()
	t.equal(tracker.model().get("title"), "Slime Basics", "the next quest")
	t.equal(tracker.model().get("step"), "Open your bag (%s)" % ControlLabels.control_label(&"menu"), "Slime Basics' first step")
	tracker.show_next()
	t.equal(tracker.model().get("title"), "Win back the Pearls", "back to the first quest")
	# A Pearl taken: the line moves to the next open objective.
	Services.run().set_flag("pearl.fatty-one-eye")
	await t.steps(1)
	t.equal(_tracker(t).model().get("step"), "Beat Fatty One Eye", "the next step once the Pearl is taken")


## Slime Basics has no sprint step since 2026-10-08 (no sprint from the start); pausing counts.
func test_pause_control(t: TestContext) -> void:
	var quests := _quests(t)
	t.check(not (quests.state(BASICS)["progress"] as Dictionary).has("sprint"), "Slime Basics still has a sprint step")
	var shell := Services.shell()
	if shell == null:
		t.note("no Shell autoload: the pause objective was not driven")
		return
	if not t.check(shell.open_pause(), "the pause menu did not open"):
		return
	t.equal((quests.state(BASICS)["progress"] as Dictionary).get("pause"), 1, "pause")
	shell.pause_menu.close()


## The windows count for the tutorial; the crafting window is a station's since 2026-11-20 (a
## campfire's), still the `menu:crafting` control.
func test_menu_windows_count_for_the_tutorial(t: TestContext) -> void:
	var quests := _quests(t)
	var windows := t.tree.get_first_node_in_group(&"game_windows")
	if not t.check(windows != null, "no GameWindows"):
		return
	for surface_id: StringName in [&"inventory", &"crafting", &"quest-journal", &"world-map"]:
		windows.window_opened.emit(surface_id)
	t.equal(quests.state(BASICS)["progress"], {"open-bag": 1, "see-crafting": 1, "read-journal": 1, "open-map": 1,
		"pause": 0}, "tutorial progress")


func test_save_round_trip(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	run.set_flag("pearl.fatty-one-eye")
	quests.handle_event(QuestEvents.CONTROL_USED, {"controlId": "menu:map"})
	var before := run.quests.duplicate(true)
	var data := run.serialize()
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if not t.check(parsed is Dictionary, "the save did not parse"):
		return
	t.check(run.install(run._integers(parsed)), "install refused the save")
	t.equal(quests.status(MAIN), "active", "the main quest after the load")
	t.equal(run.quests, before, "records after the round trip")
	t.equal(typeof(quests.state(MAIN).get("accepted_at")), TYPE_INT, "accepted_at type")
	t.equal(typeof(quests.state(MAIN).get("active_stage_id")), TYPE_STRING, "active_stage_id type")
	t.equal(int((quests.state(MAIN).get("progress") as Dictionary).get("take-pearl-1", 0)), 1, "the Pearl taken after the load")
	t.check(run.is_quest_active(MAIN), "RunState lost the active quest")


## Owner decision Q7: a broken record is reset to locked with a warning; the rest survives (and a
## retired id is dropped without one).
func test_broken_record_resets(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	var data := run.serialize()
	var records: Array = data["quests"]
	for record: Dictionary in records:
		if record["quest_id"] == BASICS:
			record["progress"] = {"open-bag": 7}
	records.append({"quest_id": "gather-building-materials", "status": "completed"})
	run.install(data)
	t.equal(quests.status(BASICS), "locked", "the broken record")
	t.equal(quests.status(MAIN), "active", "a sound record")
	t.equal(run.quests.size(), CATALOG_ORDER.size(), "records after the load")


func test_teardown_releases_npc(t: TestContext) -> void:
	var pip := await _meet(t, PIP)
	if pip == null:
		return
	var quests := _quests(t)
	_interaction(t).handle_interact()
	if not t.check(quests.dialogue.is_open() and pip.is_interaction_locked(), "no conversation"):
		return
	quests.close_conversations()
	t.check(not pip.is_interaction_locked(), "Pip stayed locked")
	t.check(not quests.dialogue.is_open() and not quests.offer_window.is_open(), "a window stayed open")
	t.check(not t.world().has_pause_reason(&"modal"), "the modal pause stayed")
	t.check(not t.tree.paused, "the world stayed paused")


## An ability learned shows its banner (the ceremony is off in the tests) with its key.
func test_ability_banner(t: TestContext) -> void:
	var quests := _quests(t)
	var banners: Array = []
	quests.notifications.banner_shown.connect(func(payload: Dictionary) -> void: banners.append(payload))
	Services.run().learn_ability("dodge")
	if t.equal(banners.size(), 1, "ability banners"):
		t.equal(banners[0]["text"], "Roll learned: press %s" % ControlLabels.control_label(AbilityBox.key_action(&"dodge")),
			"ability banner")
		t.equal((banners[0]["color"] as Color).to_html(false), "9ff0c8", "ability colour")


## The main quest cannot be abandoned; Slime Basics can, and its automatic retry leaves it locked
## (its prerequisite no longer holds: spec 2.8 quirk).
func test_abandon(t: TestContext) -> void:
	var quests := _quests(t)
	t.equal(quests.abandon(MAIN).get("code"), "mandatory-quest", "abandoning the main quest")
	t.check(bool(quests.abandon(BASICS).get("ok")), "slime-basics could not be abandoned")
	t.equal(quests.status(BASICS), "abandoned", "slime-basics after abandoning")
	t.check(bool(quests.retry_abandoned_automatic(BASICS).get("ok")), "retry refused")
	t.equal(quests.status(BASICS), "active", "slime-basics after the retry")


# --- helpers ----------------------------------------------------------------------------------

func _quests(t: TestContext) -> QuestService:
	return t.tree.get_first_node_in_group(&"quests") as QuestService


func _interaction(t: TestContext) -> InteractionController:
	return t.tree.get_first_node_in_group(&"interaction") as InteractionController


func _tracker(t: TestContext) -> QuestTracker:
	return t.tree.get_first_node_in_group(QuestTracker.GROUP) as QuestTracker


func _markers(t: TestContext) -> NpcQuestMarkers:
	return t.tree.get_first_node_in_group(NpcQuestMarkers.GROUP) as NpcQuestMarkers


func _npc(t: TestContext, instance_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == instance_id:
			return node
	return null


func _meet(t: TestContext, instance_id: String) -> Node:
	var npc := _npc(t, instance_id)
	if not t.check(npc != null, "no NPC %s" % instance_id):
		return null
	npc.call(&"configure_wander", {})
	var body := npc.get(&"body") as CharacterBody2D
	body.velocity = Vector2.ZERO
	var offset: Vector2 = npc.call(&"get_phaser_position") - body.global_position
	body.global_position = CENTRE + NPC_OFFSET - offset
	body.reset_physics_interpolation()
	t.teleport_player(CENTRE)
	await t.steps(1)
	_interaction(t).refresh(null)
	return npc


## Replaces the dialogue's clock with a fake one ({"ms"}), so the reveal only moves when told.
static func _fake_clock(dialogue: DialogueBox) -> Dictionary:
	var clock := {"ms": 1000.0}
	dialogue.clock = func() -> float: return float(clock["ms"])
	return clock


## A physical key press (and its release, or an echo press when `echo`).
static func _key(t: TestContext, code: Key, echo: bool = false) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	press.echo = echo
	t.tree.root.push_input(press)
	if echo:
		return
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	t.tree.root.push_input(release)
