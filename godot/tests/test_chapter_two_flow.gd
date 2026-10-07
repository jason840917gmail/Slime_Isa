extends RefCounted
## Chapter 2's forge line through play: Pip offers Rekindle the Forge, the forge ruin is restored
## with the interact button (its story variant brings the Forge station), charcoal and iron bars
## are smelted at the Forge, Pip takes the quest back and teaches the iron spear, and the Elder's
## Iron Gear is finished by crafting it at a workbench.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")

const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const PIP := "level-1-npc-red-slime-boy"
const ELDER := "level-1-npc-village-elder-plop"


func test_rekindle_the_forge_and_iron_gear(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	# The main line up to A Harder Pick is done (the Elder would offer A Place to Work first).
	for quest_id: String in ["a-place-to-work", "stone-tools", "worm-trouble", "the-one-eyed-guardian", "beyond-the-verdant-gate", "a-harder-pick"]:
		quests.call(&"debug_mark_completed", quest_id)
	t.equal(quests.call(&"status", "rekindle-the-forge"), "available", "the forge quest after A Harder Pick")
	var dialogue: Node = t.tree.get_first_node_in_group(&"dialogue_box")
	var offer: Node = t.tree.get_first_node_in_group(&"quest_offer_window")
	# Pip's offer.
	await _talk_to(t, PIP)
	_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")), "Pip offered nothing"):
		return
	offer.call(&"invoke", "accept")
	# Restore the forge ruin with the interact button.
	run.add_item("stone", 40)
	run.add_item("wood", 20)
	run.add_item("iron-ore", 6)
	var site: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"restoration_site"):
		if str(node.get(&"quest_id")) == "rekindle-the-forge":
			site = node
	if not t.check(site != null, "no forge ruin"):
		return
	t.teleport_player(site.call(&"origin") as Vector2 + Vector2(0.0, 40.0))
	await t.steps(2)
	t.main.interaction.refresh(null)
	t.tap(&"interact")
	await t.steps(3)
	t.check(run.has_flag("forge.restored"), "the interact button did not restore the forge")
	t.equal(str(quests.call(&"state", "rekindle-the-forge").get("active_stage_id")), "smelt", "stage after the restore")
	# Smelt at the Forge: 2 charcoal (one craft gives 2), then 3 iron bars.
	await t.steps(3)
	var forge: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"crafting_station"):
		if str(node.get(&"recipe_context")) == "forge" and node.is_inside_tree():
			forge = node
	if not t.check(forge != null, "the restored Forge is no crafting station"):
		return
	run.add_item("wood", 5)
	run.add_item("iron-ore", 6)
	var menus: Node = t.main.menu_windows
	t.check(bool(menus.call(&"open_station", forge.call(&"site"))), "the Forge window did not open")
	var crafting: Node = menus.get(&"crafting")
	crafting.call(&"select_recipe", 0)
	crafting.call(&"craft")
	t.equal(run.item_count("charcoal"), 2, "charcoal after one smelt")
	for i in 2:
		crafting.call(&"select_recipe", 1)
		crafting.call(&"craft")
	run.add_item("charcoal", 1)
	run.add_item("iron-ore", 2)
	crafting.call(&"select_recipe", 1)
	crafting.call(&"craft")
	crafting.call(&"close")
	t.equal(run.item_count("iron-bar"), 3, "iron bars smelted")
	t.check(bool(quests.call(&"view", "rekindle-the-forge").get("ready_to_turn_in", false)), "the forge quest is not ready")
	# Back to Pip for the reward (the iron spear recipe).
	await _talk_to(t, PIP)
	_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")), "no turn-in window at Pip"):
		return
	offer.call(&"invoke", "accept")
	t.equal(quests.call(&"status", "rekindle-the-forge"), "completed", "the forge quest after turning in")
	t.check(run.knows_recipe("craft-iron-spear"), "the iron spear recipe was not taught")
	# The Elder's Iron Gear: craft the iron spear at a workbench, turn it in.
	await _talk_to(t, ELDER)
	_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")), "the Elder offered no Iron Gear"):
		return
	offer.call(&"invoke", "accept")
	# The spear takes 10 wood and 4 iron bars (3 were smelted for Pip).
	run.add_item("wood", 10)
	run.add_item("iron-bar", 1)
	t.check(bool(menus.call(&"open_station", {"station": "workbench", "tier": 1})), "the workbench window did not open")
	var ids: Array[String] = []
	for recipe: Dictionary in RecipeCatalog.recipes_at(crafting.call(&"site")):
		ids.append(str(recipe["id"]))
	crafting.call(&"select_recipe", ids.find("craft-iron-spear"))
	crafting.call(&"craft")
	crafting.call(&"close")
	t.equal(run.item_count("iron-spear"), 1, "iron spears")
	await _talk_to(t, ELDER)
	_read_through(dialogue)
	if not t.check(bool(offer.call(&"is_open")), "no turn-in window at the Elder"):
		return
	offer.call(&"invoke", "accept")
	t.equal(quests.call(&"status", "iron-gear"), "completed", "Iron Gear after turning in")
	t.equal(quests.call(&"status", "the-matrons-nest"), "available", "the Matron's nest after Iron Gear")


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
