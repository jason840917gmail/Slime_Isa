extends RefCounted
## Ability lessons, the lash bell, training dummies, Goo Hearts and restoration sites in the
## playground (docs/godot/specs/abilities.md 19.5): the lash lesson (1904, 1520, reach 140), the
## bell on the moat island (2490, 1470) that opens `playground-lash-gate`, dummies at (1480, 1400),
## (1580, 1400), (1680, 1400). Bells are a ranged lock (owner, 2026-10-16, questions 115 and 127):
## a thrown thing or an arrow rings one, never the Spear or the Stretch Lash, which pulls on the
## bell's post. The Goo Heart and restoration tests travel into level-1, which is cut
## into chunk worlds (docs/godot/WORLD_ATLAS.md "Chunk worlds"): the meadow-lakeside heart is in chunk
## D4 (`level-1-d4`, in a chest at (1184, 314)), the workshop site in the village chunk C4 (`level-1-c4`).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const MAP_ID := "playground"
const LESSON := Vector2(1904.0, 1520.0)
## West of the lash bell, in the shallows before the lash yard's deep-water strip (x 2304-2368
## since the playground's water was repainted, 2026-10-06): the pull carries the slime across it.
const BELL_SHORE := Vector2(2285.0, 1465.0)
const LASH_GATE := "playground-lash-gate"
const DUMMY_STAND := Vector2(1480.0, 1440.0)
## Open ground west of the dummies (test_gulp.gd's hit spot), where the bell test sets a bell post
## up BELL_POST_OFFSET from the slime's centre: its damage area (84 x 104 over the post's foot)
## starts 12 px to the slime's right, within a Spear jab and a throw's first step.
const OPEN_GROUND := Vector2(1280.0, 1536.0)
const BELL_POST_OFFSET := Vector2(60.0, 25.0)
const BOW_TARGETS := &"bow_targets"
const SAVE_SLOT := 3


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


## The Lash hooks the bell's post across the water and pulls the slime over, but never rings the
## bell; a pot thrown from the shore rings it, and the bell opens its gate as before.
func test_the_lash_pulls_to_the_bell_post_without_ringing_it_and_a_pot_rings_it(t: TestContext) -> void:
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
	await t.until(func() -> bool: return not player.is_ability_busy(), 1500.0)
	t.check(player.get_centre().x > start.x + 80.0, "the slime was not pulled toward the bell post (%s -> %s)" % [start, player.get_centre()])
	t.equal(rungs, [], "the Lash rang the bell")
	t.check(not gate.is_open(), "the lash gate opened without a ring")
	# A clay pot thrown from the shore rings it.
	t.teleport_player(BELL_SHORE)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	player.get_mouth().restore({"kind": "clay-pot"})
	await t.steps(2)
	t.tap(&"eat")
	await t.until(func() -> bool: return not rungs.is_empty(), 1500.0)
	t.equal(rungs, [{"bellId": "playground-lash-bell"}], "a thrown pot did not ring the bell")
	t.check(gate.is_open(), "the rung bell did not open the lash gate")


## A thrown pot rings a bell and a Spear jab does not (owner, 2026-10-16, questions 115 and 127),
## in the body-shapes mode (the Spear is a shape). A bell post set up on open ground beside the
## slime: the Spear's jab reaches its damage area and clinks off it (refused as immune), and it
## stays silent; a pot thrown at it rings it. It also takes the coming Bow's arrow (group
## `bow_targets`, `on_arrow_hit`).
func test_a_thrown_pot_rings_a_bell_and_a_spear_jab_does_not(t: TestContext) -> void:
	await _enter_shapes_mode(t)
	var player := t.player()
	t.teleport_player(OPEN_GROUND)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	var post := t.world().spawn_at_phaser_position("object.lash-bell-post", OPEN_GROUND + BELL_POST_OFFSET)
	if not t.check(post != null, "object.lash-bell-post did not spawn"):
		return
	var bell := post.get_node_or_null(^"LashBellScript")
	var area := bell.get(&"damage_area") as Area2D if bell != null else null
	if not t.check(bell != null and area != null, "the bell post has no LashBellScript or damage area"):
		post.queue_free()
		return
	var rungs: Array = []
	bell.connect(&"rung", func(payload: Dictionary) -> void: rungs.append(payload))
	var routed: Array = []
	var record := func(payload: Dictionary) -> void:
		var request: Dictionary = payload.get("request", {})
		if request.get("target_area") == area:
			var result: Dictionary = payload.get("result", {})
			routed.append([str(request.get("weapon_id", "")), str(result.get("status", "")), str(result.get("reason", ""))])
	Services.router().routed.connect(record)
	# The Spear's jab: it reaches the bell, clinks, and the bell stays silent.
	t.check(Services.run().has_learned_ability(String(ShapeDefs.SPEAR)), "the shapes mode lends no Spear")
	var shapes: Variant = player.get_shapes()
	if shapes != null:
		(shapes as Object).call(&"set_current", ShapeDefs.SPEAR)
	await t.steps(3)
	t.tap(&"attack")
	await t.until(func() -> bool: return not routed.is_empty(), 1000.0)
	await t.sim_wait(800.0)
	t.check(routed.has(["shape-spear", "rejected", "immune"]), "the Spear's jab did not clink off the bell: %s" % [routed])
	t.equal(rungs, [], "a Spear jab rang the bell")
	# A clay pot thrown at it rings it.
	routed.clear()
	player.face(Vector2.RIGHT)
	player.get_mouth().restore({"kind": "clay-pot"})
	await t.steps(2)
	t.tap(&"eat")
	await t.until(func() -> bool: return not rungs.is_empty(), 1500.0)
	Services.router().routed.disconnect(record)
	t.equal(rungs, [{"bellId": "bell"}], "a thrown pot did not ring the bell")
	t.check(routed.has(["thrown-clay-pot", "accepted", ""]), "the pot's hit on the bell: %s" % [routed])
	# The Bow's hook: an arrow rings it too.
	t.check(bell.is_in_group(BOW_TARGETS), "the bell is not a Bow target")
	t.check(bool(bell.call(&"on_arrow_hit", {"direction": Vector2.RIGHT})), "the bell refused an arrow")
	t.equal(rungs.size(), 2, "an arrow did not ring the bell")
	post.queue_free()


## What a rung bell opens stays open for good (owner, 2026-10-16, question 136: a bell is a lock
## solved once). An arrow (the coming Bow's hook) rings the moat bell: the lash gate opens and its
## record is unlocked in RunState; the playground built again (as a chunk entered again) and a
## saved and loaded run both show it open.
func test_a_rung_bell_keeps_its_gate_open_for_good(t: TestContext) -> void:
	var run := Services.run()
	var bell := _script_with(t, &"rung")
	var gate := _gate(t, LASH_GATE)
	if not t.check(bell != null and gate != null, "no bell or lash gate"):
		return
	t.check(not gate.is_open(), "the lash gate starts open")
	t.check(bool(bell.call(&"on_arrow_hit", {"direction": Vector2.RIGHT})), "the bell refused an arrow")
	await t.steps(2)
	t.check(gate.is_open(), "the rung bell did not open the lash gate")
	t.check(run.is_gate_unlocked(MAP_ID, LASH_GATE), "the rung bell's gate is not recorded")
	# The world built again: the gate is open from the start.
	var old_world := t.world().world_root.get_instance_id()
	if not t.check(t.main.travel_to(MAP_ID), "travelling to %s again was refused" % MAP_ID):
		return
	var rebuilt := await t.until(func() -> bool:
		return t.world().world_root != null and t.world().world_root.get_instance_id() != old_world \
			and t.player() != null and not t.main.is_transitioning() and _gate(t, LASH_GATE) != null, 3000.0, 6000.0)
	if not t.check(rebuilt, "%s was not built again" % MAP_ID):
		return
	await t.steps(2)
	t.check(_gate(t, LASH_GATE).is_open(), "the lash gate is shut again after the world was built again")
	# Saved and loaded: still open.
	t.check(run.save_slot(SAVE_SLOT), "could not save")
	var saved_world := t.world().world_root.get_instance_id()
	t.check(bool(t.main.call(&"load_run", SAVE_SLOT)), "could not load")
	var loaded := await t.until(func() -> bool:
		return t.world().world_root != null and t.world().world_root.get_instance_id() != saved_world \
			and t.player() != null and not t.main.is_transitioning() and _gate(t, LASH_GATE) != null, 3000.0, 6000.0)
	await t.steps(3)
	t.check(loaded and _gate(t, LASH_GATE).is_open(), "the lash gate is shut again after a load")
	run.delete_slot(SAVE_SLOT)


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
	# The lakeside heart (its old name) lies in D4's old pen since 2026-10-17.
	t.main.travel_to("level-1-d4", "south")
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.world().map_id() == "level-1-d4" and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
	var heart := t.world().world_root.get_node("Chapter1/heart-chest-meadow-lakeside/ChestScript")
	if not t.check(heart != null, "no meadow-lakeside heart"):
		return
	var root := heart.get_parent() as Node2D
	t.teleport_player(root.global_position - Vector2(0, 10))
	heart.call(&"request_open")
	await t.steps(3)
	t.check(run.has_flag("goo-heart.meadow-lakeside"), "the heart flag is not set")
	t.equal(t.player().get_max_hp(), 110, "max HP after a heart")
	t.equal(t.player().get_hp(), 110, "HP after a heart")
	t.check(heart.is_empty(), "the heart chest is not empty")


func test_restoration_needs_materials(t: TestContext) -> void:
	var run := Services.run()
	# A travel to level-1 lands in the chunk of its south entry, the village chunk.
	t.main.travel_to("level-1", "south")
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.world().map_id() == "level-1-c4" and t.player() != null, 3000.0, 6000.0)
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

## The playground again with the body-shapes mode on (the test runner keeps it off;
## test_barred_gate.gd does the same).
func _enter_shapes_mode(t: TestContext) -> void:
	t.main.call(&"travel_to", MAP_ID)
	await t.until(func() -> bool: return ReworkMode.is_on() and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")), 3000.0)
	await t.steps(2)


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
