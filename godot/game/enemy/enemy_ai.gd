extends RefCounted
class_name EnemyAI
## Base enemy combat AI (Phaser `enemies/EnemyAI.ts`): states idle, wander, chase, attack, flee,
## dead, plus the safe-zone push-out applied before every state. Enemy spec 4.4. Pure logic; the
## enemy script owns the velocity and calls begin_attack itself.
##
## Context Dictionary passed in by enemy.gd:
## {"centre": Vector2, "distance": float, "dir": Vector2 (unit, enemy -> player),
##  "aggro": float, "attack_range": float, "wander_speed": float, "chase_speed": float,
##  "may_engage": bool, "safe_zones": Array[Dictionary] (rectangle perimeters)}
## Optional keys: "flee_range": float (> 0 enables the keep-distance rules of ranged enemies;
## absent or <= 0 for the worm swordsman); "in_attack_reach": bool (EnemyAI.ts:271-273, 309:
## an authored attack area decides reach, replacing the `attack_range` distance checks; absent
## for the worm, set by bosses such as Fatty).
##
## Randomness: one `randf()` per `Math.random()` call, in the same order (enemy spec 10).
##
## Owner: enemy builder.

## EnemyAI.ts literals (per AI call; frame-rate dependent, keep physics at 60 Hz).
const IDLE_TO_WANDER_CHANCE := 0.01
const WANDER_REPICK_CHANCE := 0.02
const WANDER_TO_IDLE_CHANCE := 0.005
const CHASE_GIVE_UP_MULTIPLIER := 1.5
const ATTACK_KEEP_REACH_MULTIPLIER := 1.3
const SAFE_ZONE_PUSH_MULTIPLIER := 1.25
## EnemyScript.ts:449-487: at most three state transitions per step.
const MAX_TRANSITIONS := 3

const STATE_IDLE := "idle"
const STATE_WANDER := "wander"
const STATE_CHASE := "chase"
const STATE_ATTACK := "attack"
const STATE_FLEE := "flee"
const STATE_DEAD := "dead"
const CONTINUE := "continue"


## The AI loop of enemy spec 4.4 (up to 3 state transitions per step; stop early when the
## velocity changed to a non-zero value). Returns {"state": String, "velocity": Vector2,
## "attack_requested": bool, "attack_dir": Vector2}. `attack_requested` replaces Phaser's
## in-loop `requestAttack(dir)`: enemy.gd calls `begin_attack(attack_dir)` right after the loop.
## (Equivalent: the attack state is the only requester and always returns CONTINUE, which ends
## the loop, so the request is always the last thing the loop does.)
static func run(state: String, velocity: Vector2, ctx: Dictionary) -> Dictionary:
	var current := state
	var current_velocity := velocity
	var attack_requested := false
	var attack_dir := Vector2.ZERO
	for _transition in MAX_TRANSITIONS:
		var before := current_velocity
		var result := run_state(current, current_velocity, ctx)
		current_velocity = result["velocity"]
		if result["attack_requested"]:
			attack_requested = true
			attack_dir = ctx.get("dir", Vector2.ZERO)
		var next: String = result["next"]
		if next == CONTINUE:
			break
		current = next
		var started_moving := current_velocity != Vector2.ZERO
		var velocity_changed := current_velocity != before
		if started_moving and velocity_changed:
			break
	return {"state": current, "velocity": current_velocity, "attack_requested": attack_requested,
		"attack_dir": attack_dir}


## One state call: safe-zone push-out first (except dead), then the state function.
## Returns {"next": String (a state or CONTINUE), "velocity": Vector2, "attack_requested": bool}.
static func run_state(state: String, velocity: Vector2, ctx: Dictionary) -> Dictionary:
	var chase_speed: float = ctx.get("chase_speed", 0.0)
	if state != STATE_DEAD:
		var axis := _safe_zone_axis(ctx.get("centre", Vector2.ZERO), ctx.get("safe_zones", []))
		if axis != Vector2.ZERO:
			return _result(STATE_FLEE, axis * chase_speed * SAFE_ZONE_PUSH_MULTIPLIER)
		# EnemyAI.ts enforceSpawnArea is dead in practice for camp enemies (enemy spec 0): not ported.

	var distance: float = ctx.get("distance", 0.0)
	var dir: Vector2 = ctx.get("dir", Vector2.ZERO)
	var aggro: float = ctx.get("aggro", 0.0)
	var attack_range: float = ctx.get("attack_range", 0.0)
	var flee_range: float = ctx.get("flee_range", 0.0)
	var may_engage: bool = ctx.get("may_engage", distance <= aggro)

	match state:
		STATE_IDLE:
			if may_engage:
				return _result(STATE_CHASE, Vector2.ZERO)
			if randf() < IDLE_TO_WANDER_CHANCE:
				return _result(STATE_WANDER, Vector2.ZERO)
			return _result(CONTINUE, Vector2.ZERO)
		STATE_WANDER:
			if may_engage:
				return _result(STATE_CHASE, Vector2.ZERO)
			var wander_velocity := velocity
			if randf() < WANDER_REPICK_CHANCE:
				var angle := randf() * TAU
				var wander_speed: float = ctx.get("wander_speed", 0.0)
				wander_velocity = Vector2(cos(angle), sin(angle)) * wander_speed
			if randf() < WANDER_TO_IDLE_CHANCE:
				return _result(STATE_IDLE, Vector2.ZERO)
			return _result(CONTINUE, wander_velocity)
		STATE_CHASE:
			if distance > aggro * CHASE_GIVE_UP_MULTIPLIER:
				return _result(STATE_WANDER, velocity)
			if flee_range > 0.0 and distance < flee_range:
				return _result(STATE_FLEE, velocity)
			var in_reach: bool = bool(ctx["in_attack_reach"]) if ctx.has("in_attack_reach") else distance <= attack_range
			if in_reach:
				return _result(STATE_ATTACK, Vector2.ZERO)
			return _result(CONTINUE, dir * chase_speed)
		STATE_ATTACK:
			var out_of_reach: bool = not bool(ctx["in_attack_reach"]) if ctx.has("in_attack_reach") \
				else distance > attack_range * ATTACK_KEEP_REACH_MULTIPLIER
			if out_of_reach:
				return _result(STATE_CHASE, velocity)
			var attack := _result(CONTINUE, Vector2.ZERO)
			attack["attack_requested"] = true
			return attack
		STATE_FLEE:
			if flee_range > 0.0 and distance >= flee_range:
				return _result(STATE_ATTACK, Vector2.ZERO)
			if distance > aggro * CHASE_GIVE_UP_MULTIPLIER:
				return _result(STATE_WANDER, velocity)
			# Runs away from the player.
			return _result(CONTINUE, -dir * chase_speed)
		STATE_DEAD:
			return _result(CONTINUE, velocity)
	return _result(CONTINUE, velocity)


## Safe-zone push (EnemyAI.ts:208-234): for the first safe-zone rectangle containing the centre
## (inclusive), the outward axis of the nearest edge (ties: left, right, top, bottom) times
## chase_speed * 1.25. Returns Vector2.ZERO when the centre is in no safe zone.
static func safe_zone_push(centre: Vector2, safe_zones: Array, chase_speed: float) -> Vector2:
	return _safe_zone_axis(centre, safe_zones) * chase_speed * SAFE_ZONE_PUSH_MULTIPLIER


## Outward unit axis of the nearest edge of the first safe zone containing `centre`
## (Vector2.ZERO when none contains it).
static func _safe_zone_axis(centre: Vector2, safe_zones: Array) -> Vector2:
	for zone_value: Variant in safe_zones:
		if not zone_value is Dictionary:
			continue
		var zone: Dictionary = zone_value
		var x := float(zone.get("x", 0.0))
		var y := float(zone.get("y", 0.0))
		var w := float(zone.get("w", 0.0))
		var h := float(zone.get("h", 0.0))
		if centre.x < x or centre.x > x + w or centre.y < y or centre.y > y + h:
			continue
		var nearest_distance := centre.x - x
		var nearest_axis := Vector2(-1.0, 0.0)
		var candidates: Array = [
			[x + w - centre.x, Vector2(1.0, 0.0)],
			[centre.y - y, Vector2(0.0, -1.0)],
			[y + h - centre.y, Vector2(0.0, 1.0)],
		]
		for candidate: Array in candidates:
			var candidate_distance: float = candidate[0]
			if candidate_distance < nearest_distance:
				nearest_distance = candidate_distance
				nearest_axis = candidate[1]
		return nearest_axis
	return Vector2.ZERO


static func _result(next: String, velocity: Vector2) -> Dictionary:
	return {"next": next, "velocity": velocity, "attack_requested": false}
