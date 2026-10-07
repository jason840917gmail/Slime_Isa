extends RefCounted
## "A Place to Work" from start to finish through the real systems (no debug helpers): the Elder's
## offer through the dialogue box and the offer window, wood picked up from the clearing's piles,
## a Workbench crafted from the Crafting tab, placed with the ghost, the quest turned in for its
## reward, and the stone axe it teaches crafted at the placed bench and put in hand.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const ELDER := "level-1-npc-village-elder-plop"
const LILI := "level-1-npc-lili"
const FISHER := "level-1-npc-fisherman-slime"
const SPIDER_GIVER := "level-1-npc-mossy-scout"
const PLACE := "a-place-to-work"
## The clearing's loose wood piles (10 each).
const WOOD_PILES := {"level-1-loose-wood-03": Vector2(704.0, 512.0), "level-1-loose-wood-04": Vector2(608.0, 576.0)}


func test_a_place_to_work_end_to_end(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	# 1. The Elder offers the quest; read the lines and accept.
	await _talk_to_elder(t)
	var dialogue: Node = t.tree.get_first_node_in_group(&"dialogue_box")
	var offer: Node = t.tree.get_first_node_in_group(&"quest_offer_window")
	if not t.check(dialogue != null and bool(dialogue.call(&"is_open")), "the Elder did not talk"):
		return
	_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")), "no offer window after the Elder's lines"):
		return
	offer.call(&"invoke", "accept")
	t.equal(quests.call(&"status", PLACE), "active", "the quest after accepting")
	# 2. Wood: the clearing's two piles (20), the rest as if chopped elsewhere.
	for instance_id: String in WOOD_PILES:
		t.teleport_player(WOOD_PILES[instance_id] - Vector2(0.0, 14.56))
		await t.until(func() -> bool: return int(run.collectible_record("level-1", instance_id).get("remaining", 1)) == 0, 500.0)
	t.check(run.item_count("wood") >= 20, "the piles gave %d wood" % run.item_count("wood"))
	run.add_item("wood", 40 - run.item_count("wood"))
	# 3. Craft the Workbench from the Crafting tab: the window closes and placement starts.
	t.teleport_player(Vector2(640.0, 704.0))
	await t.steps(2)
	var menus: Node = t.main.menu_windows
	t.check(bool(menus.call(&"open_crafting")), "the Crafting tab did not open")
	var crafting: Node = menus.get(&"crafting")
	crafting.call(&"select_recipe", 0)
	crafting.call(&"craft")
	await t.steps(2)
	var placement: Node = t.tree.get_first_node_in_group(&"furniture_placement")
	t.check(bool(placement.call(&"is_active")), "crafting the bench did not start placement")
	t.equal(str(quests.call(&"state", PLACE).get("active_stage_id")), "place-workbench", "stage after crafting")
	# 4. Place it near the spawn.
	placement.set(&"aim_override", Vector2(700.0, 650.0))
	await t.steps(2)
	t.tap(&"attack")
	await t.steps(3)
	t.equal(run.placed_furniture("level-1").size(), 1, "benches placed")
	t.check(bool(quests.call(&"view", PLACE).get("ready_to_turn_in", false)), "the quest is not ready to turn in")
	# 5. Back to the Elder: the turn-in window gives the reward.
	await _talk_to_elder(t)
	if dialogue.call(&"is_open"):
		_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")), "no turn-in window"):
		return
	offer.call(&"invoke", "accept")
	t.equal(quests.call(&"status", PLACE), "completed", "the quest after turning in")
	t.check(run.knows_recipe("craft-stone-axe"), "the stone axe recipe was not taught")
	t.equal(run.item_count("wood"), 20, "the reward's wood")
	# 6. The stone axe at the placed bench: onto the belt (the sword keeps the hand).
	run.add_item("wood", 10)
	run.add_item("stone", 10)
	t.teleport_player(Vector2(704.0, 700.0))
	await t.steps(2)
	t.tap(&"interact")
	await t.steps(3)
	if not t.check(bool(crafting.call(&"is_open")), "the placed bench did not open the crafting window"):
		return
	var ids: Array[String] = []
	for recipe: Dictionary in RecipeCatalog.recipes_at(crafting.call(&"site")):
		ids.append(str(recipe["id"]))
	crafting.call(&"select_recipe", ids.find("craft-stone-axe"))
	crafting.call(&"craft")
	t.equal(run.item_count("stone-axe"), 1, "stone axes after crafting")
	t.check("stone-axe" in run.weapon_slots(), "the stone axe is not on the belt: %s" % [run.weapon_slots()])
	crafting.call(&"close")


## The Elder 40 px right of the player at CENTRE, then the interact button.
func _talk_to_elder(t: TestContext) -> void:
	await _talk_to(t, ELDER)


## NPC `instance_id` 40 px right of the player at CENTRE, then the interact button.
func _talk_to(t: TestContext, instance_id: String) -> void:
	var npc: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == instance_id:
			npc = node
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


static func _read_through(dialogue: Node) -> void:
	var guard := 40
	while bool(dialogue.call(&"is_open")) and guard > 0:
		dialogue.call(&"advance")
		guard -= 1

## Stone Tools' second stage through play: the belt switch by the mouse wheel counts, and wood
## from a tree felled with the crafted axe counts once it is picked up.
func test_stone_tools_by_hand(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	quests.call(&"debug_activate", "stone-tools")
	run.learn_recipes(["craft-stone-axe", "craft-stone-pickaxe"])
	run.add_item("wood", 20)
	run.add_item("stone", 20)
	t.teleport_player(Vector2(640.0, 704.0))
	await t.steps(2)
	var menus: Node = t.main.menu_windows
	t.check(bool(menus.call(&"open_station", {"station": "workbench", "tier": 1})), "the workbench window did not open")
	var crafting: Node = menus.get(&"crafting")
	var ids: Array[String] = []
	for recipe: Dictionary in RecipeCatalog.recipes_at(crafting.call(&"site")):
		ids.append(str(recipe["id"]))
	for recipe_id: String in ["craft-stone-axe", "craft-stone-pickaxe"]:
		crafting.call(&"select_recipe", ids.find(recipe_id))
		crafting.call(&"craft")
	crafting.call(&"close")
	await t.steps(2)
	t.equal(str(quests.call(&"state", "stone-tools").get("active_stage_id")), "use-tools", "stage after crafting both tools")
	t.equal(run.weapon_slots(), ["basic-sword", "stone-axe", "stone-pickaxe", null], "belt after crafting")
	# The wheel: one notch down takes the axe.
	t.tap(&"weapon_next")
	await t.steps(3)
	t.equal(run.equipped_weapon_id(), "stone-axe", "hand after one wheel notch")
	t.equal(int((quests.call(&"state", "stone-tools").get("progress") as Dictionary).get("switch-tools", 0)), 1, "switch-tools")
	# Fell the grove tree with the axe and pick its wood up.
	var tree_base := Vector2(527.25, 1254.95)
	t.teleport_player(tree_base + Vector2(-60.0, -30.0))
	t.player().face(Vector2.RIGHT)
	var felled := false
	for swing in 6:
		t.tap(&"attack")
		await t.sim_wait(950.0)
		if run.resource_record("level-1", "level-1-tree-004").get("stage", "node") != "node":
			felled = true
			break
	if not t.check(felled, "the axe did not fell level-1-tree-004"):
		return
	await t.sim_wait(900.0)
	var before := run.item_count("wood")
	for node: Node in t.tree.get_nodes_in_group(&"collectible"):
		if str(node.get(&"source_resource_instance_id")) != "level-1-tree-004":
			continue
		var pile := node.get_parent() as Node2D
		t.teleport_player(pile.global_position - Vector2(0.0, 14.56))
		await t.steps(3)
	var gained := run.item_count("wood") - before
	t.check(gained > 0, "no wood picked up from the felled tree")
	t.equal(int((quests.call(&"state", "stone-tools").get("progress") as Dictionary).get("chop-wood", 0)), mini(gained, 20), "chop-wood after picking the piles up")

## Worm Trouble's camp stage: three worm swordsmen defeated in the world count, through the
## enemy's death, its reward and the quest event.
func test_worm_trouble_kills_count(t: TestContext) -> void:
	var quests: Node = t.main.quests
	quests.call(&"debug_activate", "worm-trouble", "clear-camp")
	t.teleport_player(Vector2(900.0, 1200.0))
	await t.steps(2)
	for index in 3:
		var worm := t.spawn_worm(Vector2(160.0 + 60.0 * index, 0.0), true)
		if not t.check(worm != null, "no worm"):
			return
		await t.steps(1)
		_kill(t, worm.damage_area)
		await t.steps(2)
	t.equal(int((quests.call(&"state", "worm-trouble").get("progress") as Dictionary).get("defeat-worms", 0)), 3, "worms counted")
	t.check(bool(quests.call(&"view", "worm-trouble").get("ready_to_turn_in", false)), "Worm Trouble is not ready to turn in")


## One big router hit (a stand-in activation), enough to defeat any ordinary enemy.
func _kill(t: TestContext, target_area: Area2D) -> void:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": target_area,
		"weapon_id": "test-blade", "weapon_tags": ["weapon"], "damage_types": ["physical"], "base_damage": 999.0,
		"effects": [], "impact": {"position": target_area.global_position, "knock": Vector2.RIGHT}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()


## A Tonic for Lili, then Snack for the Road (from the fisher slime): each is offered after the one
## before, the tonic and the basket are made in the Crafting tab, and the giver takes them back
## through the turn-in window.
func test_lili_tonic_and_snack(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	quests.call(&"debug_mark_completed", PLACE)
	t.equal(quests.call(&"status", "a-tonic-for-lili"), "available", "the tonic quest after A Place to Work")
	var dialogue: Node = t.tree.get_first_node_in_group(&"dialogue_box")
	var offer: Node = t.tree.get_first_node_in_group(&"quest_offer_window")
	for step: Array in [["a-tonic-for-lili", 0, {"purple-berry-mat": 3}, LILI], ["snack-for-the-road", 1, {"purple-berry-mat": 2, "wood": 5}, FISHER]]:
		var quest_id: String = step[0]
		var giver: String = step[3]
		await _talk_to(t, giver)
		_read_through(dialogue)
		if not t.check(bool(offer.call(&"is_open")), "%s offered no %s" % [giver, quest_id]):
			return
		offer.call(&"invoke", "accept")
		t.equal(quests.call(&"status", quest_id), "active", "%s after accepting" % quest_id)
		for item_id: String in step[2]:
			run.add_item(item_id, int(step[2][item_id]))
		var menus: Node = t.main.menu_windows
		menus.call(&"open_crafting")
		var crafting: Node = menus.get(&"crafting")
		crafting.call(&"select_recipe", 1 + int(step[1]))
		crafting.call(&"craft")
		crafting.call(&"close")
		t.check(bool(quests.call(&"view", quest_id).get("ready_to_turn_in", false)), "%s is not ready after crafting" % quest_id)
		await _talk_to(t, giver)
		_read_through(dialogue)
		if not t.check(bool(offer.call(&"is_open")), "no turn-in window for %s" % quest_id):
			return
		offer.call(&"invoke", "accept")
		t.equal(quests.call(&"status", quest_id), "completed", "%s after turning in" % quest_id)


## Slime Basics with the player's own keys: E opens the bag, its tabs show Crafting and the
## Journal, M opens the map, Shift sprints, Esc pauses; the quest then completes by itself.
func test_slime_basics_with_the_keys(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	var coins := run.coins()
	t.tap(&"menu")
	await t.steps(2)
	var menus: Node = t.main.menu_windows
	t.equal(menus.call(&"current_tab"), &"inventory", "E opened the bag")
	menus.call(&"switch_tab", &"crafting")
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
	t.press(&"move_right")
	t.press(&"sprint")
	await t.steps(3)
	t.release_all()
	await t.steps(2)
	t.tap(&"pause")
	await t.steps(2)
	var shell := Services.shell()
	if shell != null and shell.is_any_open():
		shell.pause_menu.close()
	await t.steps(2)
	t.equal(quests.call(&"status", "slime-basics"), "completed", "Slime Basics after every control (progress %s)" % [quests.call(&"state", "slime-basics").get("progress")])
	t.equal(run.coins(), coins + 10, "Slime Basics' reward")


## Chapter 1's main line in order, every quest offered by its real giver once the one before is
## turned in (no debug_activate): A Place to Work, Stone Tools, Worm Trouble, The One-Eyed Guardian,
## ending with chapter-1-complete on arrival in gloop-forest. Crafting, placing, switching tools,
## killing worms and travelling are real; the slow harvest pickups (covered by
## test_stone_tools_by_hand) and Fatty's defeat (covered by the boss tests) are sent as their events.
func test_chapter_one_main_line(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	var menus: Node = t.main.menu_windows
	var crafting: Node = menus.get(&"crafting")
	var dialogue: Node = t.tree.get_first_node_in_group(&"dialogue_box")
	var offer: Node = t.tree.get_first_node_in_group(&"quest_offer_window")
	# A Place to Work.
	if not await _accept_from(t, ELDER, "a-place-to-work", dialogue, offer):
		return
	run.add_item("wood", 40)
	t.teleport_player(Vector2(640.0, 704.0))
	await t.steps(2)
	menus.call(&"open_crafting")
	crafting.call(&"select_recipe", 0)
	crafting.call(&"craft")
	await t.steps(2)
	var placement: Node = t.tree.get_first_node_in_group(&"furniture_placement")
	placement.set(&"aim_override", Vector2(700.0, 650.0))
	await t.steps(2)
	t.tap(&"attack")
	await t.steps(3)
	if not await _turn_in_to(t, ELDER, "a-place-to-work", dialogue, offer):
		return
	# Stone Tools: the tools at the placed bench, a belt switch, then 20 wood and 20 stone picked up.
	if not await _accept_from(t, ELDER, "stone-tools", dialogue, offer):
		return
	run.add_item("wood", 20)
	run.add_item("stone", 20)
	await _craft_at_bench(t, ["craft-stone-axe", "craft-stone-pickaxe"])
	t.tap(&"weapon_next")
	await t.steps(3)
	for item_id: String in ["wood", "stone"]:
		QuestEvents.emit(QuestEvents.COLLECTIBLE_COLLECTED, {"mapId": "level-1", "instanceId": "stand-in-" + item_id,
			"objectId": "collectible.%s-pile" % item_id, "itemId": item_id, "quantity": 20})
	if not await _turn_in_to(t, ELDER, "stone-tools", dialogue, offer):
		return
	t.check(run.has_learned_ability("dodge"), "Stone Tools did not teach the dodge")
	# Worm Trouble: the spider-giver, a wooden spear, three worm swordsmen.
	if not await _accept_from(t, SPIDER_GIVER, "worm-trouble", dialogue, offer):
		return
	run.add_item("wood", 20)
	await _craft_at_bench(t, ["craft-wooden-spear"])
	t.teleport_player(Vector2(900.0, 1200.0))
	await t.steps(2)
	for index in 3:
		var worm := t.spawn_worm(Vector2(160.0 + 60.0 * index, 0.0), true)
		await t.steps(1)
		_kill(t, worm.damage_area)
		await t.steps(2)
	if not await _turn_in_to(t, SPIDER_GIVER, "worm-trouble", dialogue, offer):
		return
	t.check(run.has_learned_ability("jump"), "Worm Trouble did not teach the jump")
	# The One-Eyed Guardian: a stone spear, Fatty's camp reports his defeat, then the Verdant Gate.
	if not await _accept_from(t, ELDER, "the-one-eyed-guardian", dialogue, offer):
		return
	run.add_item("wood", 20)
	run.add_item("stone", 20)
	await _craft_at_bench(t, ["craft-stone-spear"])
	var camp: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"boss_camp"):
		if str(node.get(&"camp_id")) == "level-1-fatty-one-eye-camp":
			camp = node
	if not t.check(camp != null, "no Fatty camp in level-1"):
		return
	camp.emit_signal(&"boss_defeated", {"campId": "level-1-fatty-one-eye-camp", "bossId": "fatty-one-eye"})
	t.equal(str(quests.call(&"state", "the-one-eyed-guardian").get("active_stage_id")), "verdant-gate", "the guardian's last stage")
	t.check(bool(t.main.travel_to("gloop-forest", "west")), "the travel to gloop-forest was refused")
	await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == "gloop-forest" and t.player() != null, 3000.0, 6000.0)
	t.equal(quests.call(&"status", "the-one-eyed-guardian"), "completed", "The One-Eyed Guardian")
	t.check(run.has_flag("chapter-1-complete"), "chapter-1-complete is not set")
	t.equal(quests.call(&"status", "beyond-the-verdant-gate"), "available", "chapter 2's first quest")
	var shell := Services.shell()
	if shell != null and shell.end_card.is_open():
		shell.end_card.close()


## Talks to the giver, reads the lines and accepts `quest_id`. False (with a failure) when the
## offer did not come.
func _accept_from(t: TestContext, instance_id: String, quest_id: String, dialogue: Node, offer: Node) -> bool:
	await _talk_to(t, instance_id)
	_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")) and str(offer.call(&"title_text")) == str(t.main.quests.call(&"view", quest_id).get("definition", {}).get("title", "")),
			"%s did not offer %s (window '%s')" % [instance_id, quest_id, offer.call(&"title_text")]):
		return false
	offer.call(&"invoke", "accept")
	return t.check(t.main.quests.call(&"status", quest_id) == "active", "%s was not accepted" % quest_id)


## Talks to the giver and turns `quest_id` in. False (with a failure) when it did not complete.
func _turn_in_to(t: TestContext, instance_id: String, quest_id: String, dialogue: Node, offer: Node) -> bool:
	await _talk_to(t, instance_id)
	_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")), "no turn-in window for %s" % quest_id):
		return false
	offer.call(&"invoke", "accept")
	return t.check(t.main.quests.call(&"status", quest_id) == "completed", "%s was not completed" % quest_id)


## Crafts `recipe_ids` in order at a workbench site.
func _craft_at_bench(t: TestContext, recipe_ids: Array) -> void:
	var menus: Node = t.main.menu_windows
	menus.call(&"open_station", {"station": "workbench", "tier": 1})
	var crafting: Node = menus.get(&"crafting")
	var ids: Array[String] = []
	for recipe: Dictionary in RecipeCatalog.recipes_at(crafting.call(&"site")):
		ids.append(str(recipe["id"]))
	for recipe_id: Variant in recipe_ids:
		crafting.call(&"select_recipe", ids.find(str(recipe_id)))
		crafting.call(&"craft")
		t.check(Services.run().item_count(str(RecipeCatalog.find(str(recipe_id))["output"]["itemId"])) > 0, "%s was not crafted" % recipe_id)
	crafting.call(&"close")
	await t.steps(2)
