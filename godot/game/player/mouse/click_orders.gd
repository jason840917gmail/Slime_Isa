extends RefCounted
## One order of the mouse control schemes (game/player/mouse/control_scheme.gd) and the walking it
## needs: walk to a point (MOVE), walk into reach of an enemy or a resource and swing (ATTACK), or
## walk to something usable and use it (INTERACT).
##
## The player script issues the order on the order button's press, asks `steer()` for each step's
## direction, and runs the swing or the use itself once the target is in reach (player.gd
## `_run_click_order`). `held` mirrors the order button: a held MOVE follows the pointer (re-planned
## every `input.mouse.followRepathMs` once the pointer moved a cell), a held ATTACK keeps swinging,
## a held INTERACT runs the target's hold action.
##
## Walking follows a ClickPath route: straight lines between waypoints, across levels by stairs,
## and off rims where the route drops. At a drop's rim the slime leans over it for the drop push
## time (player.gd `_press_ledge` drops it, as with the keys) and walks on from the landing. Each
## step looks up to two waypoints ahead and goes straight there when it can (same level, away from
## stairs). The route is re-planned every `repathMs` while the goal moves, when the planner ran out
## of budget before the goal (from the end of the part it found), and when the body makes no
## progress for `stuckMs` (avoiding the waypoint it could not reach); MAX_STUCK fruitless re-plans
## end the order.
##
## Owner: player builder.

const ClickPath := preload("res://game/player/mouse/click_path.gd")

enum Kind { NONE, MOVE, ATTACK, INTERACT }

## Re-plans that found no way forward before the order gives up.
const MAX_STUCK := 3
## A pause in steering longer than this (a swing, a jump, a fall) restarts the progress watch.
const STEER_GAP_MS := 100.0
## Moving this far counts as progress for the stuck watch.
const PROGRESS_PX := 2.0

var kind: Kind = Kind.NONE
## The order button is still down.
var held: bool = false
## ATTACK: the enemy or resource script node (it has `damage_area`).
var target: Node
## INTERACT: the interaction controller's key for the target (InteractionController.key_of).
var interact_key: Variant = null
## ATTACK: a swing started since the order was given.
var swung: bool = false
## Where the order walks (feet); a moving target updates it.
var goal: Vector2 = Vector2.ZERO
## What `steer()` returned last (ZERO: standing). The jump goes this way.
var direction: Vector2 = Vector2.ZERO
var path: ClickPath = ClickPath.new()

var arrive_px: float = 6.0
var repath_ms: float = 250.0
var follow_repath_ms: float = 120.0
var follow_max_ms: float = 8.0
var stuck_ms: float = 400.0
var still_px: float = 14.0

var _goal_of: Callable = Callable()
## The level to reach the goal on (Callable() -> int); unset: ClickPath works it out.
var _goal_level_of: Callable = Callable()
var _points: PackedVector2Array = PackedVector2Array()
var _levels: PackedInt32Array = PackedInt32Array()
var _drops: Array[Vector2] = []
var _index: int = 0
var _complete: bool = true
var _exhausted: bool = false
## How far the last route took the slime from where it was planned (no progress: nothing to walk).
var _reach: float = 0.0
var _planned_goal: Vector2 = Vector2.INF
var _repath_at_ms: float = 0.0
var _progress_from: Vector2 = Vector2.INF
var _progress_since_ms: float = 0.0
var _last_steer_ms: float = -INF
var _stuck_count: int = 0
var _stuck_at: Vector2 = Vector2.ZERO
## Leaning over a drop's rim: until when, which way, and the level it leans from.
var _push_until_ms: float = -1.0
var _push_dir: Vector2 = Vector2.ZERO
var _push_level: int = 0


## Reads the tuning from game-constants through `number` (Callable(path) -> float).
func configure(number: Callable) -> void:
	path.cell_px = maxf(4.0, float(number.call("input.mouse.pathCellPx")))
	path.max_expansions = maxi(1, int(number.call("input.mouse.pathMaxExpansions")))
	path.max_ms = float(number.call("input.mouse.pathMaxMs"))
	path.walk_speed = float(number.call("character.player.movement.baseSpeed"))
	arrive_px = float(number.call("input.mouse.arrivePx"))
	repath_ms = float(number.call("input.mouse.repathMs"))
	follow_repath_ms = float(number.call("input.mouse.followRepathMs"))
	follow_max_ms = float(number.call("input.mouse.followMaxMs"))
	stuck_ms = float(number.call("input.mouse.stuckMs"))
	still_px = float(number.call("input.mouse.stillPx"))


func move_to(point: Vector2) -> void:
	_begin(Kind.MOVE)
	goal = point


## `feet_of` (Callable() -> Vector2) follows the target as it moves; `level_of` (Callable() -> int),
## when given, is the level it walks on.
func attack(node: Node, feet_of: Callable, level_of: Callable = Callable()) -> void:
	_begin(Kind.ATTACK)
	target = node
	_goal_of = feet_of
	_goal_level_of = level_of
	goal = feet_of.call()


## `stand_at` (Callable() -> Vector2): where the target stands.
func interact(key: Variant, stand_at: Callable) -> void:
	_begin(Kind.INTERACT)
	interact_key = key
	_goal_of = stand_at
	goal = stand_at.call()


func is_active() -> bool:
	return kind != Kind.NONE


## The order button went up: a MOVE walks on to the last point, an ATTACK stops after its swing.
func release() -> void:
	held = false


func cancel() -> void:
	_begin(Kind.NONE)


## The slime moved by other means (a jump): the next step re-plans from where it is.
func invalidate() -> void:
	_planned_goal = Vector2.INF
	_repath_at_ms = 0.0
	_progress_from = Vector2.INF
	_push_until_ms = -1.0


## The waypoints of the current route (tests, debugging).
func route_points() -> PackedVector2Array:
	return _points


## The push directions of the current route's drops, ZERO where it walks (tests, debugging).
func route_drops() -> Array[Vector2]:
	return _drops


## The direction to walk this step (ZERO: stand). Physics step only (routes query physics).
## `pointer`: the world pointer (a held MOVE follows it). `push_ms`: how long to lean over a rim
## before a drop counts as failed.
func steer(body: CharacterBody2D, pointer: Vector2, now_ms: float, push_ms: float) -> Vector2:
	direction = Vector2.ZERO
	if kind == Kind.NONE or body == null:
		return direction
	if now_ms - _last_steer_ms > STEER_GAP_MS:
		_progress_from = Vector2.INF
	_last_steer_ms = now_ms
	var feet := body.global_position
	var follows_pointer := kind == Kind.MOVE and held
	if follows_pointer:
		if feet.distance_to(pointer) <= still_px:
			return direction
		goal = pointer
	elif _goal_of.is_valid():
		goal = _goal_of.call()
	if _push_until_ms >= 0.0:
		if path.body_level() < _push_level:
			# Dropped: on to the landing.
			_push_until_ms = -1.0
			_index += 1
			_progress_from = Vector2.INF
		elif now_ms < _push_until_ms:
			direction = _push_dir
			return direction
		else:
			_push_until_ms = -1.0
			_stuck_count += 1
			if _stuck_count > MAX_STUCK:
				cancel()
				return direction
			_replan(feet, now_ms)
	elif now_ms >= _repath_at_ms and _planned_goal.distance_to(goal) > (path.cell_px if follows_pointer else arrive_px):
		_replan(feet, now_ms)
	var level := path.body_level()
	var looks := 0
	while _index + 1 < _points.size() and looks < 2:
		looks += 1
		if _drops[_index] != Vector2.ZERO or _levels[_index] != level or _levels[_index + 1] != level:
			break
		if not path.keeps_level(feet, _points[_index + 1], level) or not path.clear_line(feet, _points[_index + 1], level):
			break
		_index += 1
	while _index < _points.size() and feet.distance_to(_points[_index]) <= arrive_px:
		if _drops[_index] != Vector2.ZERO:
			_push_dir = _drops[_index]
			_push_level = level
			_push_until_ms = now_ms + push_ms
			direction = _push_dir
			return direction
		_index += 1
	if _index >= _points.size():
		return _route_end(feet, now_ms)
	direction = (_points[_index] - feet).normalized()
	_watch_progress(feet, now_ms)
	return direction


## Past the last waypoint. A MOVE whose route stopped short because the planner ran out of budget
## plans the rest from here (when that route got it anywhere); else a held MOVE waits for the
## pointer to go somewhere reachable and one that arrived ends. An ATTACK or INTERACT walks
## straight at its target (the player decides when it is in reach).
func _route_end(feet: Vector2, now_ms: float) -> Vector2:
	var toward := goal - feet
	if kind == Kind.MOVE:
		if not _complete and not _exhausted and _reach > arrive_px * 2.0:
			_replan(feet, now_ms)
			return direction
		if held:
			return direction
		cancel()
		return direction
	if toward.length() > arrive_px:
		direction = toward.normalized()
		_watch_progress(feet, now_ms)
	return direction


## The stuck watch: no progress for `stuck_ms` re-plans around the waypoint the body could not
## reach; MAX_STUCK of those in one place end the order (not a held MOVE: the player is steering it).
func _watch_progress(feet: Vector2, now_ms: float) -> void:
	if _progress_from == Vector2.INF or feet.distance_to(_progress_from) > PROGRESS_PX:
		_progress_from = feet
		_progress_since_ms = now_ms
		if _stuck_count > 0 and feet.distance_to(_stuck_at) > path.cell_px * 2.0:
			_stuck_count = 0
		return
	if now_ms - _progress_since_ms < stuck_ms:
		return
	_stuck_at = feet
	_stuck_count += 1
	if _stuck_count > MAX_STUCK and not (kind == Kind.MOVE and held):
		cancel()
		return
	_progress_since_ms = now_ms
	if _index < _points.size() and path.cell_of(_points[_index]) != path.cell_of(goal):
		path.block(_points[_index], _levels[_index])
	_replan(feet, now_ms)


func _replan(feet: Vector2, now_ms: float) -> void:
	var level := int(_goal_level_of.call()) if _goal_level_of.is_valid() else ClickPath.NO_LEVEL
	# Following the held pointer re-plans often: a short search each time (the walk goes on from
	# where it ends, `_route_end`).
	var route := path.find(feet, goal, now_ms, level, follow_max_ms if kind == Kind.MOVE and held else -1.0)
	_points = route["points"]
	_levels = route["levels"]
	_drops = route["drops"]
	_complete = bool(route["complete"])
	_exhausted = bool(route["exhausted"])
	_reach = feet.distance_to(_points[_points.size() - 1]) if not _points.is_empty() else 0.0
	_index = 0
	_planned_goal = goal
	_repath_at_ms = now_ms + (follow_repath_ms if kind == Kind.MOVE and held else repath_ms)


func _begin(next_kind: Kind) -> void:
	kind = next_kind
	held = false
	target = null
	interact_key = null
	swung = false
	direction = Vector2.ZERO
	_goal_of = Callable()
	_goal_level_of = Callable()
	_points = PackedVector2Array()
	_levels = PackedInt32Array()
	_drops = []
	_index = 0
	_complete = true
	_exhausted = false
	_reach = 0.0
	_planned_goal = Vector2.INF
	_repath_at_ms = 0.0
	_progress_from = Vector2.INF
	_stuck_count = 0
	_push_until_ms = -1.0
