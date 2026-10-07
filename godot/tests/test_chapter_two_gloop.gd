extends RefCounted
## Chapter 2 in gloop-forest through play: A Harder Pick (the reinforced pickaxe crafted at the
## workbench, put in hand, iron ore mined from gloop-forest's iron nodes and picked up) and Beyond
## the Verdant Gate (orb weavers defeated, their weaver fangs picked up).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")

const MAP_ID := "gloop-forest"
const IRON_NODES: Array[String] = ["gloop-iron-1", "gloop-iron-2", "gloop-iron-3"]


func test_a_harder_pick_mines_iron(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	quests.call(&"debug_activate", "a-harder-pick")
	run.learn_recipes(["craft-reinforced-pickaxe"])
	run.add_item("wood", 10)
	run.add_item("stone", 15)
	run.add_item("weaver-fang", 3)
	var menus: Node = t.main.menu_windows
	t.check(bool(menus.call(&"open_station", {"station": "workbench", "tier": 1})), "the workbench window did not open")
	var crafting: Node = menus.get(&"crafting")
	var ids: Array[String] = []
	for recipe: Dictionary in RecipeCatalog.recipes_at(crafting.call(&"site")):
		ids.append(str(recipe["id"]))
	crafting.call(&"select_recipe", ids.find("craft-reinforced-pickaxe"))
	crafting.call(&"craft")
	crafting.call(&"close")
	t.equal(run.item_count("reinforced-pickaxe"), 1, "reinforced pickaxes")
	t.equal(str(quests.call(&"state", "a-harder-pick").get("active_stage_id")), "mine-iron", "stage after crafting")
	t.main.inventory_actions.equip_weapon_from_bag("reinforced-pickaxe")
	await t.steps(2)
	t.equal(run.equipped_weapon_id(), "reinforced-pickaxe", "hand")
	var mined := 0
	for instance_id in IRON_NODES:
		var node := _resource(t, instance_id)
		if node == null:
			continue
		var at: Vector2 = node.get_parent().global_position
		t.teleport_player(at + Vector2(-60.0, -30.0))
		t.player().face(Vector2.RIGHT)
		for swing in 8:
			t.tap(&"attack")
			await t.sim_wait(950.0)
			if str(run.resource_record(MAP_ID, instance_id).get("stage", "node")) != "node":
				break
		if str(run.resource_record(MAP_ID, instance_id).get("stage", "node")) == "node":
			continue
		await t.sim_wait(900.0)
		for pile: Node in t.tree.get_nodes_in_group(&"collectible"):
			if str(pile.get(&"source_resource_instance_id")) == instance_id:
				t.teleport_player((pile.get_parent() as Node2D).global_position - Vector2(0.0, 14.56))
				await t.steps(3)
		mined += 1
		if run.item_count("iron-ore") >= 6:
			break
	t.check(mined > 0, "no iron node broke under the reinforced pickaxe")
	var ore := run.item_count("iron-ore")
	t.equal(int((quests.call(&"state", "a-harder-pick").get("progress") as Dictionary).get("collect-iron-ore", 0)), mini(ore, 6), "iron ore counted (%d picked up)" % ore)


func _resource(t: TestContext, instance_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"resource_node"):
		if str(node.get(&"instance_id")) == instance_id:
			return node
	t.check(false, "no resource node %s in gloop-forest" % instance_id)
	return null


## Beyond the Verdant Gate: orb weavers defeated in gloop-forest count, and the weaver fangs they
## drop count once picked up (loot piles are pickups).
func test_beyond_the_verdant_gate_weavers_and_fangs(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	quests.call(&"debug_activate", "beyond-the-verdant-gate")
	seed(20261005)
	var centre := Vector2(1200.0, 1200.0)
	t.teleport_player(centre)
	await t.steps(2)
	var kills := 0
	while kills < 15:
		var progress: Dictionary = quests.call(&"state", "beyond-the-verdant-gate").get("progress", {})
		if int(progress.get("defeat-orb-weavers", 0)) >= 5 and int(progress.get("collect-fangs", 0)) >= 3:
			break
		var root := Services.world().spawn_at_phaser_position("character.orb-weaver", centre + Vector2(140.0, 0.0))
		var weaver: Node = null
		for child in root.get_children():
			if child.has_signal(&"reward_requested"):
				weaver = child
		if not t.check(weaver != null, "no orb weaver spawned"):
			return
		weaver.set(&"targeting_radius", 0.0)
		weaver.set(&"attack_range", 0.0)
		await t.steps(1)
		_kill(t, weaver.get(&"damage_area"))
		kills += 1
		await t.sim_wait(900.0)
		for pile: Node in t.tree.get_nodes_in_group(&"collectible"):
			if str(pile.get(&"item_id")) == "weaver-fang" and pile.is_inside_tree():
				t.teleport_player((pile.get_parent() as Node2D).global_position - Vector2(0.0, 14.56))
				await t.steps(3)
		t.teleport_player(centre)
		await t.steps(1)
	var progress: Dictionary = quests.call(&"state", "beyond-the-verdant-gate").get("progress", {})
	t.check(int(progress.get("defeat-orb-weavers", 0)) >= 5, "weavers counted: %s" % [progress])
	t.check(int(progress.get("collect-fangs", 0)) >= 3, "fangs counted: %s (fangs in the bag %d)" % [progress, run.item_count("weaver-fang")])
	t.check(bool(quests.call(&"view", "beyond-the-verdant-gate").get("ready_to_turn_in", false)), "not ready to turn in")


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
