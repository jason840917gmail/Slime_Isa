extends RefCounted
## Resource nodes, drops, collectibles and the inventory (docs/godot/specs/world-objects.md 12.9).
## level-1 objects: `level-1-tree-004` (grove tree, 40 HP, base (527.25, 1254.95)),
## `level-1-stone-node-01` (80 HP, (1056, 352)), `level-1-loose-wood-04` (wood pile of 10 at
## (608, 576)), `level-1-purple-berry-03` ((550.4, 1363.2)). Router-level hits use a stand-in
## activation (one per hit) so the damage is exact: a stone axe does 14 (base 12 x 1.2).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ResourceRespawn := preload("res://game/world_objects/resource_respawn.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")
const ResourceNodeScript := preload("res://game/scripts/resource_node.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")

const TREE := "level-1-tree-004"
const TREE_BASE := Vector2(527.25, 1254.95)
const STONE := "level-1-stone-node-01"
const WOOD_PILE := "level-1-loose-wood-04"
const WOOD_PILE_AT := Vector2(608.0, 576.0)
const BERRY := "level-1-purple-berry-03"
const BERRY_AT := Vector2(550.4, 1363.2)
## Player pickup rect centre = old Phaser centre + (0, 14.56) (player_slime.tscn PickupShape).
const PICKUP_OFFSET := Vector2(0.0, 14.56)
const AXE_TAGS := ["harvest:wood:1", "weapon"]
const SWORD_TAGS := ["weapon"]
const PICKAXE_TAGS := ["harvest:stone:1", "weapon"]
const EPOCH := 1000000.0
const RESPAWN_MS := 600000.0


# --- inventory ---------------------------------------------------------------------------------

func test_inventory_capacity_and_stacking(t: TestContext) -> void:
	var run := Services.run()
	t.equal(run.item_capacity("wood"), 500, "wood capacity in 20 empty slots (25 each)")
	t.equal(run.item_capacity("unknown-thing"), 0, "capacity of an unknown item")
	t.equal(run.item_capacity("green-key"), 20, "green key capacity (max stack 1)")
	for i in 4:
		t.equal(run.collect_world_item("level-1", "test-pile-%d" % i, "wood", 10), 10, "wood pile %d moved" % i)
	t.equal(run.inventory["slots"], [{"item_id": "wood", "count": 25}, {"item_id": "wood", "count": 15}], "slots after four piles")
	t.check(run.remove_item("wood", 30), "removing 30 wood failed")
	t.equal(run.inventory["slots"], [{"item_id": "wood", "count": 10}], "slots after removing 30 (first slot first)")


func test_partial_collect(t: TestContext) -> void:
	var run := Services.run()
	_fill(run, 19, {"item_id": "wood", "count": 20})
	t.equal(run.collect_world_item("level-1", "test-pile", "wood", 10), 5, "moved into the last wood stack")
	t.equal(run.collectible_record("level-1", "test-pile").get("remaining"), 5, "record remaining")
	t.equal(run.item_count("wood"), 25, "wood in the bag")
	t.equal(run.collect_world_item("level-1", "test-pile", "wood", 10), 0, "nothing more fits")


# --- regrowth and placement helpers --------------------------------------------------------------

func test_respawn_resolution(t: TestContext) -> void:
	var now := EPOCH
	var none := ResourceRespawn.resolve({}, now, RESPAWN_MS)
	t.check(none["record"] == {} and not bool(none["changed"]), "no record: none, unchanged")
	var node := ResourceRespawn.resolve({"stage": "node", "value": 26.0}, now, RESPAWN_MS)
	t.check(not bool(node["changed"]), "stage node changed")
	var untimed := ResourceRespawn.resolve({"stage": "depleted", "value": 0.0}, now, RESPAWN_MS)
	t.check(bool(untimed["changed"]) and float(untimed["record"]["respawn_ready_at_epoch_ms"]) == now + RESPAWN_MS,
		"an untimed depleted record gets now + 600000 (got %s)" % [untimed])
	var due := ResourceRespawn.resolve({"stage": "depleted", "value": 0.0, "respawn_ready_at_epoch_ms": now - 1.0}, now, RESPAWN_MS)
	t.check(bool(due["changed"]) and (due["record"] as Dictionary).is_empty(), "a due depleted node regrows")
	var waiting := ResourceRespawn.resolve({"stage": "depleted", "value": 0.0, "respawn_ready_at_epoch_ms": now + 1.0}, now, RESPAWN_MS)
	t.check(not bool(waiting["changed"]), "a waiting depleted node changed")
	var piles := ResourceRespawn.resolve({"stage": "destroyed", "value": 10.0, "piles": [{"id": "p", "amount": 10}],
		"respawn_ready_at_epoch_ms": now - 1.0}, now, RESPAWN_MS)
	t.check(not bool(piles["changed"]), "a node with piles still lying regrew")


func test_drop_placement_helpers(t: TestContext) -> void:
	var offsets := []
	for k in range(1, 6):
		offsets.append(ResourceDrops.stable_offset(64, k))
	t.equal(offsets, [Vector2i(-5, 4), Vector2i(1, -9), Vector2i(7, 9), Vector2i(-13, -2), Vector2i(12, -8)], "golden-angle offsets")
	var free := func(_cell: Vector2i) -> bool: return false
	t.equal(ResourceDrops.find_drop_cells(Vector2i(10, 10), 3, free, 56, 56), [Vector2i(9, 9), Vector2i(10, 9), Vector2i(11, 9)], "first three free cells")
	var corner := func(cell: Vector2i) -> bool: return cell == Vector2i(9, 9)
	t.equal(ResourceDrops.find_drop_cells(Vector2i(10, 10), 3, corner, 56, 56), [Vector2i(10, 9), Vector2i(11, 9), Vector2i(9, 10)], "cells with (9, 9) blocked")
	var empty: Array[Vector2i] = []
	var placements := ResourceDrops.complete_placements(empty, Vector2i(5, 5), 3, 64)
	t.equal(placements.map(func(p: Dictionary) -> Vector2i: return p["offset"]), [Vector2i(0, 0), Vector2i(-5, 4), Vector2i(1, -9)], "boxed-in offsets")
	t.equal(ResourceDrops.pile_position(Vector2i(9, 9), Vector2i.ZERO, 64), Vector2(608.0, 640.0), "pile position of cell (9, 9)")
	t.equal(ResourceDrops.source_cell(Vector2(281.6, 1356.8), 64), Vector2i(4, 20), "source cell of level-1-tree-01")


# --- harvesting -----------------------------------------------------------------------------------

func test_sword_is_blocked_by_tree(t: TestContext) -> void:
	var tree := _resource(t, TREE)
	if not t.check(tree != null, "no %s" % TREE):
		return
	var blocked: Array = []
	tree.harvest_blocked.connect(func(payload: Dictionary) -> void: blocked.append(payload))
	var result := _hit(t, tree.damage_area, SWORD_TAGS, 24.0)
	t.equal(result.get("status"), "rejected", "sword hit status")
	t.equal(result.get("reason"), "state-blocked", "sword hit reason")
	t.equal(tree.get_damage_state()["hp"], 40.0, "tree HP after a sword hit")
	if t.check(blocked.size() == 1, "harvest_blocked fired %d times" % blocked.size()):
		var payload: Dictionary = blocked[0]
		t.equal(payload.get("message"), "Requires an Axe", "blocked message")
		t.equal(payload.get("targetTag"), "wood", "blocked target tag")
		t.near_vec(Vector2(payload["x"], payload["y"]), TREE_BASE, 0.01, "blocked position")
	t.check(Services.run().resource_record("level-1", TREE).is_empty(), "a blocked hit wrote a record")


func test_axe_fells_tree_and_drops_wood(t: TestContext) -> void:
	ResourceRespawn.epoch_override_ms = EPOCH
	var run := Services.run()
	var tree := _resource(t, TREE)
	if not t.check(tree != null, "no %s" % TREE):
		return
	var drops: Array = []
	tree.drops_requested.connect(func(payload: Dictionary) -> void: drops.append(payload))
	var tree_root := tree.get_parent()
	_hit(t, tree.damage_area, AXE_TAGS, 14.0)
	t.equal(run.resource_record("level-1", TREE), {"stage": "node", "value": 26.0}, "record after hit 1")
	_hit(t, tree.damage_area, AXE_TAGS, 14.0)
	t.equal(run.resource_record("level-1", TREE), {"stage": "node", "value": 12.0}, "record after hit 2")
	var last := _hit(t, tree.damage_area, AXE_TAGS, 14.0)
	t.equal(last.get("actual_damage"), 12, "last hit's damage")
	t.check(bool(last.get("defeated", false)), "the last hit did not fell the tree")
	var record := run.resource_record("level-1", TREE)
	t.equal(record.get("stage"), "destroyed", "record stage after felling")
	t.equal(record.get("value"), 10.0, "wood lying after felling")
	t.equal(record.get("respawn_ready_at_epoch_ms"), EPOCH + RESPAWN_MS, "regrow time")
	var piles: Array = record.get("piles", [])
	if t.check(piles.size() == 1, "%d piles recorded" % piles.size()):
		t.equal(piles[0].get("id"), TREE + "-drop-1", "pile id")
		t.equal(piles[0].get("object_id"), "collectible.wood-pile", "pile object")
		t.equal(piles[0].get("amount"), 10, "pile amount")
	t.equal(drops.size(), 1, "drops_requested count")
	t.check(tree_root.is_queued_for_deletion(), "the felled tree was not freed")
	var pile := _collectible(t, TREE + "-drop-1")
	if not t.check(pile != null, "no spawned pile"):
		ResourceRespawn.epoch_override_ms = -1.0
		return
	t.equal(pile.quantity, 10, "pile quantity")
	t.equal(pile.source_resource_instance_id, TREE, "pile source")
	t.check(not pile.pickup_area.monitorable, "the pile is pickable while it flies")
	var settled := await t.until(func() -> bool: return pile.pickup_area.monitorable, 600.0)
	t.check(settled, "the pile never became pickable")
	var expected := ResourceDrops.pile_position(Vector2i(int(piles[0]["cell_x"]), int(piles[0]["cell_y"])), Vector2i.ZERO, 64)
	t.near_vec((pile.get_parent() as Node2D).global_position, expected, 0.01, "pile landing position")
	ResourceRespawn.epoch_override_ms = -1.0


func test_stone_needs_pickaxe_and_forgets_damage(t: TestContext) -> void:
	var run := Services.run()
	var stone := _resource(t, STONE)
	if not t.check(stone != null, "no %s" % STONE):
		return
	var blocked: Array = []
	stone.harvest_blocked.connect(func(payload: Dictionary) -> void: blocked.append(payload))
	_hit(t, stone.damage_area, ["harvest:wood:2"], 14.0)
	t.check(blocked.size() == 1 and blocked[0]["message"] == "Requires a Pickaxe", "an axe was not turned away (%s)" % [blocked])
	_hit(t, stone.damage_area, PICKAXE_TAGS, 14.0)
	t.equal(stone.get_damage_state()["hp"], 66.0, "stone HP after one pickaxe hit")
	t.check(run.resource_record("level-1", STONE).is_empty(), "stone damage was saved")
	for i in 5:
		_hit(t, stone.damage_area, PICKAXE_TAGS, 14.0)
	var record := run.resource_record("level-1", STONE)
	t.equal(record.get("stage"), "destroyed", "stone stage after 6 hits")
	var ids: Array = (record.get("piles", []) as Array).map(func(pile: Dictionary) -> String: return pile["id"])
	t.equal(ids, [STONE + "-drop-1", STONE + "-drop-2", STONE + "-drop-3"], "stone pile ids")
	t.equal(record.get("value"), 30.0, "stone lying")


# --- pickups ----------------------------------------------------------------------------------

func test_walk_over_pickup(t: TestContext) -> void:
	var run := Services.run()
	var pile := _collectible(t, WOOD_PILE)
	if not t.check(pile != null, "no %s" % WOOD_PILE):
		return
	var results: Array = []
	pile.pickup_resolved.connect(func(payload: Dictionary) -> void: results.append(payload))
	var pile_root := pile.get_parent()
	t.teleport_player(WOOD_PILE_AT - PICKUP_OFFSET)
	await t.until(func() -> bool: return not results.is_empty(), 300.0)
	if not t.check(results.size() == 1, "%d pickup results" % results.size()):
		return
	t.equal(results[0], {"status": "collected", "moved": 10, "remaining": 0}, "pickup result")
	t.equal(run.inventory["slots"], [{"item_id": "wood", "count": 10}], "bag after the pickup")
	t.equal(run.collectible_record("level-1", WOOD_PILE), {"remaining": 0}, "pile record")
	t.check(not is_instance_valid(pile_root) or pile_root.is_queued_for_deletion(), "the pile stayed")


func test_inventory_full_keeps_pile(t: TestContext) -> void:
	var run := Services.run()
	_fill(run, 20, {})
	var pile := _collectible(t, WOOD_PILE)
	if not t.check(pile != null, "no %s" % WOOD_PILE):
		return
	var results: Array = []
	pile.pickup_resolved.connect(func(payload: Dictionary) -> void: results.append(payload))
	t.teleport_player(WOOD_PILE_AT - PICKUP_OFFSET)
	await t.until(func() -> bool: return not results.is_empty(), 300.0)
	if not t.check(results.size() == 1, "%d pickup results" % results.size()):
		return
	t.equal(results[0], {"status": "rejected", "moved": 0, "remaining": 10, "reason": "inventory-full"}, "full-bag result")
	t.check(is_instance_valid(pile) and not pile.get_parent().is_queued_for_deletion(), "the pile went away")
	t.check(run.collectible_record("level-1", WOOD_PILE).is_empty(), "a rejected pickup wrote a record")
	await t.steps(10)
	t.equal(results.size(), 1, "standing on the pile retried the pickup")


func test_collected_pile_updates_node_record(t: TestContext) -> void:
	ResourceRespawn.epoch_override_ms = EPOCH
	var run := Services.run()
	var tree := _resource(t, TREE)
	if not t.check(tree != null, "no %s" % TREE):
		return
	for i in 3:
		_hit(t, tree.damage_area, AXE_TAGS, 14.0)
	var pile := _collectible(t, TREE + "-drop-1")
	if not t.check(pile != null, "no spawned pile"):
		ResourceRespawn.epoch_override_ms = -1.0
		return
	await t.until(func() -> bool: return pile.pickup_area.monitorable, 600.0)
	t.teleport_player((pile.get_parent() as Node2D).global_position - PICKUP_OFFSET)
	await t.until(func() -> bool: return run.item_count("wood") > 0, 300.0)
	t.equal(run.item_count("wood"), 10, "wood from the felled tree")
	t.equal(run.resource_record("level-1", TREE), {"stage": "depleted", "value": 0.0, "respawn_ready_at_epoch_ms": EPOCH + RESPAWN_MS}, "node record after its pile")
	t.equal(run.collectible_record("level-1", TREE + "-drop-1"), {"remaining": 0, "source_resource_instance_id": TREE}, "pile record")
	ResourceRespawn.epoch_override_ms = -1.0


## Reloading level-1 (a travel into itself) brings back a damaged tree's HP, a felled tree's
## uncollected pile, and, once the pile is gone and the regrow time passed, the tree itself.
func test_records_restore_on_reload(t: TestContext) -> void:
	ResourceRespawn.epoch_override_ms = EPOCH
	var run := Services.run()
	var tree := _resource(t, TREE)
	if not t.check(tree != null, "no %s" % TREE):
		return
	_hit(t, tree.damage_area, AXE_TAGS, 14.0)
	await _reload(t)
	tree = _resource(t, TREE)
	if t.check(tree != null, "the damaged tree is gone after the reload"):
		t.equal(tree.get_damage_state()["hp"], 26.0, "damaged tree HP after the reload")
		_hit(t, tree.damage_area, AXE_TAGS, 14.0)
		_hit(t, tree.damage_area, AXE_TAGS, 14.0)
	await _reload(t)
	await t.steps(2)
	t.check(_resource(t, TREE) == null, "the felled tree came back too early")
	var pile := _collectible(t, TREE + "-drop-1")
	if t.check(pile != null, "the uncollected pile did not come back"):
		t.check(pile.pickup_area.monitorable, "the restored pile is not pickable")
		t.teleport_player((pile.get_parent() as Node2D).global_position - PICKUP_OFFSET)
		await t.until(func() -> bool: return run.item_count("wood") > 0, 300.0)
	ResourceRespawn.epoch_override_ms = EPOCH + RESPAWN_MS
	await _reload(t)
	tree = _resource(t, TREE)
	if t.check(tree != null, "the tree did not regrow"):
		t.equal(tree.get_damage_state()["hp"], 40.0, "regrown tree HP")
	t.check(run.collectible_record("level-1", TREE + "-drop-1").is_empty(), "the old pile record survived the regrowth")
	ResourceRespawn.epoch_override_ms = -1.0


## A real stone-axe swing on the tree (weapon, sector, router): 14 per hit, no hit-stop.
func test_stone_axe_swing_end_to_end(t: TestContext) -> void:
	var tree := _resource(t, TREE)
	if not t.check(tree != null, "no %s" % TREE):
		return
	var combat = t.player().get_combat()
	if not t.check(combat.equip("stone-axe"), "could not equip the stone axe"):
		return
	await t.steps(2)
	var routes: Array = []
	t.listen(Services.router().routed, func(payload: Dictionary) -> void:
		if (payload.get("request", {}) as Dictionary).get("target_area") == tree.damage_area:
			routes.append(payload.get("result", {})))
	var paused := {"seen": false}
	t.teleport_player(TREE_BASE + Vector2(-60.0, -30.0))
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	await t.until(func() -> bool:
		paused["seen"] = paused["seen"] or t.tree.paused
		return not routes.is_empty(), 1000.0)
	if not t.check(not routes.is_empty(), "the axe swing never reached the tree"):
		return
	var damage := int(routes[0].get("actual_damage", 0))
	t.check(damage == 14 or damage == 25, "axe damage %d (expected 14, or 25 on a crit)" % damage)
	t.check(not paused["seen"], "a tree hit paused the game (hit-stop)")


func test_purple_berry_coins(t: TestContext) -> void:
	var run := Services.run()
	t.equal(run.coins(), 50, "coins at a new run")
	t.teleport_player(BERRY_AT - PICKUP_OFFSET)
	await t.until(func() -> bool: return run.item_count("purple-berry-mat") > 0, 300.0)
	t.equal(run.item_count("purple-berry-mat"), 1, "berries in the bag")
	t.equal(run.coins(), 55, "coins after a berry")


# --- helpers ----------------------------------------------------------------------------------

func _resource(t: TestContext, instance_id: String) -> ResourceNodeScript:
	for node: Node in t.tree.get_nodes_in_group(&"resource_node"):
		var script := node as ResourceNodeScript
		if script != null and script.instance_id == instance_id and script.is_inside_tree() \
				and not script.get_parent().is_queued_for_deletion():
			return script
	return null


func _collectible(t: TestContext, instance_id: String) -> CollectibleScript:
	for node: Node in t.tree.get_nodes_in_group(&"collectible"):
		var script := node as CollectibleScript
		if script != null and script.instance_id == instance_id and script.is_inside_tree() \
				and not script.get_parent().is_queued_for_deletion():
			return script
	return null


## One weapon hit through the router with its own activation.
func _hit(t: TestContext, target_area: Area2D, tags: Array, base_damage: float) -> Dictionary:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	var result := router.route({"activation_id": activation, "source": source, "attack_area": attack,
		"target_area": target_area, "weapon_id": "test-tool", "weapon_tags": tags,
		"damage_types": ["physical"], "base_damage": base_damage, "effects": [],
		"impact": {"position": target_area.global_position, "knock": Vector2.RIGHT}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
	return result


## Fills `count` bag slots with full stone stacks, then appends `last` when given.
func _fill(run: Node, count: int, last: Dictionary) -> void:
	var slots: Array = run.inventory["slots"]
	slots.clear()
	for i in count:
		slots.append({"item_id": "stone", "count": 25})
	if not last.is_empty():
		slots.append(last)


## Rebuilds level-1 through a travel into itself and waits for the new world.
func _reload(t: TestContext) -> void:
	t.main.travel_to("level-1", "south")
	await t.until(func() -> bool: return t.main.is_transitioning(), 100.0)
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
