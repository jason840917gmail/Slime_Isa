extends RefCounted
## Player movement and the Roll (docs/godot/specs/player.md section 2 values, 4.3 move, 5 the
## Roll; roadmap 7.7). Walk 200 px/s, sprint 300 px/s, diagonals normalised. The Roll (the `dodge`
## ability on key 2) spins up in place, launches and eases to its cruising speed over its shortest
## roll, is safe from hits just after the launch, keeps rolling while held (steered, draining
## energy) and ends when let go; its values are read from `character.player.movement.roll*`.
## The player starts at level-1's spawn (centre (640, 704), in the village chunk C4); the speed
## checks walk from 60 px below it (OPEN), where the ground to the right and up-right is open for
## the distances used here (the village banner at (656, 664) stands up-right of the spawn itself).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const SquashStretch := preload("res://game/player/squash_stretch.gd")

const WALK_SPEED := 200.0
const SPRINT_SPEED := 300.0
const MEASURE_STEPS := 30
## Where the speed checks start (old Phaser centre).
const OPEN := Vector2(640.0, 764.0)


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


## A tapped Roll to the right: the spin-up keeps the slime in place for `rollSpinUpMs` (the ball
## clip, no i-frames), the launch shoots it off at `rollLaunchSpeed` with `rollInvulnerabilityMs`
## of i-frames, and without the key held it stops `rollMinMs` after the launch. A press right after
## is refused (the cooldown runs from the press), one after the cooldown rolls.
func test_a_tapped_roll_spins_up_launches_and_stops(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	var spin_up := _movement("rollSpinUpMs")
	var min_ms := _movement("rollMinMs")
	var iframes := _movement("rollInvulnerabilityMs")
	player.face(Vector2.RIGHT)
	var start_centre := player.get_centre()
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the roll press did not start a roll"):
		return
	var pressed := t.now()
	t.check(player.get_roll().is_spinning_up(), "the roll does not start with its spin-up")
	t.equal(String(player.animation.assigned_animation), "ball-side", "the ball clip")
	t.check(not player.is_dodging(), "i-frames during the spin-up")
	await t.sim_wait(spin_up * 0.5)
	t.near_vec(body.velocity, Vector2.ZERO, 0.001, "velocity during the spin-up")
	t.near_vec(player.get_centre(), start_centre, 0.001, "the slime moved during the spin-up")

	await t.until(func() -> bool: return not player.get_roll().is_spinning_up(), 1000.0)
	var launched := t.now()
	t.between(launched - pressed, spin_up, spin_up + TestContext.STEP_MS, "spin-up (ms)")
	t.near_vec(body.velocity, Vector2.RIGHT * _movement("rollLaunchSpeed"), 0.01, "launch velocity")
	t.check(player.is_dodging(), "no i-frames right after the launch")
	var blocked := player.can_receive_damage({"simulation_time": t.now()})
	t.check(not bool(blocked.get("accepted", true)) and blocked.get("reason", "") == "state-blocked",
		"damage during the roll's i-frames: got %s, expected rejected 'state-blocked'" % [blocked])
	await t.until(func() -> bool: return not player.is_dodging(), 1000.0)
	t.between(t.now() - launched, iframes, iframes + TestContext.STEP_MS, "roll i-frames (ms)")

	await t.until(func() -> bool: return not player.is_rolling(), 1500.0)
	t.between(t.now() - launched, min_ms, min_ms + 2.0 * TestContext.STEP_MS, "a tapped roll's length after the launch (ms)")
	await t.steps(2)
	t.near_vec(body.velocity, Vector2.ZERO, 0.001, "velocity after the roll")
	var travelled := player.get_centre() - start_centre
	t.check(travelled.x > _movement("rollSpeed") * min_ms / 1000.0, "the roll covered only %.1f px" % travelled.x)
	t.near(travelled.y, 0.0, 0.001, "roll vertical drift (px)")

	# Inside the cooldown (from the press): refused.
	t.tap(&"dodge")
	await t.steps(3)
	t.check(not player.is_rolling(), "a roll %.0f ms after the last press rolled (cooldown %.0f ms)" % [
		t.now() - pressed, _cooldown_from_press()])
	# After it (and the roll's own pause after its end, which step rounding puts a little later):
	# rolls.
	await t.until(func() -> bool: return t.now() >= pressed + _cooldown_from_press() + 4.0 * TestContext.STEP_MS, 1500.0)
	player.face(Vector2.LEFT)
	t.tap(&"dodge")
	t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0),
		"a roll %.0f ms after the last press was refused" % [t.now() - pressed])


## Holding the key keeps the ball rolling past its shortest roll, straight on: the movement keys
## do not turn it or slide it sideways (owner, 2026-10-09: like Zelda's Pegasus dash). Energy drains
## and does not refill, and letting go stops it.
func test_a_held_roll_goes_straight_and_drains_energy(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	player.face(Vector2.RIGHT)
	t.press(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the roll press did not start a roll"):
		t.release_all()
		return
	await t.until(func() -> bool: return not player.get_roll().is_spinning_up(), 1000.0)
	var launched := t.now()
	await t.sim_wait(80.0)
	t.press(&"move_up")
	t.press(&"move_left")
	await t.until(func() -> bool: return t.now() >= launched + _movement("rollMinMs"), 1500.0)
	var energy := player.get_energy()
	await t.sim_wait(200.0)
	t.check(player.is_rolling(), "a held roll stopped after its shortest roll")
	t.near_vec(player.get_roll().direction(), Vector2.RIGHT, 0.001, "the movement keys turned the roll")
	t.near(body.velocity.y, 0.0, 0.001, "the roll slid sideways")
	t.near(player.get_roll().speed(), _movement("rollSpeed"), 1.0, "cruising speed")
	t.check(player.get_energy() < energy - 0.25 * _movement("rollEnergyPerSecond") * 0.2,
		"energy %.1f -> %.1f over 0.2 s of rolling on" % [energy, player.get_energy()])
	t.release(&"dodge")
	t.release(&"move_up")
	t.release(&"move_left")
	t.check(await t.until(func() -> bool: return not player.is_rolling(), 100.0), "letting go did not stop the roll")
	await t.steps(2)
	t.near_vec(body.velocity, Vector2.ZERO, 0.001, "velocity after letting go")


## Rolling into a wall is a bonk: the ball stops, the slime bounces back off the wall at least a
## tile, for `rollBounceMs`, and only then is free; the roll is over after the bounce.
func test_rolling_into_a_wall_bonks_and_bounces_back(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20.0, 400.0)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	wall.position = Vector2(body.global_position.x + 90.0, body.global_position.y)
	t.world().world_root.add_child(wall)
	await t.steps(2)
	player.face(Vector2.RIGHT)
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the roll press did not start a roll"):
		wall.queue_free()
		return
	t.check(await t.until(func() -> bool: return player.get_roll().is_bouncing(), 1500.0), "the roll never bonked the wall")
	var bonk_x := player.get_centre().x
	await t.steps(3)
	t.check(body.velocity.x < 0.0, "the slime did not bounce back off the wall (velocity %s)" % [body.velocity])
	t.check(player.is_rolling(), "the bounce does not hold the slime")
	t.check(await t.until(func() -> bool: return not player.is_rolling(), _movement("rollBounceMs") + 200.0),
		"the bounce never ended")
	# At least one tile back off the wall (owner, 2026-10-09).
	t.check(bonk_x - player.get_centre().x >= 64.0 - 2.0, "the bounce went back %.1f px, less than a tile" % [
		bonk_x - player.get_centre().x])
	wall.queue_free()


func _movement(name: String) -> float:
	return Services.constants().number("character.player.movement." + name)


func _cooldown_from_press() -> float:
	return _movement("rollSpinUpMs") + _movement("rollMinMs") + _movement("rollCooldownMs")


## The Roll's ball and the keyed swings: a roll plays the ball clip for its direction (one spinning
## ball, mirrored for left) and a sword swing plays the row for its direction (it has its own
## `-left` clip because its lunge has a direction), the swing lunges toward its direction, and the
## art is back at rest after it.
func test_roll_and_swing_pick_the_facing_row(t: TestContext) -> void:
	var player := t.player()
	var combat = player.get_combat()
	var rest_offset: Vector2 = player.visual.offset
	var cases := [
		[Vector2.DOWN, "ball-down", "attack-1-down", false],
		[Vector2.UP, "ball-up", "attack-1-up", false],
		[Vector2.RIGHT, "ball-side", "attack-1-side", false],
		[Vector2.LEFT, "ball-side", "attack-1-left", true],
	]
	for case: Array in cases:
		var toward: Vector2 = case[0]
		var label := "facing %s" % [toward]
		player.face(toward)
		t.tap(&"dodge")
		if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "%s: the roll press did not start a roll" % label):
			return
		t.equal(String(player.animation.assigned_animation), case[1], "%s roll clip" % label)
		t.equal(player.visual.flip_h, case[3], "%s roll flip" % label)
		# The next roll needs the roll's cooldown; this swing needs the last one's weapon cooldown.
		await t.sim_wait(_cooldown_from_press() + 50.0)
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
	t.teleport_player(OPEN)
	await t.steps(2)
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
