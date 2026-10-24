extends RefCounted
## The barred gate (roadmap 5.22; game/scripts/barred_gate.gd; docs/godot/PROLOGUE.md "The barred
## gate"), tried first in the playground's Barred-gate corner (game/dev/corners/barred_gate_corner.tscn,
## west of the Bestiary corner: a walled yard at x 2752..3264, y 4288..4600, its gate's foot at
## (2976, 4596), a chest inside, two pots and a rock outside). The lever stands behind the bars:
## a thrown pot, a Roll or another weapon on the bars or the lever is refused (the clink and the
## line); the Spear's thrust through the bars pulls the lever, and the gate stays open after a save
## and a load. The corner is played in the body-shapes mode (the Spear is a shape): each test
## travels into the playground again with the mode on.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const MAP_ID := "playground"
const GATE_ID := "playground-barred-gate"
const GATE_FOOT := Vector2(2976, 4596)
const SAVE_SLOT := 3


func test_only_the_spear_opens_the_barred_gate_and_it_stays_open(t: TestContext) -> void:
	var run := Services.run()
	await _enter_shapes_mode(t)
	var gate := _gate(t)
	if not t.check(gate != null, "no barred gate in the playground"):
		return
	t.check(not bool(gate.call(&"is_open")), "the barred gate starts open")
	var refused: Array = []
	gate.connect(&"refused", func(payload: Dictionary) -> void: refused.append(payload))
	# The bars hold the slime back.
	t.teleport_player(GATE_FOOT + Vector2(0, 60))
	t.press(&"move_up")
	await t.sim_wait(900.0)
	t.release(&"move_up")
	t.check(t.player().get_centre().y > GATE_FOOT.y - 30.0, "the slime walked through the bars")
	# A pot thrown at the bars clinks off them.
	var pot := _liftable_near(t, Vector2(2880, 4720))
	if t.check(pot != null, "no pot by the corner"):
		t.teleport_player(pot.global_position + Vector2(0, 70))
		t.player().face(Vector2.UP)
		await t.steps(2)
		t.press(&"eat")
		await t.until(func() -> bool: return not t.player().held().is_empty(), 1500.0)
		t.release(&"eat")
		await t.steps(2)
		t.teleport_player(GATE_FOOT + Vector2(-20, 70))
		t.player().face(Vector2.UP)
		await t.steps(2)
		t.tap(&"eat")
		await t.until(func() -> bool: return not refused.is_empty(), 1500.0)
		t.check(not refused.is_empty(), "a thrown pot was not refused by the bars")
	t.check(not bool(gate.call(&"is_open")), "a thrown pot opened the gate")
	# A Roll's bonk or a sword on the lever: refused too.
	var lever := gate.get_node("Lever/LeverArea") as Area2D
	refused.clear()
	for tags: Array in [["roll"], ["weapon"], ["thrown", "rock"]]:
		_route(t, lever, tags)
	t.equal(refused.size(), 3, "the lever refused the wrong tools")
	t.check(not bool(gate.call(&"is_open")), "something else than the Spear pulled the lever")
	# The Spear's thrust through the bars.
	t.check(run.has_learned_ability(String(ShapeDefs.SPEAR)), "the shapes mode lends no Spear")
	var shapes: Variant = t.player().get_shapes()
	if shapes != null:
		(shapes as Object).call(&"set_current", ShapeDefs.SPEAR)
	t.teleport_player(GATE_FOOT + Vector2(0, -2))
	t.player().face(Vector2.UP)
	await t.steps(3)
	# (Right after a throw the slime is still busy with it: let it settle.)
	await t.sim_wait(800.0)
	var routed: Array = []
	var record := func(payload: Dictionary) -> void:
		var request: Dictionary = payload.get("request", {})
		var result: Dictionary = payload.get("result", {})
		routed.append([str(request.get("weapon_id", "")), str(result.get("status", "")), str(result.get("reason", ""))])
	Services.router().routed.connect(record)
	t.tap(&"attack")
	var opened := await t.until(func() -> bool: return bool(gate.call(&"is_open")), 1500.0)
	Services.router().routed.disconnect(record)
	t.check(routed.has(["shape-spear", "rejected", "pass"]), "the Spear did not pass the bars quietly: %s" % [routed])
	t.check(routed.has(["shape-spear", "accepted", ""]), "the Spear did not reach the lever: %s" % [routed])
	t.check(opened, "a Spear thrust through the bars did not open the gate")
	t.check(run.is_gate_unlocked(MAP_ID, GATE_ID), "the open gate is not recorded")
	await t.sim_wait(1200.0)
	t.teleport_player(GATE_FOOT + Vector2(0, 40))
	t.press(&"move_up")
	await t.until(func() -> bool: return t.player().get_centre().y < GATE_FOOT.y - 80.0, 3000.0)
	t.release(&"move_up")
	t.check(t.player().get_centre().y < GATE_FOOT.y - 80.0, "the open gate does not let the slime through")
	# Saved and loaded, it is still open.
	t.check(run.save_slot(SAVE_SLOT), "could not save")
	t.check(bool(t.main.call(&"load_run", SAVE_SLOT)), "could not load")
	await t.until(func() -> bool: return _gate(t) != null and t.player() != null, 3000.0)
	await t.steps(3)
	t.check(_gate(t) != null and bool(_gate(t).call(&"is_open")), "the gate is shut again after a load")
	run.delete_slot(SAVE_SLOT)


## The playground again with the body-shapes mode on (the test runner keeps it off).
func _enter_shapes_mode(t: TestContext) -> void:
	t.main.call(&"travel_to", MAP_ID)
	await t.until(func() -> bool: return ReworkMode.is_on() and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")) and _gate(t) != null, 3000.0)
	await t.steps(2)


func _gate(t: TestContext) -> Node2D:
	for node: Node in t.tree.get_nodes_in_group(&"barred_gate"):
		if str(node.get(&"gate_id")) == GATE_ID:
			return node as Node2D
	return null


func _liftable_near(t: TestContext, at: Vector2) -> Node2D:
	for node: Node in t.tree.get_nodes_in_group(&"liftable"):
		var root := node.get_parent() as Node2D
		if root != null and root.global_position.distance_to(at) < 12.0:
			return root
	return null


func _route(t: TestContext, area: Area2D, tags: Array) -> void:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-" + str(tags[0]), "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 20.0,
		"effects": [], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
