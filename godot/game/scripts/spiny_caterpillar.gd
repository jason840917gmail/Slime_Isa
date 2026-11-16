extends "res://game/enemy/patterned_enemy.gd"
class_name SpinyCaterpillarScript
## Scene script `game.spiny-caterpillar` (a climb monster, docs/godot/BESTIARY.md "Spiny
## Caterpillar"; the owner, 2026-11-13: "another monster lives in the vines, a spiky caterpillar
## with a fixed movement up and down or left and right; it damages the player if the player
## collides with it"): a fat caterpillar with red spikes crawling back and forth along painted vines.
##
## - **Its track** is the run of vines it is placed on (VineLayer `run_rect`): their column when it
##   starts up or down, their row when it starts left or right. `aim_direction` is the way it
##   starts: a placed enemy's rotation sets it (placed_enemy.gd "Facing": unturned it starts down,
##   up and down its column). It crawls from end to end, its body kept on the vines, at
##   `crawlSpeed`, and at each end curls round (`turnMs`) and crawls back. Placed off the vines
##   (a climbable wall, bare rock) it crawls `trackPx` along its way and back.
## - **Spikes:** the slime touching its body (its centre within `contactReachPx` of the line along
##   the caterpillar) takes `contactDamage` with knockback, at most every `contactCooldownMs`: a
##   climbing slime is knocked off the wall (feral_climb.gd `drop`).
## - Any hit hurts it (20 health: two Spear jabs along the face, player.gd `_climb_strike`); a hit
##   does not move it off its track.
##
## Its body is neither solid nor stopped (layer and mask 0), so the slime climbs through it (and is
## hurt); its art (seen from above, head up) is centred on its centre and turns with its way.
##
## Owner: enemy builder.

const PHASE_CRAWL := "crawl"
const PHASE_TURN := "turn"
const FRAME_CRAWL_A := 0
const FRAME_CRAWL_B := 1
const FRAME_TURN := 2
const VINES_GROUP := &"climb_walls"
const CUE_TURN := &"CrawlerTurn"
## Presentation: the crawl's two frames alternate every STEP_MS.
const STEP_MS := 150.0
## Its art is centred on its old centre, this far over its root (the scene's `depth_anchor`).
const CENTRE_LIFT := 20.0

## The way it starts crawling (snapped to up, down, left or right): up or down crawls its vines'
## column, left or right their row. Set by a placed enemy's rotation.
@export var aim_direction: Vector2 = Vector2.DOWN

## Its track's ends (old centres) and the end it crawls to (0 or 1).
var _ends: Array[Vector2] = []
var _goal: int = 1
var _heading: float = 0.0
var _turn_from: float = 0.0
var _turn_to: float = 0.0
var _last_ms: float = -1.0


func _ready() -> void:
	super()
	_transition(PHASE_CRAWL, Services.now_ms())
	set_frame(FRAME_CRAWL_A)


## The way it crawls now (a unit vector).
func get_travel() -> Vector2:
	return Vector2.UP.rotated(_heading)


## Its track's two ends (old centres; empty before its first step).
func get_track() -> Array[Vector2]:
	return _ends


func _step_pattern(now: float, delta: float, target: Dictionary, _engaged: bool) -> void:
	_last_ms = now
	if _ends.is_empty():
		_plan_track()
	match _phase:
		PHASE_CRAWL:
			var goal := _ends[_goal]
			var speed := pattern("crawlSpeed", 55.0)
			var offset := goal - get_centre()
			if offset.length() <= maxf(1.0, speed * delta):
				body.velocity = offset / maxf(delta, 0.0001)
				_begin_turn(now)
			else:
				body.velocity = offset.normalized() * speed
				_heading = Vector2.UP.angle_to(offset)
				set_frame(FRAME_CRAWL_A if int(now / STEP_MS) % 2 == 0 else FRAME_CRAWL_B)
			set_look(CENTRE_LIFT, Vector2.ONE, _heading)
		PHASE_TURN:
			body.velocity = Vector2.ZERO
			var t := clampf(_elapsed(now) / maxf(1.0, pattern("turnMs", 500.0)), 0.0, 1.0)
			_heading = _turn_from + (_turn_to - _turn_from) * t
			set_look(CENTRE_LIFT, Vector2.ONE, _heading)
			if t >= 1.0:
				_heading = wrapf(_turn_to, -PI, PI)
				_transition(PHASE_CRAWL, now)
				set_frame(FRAME_CRAWL_A)
	_spikes(target)


## Its track from the vines it is placed on (or `trackPx` along its way off them), the near end
## first in its starting way.
func _plan_track() -> void:
	var way := _start_way()
	var horizontal := absf(way.x) > absf(way.y)
	var centre := get_centre()
	var half := pattern("bodyHalfPx", 30.0)
	var run := Rect2()
	for node: Node in body.get_tree().get_nodes_in_group(VINES_GROUP):
		if node.has_method(&"run_rect"):
			run = node.call(&"run_rect", centre, horizontal)
			if run.has_area():
				break
	var from := centre - way * pattern("trackPx", 192.0) * 0.5
	var to := centre + way * pattern("trackPx", 192.0) * 0.5
	if run.has_area():
		if horizontal:
			var span := Vector2(run.position.x + half, run.end.x - half)
			from = Vector2(minf(span.x, centre.x), centre.y)
			to = Vector2(maxf(span.y, centre.x), centre.y)
		else:
			var span := Vector2(run.position.y + half, run.end.y - half)
			from = Vector2(centre.x, minf(span.x, centre.y))
			to = Vector2(centre.x, maxf(span.y, centre.y))
		# the end ahead in its starting way is `to`
		if way.x < 0.0 or way.y < 0.0:
			var swap := from
			from = to
			to = swap
	_ends = [from, to]
	_goal = 1
	_heading = Vector2.UP.angle_to(way)


func _start_way() -> Vector2:
	var aim := aim_direction if aim_direction != Vector2.ZERO else Vector2.DOWN
	if absf(aim.x) > absf(aim.y):
		return Vector2(signf(aim.x), 0.0)
	return Vector2(0.0, signf(aim.y))


## At an end: it curls round (half a turn, the way it curls kept the same) and crawls back.
func _begin_turn(now: float) -> void:
	_goal = 1 - _goal
	_turn_from = _heading
	_turn_to = _heading + PI
	_transition(PHASE_TURN, now)
	set_frame(FRAME_TURN)
	_cue(CUE_TURN)


## The slime touching its spiky body: a hit, at most every `contactCooldownMs`.
func _spikes(target: Dictionary) -> void:
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return
	var centre: Vector2 = target.get("centre", Vector2.INF)
	if not centre.is_finite():
		return
	# Its body along its way: the nearest point of the line through it to the slime's centre.
	var along := get_travel() * pattern("bodyHalfPx", 30.0) * 0.7
	var nearest := Geometry2D.get_closest_point_to_segment(centre, get_centre() - along, get_centre() + along)
	if nearest.distance_to(centre) > pattern("contactReachPx", 30.0):
		return
	_contact(target, _attribute("contactDamage"), _attribute("knockbackStrength"), INF)


## On its track: a knockback does not move it, and a stun holds a turn's clock.
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(now: float, _delta: float) -> void:
	body.velocity = Vector2.ZERO
	if _last_ms >= 0.0 and _phase == PHASE_TURN:
		_phase_started_at += now - _last_ms
	_last_ms = now


func _defeat() -> void:
	if is_defeated():
		return
	super()
	set_look(CENTRE_LIFT, Vector2.ONE, _heading)
