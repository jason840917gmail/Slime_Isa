extends RefCounted
## Ability lessons, the lash bell, training dummies, Goo Hearts and restoration sites in the
## playground (docs/godot/specs/abilities.md 19.5): the lash lesson (1904, 1520, reach 140), the
## bell on the moat island (2490, 1470) that opens `playground-lash-gate`, dummies at (1480, 1400),
## (1580, 1400), (1680, 1400).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const MAP_ID := "playground"
const LESSON := Vector2(1904.0, 1520.0)
const BELL_SHORE := Vector2(2340.0, 1465.0)
const LASH_GATE := "playground-lash-gate"
const DUMMY_STAND := Vector2(1480.0, 1440.0)


func test_lesson_teaches_lash_once_in_reach(t: TestContext) -> void:
	var run := Services.run()
	var lesson := _script_with(t, &"taught")
	if not t.check(lesson != null, "no ability lesson"):
		return
	var taught: Array = []
	lesson.taught.connect(func(payload: Dictionary) -> void: taught.append(payload))
	t.teleport_player(LESSON + Vector2(0.0, 180.0))
	await t.steps(3)
	t.check(taught.is_empty() and not run.has_learned_ability("stretch-lash"), "taught from 180 px")
	t.teleport_player(LESSON + Vector2(0.0, 80.0))
	await t.steps(3)
	t.equal(taught, [{"abilityIds": ["stretch-lash"]}], "taught")
	t.check(run.has_learned_ability("stretch-lash"), "the lash is not learned")


func test_lash_rings_bell_and_pulls_across_water(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("stretch-lash")
	var bell := _script_with(t, &"rung")
	var gate := _gate(t, LASH_GATE)
	if not t.check(bell != null and gate != null, "no bell or lash gate"):
		return
	var rungs: Array = []
	bell.rung.connect(func(payload: Dictionary) -> void: rungs.append(payload))
	t.teleport_player(BELL_SHORE)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	var start := player.get_centre()
	t.tap(&"stretch_lash")
	if not t.check(await t.until(func() -> bool: return player.is_ability_busy(), 100.0), "the lash did not start"):
		return
	await t.until(func() -> bool: return not rungs.is_empty(), 300.0)
	t.equal(rungs, [{"bellId": "playground-lash-bell"}], "bell rung")
	t.check(gate.is_open(), "the lash gate did not open")
	await t.until(func() -> bool: return not player.is_ability_busy(), 1500.0)
	t.check(player.get_centre().x > start.x + 80.0, "the slime was not pulled toward the bell (%s -> %s)" % [start, player.get_centre()])


func test_dummy_takes_slam_in_reach(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("squash-slam")
	var dummies := _scripts_with(t, &"hit")
	if not t.check(dummies.size() >= 3, "%d dummies" % dummies.size()):
		return
	var hits := {}
	for dummy: Node in dummies:
		var key := str(roundi((dummy.get_parent() as Node2D).global_position.x))
		hits[key] = []
		dummy.hit.connect(func(payload: Dictionary) -> void: (hits[key] as Array).append(payload))
	t.teleport_player(DUMMY_STAND)
	await t.steps(2)
	t.tap(&"squash_slam")
	await t.until(func() -> bool: return not player.is_ability_busy() and t.now() > 400.0, 1500.0)
	await t.steps(2)
	t.equal(hits.get("1480", []), [{"damage": 30.0}], "dummy 1 hit")
	t.equal(hits.get("1580", []), [{"damage": 30.0}], "dummy 2 hit (72 px)")
	t.equal(hits.get("1680", []), [], "dummy 3 (161 px) hit")


func test_goo_heart_in_level_1(t: TestContext) -> void:
	var run := Services.run()
	t.main.travel_to("level-1", "south")
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.world().map_id() == "level-1" and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
	var heart := _heart(t, "meadow-lakeside")
	if not t.check(heart != null, "no meadow-lakeside heart"):
		return
	var root := heart.get_parent() as Node2D
	t.teleport_player(root.global_position)
	await t.steps(3)
	t.check(run.has_flag("goo-heart.meadow-lakeside"), "the heart flag is not set")
	t.equal(t.player().get_max_hp(), 110, "max HP after a heart")
	t.equal(t.player().get_hp(), 110, "HP after a heart")
	t.check(heart.is_taken(), "the heart is still there")


func test_restoration_needs_materials(t: TestContext) -> void:
	var run := Services.run()
	t.main.travel_to("level-1", "south")
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.world().map_id() == "level-1" and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
	var site: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"restoration_site"):
		if str(node.get(&"flag_id")) == "workshop.restored":
			site = node
	if not t.check(site != null, "no workshop site"):
		return
	t.check(site.call(&"restore"), "a quest-locked site did nothing")
	t.check(not run.has_flag("workshop.restored"), "restored while its quest is not active")
	run.debug_active_quests.append(str(site.get(&"quest_id")))
	t.check(site.call(&"restore"), "a site without materials did nothing")
	t.check(not run.has_flag("workshop.restored"), "restored without materials")
	run.add_item("wood", 60)
	run.add_item("stone", 40)
	t.check(site.call(&"restore"), "restoring with materials failed")
	t.check(run.has_flag("workshop.restored"), "the workshop flag is not set")
	t.equal(run.item_count("wood"), 0, "wood left")
	t.equal(run.item_count("stone"), 0, "stone left")


# --- helpers ----------------------------------------------------------------------------------

func _script_with(t: TestContext, signal_name: StringName) -> Node:
	var found := _scripts_with(t, signal_name)
	return found[0] if not found.is_empty() else null


func _scripts_with(t: TestContext, signal_name: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in t.world().world_root.find_children("*", "Node", true, false):
		if node.get_script() != null and node.has_signal(signal_name) and node.get_parent() is Node2D:
			found.append(node)
	return found


func _gate(t: TestContext, gate_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"gate"):
		if str(node.get(&"gate_id")) == gate_id:
			return node
	return null


func _heart(t: TestContext, heart_id: String) -> Node:
	for node: Node in t.world().world_root.find_children("*", "Node", true, false):
		if node.has_signal(&"collected") and str(node.get(&"heart_id")) == heart_id:
			return node
	return null
