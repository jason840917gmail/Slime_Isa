extends RefCounted
## Player movement and dodge (docs/godot/specs/player.md section 2 values, 4.3 move, 5 dodge).
## Walk 200 px/s, sprint 300 px/s, diagonals normalised; dodge 380 px/s for 500 ms (190 px),
## i-frames for the first 400 ms, next dodge 750 ms after the roll start.
## The player starts at level-1's spawn (centre (640, 704)); the ground to the right and up-right
## of it is open for the distances used here (a prop sits down-right).

const TestContext := preload("res://tests/lib/test_context.gd")
const SquashStretch := preload("res://game/player/squash_stretch.gd")

const WALK_SPEED := 200.0
const SPRINT_SPEED := 300.0
const DODGE_SPEED := 380.0
const DODGE_DURATION_MS := 500.0
const DODGE_IFRAMES_MS := 400.0
const DODGE_COOLDOWN_FROM_START_MS := 750.0
const MEASURE_STEPS := 30


func test_walk_speed_is_200(t: TestContext) -> void:
	await _check_speed(t, [&"move_right"], Vector2.RIGHT, WALK_SPEED, "walk right")


func test_walk_diagonal_is_normalised(t: TestContext) -> void:
	await _check_speed(t, [&"move_right", &"move_up"], Vector2(1, -1).normalized(), WALK_SPEED, "walk up-right")


func test_sprint_speed_is_300(t: TestContext) -> void:
	await _check_speed(t, [&"sprint", &"move_right"], Vector2.RIGHT, SPRINT_SPEED, "sprint right")


func test_sprint_diagonal_is_normalised(t: TestContext) -> void:
	await _check_speed(t, [&"sprint", &"move_right", &"move_up"], Vector2(1, -1).normalized(), SPRINT_SPEED, "sprint up-right")


## A diagonal walk into a wall slides along it at the tangential speed, and the blocked velocity
## component reads back as zero, as Phaser's Arcade separation does (player spec 5.2). Godot's
## floating `move_and_slide()` would slide at the full 200 px/s and keep the velocity, which is why
## every body moves with `ArcadeMover` (res://game/shared/arcade_mover.gd).
func test_diagonal_walk_slides_along_a_wall_like_arcade(t: TestContext) -> void:
	var body := t.player_body()
	var body_shape := body.get_node("BodyShape") as CollisionShape2D
	var top := body_shape.global_position.y - (body_shape.shape as RectangleShape2D).size.y * 0.5
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(800.0, 20.0)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	# Bottom edge 6 px above the slime's body, spanning well past where it slides.
	wall.position = Vector2(body.global_position.x + 160.0, top - 6.0 - rect.size.y * 0.5)
	t.world().world_root.add_child(wall)
	await t.steps(2)
	t.press(&"move_right")
	t.press(&"move_up")
	await t.steps(12)
	var tangential := WALK_SPEED * Vector2(1, -1).normalized().x
	t.near_vec(body.velocity, Vector2(tangential, 0.0), 0.01, "velocity against the wall")
	var from := t.player().get_centre()
	var from_ms := t.now()
	await t.steps(MEASURE_STEPS)
	var moved := t.player().get_centre() - from
	var seconds := (t.now() - from_ms) / 1000.0
	if t.check(seconds > 0.0, "the gameplay clock did not advance"):
		t.near(moved.x / seconds, tangential, 0.5, "slide speed along the wall (px/s)")
	t.near(moved.y, 0.0, 0.5, "movement into the wall (px)")
	t.release_all()
	wall.queue_free()


## The three-quarter top-down sheet: walking picks the clip for the facing (down, up, side; the
## side art faces right and mirrors for left), and stopping keeps that facing in the idle clip
## (owner decisions O1/O4). The player starts facing down.
func test_directional_walk_and_idle_clips(t: TestContext) -> void:
	var player := t.player()
	t.equal(String(player.animation.assigned_animation), "idle-down", "clip at spawn")
	var cases := [
		[[&"move_up"], "walk-up", "idle-up", false],
		[[&"move_down"], "walk-down", "idle-down", false],
		[[&"move_right"], "walk-side", "idle-side", false],
		[[&"move_left"], "walk-side", "idle-side", true],
		[[&"move_left", &"move_up"], "walk-side", "idle-side", true],
	]
	for case: Array in cases:
		for action: StringName in case[0]:
			t.press(action)
		await t.steps(4)
		var label := "%s" % [case[0]]
		t.equal(String(player.animation.assigned_animation), case[1], "%s walk clip" % label)
		t.equal(player.visual.flip_h, case[3], "%s walk flip" % label)
		t.release_all()
		await t.steps(3)
		t.equal(String(player.animation.assigned_animation), case[2], "%s idle clip after stopping" % label)
		t.equal(player.visual.flip_h, case[3], "%s idle keeps the facing's flip" % label)


func test_releasing_keys_stops_the_player(t: TestContext) -> void:
	t.press(&"move_right")
	await t.steps(5)
	t.release(&"move_right")
	await t.steps(2)
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.001, "velocity after release")
	var before := t.player().get_centre()
	await t.steps(10)
	t.near_vec(t.player().get_centre(), before, 0.001, "position while idle")


## Dodge right: 380 px/s for 500 ms (190 px), i-frames 400 ms, a press during the cooldown (before
## 750 ms from the roll start) is refused, one after it rolls (back to the left).
func test_dodge_distance_duration_iframes_cooldown(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	player.face(Vector2.RIGHT)
	var start_centre := player.get_centre()
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the dodge press did not start a roll"):
		return
	# The roll began in the tick whose time now() reports (see TestContext timing model).
	var roll_start := t.now()
	t.near_vec(body.velocity, Vector2.RIGHT * DODGE_SPEED, 0.01, "roll velocity")
	t.check(player.is_dodging(), "not dodging (i-frames) right after the roll started")
	var blocked := player.can_receive_damage({"simulation_time": t.now()})
	t.check(not bool(blocked.get("accepted", true)) and blocked.get("reason", "") == "state-blocked",
		"damage during the dodge i-frames: got %s, expected rejected 'state-blocked'" % [blocked])

	await t.until(func() -> bool: return not player.is_dodging(), 1000.0)
	t.between(t.now() - roll_start, DODGE_IFRAMES_MS, DODGE_IFRAMES_MS + TestContext.STEP_MS, "dodge i-frames (ms)")
	t.check(player.is_rolling(), "the roll ended together with the i-frames (expected 100 ms of vulnerable roll)")
	var open := player.can_receive_damage({"simulation_time": t.now()})
	t.check(bool(open.get("accepted", false)), "damage after the i-frames but inside the roll: got %s, expected accepted" % [open])

	await t.until(func() -> bool: return not player.is_rolling(), 1000.0)
	t.between(t.now() - roll_start, DODGE_DURATION_MS, DODGE_DURATION_MS + TestContext.STEP_MS, "roll duration (ms)")
	await t.steps(2)
	t.near_vec(body.velocity, Vector2.ZERO, 0.001, "velocity after the roll")
	var travelled := player.get_centre() - start_centre
	t.near(travelled.x, DODGE_SPEED * DODGE_DURATION_MS / 1000.0, DODGE_SPEED / 60.0 + 0.5, "roll distance (px)")
	t.near(travelled.y, 0.0, 0.001, "roll vertical drift (px)")

	# Inside the cooldown: refused (the press is consumed, nothing rolls).
	await t.until(func() -> bool: return t.now() >= roll_start + 600.0, 1000.0)
	player.face(Vector2.LEFT)
	t.tap(&"dodge")
	await t.steps(3)
	t.check(not player.is_rolling(), "a dodge %.0f ms after the roll start rolled (cooldown is %.0f ms)" % [
		t.now() - roll_start, DODGE_COOLDOWN_FROM_START_MS])

	# After the cooldown: rolls.
	await t.until(func() -> bool: return t.now() >= roll_start + DODGE_COOLDOWN_FROM_START_MS, 1000.0)
	player.face(Vector2.LEFT)
	t.tap(&"dodge")
	t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0),
		"a dodge %.0f ms after the roll start was refused (cooldown is %.0f ms)" % [t.now() - roll_start, DODGE_COOLDOWN_FROM_START_MS])
	t.near_vec(body.velocity, Vector2.LEFT * DODGE_SPEED, 0.01, "second roll velocity")


## Page 2 and the keyed swings: a roll and a sword swing play the row for their direction (the
## side art mirrors for left; the swing has its own `-left` clip because its lunge has a
## direction), the swing lunges toward its direction, and the art is back at rest after it.
func test_roll_and_swing_pick_the_facing_row(t: TestContext) -> void:
	var player := t.player()
	var combat = player.get_combat()
	var rest_offset: Vector2 = player.visual.offset
	var cases := [
		[Vector2.DOWN, "roll-down", "attack-1-down", false],
		[Vector2.UP, "roll-up", "attack-1-up", false],
		[Vector2.RIGHT, "roll-side", "attack-1-side", false],
		[Vector2.LEFT, "roll-side", "attack-1-left", true],
	]
	for case: Array in cases:
		var toward: Vector2 = case[0]
		var label := "facing %s" % [toward]
		player.face(toward)
		t.tap(&"dodge")
		if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "%s: the dodge press did not start a roll" % label):
			return
		t.equal(String(player.animation.assigned_animation), case[1], "%s roll clip" % label)
		t.equal(player.visual.flip_h, case[3], "%s roll flip" % label)
		# The next roll needs the dodge cooldown; this swing needs the last one's weapon cooldown.
		await t.sim_wait(DODGE_COOLDOWN_FROM_START_MS + 50.0)
		await t.until(func() -> bool: return combat.get_weapon().can_begin_attack(), 2000.0)
		t.tap(&"attack")
		if not t.check(await t.until(func() -> bool: return combat.is_attacking(), 300.0), "%s: the swing did not start" % label):
			return
		t.equal(String(player.animation.assigned_animation), case[2], "%s swing clip" % label)
		t.equal(player.visual.flip_h, case[3], "%s swing flip" % label)
		await t.sim_wait(200.0)
		var reach: Vector2 = player.visual.offset - rest_offset
		t.check(reach.dot(toward) > 0.0, "%s: the swing does not lunge toward its direction (offset %s)" % [label, reach])
		await t.until(func() -> bool: return not combat.is_attacking(), 1500.0)
		await t.steps(2)
		t.near_vec(player.visual.offset, rest_offset, 0.001, "%s offset after the swing" % label)
		t.equal(player.visual.skew, 0.0, "%s skew after the swing" % label)


## Holds `actions`, lets the speed settle, then checks the velocity and the distance covered over
## MEASURE_STEPS ticks against `speed` along `direction`.
func _check_speed(t: TestContext, actions: Array, direction: Vector2, speed: float, label: String) -> void:
	for action: StringName in actions:
		t.press(action)
	await t.steps(3)
	var body := t.player_body()
	t.near_vec(body.velocity, direction * speed, 0.01, "%s velocity" % label)
	var from := t.player().get_centre()
	var from_ms := t.now()
	await t.steps(MEASURE_STEPS)
	var moved := t.player().get_centre() - from
	var seconds := (t.now() - from_ms) / 1000.0
	if not t.check(seconds > 0.0, "%s: the gameplay clock did not advance" % label):
		return
	t.near(moved.length() / seconds, speed, 0.5, "%s measured speed (px/s)" % label)
	t.near(moved.normalized().dot(direction), 1.0, 0.0001, "%s direction (cos of the angle to the expected)" % label)
	t.release_all()


## Reduce motion keeps 35 % of a squash (SquashStretch.ts squashStart): the landing splat
## (1.32, 0.72) starts at (1.112, 0.902).
func test_reduce_motion_softens_the_squash(t: TestContext) -> void:
	t.near_vec(SquashStretch.squash_start(Vector2(1.32, 0.72), false), Vector2(1.32, 0.72), 0.0001, "full squash")
	t.near_vec(SquashStretch.squash_start(Vector2(1.32, 0.72), true), Vector2(1.112, 0.902), 0.0001, "reduced squash")
