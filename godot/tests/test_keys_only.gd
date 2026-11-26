extends RefCounted
## Keys only, the one control scheme (one combat, piece 5 of docs/design/2026-11-25-weapons-beside-throws.md;
## docs/godot/MOUSE_CONTROLS.md "The keys-only scheme"): the InputMap carries its layout from the start
## (game/player/mouse/key_bindings.gd, GameSettings `apply_to_input`), the arrows walk, A swings the way the
## slime faces and a mouse click does nothing, W uses what is in reach and never a door, the interact
## prompt says "Press W", and no scheme switch is left (the F2 action, the setting). The player starts at
## level-1's spawn. These tests came from test_mouse_controls.gd, whose mouse schemes went with piece 5.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const Directions := preload("res://game/shared/directions.gd")
const GameSettings := preload("res://game/shell/game_settings.gd")
const InteractionPrompt := preload("res://game/interaction/interaction_prompt.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapeController := preload("res://game/shapes/shape_controller.gd")

## Where the slime stands below level-1's home door (tests/test_interaction.gd).
const HOME_DOOR_ARRIVAL := Vector2(270.0, 880.0)
## Open ground in level-1-c4, where the walking test starts.
const OPEN_START := Vector2(1100.0, 960.0)


func test_the_keys_layout_is_on_from_the_start(t: TestContext) -> void:
	t.equal(_keycodes(&"move_up"), [KEY_UP], "move up")
	t.equal(_keycodes(&"move_left"), [KEY_LEFT], "move left")
	t.equal(_keycodes(&"attack"), [KEY_A], "attack")
	t.equal(_keycodes(&"dodge"), [KEY_S], "the Roll")
	t.equal(_keycodes(&"ability_use"), [KEY_D], "the ability")
	t.equal(_keycodes(&"eat"), [KEY_Q], "the Gulp")
	t.equal(_keycodes(&"interact"), [KEY_W], "interact")
	t.equal(_keycodes(&"weapon_next"), [KEY_E], "next weapon")
	t.equal(_keycodes(&"weapon_previous"), [], "no key goes back")
	t.equal(_keycodes(&"potion_1"), [KEY_1], "the belt's first slot keeps project.godot's 1")
	t.equal(_keycodes(&"menu"), [KEY_B], "the bag (project.godot's)")
	t.check(not InputMap.has_action(&"control_scheme_next"), "the F2 scheme switch is still an action")
	t.check(not GameSettings.DEFAULTS.has("control_scheme"), "the settings still keep a control scheme")
	t.equal(InteractionPrompt.interact_verb(), "Press W", "the interact prompt's verb")
	await t.steps(1)


## The arrows walk; A swings the way the slime faces, wherever the pointer is; a mouse click does nothing.
func test_the_keys_play_without_the_mouse(t: TestContext) -> void:
	var shapes := _spear(t)
	if shapes == null:
		return
	var player := t.player()
	var body := t.player_body()
	t.teleport_player(OPEN_START)
	await t.steps(2)
	player._unhandled_input(InputEventMouseMotion.new())
	_key(t, KEY_RIGHT, true)
	await t.steps(3)
	var velocity := body.velocity
	_key(t, KEY_RIGHT, false)
	await t.steps(2)
	_key(t, KEY_A, true)
	_key(t, KEY_A, false)
	var swung := await t.until(func() -> bool: return shapes.is_busy(), 300.0)
	var direction := Directions.cardinal_name(player.get_facing()) if swung else ""
	await t.until(func() -> bool: return not shapes.is_busy() and not player.is_action_locked(), 2000.0)
	await t.sim_wait(1300.0)
	for button: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		for pressed: bool in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = button
			click.pressed = pressed
			player._unhandled_input(click)
	var clicked := await t.until(func() -> bool: return shapes.is_busy(), 300.0)
	t.check(velocity.x > 150.0 and absf(velocity.y) < 1.0, "the right arrow walked %s" % velocity)
	t.check(swung, "A did not swing")
	t.equal(direction, Directions.RIGHT, "the swing goes the way the slime faces")
	t.check(not clicked, "a mouse click swung")


## W uses what is in reach, never a door (beside the home door it stays).
func test_w_never_uses_a_door(t: TestContext) -> void:
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	_key(t, KEY_W, true)
	_key(t, KEY_W, false)
	await t.sim_wait(800.0)
	t.check(not t.main.is_transitioning() and t.in_world("level-1"), "W went through the home door")


static func _spear(t: TestContext) -> ShapeController:
	Services.run().learn_ability(String(ShapeDefs.SPEAR), true)
	var shapes := t.player().get_shapes()
	if not t.check(shapes != null, "the player has no ShapeController (the body-shapes mode is off)"):
		return null
	t.check(shapes.set_current(ShapeDefs.SPEAR), "the Spear could not be made current")
	return shapes


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
