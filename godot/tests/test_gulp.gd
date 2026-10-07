extends RefCounted
## Gulp forms and their puzzles in the playground (docs/godot/specs/abilities.md 19.5): the stone
## spot (1120, 800, reach 100) gives Heavy; Heavy holds the heavy plate (1344, 780, reach 44)
## which opens `playground-heavy-gate`; a Heavy jump landing on the cracked ground (1600, 1040,
## reach 52) breaks it; the silk spot (680, 1660) gives Sticky.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const MAP_ID := "playground"
const STONE_SPOT_STAND := Vector2(1120.0, 860.0)
const SILK_SPOT_STAND := Vector2(680.0, 1720.0)
const HEAVY_PLATE := Vector2(1344.0, 780.0)
const HEAVY_GATE := "playground-heavy-gate"
const CRACKED := Vector2(1600.0, 1040.0)
const CRACK_FLAG := "cracked.playground-sinkhole"


func test_eat_at_stone_spot_gives_heavy(t: TestContext) -> void:
	var player := t.player()
	t.teleport_player(STONE_SPOT_STAND)
	await t.steps(2)
	t.check(player.nearest_gulp_spot() != null, "no Gulp spot in reach at the stone spot")
	t.tap(&"eat")
	if not t.check(await t.until(func() -> bool: return player.current_form_id() == &"heavy", 300.0), "no Heavy form"):
		return
	t.near(player.form_remaining_ms(), 60000.0, 40.0, "form time left")
	t.check(player.is_action_locked(), "the eat clip did not lock actions")
	t.check(player.presses_plates(), "Heavy does not press plates")


func test_heavy_walks_slower_and_ignores_knockback(t: TestContext) -> void:
	var player := t.player()
	await _become_heavy(t)
	await t.sim_wait(300.0)
	t.teleport_player(Vector2(1280.0, 1536.0))
	t.press(&"move_right")
	await t.steps(4)
	t.near(t.player_body().velocity.x, 120.0, 0.01, "Heavy walk speed")
	t.release_all()
	await t.steps(2)
	player.apply_knockback(Vector2.RIGHT, 260.0, 160.0)
	await t.steps(1)
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.01, "velocity after a knockback on Heavy")
	t.check(not player.is_movement_suppressed(), "Heavy was knocked back")


func test_heavy_plate_opens_gate(t: TestContext) -> void:
	await _become_heavy(t)
	var plate := _script_near(t, &"pressed", HEAVY_PLATE)
	var gate := _gate(t, HEAVY_GATE)
	if not t.check(plate != null and gate != null, "no heavy plate or gate"):
		return
	var presses: Array = []
	plate.pressed.connect(func(payload: Dictionary) -> void: presses.append(payload))
	await t.sim_wait(200.0)
	t.teleport_player(HEAVY_PLATE + Vector2(0.0, 20.0))
	await t.steps(3)
	t.equal(presses, [{"plateId": "playground-heavy-plate"}], "plate presses")
	t.check(gate.is_open(), "the heavy gate did not open")
	t.equal(plate.visual.frame, 7, "pressed plate frame")


func test_light_slime_does_not_press(t: TestContext) -> void:
	var plate := _script_near(t, &"pressed", HEAVY_PLATE)
	if not t.check(plate != null, "no heavy plate"):
		return
	t.teleport_player(HEAVY_PLATE + Vector2(0.0, 20.0))
	await t.steps(3)
	t.check(not plate.is_down(), "a slime without a form pressed the plate")


func test_heavy_jump_breaks_cracked_ground(t: TestContext) -> void:
	var run := Services.run()
	run.learn_ability("jump")
	await _become_heavy(t)
	await t.sim_wait(300.0)
	t.teleport_player(CRACKED + Vector2(0.0, 20.0))
	await t.steps(3)
	t.check(not run.has_flag(CRACK_FLAG), "standing Heavy cracked the ground")
	t.tap(&"jump")
	await t.until(func() -> bool: return run.has_flag(CRACK_FLAG), 1000.0)
	t.check(run.has_flag(CRACK_FLAG), "a Heavy jump landing did not crack the ground")


func test_burp_and_sticky_switch(t: TestContext) -> void:
	var player := t.player()
	await _become_heavy(t)
	await t.sim_wait(300.0)
	t.teleport_player(Vector2(1280.0, 1536.0))
	await t.steps(2)
	t.tap(&"eat")
	await t.until(func() -> bool: return player.current_form_id() == &"", 300.0)
	t.equal(player.current_form_id(), &"", "form after a burp")
	await t.sim_wait(300.0)
	t.teleport_player(SILK_SPOT_STAND)
	await t.steps(2)
	t.tap(&"eat")
	await t.until(func() -> bool: return player.current_form_id() == &"sticky", 300.0)
	t.check(player.is_sticky_form() and player.crosses_webs(), "no Sticky form at the silk spot")


func test_nothing_to_gulp(t: TestContext) -> void:
	var player := t.player()
	t.teleport_player(Vector2(1280.0, 1536.0))
	await t.steps(2)
	t.tap(&"eat")
	await t.steps(4)
	t.equal(player.current_form_id(), &"", "form away from spots")
	t.check(not player.is_action_locked(), "the eat clip played for nothing")


# --- helpers ----------------------------------------------------------------------------------

func _become_heavy(t: TestContext) -> void:
	t.teleport_player(STONE_SPOT_STAND)
	await t.steps(2)
	t.tap(&"eat")
	await t.until(func() -> bool: return t.player().current_form_id() == &"heavy", 300.0)


## The script with signal `signal_name` whose parent is nearest `at`.
func _script_near(t: TestContext, signal_name: StringName, at: Vector2) -> Node:
	var best: Node = null
	var best_distance := INF
	for node: Node in t.world().world_root.find_children("*", "Node", true, false):
		if not node.has_signal(signal_name) or not node.get_parent() is Node2D:
			continue
		var distance := (node.get_parent() as Node2D).global_position.distance_to(at)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best if best_distance < 64.0 else null


func _gate(t: TestContext, gate_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"gate"):
		if str(node.get(&"gate_id")) == gate_id:
			return node
	return null


func test_quick_wheel_eats_from_the_bag(t: TestContext) -> void:
	var player := t.player()
	var run := Services.run()
	run.add_item("stone", 3)
	run.add_item("silk-clump", 2)
	t.teleport_player(Vector2(1280.0, 1536.0))
	await t.steps(2)
	t.press(&"eat")
	await t.sim_wait(320.0)
	var wheel: Node = player.get_gulp_wheel()
	if not t.check(wheel != null and bool(wheel.call(&"is_open")), "the quick wheel did not open after a 250 ms hold"):
		t.release_all()
		return
	t.equal((wheel.get(&"entries") as Array).size(), 2, "wheel entries (stone, silk)")
	t.equal(wheel.call(&"title_text"), "HEAVY", "the preferred material (stone) is chosen first")
	t.press(&"move_down")
	await t.steps(2)
	t.equal(wheel.call(&"title_text"), "STICKY", "down picks the bottom slot")
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.01, "the slime stands still while the wheel is open")
	t.release(&"move_down")
	t.release(&"eat")
	await t.until(func() -> bool: return player.current_form_id() == &"sticky", 300.0)
	t.equal(player.current_form_id(), &"sticky", "the release eats the chosen material")
	t.equal(run.item_count("silk-clump"), 1, "silk left after eating one")
	t.check(not bool(wheel.call(&"is_open")), "the wheel stays open after the release")


func test_long_hold_with_nothing_carried_does_nothing(t: TestContext) -> void:
	var player := t.player()
	t.teleport_player(STONE_SPOT_STAND)
	await t.steps(2)
	t.press(&"eat")
	await t.sim_wait(320.0)
	t.release(&"eat")
	await t.sim_wait(100.0)
	t.equal(player.current_form_id(), &"", "a long hold with nothing carried ate the spot (Phaser does nothing)")
	t.check(player.get_gulp_wheel() == null or not bool(player.get_gulp_wheel().call(&"is_open")), "a wheel opened with nothing carried")


## The form skin (form_skin.gdshader on the Visual): Heavy paints cobbles (skin 1), Sticky silk
## (skin 2), the end of a form clears it; the tint fallback stays off.
func test_form_skin_follows_the_form(t: TestContext) -> void:
	var player := t.player()
	var visual := player.visual as CanvasItem
	var skin_material := visual.material as ShaderMaterial
	if not t.check(skin_material != null, "the Visual has no skin material"):
		return
	var run := Services.run()
	run.add_item("stone", 1)
	run.add_item("silk-clump", 1)
	player.get_gulp().eat_material("stone")
	t.equal(int(skin_material.get_shader_parameter(&"skin")), 1, "Heavy's skin")
	t.equal(visual.self_modulate, Color.WHITE, "no tint over the skin")
	player.get_gulp().eat_material("silk-clump")
	t.equal(int(skin_material.get_shader_parameter(&"skin")), 2, "Sticky's skin")
	player.get_gulp().end("burp")
	t.equal(int(skin_material.get_shader_parameter(&"skin")), 0, "no skin after the form")
