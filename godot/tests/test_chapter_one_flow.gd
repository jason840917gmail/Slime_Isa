extends RefCounted
## Slimeshire's beginning through the real systems (docs/godot/specs/quests.md 14): Slime Basics with
## the player's own keys (the bag, a campfire's window, the Journal, the map, the pause menu), and the
## first steps of the main line: Elder Plop's tip about Burr once the prologue is over, young Burr's
## Roll lesson in his house, Fatty's fall reported by his camp (chapter-1-complete; Mossy and Sunny
## leave for the forest), his Pearl taken, and the main quest moving on with each.
## Rewritten 2026-11-20: the Phaser-era chapter quests are retired (A Place to Work, Stone Tools,
## Worm Trouble, A Tonic for Lili, Snack for the Road, The One-Eyed Guardian), and with them their
## tests here (the end-to-end workbench quest, the stone tools by hand, the worm kills, Lili's and the
## fisher's quests, the old chapter-one main line); Lili's tonic lesson is test_main_quest.gd's.
## level-1 is cut into chunk worlds (docs/godot/WORLD_ATLAS.md "Chunk worlds"): the tests play in the
## village's chunk C4 (`level-1-c4`); Fatty's camp stands in his arena (`fatty-lair-r13-fattys-arena`).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestNpcTalk := preload("res://game/quests/quest_npc_talk.gd")

const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const ELDER := "level-1-npc-village-elder-plop"
const ELDER_ID := "village-elder-plop"
const MAIN := "win-back-the-pearls"
## C4's campfire on the plaza meadow (a cook station since 2026-11-20).
const CAMPFIRE := Vector2(952.0, 1424.0)
const BURR_HOUSE := "slimeshire-burr-house"
const YOUNG_BURR := "slimeshire-burr-house-young-burr"
## Fatty's camp stands in his arena, its own world since the Lair is one world per room (2026-10-18).
const FATTY_MAP := "fatty-lair-r13-fattys-arena"
const FATTY_CAMP := "fatty-lair-boss"


## Slime Basics with the player's own keys: E opens the bag, its strip shows the Journal, M opens the
## map, the interact key at a campfire opens its window, Esc pauses; the quest then completes by
## itself.
func test_slime_basics_with_the_keys(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	var coins := run.coins()
	t.tap(&"menu")
	await t.steps(2)
	var menus: Node = t.main.menu_windows
	t.equal(menus.call(&"current_tab"), &"inventory", "E opened the bag")
	menus.call(&"switch_tab", &"journal")
	t.equal(menus.call(&"current_tab"), &"journal", "the Journal tab")
	t.tap(&"menu")
	await t.steps(2)
	t.equal(menus.call(&"current_tab"), &"", "E closed the journal")
	t.tap(&"map")
	await t.steps(3)
	var map_ui: Node = t.tree.get_first_node_in_group(&"map_ui")
	if map_ui != null:
		t.check(bool(map_ui.call(&"is_world_map_open")), "M did not open the world map")
		map_ui.call(&"close_world_map")
		await t.steps(2)
	# The campfire: walk up to it and use it.
	t.teleport_player(CAMPFIRE + Vector2(-70.0, 10.0))
	await t.steps(3)
	t.main.interaction.refresh(null)
	t.tap(&"interact")
	await t.steps(3)
	var crafting: Node = menus.get(&"crafting")
	t.check(bool(crafting.call(&"is_open")), "the interact key at the campfire opened no window")
	if bool(crafting.call(&"is_open")):
		crafting.call(&"close")
	await t.steps(2)
	t.tap(&"pause")
	await t.steps(2)
	var shell := Services.shell()
	if shell != null and shell.is_any_open():
		shell.pause_menu.close()
	await t.steps(2)
	t.equal(quests.call(&"status", "slime-basics"), "completed", "Slime Basics after every control (progress %s)" % [quests.call(&"state", "slime-basics").get("progress")])
	t.equal(run.coins(), coins + 10, "Slime Basics' reward")


## The main line's first steps: Plop's tip sends the slime to Burr's boy (once the prologue is over),
## the boy teaches the Roll, Fatty's camp reports his fall (chapter-1-complete), his Pearl is taken.
func test_plop_sends_the_slime_to_burrs_boy_and_the_main_line_follows(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	var dialogue: Node = t.tree.get_first_node_in_group(&"dialogue_box")
	t.equal(str(QuestNpcTalk.matching_talk(ELDER_ID).get("id", "")), "", "Plop's talk before the prologue is over")
	run.set_flag("prologue.done")
	t.equal(str(quests.call(&"marker_for", ELDER_ID)), "tip", "Plop's marker once the prologue is over")
	await _talk_to(t, ELDER)
	await _read_all(t, dialogue)
	t.check(run.has_heard_tip("plop.burr"), "Plop's tip about Burr was not heard")
	t.equal(str(quests.call(&"marker_for", ELDER_ID)), "", "Plop's marker after his tip")
	# Burr's boy teaches the Roll.
	if not t.check(t.main.travel_to(BURR_HOUSE), "travel to Burr's house was refused"):
		return
	if not t.check(await t.until(func() -> bool:
			return not t.main.is_transitioning() and t.world().map_id() == BURR_HOUSE and t.player() != null, 3000.0, 6000.0),
			"the player did not reach Burr's house"):
		return
	await t.steps(2)
	var boy := _npc(t, YOUNG_BURR)
	if not t.check(boy != null, "no young Burr at home"):
		return
	boy.call(&"configure_wander", {})
	var body := boy.get(&"body") as CharacterBody2D
	body.velocity = Vector2.ZERO
	body.global_position = t.player().get_centre() + NPC_OFFSET - (boy.call(&"get_phaser_position") - body.global_position)
	body.reset_physics_interpolation()
	await t.steps(2)
	t.main.interaction.refresh(null)
	t.tap(&"interact")
	await t.steps(2)
	await _read_all(t, dialogue)
	t.check(run.has_learned_ability("dodge"), "young Burr did not teach the Roll")
	# Fatty's fall, reported by his camp.
	if not t.check(t.main.travel_to(FATTY_MAP, "west"), "the travel to %s was refused" % FATTY_MAP):
		return
	var at_camp := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == FATTY_MAP and t.player() != null, 3000.0, 6000.0)
	if not t.check(at_camp, "the player did not reach %s" % FATTY_MAP):
		return
	var camp: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"boss_camp"):
		if str(node.get(&"camp_id")) == FATTY_CAMP:
			camp = node
	if not t.check(camp != null, "no Fatty camp in %s" % FATTY_MAP):
		return
	camp.emit_signal(&"boss_defeated", {"campId": FATTY_CAMP, "bossId": "fatty-one-eye"})
	await t.steps(2)
	t.check(run.has_flag("chapter-1-complete"), "Fatty's fall did not set chapter-1-complete")
	t.equal(int((quests.call(&"state", MAIN).get("progress") as Dictionary).get("beat-fatty", 0)), 1, "Fatty's fall in the main quest")
	run.set_flag("pearl.fatty-one-eye")
	t.equal(int((quests.call(&"state", MAIN).get("progress") as Dictionary).get("take-pearl-1", 0)), 1, "Fatty's Pearl in the main quest")
	t.equal(str(quests.call(&"state", MAIN).get("active_stage_id")), "pearl-1", "the stage before the Pearl is home")
	var shell := Services.shell()
	if shell != null and shell.end_card.is_open():
		shell.end_card.close()


func _npc(t: TestContext, instance_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == instance_id:
			return node
	return null


## NPC `instance_id` 40 px right of the player at CENTRE, then the interact button.
func _talk_to(t: TestContext, instance_id: String) -> void:
	var npc := _npc(t, instance_id)
	if not t.check(npc != null, "no %s in level-1" % instance_id):
		return
	npc.call(&"configure_wander", {})
	var body := npc.get(&"body") as CharacterBody2D
	body.velocity = Vector2.ZERO
	var offset: Vector2 = npc.call(&"get_phaser_position") - body.global_position
	body.global_position = CENTRE + NPC_OFFSET - offset
	body.reset_physics_interpolation()
	t.teleport_player(CENTRE)
	await t.steps(2)
	t.main.interaction.refresh(null)
	t.tap(&"interact")
	await t.steps(2)


## Reads every page, including the lines said after a lesson's ceremony, until the box stays shut.
static func _read_all(t: TestContext, dialogue: Node) -> void:
	var shut_steps := 0
	var guard := 600
	while shut_steps < 20 and guard > 0 and not t.aborted:
		guard -= 1
		if bool(dialogue.call(&"is_open")):
			shut_steps = 0
			dialogue.call(&"advance")
		else:
			shut_steps += 1
		await t.tree.process_frame
