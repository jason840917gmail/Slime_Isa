extends RefCounted
## Line-up AI of the four-way shooters (owner, 2026-10-16: the archer "will always try to get
## horizontal or perpendicular to you, since his arrow can only be shot in 4 directions, not
## diagonals, similar to the archer in Zelda"; the spiders too). Enemy spec 20.
##
## Used by `EnemyAI.run_state` for the chase, flee and attack states of an enemy that lines up
## (enemy.gd `_lines_up`: `behavior: "liner-up"`, the Worm Archer; `behavior: "slime-spider"` with an
## `alignSpeed`, the Slime Spider and the Orb-weaver). Idle and wander stay the base or spider AI's.
## One instance per enemy (it remembers the line it is running for); pure logic otherwise: the
## enemy hands in the probes.
##
## - **Lining up** (chase): it picks the nearer of the slime's row or column and runs to it at
##   `alignSpeed`, for a spot on that line at bow range: its own distance along the line, kept
##   between `fleeRange + alignMarginPx` and `attackRange - alignMarginPx`. A spot it cannot walk
##   to (`route_clear`) or shoot from (`shot_clear`) is passed over for the next (the other line,
##   then the far sides). The choice is made again every `alignReplanMs`; it keeps its line unless
##   another is `alignSwitchPx` nearer.
## - **Shooting** (attack): lined up (the slime's aim point within `alignTolerancePx` of its row or
##   column, FourWayAim.line_direction), within `attackRange` along the line and with a clear shot,
##   it stops and requests the attack along the line (`attack_dir`, a cardinal). It stays lined up
##   up to `attackRange` x 1.3, as the base AI keeps its reach. While a shot is in flight it holds
##   still: the wind-up is the tell, and the arrow goes down the line where the slime was.
## - **Too close** (flee, centre distance < `fleeRange`): it backs off to the spot on its line at
##   `backOffSpeed` (along the line when it is on it; a blocked way picks the other line, a
##   sidestep).
## - **Facing:** `face_dir` while it holds (along the line), and while it moves when
##   `faces_target` (the spiders scuttle sideways, looking at the slime).
##
## Context keys (enemy.gd): "centre", "aim_point" (the slime's hurtbox middle, where a shot must
## pass), "distance" (centre to centre), "aggro", "attack_range", "flee_range", "now", "step_s",
## "attacking" (a shot in flight), "faces_target", "route_clear" and "shot_clear" (Callables
## `(from, to) -> bool`; missing = clear) and "align" (the numbers: "speed", "back_off_speed",
## "tolerance", "margin", "replan_ms", "switch_px").
## Returns the `EnemyAI.run_state` shape plus the optional "attack_dir" and "face_dir".
##
## Owner: enemy builder.

const FourWayAim := preload("res://game/enemy/four_way_aim.gd")

## As the base AI (EnemyAI.ts): give up beyond aggro x 1.5, keep shooting up to range x 1.3.
const GIVE_UP_MULTIPLIER := 1.5
const ATTACK_KEEP_REACH_MULTIPLIER := 1.3

const STATE_CHASE := "chase"
const STATE_ATTACK := "attack"
const STATE_FLEE := "flee"
const STATE_WANDER := "wander"
const CONTINUE := "continue"

## The lines through the slime: its row (shots left or right) and its column (up or down).
const ROW := 0
const COLUMN := 1
const NO_LINE := -1

## The line it runs for (ROW, COLUMN or NO_LINE), the side of the slime (+1 right / below, -1),
## when it chose them, and the last shot probe.
var _line: int = NO_LINE
var _side: float = 1.0
var _planned_at: float = -INF
var _shot_checked_at: float = -INF
var _shot_checked_line: Vector2 = Vector2.ZERO
var _shot_was_clear: bool = false


## True for the states this AI runs (the rest stay the base or spider AI's).
static func handles(state: String) -> bool:
	return state == STATE_CHASE or state == STATE_FLEE or state == STATE_ATTACK


## A four-way shooter's shot direction: the cardinal nearest to `direction` (FourWayAim.snap).
static func snap_shot(direction: Vector2) -> Vector2:
	return FourWayAim.snap(direction)


## The line it runs for: ROW, COLUMN or NO_LINE.
func get_line() -> int:
	return _line


func run_state(state: String, velocity: Vector2, ctx: Dictionary) -> Dictionary:
	if state == STATE_ATTACK:
		return _hold(velocity, ctx)
	return _position(state, velocity, ctx)


## Chase and flee: shoot when lined up, else run to the spot on its line.
func _position(state: String, velocity: Vector2, ctx: Dictionary) -> Dictionary:
	var distance: float = ctx.get("distance", 0.0)
	if distance > float(ctx.get("aggro", 0.0)) * GIVE_UP_MULTIPLIER:
		_line = NO_LINE
		return _result(STATE_WANDER, velocity)
	if bool(ctx.get("attacking", false)):
		return _result(STATE_ATTACK, Vector2.ZERO)
	var too_close := _too_close(ctx)
	var wanted := STATE_FLEE if too_close else STATE_CHASE
	if wanted != state:
		return _result(wanted, velocity)
	if not too_close and _shot_line(ctx, float(ctx.get("attack_range", 0.0))) != Vector2.ZERO:
		return _result(STATE_ATTACK, Vector2.ZERO)
	_plan(ctx)
	var centre: Vector2 = ctx.get("centre", Vector2.ZERO)
	var aim := _aim(ctx)
	var numbers: Dictionary = ctx.get("align", {})
	var speed := float(numbers.get("back_off_speed" if too_close else "speed", 0.0))
	var spot := _spot(_line, _side, centre, aim, ctx)
	var result := _result(CONTINUE, _toward(centre, spot, speed, float(ctx.get("step_s", 0.0))))
	if bool(ctx.get("faces_target", false)):
		result["face_dir"] = FourWayAim.snap(aim - centre)
	return result


## Attack: hold still on the line and request the shot along it (the cooldown decides when).
func _hold(_velocity: Vector2, ctx: Dictionary) -> Dictionary:
	if bool(ctx.get("attacking", false)):
		return _result(CONTINUE, Vector2.ZERO)
	if _too_close(ctx):
		return _result(STATE_FLEE, Vector2.ZERO)
	var line := _shot_line(ctx, float(ctx.get("attack_range", 0.0)) * ATTACK_KEEP_REACH_MULTIPLIER)
	if line == Vector2.ZERO:
		return _result(STATE_CHASE, Vector2.ZERO)
	var attack := _result(CONTINUE, Vector2.ZERO)
	attack["attack_requested"] = true
	attack["attack_dir"] = line
	attack["face_dir"] = line
	return attack


func _too_close(ctx: Dictionary) -> bool:
	var flee_range: float = ctx.get("flee_range", 0.0)
	return flee_range > 0.0 and float(ctx.get("distance", 0.0)) < flee_range


## The cardinal along the row or column it shares with the slime's aim point, when that point is
## within `max_along` along it and the shot is clear; else zero.
func _shot_line(ctx: Dictionary, max_along: float) -> Vector2:
	var centre: Vector2 = ctx.get("centre", Vector2.ZERO)
	var aim := _aim(ctx)
	var numbers: Dictionary = ctx.get("align", {})
	var line := FourWayAim.line_direction(centre, aim, float(numbers.get("tolerance", 0.0)))
	if line == Vector2.ZERO:
		return Vector2.ZERO
	var along := (aim - centre).dot(line)
	if along > max_along:
		return Vector2.ZERO
	var now: float = ctx.get("now", 0.0)
	if line != _shot_checked_line or now - _shot_checked_at >= float(numbers.get("replan_ms", 0.0)):
		_shot_checked_line = line
		_shot_checked_at = now
		_shot_was_clear = _probe(ctx, "shot_clear", centre, centre + line * along)
	return line if _shot_was_clear else Vector2.ZERO


## Chooses the line and side to run for (every `replan_ms`, or when it has none): the nearest spot
## it can walk to and shoot from; the current one while it is no more than `switch_px` further.
func _plan(ctx: Dictionary) -> void:
	var numbers: Dictionary = ctx.get("align", {})
	var now: float = ctx.get("now", 0.0)
	if _line != NO_LINE and now - _planned_at < float(numbers.get("replan_ms", 0.0)):
		return
	_planned_at = now
	var centre: Vector2 = ctx.get("centre", Vector2.ZERO)
	var aim := _aim(ctx)
	var candidates: Array = []
	for line: int in [ROW, COLUMN]:
		var near := _near_side(line, centre, aim)
		for side: float in [near, -near]:
			var spot := _spot(line, side, centre, aim, ctx)
			candidates.append([centre.distance_to(spot), line, side, spot])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var best: Array = []
	for candidate: Array in candidates:
		if _usable(ctx, centre, candidate[3], aim):
			best = candidate
			break
	if best.is_empty():
		# Nothing clear: head for the nearest anyway (the walls slide it along).
		best = candidates[0]
	if _line != NO_LINE and (int(best[1]) != _line or float(best[2]) != _side):
		for candidate: Array in candidates:
			if int(candidate[1]) == _line and float(candidate[2]) == _side:
				if float(candidate[0]) <= float(best[0]) + float(numbers.get("switch_px", 0.0)) \
						and _usable(ctx, centre, candidate[3], aim):
					best = candidate
				break
	_line = int(best[1])
	_side = float(best[2])


func _usable(ctx: Dictionary, centre: Vector2, spot: Vector2, aim: Vector2) -> bool:
	return _probe(ctx, "route_clear", centre, spot) and _probe(ctx, "shot_clear", spot, aim)


## The side of the slime's line the shooter stands on (+1 right of / below it, -1; 0 counts +1).
static func _near_side(line: int, centre: Vector2, aim: Vector2) -> float:
	var offset := centre.x - aim.x if line == ROW else centre.y - aim.y
	return -1.0 if offset < 0.0 else 1.0


## The spot on `line` (`side` of the slime) at its own distance along the line, kept in the bow
## band [fleeRange + margin, attackRange - margin].
static func _spot(line: int, side: float, centre: Vector2, aim: Vector2, ctx: Dictionary) -> Vector2:
	var numbers: Dictionary = ctx.get("align", {})
	var margin := float(numbers.get("margin", 0.0))
	var low := maxf(0.0, float(ctx.get("flee_range", 0.0))) + margin
	var high := maxf(low, float(ctx.get("attack_range", 0.0)) - margin)
	if line == ROW:
		return Vector2(aim.x + side * clampf(absf(centre.x - aim.x), low, high), aim.y)
	if line == COLUMN:
		return Vector2(aim.x, aim.y + side * clampf(absf(centre.y - aim.y), low, high))
	return centre


## Velocity from `centre` to `spot` at `speed`, landing on it rather than past it.
static func _toward(centre: Vector2, spot: Vector2, speed: float, step_s: float) -> Vector2:
	var to := spot - centre
	var length := to.length()
	if length == 0.0 or speed <= 0.0:
		return Vector2.ZERO
	if step_s > 0.0 and length < speed * step_s:
		return to / step_s
	return to / length * speed


static func _aim(ctx: Dictionary) -> Vector2:
	if ctx.has("aim_point"):
		return ctx["aim_point"]
	var centre: Vector2 = ctx.get("centre", Vector2.ZERO)
	return centre + (ctx.get("dir", Vector2.ZERO) as Vector2) * float(ctx.get("distance", 0.0))


static func _probe(ctx: Dictionary, key: String, from: Vector2, to: Vector2) -> bool:
	var probe: Variant = ctx.get(key)
	if probe is Callable and (probe as Callable).is_valid():
		return bool((probe as Callable).call(from, to))
	return true


static func _result(next: String, velocity: Vector2) -> Dictionary:
	return {"next": next, "velocity": velocity, "attack_requested": false}
