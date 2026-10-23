extends "res://game/enemy/patterned_enemy.gd"
class_name DungRollerScript
## Scene script `game.dung-roller` (the bestiary's row 13, a patroller; docs/godot/BESTIARY.md "Dung
## Roller"): a dung beetle that rolls a big mud ball back and forth along a fixed track.
##
## The body is the ball (its root stands where the ball touches the ground); the beetle walks behind
## it (`beetle`, moved by this script round the ball, with its own body shape and hurtbox shape).
## - **Track** (`track`): points from where it was placed (old centres); the ball rolls from point
##   to point at `rollSpeed` and back along them, the beetle pushing it from behind. Anything but the
##   slime that stops the ball (a wall, a fence, a rock) turns it back early.
## - **The ball hurts and blocks:** rolling, it hits the slime within `ballHitPx` for
##   `ballDamage` with `ballKnockback` (at most every `contactCooldownMs`). Every hit from the
##   ball's side clinks.
## - **Turn** (the tell, `turnMs` for a half turn, at least `minTurnShare` of it at a bend): at each
##   end the ball stops and the beetle walks round it to its other side, then braces against it
##   (`braceMs`) and pushes off. That is the gap: the ball lies still and harmless, the beetle shows
##   its back.
## - **Soft from behind:** a hit that comes from behind the beetle (the attacker more than `rearDot`
##   behind it, away from the ball) lands, `rearDamageTaken` times; any other clinks. The right
##   tool: Roll through the gap and hit the beetle from behind.
## A hit's stun holds it on its track (no slide) and the pattern waits.
##
## Owner: enemy builder.

const PHASE_ROLL := "roll"
const PHASE_TURN := "turn"
const PHASE_BRACE := "brace"
const FRAME_PUSH_A := 0
const FRAME_PUSH_B := 1
const FRAME_FLIPPED := 2
const CUE_BRACE := &"SlamWindup"
const CUE_PUSH := &"RollLaunch"
const CUE_BUMP := &"RollBonk"
const CUE_STEP := &"StairsStep"
const DUST := &"dodge-dust"
## A blocked roll: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## Presentation: the beetle's stride (a frame swap every this many px rolled or walked), the
## brace's lean, the orbit's flattening in the three-quarter view, the ball's dust.
const STRIDE_PX := 9.0
const BRACE_LEAN_RAD := 0.12
const ORBIT_Y := 0.55
const DUST_EVERY_PX := 26.0
## The beetle's hurtbox and body shapes sit this far above its feet.
const BEETLE_RISE_PX := 12.0

## The track: points from where it was placed (old centres), rolled from first to last and back.
@export var track: PackedVector2Array = PackedVector2Array([Vector2(-150.0, 0.0), Vector2(150.0, 0.0)])
## The beetle (its feet), moved round the ball by this script.
@export var beetle: Node2D
## The beetle's body shape and hurtbox shape (they follow it).
@export var beetle_shape: CollisionShape2D
@export var beetle_hurt_shape: CollisionShape2D
## The ball's look (spun as it rolls).
@export var ball_look: Node2D

var _points: PackedVector2Array = PackedVector2Array()
var _index: int = 0
var _step: int = 1
var _dir: Vector2 = Vector2.LEFT
var _asked: Vector2 = Vector2.ZERO
## The beetle's angle round the ball (radians; 0 = east of it), and the turn from it.
var _angle: float = 0.0
var _turn_from: float = 0.0
var _turn_by: float = 0.0
var _travelled: float = 0.0
var _dust_at: float = 0.0


func _ready() -> void:
	super()
	_transition(PHASE_BRACE, Services.now_ms())
	set_frame(FRAME_PUSH_A)


func _step_pattern(now: float, _delta: float, target: Dictionary, engaged: bool) -> void:
	if _points.is_empty():
		_start()
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_BRACE:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("braceMs", 350.0)), 0.0, 1.0)
			_place_beetle()
			face_x(_dir.x)
			set_look(0.0, Vector2.ONE, -signf(_dir.x) * BRACE_LEAN_RAD * sin(t * PI))
			if t >= 1.0:
				_transition(PHASE_ROLL, now)
				_asked = Vector2.ZERO
				_cue(CUE_PUSH)
		PHASE_ROLL:
			var blocked := _asked != Vector2.ZERO and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			var travelled := body.velocity.length() * get_physics_process_delta_time()
			_roll_look(travelled)
			var hit_slime := engaged and _contact(target, pattern("ballDamage", 20.0), pattern("ballKnockback", 300.0),
				pattern("ballHitPx", 40.0))
			if blocked and not hit_slime and not _slime_touching(target):
				# Something else stopped it: back the way it came.
				_cue(CUE_BUMP)
				_puff(DUST, feet() + _dir * pattern("ballRadiusPx", 22.0))
				_step = -_step
				_index = clampi(_index + _step, 0, _points.size() - 1)
				_begin_turn(now)
				return
			var goal := _points[_index]
			var velocity := _velocity_toward(goal, pattern("rollSpeed", 120.0), get_physics_process_delta_time())
			if velocity == Vector2.ZERO:
				FeetAnchor.place_at_phaser_position(body, goal)
				_next_point()
				_begin_turn(now)
				return
			_dir = velocity.normalized()
			_asked = velocity
			body.velocity = velocity
			_place_beetle()
			face_x(_dir.x)
			set_look(0.0)
		PHASE_TURN:
			body.velocity = Vector2.ZERO
			var share := maxf(pattern("minTurnShare", 0.3), absf(_turn_by) / PI)
			var t := clampf(elapsed / maxf(1.0, pattern("turnMs", 900.0) * share), 0.0, 1.0)
			var before := _beetle_offset()
			_angle = _turn_from + _turn_by * t
			_place_beetle()
			var walked := _beetle_offset() - before
			face_x(walked.x)
			_stride(walked.length())
			set_look(0.0)
			if t >= 1.0:
				_transition(PHASE_BRACE, now)
				set_frame(FRAME_PUSH_A)
				_cue(CUE_BRACE)


## The track in world old centres, the first point to roll to and the beetle behind the ball.
func _start() -> void:
	for point: Vector2 in track:
		_points.append(_home + point)
	if _points.is_empty():
		_points.append(_home)
	_index = 0
	_step = 1
	var to_first := _points[0] - get_centre()
	_dir = to_first.normalized() if to_first.length() > 1.0 else Vector2.LEFT
	_angle = (-_dir).angle()


## The next point along the track, bouncing back at its ends.
func _next_point() -> void:
	if _points.size() <= 1:
		return
	if _index + _step < 0 or _index + _step >= _points.size():
		_step = -_step
	_index += _step


## The ball stops; the beetle walks round it to behind the new heading (through the side nearer
## the viewer on a full turn).
func _begin_turn(now: float) -> void:
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	var goal := _points[_index]
	var to_goal := goal - get_centre()
	var heading := to_goal.normalized() if to_goal.length() > 1.0 else -_dir
	_turn_from = _angle
	_turn_by = angle_difference(_angle, (-heading).angle())
	if absf(absf(_turn_by) - PI) < 0.01:
		# A full turn: round the front (south) side.
		_turn_by = PI if sin(_angle + PI * 0.5) > 0.0 else -PI
	_dir = heading
	_transition(PHASE_TURN, now)


## The beetle's feet from the ball's root: behind the ball at `pushOffsetPx`, flattened in y.
func _beetle_offset() -> Vector2:
	var reach := pattern("pushOffsetPx", 34.0)
	return Vector2(cos(_angle) * reach, sin(_angle) * reach * ORBIT_Y)


func _place_beetle() -> void:
	var offset := _beetle_offset()
	if beetle != null:
		beetle.position = offset
	if beetle_shape != null:
		beetle_shape.position = offset - Vector2(0.0, BEETLE_RISE_PX * 0.5)
	if beetle_hurt_shape != null:
		beetle_hurt_shape.position = offset - Vector2(0.0, BEETLE_RISE_PX)


## The ball spins and the beetle strides as it rolls `travelled` px; dust now and then.
func _roll_look(travelled: float) -> void:
	if ball_look != null:
		var sense := signf(_dir.x if absf(_dir.x) > 0.1 else _dir.y)
		ball_look.rotation += travelled / maxf(1.0, pattern("ballRadiusPx", 22.0)) * sense
	_stride(travelled)
	_dust_at += travelled
	if _dust_at >= DUST_EVERY_PX:
		_dust_at = 0.0
		_puff(DUST, feet() - _dir * pattern("ballRadiusPx", 22.0) * 0.5)


func _stride(px: float) -> void:
	_travelled += px
	var flip := int(_travelled / STRIDE_PX) % 2 == 1
	set_frame(FRAME_PUSH_B if flip else FRAME_PUSH_A)


## The slime pressed against the ball (within its hit reach and a little slack).
func _slime_touching(target: Dictionary) -> bool:
	var centre: Variant = target.get("centre")
	var reach := pattern("ballHitPx", 40.0) + pattern("slimeBlockSlackPx", 14.0)
	return centre is Vector2 and get_centre().distance_to(centre) <= reach


## The beetle's middle (world).
func beetle_centre() -> Vector2:
	return feet() + _beetle_offset() - Vector2(0.0, BEETLE_RISE_PX)


## The ball's middle (world): where the beetle faces.
func ball_centre() -> Vector2:
	return feet() - Vector2(0.0, pattern("ballRadiusPx", 22.0))


## True when the hit in `request` comes from behind the beetle: its attacker (the request's source,
## else the impact point) more than `rearDot` behind it, away from the ball.
func is_from_behind(request: Dictionary) -> bool:
	var at: Variant = null
	var source: Variant = request.get("source")
	if is_instance_valid(source) and source is Object and (source as Object).has_method(&"get_centre"):
		at = (source as Object).call(&"get_centre")
	if not at is Vector2:
		var impact: Variant = request.get("impact", {})
		at = (impact as Dictionary).get("position") if impact is Dictionary else null
	if not at is Vector2:
		return false
	var from := beetle_centre()
	var facing := ball_centre() - from
	var to_attacker := (at as Vector2) - from
	if facing == Vector2.ZERO or to_attacker == Vector2.ZERO:
		return false
	return to_attacker.normalized().dot(facing.normalized()) <= -pattern("rearDot", 0.3)


## Rolling or not, only a hit from behind gets through.
func _shields(request: Dictionary) -> bool:
	return not is_from_behind(request)


## Soft from behind: what gets through lands `rearDamageTaken` times.
func mitigate_damage(input: Dictionary) -> float:
	return super(input) * pattern("rearDamageTaken", 2.0)


## On its track: a knockback does not move it, the stun only holds it.
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(_now: float, _delta: float) -> void:
	_asked = Vector2.ZERO


func _defeat() -> void:
	if is_defeated():
		return
	_puff(DUST, beetle_centre())
	super()
