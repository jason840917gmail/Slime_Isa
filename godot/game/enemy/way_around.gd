extends RefCounted
class_name WayAround
## How an enemy walking to a spot gets round what stands in its way (owner, 2026-11-21: enemies on
## their way home "get stuck in a wall and then they can't attack or do anything, they are lost.
## Make sure the intelligence is enough so they don't get stuck"). One per enemy; pure steering: it
## answers the heading to walk, the caller sets the velocity and moves the body as always
## (`ArcadeMover.move`).
##
## The walks it serves were straight lines at a point (a camp enemy's walk home and to where it last
## saw the slime: enemy.gd; a bestiary enemy's walk home: patterned_enemy.gd `_velocity_home`; the
## Dung Roller's walk to its ball), so a wall, a cliff's foot, a rim, water, a fence or a rock on the
## line held the body against it for good.
##
## - **Straight** while the way is open: the body's own shape, moved `probePx` along the line, meets
##   nothing it collides with (`CharacterBody2D.test_move`: its mask, so whatever stops its walk
##   stops the probe: walls, rims, water, fences, liftables, the slime).
## - **Round it** once the line is blocked: it picks a side (the one that opens with the smaller
##   turn; a tie goes to the side that was open last, else the right) and feels its way along the
##   obstacle, keeping it on that side, on the compass's eight headings (walls are straight or at
##   45°, so it runs true along them): each step it tries, in eighths of a turn, to turn back toward
##   the obstacle (after `turnHoldMs` on its heading, so it rounds a corner instead of spinning on
##   it), then straight on, then away from it, and takes the first open heading. A dead end turns it
##   right round.
## - **Back on the line** as soon as it is nearer its goal than where it met the obstacle (by
##   `leavePx`) and the straight way is open, or when it has turned toward the obstacle twice with
##   nothing there (the obstacle is behind it, or walked off: the slime).
## - **Lost** (`is_lost`): `giveUpMs` without getting `progressPx` nearer than it has ever been. The
##   caller then lets the walk go (a camp enemy settles where it stands, a bestiary enemy's home
##   moves there), so nothing presses against a wall for ever.
##
## Numbers: game-constants.json `combat.wayAround`. Gameplay time (`now_ms`: Services.now_ms()).
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")

const BLOCK := "combat.wayAround"
## An eighth of a turn: the headings it tries.
const STEP_RAD := PI / 4.0
## The headings tried while it follows an obstacle, in eighths of a turn from its heading: toward
## the obstacle first (negative), then on, then away, round to straight back.
const TOWARD_STEPS: Array[int] = [-2, -1]
const AWAY_STEPS: Array[int] = [0, 1, 2, 3, 4]
## The sides tried when the line is first blocked, in eighths of a turn from it.
const PICK_STEPS: Array[int] = [1, 2, 3]

## 0 while it walks the line; 1 or -1 while it goes round something (the turn's sign that leads
## away from it).
var _turn: int = 0
var _heading: Vector2 = Vector2.ZERO
## How far from the goal it was when it met the obstacle.
var _met_at: float = INF
## When it last turned toward the obstacle, and how many such turns found nothing since a probe
## last met it.
var _turned_at_ms: float = -INF
var _free_turns: int = 0
## The side that opened last (a tie's pick).
var _last_turn: int = 1
## The nearest it has been to the goal, and when it last got nearer.
var _best: float = INF
var _best_at_ms: float = -INF
var _numbers: Dictionary = {}


## The unit heading to walk now for a body that wants to go `to_goal` (the offset from where it is
## to its goal); Vector2.ZERO when it is there or shut in on every side.
func heading(body: CharacterBody2D, to_goal: Vector2, now_ms: float) -> Vector2:
	var distance := to_goal.length()
	if body == null or not body.is_inside_tree() or distance < 0.001:
		return Vector2.ZERO
	var line := to_goal / distance
	if distance < _best - _number("progressPx", 12.0) or _best_at_ms == -INF:
		_best = minf(_best, distance)
		_best_at_ms = now_ms
	if _turn == 0:
		if not _blocked(body, line):
			return line
		# Along the compass's eight ways, so it runs true along a straight wall instead of weaving.
		_heading = Vector2.from_angle(snappedf(line.angle(), STEP_RAD))
		_turn = _pick_turn(body, _heading)
		_last_turn = _turn
		_met_at = distance
		_turned_at_ms = now_ms
		_free_turns = 0
	elif distance < _met_at - _number("leavePx", 6.0) and not _blocked(body, line):
		_turn = 0
		return line
	return _follow(body, line, now_ms)


## True once it has not got nearer its goal for `giveUpMs` (the caller lets the walk go).
func is_lost(now_ms: float) -> bool:
	return _best_at_ms != -INF and now_ms - _best_at_ms >= _number("giveUpMs", 8000.0)


## True while it goes round something.
func is_rounding() -> bool:
	return _turn != 0


## A new walk: it forgets the obstacle and its progress (the goal changed, or it arrived).
func reset() -> void:
	_turn = 0
	_heading = Vector2.ZERO
	_met_at = INF
	_free_turns = 0
	_best = INF
	_best_at_ms = -INF


## One step along the obstacle: toward it when its heading has held `turnHoldMs`, else on, else away.
func _follow(body: CharacterBody2D, line: Vector2, now_ms: float) -> Vector2:
	if now_ms - _turned_at_ms >= _number("turnHoldMs", 160.0):
		var met := false
		for step: int in TOWARD_STEPS:
			var toward := _heading.rotated(float(step * _turn) * STEP_RAD)
			if _blocked(body, toward):
				met = true
				continue
			# Nothing there twice running: the obstacle is behind it (or left), so back on the line.
			_free_turns = 0 if met else _free_turns + 1
			if _free_turns >= 2:
				_turn = 0
				return line if not _blocked(body, line) else Vector2.ZERO
			_heading = toward
			_turned_at_ms = now_ms
			return _heading
		_free_turns = 0
	for step: int in AWAY_STEPS:
		var away := _heading.rotated(float(step * _turn) * STEP_RAD)
		if not _blocked(body, away):
			_heading = away
			return _heading
	return Vector2.ZERO


## The turn (1 or -1) that opens with the smaller angle from `line`; a tie keeps the last one.
func _pick_turn(body: CharacterBody2D, line: Vector2) -> int:
	for step: int in PICK_STEPS:
		var first := not _blocked(body, line.rotated(float(step * _last_turn) * STEP_RAD))
		var second := not _blocked(body, line.rotated(float(-step * _last_turn) * STEP_RAD))
		if first:
			return _last_turn
		if second:
			return -_last_turn
	return _last_turn


## True when the body's shape, moved `probePx` along `way`, meets something it collides with.
func _blocked(body: CharacterBody2D, way: Vector2) -> bool:
	return body.test_move(body.global_transform, way * _number("probePx", 20.0))


func _number(key: String, fallback: float) -> float:
	if _numbers.is_empty():
		var constants := Services.constants()
		var block: Variant = constants.value(BLOCK, {}) if constants != null else {}
		_numbers = (block as Dictionary) if block is Dictionary else {}
		if _numbers.is_empty():
			_numbers = {"": 0}
	var value: Variant = _numbers.get(key)
	return float(value) if value is float or value is int else fallback
