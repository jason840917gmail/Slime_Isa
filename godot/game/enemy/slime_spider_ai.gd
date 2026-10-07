extends RefCounted
class_name SlimeSpiderAI
## Ranged spider behaviour (Phaser `enemies/ai/SlimeSpiderAI.ts`): approach while orbiting, hold a
## preferred distance, retreat around the player when pressured, keep spitting through the common
## attack. Enemy spec 14. Used by `EnemyAI.run_state` for `attributes.behavior == "slime-spider"`
## (slime spider, orb weaver, the Orb-Weaver Matron) after the safe-zone push.
##
## Context keys (enemy_ai.gd): "distance", "dir", "centre", "aggro", "attack_range",
## "wander_speed", "chase_speed", "may_engage", plus "preferred_distance" (enemy.gd:
## `max(1, fleeRange ?? attackRange * 0.55)`).
## Returns the same {"next", "velocity", "attack_requested"} shape as `EnemyAI.run_state`.
##
## Owner: enemy port.

## SlimeSpiderAI.ts literals (per AI call; frame-rate dependent like the base AI).
const IDLE_TO_WANDER_CHANCE := 0.008
const WANDER_REPICK_CHANCE := 0.02
const WANDER_TO_IDLE_CHANCE := 0.004
const GIVE_UP_MULTIPLIER := 1.5
const ATTACK_KEEP_REACH_MULTIPLIER := 1.3
const PRESSURED_MULTIPLIER := 0.72
const APPROACH_RADIAL := 0.86
const APPROACH_LATERAL := 0.52
const RETREAT_RADIAL := -0.92
const RETREAT_LATERAL := 0.44
const RETREAT_SPEED_MULTIPLIER := 1.08
## Orbit side: sign of sin(x * 0.017 + y * 0.013) of the spider's centre.
const ORBIT_SIGN_X := 0.017
const ORBIT_SIGN_Y := 0.013
## Fallback preferred distance as a share of the attack range (`fleeRange` absent).
const PREFERRED_RANGE_SHARE := 0.55

const STATE_IDLE := "idle"
const STATE_WANDER := "wander"
const STATE_CHASE := "chase"
const STATE_ATTACK := "attack"
const STATE_FLEE := "flee"
const STATE_DEAD := "dead"
const CONTINUE := "continue"


## `preferredDistance` (:33-35): max(1, flee_range when authored, else attack_range * 0.55).
## `flee_range < 0` means "absent".
static func preferred_distance(flee_range: float, attack_range: float) -> float:
	return maxf(1.0, flee_range if flee_range >= 0.0 else attack_range * PREFERRED_RANGE_SHARE)


## `runSlimeSpiderState` (:16-31) for one state.
static func run_state(state: String, velocity: Vector2, ctx: Dictionary) -> Dictionary:
	var distance: float = ctx.get("distance", 0.0)
	var aggro: float = ctx.get("aggro", 0.0)
	var attack_range: float = ctx.get("attack_range", 0.0)
	var chase_speed: float = ctx.get("chase_speed", 0.0)
	var preferred: float = ctx.get("preferred_distance", 1.0)
	var notices: bool = ctx.get("may_engage", distance <= aggro)
	match state:
		STATE_IDLE:
			if notices:
				return _result(STATE_CHASE, Vector2.ZERO)
			if randf() < IDLE_TO_WANDER_CHANCE:
				return _result(STATE_WANDER, Vector2.ZERO)
			return _result(CONTINUE, Vector2.ZERO)
		STATE_WANDER:
			if notices:
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
			if distance > aggro * GIVE_UP_MULTIPLIER:
				return _result(STATE_WANDER, velocity)
			if distance <= attack_range:
				if distance < preferred:
					return _result(STATE_FLEE, velocity)
				return _result(STATE_ATTACK, Vector2.ZERO)
			return _result(CONTINUE, orbit_velocity(ctx, APPROACH_RADIAL, APPROACH_LATERAL, chase_speed))
		STATE_FLEE:
			if distance > aggro * GIVE_UP_MULTIPLIER:
				return _result(STATE_WANDER, velocity)
			if distance >= preferred:
				return _result(STATE_ATTACK if distance <= attack_range else STATE_CHASE, velocity)
			return _result(CONTINUE, orbit_velocity(ctx, RETREAT_RADIAL, RETREAT_LATERAL,
				chase_speed * RETREAT_SPEED_MULTIPLIER))
		STATE_ATTACK:
			if distance > attack_range * ATTACK_KEEP_REACH_MULTIPLIER:
				return _result(STATE_CHASE, velocity)
			if distance < preferred * PRESSURED_MULTIPLIER:
				return _result(STATE_FLEE, velocity)
			var attack := _result(CONTINUE, Vector2.ZERO)
			attack["attack_requested"] = true
			return attack
	return _result(CONTINUE, velocity)


## `setOrbitVelocity` (:102-120): the direction to the player weighted with its tangent (side
## picked from the spider's centre), normalised to `speed`.
static func orbit_velocity(ctx: Dictionary, radial_weight: float, lateral_weight: float, speed: float) -> Vector2:
	var direction: Vector2 = ctx.get("dir", Vector2.ZERO)
	var centre: Vector2 = ctx.get("centre", Vector2.ZERO)
	var orbit_sign := 1.0 if sin(centre.x * ORBIT_SIGN_X + centre.y * ORBIT_SIGN_Y) >= 0.0 else -1.0
	var tangent := Vector2(-direction.y * orbit_sign, direction.x * orbit_sign)
	var blend := direction * radial_weight + tangent * lateral_weight
	var length := blend.length()
	if length == 0.0:
		length = 1.0
	return blend / length * speed


static func _result(next: String, velocity: Vector2) -> Dictionary:
	return {"next": next, "velocity": velocity, "attack_requested": false}
