extends RefCounted
## "A Place to Work" from start to finish through the real systems (no debug helpers): the Elder's
## offer through the dialogue box and the offer window, wood picked up from the clearing's piles,
## a Workbench crafted from the Crafting tab, placed with the ghost, the quest turned in for its
## reward, and the stone axe it teaches crafted at the placed bench and put in hand.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")

const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const ELDER := "level-1-npc-village-elder-plop"
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
	var npc: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == ELDER:
			npc = node
	if not t.check(npc != null, "no Elder in level-1"):
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
