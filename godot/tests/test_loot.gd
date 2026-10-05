extends RefCounted
## Enemy rewards (game/world_objects/enemy_loot.gd; Phaser CombatController.awardEnemyDefeat,
## InventoryDropController.dropLoot): a defeated enemy pays its coins, and loot that wins its roll
## falls as a recorded pile around the corpse, which is back after a reload until it is picked up.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const EnemyLoot := preload("res://game/world_objects/enemy_loot.gd")


func test_worm_pays_coins_on_defeat(t: TestContext) -> void:
	var run := Services.run()
	var worm := t.spawn_worm(Vector2(200.0, 0.0), true)
	if not t.check(worm != null, "no worm"):
		return
	await t.steps(1)
	var coins: int = run.coins()
	var rewards: Dictionary = worm.rewards
	worm.reward_requested.emit({"receiverNodeId": "", "rewards": {"coins": rewards.get("coins", 0), "items": []}})
	t.equal(run.coins(), coins + int(rewards.get("coins", 0)), "coins after the reward")


func test_loot_pile_is_recorded_restored_and_collected(t: TestContext) -> void:
	var run := Services.run()
	var at := Vector2(900.0, 900.0)
	t.main.loot.drop_loot("level-1", at, [{"item_id": "shard", "count": 1}])
	var drops: Dictionary = run.map_record("level-1")["inventory_drops"]
	if not t.check(drops.size() == 1, "%d loot records" % drops.size()):
		return
	var record: Dictionary = drops.values()[0]
	t.equal(record.get("origin"), "loot", "loot origin")
	t.main.travel_to("level-1", "south")
	await t.until(func() -> bool: return t.main.is_transitioning(), 100.0)
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.player() != null, 3000.0, 6000.0)
	await t.steps(3)
	var pile: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"collectible"):
		if str(node.get(&"source_inventory_drop_id")) == str(record["id"]):
			pile = node
	if not t.check(pile != null, "the loot pile did not come back after a reload"):
		return
	t.teleport_player((pile.get_parent() as Node2D).global_position - Vector2(0.0, 14.56))
	await t.until(func() -> bool: return run.item_count("shard") > 0, 300.0)
	t.equal(run.item_count("shard"), 1, "shards after the pickup")
	t.check(not (run.map_record("level-1")["inventory_drops"] as Dictionary).has(record["id"]), "the loot record is gone after the pickup")


func test_scatter_rings(t: TestContext) -> void:
	var free := func(_point: Vector2) -> bool: return false
	var points := EnemyLoot.scatter(Vector2(1000.0, 1000.0), 3, 64, free)
	t.near_vec(points[0], Vector2(1029.0, 1000.0), 0.01, "first piece (0.45 tile, angle 0)")
	t.check(points[1].distance_to(Vector2(1000.0, 1000.0)) > 20.0, "second piece on the corpse")
	var blocked := func(_point: Vector2) -> bool: return true
	t.near_vec(EnemyLoot.scatter(Vector2(10.4, 20.6), 1, 64, blocked)[0], Vector2(10.0, 21.0), 0.01, "boxed in: on the corpse")
