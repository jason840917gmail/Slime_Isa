extends RefCounted
## Tom in the web (docs/godot/specs/quests.md 14.3 "Tom's Goo Bomb", 14.6): the web holding Tom
## (`object.tom-web`, in his clearing in gloop-forest E5 at (736, 1440)) tears under weapon hits only,
## with no quest to wait for; torn, it frees Tom (`tom-freed`) and his lesson plays right there
## (game/scripts/tom_lesson.gd: the slime held, his lines, the Goo Bomb learned, `tom.goo-bomb-taught`),
## and he waits at Mossy's camp (E4). A run that tore the web without the lesson learns it from Tom
## at the camp (his `goo-bomb-lesson` talk).
## Rewritten 2026-11-20: Mossy's quest "Tom in the Web" and Tom's Swallow lesson are retired (the
## old tests of the quest gate and of Swallow are gone).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestNpcTalk := preload("res://game/quests/quest_npc_talk.gd")

const MAP_ID := "gloop-forest-e5"
## The camp's chunk, where Tom shows once freed.
const CAMP_MAP := "gloop-forest-e4"
const FLAG := "tom-freed"
const TAUGHT := "tom.goo-bomb-taught"
const GOO_BOMBS := "goo-bombs"
const WEB := Vector2(736.0, 1440.0)


func test_the_web_tears_only_under_weapon_hits(t: TestContext) -> void:
	var run := Services.run()
	var web := _web(t)
	if not t.check(web != null, "no Tom's web in gloop-forest E5"):
		return
	t.teleport_player(WEB + Vector2(0.0, 80.0))
	await t.steps(2)
	var area: Area2D = web.get(&"damage_area")
	_hit(t, area, ["thrown", "rock"])
	await t.steps(1)
	t.equal(int(web.get(&"hits")), 0, "a thrown rock counted as a cut")
	t.check(not run.has_flag(FLAG), "a thrown rock tore the web")
	for i in int(web.get(&"hits_to_tear")):
		_hit(t, area, ["spear" if i % 2 == 0 else "weapon"])
		await t.steps(1)
	t.check(run.has_flag(FLAG), "the web did not tear after %d weapon hits" % int(web.get(&"hits_to_tear")))


func test_tearing_the_web_teaches_the_goo_bomb_and_tom_goes_to_the_camp(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	t.check(not run.has_learned_ability(GOO_BOMBS), "the Goo Bomb is known before Tom's lesson")
	var web := _web(t)
	if not t.check(web != null, "no Tom's web in gloop-forest E5"):
		return
	var lesson := web.get_parent().get_node("TomLesson")
	t.teleport_player(WEB + Vector2(0.0, 80.0))
	await t.steps(2)
	for i in int(web.get(&"hits_to_tear")):
		_hit(t, web.get(&"damage_area"), ["weapon"])
		await t.steps(1)
	t.check(bool(lesson.call(&"is_playing")), "Tom's lesson did not start as the web tore")
	var dialogue: Node = quests.get(&"dialogue")
	t.check(await t.until(func() -> bool: return bool(dialogue.call(&"is_open")), 1500.0), "Tom said nothing")
	t.equal(str(dialogue.call(&"speaker")), "Tom", "the speaker")
	var at := t.player().get_centre()
	await _read_all(t, dialogue, lesson)
	t.check(not bool(lesson.call(&"is_playing")), "Tom's lesson did not end")
	t.check(run.has_learned_ability(GOO_BOMBS), "Tom did not teach the Goo Bomb")
	t.check(run.has_flag(TAUGHT), "Tom's lesson flag")
	t.near_vec(t.player().get_centre(), at, 1.0, "the slime moved during Tom's lesson")
	t.equal(str(QuestNpcTalk.matching_talk("tom").get("id", "")), "watch-oak", "Tom's talk after his lesson")
	await t.steps(3)
	if not t.check(t.main.travel_to(CAMP_MAP, "west"), "travel to the camp's chunk was refused"):
		return
	if not t.check(await t.until(func() -> bool: return t.world().map_id() == CAMP_MAP and t.player() != null, 3000.0, 6000.0),
			"the player did not reach %s" % CAMP_MAP):
		return
	await t.steps(3)
	t.check(_tom_at_camp(t) != null, "Tom is not at the camp after he was freed")


func test_tom_at_the_camp_teaches_a_run_that_missed_his_lesson(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	t.equal(str(QuestNpcTalk.matching_talk("tom").get("id", "")), "", "Tom's talk while he hangs in the web")
	run.set_flag(FLAG)
	var talk := QuestNpcTalk.matching_talk("tom")
	t.equal(str(talk.get("id", "")), "goo-bomb-lesson", "Tom's talk for a run that tore the web without the lesson")
	var outcome: Dictionary = (quests.get(&"talk") as Object).call(&"apply_talk", talk)
	t.check(bool(outcome.get("learned")), "Tom's talk did not teach the Goo Bomb")
	t.check(run.has_learned_ability(GOO_BOMBS) and run.has_flag(TAUGHT), "the Goo Bomb or the lesson flag after his talk")
	t.equal(str(QuestNpcTalk.matching_talk("tom").get("id", "")), "watch-oak", "Tom's talk after it")


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


## Reads Tom's lines until his lesson is over.
static func _read_all(t: TestContext, dialogue: Node, lesson: Node) -> void:
	var guard := 900
	while guard > 0 and not t.aborted and (bool(lesson.call(&"is_playing")) or bool(dialogue.call(&"is_open"))):
		guard -= 1
		if bool(dialogue.call(&"is_open")):
			dialogue.call(&"advance")
		await t.tree.process_frame


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
