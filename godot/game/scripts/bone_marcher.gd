extends "res://game/enemy/skeleton_enemy.gd"
class_name BoneMarcherScript
## Scene script `game.bone-marcher` (the bestiary's row 32, a patroller; docs/godot/BESTIARY.md "Bone
## Marcher"): a stiff skeleton soldier with an old helmet and a shield, found only in the dungeons.
##
## - **March:** it walks its `route` (points drawn in the editor, from where it was placed: the
##   scene's RoutePreview, game/enemy/route_preview.gd, draws them) at a steady `movement_speed`,
##   round and round (`route_loop`) or back and forth, starting at the route point nearest to it. It
##   never chases and never stops for the slime: its body does not collide with the slime's (it walks
##   on through it) and nothing the slime does changes its route.
## - **Touching it hurts:** the slime within `contactReachPx` of its centre takes `contactDamage`
##   (attributes) with `knockbackStrength`, at most every `contactCooldownMs`.
## - **Blocked** by something solid for `blockedMs` (a pushed block on its route), it turns back
##   along its route.
## - **The right tool:** time the gap to pass; any hit with damage drops it at once into a bone pile
##   (skeleton_enemy.gd), and the pile stands up and marches on unless it is finished (a hit on the
##   pile, or the Gulp takes the skull).
##
## Owner: enemy builder.

const PHASE_MARCH := "march"
const FRAME_FRONT_A := 0
const FRAME_FRONT_B := 1
const FRAME_BACK_A := 2
const FRAME_BACK_B := 3
const CUE_STEP := &"StairsStep"
## A blocked march: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## Presentation: the march's stomp.
const STOMP_PX := 2.5

## Its route: points from where it was placed (old centres), walked in order.
@export var route: PackedVector2Array = PackedVector2Array([Vector2(-96.0, -96.0), Vector2(96.0, -96.0),
	Vector2(96.0, 96.0), Vector2(-96.0, 96.0)])
## True: a closed loop (from the last point on to the first); false: back and forth.
@export var route_loop: bool = true

## The route in world old centres (made on the first step, from its home).
var _points: PackedVector2Array = PackedVector2Array()
var _next: int = 0
var _dir: int = 1
var _asked: Vector2 = Vector2.ZERO
var _blocked_since: float = -1.0
var _step_flip: bool = false
var _back: bool = false


func _ready() -> void:
	super()
	_transition(PHASE_MARCH, Services.now_ms())
	set_frame(FRAME_FRONT_A)


func _step_skeleton(now: float, delta: float, target: Dictionary, _engaged: bool) -> void:
	if _points.is_empty():
		_build_route()
	_contact(target, _attribute("contactDamage"), _attribute("knockbackStrength"), pattern("contactReachPx", 34.0))
	if _points.is_empty():
		body.velocity = Vector2.ZERO
		return
	var centre := get_centre()
	var reach := maxf(pattern("pointSlackPx", 3.0), movement_speed * delta)
	if centre.distance_to(_points[_next]) <= reach:
		if _points.size() == 1:
			body.velocity = Vector2.ZERO
			_asked = Vector2.ZERO
			set_look(0.0)
			return
		_advance()
	var blocked := _asked != Vector2.ZERO and body.velocity.length() < _asked.length() * BLOCKED_SHARE
	if blocked:
		if _blocked_since < 0.0:
			_blocked_since = now
		elif now - _blocked_since >= pattern("blockedMs", 600.0):
			_turn_back()
	else:
		_blocked_since = -1.0
	var offset := _points[_next] - centre
	_asked = offset.normalized() * movement_speed if offset != Vector2.ZERO else Vector2.ZERO
	body.velocity = _asked
	_animate(now)


## The route point after `_next`: round the loop, or back at the ends.
func _advance() -> void:
	var count := _points.size()
	if route_loop:
		_next = posmod(_next + _dir, count)
		return
	if _next + _dir < 0 or _next + _dir >= count:
		_dir = -_dir
	_next = clampi(_next + _dir, 0, count - 1)


## Blocked: back the way it came.
func _turn_back() -> void:
	_dir = -_dir
	_blocked_since = -1.0
	var count := _points.size()
	_next = posmod(_next + _dir, count) if route_loop else clampi(_next + _dir, 0, count - 1)


func _build_route() -> void:
	_points = PackedVector2Array()
	for point: Vector2 in route:
		_points.append(_home + point)
	var centre := get_centre()
	var best := INF
	for index: int in _points.size():
		var distance := centre.distance_to(_points[index])
		if distance < best:
			best = distance
			_next = index


func _animate(now: float) -> void:
	var step_ms := maxf(1.0, pattern("stepMs", 300.0))
	var flip := int(now / step_ms) % 2 == 1
	if flip != _step_flip:
		_step_flip = flip
		_cue(CUE_STEP)
	var velocity := body.velocity
	if absf(velocity.y) > absf(velocity.x) + WALK_SPEED_THRESHOLD:
		_back = velocity.y < 0.0
	elif absf(velocity.x) > WALK_SPEED_THRESHOLD:
		_back = false
	if _back:
		set_frame(FRAME_BACK_B if flip else FRAME_BACK_A)
	else:
		set_frame(FRAME_FRONT_B if flip else FRAME_FRONT_A)
	var t := fmod(now, step_ms) / step_ms
	set_look(sin(t * PI) * STOMP_PX)
	if absf(velocity.x) > WALK_SPEED_THRESHOLD:
		face_x(velocity.x)


## Any hit with damage drops it into its bone pile at once.
func _kill_hit(request: Dictionary) -> bool:
	return not is_pile() and float(request.get("base_damage", 0.0)) > 0.0


## On its route a knockback never moves it.
func _skeleton_slides() -> bool:
	return false


func _on_stand_up(now: float) -> void:
	_transition(PHASE_MARCH, now)
	_asked = Vector2.ZERO
	_blocked_since = -1.0
