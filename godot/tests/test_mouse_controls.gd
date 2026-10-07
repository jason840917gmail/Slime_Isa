extends RefCounted
## The mouse control schemes (game/player/mouse/control_scheme.gd, docs/godot/MOUSE_CONTROLS.md):
## a click order walks around a wall to its point, a click on the ground gives a walk order to the
## pointer, an attack order walks into weapon reach and swings, a use order walks to the
## home door and goes through it, the movement keys cancel an order, and the scheme setting keeps
## to its three values. The player starts at level-1's spawn (centre (640, 704)); the ground right
## and up-right of it is open.
## Tests that switch the scheme switch it back to the keyboard one before they wait on anything
## (the Shell's settings outlive the test).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const Directions := preload("res://game/shared/directions.gd")
const GameSettings := preload("res://game/shell/game_settings.gd")
const ControlScheme := preload("res://game/player/mouse/control_scheme.gd")
const ClickOrders := preload("res://game/player/mouse/click_orders.gd")
const PointerTargets := preload("res://game/player/mouse/pointer_targets.gd")
const InteractionPrompt := preload("res://game/interaction/interaction_prompt.gd")

## level-1's home door pick point (origin (1081, 903) - 24) and the slime-home it leads to.
const HOME_DOOR_PICK := Vector2(1081.0, 879.0)
## Where the slime stands beside the home door, in its reach (tests/test_interaction.gd).
const HOME_DOOR_ARRIVAL := Vector2(1083.0, 954.0)


func test_walk_order_goes_around_a_wall(t: TestContext) -> void:
	var body := t.player_body()
	var start := body.global_position
	# A 20 x 160 wall 100 px to the right, centred on the slime: the straight line is blocked.
	_add_wall(t, start + Vector2(100.0, 0.0), Vector2(20.0, 160.0))
	await t.steps(2)
	var goal := start + Vector2(220.0, 0.0)
	var orders := t.player().get_click_orders()
	orders.move_to(goal)
	if not t.check(await t.until(func() -> bool: return not orders.is_active(), 4000.0),
			"the walk order did not finish within 4 s (feet %s)" % [body.global_position]):
		return
	t.near_vec(body.global_position, goal, 8.0, "feet at the goal behind the wall")


## The headless window is 64 x 64 px: the HUD covers all of it and takes a pushed click, and a
## pushed motion does not move the pointer the game reads. So the click goes to the player's input
## handler straight away, and the walk ends where the pointer reads.
## A long upright wall with a gap barely taller than the body (26 px; 27.4 and 29 px gaps, off the
## path grid; routes keep half a pixel off walls) between the slime and its goal: the route goes
## through the gap, and the slime walks through the wider one.
func test_route_threads_a_gap_the_body_fits(t: TestContext) -> void:
	var body := t.player_body()
	var start := body.global_position
	var orders := t.player().get_click_orders()
	var goal := start + Vector2(220.0, 0.0)
	for gap: float in [27.4, 29.0]:
		# The body's centre is 13 above its feet; the gap's 5 lower still.
		var walls := _add_wall_with_gap(t, Vector2(start.x + 120.0, start.y - 8.0), gap, 1200.0)
		await t.steps(2)
		var started := Time.get_ticks_usec()
		var route: Dictionary = orders.path.find(body.global_position, goal, t.now())
		t.notes.append("%.1f px gap route planned in %.1f ms" % [gap, (Time.get_ticks_usec() - started) / 1000.0])
		t.check(bool(route["complete"]), "%.1f px gap: no complete route" % gap)
		var length := 0.0
		var from := body.global_position
		for point: Vector2 in route["points"]:
			length += from.distance_to(point)
			from = point
		t.check(length < start.distance_to(goal) + 40.0, "%.1f px gap: the route goes around (%.0f px: %s)" % [gap, length, route["points"]])
		if gap > 28.0:
			orders.move_to(goal)
			if t.check(await t.until(func() -> bool: return not orders.is_active(), 3000.0),
					"the walk through the %.1f px gap did not finish (feet %s)" % [gap, body.global_position]):
				t.near_vec(body.global_position, goal, 8.0, "feet past the gap")
		for wall: Node in walls:
			wall.free()
		await t.steps(2)


## A goal walled in on every side: the search gives up within its time budget.
func test_unreachable_goal_stays_within_the_budget(t: TestContext) -> void:
	var body := t.player_body()
	var start := body.global_position
	var box := start + Vector2(220.0, -13.0)
	for side: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var size := Vector2(20.0, 140.0) if side.y == 0.0 else Vector2(140.0, 20.0)
		_add_wall(t, box + side * 60.0, size)
	await t.steps(2)
	var path := t.player().get_click_orders().path
	var started := Time.get_ticks_usec()
	var route: Dictionary = path.find(start, start + Vector2(220.0, 0.0), t.now())
	var spent := (Time.get_ticks_usec() - started) / 1000.0
	t.notes.append("unreachable goal: %.1f ms, %d nodes" % [spent, int(route.get("expansions", 0))])
	t.check(not bool(route["complete"]), "a route through a wall")
	t.check(spent < path.max_ms * 2.0, "the search took %.1f ms (budget %.0f ms)" % [spent, path.max_ms])


func test_click_on_the_ground_walks_there(t: TestContext) -> void:
	var body := t.player_body()
	var goal := body.get_global_mouse_position()
	_use_scheme(ControlScheme.CLICK)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		t.player()._unhandled_input(click)
	_use_scheme(ControlScheme.KEYBOARD)
	await t.steps(2)
	var orders := t.player().get_click_orders()
	t.equal(orders.kind, ClickOrders.Kind.MOVE, "order kind after a click on the ground")
	t.near_vec(orders.goal, goal, 0.01, "order goal: the pointer")
	var start_distance := body.global_position.distance_to(goal)
	if not t.check(await t.until(func() -> bool: return not orders.is_active(), 3000.0),
			"the click did not walk the slime there within 3 s (feet %s)" % [body.global_position]):
		return
	# The point the headless pointer reads lies in a prop near the spawn: the slime stops at the
	# nearest open spot, within two path cells.
	t.between(body.global_position.distance_to(goal), 0.0, 32.0, "distance left to the clicked point")
	t.check(body.global_position.distance_to(goal) < start_distance * 0.6, "the slime hardly moved toward the click")


func test_movement_keys_cancel_an_order(t: TestContext) -> void:
	var orders := t.player().get_click_orders()
	orders.move_to(t.player_body().global_position + Vector2(300.0, 0.0))
	await t.steps(5)
	t.check(t.player().is_click_moving(), "the order is not walking")
	t.press(&"move_up")
	await t.steps(2)
	t.release(&"move_up")
	t.check(not orders.is_active(), "a movement key left the order active")


func test_attack_order_walks_into_reach_and_swings(t: TestContext) -> void:
	var worm := t.spawn_worm(Vector2(180.0, 0.0), true)
	if worm == null:
		return
	await t.steps(1)
	var hits: Array = []
	t.listen(Services.router().routed, func(payload: Dictionary) -> void:
		var request: Dictionary = payload.get("request", {})
		if request.get("target_area") == worm.damage_area:
			hits.append(t.now()))
	var start_x := t.player().get_centre().x
	var orders := t.player().get_click_orders()
	orders.attack(worm, func() -> Vector2: return PointerTargets.feet_of(worm))
	if not t.check(await t.until(func() -> bool: return not hits.is_empty(), 3000.0),
			"the attack order routed no hit to the worm within 3 s (centre %s)" % [t.player().get_centre()]):
		return
	t.check(t.player().get_centre().x > start_x + 60.0, "the slime did not walk toward the worm")
	t.equal(Directions.cardinal_name(t.player().get_facing()), Directions.RIGHT, "facing when it swung")
	await t.until(func() -> bool: return not orders.is_active(), 2000.0)
	t.check(not orders.is_active(), "the order (button up) went on after its swing")


func test_use_order_walks_through_the_home_door(t: TestContext) -> void:
	await t.steps(2)
	var interaction := t.main.get_tree().get_first_node_in_group(&"interaction")
	var door: Dictionary = interaction.call(&"target_at", HOME_DOOR_PICK)
	if not t.check(str(door.get("id", "")) == "world-doors:home-door", "the door under the pointer: %s" % [door.get("id")]):
		return
	var orders := t.player().get_click_orders()
	orders.interact(interaction.call(&"key_of", door), door["origin"])
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == "slime-home" and t.player() != null, 8000.0, 16000.0)
	t.check(arrived, "the use order did not take the slime through the home door within 8 s")


## The click scheme's right button swings in place (an `attack` press), with no order.
## Swinging in place: the moba scheme's left button and the click scheme's Shift + left click. The
## click scheme's right button uses things and never swings.
func test_swing_buttons_swing_in_place(t: TestContext) -> void:
	await t.steps(2)
	var combat := t.player().get_combat()
	var cases: Array = [
		[ControlScheme.MOBA, MOUSE_BUTTON_LEFT, false, true, "moba left click"],
		[ControlScheme.CLICK, MOUSE_BUTTON_LEFT, true, true, "click scheme Shift + left click"],
		[ControlScheme.CLICK, MOUSE_BUTTON_RIGHT, false, false, "click scheme right click"],
	]
	for entry: Array in cases:
		_use_scheme(entry[0])
		_click_button(t, entry[1], entry[2])
		_use_scheme(ControlScheme.KEYBOARD)
		var swung := await t.until(func() -> bool: return combat.is_attacking(), 300.0)
		t.equal(swung, bool(entry[3]), "%s swings" % entry[4])
		t.check(not t.player().get_click_orders().is_active(), "%s gave an order" % entry[4])
		await t.until(func() -> bool: return not combat.is_attacking() and not t.player().is_action_locked(), 2000.0)
		await t.sim_wait(1300.0)


## The click scheme's right button with nothing usable under the pointer uses what is in reach, as
## the keyboard scheme's does: beside the home door, it goes through it.
func test_click_scheme_right_click_uses_what_is_in_reach(t: TestContext) -> void:
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	_use_scheme(ControlScheme.CLICK)
	_click_button(t, MOUSE_BUTTON_RIGHT, false)
	_use_scheme(ControlScheme.KEYBOARD)
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == "slime-home" and t.player() != null, 3000.0, 6000.0)
	t.check(arrived, "the right click did not use the home door")


## The pointer scheme: the slime turns to the pointer, W walks toward it, S does not move it, nor
## does a click (the left button swings toward the pointer).
func test_pointer_scheme_faces_the_pointer_and_w_walks_there(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	_use_scheme(ControlScheme.POINTER)
	player._unhandled_input(InputEventMouseMotion.new())
	await t.steps(2)
	var aim := _pointer_aim(t)
	t.check(player.get_facing().dot(aim) > 0.99, "facing %s, not the pointer %s" % [player.get_facing(), aim])
	t.press(&"move_down")
	await t.steps(3)
	t.release(&"move_down")
	t.near_vec(body.velocity, Vector2.ZERO, 0.01, "S moved the slime")
	t.press(&"move_up")
	await t.steps(3)
	var velocity := body.velocity
	aim = _pointer_aim(t)
	t.release(&"move_up")
	t.check(velocity.length() > 150.0 and velocity.normalized().dot(aim) > 0.99, "W walks %s, not toward the pointer %s" % [velocity, aim])
	await t.steps(2)
	_click_button(t, MOUSE_BUTTON_LEFT, false)
	await t.steps(2)
	t.check(player.get_combat().is_attacking(), "the left button did not swing")
	t.near_vec(body.velocity, Vector2.ZERO, 0.01, "a click moved the slime")
	t.check(not player.get_click_orders().is_active(), "a click gave an order")
	_use_scheme(ControlScheme.KEYBOARD)


## The keys-only scheme rebinds the InputMap (arrows walk, A attacks, W interacts, S / D switch
## weapons, no mouse) and another scheme puts every event back.
func test_keys_scheme_rebinds_the_keys_and_puts_them_back(t: TestContext) -> void:
	var actions: Array[StringName] = [&"move_up", &"move_left", &"attack", &"interact", &"weapon_next", &"weapon_previous"]
	var before := {}
	for action: StringName in actions:
		before[action] = InputMap.action_get_events(action)
	_use_scheme(ControlScheme.KEYS)
	var bound := {}
	for action: StringName in actions:
		bound[action] = _keycodes(action)
	_use_scheme(ControlScheme.KEYBOARD)
	t.equal(bound[&"move_up"], [KEY_UP], "move up")
	t.equal(bound[&"move_left"], [KEY_LEFT], "move left")
	t.equal(bound[&"attack"], [KEY_A], "attack")
	t.equal(bound[&"interact"], [KEY_W], "interact")
	t.equal(bound[&"weapon_next"], [KEY_D], "next weapon")
	t.equal(bound[&"weapon_previous"], [KEY_S], "previous weapon")
	for action: StringName in actions:
		t.equal(InputMap.action_get_events(action), before[action], "%s put back" % action)
	await t.steps(1)


## Keys only: the arrows walk; A swings the way the slime faces, wherever the pointer is; a mouse
## click does nothing.
func test_keys_scheme_plays_without_the_mouse(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	var combat := player.get_combat()
	_use_scheme(ControlScheme.KEYS)
	player._unhandled_input(InputEventMouseMotion.new())
	_key(t, KEY_RIGHT, true)
	await t.steps(3)
	var velocity := body.velocity
	_key(t, KEY_RIGHT, false)
	await t.steps(2)
	_key(t, KEY_A, true)
	_key(t, KEY_A, false)
	var swung := await t.until(func() -> bool: return combat.is_attacking(), 300.0)
	var direction := combat.get_weapon().get_active_direction() if swung else ""
	await t.until(func() -> bool: return not combat.is_attacking() and not player.is_action_locked(), 2000.0)
	await t.sim_wait(1300.0)
	_click_button(t, MOUSE_BUTTON_LEFT, false)
	var clicked := await t.until(func() -> bool: return combat.is_attacking(), 300.0)
	_use_scheme(ControlScheme.KEYBOARD)
	t.check(velocity.x > 150.0 and absf(velocity.y) < 1.0, "the right arrow walked %s" % velocity)
	t.check(swung, "A did not swing")
	t.equal(direction, Directions.RIGHT, "the swing goes the way the slime faces, not to the pointer")
	t.check(not clicked, "a mouse click swung")


## Keys only: W uses what is in reach (beside the home door, it goes through it).
func test_keys_scheme_w_uses_what_is_in_reach(t: TestContext) -> void:
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	_use_scheme(ControlScheme.KEYS)
	_key(t, KEY_W, true)
	_key(t, KEY_W, false)
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == "slime-home" and t.player() != null, 3000.0, 6000.0)
	_use_scheme(ControlScheme.KEYBOARD)
	t.check(arrived, "W did not use the home door")


func test_prompt_verb_follows_the_scheme(t: TestContext) -> void:
	_use_scheme(ControlScheme.CLICK)
	var click_verb := InteractionPrompt.interact_verb()
	_use_scheme(ControlScheme.MOBA)
	var moba_verb := InteractionPrompt.interact_verb()
	_use_scheme(ControlScheme.POINTER)
	var pointer_verb := InteractionPrompt.interact_verb()
	_use_scheme(ControlScheme.KEYS)
	var keys_verb := InteractionPrompt.interact_verb()
	_use_scheme(ControlScheme.KEYBOARD)
	t.equal(keys_verb, "Press W", "keys scheme verb")
	t.equal(click_verb, "Click", "click scheme verb")
	t.equal(moba_verb, "Right-click", "moba scheme verb")
	t.equal(pointer_verb, "Right-click", "pointer scheme verb")
	t.equal(InteractionPrompt.interact_verb(), "Right-click", "keyboard scheme verb")
	await t.steps(1)


func test_scheme_setting_values(t: TestContext) -> void:
	t.equal(GameSettings.parse({"control_scheme": "click"})["control_scheme"], "click", "click")
	t.equal(GameSettings.parse({"control_scheme": "moba"})["control_scheme"], "moba", "moba")
	t.equal(GameSettings.parse({"control_scheme": "joystick"})["control_scheme"], "keyboard", "unknown -> keyboard")
	t.equal(ControlScheme.next(ControlScheme.KEYBOARD), ControlScheme.CLICK, "keyboard -> click")
	t.equal(ControlScheme.next(ControlScheme.MOBA), ControlScheme.POINTER, "moba -> pointer")
	t.equal(ControlScheme.next(ControlScheme.POINTER), ControlScheme.KEYS, "pointer -> keys")
	t.equal(ControlScheme.next(ControlScheme.KEYS), ControlScheme.KEYBOARD, "keys -> keyboard")
	t.equal(GameSettings.parse({"control_scheme": "keys"})["control_scheme"], "keys", "keys")
	t.check(not ControlScheme.uses_mouse(ControlScheme.KEYS), "the keys scheme uses the mouse")
	t.equal(GameSettings.parse({"control_scheme": "pointer"})["control_scheme"], "pointer", "pointer")
	t.equal(ControlScheme.order_button(ControlScheme.MOBA), MOUSE_BUTTON_RIGHT, "moba orders with the right button")
	t.equal(ControlScheme.swing_button(ControlScheme.CLICK), MOUSE_BUTTON_NONE, "the click scheme has no swing button")
	t.equal(ControlScheme.use_button(ControlScheme.CLICK), MOUSE_BUTTON_RIGHT, "the click scheme uses with the right button")
	t.check(not ControlScheme.uses_orders(ControlScheme.POINTER), "the pointer scheme gives orders")
	await t.steps(1)


# --- helpers -------------------------------------------------------------------------------------

## A press and release of `button` (Shift held when `shift`), handed to the player's input handler
## (the headless window's HUD would take a pushed click).
func _click_button(t: TestContext, button: MouseButton, shift: bool) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.pressed = pressed
		click.shift_pressed = shift
		t.player()._unhandled_input(click)


## A key press or release (physical `keycode`) handed to the player's input handler.
func _key(t: TestContext, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	t.player()._unhandled_input(event)


## The physical keycodes bound to `action` (0 for a non-key event).
static func _keycodes(action: StringName) -> Array:
	var codes: Array = []
	for event: InputEvent in InputMap.action_get_events(action):
		codes.append((event as InputEventKey).physical_keycode if event is InputEventKey else 0)
	return codes


## The unit vector from the slime's aim origin to the pointer.
func _pointer_aim(t: TestContext) -> Vector2:
	var player := t.player()
	var origin := player.get_centre() - Vector2(0.0, player.aim_rise_px)
	return (t.player_body().get_global_mouse_position() - origin).normalized()


func _use_scheme(scheme: String) -> void:
	Services.shell().get_settings().update({"control_scheme": scheme})


## A 20 px thick upright wall `length` long centred on `gap_centre`, with a `gap` tall opening
## there. Returns its two bodies.
func _add_wall_with_gap(t: TestContext, gap_centre: Vector2, gap: float, length: float) -> Array[Node]:
	var walls: Array[Node] = []
	var half := length * 0.5
	for side: float in [-1.0, 1.0]:
		var inner := gap_centre.y + side * gap * 0.5
		var outer := gap_centre.y + side * half
		walls.append(_add_wall(t, Vector2(gap_centre.x, (inner + outer) * 0.5), Vector2(20.0, absf(outer - inner))))
	return walls


func _add_wall(t: TestContext, centre: Vector2, size: Vector2) -> Node:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	wall.position = centre
	t.world().world_root.add_child(wall)
	return wall
