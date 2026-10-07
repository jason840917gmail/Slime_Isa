extends RefCounted
## Quests in gloop-forest (docs/godot/specs/quests.md 7.5 and 10.10): Sunny's basket
## (`gloop-ch2-sunny-basket`, one berry basket across the water, reached with the Stretch Lash).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestService := preload("res://game/quests/quest_service.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")

const MAP_ID := "gloop-forest"
const BASKET := "gloop-ch2-sunny-basket"


## Owner decision Q1 keeps Phaser's soft-lock: a basket taken before Sunny's quest starts never
## counts (collect objectives count pickups during the active stage only), and the authored pile
## never comes back. Rewrite this test if the content gets fixed.
func test_sunny_basket_soft_lock(t: TestContext) -> void:
	var quests := t.tree.get_first_node_in_group(&"quests") as QuestService
	var run := Services.run()
	var pile: CollectibleScript = null
	for node: Node in t.tree.get_nodes_in_group(CollectibleScript.GROUP):
		if node is CollectibleScript and (node as CollectibleScript).instance_id == BASKET:
			pile = node
	if not t.check(pile != null, "no %s" % BASKET):
		return
	var result := pile.request_pickup(t.player().get_pickup_area())
	t.equal(result.get("status"), "collected", "the basket pickup")
	quests.debug_mark_completed("beyond-the-verdant-gate")
	t.equal(quests.status("sunnys-basket"), "available", "Sunny's basket")
	t.check(bool(quests.accept("sunnys-basket", "yellow-blond-slime-girl").get("ok")), "accept refused")
	t.equal(int((quests.state("sunnys-basket")["progress"] as Dictionary).get("collect-basket", -1)), 0, "basket progress")
	t.equal(run.collectible_record(MAP_ID, BASKET), {"remaining": 0}, "the pile is gone for good")
	t.equal(run.item_count("berry-basket"), 1, "the basket in the bag")
	t.check(not bool(quests.view("sunnys-basket").get("ready_to_turn_in")), "a carried basket counted")
