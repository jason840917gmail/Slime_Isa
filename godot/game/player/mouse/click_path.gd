extends RefCounted
## Routes for the click orders (game/player/mouse/click_orders.gd): the shortest way the slime can
## walk to a point, through any gap its body fits, up and down stairs and over the rims it can drop
## off (docs/godot/MOUSE_CONTROLS.md).
##
## The search is Lazy Theta*, an any-angle A*, over cells of `input.mouse.pathCellPx` world px on
## every ground level (docs/godot/ELEVATION.md). A node is a cell at a level, standing at its spot:
## where the slime's body (its BodyShape, grown SHAPE_MARGIN) fits in that cell with that level's
## collision (the body's own mask with the level's bit; enemies left out: they move, and an attack
## walks up to one anyway). The spot is the cell's centre or, when the body does not fit there, the
## centre pushed out of what it overlaps while it stays in the cell, so a gap as wide as the body
## (and the margin) is found wherever it lies against the grid. The margin keeps the real body a
## hair off every wall and corner a route passes; a start a body rests against a wall from begins
## at the nearest spot clear of it.
##
## A step between neighbours is free when both ends are centres a step apart (the body's own
## extent covers the move); otherwise it is walked the way the follower walks it: straight at the
## next spot, sliding along whatever it meets and aiming again (`_slides_to`), so the corners of a
## gap just wider than the body funnel it in as the mover's sliding does. Stepping onto stairs
## takes the level of the stretch there, as a walking body does (Elevation._physics_process). From
## a rim the slime can drop over (Elevation.ledge_below, drop_target), a drop is a one-way step to
## its landing, costed as the distance walked in the time the push and the fall take. Each node
## looks back to its parent's parent and goes straight there when the body can sweep that line
## (exactly, no sliding) on one level away from stairs, so routes are straight lines that bend
## only at corners.
##
## Spots are cached for CACHE_MS and dropped when the body's mask or the world changes. A route
## that cannot reach the goal ends at the explored node closest to it (`complete` false):
## `exhausted` when there was nothing more to explore, else the budget
## (`input.mouse.pathMaxExpansions`, `pathMaxMs`) ran out first.
##
## Owner: player builder.

const Services := preload("res://game/shared/services.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")

## Physics layer 3 "enemy" (project.godot layer_names).
const ENEMY_LAYER_BIT := 4
## The body's shape is queried this much larger on every side, so routes keep the real body off
## the corners and walls they pass.
const SHAPE_MARGIN := 0.5
const CACHE_MS := 1500.0
## Pushes out of an overlap before a cell counts as blocked, and the extra beyond each push.
const SEPARATION_TRIES := 3
const SEPARATION_EXTRA := 0.1
## A step's walk: aim-and-slide rounds, and how close to its end counts as there.
const SLIDE_TRIES := 4
const SLIDE_ARRIVE_PX := 0.5
## How far (cells) around a goal the body cannot stand at a spot is looked for.
const GOAL_SEARCH_CELLS := 6
## How often a straight line near stairs is checked for a change of level.
const LEVEL_SAMPLE_PX := 6.0
## How far (cells) from a spot a drop looks for its rim, and how near the rim must be.
const RIM_REACH_CELLS := 1.5
const RIM_NEAR_CELLS := 0.5
## Drops worked out per search (Elevation.drop_target is costly), and the rounding of the cache key.
const MAX_DROP_CHECKS := 24
const DROP_KEY_PX := 4.0
## A level no node has: "work it out" in `find`.
const NO_LEVEL := -1000
## Node kinds, in the two low bits of a key's z (`_key`): a cell's spot, the start, a drop's landing,
## the goal point.
const KIND_SPOT := 0
const KIND_START := 1
const KIND_LANDING := 2
const KIND_GOAL := 3
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const HERE_AND_NEIGHBOURS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
	Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var cell_px: float = 16.0
var max_expansions: int = 2400
var max_ms: float = 30.0
## The slime's walking speed: a drop's time as distance.
var walk_speed: float = 200.0

var _body: CharacterBody2D
## The body shape's transform from the body origin (the feet).
var _shape_offset: Transform2D = Transform2D.IDENTITY
var _query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
## Neighbouring centres need no sweep when a step is shorter than the body in both axes.
var _centre_steps_safe: bool = false
var _space: PhysicsDirectSpaceState2D
var _elevation: Elevation
## The body's mask without its level bits and the enemy bit; a level adds its own bit.
var _base_mask: int = 0
var _mask_level: int = NO_LEVEL
## Vector3i(cell x, cell y, level) -> Vector2 spot, or null when the body fits nowhere in the cell.
var _spots: Dictionary = {}
var _cache_mask: int = -1
var _cache_world: int = -1
var _cache_since_ms: float = -INF
## Cells near a flight of stairs (a step there may change the level) -> the indices of those
## flights; the flights (ElevationStairs) and their rects (world), in the same order.
var _flight_cells: Dictionary = {}
var _flights: Array = []
var _flight_rects: Array[Rect2] = []
var _flights_key: int = -1
## Vector3i(cell x, cell y, level) -> whether the whole cell keeps a body on that level.
var _keeps: Dictionary = {}
## Vector4i(rim x, rim y, level, direction) -> Elevation.drop_target's answer (`_drop_at`).
var _drops_known: Dictionary = {}
var _drop_checks: int = 0

# One search.
var _pos: Dictionary = {}
var _g: Dictionary = {}
var _parent: Dictionary = {}
## Nodes whose parent came from a look-back (checked when they are expanded).
var _looked_back: Dictionary = {}
var _closed: Dictionary = {}
## Landing key -> {"rim": Vector2, "dir": Vector2} of the drop that reaches it.
var _drop_of: Dictionary = {}
var _goal_point: Vector2 = Vector2.ZERO
var _goal_level: int = 0
var _goal_cell: Vector2i = Vector2i.ZERO
var _goal_key: Vector3i = Vector3i.ZERO
var _goal_node: bool = false
## Level -> [[a flight's rect, its distance to the goal]] of the flights that climb from that level.
var _climbs: Dictionary = {}
var _heap_keys: Array[float] = []
var _heap_nodes: Array[Vector3i] = []


## Takes the body's first enabled CollisionShape2D. False when it has none.
func bind(body: CharacterBody2D) -> bool:
	_body = body
	if body == null:
		return false
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		_shape_offset = shape_node.transform
		_query.shape = _resized(shape_node.shape, SHAPE_MARGIN)
		_query.collide_with_areas = false
		_query.collide_with_bodies = true
		var exclude: Array[RID] = [body.get_rid()]
		_query.exclude = exclude
		var rectangle := shape_node.shape as RectangleShape2D
		_centre_steps_safe = rectangle != null and cell_px < minf(rectangle.size.x, rectangle.size.y) + 2.0 * SHAPE_MARGIN
		return true
	return false


## A route from `from` to `to` (feet): {"points": PackedVector2Array (the waypoints after `from`),
## "levels": PackedInt32Array (the level at each), "drops": Array[Vector2] (the push direction at a
## rim to drop from, else ZERO), "complete": bool, "exhausted": bool, "expansions": int}.
## `goal_level`: the level to reach `to` on; NO_LEVEL: the slime's own level where it can walk
## there, else the ground seen there. `budget_ms`: the search's time (`max_ms` when < 0). Physics
## must be readable (a physics step). Without a body or a space: the straight line.
func find(from: Vector2, to: Vector2, now_ms: float, goal_level: int = NO_LEVEL, budget_ms: float = -1.0) -> Dictionary:
	if not _prepare():
		return _route([to], [0], [Vector2.ZERO], true, false)
	_expire(now_ms)
	var start_level := body_level()
	_goal_level = goal_level if goal_level != NO_LEVEL else goal_level_at(to, start_level)
	# A body resting against a wall starts from the nearest spot clear of it (the first waypoint).
	var start := from
	if not fits(from, start_level):
		var clear: Variant = _free_spot(from, start_level, cell_px * 0.5)
		if clear != null:
			start = clear
	var route: Dictionary
	if _goal_level == start_level and keeps_level(start, to, start_level) and _sweep(start, to, start_level):
		route = _route([to], [start_level], [Vector2.ZERO], true, false)
	else:
		route = _search(start, start_level, to, budget_ms if budget_ms >= 0.0 else max_ms)
	if start != from:
		# Packed arrays are values: change the copies, then put them back.
		var points: PackedVector2Array = route["points"]
		var levels: PackedInt32Array = route["levels"]
		points.insert(0, start)
		levels.insert(0, start_level)
		route["points"] = points
		route["levels"] = levels
		(route["drops"] as Array).insert(0, Vector2.ZERO)
	return route


## The level a click at `point` means for a slime on `level`: its own where it can walk there (the
## strip behind a hill seen from the north), else the ground seen there.
func goal_level_at(point: Vector2, level: int) -> int:
	if _elevation == null:
		return level
	if _elevation.is_walkable(point, level):
		return level
	return _elevation.level_at(point, level)


## True when the body can sweep from `from` to `to` on `level` (the body's own by default) without
## touching anything (enemies aside).
func clear_line(from: Vector2, to: Vector2, level: int = NO_LEVEL) -> bool:
	if not _prepare():
		return true
	return _sweep(from, to, level if level != NO_LEVEL else body_level())


## True when the body fits standing at `feet` on `level`.
func fits(feet: Vector2, level: int) -> bool:
	if _space == null:
		return true
	_use_level(level)
	_query.transform = Transform2D(0.0, feet) * _shape_offset
	return _space.collide_shape(_query, 1).is_empty()


## The level the body walks on (Elevation.level_of; 0 without elevation).
func body_level() -> int:
	return _elevation.level_of(_body) if _elevation != null and _body != null else 0


## True when the line from `a` to `b` passes near a flight of stairs.
func crosses_stairs(a: Vector2, b: Vector2) -> bool:
	if _flight_rects.is_empty():
		return false
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(cell_px)
	for rect: Rect2 in _flight_rects:
		if rect.intersects(box):
			return true
	return false


## True when a body of `level` walking the line from `a` to `b` stays on `level`: it never stands
## on a stretch of stairs of another level. The line is walked half a cell at a time; only cells
## near flights where the level changes somewhere (`_cell_keeps_level`) are sampled finely, every
## LEVEL_SAMPLE_PX.
func keeps_level(a: Vector2, b: Vector2, level: int) -> bool:
	if _elevation == null or _flight_cells.is_empty():
		return true
	var length := a.distance_to(b)
	var steps := maxi(1, ceili(length / (cell_px * 0.5)))
	var fine := maxi(1, ceili(cell_px * 0.5 / LEVEL_SAMPLE_PX))
	var previous := Vector2i(-2147483648, -2147483648)
	for i in range(steps + 1):
		var point := a.lerp(b, float(i) / steps)
		var cell := cell_of(point)
		if cell == previous:
			continue
		previous = cell
		if not _flight_cells.has(cell) or _cell_keeps_level(cell, level):
			continue
		# Around this sample, finely (half a step back and forth).
		for k in range(-fine, fine + 1):
			var t := clampf((float(i) + float(k) / (2.0 * fine)) / steps, 0.0, 1.0)
			var near := a.lerp(b, t)
			if _level_after(cell_of(near), near, level) != level:
				return false
	return true


## True when standing anywhere in `cell` (its corners and centre) keeps a body on `level` (cached).
func _cell_keeps_level(cell: Vector2i, level: int) -> bool:
	var key := Vector3i(cell.x, cell.y, level)
	var known: Variant = _keeps.get(key)
	if known != null:
		return bool(known)
	var corner := Vector2(cell) * cell_px
	var keeps := true
	for point: Vector2 in [corner, corner + Vector2(cell_px, 0.0), corner + Vector2(0.0, cell_px),
			corner + Vector2(cell_px, cell_px), centre_of(cell)]:
		if _level_after(cell, point, level) != level:
			keeps = false
			break
	_keeps[key] = keeps
	return keeps


## Marks the cell under `point` blocked on `level` until the cache expires (a waypoint the body got
## stuck on).
func block(point: Vector2, level: int) -> void:
	var cell := cell_of(point)
	_spots[Vector3i(cell.x, cell.y, level)] = null


func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / cell_px), floori(point.y / cell_px))


func centre_of(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_px


# --- the search ----------------------------------------------------------------------------------

func _search(from: Vector2, start_level: int, to: Vector2, budget_ms: float) -> Dictionary:
	_pos.clear()
	_g.clear()
	_parent.clear()
	_looked_back.clear()
	_closed.clear()
	_drop_of.clear()
	_climbs.clear()
	_drop_checks = 0
	_heap_keys.clear()
	_heap_nodes.clear()
	_goal_point = to
	_goal_cell = cell_of(to)
	_goal_node = fits(to, _goal_level) and (_elevation == null or _elevation.is_walkable(to, _goal_level))
	if _goal_node:
		_goal_key = _key(_goal_cell, _goal_level, KIND_GOAL)
	else:
		var near: Variant = _nearest_spot_cell(_goal_cell, _goal_level)
		_goal_key = _key(near if near != null else _goal_cell, _goal_level, KIND_SPOT)
	var start := _key(cell_of(from), start_level, KIND_START)
	_pos[start] = from
	_g[start] = 0.0
	_parent[start] = start
	_push(_estimate(from, start_level), start)
	var best := start
	var best_distance := from.distance_to(to)
	var reached := false
	var expansions := 0
	var deadline := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	while not _heap_nodes.is_empty():
		if expansions >= max_expansions or (expansions % 32 == 0 and Time.get_ticks_usec() > deadline):
			break
		var node := _pop()
		if _closed.has(node):
			continue
		# Lazy Theta*: a look-back assumed a clear line on one level; check it now, else take the
		# best neighbour.
		if _looked_back.has(node) and not (keeps_level(_pos[_parent[node]], _pos[node], _level(node)) \
				and _sweep(_pos[_parent[node]], _pos[node], _level(node))):
			_repair(node)
			if not is_finite(float(_g[node])):
				continue
		_closed[node] = true
		expansions += 1
		var at: Vector2 = _pos[node]
		if node == _goal_key:
			best = node
			reached = true
			break
		var distance := at.distance_to(to)
		if distance < best_distance:
			best = node
			best_distance = distance
		_expand(node)
	var route := _route_to(best, start)
	route["complete"] = reached
	route["exhausted"] = not reached and _heap_nodes.is_empty()
	route["expansions"] = expansions
	return route


## Every step from `node`: to the spots around it (its own cell's too, from the start or a landing),
## to the goal point from around it, and off the rims around it when the goal lies lower.
func _expand(node: Vector3i) -> void:
	var cell := Vector2i(node.x, node.y)
	var level := _level(node)
	var at: Vector2 = _pos[node]
	var kind := _kind(node)
	# Neighbours where something stands (no spot, or one pushed off the centre): rims may be there.
	var crowded: Array[Vector2i] = []
	for offset: Vector2i in (NEIGHBOURS if kind == KIND_SPOT else HERE_AND_NEIGHBOURS):
		var next_cell := cell + offset
		var arrive: Variant = _spot(next_cell, level)
		if arrive == null or arrive != centre_of(next_cell):
			crowded.append(offset)
		if arrive == null:
			continue
		var next_level := _level_after(next_cell, arrive, level)
		var next := _key(next_cell, next_level, KIND_SPOT)
		if next == node or _closed.has(next):
			continue
		var spot: Variant = arrive if next_level == level else _spot(next_cell, next_level)
		if spot == null or not _step_ok(at, cell, next_cell, arrive, spot, level):
			continue
		_relax(node, next, spot)
	if _goal_node and level == _goal_level and kind != KIND_GOAL and not _closed.has(_goal_key) \
			and absi(cell.x - _goal_cell.x) <= 1 and absi(cell.y - _goal_cell.y) <= 1 and _slides_to(at, _goal_point, level):
		_relax(node, _goal_key, _goal_point)
	if _elevation != null and level > _goal_level and kind != KIND_GOAL:
		_expand_drops(node, level, at, crowded)


## Drops from `node` over the rims around it: toward each crowded neighbouring cell that does not
## face away from the goal, slide to what stands there; when that is within RIM_NEAR_CELLS, ask
## Elevation whether it is a rim and where the drop lands (`_drop_at`). The landing node stands
## clear of what is around it.
func _expand_drops(node: Vector3i, level: int, at: Vector2, crowded: Array[Vector2i]) -> void:
	var toward_goal := _goal_point - at
	for offset: Vector2i in crowded:
		if offset == Vector2i.ZERO or _drop_checks >= MAX_DROP_CHECKS:
			continue
		var unit := Vector2(offset).normalized()
		if unit.dot(toward_goal) < 0.0:
			continue
		var rim := _slide(at, unit, cell_px * RIM_REACH_CELLS, level)
		if at.distance_to(rim) > cell_px * RIM_NEAR_CELLS:
			continue
		var landing := _drop_at(rim, level, unit, offset)
		if landing.is_empty():
			continue
		var land_level := int(landing["level"])
		var feet: Variant = landing["feet"]
		if not fits(feet, land_level):
			feet = _free_spot(feet, land_level, cell_px * 0.5)
			if feet == null:
				continue
		var next := _key(cell_of(feet), land_level, KIND_LANDING)
		if _closed.has(next):
			continue
		var cost := float(_g[node]) + at.distance_to(rim) + _drop_cost(int(landing["drop"]))
		if cost < float(_g.get(next, INF)):
			_g[next] = cost
			_parent[next] = node
			_pos[next] = feet
			_looked_back.erase(next)
			_drop_of[next] = {"rim": rim, "dir": unit}
			_push(cost + _estimate(feet, land_level), next)


## Elevation.drop_target for a body of `level` at `rim` going `unit` (cached across searches by
## the rim rounded to DROP_KEY_PX, the level and the direction; counted against MAX_DROP_CHECKS
## when it is worked out).
func _drop_at(rim: Vector2, level: int, unit: Vector2, offset: Vector2i) -> Dictionary:
	var key := Vector4i(roundi(rim.x / DROP_KEY_PX), roundi(rim.y / DROP_KEY_PX), level, (offset.x + 1) * 3 + offset.y + 1)
	var known: Variant = _drops_known.get(key)
	if known != null:
		return known
	_drop_checks += 1
	var landing := _elevation.drop_target(rim, level, unit)
	_drops_known[key] = landing
	return landing


## Theta*'s relax: through `node`, or straight from its parent when that is allowed (same level, no
## drop between; that the line is clear and keeps the level is checked when `next` is expanded).
func _relax(node: Vector3i, next: Vector3i, spot: Vector2) -> void:
	var at: Vector2 = _pos[node]
	var cost := float(_g[node]) + at.distance_to(spot)
	var parent := node
	var looked_back := false
	var grand: Vector3i = _parent[node]
	if grand != node and _kind(node) != KIND_LANDING and _level(grand) == _level(node) and _level(next) == _level(node):
		var through := float(_g[grand]) + (_pos[grand] as Vector2).distance_to(spot)
		if through <= cost:
			cost = through
			parent = grand
			looked_back = true
	if cost < float(_g.get(next, INF)):
		_g[next] = cost
		_parent[next] = parent
		_pos[next] = spot
		if looked_back:
			_looked_back[next] = true
		else:
			_looked_back.erase(next)
		_push(cost + _estimate(spot, _level(next)), next)


## Lazy Theta*'s repair: the best expanded node around `node` (same level) that steps to it.
func _repair(node: Vector3i) -> void:
	_looked_back.erase(node)
	_g[node] = INF
	var cell := Vector2i(node.x, node.y)
	var level := _level(node)
	var spot: Vector2 = _pos[node]
	for offset: Vector2i in HERE_AND_NEIGHBOURS:
		var from_cell := cell - offset
		for kind: int in [KIND_SPOT, KIND_START, KIND_LANDING]:
			var from := _key(from_cell, level, kind)
			if from == node or not _closed.has(from):
				continue
			var at: Vector2 = _pos[from]
			var ok := false
			if _kind(node) == KIND_GOAL:
				ok = _slides_to(at, spot, level)
			else:
				var arrive: Variant = _spot(cell, level)
				ok = arrive != null and _level_after(cell, arrive, level) == level and _step_ok(at, from_cell, cell, arrive, spot, level)
			if not ok:
				continue
			var cost := float(_g[from]) + at.distance_to(spot)
			if cost < float(_g[node]):
				_g[node] = cost
				_parent[node] = from


## True when the body steps from `at` (in `from_cell`) to `spot` (in `to_cell`, where it arrives
## at `arrive` on `level`): free when every end is a centre a step apart (and, on a diagonal, both
## cells beside it too), else the way the follower walks it (`_slides_to`).
func _step_ok(at: Vector2, from_cell: Vector2i, to_cell: Vector2i, arrive: Vector2, spot: Vector2, level: int) -> bool:
	var offset := to_cell - from_cell
	var centre := centre_of(to_cell)
	var plain := _centre_steps_safe and offset != Vector2i.ZERO and at == centre_of(from_cell) and arrive == centre and spot == centre
	if plain and offset.x != 0 and offset.y != 0:
		for side: Vector2i in [Vector2i(to_cell.x, from_cell.y), Vector2i(from_cell.x, to_cell.y)]:
			var beside: Variant = _spot(side, level)
			if beside == null or beside != centre_of(side):
				plain = false
	return plain or _slides_to(at, spot, level)


## True when the body gets from `from` to `to` on `level` the way the follower walks a step: straight
## at it, and when it meets something, sliding along it and aiming again (SLIDE_TRIES times). A
## step into a gap only just wider than the body then counts: the gap's corners funnel it in, as
## the mover's sliding does (game/shared/arcade_mover.gd).
func _slides_to(from: Vector2, to: Vector2, level: int) -> bool:
	if _space == null:
		return true
	_use_level(level)
	_query.transform = Transform2D(0.0, from) * _shape_offset
	if not _space.collide_shape(_query, 1).is_empty():
		return false
	var at := from
	for attempt in SLIDE_TRIES:
		var motion := to - at
		if motion.length() <= SLIDE_ARRIVE_PX:
			return true
		_query.transform = Transform2D(0.0, at) * _shape_offset
		_query.motion = motion
		var fractions := _space.cast_motion(_query)
		_query.motion = Vector2.ZERO
		if fractions.size() < 2 or fractions[0] >= 1.0:
			return true
		# The surface met (just past the last free spot), and what is left of the move along it.
		_query.transform = Transform2D(0.0, at + motion * fractions[1]) * _shape_offset
		var contact := _space.get_rest_info(_query)
		at += motion * fractions[0]
		if contact.is_empty():
			return false
		var along := (motion * (1.0 - fractions[0])).slide((contact["normal"] as Vector2).normalized())
		if along.length() < SLIDE_ARRIVE_PX:
			return false
		_query.transform = Transform2D(0.0, at) * _shape_offset
		_query.motion = along
		var slid := _space.cast_motion(_query)
		_query.motion = Vector2.ZERO
		var moved := along * (slid[0] if slid.size() > 0 else 0.0)
		if moved.length() < SLIDE_ARRIVE_PX:
			return false
		at += moved
	return at.distance_to(to) <= SLIDE_ARRIVE_PX


## A lower bound of the way left from `at` on `level`: the straight line, or, below the goal's
## level, the way through the nearest flight of stairs that climbs from there (nothing else
## climbs: drops only go down, the hop never climbs).
func _estimate(at: Vector2, level: int) -> float:
	var straight := at.distance_to(_goal_point)
	if level >= _goal_level:
		return straight
	var climbs: Array = _climbs_from(level)
	var best := INF
	for climb: Array in climbs:
		var rect: Rect2 = climb[0]
		best = minf(best, _rect_distance(rect, at) + float(climb[1]))
	return maxf(straight, best) if best < INF else straight


## The flights that climb from `level` as [rect, its distance to the goal] (cached per search).
func _climbs_from(level: int) -> Array:
	if _climbs.has(level):
		return _climbs[level]
	var climbs: Array = []
	for i in _flights.size():
		var flight = _flights[i]
		if flight.joins(level) and int(flight.top) > level:
			climbs.append([_flight_rects[i], _rect_distance(_flight_rects[i], _goal_point)])
	_climbs[level] = climbs
	return climbs


static func _rect_distance(rect: Rect2, point: Vector2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))


## The open cell nearest `cell` on `level` within GOAL_SEARCH_CELLS rings (its own first) where the
## level walks; null when there is none.
func _nearest_spot_cell(cell: Vector2i, level: int) -> Variant:
	for ring in range(0, GOAL_SEARCH_CELLS + 1):
		var best: Variant = null
		var best_distance := INF
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var next := cell + Vector2i(dx, dy)
				var spot: Variant = _spot(next, level)
				if spot == null or (_elevation != null and not _elevation.is_walkable(spot, level)):
					continue
				var distance := (spot as Vector2).distance_to(_goal_point)
				if distance < best_distance:
					best = next
					best_distance = distance
		if best != null:
			return best
	return null


## The waypoints from the start to `end` (a drop adds its rim, with the push direction, before its
## landing).
func _route_to(end: Vector3i, start: Vector3i) -> Dictionary:
	var keys: Array[Vector3i] = []
	var key := end
	while key != start:
		keys.append(key)
		key = _parent[key]
	keys.reverse()
	var points: Array[Vector2] = []
	var levels: Array[int] = []
	var drops: Array[Vector2] = []
	var previous := start
	for node: Vector3i in keys:
		if _drop_of.has(node) and _parent[node] == previous:
			var drop: Dictionary = _drop_of[node]
			points.append(drop["rim"])
			levels.append(_level(previous))
			drops.append(drop["dir"])
		points.append(_pos[node])
		levels.append(_level(node))
		drops.append(Vector2.ZERO)
		previous = node
	return _route(points, levels, drops, false, false)


static func _route(points: Array, levels: Array, drops: Array, complete: bool, exhausted: bool) -> Dictionary:
	var drop_list: Array[Vector2] = []
	for drop: Vector2 in drops:
		drop_list.append(drop)
	return {"points": PackedVector2Array(points), "levels": PackedInt32Array(levels), "drops": drop_list,
		"complete": complete, "exhausted": exhausted}


# --- cells, levels and physics -------------------------------------------------------------------

## Where the body fits in `cell` on `level` (cached), or null.
func _spot(cell: Vector2i, level: int) -> Variant:
	var key := Vector3i(cell.x, cell.y, level)
	if _spots.has(key):
		return _spots[key]
	var spot: Variant = _free_spot(centre_of(cell), level, cell_px * 0.5)
	_spots[key] = spot
	return spot


## `at` when the body fits there on `level`, else `at` pushed out of what the body overlaps (each
## contact's way out, per axis the strongest either way, summed: walls on both sides cancel), up to
## SEPARATION_TRIES times; null when it does not come free within `slack` of `at` on either axis.
func _free_spot(at: Vector2, level: int, slack: float) -> Variant:
	_use_level(level)
	var point := at
	for attempt in SEPARATION_TRIES + 1:
		_query.transform = Transform2D(0.0, point) * _shape_offset
		var contacts := _space.collide_shape(_query, 16)
		if contacts.is_empty():
			return point
		if attempt == SEPARATION_TRIES:
			break
		var most := Vector2.ZERO
		var least := Vector2.ZERO
		for i in range(0, contacts.size() - 1, 2):
			var out := contacts[i + 1] - contacts[i]
			most = most.max(out)
			least = least.min(out)
		var push := most + least
		if push.length_squared() < 1e-6:
			break
		point += push + push.normalized() * SEPARATION_EXTRA
		if absf(point.x - at.x) > slack or absf(point.y - at.y) > slack:
			break
	return null


## The level after stepping onto `cell` at `spot` from `level`: the stretch of stairs there (the
## first flight whose steps hold it, as Elevation.stairs_at), else the same.
func _level_after(cell: Vector2i, spot: Vector2, level: int) -> int:
	if _elevation == null:
		return level
	var near: Variant = _flight_cells.get(cell)
	if near == null:
		return level
	var local := spot - _elevation.global_position
	for index: int in near:
		var flight = _flights[index]
		if flight.walks(local):
			return flight.level_at(local, level)
	return level


## True when the body sweeps from `from` to `to` on `level` touching nothing. A start that already
## overlaps something is not clear: the physics cast ignores what it starts inside.
func _sweep(from: Vector2, to: Vector2, level: int) -> bool:
	if _space == null:
		return true
	_use_level(level)
	_query.transform = Transform2D(0.0, from) * _shape_offset
	if not _space.collide_shape(_query, 1).is_empty():
		return false
	if from == to:
		return true
	_query.motion = to - from
	var fractions := _space.cast_motion(_query)
	_query.motion = Vector2.ZERO
	return fractions.size() < 1 or fractions[0] >= 1.0


## How far the body slides from `from` along `unit` (at most `reach`) before it touches something.
func _slide(from: Vector2, unit: Vector2, reach: float, level: int) -> Vector2:
	_use_level(level)
	_query.transform = Transform2D(0.0, from) * _shape_offset
	_query.motion = unit * reach
	var fractions := _space.cast_motion(_query)
	_query.motion = Vector2.ZERO
	var safe := fractions[0] if fractions.size() > 0 else 1.0
	return from + unit * reach * safe


func _drop_cost(drop: int) -> float:
	var ms := Elevation.setting("dropPushMs") + Elevation.setting("dropBaseMs") + Elevation.setting("dropMsPerLevel") * float(drop)
	return walk_speed * ms / 1000.0


func _use_level(level: int) -> void:
	if level == _mask_level:
		return
	_mask_level = level
	_query.collision_mask = _base_mask | (Elevation.level_bit(level) if _elevation != null else 0)


## Reads the space, the world's elevation and the body's mask. False without a body in a world.
func _prepare() -> bool:
	if _body == null or not is_instance_valid(_body) or not _body.is_inside_tree() or _query.shape == null:
		_space = null
		return false
	_space = _body.get_world_2d().direct_space_state
	var world := Services.world()
	var elevation: Elevation = world.elevation if world != null else null
	_elevation = elevation if elevation != null and is_instance_valid(elevation) and elevation.grid != null else null
	var mask := _body.collision_mask & ~ENEMY_LAYER_BIT & ~Elevation.all_level_bits()
	if mask != _base_mask:
		_base_mask = mask
		_mask_level = NO_LEVEL
	_index_flights()
	return _space != null


## Drops the cached spots when they are old, the mask changed or the world did.
func _expire(now_ms: float) -> void:
	var world_id := _elevation.get_instance_id() if _elevation != null else 0
	if _base_mask != _cache_mask or world_id != _cache_world or now_ms - _cache_since_ms > CACHE_MS:
		_spots.clear()
		_drops_known.clear()
		_cache_mask = _base_mask
		_cache_world = world_id
		_cache_since_ms = now_ms
	_mask_level = NO_LEVEL


func _index_flights() -> void:
	var key := hash([_elevation.get_instance_id(), _elevation.stairs.size()]) if _elevation != null else 0
	if key == _flights_key:
		return
	_flights_key = key
	_flight_cells.clear()
	_flights.clear()
	_flight_rects.clear()
	_keeps.clear()
	if _elevation == null:
		return
	for flight in _elevation.stairs:
		var rect: Rect2 = flight.bounds
		rect.position += _elevation.global_position
		var index := _flights.size()
		_flights.append(flight)
		_flight_rects.append(rect)
		var grown := rect.grow(cell_px)
		for y in range(floori(grown.position.y / cell_px), floori(grown.end.y / cell_px) + 1):
			for x in range(floori(grown.position.x / cell_px), floori(grown.end.x / cell_px) + 1):
				var cell := Vector2i(x, y)
				if not _flight_cells.has(cell):
					_flight_cells[cell] = []
				(_flight_cells[cell] as Array).append(index)


static func _key(cell: Vector2i, level: int, kind: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, level * 4 + kind)


static func _level(key: Vector3i) -> int:
	return floori(float(key.z) / 4.0)


static func _kind(key: Vector3i) -> int:
	return posmod(key.z, 4)


## A copy of `shape` grown by `margin` on every side (negative: shrunk); other shapes as they are.
static func _resized(shape: Shape2D, margin: float) -> Shape2D:
	var rectangle := shape as RectangleShape2D
	if rectangle != null:
		var resized := RectangleShape2D.new()
		resized.size = (rectangle.size + Vector2.ONE * margin * 2.0).max(Vector2.ONE)
		return resized
	var circle := shape as CircleShape2D
	if circle != null:
		var resized_circle := CircleShape2D.new()
		resized_circle.radius = maxf(1.0, circle.radius + margin)
		return resized_circle
	return shape


# --- binary heap on two parallel arrays (key, node) ---------------------------------------------

func _push(key: float, node: Vector3i) -> void:
	_heap_keys.append(key)
	_heap_nodes.append(node)
	var i := _heap_keys.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _heap_keys[parent] <= _heap_keys[i]:
			break
		_swap(i, parent)
		i = parent


func _pop() -> Vector3i:
	var top := _heap_nodes[0]
	var last := _heap_keys.size() - 1
	_heap_keys[0] = _heap_keys[last]
	_heap_nodes[0] = _heap_nodes[last]
	_heap_keys.resize(last)
	_heap_nodes.resize(last)
	var i := 0
	while true:
		var left := 2 * i + 1
		var right := left + 1
		var smallest := i
		if left < last and _heap_keys[left] < _heap_keys[smallest]:
			smallest = left
		if right < last and _heap_keys[right] < _heap_keys[smallest]:
			smallest = right
		if smallest == i:
			break
		_swap(i, smallest)
		i = smallest
	return top


func _swap(a: int, b: int) -> void:
	var key := _heap_keys[a]
	_heap_keys[a] = _heap_keys[b]
	_heap_keys[b] = key
	var node := _heap_nodes[a]
	_heap_nodes[a] = _heap_nodes[b]
	_heap_nodes[b] = node
