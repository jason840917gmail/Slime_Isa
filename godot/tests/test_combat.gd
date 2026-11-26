extends RefCounted
## The slime's melee attack vs the worm swordsman, and worm vs player (docs/godot/specs/combat.md
## section 15 "Expected trial numbers" for the worm's side, enemy.md 5-7, player.md 6).
## The body-shapes rework mode is on in every world (docs/godot/BODY_SHAPES.md "Running it"): no
## crafted weapon is mounted in the hand (main.gd `equip_run_start`), the attack key strikes with the
## current body shape beside the throw rules (one combat since 2026-11-25: THROW_COMBAT.md "One
## combat"). These tests lend the Spear (`shapes.spear`):
## - a tap is the chain's first step, the jab (class tap), doing `baseDamage` x (attack / 10) x its
##   `damageScale` x `shapes.weaponDamageScale` (12 x 1.2 x 0.97 x 0.5 = 7; a crit, 5 %, x `critMultiplier` 1.75), knocked along the
##   aim (`knockMode` aim: right here); BODY_SHAPES.md "Data" and "The hit";
## - the Spear is drawn only while it strikes (the player's StrikeRig draws nothing while no strike
##   runs);
## - 90 HP takes strikes until their sum reaches it; the corpse is freed 800 ms (gameplay clock)
##   after the killing blow.
## - A worm swing lands 400 ms after it starts and does 10 (the slime has no defence since
##   2026-11-24: docs/design/2026-11-24-health-and-damage.md), so 8 kill its 80; the player then has
##   500 ms of i-frames (a second worm's simultaneous swing is rejected "state-blocked") and is
##   knocked back at 260 px/s.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const WORM_MAX_HP := 90.0
const SPEAR_WEAPON_ID := "shape-spear"
const CRIT_MULTIPLIER_PATH := "character.player.stats.critMultiplier"
const WORM_WINDUP_MS := 400.0
const WORM_HIT_ON_PLAYER := 10
## The slime's max health (`character.player.stats.maxHp`) and the worm hits that empty it.
const PLAYER_MAX_HP := 80
const WORM_HITS_TO_KILL := 8
const PLAYER_IFRAMES_MS := 500.0
const PLAYER_KNOCKBACK_SPEED := 260.0
const DISPOSE_AFTER_DEFEAT_MS := 800.0
## Worm centre offset from the player centre: inside the Spear's reach to the right, outside the
## worm's 38 px attack range.
const SPEAR_TARGET_OFFSET := Vector2(40.0, 0.0)
## Inside the worm's 38 px attack range.
const WORM_ATTACK_OFFSET := 34.0


func test_spear_tap_damages_and_pushes_the_worm(t: TestContext) -> void:
	var shapes: Object = await _lend_spear(t)
	if shapes == null:
		return
	var worm := t.spawn_worm(SPEAR_TARGET_OFFSET, true)
	if worm == null:
		return
	await t.steps(1)
	var hits := _record_routes(t, worm.damage_area, worm.body)
	var paused_seen := {"value": false}
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	if not t.check(await t.until(func() -> bool: return not hits.is_empty(), 600.0), "the Spear never routed a hit to the worm"):
		return
	var hit: Dictionary = hits[0]
	var result: Dictionary = hit["result"]
	if not t.equal(result.get("status"), "accepted", "Spear hit status (reason '%s')" % result.get("reason", "")):
		return
	var request: Dictionary = hit["request"]
	t.equal(str(request.get("weapon_id", "")), SPEAR_WEAPON_ID, "the hit's weapon id")
	var sent: Dictionary = request.get("hit", {})
	t.equal(str(sent.get("class", "")), "tap", "a tap's hit class")
	t.equal(int(sent.get("step", 0)), 1, "a tap is the chain's first step")
	t.equal(str(sent.get("shape", "")), "spear", "the hit's shape")
	t.near_vec(sent.get("knock", Vector2.ZERO), Vector2.RIGHT, 0.001, "the knock follows the aim")
	var damage := int(result.get("actual_damage", 0))
	var allowed := _step_damages(0)
	t.check(allowed.has(damage), "Spear jab damage: got %d, expected one of %s (a crit is the second)" % [damage, allowed])
	if damage == allowed[1]:
		t.note("the jab was a critical hit (%d)" % damage)
	t.near(float(worm.get_damage_state()["hp"]), WORM_MAX_HP - damage, 0.001, "worm HP after one jab")
	# Hit-stop: the tree pauses (deferred) right after the hit.
	await t.until(func() -> bool:
		paused_seen["value"] = paused_seen["value"] or t.tree.paused
		return not bool(shapes.call(&"is_busy")), 1000.0)
	t.check(paused_seen["value"], "no hit-stop pause after the Spear hit")
	var drift: Vector2 = worm.get_centre() - (hit["centre"] as Vector2)
	t.check(drift.x >= -0.5, "the worm moved toward the slime (%s) after a jab to the right" % [drift])
	t.near(drift.y, 0.0, 1.0, "worm vertical drift after the jab (px)")
	t.check(hits.size() == 1, "one jab routed %d hits to the worm (expected 1)" % hits.size())


## The Spear is drawn only while it strikes (the StrikeRig under the slime's Visual draws nothing
## while no strike runs: game/shapes/strike_rig.gd `is_active`).
func test_spear_shows_only_while_striking(t: TestContext) -> void:
	var shapes: Object = await _lend_spear(t)
	if shapes == null:
		return
	var rig := t.player().get_strike_rig()
	if not t.check(rig != null and rig.has_method(&"is_active"), "the slime has no strike rig"):
		return
	await t.steps(2)
	t.check(not bool(rig.call(&"is_active")), "the Spear is drawn at rest")
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	var started := await t.until(func() -> bool: return bool(shapes.call(&"is_busy")), 300.0)
	if not t.check(started, "the strike did not start"):
		return
	t.check(await t.until(func() -> bool: return bool(rig.call(&"is_active")), 200.0), "the Spear is not drawn during the strike")
	var finished := await t.until(func() -> bool: return not bool(shapes.call(&"is_busy")), 1500.0)
	if not t.check(finished, "the strike did not finish"):
		return
	await t.steps(2)
	t.check(not bool(rig.call(&"is_active")), "the Spear is still drawn after the strike")


func test_worm_dies_after_enough_strikes_and_is_freed(t: TestContext) -> void:
	var shapes: Object = await _lend_spear(t)
	if shapes == null:
		return
	var worm := t.spawn_worm(SPEAR_TARGET_OFFSET, true)
	if worm == null:
		return
	var body := worm.body
	var freed := {"at": -1.0}
	body.tree_exited.connect(func() -> void: freed["at"] = t.now())
	var hits := _record_routes(t, worm.damage_area, body)
	var allowed: Array[int] = []
	for index in ShapeDefs.step_count(ShapeDefs.SPEAR):
		allowed.append_array(_step_damages(index))
	var damages: Array[int] = []
	var defeated_at := -1.0
	for swing in 12:
		var ready := await t.until(func() -> bool:
			return not bool(shapes.call(&"is_busy")) and not t.player().is_action_locked(), 2000.0)
		if not t.check(ready, "the Spear was not ready for strike %d" % (swing + 1)):
			return
		t.place_worm(worm, t.player().get_centre() + SPEAR_TARGET_OFFSET)
		t.player().face(Vector2.RIGHT)
		var before := hits.size()
		t.tap(&"attack")
		if not t.check(await t.until(func() -> bool: return hits.size() > before, 900.0), "strike %d did not reach the worm" % (swing + 1)):
			return
		var result: Dictionary = hits[hits.size() - 1]["result"]
		if not t.equal(result.get("status"), "accepted", "strike %d status (reason '%s')" % [swing + 1, result.get("reason", "")]):
			return
		var damage := int(result.get("actual_damage", 0))
		damages.append(damage)
		var expected_hp := WORM_MAX_HP
		for d in damages:
			expected_hp -= d
		t.near(float(worm.get_damage_state()["hp"]), maxf(0.0, expected_hp), 0.001, "worm HP after hit %d" % damages.size())
		if bool(result.get("defeated", false)):
			defeated_at = float(hits[hits.size() - 1]["now"])
			break
	t.note("hits: %s" % [damages])
	t.check(defeated_at >= 0.0, "the worm was not defeated after %d hits %s" % [damages.size(), damages])
	t.equal(damages.size(), _hits_to_kill(damages), "hits to kill (damages %s)" % [damages])
	for d in damages.slice(0, damages.size() - 1):
		t.check(allowed.has(d), "a Spear hit did %d (a chain step's damage: %s)" % [d, allowed])
	if defeated_at < 0.0:
		return
	t.check(worm.is_defeated(), "is_defeated() false after the killing blow")
	t.equal(worm.get_runtime_state(), "dead", "runtime state after the killing blow")
	await t.until(func() -> bool: return freed["at"] >= 0.0, DISPOSE_AFTER_DEFEAT_MS + 500.0)
	if not t.check(freed["at"] >= 0.0, "the defeated worm was not freed within %d ms" % (DISPOSE_AFTER_DEFEAT_MS + 500.0)):
		return
	t.between(float(freed["at"]) - defeated_at, DISPOSE_AFTER_DEFEAT_MS, DISPOSE_AFTER_DEFEAT_MS + TestContext.STEP_MS + 0.01,
		"defeat -> free delay (gameplay ms)")


func test_worm_attack_hits_player_for_34_after_windup_and_respects_iframes(t: TestContext) -> void:
	var player := t.player()
	var hurtbox := player.get_damage_area()
	var routes := _record_routes(t, hurtbox, player.body)
	var starts: Array = []
	# Two worms on either side swing in the same tick: the first lands, the second hits the
	# i-frames the first one granted.
	var right := t.spawn_worm(Vector2(WORM_ATTACK_OFFSET, 0.0))
	var left := t.spawn_worm(Vector2(-WORM_ATTACK_OFFSET, 0.0))
	if right == null or left == null:
		return
	for worm: EnemyScript in [right, left]:
		worm.attack_started.connect(func(_payload: Dictionary) -> void: starts.append(t.now()))
	if not t.check(await t.until(func() -> bool: return routes.size() >= 2, 1500.0),
			"the worms routed %d swing(s) at the player within 1.5 s (expected 2)" % routes.size()):
		return
	if not t.check(starts.size() >= 2, "only %d attack_started signal(s)" % starts.size()):
		return
	t.near(float(starts[0]), float(starts[1]), 0.001, "the two worms' swing start times")
	var first: Dictionary = routes[0]
	var second: Dictionary = routes[1]
	t.near(float(first["now"]) - float(starts[0]), WORM_WINDUP_MS, TestContext.STEP_MS + 0.01, "swing start -> impact (ms)")
	var first_result: Dictionary = first["result"]
	t.equal(first_result.get("status"), "accepted", "first worm hit status")
	t.equal(int(first_result.get("actual_damage", 0)), WORM_HIT_ON_PLAYER, "worm damage to the player")
	t.equal(player.get_hp(), player.get_max_hp() - WORM_HIT_ON_PLAYER, "player HP after one worm hit")
	t.near((first["velocity"] as Vector2).length(), PLAYER_KNOCKBACK_SPEED, 0.01, "player knockback speed")
	var second_result: Dictionary = second["result"]
	t.near(float(second["now"]), float(first["now"]), 0.001, "the second worm's impact time")
	t.check(second_result.get("status") == "rejected" and second_result.get("reason") == "state-blocked",
		"second worm hit inside the i-frames: got %s/%s, expected rejected/state-blocked" % [second_result.get("status"), second_result.get("reason")])
	# I-frames last 500 ms from the accepted hit.
	var hit_time := float(first["now"])
	var during := player.can_receive_damage({"simulation_time": hit_time + PLAYER_IFRAMES_MS - 1.0})
	var after := player.can_receive_damage({"simulation_time": hit_time + PLAYER_IFRAMES_MS})
	t.check(not bool(during.get("accepted", true)), "damage 499 ms after a hit was accepted (i-frames 500 ms)")
	t.check(bool(after.get("accepted", false)), "damage 500 ms after a hit was rejected: %s" % [after])


func test_worm_hits_kill_the_player_then_respawn_at_spawn(t: TestContext) -> void:
	var player := t.player()
	var damage_taken: Array[int] = []
	var timeline := {"dead_real": -1.0, "respawn_real": -1.0, "respawn_payload": {}}
	player.damaged.connect(func(commit: Dictionary) -> void:
		damage_taken.append(int((commit.get("result", {}) as Dictionary).get("actual_damage", 0))))
	player.defeated.connect(func(_payload: Dictionary) -> void: timeline["dead_real"] = float(Time.get_ticks_msec()))
	player.respawned.connect(func(payload: Dictionary) -> void:
		timeline["respawn_real"] = float(Time.get_ticks_msec())
		timeline["respawn_payload"] = payload)
	if t.spawn_worm(Vector2(WORM_ATTACK_OFFSET, 0.0)) == null:
		return
	if not t.check(await t.until(func() -> bool: return player.is_dead(), 20000.0),
			"the worm did not kill the player within 20 s (hits %s, HP %d)" % [damage_taken, player.get_hp()]):
		return
	var expected: Array[int] = []
	for i in WORM_HITS_TO_KILL:
		expected.append(WORM_HIT_ON_PLAYER)
	t.equal(damage_taken, expected, "damage taken until death")
	t.equal(player.get_hp(), 0, "HP at death")
	await t.until(func() -> bool: return timeline["respawn_real"] >= 0.0, 10000.0, 4000.0)
	if not t.check(timeline["respawn_real"] >= 0.0, "the player did not respawn within 4 s (real time)"):
		return
	t.between(float(timeline["respawn_real"]) - float(timeline["dead_real"]), 1398.0, 1500.0, "death -> respawn delay (real ms, 1 ms clock granularity)")
	t.check(not player.is_dead(), "still dead after respawning")
	t.equal(player.get_hp(), player.get_max_hp(), "HP after respawn")
	t.equal(player.get_max_hp(), PLAYER_MAX_HP, "max HP")
	var world := t.world()
	var spawn := world.find_spawn_point(world.player_spawn_marker())
	t.near_vec(player.get_centre(), spawn, 0.01, "respawn position (centre)")
	t.note("respawned at %s (findSpawnPoint of the level-1 marker %s)" % [player.get_centre(), world.player_spawn_marker()])


## Records DamageRouter routes that target `area`: [{"request", "result", "now", "velocity" (of
## `body` right after the commit), "centre" (old Phaser position of `body`)}].
func _record_routes(t: TestContext, area: Area2D, body: CharacterBody2D) -> Array:
	var routes: Array = []
	var router := Services.router()
	t.listen(router.routed, func(payload: Dictionary) -> void:
		var request: Dictionary = payload.get("request", {})
		if request.get("target_area") != area:
			return
		routes.append({
			"request": request,
			"result": payload.get("result", {}),
			"now": t.now(),
			"velocity": body.velocity if is_instance_valid(body) else Vector2.ZERO,
			"centre": FeetAnchor.phaser_position(body) if is_instance_valid(body) else Vector2.ZERO,
		}))
	return routes


## Smallest number of the leading `damages` whose sum reaches the worm's HP.
static func _hits_to_kill(damages: Array[int]) -> int:
	var total := 0
	for i in damages.size():
		total += damages[i]
		if total >= WORM_MAX_HP:
			return i + 1
	return damages.size() + 1


## Lends the Spear for the session (as the playground and `?shapes` do) and makes it the current
## shape; the player's ShapeController, or null.
func _lend_spear(t: TestContext) -> Object:
	Services.run().learn_session_ability(String(ShapeDefs.SPEAR))
	var shapes: Object = t.player().get_shapes()
	if not t.check(shapes != null and bool(shapes.call(&"set_current", ShapeDefs.SPEAR)), "the Spear could not be made current"):
		return null
	await t.steps(1)
	return shapes


## The damage of the Spear's chain step `index`, plain then critical: `baseDamage` x (attack / 10) x
## the step's `damageScale` (ShapeDefs.damage), rounded by the resolver.
static func _step_damages(index: int) -> Array[int]:
	var plain := ShapeDefs.damage(ShapeDefs.SPEAR, ShapeDefs.num(ShapeDefs.step(ShapeDefs.SPEAR, index), "damageScale", 1.0))
	var crit := Services.constants().number(CRIT_MULTIPLIER_PATH)
	var damages: Array[int] = [roundi(plain), roundi(plain * crit)]
	return damages
