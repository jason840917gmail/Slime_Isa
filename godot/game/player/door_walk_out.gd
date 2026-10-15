extends RefCounted
## The walk out of a door (owner, 2026-10-14; docs/godot/CONVENTIONS.md "Doors"): arriving at a door
## with a side, the slime stands in the doorway (its feet on the door node) and walks out into the
## room, input locked, until its body is clear of the wall or building the doorway is in, plus
## `worldNavigation.doorWalkOutMarginPx`. The walk is measured, not a fixed distance:
##
## - At the start a probe (the body's own collision rect, widened sideways to
##   `doorWalkOutProbeWidthPx` so the posts or walls beside an opening count too) finds the shapes
##   it touches in the doorway: the door's wall or building. The body ignores their bodies
##   (collision exceptions) while it walks, so it is not pushed sideways out of the opening.
## - Each step the probe is tested again; once it touches none of those shapes the slime walks the
##   margin more and stops.
## - It never walks into anything else: before each step the body's rect at the next spot is tested
##   against everything it collides with except those doorway shapes, and the walk stops there; it
##   also stops when a step moved it less than a quarter of the way, or after `doorWalkOutMaxPx`.
##
## Owned by the player script (game/scripts/player.gd `walk_out_of_door`), which walks the body at
## `doorWalkOutSpeedShare` of its walking speed through its own `_move` and ArcadeMover.
##
## Owner: player.

const MAX_RESULTS := 32
const BLOCKED_SHARE := 0.25

var active: bool = false
var direction: Vector2 = Vector2.ZERO

var _body: CharacterBody2D
var _shape: RectangleShape2D
var _shape_offset: Vector2 = Vector2.ZERO
var _probe: RectangleShape2D
var _doorway: Dictionary = {}
var _exceptions: Array[PhysicsBody2D] = []
var _margin: float = 0.0
var _max_distance: float = 0.0
var _walked: float = 0.0
var _clear_at: float = -1.0
var _last_feet: Vector2 = Vector2.ZERO
var _expected: float = 0.0


## Starts the walk of `body` (feet already in the doorway) toward `walk_direction`. False (and no
## walk) without a body rect or a direction.
func start(body: CharacterBody2D, walk_direction: Vector2, margin: float, max_distance: float, probe_width: float) -> bool:
	finish()
	if body == null or not body.is_inside_tree() or walk_direction == Vector2.ZERO or max_distance <= 0.0:
		return false
	var rect := _body_rect(body)
	if rect == null:
		return false
	_body = body
	_shape = rect
	direction = walk_direction.normalized()
	_margin = maxf(0.0, margin)
	_max_distance = max_distance
	_walked = 0.0
	_clear_at = -1.0
	_expected = 0.0
	_last_feet = body.global_position
	_probe = RectangleShape2D.new()
	var across := Vector2(absf(direction.y), absf(direction.x))
	_probe.size = rect.size + across * maxf(0.0, probe_width - (rect.size * across).length())
	_doorway.clear()
	for hit: Dictionary in _query(_probe, body.global_position):
		_doorway[_key(hit)] = true
		var physics_body := hit.get("collider") as PhysicsBody2D
		if physics_body != null and not physics_body in _exceptions:
			_exceptions.append(physics_body)
			body.add_collision_exception_with(physics_body)
	active = true
	return true


## The way to walk this step, or ZERO when the walk is over (then `finish` it). Counts how far the
## last step went.
func next_direction() -> Vector2:
	if not active or not is_instance_valid(_body) or not _body.is_inside_tree():
		return Vector2.ZERO
	var feet := _body.global_position
	var moved := (feet - _last_feet).dot(direction)
	_last_feet = feet
	_walked += maxf(0.0, moved)
	if _expected > 0.0 and moved < _expected * BLOCKED_SHARE:
		return Vector2.ZERO # Something stopped it.
	_expected = 0.0
	if _walked >= _max_distance:
		return Vector2.ZERO
	if _clear_at < 0.0 and not _touches_doorway(feet):
		_clear_at = _walked
	if _clear_at >= 0.0 and _walked - _clear_at >= _margin:
		return Vector2.ZERO
	return direction


## True when moving the body by `motion` would put it into something that is not the doorway's
## wall (then the walk stops where it is). Records the step's length for `next_direction`.
func blocked_ahead(motion: Vector2) -> bool:
	if not active or not is_instance_valid(_body):
		return true
	var step := motion.dot(direction)
	if step <= 0.0:
		return false
	for hit: Dictionary in _query(_shape, _body.global_position + direction * step):
		if not _doorway.has(_key(hit)):
			return true
	_expected = step
	return false


## Ends the walk and gives the doorway's bodies their collision back.
func finish() -> void:
	if is_instance_valid(_body):
		for other: PhysicsBody2D in _exceptions:
			if is_instance_valid(other):
				_body.remove_collision_exception_with(other)
	_exceptions.clear()
	_doorway.clear()
	active = false


func _touches_doorway(feet: Vector2) -> bool:
	for hit: Dictionary in _query(_probe, feet):
		if _doorway.has(_key(hit)):
			return true
	return false


func _query(shape: Shape2D, feet: Vector2) -> Array[Dictionary]:
	var space := _body.get_world_2d().direct_space_state if is_instance_valid(_body) else null
	if space == null:
		return []
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, feet + _shape_offset)
	params.collision_mask = _body.collision_mask
	params.exclude = [_body.get_rid()]
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return space.intersect_shape(params, MAX_RESULTS)


func _key(hit: Dictionary) -> String:
	return "%s:%d" % [hit.get("rid"), int(hit.get("shape", 0))]


## The body's collision rect (its first CollisionShape2D with a RectangleShape2D), noting its offset.
func _body_rect(body: CharacterBody2D) -> RectangleShape2D:
	for child: Node in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and not shape_node.disabled and shape_node.shape is RectangleShape2D:
			_shape_offset = shape_node.position
			return shape_node.shape as RectangleShape2D
	return null
