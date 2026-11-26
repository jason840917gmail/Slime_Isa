extends RefCounted
## Resource nodes, drops, collectibles and the inventory (docs/godot/specs/world-objects.md 12.9).
## level-1 objects: `level-1-tree-004` (grove tree, 40 HP, base (1685, 1481) since the village chunk
## was repainted) and `level-1-purple-berry-03` ((227, 1234)). The repaint left no wood pile or stone
## node in the chunk, so the tests that need one place their own at run time (`_place_wood_pile`,
## `_place_stone_node`: the game's `collectible-wood-pile` and `resource-stone-node` scenes, a pile of
## 10 and a node of 80 HP): their rules do not depend on the painting. Router-level hits use a
## stand-in activation (one per hit) so the damage is exact: a stone axe does 14 (base 12 x 1.2).
## level-1 is cut into chunk worlds (docs/godot/WORLD_ATLAS.md "Chunk worlds"): all of these are in
## the village chunk C4 (`level-1-c4`, its origin at level-1's (0, 0)), and their records are keyed
## by it.

## run_tests.gd starts every test of this file in level-1's village chunk.
const MAP_ID := "level-1-c4"

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ResourceRespawn := preload("res://game/world_objects/resource_respawn.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")
const ResourceNodeScript := preload("res://game/scripts/resource_node.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const TREE := "level-1-tree-004"
const TREE_BASE := Vector2(1685.0, 1481.0)
## The stone node and the wood pile the tests place (ids of their own, keyed by the chunk).
const STONE := "test-stone-node"
const STONE_SCENE := "object.resource-stone-node"
const WOOD_PILE := "test-wood-pile"
const WOOD_PILE_OBJECT := "collectible.wood-pile"
const WOOD_PILE_AMOUNT := 10
## Where they go, from the player's centre at the start (open village ground east of it).
const PLACE_OFFSET := Vector2(160.0, 0.0)
const BERRY := "level-1-purple-berry-03"
const BERRY_AT := Vector2(227.0, 1234.0)
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
	# An empty bag: the trial sword (crafting spec C3) set aside.
	_fill(run, 0, {})
	t.equal(run.item_capacity("wood"), 500, "wood capacity in 20 empty slots (25 each)")
	t.equal(run.item_capacity("unknown-thing"), 0, "capacity of an unknown item")
	t.equal(run.item_capacity("green-key"), 20, "green key capacity (max stack 1)")
	for i in 4:
		t.equal(run.collect_world_item(MAP_ID, "test-pile-%d" % i, "wood", 10), 10, "wood pile %d moved" % i)
	t.equal(run.inventory["slots"], [{"item_id": "wood", "count": 25}, {"item_id": "wood", "count": 15}], "slots after four piles")
	t.check(run.remove_item("wood", 30), "removing 30 wood failed")
	t.equal(run.inventory["slots"], [{"item_id": "wood", "count": 10}], "slots after removing 30 (first slot first)")


func test_partial_collect(t: TestContext) -> void:
	var run := Services.run()
	_fill(run, 19, {"item_id": "wood", "count": 20})
	t.equal(run.collect_world_item(MAP_ID, "test-pile", "wood", 10), 5, "moved into the last wood stack")
	t.equal(run.collectible_record(MAP_ID, "test-pile").get("remaining"), 5, "record remaining")
	t.equal(run.item_count("wood"), 25, "wood in the bag")
	t.equal(run.collect_world_item(MAP_ID, "test-pile", "wood", 10), 0, "nothing more fits")


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
	t.check(Services.run().resource_record(MAP_ID, TREE).is_empty(), "a blocked hit wrote a record")


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
	t.equal(run.resource_record(MAP_ID, TREE), {"stage": "node", "value": 26.0}, "record after hit 1")
	_hit(t, tree.damage_area, AXE_TAGS, 14.0)
	t.equal(run.resource_record(MAP_ID, TREE), {"stage": "node", "value": 12.0}, "record after hit 2")
	var last := _hit(t, tree.damage_area, AXE_TAGS, 14.0)
	t.equal(last.get("actual_damage"), 12, "last hit's damage")
	t.check(bool(last.get("defeated", false)), "the last hit did not fell the tree")
	var record := run.resource_record(MAP_ID, TREE)
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
	var stone := _place_stone_node(t)
	if not t.check(stone != null, "could not place %s" % STONE):
		return
	var blocked: Array = []
	stone.harvest_blocked.connect(func(payload: Dictionary) -> void: blocked.append(payload))
	_hit(t, stone.damage_area, ["harvest:wood:2"], 14.0)
	t.check(blocked.size() == 1 and blocked[0]["message"] == "Requires a Pickaxe", "an axe was not turned away (%s)" % [blocked])
	_hit(t, stone.damage_area, PICKAXE_TAGS, 14.0)
	t.equal(stone.get_damage_state()["hp"], 66.0, "stone HP after one pickaxe hit")
	t.check(run.resource_record(MAP_ID, STONE).is_empty(), "stone damage was saved")
	for i in 5:
		_hit(t, stone.damage_area, PICKAXE_TAGS, 14.0)
	var record := run.resource_record(MAP_ID, STONE)
	t.equal(record.get("stage"), "destroyed", "stone stage after 6 hits")
	var ids: Array = (record.get("piles", []) as Array).map(func(pile: Dictionary) -> String: return pile["id"])
	t.equal(ids, [STONE + "-drop-1", STONE + "-drop-2", STONE + "-drop-3"], "stone pile ids")
	t.equal(record.get("value"), 30.0, "stone lying")


# --- pickups ----------------------------------------------------------------------------------

func test_walk_over_pickup(t: TestContext) -> void:
	var run := Services.run()
	_fill(run, 0, {})
	var pile := _place_wood_pile(t)
	if not t.check(pile != null, "could not place %s" % WOOD_PILE):
		return
	var results: Array = []
	pile.pickup_resolved.connect(func(payload: Dictionary) -> void: results.append(payload))
	var pile_root := pile.get_parent()
	t.teleport_player((pile_root as Node2D).global_position - PICKUP_OFFSET)
	await t.until(func() -> bool: return not results.is_empty(), 300.0)
	if not t.check(results.size() == 1, "%d pickup results" % results.size()):
		return
	t.equal(results[0], {"status": "collected", "moved": 10, "remaining": 0}, "pickup result")
	t.equal(run.inventory["slots"], [{"item_id": "wood", "count": 10}], "bag after the pickup")
	t.equal(run.collectible_record(MAP_ID, WOOD_PILE), {"remaining": 0}, "pile record")
	t.check(not is_instance_valid(pile_root) or pile_root.is_queued_for_deletion(), "the pile stayed")


func test_inventory_full_keeps_pile(t: TestContext) -> void:
	var run := Services.run()
	_fill(run, 20, {})
	var pile := _place_wood_pile(t)
	if not t.check(pile != null, "could not place %s" % WOOD_PILE):
		return
	var results: Array = []
	pile.pickup_resolved.connect(func(payload: Dictionary) -> void: results.append(payload))
	t.teleport_player((pile.get_parent() as Node2D).global_position - PICKUP_OFFSET)
	await t.until(func() -> bool: return not results.is_empty(), 300.0)
	if not t.check(results.size() == 1, "%d pickup results" % results.size()):
		return
	t.equal(results[0], {"status": "rejected", "moved": 0, "remaining": 10, "reason": "inventory-full"}, "full-bag result")
	t.check(is_instance_valid(pile) and not pile.get_parent().is_queued_for_deletion(), "the pile went away")
	t.check(run.collectible_record(MAP_ID, WOOD_PILE).is_empty(), "a rejected pickup wrote a record")
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
	t.equal(run.resource_record(MAP_ID, TREE), {"stage": "depleted", "value": 0.0, "respawn_ready_at_epoch_ms": EPOCH + RESPAWN_MS}, "node record after its pile")
	t.equal(run.collectible_record(MAP_ID, TREE + "-drop-1"), {"remaining": 0, "source_resource_instance_id": TREE}, "pile record")
	ResourceRespawn.epoch_override_ms = -1.0


## Reloading the village chunk (a travel into itself) brings back a damaged tree's HP, a felled tree's
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
	t.check(run.collectible_record(MAP_ID, TREE + "-drop-1").is_empty(), "the old pile record survived the regrowth")
	ResourceRespawn.epoch_override_ms = -1.0


## A real War Axe sweep on the tree (the body-shapes mode is on in every world, so the attack key
## swings the current shape, not a weapon: docs/godot/BODY_SHAPES.md "War Axe", "Trees: the Axe chops
## (harvest wood 1)"): one accepted hit of the sweep's damage (the shape's base x the attack stat, x its
## `wood` target modifier; x the crit multiplier on a crit), and no hit-stop (resources show their own
## hit: ShapeStrike.feel_swing).
func test_war_axe_sweep_end_to_end(t: TestContext) -> void:
	var tree := _resource(t, TREE)
	if not t.check(tree != null, "no %s" % TREE):
		return
	var run := Services.run()
	run.learn_ability(String(ShapeDefs.AXE), true)
	var shapes := t.player().get_shapes()
	if not t.check(shapes != null, "the player has no ShapeController"):
		return
	shapes.sync_learned()
	if not t.check(shapes.set_current(ShapeDefs.AXE), "could not make the War Axe current"):
		return
	await t.steps(2)
	var routes: Array = []
	t.listen(Services.router().routed, func(payload: Dictionary) -> void:
		var request: Dictionary = payload.get("request", {})
		if request.get("target_area") == tree.damage_area:
			routes.append({"request": request, "result": payload.get("result", {})}))
	var paused := {"seen": false}
	t.teleport_player(TREE_BASE + Vector2(-60.0, -30.0))
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	await t.until(func() -> bool:
		paused["seen"] = paused["seen"] or t.tree.paused
		return not routes.is_empty(), 1000.0)
	if not t.check(not routes.is_empty(), "the War Axe sweep never reached the tree"):
		return
	var request: Dictionary = routes[0]["request"]
	var result: Dictionary = routes[0]["result"]
	t.equal(request.get("weapon_id"), String(ShapeDefs.AXE), "the hit's weapon")
	t.check((request.get("weapon_tags", []) as Array).has("harvest:wood:1"), "the sweep carries no harvest:wood:1 (%s)" % [request.get("weapon_tags")])
	t.equal(result.get("status"), "accepted", "the sweep's hit on the tree")
	var plain := roundi(ShapeDefs.damage(ShapeDefs.AXE, 1.0) * ShapeDefs.target_modifier(ShapeDefs.AXE, tree.tags))
	var crit := roundi(ShapeDefs.damage(ShapeDefs.AXE, 1.0) * ShapeDefs.crit_multiplier() * ShapeDefs.target_modifier(ShapeDefs.AXE, tree.tags))
	var damage := int(result.get("actual_damage", 0))
	t.check(plain > 0 and (damage == plain or damage == crit), "axe damage %d (expected %d, or %d on a crit)" % [damage, plain, crit])
	t.equal(tree.get_damage_state()["hp"], tree.max_health - float(damage), "tree HP after the sweep")
	await t.steps(2)
	t.check(not paused["seen"], "a tree hit paused the game (hit-stop)")


func test_purple_berry_coins(t: TestContext) -> void:
	var run := Services.run()
	t.equal(run.coins(), 50, "coins at a new run")
	t.teleport_player(BERRY_AT - PICKUP_OFFSET)
	await t.until(func() -> bool: return run.item_count("purple-berry-mat") > 0, 300.0)
	t.equal(run.item_count("purple-berry-mat"), 1, "berries in the bag")
	t.equal(run.coins(), 55, "coins after a berry")


# --- helpers ----------------------------------------------------------------------------------

## The pickup bounce (owner decision 2026-10-05): a walk-over pile hops about 6 world px now and then
## and settles back where it was; a resource node never moves.
func test_pickups_bounce_and_resource_nodes_stay_still(t: TestContext) -> void:
	var pile := _place_wood_pile(t)
	var stone := _place_stone_node(t, Vector2(0.0, 160.0))
	if not t.check(pile != null and stone != null, "could not place %s or %s" % [WOOD_PILE, STONE]):
		return
	var visual := pile.get_parent().get_node(^"Visual") as Sprite2D
	var stone_visual := stone.get_parent().get_node(^"Visual") as Sprite2D
	var rest := visual.offset
	var stone_rest := stone_visual.offset
	var highest := 0.0
	var stone_moved := false
	var started := t.now()
	while t.now() - started < 4000.0 and not t.aborted:
		await t.steps(1)
		highest = maxf(highest, (rest.y - visual.offset.y) * absf(visual.scale.y))
		stone_moved = stone_moved or stone_visual.offset != stone_rest
	t.between(highest, 4.0, CollectibleScript.BOUNCE_HEIGHT + 0.5, "the pile's highest hop (world px)")
	t.check(not stone_moved, "the stone node moved")
	await t.until(func() -> bool: return visual.offset == rest, 3000.0)
	t.equal(visual.offset, rest, "the pile settles back where it was")


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


## Places an authored-like wood pile of 10 (no source node) at the player's centre + `offset`, the
## way the game spawns a pile (ResourceDrops.spawn_pile), already landed.
func _place_wood_pile(t: TestContext, offset: Vector2 = PLACE_OFFSET) -> CollectibleScript:
	var at := t.player().get_centre() + offset
	var root := ResourceDrops.spawn_pile(WOOD_PILE_OBJECT, WOOD_PILE, MAP_ID, WOOD_PILE_AMOUNT, "", at, null, 0)
	return _collectible(t, WOOD_PILE) if root != null else null


## Places a stone node (80 HP) at the player's centre + `offset` in the world's entities root.
func _place_stone_node(t: TestContext, offset: Vector2 = PLACE_OFFSET) -> ResourceNodeScript:
	var world := Services.world()
	var parent := world.entities_root()
	var root := world.instantiate_scene(STONE_SCENE) as Node2D
	if root == null or parent == null:
		return null
	var script := root.get_node_or_null(^"ResourceNodeScript") as ResourceNodeScript
	if script == null:
		root.free()
		return null
	script.map_id = MAP_ID
	script.instance_id = STONE
	root.position = parent.to_local(t.player().get_centre() + offset)
	parent.add_child(root)
	root.reset_physics_interpolation()
	return script


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


## Rebuilds the village chunk through a travel into itself and waits for the new world.
func _reload(t: TestContext) -> void:
	t.main.travel_to(MAP_ID, "south")
	await t.until(func() -> bool: return t.main.is_transitioning(), 100.0)
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
