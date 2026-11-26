extends RefCounted
## Player movement and the Roll (docs/godot/specs/player.md section 2 values, 4.3 move, 5 the
## Roll; roadmap 7.7; docs/godot/BODY_SHAPES.md checklist 10, the Roll in the body-shapes mode, which
## is on in every world since 2026-10-24). The walk is `character.player.movement.baseSpeed` (180
## since 2026-11-18), the sprint `boostSpeed`, both under `movementSpeedCap`; diagonals normalised.
## The Roll (the `dodge` ability, on Space; young Burr teaches it, lent for the session here) fires on
## the key's release: a tap rolls the **quick roll** (no spin-up, `character.player.rework.
## quickRollDistancePx` over `quickRollMs`, safe for `quickRollInvulnerabilityMs`); with the
## `roll-charge` upgrade a hold past `rollTapMs` is the **charged roll**: it spins up in place,
## launches and eases to its cruising speed over its shortest roll, is safe just after the launch,
## keeps rolling while held (straight, draining energy) and ends when let go (its values in
## `character.player.movement.roll*`). A roll sticks in a floor web (owner, 2026-10-16) unless the
## slime crosses webs (the Silk skin).
## The speed checks walk from OPEN in level-1's village chunk, where the ground to the right and
## up-right is open for the distances used here.

const TestContext := preload("res://tests/lib/test_context.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const Services := preload("res://game/shared/services.gd")
const SquashStretch := preload("res://game/player/squash_stretch.gd")
const PlayerRoll := preload("res://game/player/roll/player_roll.gd")

const MEASURE_STEPS := 30
## Where the speed and roll checks start (old Phaser centre).
const OPEN := Vector2(640.0, 764.0)


func test_walk_speed_is_the_base_speed(t: TestContext) -> void:
	await _check_speed(t, [&"move_right"], Vector2.RIGHT, _walk_speed(), "walk right")


func test_walk_diagonal_is_normalised(t: TestContext) -> void:
	await _check_speed(t, [&"move_right", &"move_up"], Vector2(1, -1).normalized(), _walk_speed(), "walk up-right")


func test_sprint_speed_is_300(t: TestContext) -> void:
	await _check_speed(t, [&"sprint", &"move_right"], Vector2.RIGHT, _sprint_speed(), "sprint right")


func test_sprint_diagonal_is_normalised(t: TestContext) -> void:
	await _check_speed(t, [&"sprint", &"move_right", &"move_up"], Vector2(1, -1).normalized(), _sprint_speed(), "sprint up-right")


## A diagonal walk into a wall slides along it at the tangential speed, and the blocked velocity
## component reads back as zero, as Phaser's Arcade separation does (player spec 5.2). Godot's
## floating `move_and_slide()` would slide at the full walk speed and keep the velocity, which is why
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
	var tangential := _walk_speed() * Vector2(1, -1).normalized().x
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


## A tapped Roll to the right is the quick roll (BODY_SHAPES.md checklist 10): no spin-up, the ball
## shoots off at once at the speed that covers `quickRollDistancePx` in `quickRollMs` while easing to
## `quickRollEndSpeedShare` of it, safe for `quickRollInvulnerabilityMs`, and it stops `quickRollMs`
## after the launch. A press right after is refused (the cooldown runs from the press:
## `quickRollMs` + `rollCooldownMs`), one after the cooldown rolls.
func test_a_tapped_roll_is_the_quick_roll(t: TestContext) -> void:
	_learn_the_roll()
	var player := t.player()
	var body := t.player_body()
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	var length := _rework("quickRollMs")
	var iframes := _rework("quickRollInvulnerabilityMs")
	var start_centre := player.get_centre()
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the roll press did not start a roll"):
		return
	var launched := t.now()
	t.check(not player.get_roll().is_spinning_up(), "the quick roll spins up")
	t.equal(String(player.animation.assigned_animation), "ball-side", "the ball clip")
	t.near_vec(body.velocity, Vector2.RIGHT * _quick_launch_speed(), 0.01, "launch velocity")
	t.check(player.is_dodging(), "no i-frames right after the launch")
	var blocked := player.can_receive_damage({"simulation_time": t.now()})
	t.check(not bool(blocked.get("accepted", true)) and blocked.get("reason", "") == "state-blocked",
		"damage during the roll's i-frames: got %s, expected rejected 'state-blocked'" % [blocked])
	await t.until(func() -> bool: return not player.is_dodging(), 1000.0)
	t.between(t.now() - launched, iframes, iframes + TestContext.STEP_MS, "roll i-frames (ms)")

	await t.until(func() -> bool: return not player.is_rolling(), 1500.0)
	t.between(t.now() - launched, length, length + 2.0 * TestContext.STEP_MS, "a quick roll's length after the launch (ms)")
	await t.steps(2)
	t.near_vec(body.velocity, Vector2.ZERO, 0.001, "velocity after the roll")
	var travelled := player.get_centre() - start_centre
	var distance := _rework("quickRollDistancePx")
	t.between(travelled.x, distance * 0.9, distance * 1.1, "the quick roll's distance (px)")
	t.near(travelled.y, 0.0, 0.001, "roll vertical drift (px)")

	# Inside the cooldown (from the press): refused.
	t.tap(&"dodge")
	await t.steps(3)
	t.check(not player.is_rolling(), "a roll %.0f ms after the last press rolled (cooldown %.0f ms)" % [
		t.now() - launched, _quick_cooldown_from_press()])
	# After it (and the roll's own pause after its end, which step rounding puts a little later):
	# rolls.
	await t.until(func() -> bool: return t.now() >= launched + _quick_cooldown_from_press() + 4.0 * TestContext.STEP_MS, 2000.0)
	player.face(Vector2.LEFT)
	t.tap(&"dodge")
	t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0),
		"a roll %.0f ms after the last press was refused" % [t.now() - launched])


## Without the `roll-charge` upgrade a held key waits for its release and rolls the quick roll then
## (player.gd `_due_roll`). With it, a hold past `rollTapMs` is the charged roll: the spin-up keeps
## the slime in place for `rollSpinUpMs` (the ball clip, no i-frames), the launch shoots it off at
## `rollLaunchSpeed` with `rollInvulnerabilityMs` of i-frames, and the held key keeps the ball rolling
## past its shortest roll, straight on: the movement keys do not turn it or slide it sideways (owner,
## 2026-10-09: like Zelda's Pegasus dash). Energy drains and does not refill, and letting go stops it.
func test_a_held_roll_goes_straight_and_drains_energy(t: TestContext) -> void:
	_learn_the_roll()
	var player := t.player()
	var body := t.player_body()
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	# No upgrade: nothing rolls while the key is held.
	t.press(&"dodge")
	await t.sim_wait(_rework("rollTapMs") + _movement("rollSpinUpMs"))
	t.check(not player.is_rolling(), "a held key rolled without the roll-charge upgrade")
	t.release(&"dodge")
	t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the release did not roll the quick roll")
	t.check(not player.get_roll().is_spinning_up(), "the release's roll spins up")
	await t.until(func() -> bool: return not player.is_rolling(), 1500.0)
	await t.sim_wait(_quick_cooldown_from_press() + 100.0)

	# The upgrade: the charged roll.
	Services.run().learn_session_ability(String(PlayerRoll.CHARGE_UPGRADE_ID))
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	var start_centre := player.get_centre()
	var spin_up := _movement("rollSpinUpMs")
	var iframes := _movement("rollInvulnerabilityMs")
	t.press(&"dodge")
	var pressed := t.now()
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), _rework("rollTapMs") + 100.0), "the held roll key did not start a roll"):
		t.release_all()
		return
	var spun := t.now()
	t.between(spun - pressed, _rework("rollTapMs"), _rework("rollTapMs") + 2.0 * TestContext.STEP_MS, "the hold before the charged roll (ms)")
	t.check(player.get_roll().is_spinning_up(), "the charged roll does not start with its spin-up")
	t.equal(String(player.animation.assigned_animation), "ball-side", "the ball clip")
	t.check(not player.is_dodging(), "i-frames during the spin-up")
	await t.sim_wait(spin_up * 0.5)
	t.near_vec(body.velocity, Vector2.ZERO, 0.001, "velocity during the spin-up")
	t.near_vec(player.get_centre(), start_centre, 0.001, "the slime moved during the spin-up")
	await t.until(func() -> bool: return not player.get_roll().is_spinning_up(), 1000.0)
	var launched := t.now()
	t.between(launched - spun, spin_up, spin_up + TestContext.STEP_MS, "spin-up (ms)")
	t.near_vec(body.velocity, Vector2.RIGHT * _movement("rollLaunchSpeed"), 0.01, "launch velocity")
	t.check(player.is_dodging(), "no i-frames right after the launch")
	await t.sim_wait(80.0)
	t.press(&"move_up")
	t.press(&"move_left")
	await t.until(func() -> bool: return not player.is_dodging(), 1000.0)
	t.between(t.now() - launched, iframes, iframes + TestContext.STEP_MS, "roll i-frames (ms)")
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
	_learn_the_roll()
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


## A Roll sticks in a floor web (owner, 2026-10-16, question 131). A Matron web patch (r 50) lies
## 130 px to the right of OPEN, a little below the roll's line: the ball rolling into it sticks (the
## web's `caught`; the floor webs' rule, game/world/webs/floor_webs.gd, since 2026-10-17), its roll
## is over there (no bonk, no bounce, no rolling on), the slime is stuck (rooted, still) where the
## web caught it, on the patch (nothing sets it back), and the web is whole. With the Silk skin
## (SkinState, `crosses_webs`; roadmap 7.8) the web no longer sticks: the roll tears through it and
## goes on past it. The painted floor webs: tests/test_weaver_webs.gd.
func test_a_roll_sticks_in_a_floor_web(t: TestContext) -> void:
	_learn_the_roll()
	var player := t.player()
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	var at := OPEN + Vector2(130.0, 12.0)
	var root := t.world().spawn_at_phaser_position("effect.matron-web-patch", at)
	if not t.check(root != null, "effect.matron-web-patch did not spawn"):
		return
	var patch := root.get_node_or_null(^"WebPatchScript")
	if not t.check(patch != null, "the patch effect has no WebPatchScript"):
		return
	var events := {"caught": [], "torn": []}
	patch.connect(&"caught", func(zone: Dictionary) -> void: (events["caught"] as Array).append(zone))
	patch.connect(&"torn", func(zone: Dictionary) -> void: (events["torn"] as Array).append(zone))
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "the roll press did not start a roll"):
		return
	if not t.check(await t.until(func() -> bool: return not (events["caught"] as Array).is_empty(), 1500.0), "the roll never met the web"):
		return
	t.check(not player.is_rolling(), "the roll goes on in the web")
	t.check(player.is_rooted(), "the rolling slime is not stuck in the web")
	t.check(not bool(patch.call(&"is_torn")), "the Roll tore the web")
	var stuck_at := player.get_centre()
	t.check(stuck_at.distance_to(at) <= 52.0, "the stuck slime is not on the web (%s, the web at %s)" % [stuck_at, at])
	await t.steps(3)
	t.check(not player.get_roll().is_bouncing(), "the web bonked the roll")
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.001, "the stuck slime's velocity")
	t.near_vec(player.get_centre(), stuck_at, 1.0, "the stuck slime moved")
	t.equal((events["caught"] as Array).size(), 1, "catches of the rolling slime")
	# The Silk skin: the web no longer sticks, the roll tears through.
	await t.sim_wait(1100.0)
	SkinState.lend(SkinState.SILK)
	if not t.check(player.crosses_webs(), "the Silk skin does not cross webs"):
		return
	t.teleport_player(OPEN)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	t.tap(&"dodge")
	if not t.check(await t.until(func() -> bool: return not (events["torn"] as Array).is_empty(), 1500.0), "the Silk roll did not tear the web"):
		return
	t.check(player.is_rolling(), "the Silk roll stopped in the web")
	t.check(not player.is_rooted(), "the web stuck the Silk slime")
	t.equal((events["caught"] as Array).size(), 1, "catches of the Silk slime")
	await t.until(func() -> bool: return not player.is_rolling(), 1500.0)
	t.check(player.get_centre().x > at.x, "the Silk roll did not go past the web (%s, the web at %s)" % [player.get_centre(), at])


## The Roll is young Burr's lesson since 2026-11-19 (no longer known from birth): lent here.
static func _learn_the_roll() -> void:
	Services.run().learn_session_ability("dodge")


func _movement(name: String) -> float:
	return Services.constants().number("character.player.movement." + name)


## The body-shapes mode's player numbers (`character.player.rework`).
func _rework(name: String) -> float:
	return Services.constants().number("character.player.rework." + name)


## Player spec 4.3: the walk is `baseSpeed` under `movementSpeedCap`; the sprint is `boostSpeed`.
func _walk_speed() -> float:
	return minf(_movement("movementSpeedCap"), _movement("baseSpeed"))


func _sprint_speed() -> float:
	return minf(_movement("movementSpeedCap"), _movement("boostSpeed"))


## The quick roll's launch speed: it covers `quickRollDistancePx` in `quickRollMs` easing linearly
## to `quickRollEndSpeedShare` of it (the distance is the mean speed times the time).
func _quick_launch_speed() -> float:
	return 2.0 * _rework("quickRollDistancePx") / (_rework("quickRollMs") / 1000.0 * (1.0 + _rework("quickRollEndSpeedShare")))


## The quick roll's cooldown from the press (BODY_SHAPES.md: `quickRollMs` + `rollCooldownMs`).
func _quick_cooldown_from_press() -> float:
	return _rework("quickRollMs") + _movement("rollCooldownMs")


## The Roll's ball picks the row for the direction it rolls (one spinning ball, mirrored for left).
## (The keyed sword swing this test also drove is gone: the body-shapes mode, on in every world since
## 2026-10-24, hands out no weapon and strikes with the shapes, BODY_SHAPES.md "Running it".)
func test_a_roll_picks_the_facing_row(t: TestContext) -> void:
	_learn_the_roll()
	var player := t.player()
	t.teleport_player(OPEN)
	await t.steps(2)
	var cases := [
		[Vector2.DOWN, "ball-down", false],
		[Vector2.UP, "ball-up", false],
		[Vector2.RIGHT, "ball-side", false],
		[Vector2.LEFT, "ball-side", true],
	]
	for case: Array in cases:
		var toward: Vector2 = case[0]
		var label := "facing %s" % [toward]
		player.face(toward)
		t.tap(&"dodge")
		if not t.check(await t.until(func() -> bool: return player.is_rolling(), 100.0), "%s: the roll press did not start a roll" % label):
			return
		t.equal(String(player.animation.assigned_animation), case[1], "%s roll clip" % label)
		t.equal(player.visual.flip_h, case[2], "%s roll flip" % label)
		# The next roll needs the roll's cooldown (from the press, and its pause after the roll's end,
		# which a bonk's bounce puts later).
		await t.until(func() -> bool: return not player.is_rolling(), 2000.0)
		await t.sim_wait(_quick_cooldown_from_press() + 50.0)
		t.teleport_player(OPEN)
		await t.steps(2)


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
