extends RefCounted
## First-time control hints (game/hints/control_hints.gd; Phaser ControlHints.ts): the move hint
## first, learning by use (saved as `hint.<id>` story flags), hiding under a window, menus
## learning their hints as they open.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")


func _hints(t: TestContext) -> Node:
	return t.main.get_node("ControlHints")


func test_move_first_then_learned_by_moving(t: TestContext) -> void:
	var hints := _hints(t)
	await _frames(t)
	t.equal(hints.get(&"current"), &"move", "the first hint")
	t.equal(hints.call(&"text"), "Move with %s" % ControlLabels.movement_label(), "the move hint's text")
	t.press(&"move_right")
	await t.steps(3)
	await _frames(t)
	t.release_all()
	t.check(Services.run().has_flag("hint.move"), "moving did not learn the move hint")
	t.check(hints.get(&"current") != &"move", "the move hint still shows after moving")
	# No sprint hint since 2026-10-08 (no sprint from the start).
	var hint_ids: Array = (hints.get_script() as Script).get_script_constant_map()["HINT_IDS"]
	t.check(not hint_ids.has(&"sprint"), "the sprint hint is back")


func test_hidden_under_a_window_and_menus_learn(t: TestContext) -> void:
	var hints := _hints(t)
	var world := Services.world()
	world.set_pause_reason(Services.WorldServiceType.PAUSE_MODAL, true)
	await _frames(t)
	t.equal(hints.get(&"current"), &"", "a hint shows under a window")
	world.set_pause_reason(Services.WorldServiceType.PAUSE_MODAL, false)
	await _frames(t)
	t.equal(hints.get(&"current"), &"move", "the hint did not come back after the window")
	var windows: Node = t.main.get_node("GameWindows")
	windows.call(&"push", hints, &"inventory", true)
	windows.call(&"pop", hints, true)
	t.check(Services.run().has_flag("hint.inventory"), "opening the bag did not learn the bag hint")


## The rework mode (on in every world; control_hints.gd "Body-shapes rework mode"): the attack hint
## is useful while a shape is current, and a shape step learns it (one combat: the attack key strikes
## with the weapon beside the throw rules).
func test_attack_hint_needs_a_shape(t: TestContext) -> void:
	var hints := _hints(t)
	var run := Services.run()
	run.set_flag("hint.move")
	await _frames(t)
	var player := t.player()
	t.check(not bool(hints.call(&"is_relevant", &"attack", player)), "the attack hint is useful without a shape")
	run.learn_session_ability(String(ShapeDefs.SPEAR))
	var shapes: Object = player.get_shapes()
	if not t.check(shapes != null and bool(shapes.call(&"set_current", ShapeDefs.SPEAR)), "the Spear could not be made current"):
		return
	await _frames(t)
	t.check(bool(hints.call(&"is_relevant", &"attack", player)), "the attack hint is not useful with the Spear current")
	t.equal(hints.call(&"hint_text", &"attack"), "%s to attack" % ControlLabels.control_verb(&"attack"),
		"the attack hint's text")
	t.equal(ControlLabels.control_verb(&"attack"), "Press A", "the attack's key in the keys-only default")
	t.tap(&"attack")
	await t.until(func() -> bool: return bool(shapes.call(&"is_busy")), 300.0)
	await _frames(t)
	t.check(run.has_flag("hint.attack"), "a Spear strike did not learn the attack hint")


## Two frames: `process_frame` fires before the nodes' `_process` of that frame.
func _frames(t: TestContext) -> void:
	await t.tree.process_frame
	await t.tree.process_frame
