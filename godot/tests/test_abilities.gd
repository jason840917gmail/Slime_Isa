extends RefCounted
## Jump, Squash Slam, Teleport, Stretch Lash rules and energy (docs/godot/specs/abilities.md 19.5).
## level-1 spawn: centre (640, 704). Times are simulation ms from the step that took the press.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const JUMP_MS := 420.0
const JUMP_COOLDOWN_MS := 700.0
const SLAM_IMPACT_MS := 320.0
const WORM_HP := 90.0
const SLAM_DAMAGE := 30.0
const STEP := TestContext.STEP_MS


func test_unlearned_jump_is_refused(t: TestContext) -> void:
	var player := t.player()
	var status: Dictionary = player.ability_status(&"jump")
	t.equal(status.get("unlocked"), false, "jump unlocked at a new run")
	t.equal(status.get("earnedBy"), "Quest", "jump earnedBy")
	t.equal(status.get("canActivate"), false, "jump canActivate")
	t.tap(&"jump")
	await t.steps(3)
	t.check(not player.is_ability_busy(), "an unlearned jump started")


func test_jump_in_place_and_cooldown(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("jump")
	var landings: Array = []
	t.listen(player.jump_landed, func(payload: Dictionary) -> void: landings.append([t.now(), payload]))
	var start := player.get_centre()
	t.tap(&"jump")
	if not t.check(await t.until(func() -> bool: return player.is_ability_busy(), 100.0), "the jump did not start"):
		return
	var began := t.now()
	t.check(player.is_action_locked(), "not action-locked during the jump")
	t.near(player.ability_status(&"jump")["cooldownRemainingMs"], JUMP_COOLDOWN_MS, STEP + 0.5, "cooldown at the press")
	await t.until(func() -> bool: return not landings.is_empty(), 1000.0)
	if not t.check(not landings.is_empty(), "the jump never landed"):
		return
	t.between(landings[0][0] - began, JUMP_MS - STEP, JUMP_MS + STEP, "landing time (ms)")
	t.equal(landings[0][1]["heavy"], false, "a plain jump is not heavy")
	t.near_vec(player.get_centre(), start, 0.5, "a jump in place lands where it started")
	await t.steps(2)
	t.check(not player.is_action_locked(), "still locked after landing")
	# Second jump inside the cooldown is refused; after it, accepted.
	await t.until(func() -> bool: return t.now() >= began + 500.0, 1000.0)
	t.tap(&"jump")
	await t.steps(3)
	t.check(not player.is_ability_busy(), "a jump %d ms after the first started (cooldown 700)" % roundi(t.now() - began))
	await t.until(func() -> bool: return t.now() >= began + JUMP_COOLDOWN_MS + STEP, 1000.0)
	t.tap(&"jump")
	t.check(await t.until(func() -> bool: return player.is_ability_busy(), 100.0), "a jump after the cooldown was refused")


func test_jump_right_carries_the_body_through_the_air(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("jump")
	var start := player.get_centre()
	t.press(&"move_right")
	await t.steps(1)
	start = player.get_centre()
	t.tap(&"jump")
	if not t.check(await t.until(func() -> bool: return player.is_ability_busy(), 100.0), "the jump did not start"):
		return
	t.release_all()
	start = player.get_centre()
	await t.sim_wait(JUMP_MS / 2.0)
	# The body travels evenly (the camera follows it); the art arcs over it.
	t.between(player.get_centre().x - start.x, 168.0 * 0.5 - 16.0, 168.0 * 0.5 + 16.0, "body x mid-jump")
	await t.until(func() -> bool: return not player.is_ability_busy(), 1000.0)
	t.near(player.get_centre().x - start.x, 168.0, 0.5, "jump distance right")


func test_slam_hits_worm_in_reach_only(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("squash-slam")
	var near := t.spawn_worm(Vector2(60.0, 0.0), true)
	var far := t.spawn_worm(Vector2(200.0, 0.0), true)
	if not t.check(near != null and far != null, "no worms"):
		return
	await t.steps(1)
	t.tap(&"squash_slam")
	if not t.check(await t.until(func() -> bool: return player.is_ability_busy(), 100.0), "the slam did not start"):
		return
	var began := t.now()
	await t.until(func() -> bool: return t.now() >= began + SLAM_IMPACT_MS - 2.0 * STEP, 1000.0)
	t.equal(float(near.get_damage_state()["hp"]), WORM_HP, "near worm HP before the impact")
	await t.until(func() -> bool: return float(near.get_damage_state()["hp"]) < WORM_HP, 300.0)
	t.equal(float(near.get_damage_state()["hp"]), WORM_HP - SLAM_DAMAGE, "near worm HP after the slam")
	t.check(near.body.velocity.x > 200.0, "near worm knockback %s (expected about 242 right)" % [near.body.velocity])
	t.equal(float(far.get_damage_state()["hp"]), WORM_HP, "far worm HP")
	t.between(player.get_energy(), 70.0, 75.0, "energy after the slam (100 - 30, plus regen)")


func test_teleport_lands_ahead_and_blocked_is_refused(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("teleport")
	var start := Vector2(640.0, 704.0)
	t.teleport_player(start)
	player.face(Vector2.RIGHT)
	await t.steps(2)
	start = player.get_centre()
	var expected: Vector2 = player.get_abilities().AbilityTerrain.safe_landing(start, Vector2.RIGHT, 240.0, player.body_rids())
	t.tap(&"teleport")
	if not t.check(await t.until(func() -> bool: return player.is_ability_busy(), 100.0), "the teleport did not start"):
		return
	var began := t.now()
	t.near_vec(player.get_centre(), start, 0.5, "still at the start before 120 ms")
	await t.until(func() -> bool: return t.now() >= began + 130.0, 500.0)
	t.near_vec(player.get_centre(), expected, 0.5, "landing")
	t.between(player.get_energy(), 65.0, 67.0, "energy after the teleport (100 - 35, plus regen)")
	await t.until(func() -> bool: return not player.is_ability_busy(), 1000.0)
	t.between(t.now() - began, 300.0 - STEP, 300.0 + STEP, "teleport length (ms)")


func test_low_energy_refuses_and_regen(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("stretch-lash")
	player.set_energy(10.0)
	t.tap(&"stretch_lash")
	await t.steps(3)
	t.check(not player.is_ability_busy(), "a lash started with 10 energy (costs 20)")
	var before := player.get_energy()
	var from := t.now()
	await t.sim_wait(1000.0)
	t.near(player.get_energy() - before, 8.0 * (t.now() - from) / 1000.0, 0.2, "regen 8 per second")


func test_lash_faces_its_direction(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("stretch-lash")
	t.teleport_player(Vector2(640.0, 704.0))
	player.face(Vector2.DOWN)
	await t.steps(2)
	# A pointer aim to the left while facing down (headless runs have no pointer: request it).
	var started: bool = player.get_abilities().try_begin(&"stretch-lash",
			{"position": player.get_centre(), "direction": Vector2.LEFT, "facing": player.get_facing()})
	if not t.check(started, "the lash did not start"):
		return
	await t.steps(1)
	t.near_vec(player.get_facing(), Vector2.LEFT, 0.001, "facing after a lash to the left")
	t.equal(String(player.animation.assigned_animation), "stretch-left", "the lash clip")
	await t.until(func() -> bool: return not player.is_ability_busy(), 1000.0)


func test_lash_into_nothing_retracts(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("stretch-lash")
	var start := Vector2(640.0, 704.0)
	t.teleport_player(start)
	player.face(Vector2.DOWN)
	await t.steps(2)
	start = player.get_centre()
	t.tap(&"stretch_lash")
	if not t.check(await t.until(func() -> bool: return player.is_ability_busy(), 100.0), "the lash did not start"):
		return
	var began := t.now()
	var tendril := Services.world().entities_root().get_node_or_null("LashTendril") as Sprite2D
	if t.check(tendril != null, "no lash tendril"):
		t.near_vec(tendril.global_position, start, 1.0, "the tendril starts at the slime")
		t.near(tendril.rotation, Vector2.DOWN.angle(), 0.01, "the tendril points down")
		t.near(tendril.scale.x * 384.0, 180.0, 1.0, "the tendril reaches the full 180 px")
	await t.until(func() -> bool: return not player.is_ability_busy(), 1000.0)
	var length := t.now() - began
	t.check(length <= 300.0 + STEP, "the lash lasted %d ms (expected 270 into nothing, 280 heavy without pull)" % roundi(length))
	t.near_vec(player.get_centre(), start, 1.0, "the slime did not move")
	t.near(player.ability_status(&"stretch-lash")["cooldownRemainingMs"], 2000.0 - length, STEP + 1.0, "lash cooldown left")
