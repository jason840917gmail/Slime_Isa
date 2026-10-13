extends RefCounted
## Tom in the Web (roadmap 8.13) in gloop-forest: the web holding Tom (`object.tom-web`, south-west
## thicket, in chunk E5 at (860, 422): gloop-forest is cut into chunk worlds, docs/godot/WORLD_ATLAS.md)
## only tears while Mossy's quest is active and only under weapon hits;
## torn, it frees Tom (`tom-freed`), counts the quest's objective and shows Tom at the camp, where
## turning the quest in to him teaches Swallow. A Harder Pick waits for this quest.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const MAP_ID := "gloop-forest-e5"
## The camp's chunk, where Tom shows once freed.
const CAMP_MAP := "gloop-forest-e4"
const QUEST := "tom-in-the-web"
const FLAG := "tom-freed"
const WEB := Vector2(860.0, 422.0)


func test_the_web_tears_only_under_weapon_hits_while_the_quest_is_on(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	var web := _web(t)
	if not t.check(web != null, "no Tom's web in gloop-forest"):
		return
	t.teleport_player(WEB + Vector2(0.0, 80.0))
	await t.steps(2)
	var area: Area2D = web.get(&"damage_area")
	_hit(t, area, ["weapon"])
	await t.steps(1)
	t.check(not run.has_flag(FLAG), "the web tore before Mossy asked for Tom")
	quests.call(&"debug_activate", QUEST)
	_hit(t, area, ["thrown", "rock"])
	await t.steps(1)
	t.equal(int(web.get(&"hits")), 0, "a thrown rock counted as a cut")
	for i in int(web.get(&"hits_to_tear")):
		_hit(t, area, ["spear" if i % 2 == 0 else "weapon"])
		await t.steps(1)
	t.check(run.has_flag(FLAG), "the web did not tear after %d weapon hits" % int(web.get(&"hits_to_tear")))
	t.check(bool(quests.call(&"view", QUEST).get("ready_to_turn_in", false)), "the quest is not ready to turn in")
	await t.steps(3)
	if not t.check(t.main.travel_to(CAMP_MAP, "west"), "travel to the camp's chunk was refused"):
		return
	if not t.check(await t.until(func() -> bool: return t.world().map_id() == CAMP_MAP and t.player() != null, 3000.0, 6000.0),
			"the player did not reach %s" % CAMP_MAP):
		return
	await t.steps(3)
	t.check(_tom_at_camp(t) != null, "Tom is not at the camp after he was freed")


func test_tom_teaches_swallow_and_a_harder_pick_waits_for_him(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	t.check(not run.has_learned_ability("swallow"), "Swallow is known before Tom teaches it")
	t.equal(str(quests.call(&"status", "a-harder-pick")), "locked", "A Harder Pick before Tom's quest")
	quests.call(&"debug_activate", QUEST)
	var web := _web(t)
	if not t.check(web != null, "no Tom's web in gloop-forest"):
		return
	for i in int(web.get(&"hits_to_tear")):
		_hit(t, web.get(&"damage_area"), ["weapon"])
		await t.steps(1)
	await t.steps(3)
	var result: Dictionary = quests.call(&"turn_in", QUEST, "tom")
	t.check(bool(result.get("ok", false)), "turning in to Tom failed: %s" % [result])
	t.equal(str(quests.call(&"status", QUEST)), "completed", "Tom's quest")
	t.check(run.has_learned_ability("swallow"), "Tom did not teach Swallow")
	t.check(str(quests.call(&"status", "a-harder-pick")) != "locked", "A Harder Pick is still locked after Tom's quest")


func _web(t: TestContext) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"quest_object"):
		if str(node.get(&"object_id")) == "tom-web":
			return node
	return null


func _tom_at_camp(t: TestContext) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.get(&"npc_definition_id")) == "tom" and node.is_inside_tree():
			return node
	return null


func _hit(t: TestContext, target_area: Area2D, tags: Array) -> void:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": target_area,
		"weapon_id": "test-blade", "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 10.0,
		"effects": [], "impact": {"position": target_area.global_position, "knock": Vector2.RIGHT}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
