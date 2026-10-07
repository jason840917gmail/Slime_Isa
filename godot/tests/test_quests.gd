extends RefCounted
## Quests, NPC quest talk, the dialogue box, the offer / turn-in window, the tracker, the NPC
## markers, the toasts and the waypoint (docs/godot/specs/quests.md 10.10). level-1: the Elder
## (`level-1-npc-village-elder-plop`, A Place to Work), Pip (`level-1-npc-red-slime-boy`, plain
## talk), the forge ruin (`level-1-forge`), Fatty's camp, the loose wood piles 03 (704, 512) and 04
## (608, 576). NPCs are placed next to the player at (900, 1200), where nothing else is in reach,
## and stop wandering (no lock, so the conversation's lock is the only one).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestService := preload("res://game/quests/quest_service.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")
const DialogueBox := preload("res://game/ui/screens/dialogue_box.gd")
const QuestOfferWindow := preload("res://game/ui/screens/quest_offer_window.gd")
const InteractionController := preload("res://game/interaction/interaction_controller.gd")
const QuestTracker := preload("res://game/ui/quest_tracker.gd")
const NpcQuestMarkers := preload("res://game/ui/npc_quest_markers.gd")
const QuestWaypointView := preload("res://game/ui/quest_waypoint_view.gd")
const RestorationSiteScript := preload("res://game/scripts/restoration_site.gd")
const BossCampScript := preload("res://game/scripts/boss_camp.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")
const QuestWaypoint := preload("res://game/quests/quest_waypoint.gd")

const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const ELDER := "level-1-npc-village-elder-plop"
const ELDER_ID := "village-elder-plop"
const PIP := "level-1-npc-red-slime-boy"
const PLACE := "a-place-to-work"
const CATALOG_ORDER: Array[String] = ["a-place-to-work", "slime-basics", "stone-tools", "worm-trouble",
	"the-one-eyed-guardian", "the-old-workshop", "a-tonic-for-lili", "snack-for-the-road",
	"beyond-the-verdant-gate", "a-harder-pick", "rekindle-the-forge", "iron-gear", "sunnys-basket",
	"the-matrons-nest"]
const OFFER_DESCRIPTION := "Every good slime needs a workbench. Build one and set it up in the clearing.\n\n• Craft a Workbench (40 wood) (0/1)\n\nReward: 20× Wood · New recipe: Stone Axe · New recipe: Stone Pickaxe"
const PLACE_PROGRESS_PAGES: Array[String] = ["A workbench is the heart of every camp. Wood is scattered all over the clearing.",
	"Still to do for \"A Place to Work\":\n• Craft a Workbench (40 wood) (0/1)"]
const SLIME_BASICS_LINES := "• Open your bag (E)\n• Look at the Crafting tab (E, then its tab)\n• Read your Journal (E, then its tab)\n• Open the map (M)\n• Sprint (hold Shift)\n• Pause to save or change settings (Esc)"
const WORKBENCH_CRAFT := {"recipeId": "craft-workbench", "itemId": "workbench", "quantity": 1}
const WORKBENCH_PLACED := {"placementId": "p1", "itemId": "workbench", "mapId": "level-1", "sceneId": "", "x": 0, "y": 0}


func test_new_run_states(t: TestContext) -> void:
	await t.steps(2)
	var run := Services.run()
	t.equal(run.quests.size(), 14, "quest records")
	var ids: Array[String] = []
	for record: Dictionary in run.quests:
		ids.append(str(record["quest_id"]))
	t.equal(ids, CATALOG_ORDER, "record order")
	var quests := _quests(t)
	t.equal(quests.status(PLACE), "available", "a-place-to-work")
	var basics := quests.state("slime-basics")
	t.equal(basics.get("status"), "active", "slime-basics status")
	t.equal(basics.get("active_stage_id"), "learn-the-basics", "slime-basics stage")
	t.equal(basics.get("progress"), {"open-bag": 0, "see-crafting": 0, "read-journal": 0, "open-map": 0, "sprint": 0, "pause": 0},
		"slime-basics progress")
	var locked := 0
	for record: Dictionary in run.quests:
		if record["status"] == "locked":
			locked += 1
	t.equal(locked, 12, "locked quests")
	t.check(run.is_quest_active("slime-basics"), "RunState does not see slime-basics active")
	t.check(not run.is_quest_active(PLACE), "an available quest counts as active")


func test_elder_offer_candidate_and_marker(t: TestContext) -> void:
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var interaction := _interaction(t)
	t.equal(interaction.current().get("id"), "quest-npcs:%s:offer" % ELDER, "candidate id")
	t.equal(interaction.current().get("priority"), 90, "offer priority")
	t.equal(interaction.get_prompt().get_text(), "Right-click: Talk to Village Elder Plop", "offer prompt")
	var quests := _quests(t)
	t.equal(quests.marker_for(ELDER_ID), "main-offer", "Elder marker")
	t.equal(quests.marker_for("lili"), "", "Lili marker")
	await t.tree.process_frame
	await t.tree.process_frame
	t.equal(_markers(t).kind_for(ELDER), "main-offer", "Elder marker label")
	t.equal(_markers(t).kind_for("level-1-npc-lili"), "", "Lili marker label")


func test_offer_conversation_accept(t: TestContext) -> void:
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var quests := _quests(t)
	var dialogue := quests.dialogue
	var offer := quests.offer_window
	_fake_clock(dialogue)
	var events := {"accepted": [], "talked": []}
	quests.quest_accepted.connect(func(payload: Dictionary) -> void: (events["accepted"] as Array).append(payload))
	quests.npc_talked.connect(func(payload: Dictionary) -> void: (events["talked"] as Array).append(payload))
	t.check(_interaction(t).handle_interact(), "the Elder did not talk")
	if not t.check(dialogue.is_open(), "no dialogue"):
		return
	t.equal(dialogue.speaker(), "Village Elder Plop", "speaker")
	t.equal(dialogue.page_label(), "1 / 3", "page label")
	t.equal(dialogue.next_label(), "Skip  ▸▸", "next label while typing")
	t.check(t.tree.paused, "the world runs during the dialogue")
	t.check(t.world().has_pause_reason(&"modal"), "no modal pause reason")
	t.check(elder.is_interaction_locked(), "the Elder is not locked")
	dialogue.advance()
	t.equal(dialogue.visible_text(), dialogue.pages()[0], "a skip shows the whole page")
	t.equal(dialogue.next_label(), "Next  ▸", "next label after the skip")
	dialogue.advance()
	t.equal(dialogue.page_index(), 1, "page after Next")
	dialogue.advance()
	dialogue.advance()
	dialogue.advance()
	t.equal(dialogue.page_index(), 2, "last page")
	t.equal(dialogue.next_label(), "Continue  ▸", "finish label")
	dialogue.advance()
	t.check(not dialogue.is_open(), "the dialogue stayed open")
	if not t.check(offer.is_open(), "the offer window did not open"):
		return
	t.equal(offer.title_text(), "A Place to Work", "offer title")
	t.equal(offer.accept_label(), "Accept quest", "accept label")
	t.equal(offer.decline_label(), "Decline / close", "decline label")
	t.equal(offer.description_text(), OFFER_DESCRIPTION, "offer description")
	t.check(t.tree.paused, "the world ran between the dialogue and the offer")
	t.check((events["talked"] as Array).is_empty(), "the offer recorded a talk before the decision")
	offer.invoke("accept")
	var state := quests.state(PLACE)
	t.equal(state.get("status"), "active", "status after accepting")
	t.equal(state.get("active_stage_id"), "build-workbench", "stage after accepting")
	t.equal(events["accepted"], [{"questId": PLACE, "source": "npc"}], "quest_accepted")
	t.equal(events["talked"], [{"npcId": ELDER_ID}], "npc_talked")
	t.check(ELDER_ID in (Services.run().story["talked_npc_ids"] as Array), "the talk was not recorded")
	t.check(not offer.is_open(), "the offer window stayed open")
	t.check(not t.tree.paused, "the world stayed paused")
	t.check(not elder.is_interaction_locked(), "the Elder stayed locked")
	t.equal(quests.marker_for(ELDER_ID), "in-progress", "Elder marker after accepting")


func test_escape_during_lines_changes_nothing(t: TestContext) -> void:
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var quests := _quests(t)
	_fake_clock(quests.dialogue)
	_interaction(t).handle_interact()
	if not t.check(quests.dialogue.is_open(), "no dialogue"):
		return
	t.tap(&"pause")
	await t.steps(1)
	t.check(not quests.dialogue.is_open(), "Escape left the dialogue open")
	t.check(not quests.offer_window.is_open(), "Escape opened the offer window")
	t.equal(quests.status(PLACE), "available", "status after Escape")
	t.equal(Services.run().story["talked_npc_ids"], [], "talked ids after Escape")
	t.check(not elder.is_interaction_locked(), "the Elder stayed locked")
	t.check(not t.tree.paused, "the world stayed paused")
	var shell := Services.shell()
	if shell != null:
		t.check(not shell.is_any_open(), "Escape opened %s" % [shell.open_menus()])


func test_decline_records_talk(t: TestContext) -> void:
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var quests := _quests(t)
	_fake_clock(quests.dialogue)
	_interaction(t).handle_interact()
	_read_through(quests.dialogue)
	if not t.check(quests.offer_window.is_open(), "no offer window"):
		return
	quests.offer_window.invoke("decline")
	t.equal(quests.status(PLACE), "available", "status after declining")
	t.check(Services.run().has_talked_to(ELDER_ID), "declining did not record the talk")
	t.check(not quests.offer_window.is_open(), "the offer window stayed open")
	t.check(not elder.is_interaction_locked(), "the Elder stayed locked")
	_interaction(t).refresh(null)
	t.equal(_interaction(t).current().get("id"), "quest-npcs:%s:offer" % ELDER, "candidate after declining")


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
	var pages := QuestCatalog.npc_default_pages("red-slime-boy")
	t.equal([(pages[0] as String).length(), (pages[1] as String).length(), (pages[2] as String).length()], [72, 61, 51], "page lengths")
	t.equal(talked, [{"npcId": "red-slime-boy"}], "npc_talked at open")
	t.equal(dialogue.page_label(), "1 / 3", "page label")
	t.equal(dialogue.next_label(), "Skip  ▸▸", "typing label")
	dialogue.advance_reveal(1000.0)
	t.equal(dialogue.visible_text().length(), 45, "characters after 1 s")
	_key(t, KEY_SPACE)
	t.equal(dialogue.visible_text().length(), 72, "Space shows the page")
	t.equal(dialogue.next_label(), "Next  ▸", "label after the skip")
	_key(t, KEY_SPACE)
	t.equal(dialogue.page_index(), 1, "Space turns the page")
	t.equal(dialogue.visible_text().length(), 0, "page 2 starts empty")
	_key(t, KEY_SPACE, true)
	t.equal(dialogue.page_index(), 1, "a held Space turned the page")
	t.equal(dialogue.visible_text().length(), 0, "a held Space skipped")
	_key(t, KEY_ENTER)
	_key(t, KEY_KP_ENTER)
	t.equal(dialogue.page_index(), 2, "Enter / keypad Enter")
	clock["ms"] = float(clock["ms"]) + 2000.0
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
	t.equal(dialogue.visible_text().length(), 72, "interact skips the typing")
	t.tap(&"interact")
	t.equal(dialogue.page_index(), 1, "interact turns the page")
	await t.steps(2)
	t.check(dialogue.is_open(), "an interact press reached the world and closed the dialogue")


func test_talk_progress_pages(t: TestContext) -> void:
	var quests := _quests(t)
	quests.debug_activate(PLACE)
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var interaction := _interaction(t)
	t.equal(interaction.current().get("id"), "quest-npcs:%s:talk" % ELDER, "candidate while the quest runs")
	t.equal(interaction.current().get("priority"), 50, "talk priority")
	var talked: Array = []
	quests.npc_talked.connect(func(payload: Dictionary) -> void: talked.append(payload))
	interaction.handle_interact()
	t.equal(quests.dialogue.pages(), PLACE_PROGRESS_PAGES, "progress pages")
	t.equal(talked, [{"npcId": ELDER_ID}], "npc_talked at open")
	quests.dialogue.close()
	t.check(not elder.is_interaction_locked(), "the Elder stayed locked")


func test_stage_advance_and_turn_in(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	quests.debug_activate(PLACE)
	var events := {"progressed": [], "stages": [], "available": [], "completed": []}
	quests.quest_progressed.connect(func(payload: Dictionary) -> void: (events["progressed"] as Array).append(payload))
	quests.quest_stage_completed.connect(func(payload: Dictionary) -> void: (events["stages"] as Array).append(payload))
	quests.quest_available.connect(func(payload: Dictionary) -> void: (events["available"] as Array).append(payload))
	quests.quest_completed.connect(func(payload: Dictionary) -> void: (events["completed"] as Array).append(payload))
	quests.handle_event(QuestEvents.CRAFT_COMPLETED, WORKBENCH_CRAFT)
	t.equal(events["progressed"], [{"questId": PLACE, "stageId": "build-workbench", "objectiveId": "craft-workbench", "before": 0, "after": 1}],
		"quest_progressed")
	t.equal(events["stages"], [{"questId": PLACE, "stageId": "build-workbench"}], "quest_stage_completed")
	var state := quests.state(PLACE)
	t.equal(state.get("active_stage_id"), "place-workbench", "second stage")
	t.equal((state["progress"] as Dictionary).get("place-workbench"), 0, "second stage progress")
	quests.handle_event(QuestEvents.FURNITURE_PLACED, WORKBENCH_PLACED)
	t.check(bool(quests.view(PLACE).get("ready_to_turn_in")), "not ready to turn in")
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var interaction := _interaction(t)
	t.equal(interaction.current().get("id"), "quest-npcs:%s:turn-in" % ELDER, "turn-in candidate")
	t.equal(interaction.current().get("priority"), 100, "turn-in priority")
	t.equal(interaction.get_prompt().get_text(), "Right-click: Return to Village Elder Plop", "turn-in prompt")
	t.equal(quests.marker_for(ELDER_ID), "turn-in", "turn-in marker")
	_fake_clock(quests.dialogue)
	interaction.handle_interact()
	t.equal(quests.dialogue.page_count(), 2, "complete pages")
	_read_through(quests.dialogue)
	var offer := quests.offer_window
	if not t.check(offer.is_open(), "no turn-in window"):
		return
	t.equal(offer.title_text(), "Complete: A Place to Work", "turn-in title")
	t.equal(offer.accept_label(), "Turn in and claim reward", "turn-in accept label")
	t.equal(offer.decline_label(), "Close", "turn-in close label")
	offer.invoke("accept")
	state = quests.state(PLACE)
	t.equal(state.get("status"), "completed", "status after turning in")
	t.check(bool(state.get("rewards_granted")), "rewards not granted")
	t.equal(run.item_count("wood"), 20, "reward wood")
	t.equal(run.story["learned_recipe_ids"], ["craft-stone-axe", "craft-stone-pickaxe"], "learned recipes")
	t.equal(run.coins(), 50, "coins")
	t.equal(quests.status("stone-tools"), "available", "stone-tools")
	t.equal(quests.status("a-tonic-for-lili"), "available", "a-tonic-for-lili")
	t.equal(events["available"], [{"questId": "stone-tools", "source": "condition"}, {"questId": "a-tonic-for-lili", "source": "condition"}],
		"quest_available")
	if t.equal((events["completed"] as Array).size(), 1, "quest_completed"):
		t.equal(events["completed"][0]["rewards"], QuestCatalog.definition(PLACE)["rewards"], "completed rewards")
	t.check(not offer.is_open() and not t.tree.paused, "the window or the pause stayed")
	t.check(not elder.is_interaction_locked(), "the Elder stayed locked")
	t.check(run.has_talked_to(ELDER_ID), "the turn-in did not record the talk")
	t.equal(quests.marker_for(ELDER_ID), "main-offer", "Elder marker after the turn-in (stone-tools)")
	t.equal(quests.marker_for("lili"), "side-offer", "Lili marker after the turn-in")


func test_place_fact_counts_once(t: TestContext) -> void:
	var quests := _quests(t)
	quests.debug_activate(PLACE, "place-workbench")
	var progressed: Array = []
	quests.quest_progressed.connect(func(payload: Dictionary) -> void: progressed.append(payload))
	quests.handle_event(QuestEvents.FURNITURE_PLACED, WORKBENCH_PLACED)
	quests.handle_event(QuestEvents.FURNITURE_PLACED, WORKBENCH_PLACED)
	t.equal(progressed.size(), 1, "progress events")
	t.equal(quests.state(PLACE).get("consumed_fact_ids"), {"place-workbench": ["p1"]}, "consumed facts")


func test_reward_items_must_fit(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	quests.debug_activate(PLACE, "place-workbench")
	quests.handle_event(QuestEvents.FURNITURE_PLACED, WORKBENCH_PLACED)
	run.add_item("stone", run.item_capacity("stone"))
	t.equal(run.item_capacity("wood"), 0, "room for wood in a full bag")
	var reason := "Could not grant all reward items for quest 'a-place-to-work'."
	t.equal(quests.turn_in(PLACE, ELDER_ID), {"ok": false, "code": "reward-items", "reason": reason}, "turn_in result")
	var offer := quests.offer_window
	offer.open_turn_in(PLACE, ELDER_ID, func() -> void: pass, func() -> void: pass)
	offer.invoke("accept")
	t.check(offer.is_open(), "the window closed on a refusal")
	t.equal(offer.error_text(), reason, "window error")
	offer.close()
	t.equal(quests.status(PLACE), "active", "status after the refusal")
	t.check(bool(quests.view(PLACE).get("ready_to_turn_in")), "no longer ready")
	t.equal(run.story["learned_recipe_ids"], [], "recipes learned on a refusal")
	t.equal(run.item_count("wood"), 0, "wood given on a refusal")


func test_collect_only_in_current_stage(t: TestContext) -> void:
	var quests := _quests(t)
	quests.debug_activate("stone-tools")
	var progressed: Array = []
	quests.quest_progressed.connect(func(payload: Dictionary) -> void: progressed.append(payload))
	if not await _pick_up(t, "level-1-loose-wood-04", Vector2(608.0, 576.0)):
		return
	t.equal(int((quests.state("stone-tools")["progress"] as Dictionary).get("chop-wood", 0)), 0, "chop-wood during craft-tools")
	t.equal(progressed, [], "progress during craft-tools")
	quests.debug_activate("stone-tools", "use-tools")
	if not await _pick_up(t, "level-1-loose-wood-03", Vector2(704.0, 512.0)):
		return
	t.equal(int((quests.state("stone-tools")["progress"] as Dictionary).get("chop-wood", 0)), 10, "chop-wood during use-tools")
	t.equal(progressed, [{"questId": "stone-tools", "stageId": "use-tools", "objectiveId": "chop-wood", "before": 0, "after": 10}],
		"the pile's 10 wood")


func test_kill_counts_kind_only(t: TestContext) -> void:
	var quests := _quests(t)
	quests.debug_activate("worm-trouble", "clear-camp")
	var progressed: Array = []
	quests.quest_progressed.connect(func(payload: Dictionary) -> void: progressed.append(payload))
	quests.handle_event(QuestEvents.ENEMY_DIED, {"enemyId": 1, "areaId": "level-1", "kind": "worm-archer"})
	t.equal(int((quests.state("worm-trouble")["progress"] as Dictionary).get("defeat-worms", 0)), 0, "an archer counted")
	for enemy_id in 3:
		quests.handle_event(QuestEvents.ENEMY_DIED, {"enemyId": 10 + enemy_id, "areaId": "level-1", "kind": "worm-swordsman"})
	t.equal(int((quests.state("worm-trouble")["progress"] as Dictionary).get("defeat-worms", 0)), 3, "three swordsmen")
	t.check(bool(quests.view("worm-trouble").get("ready_to_turn_in")), "worm-trouble not ready")
	var before := progressed.size()
	quests.handle_event(QuestEvents.ENEMY_DIED, {"enemyId": 20, "areaId": "level-1", "kind": "worm-swordsman"})
	t.equal(progressed.size(), before, "a fourth worm progressed")


## A real worm death reaches the quests through EnemyLoot (ordinary enemies only).
func test_enemy_death_reaches_quests(t: TestContext) -> void:
	var quests := _quests(t)
	quests.debug_activate("worm-trouble", "clear-camp")
	var worm := t.spawn_worm(Vector2(200.0, 0.0), true)
	if worm == null:
		return
	worm.reward_requested.emit({"receiverNodeId": "", "rewards": {"coins": 0, "items": []}})
	t.equal(int((quests.state("worm-trouble")["progress"] as Dictionary).get("defeat-worms", 0)), 1, "worm death")


func test_known_boss_fact_on_accept(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	run.world["defeated_boss_ids"] = ["orb-weaver-matron"]
	quests.debug_mark_completed("iron-gear")
	t.equal(quests.status("the-matrons-nest"), "available", "the Matron's nest")
	var coins := run.coins()
	var result := quests.accept("the-matrons-nest", "level-1-spider-giver")
	t.check(bool(result.get("ok")), "accept refused: %s" % [result])
	t.equal(quests.status("the-matrons-nest"), "completed", "completed on accept")
	t.check(run.has_learned_ability("squash-slam"), "Squash Slam not learned")
	t.check(run.has_flag("chapter-2-complete"), "chapter-2-complete not set")
	t.equal(run.coins(), coins + 100, "coins")
	t.equal(quests.status("the-old-workshop"), "available", "the old workshop")
	_close_end_card()


func test_known_facts_skip_later_stages(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	run.world["defeated_boss_ids"] = ["fatty-one-eye"]
	quests.debug_activate("the-one-eyed-guardian")
	quests.handle_event(QuestEvents.CRAFT_COMPLETED, {"recipeId": "craft-stone-spear", "itemId": "stone-spear", "quantity": 1})
	var state := quests.state("the-one-eyed-guardian")
	t.equal(state.get("active_stage_id"), "defeat-fatty", "stage after the spear")
	t.equal((state["progress"] as Dictionary).get("defeat-fatty"), 0, "an earlier defeat counted")
	var camp := _camp(t, "level-1-fatty-one-eye-camp")
	if not t.check(camp != null, "no Fatty camp"):
		return
	camp.boss_defeated.emit({"campId": "level-1-fatty-one-eye-camp", "bossId": "fatty-one-eye"})
	t.equal(quests.state("the-one-eyed-guardian").get("active_stage_id"), "verdant-gate", "stage after the camp's defeat")


func test_guardian_completes_on_gloop_forest_arrival(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	quests.debug_activate("the-one-eyed-guardian", "verdant-gate")
	var coins := run.coins()
	if not t.check(t.main.travel_to("gloop-forest", "west"), "the travel was refused"):
		return
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == "gloop-forest" and t.player() != null, 3000.0, 6000.0)
	if not t.check(arrived, "no arrival in gloop-forest"):
		return
	t.equal(quests.status("the-one-eyed-guardian"), "completed", "the guardian")
	t.equal(run.coins(), coins + 100, "coins")
	t.check(run.has_flag("chapter-1-complete"), "chapter-1-complete not set")
	t.equal(quests.status("beyond-the-verdant-gate"), "available", "beyond the verdant gate")
	t.check("gloop-forest" in (run.world["discovered_areas"] as Array), "gloop-forest not discovered")
	await t.tree.process_frame
	await t.tree.process_frame
	t.equal(_markers(t).kind_for("gloop-ch2-npc-mossy"), "main-offer", "Mossy's marker")


func test_restoration_progresses_forge_quest(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	t.check(run.debug_active_quests.is_empty(), "the debug quest list is not empty")
	quests.debug_activate("rekindle-the-forge")
	run.add_item("stone", 40)
	run.add_item("wood", 20)
	run.add_item("iron-ore", 6)
	var site: Node = null
	for node: Node in t.tree.get_nodes_in_group(RestorationSiteScript.GROUP):
		if str(node.get(&"quest_id")) == "rekindle-the-forge":
			site = node
	if not t.check(site != null, "no forge site"):
		return
	t.check(site.call(&"restore"), "restore did nothing")
	t.check(run.has_flag("forge.restored"), "forge.restored not set")
	var state := quests.state("rekindle-the-forge")
	t.equal(state.get("active_stage_id"), "smelt", "stage after the restore")
	t.equal(state.get("progress"), {"restore-forge": 1, "smelt-charcoal": 0, "smelt-iron-bars": 0}, "progress")
	t.equal((state["consumed_fact_ids"] as Dictionary).get("restore-forge"), ["level-1.level-1-forge"], "consumed facts")


func test_tracker_fresh_run(t: TestContext) -> void:
	await t.steps(2)
	var tracker := _tracker(t)
	if not t.check(tracker != null, "no tracker"):
		return
	var model := tracker.model()
	t.check(tracker.visible, "the tracker is hidden")
	t.equal(model.get("heading"), "QUESTS · 2", "heading")
	t.equal(model.get("quest1Title"), "A Place to Work", "slot 1 title")
	t.equal((model.get("quest1Color") as Color).to_html(false), "ffd277", "slot 1 colour")
	t.equal(model.get("quest1Objectives"), "! Talk to Village Elder Plop", "slot 1 lines")
	t.equal([model.get("quest1OffsetMin"), model.get("quest1OffsetMax")], [Vector2(10, 26), Vector2(-10, 64)], "slot 1 rect")
	t.equal(model.get("quest2Title"), "Slime Basics", "slot 2 title")
	t.equal((model.get("quest2Color") as Color).to_html(false), "d9ecff", "slot 2 colour")
	t.equal(model.get("quest2Objectives"), SLIME_BASICS_LINES, "slot 2 lines")
	t.equal([model.get("quest2OffsetMin"), model.get("quest2OffsetMax")], [Vector2(10, 72), Vector2(-10, 218)], "slot 2 rect")
	t.check(not bool(model.get("quest3Visible")), "slot 3 shows")
	t.equal([model.get("offsetMin"), model.get("offsetMax")], [Vector2(16, 96), Vector2(300, 336)], "card rect")
	t.equal(model.get("hint"), "Click a quest to show the way", "hint")
	t.equal(model.get("bookHint"), "E · Journal tab", "book hint")
	t.equal([tracker.offset_left, tracker.offset_top, tracker.offset_right, tracker.offset_bottom], [16.0, 96.0, 300.0, 336.0], "card offsets")


func test_tracker_order_after_accept(t: TestContext) -> void:
	var quests := _quests(t)
	t.check(bool(quests.accept(PLACE, ELDER_ID).get("ok")), "accept refused")
	await t.steps(1)
	var model := _tracker(t).model()
	t.equal(model.get("quest1Title"), "A Place to Work", "slot 1")
	t.equal(model.get("quest1Objectives"), "• Craft a Workbench (40 wood)", "slot 1 lines")
	t.equal(model.get("quest2Title"), "Slime Basics", "slot 2")


func test_sprint_and_pause_controls(t: TestContext) -> void:
	var quests := _quests(t)
	var progressed: Array = []
	quests.quest_progressed.connect(func(payload: Dictionary) -> void: progressed.append(payload))
	t.press(&"move_right")
	t.press(&"sprint")
	await t.steps(3)
	var state := quests.state("slime-basics")
	t.equal((state["progress"] as Dictionary).get("sprint"), 1, "sprint")
	t.equal((state["consumed_fact_ids"] as Dictionary).get("sprint"), ["sprint"], "sprint fact")
	t.release(&"sprint")
	await t.steps(2)
	t.press(&"sprint")
	await t.steps(2)
	t.release_all()
	var sprint_events := progressed.filter(func(payload: Dictionary) -> bool: return payload["objectiveId"] == "sprint")
	t.equal(sprint_events.size(), 1, "sprint progress events")
	var shell := Services.shell()
	if shell == null:
		t.note("no Shell autoload: the pause objective was not driven")
		return
	if not t.check(shell.open_pause(), "the pause menu did not open"):
		return
	t.equal((quests.state("slime-basics")["progress"] as Dictionary).get("pause"), 1, "pause")
	shell.pause_menu.close()


func test_menu_windows_count_for_the_tutorial(t: TestContext) -> void:
	var quests := _quests(t)
	var windows := t.tree.get_first_node_in_group(&"game_windows")
	if not t.check(windows != null, "no GameWindows"):
		return
	for surface_id: StringName in [&"inventory", &"crafting", &"quest-journal", &"world-map"]:
		windows.window_opened.emit(surface_id)
	t.equal(quests.state("slime-basics")["progress"], {"open-bag": 1, "see-crafting": 1, "read-journal": 1, "open-map": 1,
		"sprint": 0, "pause": 0}, "tutorial progress")


func test_save_round_trip(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	t.check(bool(quests.accept(PLACE, ELDER_ID).get("ok")), "accept refused")
	var before := run.quests.duplicate(true)
	var data := run.serialize()
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if not t.check(parsed is Dictionary, "the save did not parse"):
		return
	t.check(run.install(run._integers(parsed)), "install refused the save")
	t.equal(quests.status(PLACE), "active", "status after the load")
	t.equal(run.quests, before, "records after the round trip")
	t.equal(typeof(quests.state(PLACE).get("accepted_at")), TYPE_INT, "accepted_at type")
	t.equal(typeof(quests.state(PLACE).get("active_stage_id")), TYPE_STRING, "active_stage_id type")
	t.check(run.is_quest_active(PLACE), "RunState lost the active quest")


## Owner decision Q7: a broken record is reset to locked with a warning; the rest survives.
func test_broken_record_resets(t: TestContext) -> void:
	var quests := _quests(t)
	var run := Services.run()
	var data := run.serialize()
	var records: Array = data["quests"]
	for record: Dictionary in records:
		if record["quest_id"] == "slime-basics":
			record["progress"] = {"open-bag": 7}
	records.append({"quest_id": "gather-building-materials", "status": "completed"})
	run.install(data)
	t.equal(quests.status("slime-basics"), "locked", "the broken record")
	t.equal(quests.status(PLACE), "available", "a sound record")
	t.equal(run.quests.size(), 14, "records after the load")


func test_teardown_releases_npc(t: TestContext) -> void:
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var quests := _quests(t)
	_interaction(t).handle_interact()
	if not t.check(quests.dialogue.is_open() and elder.is_interaction_locked(), "no conversation"):
		return
	quests.close_conversations()
	t.check(not elder.is_interaction_locked(), "the Elder stayed locked")
	t.check(not quests.dialogue.is_open() and not quests.offer_window.is_open(), "a window stayed open")
	t.check(not t.world().has_pause_reason(&"modal"), "the modal pause stayed")
	t.check(not t.tree.paused, "the world stayed paused")


func test_toasts_banner_and_stacking(t: TestContext) -> void:
	var quests := _quests(t)
	var toasts: Array = []
	var banners: Array = []
	quests.notifications.toast_shown.connect(func(payload: Dictionary) -> void: toasts.append(payload))
	quests.notifications.banner_shown.connect(func(payload: Dictionary) -> void: banners.append(payload))
	quests.accept(PLACE, ELDER_ID)
	if t.equal(banners.size(), 1, "banners on accept"):
		t.equal(banners[0]["text"], "Chapter 1 — The Clearing", "chapter banner")
		t.equal((banners[0]["color"] as Color).to_html(false), "ffd277", "chapter colour")
	if t.equal(toasts.size(), 1, "toasts on accept"):
		t.equal([toasts[0]["text"], toasts[0]["color"], toasts[0]["big"], toasts[0]["lift"]],
			["Quest accepted: A Place to Work", "green", true, 70.0], "accept toast")
	await t.steps(1)
	quests.handle_event(QuestEvents.CRAFT_COMPLETED, WORKBENCH_CRAFT)
	await t.steps(1)
	quests.handle_event(QuestEvents.FURNITURE_PLACED, WORKBENCH_PLACED)
	await t.steps(1)
	toasts.clear()
	quests.turn_in(PLACE, ELDER_ID)
	var shown: Array = []
	for toast: Dictionary in toasts:
		shown.append([toast["text"], toast["lift"]])
	t.equal(shown, [["QUEST COMPLETE: A Place to Work", 70.0], ["+ 20× Wood", 46.0], ["+ New recipe: Stone Axe", 26.0],
		["+ New recipe: Stone Pickaxe", 6.0], ["New quest available: Stone Tools", 112.0],
		["New quest available: A Tonic for Lili", 134.0]], "completion toasts (Q5: stacked 22 px)")
	banners.clear()
	Services.run().learn_ability("dodge")
	if t.equal(banners.size(), 1, "ability banners"):
		t.equal(banners[0]["text"], "Dodge learned: press 1", "ability banner")
		t.equal((banners[0]["color"] as Color).to_html(false), "9ff0c8", "ability colour")


func test_waypoint_points_at_the_giver(t: TestContext) -> void:
	var elder := await _meet(t, ELDER)
	if elder == null:
		return
	var tracker := _tracker(t)
	var waypoint := t.tree.get_first_node_in_group(QuestWaypointView.GROUP) as QuestWaypointView
	if not t.check(tracker != null and waypoint != null, "no tracker or waypoint"):
		return
	tracker.invoke_track(1)
	t.check(tracker.showing_way(), "the waypoint is off after a click")
	t.equal(tracker.model().get("quest1Title"), "➜ A Place to Work", "pointing title")
	await t.steps(3)
	var target := waypoint.target()
	if t.check(not target.is_empty(), "no waypoint target"):
		t.near_vec(target["position"], elder.get_phaser_position(), 0.01, "waypoint position")
		t.equal(target["label"], "Talk to Village Elder Plop", "waypoint label")
	t.equal(tracker.model().get("hint"), "➜ Follow the gold arrow · click it again to hide", "hint while pointing")
	t.check(waypoint.is_showing_marker(), "no waypoint pin")
	var map_ui := t.tree.get_first_node_in_group(&"map_ui")
	var markers: Variant = map_ui.get(&"markers") if map_ui != null else null
	if markers is Object and (markers as Object).has_method(&"marker"):
		var pin: Dictionary = (markers as Object).call(&"marker", &"quest-waypoint")
		t.check(not pin.is_empty() and (pin["point"] as Vector2).is_equal_approx(elder.get_phaser_position()), "map marker %s" % [pin])
	tracker.invoke_track(1)
	t.check(not tracker.showing_way(), "a second click kept the waypoint")
	t.equal(tracker.model().get("hint"), "Click a quest to show the way", "hint after hiding")
	# `process_frame` fires before the nodes' `_process`: wait for two.
	await t.tree.process_frame
	await t.tree.process_frame
	if markers is Object and (markers as Object).has_method(&"has_marker"):
		t.check(not bool((markers as Object).call(&"has_marker", &"quest-waypoint")), "the map marker stayed")


## Abandon (journal command), the reoffer by the giver straight into the offer window, the
## forbidden abandon of a main quest, and slime-basics' retry that never restarts (spec 2.8 quirk).
func test_abandon_and_reoffer(t: TestContext) -> void:
	var quests := _quests(t)
	quests.debug_mark_completed(PLACE)
	t.check(bool(quests.accept("a-tonic-for-lili", "lili").get("ok")), "accept refused")
	t.equal(quests.abandon(PLACE).get("code"), "invalid-status", "abandoning a completed quest")
	t.equal(quests.abandon("stone-tools").get("code"), "invalid-status", "abandoning an available quest")
	var result := quests.abandon("a-tonic-for-lili")
	t.check(bool(result.get("ok")), "abandon refused: %s" % [result])
	var state := quests.state("a-tonic-for-lili")
	t.equal([state.get("status"), state.get("active_stage_id"), state.get("resume_stage_id")], ["abandoned", "", "brew-tonic"], "abandoned record")
	t.equal(quests.npc_candidate("lili").get("kind"), "reoffer", "Lili's candidate")
	t.equal(quests.marker_for("lili"), "side-offer", "Lili's marker")
	var lili := await _meet(t, "level-1-npc-lili")
	if lili == null:
		return
	var interaction := _interaction(t)
	t.equal(interaction.current().get("priority"), 85, "reoffer priority")
	t.equal(interaction.get_prompt().get_text(), "Right-click: Resume quest with Lili", "reoffer prompt")
	interaction.handle_interact()
	t.check(not quests.dialogue.is_open(), "a reoffer opened the dialogue")
	t.check(quests.offer_window.is_open(), "no offer window for the reoffer")
	t.equal(quests.status("a-tonic-for-lili"), "available", "status after the reoffer")
	quests.offer_window.invoke("accept")
	t.equal(quests.status("a-tonic-for-lili"), "active", "status after accepting again")
	t.check(not lili.is_interaction_locked(), "Lili stayed locked")
	quests.debug_activate("stone-tools")
	t.equal(quests.abandon("stone-tools").get("code"), "mandatory-quest", "abandoning a main quest")
	t.check(bool(quests.abandon("slime-basics").get("ok")), "slime-basics could not be abandoned")
	t.check(bool(quests.retry_abandoned_automatic("slime-basics").get("ok")), "retry refused")
	t.equal(quests.status("slime-basics"), "locked", "slime-basics after the retry (its prerequisite no longer holds)")


## Quests spec 4.6 level-1 targets: the worm camp, Fatty's camp, the exit to gloop-forest, the forge
## ruin and the workshop ruin.
func test_waypoint_targets_on_level_1(t: TestContext) -> void:
	var quests := _quests(t)
	var from := Vector2(640.0, 704.0)
	var cases := [
		["worm-trouble", "clear-camp", Vector2(1130.0, 1514.0)],
		["the-one-eyed-guardian", "defeat-fatty", Vector2(2528.0, 1472.0)],
		["the-one-eyed-guardian", "verdant-gate", Vector2(3552.0, 576.0)],
		["rekindle-the-forge", "", Vector2(1190.0, 1068.0)],
		["the-old-workshop", "", Vector2(640.0, 392.0)],
	]
	for entry: Array in cases:
		quests.debug_activate(entry[0], entry[1])
		var view := quests.view(entry[0])
		var target := QuestWaypoint.resolve(view, from)
		var stage_definition := QuestCatalog.stage(view["definition"], str(view["active_stage_id"]))
		var label := str((QuestCatalog.objectives(stage_definition)[0] as Dictionary)["label"])
		if t.check(not target.is_empty(), "no target for %s" % [entry]):
			t.near_vec(target["position"], entry[2], 0.5, "%s target" % entry[0])
			t.equal(target["label"], label, "%s label" % entry[0])
	quests.debug_mark_completed(PLACE)
	t.check(QuestWaypoint.resolve(quests.view("a-tonic-for-lili"), from).get("label") == "Talk to Lili", "the giver of an offer")


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


func _camp(t: TestContext, camp_id: String) -> BossCampScript:
	for node: Node in t.tree.get_nodes_in_group(BossCampScript.GROUP):
		if node is BossCampScript and (node as BossCampScript).camp_id == camp_id:
			return node
	return null


## The player at CENTRE, the NPC 40 px to its right (standing still, not locked), the interaction
## refreshed. Null when the NPC is missing.
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


## Advances the dialogue until it ends (finished).
static func _read_through(dialogue: DialogueBox) -> void:
	var guard := 40
	while dialogue.is_open() and guard > 0:
		dialogue.advance()
		guard -= 1


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


## Walks the player onto a pile (old position `at`) and waits until it is taken.
func _pick_up(t: TestContext, instance_id: String, at: Vector2) -> bool:
	t.teleport_player(at - Vector2(0.0, 14.56))
	var taken := await t.until(func() -> bool:
		return int(Services.run().collectible_record("level-1", instance_id).get("remaining", 1)) == 0, 500.0)
	return t.check(taken, "%s was not picked up" % instance_id)


static func _close_end_card() -> void:
	var shell := Services.shell()
	if shell != null and shell.end_card.is_open():
		shell.end_card.close()
