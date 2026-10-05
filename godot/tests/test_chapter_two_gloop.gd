extends RefCounted
## Chapter 2 in gloop-forest through play: A Harder Pick (the reinforced pickaxe crafted at the
## workbench, put in hand, iron ore mined from gloop-forest's iron nodes and picked up).

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
