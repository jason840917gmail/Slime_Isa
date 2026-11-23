extends "res://game/enemy/patterned_enemy.gd"
class_name DungRollerScript
## Scene script `game.dung-roller` (the bestiary's row 13, a patroller; docs/godot/BESTIARY.md "Dung
## Roller"): a dung beetle that rolls a big mud ball back and forth along a fixed track.
##
## The body is the ball (its root stands where the ball touches the ground); the beetle walks behind
## it (`beetle`, moved by this script round the ball, with its own body shape and hurtbox shape).
## - **Track**: a straight line through where it was placed, along `patrol_axis` (horizontal or
##   vertical: owner, 2026-11-21, "modify in what direction they wander, horizontal or vertical,
##   since they always go straight"), `patrol_length` to each side; with the axis left on "its own
##   track" the points of `track` instead (from where it was placed, old centres). The ball rolls
##   from point to point at `rollSpeed` and back along them, the beetle pushing it from behind.
##   Anything but the slime that stops the ball (a wall, a fence, a rock) turns it back early.
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
## **The stolen ball** (owner, 2026-11-21; game/enemy/dung_ball.gd): the Gulp sucks the ball off the
## beetle (the ball is a suckable while the beetle has it). From then on the body is the beetle alone
## (its root at its feet) and nothing shields it: every hit lands, as it is.
## - **Furious**: it stamps (`furyMs`, red, steaming), then charges the slime in straight dashes
##   (`chargeSpeed` for `chargePx`, or until something stops it) with a breather between
##   (`chargeRestMs`, the last `chargeTellMs` of it leaning back: the tell). A dash that reaches the
##   slime (`chargeHitPx`) deals `chargeDamage` with `chargeKnockback`; that hit makes the slime drop
##   the ball whole (mouth.gd `drop`). It rages while the slime has the ball, or has broken it, and
##   stands inside its reach (its pen, else its `targeting_radius`).
## - **The ball thrown** is a light soft throwable (thrown_object.gd): a blow that hurts breaks it; a
##   throw that hurts nothing leaves it whole where it came down. Thrown back at a beetle that has
##   lost its ball it is the kill hit.
## - **Fetch**: a ball lying on the ground (a miss, or dropped by the slime) makes it forget the
##   slime at once: it walks to its ball (`fetchSpeed`, round what stands in the way), takes it and
##   rolls it back to its track. The Gulp can steal it again, lying or pushed.
## - **A new ball**: with the slime out of reach it walks home (`homeSpeed`); there, once its ball is
##   no more (broken, or gone with the slime through a door), it kneads a new one (`kneadMs`) and
##   patrols again. While the slime still carries the ball somewhere, it waits at home.
## Beaten with its ball, the ball stays on the ground as a throwable.
##
## Owner: enemy builder.

const DungBall := preload("res://game/enemy/dung_ball.gd")

const PHASE_ROLL := "roll"
const PHASE_TURN := "turn"
const PHASE_BRACE := "brace"
const PHASE_FURY := "fury"
const PHASE_CHARGE := "charge"
const PHASE_REST := "rest"
const PHASE_FETCH := "fetch"
const PHASE_HOME := "home"
const PHASE_WAIT := "wait"
const PHASE_KNEAD := "knead"
const FRAME_PUSH_A := 0
const FRAME_PUSH_B := 1
const FRAME_FLIPPED := 2
const FRAME_BALL := 3
## Its second sheet (2026-11-21): pushing away from the viewer, seen from behind (rolling up), and
## toward it, seen from the front (rolling down), two strides each (`_pose_frame`).
const FRAME_UP_A := 4
const FRAME_UP_B := 5
const FRAME_DOWN_A := 6
const FRAME_DOWN_B := 7
## Its own sounds (Sound Picker round 13, 2026-11-21: it borrowed the slime's before).
const CUE_BRACE := &"DungBrace"
const CUE_PUSH := &"DungPush"
const CUE_BUMP := &"DungBump"
const CUE_FURY := &"DungFury"
const CUE_CHARGE := &"DungCharge"
const CUE_BALL := &"DungBall"
const CUE_HURT := &"DungHurt"
const CUE_DEATH := &"DungDeath"
const DUST := &"dodge-dust"
const STEAM := &"dodge-dust"
const TEXT_FURY := "!!"
const FURY_TEXT_COLOR := &"yellow"
## The ways `patrol_axis` names.
const AXIS_TRACK := 0
const AXIS_HORIZONTAL := 1
const AXIS_VERTICAL := 2
## A blocked roll: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## Presentation: the beetle's stride (a frame swap every this many px rolled or walked), the
## brace's lean, the orbit's flattening in the three-quarter view, the ball's dust.
const STRIDE_PX := 9.0
const BRACE_LEAN_RAD := 0.12
const ORBIT_Y := 0.8
const DUST_EVERY_PX := 26.0
## The beetle's hurtbox and body shapes sit this far above its feet.
const BEETLE_RISE_PX := 12.0
## Presentation of the fury: the stamp's shake and hop, its red, the steam, the dash's bob and lean,
## the tell's lean back, the wait's sway, the knead's bob.
const FURY_SHAKE_PX := 2.5
const FURY_SHAKE_MS := 28.0
const FURY_HOP_PX := 5.0
const FURY_TINT := Color(1.0, 0.5, 0.42)
const FURY_PULSE_MS := 140.0
const STEAM_EVERY_MS := 170.0
const CHARGE_BOB_PX := 2.0
const CHARGE_BOB_MS := 40.0
const CHARGE_LEAN_RAD := 0.1
const TELL_LEAN_RAD := 0.16
const TEXT_RISE_PX := 46.0
const KNEAD_BOB_PX := 3.0
const KNEAD_BOB_MS := 90.0
const KNEAD_TURN_RAD := 7.0
## The ball's drawn width in a frame of the sheet (px; scripts/characters/pack-bestiary-enemies.py).
const BALL_ART_PX := 214.0

## The way it rolls: a straight line through where it stands, `patrol_length` to each side; or its
## own `track`. A placed enemy sets it in the Inspector (placed_enemy.gd `patrol_axis`).
@export_enum("Its own track", "Horizontal", "Vertical") var patrol_axis: int = AXIS_TRACK
## How far it rolls to each side of where it stands, along `patrol_axis` (px).
@export_range(16.0, 2048.0, 1.0, "or_greater") var patrol_length: float = 150.0
## The track when `patrol_axis` is "Its own track": points from where it was placed (old centres),
## rolled from first to last and back.
@export var track: PackedVector2Array = PackedVector2Array([Vector2(-150.0, 0.0), Vector2(150.0, 0.0)])
## The beetle (its feet), moved round the ball by this script.
@export var beetle: Node2D
## The beetle's body shape and hurtbox shape (they follow it).
@export var beetle_shape: CollisionShape2D
@export var beetle_hurt_shape: CollisionShape2D
## The ball's look (spun as it rolls), its body shape and its hurtbox shape (off while the beetle
## has no ball).
@export var ball_look: Node2D
@export var ball_shape: CollisionShape2D
@export var ball_hurt_shape: CollisionShape2D

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
## The ball: on the beetle (`_has_ball`: the body is the ball then); its handle for the Gulp
## (dung_ball.gd `ride`); the one lying on the ground it goes for; `_ball_gone` once it broke or was
## lost; and until when it counts as in the mouth or in the air after the mouth was last seen holding
## it (simulation ms).
var _has_ball: bool = true
var _ball: Node2D
var _lying: Node2D
var _ball_gone: bool = false
var _ball_out_until: float = 0.0
## A dash: its start (feet) and whether its tell was cued; the steam's clock.
var _dash_from: Vector2 = Vector2.ZERO
var _tell_cued: bool = false
var _steam_at: float = 0.0
var _ball_scale: Vector2 = Vector2.ONE
## The way the beetle looks (`_look_toward`): the side view (mirrored for left), from behind (up) or
## from the front (down).
var _look_dir: Vector2 = Vector2.RIGHT


func _ready() -> void:
	super()
	_transition(PHASE_BRACE, Services.now_ms())
	set_frame(FRAME_PUSH_A)
	if ball_look != null:
		_ball_scale = ball_look.scale
	if body != null:
		_ball = DungBall.ride(body, self, _ball_picture())
		_ball.call(&"set_takeable", true)
	# Its hurt sound (the scene has no hurt player): any hit that lands.
	damaged.connect(func(_commit: Dictionary) -> void: _cue(CUE_HURT))


## True while it pushes its ball (false once the Gulp took it, until it has one again).
func has_ball() -> bool:
	return _has_ball


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	if _points.is_empty():
		_start()
	if not _has_ball:
		_step_without_ball(now, delta, target, engaged)
		return
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_BRACE:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("braceMs", 350.0)), 0.0, 1.0)
			_place_beetle()
			_look_toward(_dir)
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
			_look_toward(_dir)
			set_look(0.0)
		PHASE_TURN:
			body.velocity = Vector2.ZERO
			var share := maxf(pattern("minTurnShare", 0.3), absf(_turn_by) / PI)
			var t := clampf(elapsed / maxf(1.0, pattern("turnMs", 900.0) * share), 0.0, 1.0)
			var before := _beetle_offset()
			_angle = _turn_from + _turn_by * t
			_place_beetle()
			var walked := _beetle_offset() - before
			_look_toward(-Vector2.from_angle(_angle))
			_stride(walked.length())
			set_look(0.0)
			if t >= 1.0:
				_transition(PHASE_BRACE, now)
				set_frame(_pose_frame(false))
				_cue(CUE_BRACE)
		_:
			# A phase of the beetle alone with the ball back on it (it cannot be): patrol again.
			_begin_turn(now)


## The track in world old centres, the first point to roll to and the beetle behind the ball.
func _start() -> void:
	for point: Vector2 in track_points(patrol_axis, patrol_length, track):
		_points.append(_home + point)
	if _points.is_empty():
		_points.append(_home)
	_index = 0
	_step = 1
	var to_first := _points[0] - get_centre()
	_dir = to_first.normalized() if to_first.length() > 1.0 else Vector2.LEFT
	_angle = (-_dir).angle()


## The track's points from where a roller stands: `length` to each side along `axis` (AXIS_HORIZONTAL,
## AXIS_VERTICAL), else `own` (its `track`). The placed enemy's editor picture draws the same line.
static func track_points(axis: int, length: float, own: PackedVector2Array) -> PackedVector2Array:
	var along := Vector2.ZERO
	if axis == AXIS_HORIZONTAL:
		along = Vector2.RIGHT
	elif axis == AXIS_VERTICAL:
		along = Vector2.DOWN
	if along == Vector2.ZERO:
		return own
	return PackedVector2Array([-along * maxf(0.0, length), along * maxf(0.0, length)])


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


## The beetle's feet from the root: behind the ball at `pushOffsetPx`, flattened in y; on the root
## itself while it has no ball (the body is the beetle then).
func _beetle_offset() -> Vector2:
	if not _has_ball:
		return Vector2.ZERO
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


## Looks the way `way` points: the side view (mirrored for left) when it is more across than up or
## down, else from behind (up the screen) or from the front (down). Zero keeps the last.
func _look_toward(way: Vector2) -> void:
	if way.length() < 0.01:
		return
	_look_dir = way
	if _looks_vertical():
		if visual != null:
			visual.flip_h = false
	else:
		face_x(way.x)


func _looks_vertical() -> bool:
	return absf(_look_dir.y) > absf(_look_dir.x)


## The frame of its pose for the way it looks (`_look_toward`): a stride's first or second step.
func _pose_frame(second_step: bool) -> int:
	if _looks_vertical():
		if _look_dir.y < 0.0:
			return FRAME_UP_B if second_step else FRAME_UP_A
		return FRAME_DOWN_B if second_step else FRAME_DOWN_A
	return FRAME_PUSH_B if second_step else FRAME_PUSH_A


func _stride(px: float) -> void:
	_travelled += px
	var flip := int(_travelled / STRIDE_PX) % 2 == 1
	set_frame(_pose_frame(flip))


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


# --- the stolen ball ---------------------------------------------------------------------------------

## The Gulp took the ball (dung_ball.gd `take`): off the beetle, or from where it lay. It is furious.
func ball_taken() -> void:
	if is_defeated():
		return
	var now := Services.now_ms()
	_lying = null
	_ball_gone = false
	_ball_out_until = now + pattern("ballOutMs", 1200.0)
	if _has_ball:
		_lose_ball()
	_enrage(now)


## Its ball lies on the ground (a throw that hurt nothing, or the slime dropped it): `ball`.
func ball_lies(ball: Node2D) -> void:
	if is_defeated() or _has_ball:
		return
	_lying = ball
	_ball_gone = false


## Its ball broke on something.
func ball_broke() -> void:
	if _has_ball:
		return
	_lying = null
	_ball_gone = true


## One step of the beetle alone: after its ball when it lies somewhere, else furious at the slime
## inside its reach, else home (where it kneads a new ball once the old one is no more).
func _step_without_ball(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	if _slime_holds_ball():
		_ball_out_until = now + pattern("ballOutMs", 1200.0)
	if _lying != null and (not is_instance_valid(_lying) or _lying.is_queued_for_deletion()):
		_lying = null
	if _lying == null and not _ball_gone and now >= _ball_out_until:
		# Neither in the mouth, in the air nor on the ground any more: lost with the slime (a door, a death).
		_ball_gone = true
	if _lying != null and _phase != PHASE_FETCH:
		# It forgets the slime: its ball is all it sees.
		_calm()
		_transition(PHASE_FETCH, now)
	match _phase:
		PHASE_FETCH:
			if _lying == null:
				_after_ball(now, engaged)
				return
			var spot := _lying.global_position
			if feet().distance_to(spot) <= pattern("pushOffsetPx", 34.0):
				_take_back(spot, now)
				return
			body.velocity = _velocity_around(spot + (centre - feet()), pattern("fetchSpeed", 110.0), delta)
			if _way != null and _way.is_lost(now):
				# It cannot get to it: that ball is lost to it (it lies there for the slime).
				_way.reset()
				_lying = null
				_ball_gone = true
			_walk_look(delta)
		PHASE_FURY:
			body.velocity = Vector2.ZERO
			_look_toward(slime - centre)
			_fury_look(now, elapsed, true)
			if elapsed >= pattern("furyMs", 650.0):
				if engaged:
					_dash(now, slime)
				else:
					_go_home(now)
		PHASE_CHARGE:
			var blocked := _asked != Vector2.ZERO and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			var hit := engaged and _contact(target, pattern("chargeDamage", 15.0), pattern("chargeKnockback", 280.0),
				pattern("chargeHitPx", 34.0))
			if hit or blocked or feet().distance_to(_dash_from) >= pattern("chargePx", 240.0):
				if blocked and not hit:
					_cue(CUE_BUMP)
					_puff(DUST, feet() + _dir * 14.0)
				_rest(now)
				return
			_asked = _dir * pattern("chargeSpeed", 300.0)
			body.velocity = _asked
			_look_toward(_dir)
			_stride(_asked.length() * delta)
			set_look(absf(sin(now / CHARGE_BOB_MS)) * CHARGE_BOB_PX, Vector2.ONE, signf(_dir.x) * CHARGE_LEAN_RAD)
			_fury_tint(now)
			_steam(now)
		PHASE_REST:
			body.velocity = Vector2.ZERO
			var rest_ms := pattern("chargeRestMs", 750.0)
			var telling := elapsed >= rest_ms - pattern("chargeTellMs", 320.0)
			_look_toward(slime - centre)
			_fury_tint(now)
			if telling:
				# The tell: it leans back on its legs, then goes.
				if not _tell_cued:
					_tell_cued = true
					_cue(CUE_BRACE)
				set_look(0.0, Vector2(1.06, 0.94), -signf(slime.x - centre.x) * TELL_LEAN_RAD)
			else:
				set_look(0.0)
				set_frame(_pose_frame(false))
			if not engaged:
				_go_home(now)
			elif elapsed >= rest_ms:
				_dash(now, slime)
		PHASE_HOME:
			if engaged:
				_enrage(now)
				return
			body.velocity = _velocity_home(pattern("homeSpeed", 70.0), delta)
			_walk_look(delta)
			if body.velocity == Vector2.ZERO:
				_transition(PHASE_KNEAD if _ball_gone else PHASE_WAIT, now)
				_dir = _first_heading()
		PHASE_WAIT:
			body.velocity = Vector2.ZERO
			_look_toward(slime - centre)
			set_look(0.0)
			set_frame(_pose_frame(false))
			if engaged:
				_enrage(now)
			elif _ball_gone:
				_transition(PHASE_KNEAD, now)
				_dir = _first_heading()
		PHASE_KNEAD:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("kneadMs", 1500.0)), 0.0, 1.0)
			_knead_look(now, t)
			if t >= 1.0:
				_take_back(feet() + _ball_ahead(), now)
		_:
			_enrage(now)


## The ball leaves the beetle: the body is the beetle from now on (its root at the beetle's feet).
func _lose_ball() -> void:
	var offset := _beetle_offset()
	_has_ball = false
	if _ball != null and is_instance_valid(_ball):
		_ball.call(&"set_takeable", false)
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	body.global_position += offset
	_show_ball(false)
	_place_beetle()
	set_look(0.0)
	body.reset_physics_interpolation()


## It has a ball again, standing on the ground point `spot`: the body is the ball again, the beetle
## beside it where it stood; it walks round it and rolls it back to its track.
func _take_back(spot: Vector2, now: float) -> void:
	var beside := feet() - spot
	if _lying != null and is_instance_valid(_lying):
		_lying.call(&"picked_up")
	_lying = null
	_ball_gone = false
	_has_ball = true
	_calm()
	_angle = Vector2(beside.x, beside.y / ORBIT_Y).angle() if beside.length() > 1.0 else (-_dir).angle()
	body.velocity = Vector2.ZERO
	body.global_position = spot
	_show_ball(true)
	_place_beetle()
	body.reset_physics_interpolation()
	if _ball != null and is_instance_valid(_ball):
		_ball.call(&"set_takeable", true)
	_cue(CUE_BALL)
	_puff(DUST, spot)
	# Back to the nearest point of its track, then on along it.
	_index = _nearest_point()
	if _points[_index].distance_to(get_centre()) <= 1.0:
		_next_point()
	_begin_turn(now)


## The ball's look and its shapes on (the beetle pushes it) or off (the beetle alone).
func _show_ball(on: bool) -> void:
	if ball_look != null:
		ball_look.visible = on
		ball_look.scale = _ball_scale
		var holder := ball_look.get_parent() as Node2D
		if holder != null:
			holder.position = Vector2.ZERO
	# Deferred: a hit that beats it can arrive from a physics callback.
	if ball_shape != null:
		ball_shape.set_deferred(&"disabled", not on)
	if ball_hurt_shape != null:
		ball_hurt_shape.set_deferred(&"disabled", not on)


## Furious: the stamp, then the dashes.
func _enrage(now: float) -> void:
	_transition(PHASE_FURY, now)
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	_tell_cued = false
	_cue(CUE_FURY)
	var feel := Services.feel()
	if feel != null and Hearing.heard(feet()):
		feel.floating_text(feet() - Vector2(0.0, TEXT_RISE_PX), TEXT_FURY, FURY_TEXT_COLOR, true)


## A dash at where the slime stands now.
func _dash(now: float, slime: Vector2) -> void:
	var to_slime := slime - get_centre()
	_dir = to_slime.normalized() if to_slime.length() > 1.0 else _dir
	_dash_from = feet()
	_asked = Vector2.ZERO
	_transition(PHASE_CHARGE, now)
	_cue(CUE_CHARGE)
	_puff(DUST, feet() - _dir * 12.0)


func _rest(now: float) -> void:
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	_tell_cued = false
	_transition(PHASE_REST, now)


func _go_home(now: float) -> void:
	_calm()
	_transition(PHASE_HOME, now)


## The lying ball it was after is gone again (the Gulp's `ball_taken` enrages it by itself): furious
## when the slime is in reach, else home.
func _after_ball(now: float, engaged: bool) -> void:
	if engaged:
		_enrage(now)
	else:
		_go_home(now)


## No fury showing.
func _calm() -> void:
	_asked = Vector2.ZERO
	_tell_cued = false
	if pose != null:
		pose.modulate = Color.WHITE
	set_look(0.0)


## The stamp: it hops and shakes on the spot, red, steaming.
func _fury_look(now: float, elapsed: float, steaming: bool) -> void:
	var shake := sin(elapsed / FURY_SHAKE_MS) * FURY_SHAKE_PX
	set_look(absf(sin(elapsed / (FURY_SHAKE_MS * 3.0))) * FURY_HOP_PX)
	if pose != null:
		pose.position.x = shake
	set_frame(_pose_frame(int(elapsed / (FURY_SHAKE_MS * 3.0)) % 2 == 1))
	_fury_tint(now)
	if steaming:
		_steam(now)


## The fury's red, pulsing (on the pose: the hit flash keeps the Visual's own).
func _fury_tint(now: float) -> void:
	if pose != null:
		pose.modulate = Color.WHITE.lerp(FURY_TINT, 0.55 + 0.45 * sin(now / FURY_PULSE_MS))


func _steam(now: float) -> void:
	if now >= _steam_at:
		_steam_at = now + STEAM_EVERY_MS
		_puff(STEAM, beetle_centre() - Vector2(0.0, BEETLE_RISE_PX))


## The beetle walking on its own legs (to its ball, home).
func _walk_look(delta: float) -> void:
	var speed := body.velocity.length()
	_look_toward(body.velocity)
	set_look(0.0)
	if pose != null:
		pose.modulate = Color.WHITE
	if speed > WALK_SPEED_THRESHOLD:
		_stride(speed * delta)
	else:
		set_frame(_pose_frame(false))


## Kneading a new ball: it grows in front of the beetle, turning (`t` 0 to 1), the beetle bobbing.
func _knead_look(now: float, t: float) -> void:
	_look_toward(_dir)
	set_look(absf(sin(now / KNEAD_BOB_MS)) * KNEAD_BOB_PX * (1.0 - t))
	set_frame(_pose_frame(int(now / (KNEAD_BOB_MS * 2.0)) % 2 == 1))
	if ball_look == null:
		return
	var holder := ball_look.get_parent() as Node2D
	if holder != null:
		holder.position = _ball_ahead()
	ball_look.visible = true
	ball_look.scale = _ball_scale * maxf(0.05, t)
	ball_look.rotation = t * KNEAD_TURN_RAD * signf(_dir.x if absf(_dir.x) > 0.1 else 1.0)


## Where a new ball stands from the beetle's feet: `pushOffsetPx` ahead along its heading, flattened
## in y as the orbit is.
func _ball_ahead() -> Vector2:
	var reach := pattern("pushOffsetPx", 34.0)
	return Vector2(_dir.x * reach, _dir.y * reach * ORBIT_Y)


## The heading from home to the first point of its track (east when it has none).
func _first_heading() -> Vector2:
	var to_first := (_points[0] if not _points.is_empty() else _home) - _home
	return to_first.normalized() if to_first.length() > 1.0 else Vector2.RIGHT


## The index of the track point nearest to the ball.
func _nearest_point() -> int:
	var best := 0
	var centre := get_centre()
	for i in _points.size():
		if _points[i].distance_to(centre) < _points[best].distance_to(centre):
			best = i
	return best


## True while the slime's mouth holds this beetle's ball.
func _slime_holds_ball() -> bool:
	var world := Services.world()
	var slime: Node = world.player if world != null else null
	if slime == null or not is_instance_valid(slime) or not slime.has_method(&"get_mouth"):
		return false
	var mouth := slime.call(&"get_mouth") as RefCounted
	var held: Variant = mouth.get(&"held") if mouth != null else null
	return held is Dictionary and DungBall.is_ball(held as Dictionary) and DungBall.roller_of(held as Dictionary) == self


## The ball's picture for the mouth and the throw (dung_ball.gd): its frame of the beetle's sheet.
func _ball_picture() -> Dictionary:
	var sprite := (ball_look.get_child(0) as Sprite2D) if ball_look != null and ball_look.get_child_count() > 0 else null
	var path := str(sprite.get(&"sheet_path")) if sprite != null and &"sheet_path" in sprite else ""
	return {"texture": path, "hframes": sprite.hframes if sprite != null else 1, "frame": FRAME_BALL,
		"art_px": BALL_ART_PX, "ground_px": BALL_ART_PX * (absf(sprite.scale.x) if sprite != null else 0.215)}


# --- hits --------------------------------------------------------------------------------------------

## Pushing its ball, only a hit from behind gets through; alone, nothing shields it.
func _shields(request: Dictionary) -> bool:
	return _has_ball and not is_from_behind(request)


## Its own kind of ball, thrown back at a beetle that has lost its own, finishes it.
func _kill_hit(request: Dictionary) -> bool:
	return not _has_ball and has_tag(request, DungBall.KIND)


## Soft from behind: what gets through to a beetle with its ball lands `rearDamageTaken` times.
func mitigate_damage(input: Dictionary) -> float:
	return super(input) * (pattern("rearDamageTaken", 2.0) if _has_ball else 1.0)


## On its track: a knockback does not move it, the stun only holds it.
func _slides_when_stunned() -> bool:
	return false


## A stun stops the roll; a dash is over (it catches its breath first).
func _on_stunned(now: float, _delta: float) -> void:
	_asked = Vector2.ZERO
	if _phase == PHASE_CHARGE:
		_rest(now)


func _defeat() -> void:
	if is_defeated():
		return
	_puff(DUST, beetle_centre())
	_cue(CUE_DEATH)
	_calm()
	if _ball != null and is_instance_valid(_ball):
		_ball.call(&"set_takeable", false)
	if _has_ball:
		# Its ball stays behind, for the Gulp: the corpse is the beetle alone.
		var world := Services.world()
		var spot := feet()
		_lose_ball()
		var info: Dictionary = _ball.call(&"suck_info") if _ball != null and is_instance_valid(_ball) else {}
		if world != null and not info.is_empty():
			info.erase(DungBall.ROLLER_KEY)
			DungBall.lay(world.entities_root(), spot, info)
	elif _phase == PHASE_KNEAD and ball_look != null:
		ball_look.visible = false
	super()
