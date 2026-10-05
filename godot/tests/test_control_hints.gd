extends RefCounted
## First-time control hints (game/hints/control_hints.gd; Phaser ControlHints.ts): the move hint
## first, learning by use (saved as `hint.<id>` story flags), hiding under a window, menus
## learning their hints as they open.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")


func _hints(t: TestContext) -> Node:
	return t.main.get_node("ControlHints")


func test_move_first_then_learned_by_moving(t: TestContext) -> void:
	var hints := _hints(t)
	await _frames(t)
	t.equal(hints.get(&"current"), &"move", "the first hint")
	t.equal(hints.call(&"text"), "Move with WASD", "the move hint's text")
	t.press(&"move_right")
	await t.steps(3)
	await _frames(t)
	t.release_all()
	t.check(Services.run().has_flag("hint.move"), "moving did not learn the move hint")
	t.check(hints.get(&"current") != &"move", "the move hint still shows after moving")
	t.press(&"move_right")
	t.press(&"sprint")
	await t.steps(2)
	await _frames(t)
	t.release_all()
	t.check(Services.run().has_flag("hint.sprint"), "sprinting did not learn the sprint hint")


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


func test_attack_hint_needs_a_weapon(t: TestContext) -> void:
	var hints := _hints(t)
	var run := Services.run()
	run.set_flag("hint.move")
	await _frames(t)
	var player := t.player()
	t.check(bool(hints.call(&"is_relevant", &"attack", player)) == (run.equipped_weapon_id() != null), "attack relevance follows the hand")
	if run.equipped_weapon_id() == null:
		return
	t.equal(hints.call(&"hint_text", &"attack"), "Left-click to attack", "the attack hint's text")
	t.tap(&"attack")
	await t.steps(3)
	await _frames(t)
	t.check(run.has_flag("hint.attack"), "a swing did not learn the attack hint")


## Two frames: `process_frame` fires before the nodes' `_process` of that frame.
func _frames(t: TestContext) -> void:
	await t.tree.process_frame
	await t.tree.process_frame
