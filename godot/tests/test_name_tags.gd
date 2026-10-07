extends RefCounted
## NPC name tags (game/ui/npc_name_tags.gd; world spec 5.6): every NPC with a definition wears its
## display name 2 px above its sprite (old position - (0, 75.28)), and the tag walks with it.

const TestContext := preload("res://tests/lib/test_context.gd")
const NpcNameTags := preload("res://game/ui/npc_name_tags.gd")


func test_elder_wears_his_name(t: TestContext) -> void:
	await t.tree.process_frame
	await t.tree.process_frame
	var elder: Node = null
	for npc: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(npc.get(&"npc_definition_id")) == "village-elder-plop":
			elder = npc
	if not t.check(elder != null, "no Village Elder Plop in level-1"):
		return
	var body := elder.get(&"body") as Node2D
	t.equal(NpcNameTags.tag_text(body), "Village Elder Plop", "the Elder's tag")
	var label := body.get_node("NameTag").get_child(0) as Label
	var bottom_centre := label.global_position + Vector2(label.size.x / 2.0, label.size.y)
	var expected: Vector2 = (elder.call(&"get_phaser_position") as Vector2) - Vector2(0.0, 75.28)
	t.near_vec(bottom_centre, expected, 1.0, "tag bottom centre")
