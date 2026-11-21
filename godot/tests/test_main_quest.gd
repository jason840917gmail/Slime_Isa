extends RefCounted
## The main quest "Win back the Pearls", Pip's Workshop, the NPCs' talks and tips, and young Burr's
## Roll lesson (docs/godot/specs/quests.md 14): the main quest is on from the start (the prologue
## counts as over in a test run) beside Slime Basics, Pip's Workshop waits locked for Pip's mission,
## and the retired chapter quests are gone from the catalogue and from a loaded save; its `story-flag`
## objectives and the bosses' falls carry it through its three Pearls (a Pearl won before its stage
## came up still counts); the journal shows the eight Pearl slots and the Tips; a talk's conditions
## pick what an NPC says and its effects (items, flags, recipes, the tip, an ability) are given once
## its pages end: Burr thanks the slime and sends it to Pip, Pip asks for the Pearls, then (the
## Workshop raised) for the bow rune's makings, carves it from 5 wood, the Matron's thread and the
## smith's crystal and so teaches the Bow (owner, 2026-11-20: Burr no longer teaches it); Pip's
## Workshop starts with his mission and follows the Workshop, the rune and the Forge; an NPC with a
## tip not heard yet shows the gold "!"; the Roll is unknown until young Burr teaches it (a save past
## his dad's cell knows it on load); and a tool run saves to `user://tool-saves`.
## The tests start in level-1's village chunk C4 (`level-1-c4`): Lili (`level-1-npc-lili`) is met at
## (900, 1200), where nothing else is in reach; young Burr stands in his house (`slimeshire-burr-house`).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestService := preload("res://game/quests/quest_service.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")
const QuestNpcTalk := preload("res://game/quests/quest_npc_talk.gd")
const QuestJournalModel := preload("res://game/ui/screens/quest_journal_model.gd")
const DialogueBox := preload("res://game/ui/screens/dialogue_box.gd")
const InteractionController := preload("res://game/interaction/interaction_controller.gd")
const NpcQuestMarkers := preload("res://game/ui/npc_quest_markers.gd")
const RunStateScript := preload("res://game/autoload/run_state.gd")

const MAIN := "win-back-the-pearls"
const PIPS_WORKSHOP := "pips-workshop"
const BASICS := "slime-basics"
const PIP_ID := "red-slime-boy"
## The bow rune's makings Pip takes (his `rune-carve` talk).
const RUNE_MAKINGS := {"matron-thread": 1, "wood": 5, "mine-crystal": 1}
const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const LILI := "level-1-npc-lili"
const LILI_ID := "lili"
const LILI_TIP := "lili.yoi-hideout"
const BURR_HOUSE := "slimeshire-burr-house"
const YOUNG_BURR := "slimeshire-burr-house-young-burr"
const YOUNG_BURR_ID := "young-burr"
const ROLL := "dodge"
## The three Release 1 Pearls in the main quest's order: [pearl id, boss id, stage id].
const PEARLS := [["fatty-one-eye", "fatty-one-eye", "pearl-1"],
	["orb-weaver-matron", "orb-weaver-matron", "pearl-2"],
	["crystal-colossus", "crystal-colossus", "pearl-3"]]


func test_a_new_run_starts_the_main_quest_and_slime_basics_only(t: TestContext) -> void:
	await t.steps(2)
	var run := Services.run()
	var quests := _quests(t)
	var ids: Array[String] = []
	for record: Dictionary in run.quests:
		ids.append(str(record["quest_id"]))
	t.equal(ids, [MAIN, PIPS_WORKSHOP, BASICS], "quest records of a new run")
	t.equal(quests.status(PIPS_WORKSHOP), "locked", "Pip's Workshop before Pip's mission")
	for retired: String in QuestCatalog.RETIRED_IDS:
		t.check(not QuestCatalog.has(retired), "the retired quest %s is still in the catalogue" % retired)
	var main := quests.state(MAIN)
	t.equal(main.get("status"), "active", "the main quest's status")
	t.equal(main.get("active_stage_id"), "pearl-1", "the main quest's stage")
	t.equal(main.get("progress"), {"take-pearl-1": 0, "beat-fatty": 0, "bring-pearl-1-home": 0}, "the first stage's progress")
	t.equal(quests.status(BASICS), "active", "Slime Basics")
	t.equal(str(QuestCatalog.definition(MAIN).get("category", "")), "mandatory", "the main quest's category")


func test_story_flags_and_boss_falls_carry_the_main_quest_through_its_pearls(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	var stage_number := 0
	for pearl: Array in PEARLS:
		stage_number += 1
		var objectives := _objective_ids(str(pearl[2]))
		t.equal(quests.state(MAIN).get("active_stage_id"), pearl[2], "the stage before Pearl %d" % stage_number)
		run.set_flag("pearl.%s" % pearl[0])
		t.equal(int(_progress(quests)[objectives[0]]), 1, "Pearl %d taken (story flag)" % stage_number)
		quests.handle_event(QuestEvents.BOSS_DEFEATED, {"bossId": str(pearl[1])})
		_close_end_card()
		t.equal(int(_progress(quests)[objectives[1]]), 1, "boss %s beaten" % pearl[1])
		t.check(run.has_flag(RunStateScript.boss_flag(str(pearl[1]))), "%s's fall did not set %s" % [pearl[1],
			RunStateScript.boss_flag(str(pearl[1]))])
		t.equal(quests.state(MAIN).get("active_stage_id"), pearl[2], "the stage before Pearl %d is home" % stage_number)
		run.set_flag("pearl.%s.home" % pearl[0])
		await t.steps(1)
		_close_end_card()
	t.equal(quests.status(MAIN), "completed", "the main quest after the third Pearl came home")
	t.check(run.has_flag("chapter-1-complete") and run.has_flag("chapter-2-complete") and run.has_flag("chapter-3-complete"),
		"the chapter flags after the three bosses")


func test_a_pearl_won_before_its_stage_counts_when_the_stage_starts(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	# The Matron's Pearl taken and the Matron beaten while the first stage is still on.
	run.set_flag("pearl.orb-weaver-matron")
	quests.handle_event(QuestEvents.BOSS_DEFEATED, {"bossId": "orb-weaver-matron"})
	t.equal(quests.state(MAIN).get("active_stage_id"), "pearl-1", "the stage while Fatty's Pearl is out")
	run.set_flag("pearl.fatty-one-eye")
	quests.handle_event(QuestEvents.BOSS_DEFEATED, {"bossId": "fatty-one-eye"})
	run.set_flag("pearl.fatty-one-eye.home")
	t.equal(quests.state(MAIN).get("active_stage_id"), "pearl-2", "the stage after Fatty's Pearl came home")
	var progress := _progress(quests)
	t.equal([progress.get("take-pearl-2"), progress.get("beat-matron"), progress.get("bring-pearl-2-home")], [1, 1, 0],
		"the second stage counts the Pearl and the fall that came first")
	# A world build counts them again (nothing twice).
	quests.on_world_built(t.world().map_id())
	t.equal(int(_progress(quests)["take-pearl-2"]), 1, "a world build counted the Pearl twice")


func test_the_journal_shows_the_pearl_slots_and_the_tips(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	var page := _journal(quests, MAIN)
	t.check(page["details"].contains(QuestJournalModel.PEARLS_HEADING % [0, 8]), "no Pearl heading on the main quest's page:\n%s" % page["details"])
	t.equal(page["details"].count(QuestJournalModel.PEARL_LOST), 5, "the slots past Release 1's three Pearls")
	t.check(not _has_row(page, QuestJournalModel.TIPS_ID), "a Tips row before any tip was heard")
	run.set_flag("pearl.fatty-one-eye")
	page = _journal(quests, MAIN)
	t.check(page["details"].contains(QuestJournalModel.MARK_CURRENT + " "), "a won Pearl is not marked on its way home")
	run.set_flag("pearl.fatty-one-eye.home")
	page = _journal(quests, MAIN)
	t.check(page["details"].contains(QuestJournalModel.PEARLS_HEADING % [1, 8]), "one Pearl home is not counted:\n%s" % page["details"])
	t.check(page["details"].contains(QuestJournalModel.MARK_DONE + " "), "the Pearl home is not ticked")
	t.check(run.hear_tip(LILI_TIP), "the tip was not new")
	page = _journal(quests, QuestJournalModel.TIPS_ID)
	t.check(_has_row(page, QuestJournalModel.TIPS_ID), "no Tips row after a tip was heard")
	t.equal(page["details_name"], QuestJournalModel.TIPS_TITLE, "the Tips page's name")
	t.check(page["details"].contains(str(QuestCatalog.tip(LILI_TIP).get("text", "?"))), "the Tips page lacks Lili's tip")
	t.check(page["details"].contains("Lili"), "the Tips page does not name who said it")


func test_retired_quests_leave_a_save_quietly(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	var data := run.serialize()
	(data["quests"] as Array).append({"quest_id": "a-place-to-work", "status": "completed", "definition_version": 1})
	(data["quests"] as Array).append({"quest_id": "tom-in-the-web", "status": "active", "definition_version": 1})
	t.check(run.install(data), "install refused the save")
	t.equal(quests.state("a-place-to-work"), {}, "a retired quest's record after the load")
	var ids: Array[String] = []
	for record: Dictionary in run.quests:
		ids.append(str(record["quest_id"]))
	t.equal(ids, [MAIN, PIPS_WORKSHOP, BASICS], "quest records after loading a save with retired quests")


func test_lili_teaches_the_tonic_and_her_tip_shows_the_gold_mark(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	var lili := await _meet(t, LILI)
	if lili == null:
		return
	t.equal(quests.marker_for(LILI_ID), "tip", "Lili's marker with her tip unheard")
	await t.tree.process_frame
	await t.tree.process_frame
	t.equal(_markers(t).kind_for(LILI), "tip", "Lili's drawn marker")
	t.check(not run.knows_recipe("brew-tonic"), "the tonic is known before Lili's lesson")
	t.check(_interaction(t).handle_interact(), "Lili did not talk")
	var dialogue := quests.dialogue
	if not t.check(dialogue.is_open(), "no dialogue with Lili"):
		return
	t.equal(dialogue.speaker(), "Lili", "speaker")
	t.equal(dialogue.pages(), QuestNpcTalk._talk_pages(QuestCatalog.npc_talks(LILI_ID)[0], "pages"), "Lili's first talk")
	t.check(not run.has_heard_tip(LILI_TIP), "the tip was given before the pages ended")
	await _read_all(t, dialogue)
	t.check(run.knows_recipe("brew-tonic"), "Lili did not teach the tonic")
	t.check(run.has_flag("lili.tonic-taught"), "Lili's lesson flag")
	t.check(run.has_heard_tip(LILI_TIP), "Lili's tip was not heard")
	t.equal(quests.marker_for(LILI_ID), "", "Lili's marker once her tip was heard")
	t.equal(str(QuestNpcTalk.matching_talk(LILI_ID).get("id", "")), "yoi-hideout-again", "Lili's talk after her lesson")
	t.check(not lili.is_interaction_locked(), "Lili stayed locked after her talk")


## Burr thanks the slime and sends it to Pip (no Bow lesson since 2026-11-20); Pip gives his mission,
## asks for the bow rune's makings once the Workshop stands, carves the rune from them (taking them)
## and so teaches the Bow, then talks of the cold Forge until it is lit.
func test_talk_conditions_pick_burrs_and_pips_lines_and_pips_rune_takes_the_makings(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	t.equal(_talk_id("burr"), "thanks", "Burr's first talk")
	t.equal(QuestNpcTalk.talk_tip_id(QuestNpcTalk.matching_talk("burr")), "burr.bow-rune", "the tip of his thanks")
	t.check(bool(quests.talk.apply_talk(QuestNpcTalk.matching_talk("burr")).get("ok")), "his thanks were refused")
	t.check(run.has_flag("burr.thanked") and run.has_heard_tip("burr.bow-rune"), "his thanks set nothing")
	t.equal(_talk_id("burr"), "", "after his thanks, without the Bow: his own lines (unlessFlags)")
	t.equal(quests.marker_for("burr"), "", "Burr's marker after his thanks")
	# Pip's mission (unlessFlags), then his own lines while the Workshop is down.
	t.equal(_talk_id(PIP_ID), "mission", "Pip's first talk")
	t.equal(quests.marker_for(PIP_ID), "", "Pip's marker before his mission (no tip)")
	t.check(bool(quests.talk.apply_talk(QuestNpcTalk.matching_talk(PIP_ID)).get("ok")), "Pip's mission was refused")
	t.check(run.has_flag("pip.mission-given"), "Pip's mission set no flag")
	t.equal(_talk_id(PIP_ID), "", "Pip after his mission, the Workshop down")
	# The Matron's Pearl home raises the Workshop (test_glimmerhill.gd): he asks for the makings.
	run.set_flag("workshop.restored")
	t.equal(_talk_id(PIP_ID), "rune-ask", "the Workshop standing, no makings (ifFlags without ifItems)")
	t.equal(quests.marker_for(PIP_ID), "tip", "Pip's marker with his rune tip unheard")
	t.check(bool(quests.talk.apply_talk(QuestNpcTalk.matching_talk(PIP_ID)).get("ok")), "Pip's ask was refused")
	t.check(run.has_heard_tip("pip.bow-rune"), "Pip's rune tip was not heard")
	var before := {}
	for item_id: String in RUNE_MAKINGS:
		before[item_id] = run.item_count(item_id)
	run.add_item("matron-thread", 1)
	run.add_item("wood", 5)
	t.equal(_talk_id(PIP_ID), "rune-ask", "without the smith's crystal (ifItems)")
	run.add_item("mine-crystal", 1)
	var carving := QuestNpcTalk.matching_talk(PIP_ID)
	t.equal(str(carving.get("id", "")), "rune-carve", "with the makings in the bag (ifItems)")
	var outcome: Dictionary = quests.talk.apply_talk(carving)
	t.check(bool(outcome.get("ok")), "the rune's carving was refused")
	t.check(bool(outcome.get("learned")), "the rune taught nothing new")
	for item_id: String in RUNE_MAKINGS:
		t.equal(run.item_count(item_id), int(before[item_id]), "%s after the carving (takeItems)" % item_id)
	t.check(run.has_learned_ability("bow"), "Pip's rune did not teach the Bow")
	t.check(run.has_flag("pip.bow-rune-made") and run.has_heard_tip("pip.camp-lenses"), "the carving's flag and tip")
	t.equal(_talk_id(PIP_ID), "forge-cold", "Pip with the Bow, the Forge cold (unlessAbilities, ifAbilities)")
	# The Colossus's Pearl home lights the Forge (test_glimmerhill.gd): the Fizzy Brew lesson.
	run.set_flag("forge.restored")
	t.equal(_talk_id(PIP_ID), "forge-lit", "Pip once the Forge is lit")
	t.equal(_talk_id("burr"), "arrow-bells", "Burr with the Bow (ifAbilities)")
	# A boss beaten counts as a flag `boss:<id>`.
	t.check(not QuestNpcTalk.talk_matches({"ifFlags": ["boss:fatty-one-eye"]}, run), "boss:fatty-one-eye holds before his fall")
	run.record_boss_defeated("fatty-one-eye")
	t.check(QuestNpcTalk.talk_matches({"ifFlags": ["boss:fatty-one-eye"]}, run), "boss:fatty-one-eye does not hold after his fall")


## Pip's Workshop starts by itself with Pip's mission and walks its stages on the story's flags: the
## Workshop raised, the bow rune carved, the Forge lit; a flag set before its stage came up counts.
func test_pips_workshop_starts_with_his_mission_and_follows_the_workshop_the_rune_and_the_forge(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	run.set_flag("workshop.restored")
	t.equal(quests.status(PIPS_WORKSHOP), "locked", "Pip's Workshop before his mission, the Workshop raised")
	run.set_flag("pip.mission-given")
	t.equal(quests.status(PIPS_WORKSHOP), "active", "Pip's Workshop after his mission")
	t.equal(quests.state(PIPS_WORKSHOP).get("active_stage_id"), "the-bow-rune",
		"the Workshop raised before the mission counts (its stage done)")
	run.set_flag("pip.bow-rune-made")
	t.equal(quests.state(PIPS_WORKSHOP).get("active_stage_id"), "the-forge", "the stage after the rune")
	run.set_flag("forge.restored")
	t.equal(quests.status(PIPS_WORKSHOP), "completed", "Pip's Workshop once the Forge is lit")
	t.equal(quests.status(MAIN), "active", "the main quest goes on")


## The same quest from its first stage: the Workshop raised after the mission.
func test_pips_workshop_waits_for_the_workshop(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	run.set_flag("pip.mission-given")
	t.equal(quests.state(PIPS_WORKSHOP).get("active_stage_id"), "the-workshop", "the first stage")
	t.equal(quests.state(PIPS_WORKSHOP).get("progress"), {"raise-workshop": 0}, "the first stage's progress")
	run.set_flag("workshop.restored")
	t.equal(quests.state(PIPS_WORKSHOP).get("active_stage_id"), "the-bow-rune", "the stage after the Workshop rose")


func test_a_talk_whose_items_do_not_fit_gives_nothing(t: TestContext) -> void:
	var run := Services.run()
	var quests := _quests(t)
	var before := run.inventory.duplicate(true)
	var entry := {"giveItems": {"wood": 99999}, "setFlags": ["test.talk-gift"], "learnRecipes": ["brew-tonic"],
		"tip": {"id": LILI_TIP, "text": "?"}}
	var outcome: Dictionary = quests.talk.apply_talk(entry)
	t.check(not bool(outcome.get("ok", true)), "a gift that does not fit was given")
	t.check(not run.has_flag("test.talk-gift"), "a refused talk set its flag")
	t.check(not run.knows_recipe("brew-tonic"), "a refused talk taught its recipe")
	t.check(not run.has_heard_tip(LILI_TIP), "a refused talk gave its tip")
	t.equal(run.inventory, before, "the bag after a refused talk")
	var taking := {"takeItems": {"matron-thread": 1}, "setFlags": ["test.talk-take"]}
	t.check(not bool(quests.talk.apply_talk(taking).get("ok", true)), "a talk took an item the bag did not hold")
	t.check(not run.has_flag("test.talk-take"), "a talk that could not take set its flag")


func test_young_burr_teaches_the_roll(t: TestContext) -> void:
	var run := Services.run()
	t.check(not run.has_learned_ability(ROLL), "the Roll is known from birth")
	t.equal(t.player().ability_status(&"dodge").get("unlocked"), false, "the Roll unlocked before its lesson")
	if not await _travel(t, BURR_HOUSE):
		return
	var boy := _npc(t, YOUNG_BURR)
	if not t.check(boy != null, "no young Burr in his house"):
		return
	t.equal(_talk_id(YOUNG_BURR_ID), "roll-lesson", "young Burr's talk before the Roll")
	var quests := _quests(t)
	t.equal(quests.marker_for(YOUNG_BURR_ID), "tip", "young Burr's marker before his lesson")
	await _meet_where_the_player_is(t, boy)
	t.check(_interaction(t).handle_interact(), "young Burr did not talk")
	await _read_all(t, quests.dialogue)
	t.check(run.has_learned_ability(ROLL), "young Burr did not teach the Roll")
	t.check(run.has_heard_tip("young-burr.planks"), "young Burr's tip")
	t.equal(t.player().ability_status(&"dodge").get("unlocked"), true, "the Roll after its lesson")
	t.equal(_talk_id(YOUNG_BURR_ID), "waiting", "young Burr's talk after the lesson")
	t.equal(quests.marker_for(YOUNG_BURR_ID), "", "young Burr's marker after the lesson")
	# A real lesson is saved (not lent for the session).
	var data := run.serialize()
	t.check(ROLL in (data["story"]["learned_ability_ids"] as Array), "the Roll is not in the save")


func test_a_save_past_burrs_cell_knows_the_roll_on_load(t: TestContext) -> void:
	var run := Services.run()
	var cases := [[[], false], [["fatty-lair.burr-freed"], true], [["pearl.fatty-one-eye"], true],
		[["fatty-lair.burr-outside-not-a-pearl"], false]]
	for case: Array in cases:
		var data := run.serialize()
		var story: Dictionary = data["story"]
		story["learned_ability_ids"] = []
		story["world_flags"] = (case[0] as Array).duplicate()
		t.check(run.install(data), "install refused the save")
		t.equal(run.has_learned_ability(ROLL), case[1], "the Roll after loading a save with flags %s" % [case[0]])


func test_tool_runs_save_apart_from_the_players_slots(t: TestContext) -> void:
	t.check(RunStateScript.is_tool_script("res://tools/render_belt.gd"), "a render tool is not a tool run")
	t.check(RunStateScript.is_tool_script("res://tools/bake_elevation.gd"), "the elevation bake is not a tool run")
	t.check(not RunStateScript.is_tool_script("res://tests/run_tests.gd"), "the test runner counts as a tool run")
	t.check(not RunStateScript.is_tool_script(""), "the game (no main loop script) counts as a tool run")
	t.equal(RunStateScript.save_root_for("res://tools/render_glimmerhill.gd"), RunStateScript.TOOL_SAVE_ROOT, "a tool run's saves")
	t.equal(RunStateScript.save_root_for(""), RunStateScript.PLAYER_SAVE_ROOT, "the game's saves")
	t.equal(RunStateScript.TOOL_SAVE_ROOT, "user://tool-saves", "the tool runs' folder")
	t.check(not RunStateScript._running_a_tool(), "the test runner is taken for a tool run")


# --- helpers ---------------------------------------------------------------------------------------

func _quests(t: TestContext) -> QuestService:
	return t.tree.get_first_node_in_group(&"quests") as QuestService


func _interaction(t: TestContext) -> InteractionController:
	return t.tree.get_first_node_in_group(&"interaction") as InteractionController


func _markers(t: TestContext) -> NpcQuestMarkers:
	return t.tree.get_first_node_in_group(NpcQuestMarkers.GROUP) as NpcQuestMarkers


func _npc(t: TestContext, instance_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == instance_id:
			return node
	return null


## The id of the talk `npc_id` would give now ("" when none matches).
static func _talk_id(npc_id: String) -> String:
	return str(QuestNpcTalk.matching_talk(npc_id).get("id", ""))


## The objective ids of a main-quest stage, in order.
static func _objective_ids(stage_id: String) -> Array[String]:
	var out: Array[String] = []
	for objective: Dictionary in QuestCatalog.objectives(QuestCatalog.stage(QuestCatalog.definition(MAIN), stage_id)):
		out.append(str(objective["id"]))
	return out


static func _progress(quests: QuestService) -> Dictionary:
	return quests.state(MAIN).get("progress", {})


## The journal's model with `selected_id` selected (as the journal window builds it).
static func _journal(quests: QuestService, selected_id: String) -> Dictionary:
	var run := Services.run()
	return QuestJournalModel.snapshot(quests.list(), selected_id, "", {"tips": quests.heard_tips(),
		"has_flag": run.has_flag})


static func _has_row(page: Dictionary, row_id: String) -> bool:
	for row: Dictionary in page["rows"]:
		if str(row["id"]) == row_id:
			return true
	return false


## Moves the NPC beside the player at CENTRE, still, and refreshes the interaction.
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


## Moves the NPC beside the player where it stands (a room), still, and refreshes the interaction.
func _meet_where_the_player_is(t: TestContext, npc: Node) -> void:
	npc.call(&"configure_wander", {})
	var body := npc.get(&"body") as CharacterBody2D
	body.velocity = Vector2.ZERO
	var offset: Vector2 = npc.call(&"get_phaser_position") - body.global_position
	body.global_position = t.player().get_centre() + NPC_OFFSET - offset
	body.reset_physics_interpolation()
	await t.steps(1)
	_interaction(t).refresh(null)


## Reads every page the NPC says, including the lines said after a lesson's ceremony, until the box
## stays shut.
static func _read_all(t: TestContext, dialogue: DialogueBox) -> void:
	var shut_steps := 0
	var guard := 600
	while shut_steps < 20 and guard > 0 and not t.aborted:
		guard -= 1
		if dialogue.is_open():
			shut_steps = 0
			dialogue.advance()
		else:
			shut_steps += 1
		await t.tree.process_frame


static func _close_end_card() -> void:
	var shell := Services.shell()
	if shell != null and shell.end_card.is_open():
		shell.end_card.close()


## Travels to `map` (its spawn); false when it did not arrive.
static func _travel(t: TestContext, map: String) -> bool:
	if not t.check(t.main.travel_to(map), "travel to %s was refused" % map):
		return false
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == map and t.player() != null, 3000.0, 6000.0)
	if not t.check(arrived, "the player did not reach %s" % map):
		return false
	await t.steps(2)
	return true
