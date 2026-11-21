extends RefCounted
## The forest camp in gloop-forest E4 in Release 1 (docs/godot/specs/quests.md 14.4): Mossy
## (`gloop-ch2-npc-mossy`) tells where Tom went (the tip `mossy.tom`, the gold "!") until Tom is free,
## and Sunny (`gloop-ch2-npc-sunny`) only tells of her basket across the north stream (no quest).
## Rewritten 2026-11-20: Sunny's Basket is retired, with its test of the Phaser soft-lock.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestService := preload("res://game/quests/quest_service.gd")
const QuestNpcTalk := preload("res://game/quests/quest_npc_talk.gd")

const MAP_ID := "gloop-forest-e4"
const MOSSY := "gloop-ch2-npc-mossy"
const SUNNY := "gloop-ch2-npc-sunny"


func test_mossy_points_at_tom_and_sunny_tells_of_her_basket(t: TestContext) -> void:
	var quests := t.tree.get_first_node_in_group(&"quests") as QuestService
	var run := Services.run()
	var mossy := _npc(t, MOSSY)
	var sunny := _npc(t, SUNNY)
	if not t.check(mossy != null and sunny != null, "Mossy or Sunny is not at the camp"):
		return
	var mossy_id := str(mossy.get(&"npc_definition_id"))
	var sunny_id := str(sunny.get(&"npc_definition_id"))
	run.set_flag("chapter-1-complete")
	t.equal(str(QuestNpcTalk.matching_talk(mossy_id).get("id", "")), "camp", "Mossy's talk at the camp")
	t.equal(QuestNpcTalk.talk_tip_id(QuestNpcTalk.matching_talk(mossy_id)), "mossy.tom", "Mossy's tip")
	t.equal(quests.marker_for(mossy_id), "tip", "Mossy's marker before Tom is free")
	t.equal(str(QuestNpcTalk.matching_talk(sunny_id).get("id", "")), "lost-basket", "Sunny's talk at the camp")
	t.equal(QuestNpcTalk.talk_tip_id(QuestNpcTalk.matching_talk(sunny_id)), "", "Sunny's talk gives a tip")
	t.equal(quests.offers_for_npc(sunny_id), [], "Sunny offers a quest")
	run.set_flag("tom-freed")
	t.equal(str(QuestNpcTalk.matching_talk(mossy_id).get("id", "")), "camp-after-tom", "Mossy's talk once Tom is free")
	t.equal(quests.marker_for(mossy_id), "", "Mossy's marker once Tom is free")


func _npc(t: TestContext, instance_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == instance_id:
			return node
	return null
