extends RefCounted
## Sword vs worm swordsman and worm vs player (docs/godot/specs/combat.md section 15 "Expected
## trial numbers", enemy.md 5-7, player.md 6).
## - A basic-sword hit does 24 (combo x1.0 on a lone hit, owner decision O3); a crit does 42 (5 % chance,
##   so both are accepted and the crit is noted). The worm (90 HP, knockback resist 0.45) is
##   knocked back at (140 + 120) x 0.55 = 143 px/s along the swing, stunned 370 ms, ~30 px drift.
## - 90 HP takes 4 plain hits (24, 48, 72, then 18); the corpse is freed 800 ms (gameplay clock)
##   after the killing blow.
## - A worm swing lands 400 ms after it starts and does max(1, 37 - 3) = 34; the player then has
##   500 ms of i-frames (a second worm's simultaneous swing is rejected "state-blocked") and is
##   knocked back at 260 px/s.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const WORM_MAX_HP := 90.0
const SWORD_HIT := 24
const SWORD_CRIT_HIT := 42
const WORM_KNOCKBACK_SPEED := 143.0
const WORM_STUN_MS := 370.0
const WORM_WINDUP_MS := 400.0
const WORM_HIT_ON_PLAYER := 34
const PLAYER_IFRAMES_MS := 500.0
const PLAYER_KNOCKBACK_SPEED := 260.0
const DISPOSE_AFTER_DEFEAT_MS := 800.0
## Worm centre offset from the player centre: inside the sword's 57 px sector, outside the
## worm's 38 px attack range.
const SWORD_TARGET_OFFSET := Vector2(40.0, 0.0)
## Inside the worm's 38 px attack range.
const WORM_ATTACK_OFFSET := 34.0


func test_sword_hit_damages_and_knocks_back_worm(t: TestContext) -> void:
	var worm := t.spawn_worm(SWORD_TARGET_OFFSET)
	if worm == null:
		return
	await t.steps(1)
	var hits := _record_routes(t, worm.damage_area, worm.body)
	var paused_seen := {"value": false}
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	if not t.check(await t.until(func() -> bool: return not hits.is_empty(), 600.0), "the sword never routed a hit to the worm"):
		return
	var hit: Dictionary = hits[0]
	var result: Dictionary = hit["result"]
	if not t.equal(result.get("status"), "accepted", "sword hit status (reason '%s')" % result.get("reason", "")):
		return
	var damage := int(result.get("actual_damage", 0))
	t.check(damage == SWORD_HIT or damage == SWORD_CRIT_HIT, "sword damage: got %d, expected %d (or %d on a crit)" % [damage, SWORD_HIT, SWORD_CRIT_HIT])
	if damage == SWORD_CRIT_HIT:
		t.note("the swing was a critical hit (%d)" % damage)
	t.near(float(worm.get_damage_state()["hp"]), WORM_MAX_HP - damage, 0.001, "worm HP after one hit")
	t.near_vec(hit["velocity"], Vector2.RIGHT * WORM_KNOCKBACK_SPEED, 0.01, "worm knockback velocity")
	# Hit-stop: the tree pauses (deferred) right after the hit.
	await t.until(func() -> bool:
		paused_seen["value"] = paused_seen["value"] or t.tree.paused
		return t.now() >= float(hit["now"]) + WORM_STUN_MS, 1000.0)
	t.check(paused_seen["value"], "no hit-stop pause after the sword hit")
	var drift: Vector2 = worm.get_centre() - (hit["centre"] as Vector2)
	t.between(drift.x, 22.0, 36.0, "worm knockback drift over the %d ms stun (px)" % WORM_STUN_MS)
	t.near(drift.y, 0.0, 1.0, "worm vertical drift during the stun (px)")
	t.check(hits.size() == 1, "one swing routed %d hits to the worm (expected 1)" % hits.size())


## The sword is drawn only while it swings (owner decision 2026-10-05, `show_when_idle` off):
## hidden after equipping, visible from the swing start, hidden again when the swing ends.
func test_sword_shows_only_while_swinging(t: TestContext) -> void:
	var combat = t.player().get_combat()
	var weapon = combat.get_weapon()
	var root := weapon.get_parent() as CanvasItem
	await t.steps(2)
	t.equal(root.visible, false, "sword visible after equipping")
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	var started := await t.until(func() -> bool: return combat.is_attacking(), 300.0)
	if not t.check(started, "the swing did not start"):
		return
	t.equal(root.visible, true, "sword visible during the swing")
	var finished := await t.until(func() -> bool: return not combat.is_attacking(), 1500.0)
	if not t.check(finished, "the swing did not finish"):
		return
	await t.steps(1)
	t.equal(root.visible, false, "sword visible after the swing")


func test_worm_dies_after_four_hits_and_is_freed(t: TestContext) -> void:
	var worm := t.spawn_worm(SWORD_TARGET_OFFSET, true)
	if worm == null:
		return
	var body := worm.body
	var freed := {"at": -1.0}
	body.tree_exited.connect(func() -> void: freed["at"] = t.now())
	var hits := _record_routes(t, worm.damage_area, body)
	var combat = t.player().get_combat()
	var weapon = combat.get_weapon()
	var damages: Array[int] = []
	var defeated_at := -1.0
	for swing in 6:
		var ready := await t.until(func() -> bool:
			return not combat.is_attacking() and weapon.can_begin_attack() and not t.player().is_action_locked(), 2000.0)
		if not t.check(ready, "the sword was not ready for swing %d" % (swing + 1)):
			return
		t.place_worm(worm, t.player().get_centre() + SWORD_TARGET_OFFSET)
		t.player().face(Vector2.RIGHT)
		var before := hits.size()
		t.tap(&"attack")
		if not t.check(await t.until(func() -> bool: return hits.size() > before, 600.0), "swing %d did not reach the worm" % (swing + 1)):
			return
		var result: Dictionary = hits[hits.size() - 1]["result"]
		if not t.equal(result.get("status"), "accepted", "swing %d status (reason '%s')" % [swing + 1, result.get("reason", "")]):
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
	var expected_hits := _hits_to_kill(damages)
	t.check(defeated_at >= 0.0, "the worm was not defeated after %d hits %s" % [damages.size(), damages])
	t.equal(damages.size(), expected_hits, "hits to kill (damages %s)" % [damages])
	if not damages.has(SWORD_CRIT_HIT):
		t.equal(damages.size(), 4, "hits to kill with no crit")
	for d in damages.slice(0, damages.size() - 1):
		t.check(d == SWORD_HIT or d == SWORD_CRIT_HIT, "a sword hit did %d" % d)
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


func test_three_worm_hits_kill_the_player_then_respawn_at_spawn(t: TestContext) -> void:
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
	if not t.check(await t.until(func() -> bool: return player.is_dead(), 9000.0),
			"the worm did not kill the player within 9 s (hits %s, HP %d)" % [damage_taken, player.get_hp()]):
		return
	t.equal(damage_taken, [34, 34, 32] as Array[int], "damage taken until death")
	t.equal(player.get_hp(), 0, "HP at death")
	await t.until(func() -> bool: return timeline["respawn_real"] >= 0.0, 10000.0, 4000.0)
	if not t.check(timeline["respawn_real"] >= 0.0, "the player did not respawn within 4 s (real time)"):
		return
	t.between(float(timeline["respawn_real"]) - float(timeline["dead_real"]), 1398.0, 1500.0, "death -> respawn delay (real ms, 1 ms clock granularity)")
	t.check(not player.is_dead(), "still dead after respawning")
	t.equal(player.get_hp(), player.get_max_hp(), "HP after respawn")
	t.equal(player.get_max_hp(), 100, "max HP")
	var world := t.world()
	var spawn := world.find_spawn_point(world.player_spawn_marker())
	t.near_vec(player.get_centre(), spawn, 0.01, "respawn position (centre)")
	t.note("respawned at %s (findSpawnPoint of the level-1 marker %s)" % [player.get_centre(), world.player_spawn_marker()])


## Records DamageRouter routes that target `area`: [{"result", "now", "velocity" (of `body` right
## after the commit), "centre" (old Phaser position of `body`)}].
func _record_routes(t: TestContext, area: Area2D, body: CharacterBody2D) -> Array:
	var routes: Array = []
	var router := Services.router()
	t.listen(router.routed, func(payload: Dictionary) -> void:
		var request: Dictionary = payload.get("request", {})
		if request.get("target_area") != area:
			return
		routes.append({
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
