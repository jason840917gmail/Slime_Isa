extends RefCounted
class_name NpcWanderPolicy
## Pure NPC wander state machine (Phaser `features/npcs/NpcWanderPolicy.ts:19-86`,
## `content/npcs/npcWanderGeometry.ts:8-27`). World spec 5.2 and 5.4. No node access.
##
## State Dictionary: {"phase": "pause"|"move", "pause_remaining_ms": float,
##   "target": Vector2 or null, "facing": "down"|"up"|"left"|"right",
##   "stuck_sample_remaining_ms": float, "previous_distance": float or null}.
## Domain Dictionary: a Perimeter dictionary (res://game/shared/perimeter.gd) or {} (none).
##
## Owner: world builder.

const Perimeter := preload("res://game/shared/perimeter.gd")

## NpcWanderPolicy.ts literals.
const AREA_MARGIN := 8.0
const TARGET_ARRIVAL_DISTANCE := 6.0
const STUCK_PROGRESS_DISTANCE := 2.0
const STUCK_SAMPLE_MS := 750.0

const PHASE_PAUSE := "pause"
const PHASE_MOVE := "move"
const ANIM_IDLE := "idle"


## `createState(pauseMs = 0, facing = "down")` (world spec 5.4).
static func create_state(pause_ms: float = 0.0, facing: String = "down") -> Dictionary:
	return {
		"phase": PHASE_PAUSE if pause_ms > 0.0 else PHASE_MOVE,
		"pause_remaining_ms": maxf(0.0, pause_ms),
		"target": null,
		"facing": facing,
		"stuck_sample_remaining_ms": STUCK_SAMPLE_MS,
		"previous_distance": null,
	}


## `step(state, position, deltaMs, speed)` -> {"state": Dictionary, "velocity": Vector2,
## "animation": "idle" | "walk-<facing>"}; world spec 5.4 steps 1-7 exactly (a pause ending
## this tick moves in the same tick; velocity never overshoots the target).
static func step(state: Dictionary, position: Vector2, delta_ms: float, speed: float, domain: Dictionary) -> Dictionary:
	var dt := maxf(0.0, delta_ms) if is_finite(delta_ms) else 0.0
	var spd := maxf(0.0, speed) if is_finite(speed) else 0.0
	var facing: String = state.get("facing", "down")
	if spd <= 0.0:
		return _result(create_state(0.0, facing), Vector2.ZERO, ANIM_IDLE)

	var next := state.duplicate()
	if next["phase"] == PHASE_PAUSE:
		var remaining := maxf(0.0, float(next["pause_remaining_ms"]) - dt)
		next["pause_remaining_ms"] = remaining
		next["phase"] = PHASE_PAUSE if remaining > 0.0 else PHASE_MOVE
		next["target"] = null
		next["stuck_sample_remaining_ms"] = STUCK_SAMPLE_MS
		next["previous_distance"] = null
		if next["phase"] == PHASE_PAUSE:
			return _result(next, Vector2.ZERO, ANIM_IDLE)

	var target: Variant = next.get("target")
	if target == null:
		if domain.is_empty():
			next["phase"] = PHASE_PAUSE
			next["pause_remaining_ms"] = 0.0
			next["target"] = null
			return _result(next, Vector2.ZERO, ANIM_IDLE)
		target = Perimeter.random_point(domain)
	var goal: Vector2 = target
	var d := goal - position
	var distance := d.length()
	if distance <= TARGET_ARRIVAL_DISTANCE:
		return _result(_resting(next), Vector2.ZERO, ANIM_IDLE)

	var new_facing: String
	if absf(d.x) >= absf(d.y):
		new_facing = "left" if d.x < 0.0 else "right"
	else:
		new_facing = "up" if d.y < 0.0 else "down"
	var sample_remaining := float(next["stuck_sample_remaining_ms"]) - dt
	var previous: Variant = next.get("previous_distance")
	var made_progress := previous == null or float(previous) - distance >= STUCK_PROGRESS_DISTANCE
	if sample_remaining <= 0.0 and not made_progress:
		return _result(_resting(next), Vector2.ZERO, ANIM_IDLE)

	var delta_seconds := dt / 1000.0
	var magnitude := minf(spd, distance / delta_seconds) if delta_seconds > 0.0 else spd
	next["phase"] = PHASE_MOVE
	next["target"] = goal
	next["facing"] = new_facing
	if sample_remaining > 0.0:
		next["stuck_sample_remaining_ms"] = sample_remaining
		next["previous_distance"] = distance if previous == null else float(previous)
	else:
		next["stuck_sample_remaining_ms"] = STUCK_SAMPLE_MS
		next["previous_distance"] = distance
	return _result(next, d / distance * magnitude, "walk-" + new_facing)


## Wander domain from an area perimeter and the body bounds (world spec 5.2): circle radius
## shrinks by the farthest body corner + margin; rectangle insets by margin and the bounds.
## {} when the result is empty (radius <= 0 or w/h <= 0).
## `body_bounds` = Rect2(minX, minY, width, height) relative to the old root.
static func wander_domain(perimeter: Dictionary, body_bounds: Rect2) -> Dictionary:
	if perimeter.is_empty():
		return {}
	var min_x := body_bounds.position.x
	var min_y := body_bounds.position.y
	var max_x := body_bounds.end.x
	var max_y := body_bounds.end.y
	if perimeter["shape"] == Perimeter.SHAPE_CIRCLE:
		var body_radius := maxf(maxf(Vector2(min_x, min_y).length(), Vector2(min_x, max_y).length()),
			maxf(Vector2(max_x, min_y).length(), Vector2(max_x, max_y).length()))
		var radius := float(perimeter["radius"]) - body_radius - AREA_MARGIN
		if radius <= 0.0:
			return {}
		return {"shape": Perimeter.SHAPE_CIRCLE, "x": float(perimeter["x"]), "y": float(perimeter["y"]), "radius": radius}
	var left := AREA_MARGIN - min_x
	var right := AREA_MARGIN + max_x
	var top := AREA_MARGIN - min_y
	var bottom := AREA_MARGIN + max_y
	var w := float(perimeter["w"]) - left - right
	var h := float(perimeter["h"]) - top - bottom
	if w <= 0.0 or h <= 0.0:
		return {}
	return {"shape": Perimeter.SHAPE_RECTANGLE, "x": float(perimeter["x"]) + left, "y": float(perimeter["y"]) + top, "w": w, "h": h}


## Arrival / stuck result state: pause 0, no target, fresh stuck window (facing kept).
static func _resting(state: Dictionary) -> Dictionary:
	var rest := state.duplicate()
	rest["phase"] = PHASE_PAUSE
	rest["pause_remaining_ms"] = 0.0
	rest["target"] = null
	rest["stuck_sample_remaining_ms"] = STUCK_SAMPLE_MS
	rest["previous_distance"] = null
	return rest


static func _result(state: Dictionary, velocity: Vector2, animation: String) -> Dictionary:
	return {"state": state, "velocity": velocity, "animation": animation}
