extends "res://game/enemy/patterned_enemy.gd"
class_name SquintScript
## Scene script `game.squint` (the bestiary's row 11, an armoured one; docs/godot/BESTIARY.md
## "Squint"), and `game.big-squint` (row 14, Fatty's Lair's mini-boss) with its own numbers: a squat
## burrow beast in slate-blue clay armour, one crimson eye behind a visor of two plates.
##
## - **Walk:** the visor shut, it creeps toward the slime at `walkSpeed` (home while the slime is
##   away), stepping through its walk cycles (`walk_frame`). Its armour shrugs every hit off (a
##   clink).
## - **Rear** (the tell, `rearMs`): within `leapRangePx` of the slime (`cooldownMs` after its last
##   opening) it rears up, rattling, and a ring (`ringRadiusPx` x `ringRadiusYPx`) lights up on the
##   ground where it will come down: where the slime's feet were, `leapPx` at most away.
## - **Air** (`airMs`, `hopHeightPx` high): it leaps there; a wall ends the leap early.
## - **Slam:** everything in the ring takes `slamDamage` with `slamKnockback`; the screen shakes.
##   A Big Squint stomps `stomps` times in a row: after each but the last it settles `betweenMs`,
##   visor shut, and rears again for `nextRearMs` with a new ring at the slime's feet.
## - **Open** (`openMs`, after the last stomp): it lies flat, dazed, the visor wide open. Only the
##   Spear and thrown things get through (a hit tagged `spear` or `thrown`; every other hit still
##   clinks): the Spear or a pot in the eye.
##   Then the visor shuts and it walks again.
##
## Owner: enemy builder.

const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")

const PHASE_WALK := "walk"
const PHASE_REAR := "rear"
const PHASE_AIR := "air"
const PHASE_SETTLE := "settle"
const PHASE_OPEN := "open"
const FRAME_STAND := 0
const FRAME_REAR := 1
const FRAME_OPEN := 2
const FRAME_FLIPPED := 3
## The tag the Spear's hits carry (its shape's tags, and the old spear weapons).
const SPEAR_TAG := "spear"
const CUE_REAR := &"SlamWindup"
const CUE_LEAP := &"Jump"
const CUE_SLAM := &"StomperSlam"
const CUE_OPEN := &"GroundCreak"
const CUE_SHUT := &"GateLocked"
const DUST := &"dodge-dust"
## A blocked leap: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## Presentation: the waddle, the rear's rattle and tilt, the slam's squash, the daze's sway, the
## shadow in the air.
const WADDLE_RAD := 0.06
const WADDLE_MS := 140.0
const REAR_SQUASH := Vector2(0.92, 1.1)
const RATTLE_RAD := 0.05
const RATTLE_MS := 28.0
const SLAM_SQUASH := Vector2(1.16, 0.84)
const SLAM_SQUASH_MS := 160.0
const DAZE_SWAY_RAD := 0.05
const DAZE_SWAY_MS := 240.0
const SHADOW_SIZE := Vector2(22.0, 8.0)
## The ring's outline is drawn with this many points.
const RING_POINTS := 32

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _asked: Vector2 = Vector2.ZERO
var _ready_at: float = 0.0
var _stomps_done: int = 0
var _landed_at: float = -INF


func _ready() -> void:
	super()
	_walk(Services.now_ms())
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE * _shadow_scale()
		shadow.strength = 0.0


func _exit_tree() -> void:
	AttackTelegraph.clear_for(self)
	super()


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_WALK:
			if engaged:
				face_x(slime.x - centre.x)
				if now >= _ready_at and centre.distance_to(slime) <= pattern("leapRangePx", 150.0):
					_rear(now, target)
					return
				body.velocity = _velocity_toward(slime, pattern("walkSpeed", 45.0), delta)
			else:
				body.velocity = _velocity_toward(_home, pattern("walkSpeed", 45.0), delta)
				face_x(body.velocity.x)
			var walking := body.velocity.length() > WALK_SPEED_THRESHOLD
			if show_walk(delta, FRAME_STAND):
				set_look(0.0, _settle_squash(now))
			else:
				set_look(0.0, _settle_squash(now), sin(now / WADDLE_MS) * WADDLE_RAD if walking else 0.0)
		PHASE_REAR:
			body.velocity = Vector2.ZERO
			var rear_ms := pattern("rearMs", 650.0) if _stomps_done == 0 else pattern("nextRearMs", 400.0)
			var t := clampf(elapsed / maxf(1.0, rear_ms), 0.0, 1.0)
			set_look(0.0, Vector2.ONE.lerp(REAR_SQUASH, t), sin(elapsed / RATTLE_MS) * RATTLE_RAD * t)
			if t >= 1.0:
				_leap(now)
		PHASE_AIR:
			var air_ms := maxf(1.0, pattern("airMs", 380.0))
			var t := clampf(elapsed / air_ms, 0.0, 1.0)
			var blocked := _asked != Vector2.ZERO and elapsed > 0.0 \
				and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			if t >= 1.0 or blocked:
				_slam(now, target)
				return
			var height := pattern("hopHeightPx", 34.0)
			var lift := sin(PI * t) * height
			set_look(lift, REAR_SQUASH)
			var shadow := ground_shadow()
			if shadow != null:
				shadow.strength = 1.0
				shadow.size = SHADOW_SIZE * _shadow_scale() * lerpf(1.0, 0.65, lift / maxf(1.0, height))
			_asked = (_to - _from) / (air_ms / 1000.0)
			body.velocity = _asked
		PHASE_SETTLE:
			body.velocity = Vector2.ZERO
			set_look(0.0, _settle_squash(now))
			if elapsed >= pattern("betweenMs", 250.0):
				if engaged:
					_rear(now, target)
				else:
					_walk(now)
		PHASE_OPEN:
			body.velocity = Vector2.ZERO
			set_look(0.0, _settle_squash(now), sin(elapsed / DAZE_SWAY_MS) * DAZE_SWAY_RAD)
			if elapsed >= pattern("openMs", 900.0):
				_cue(CUE_SHUT)
				_walk(now)
				_ready_at = now + pattern("cooldownMs", 900.0)


## The tell: it rears up and the ring lights where it will land.
func _rear(now: float, target: Dictionary) -> void:
	_transition(PHASE_REAR, now)
	set_frame(FRAME_REAR)
	body.velocity = Vector2.ZERO
	_from = feet()
	var goal := _from
	var slime_body := target.get("body") as Node2D
	if slime_body != null:
		goal = slime_body.global_position
	var offset := goal - _from
	var reach := minf(offset.length(), pattern("leapPx", 90.0))
	_to = _from + (offset.normalized() * reach if offset.length() > 0.0 else Vector2.ZERO)
	face_x(offset.x)
	AttackTelegraph.show_for(self, _ring_at(_to))
	_cue(CUE_REAR)


func _leap(now: float) -> void:
	_transition(PHASE_AIR, now)
	set_solid(false)
	_asked = Vector2.ZERO
	_cue(CUE_LEAP)
	_puff(DUST, feet())


func _slam(now: float, target: Dictionary) -> void:
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	set_solid(true)
	_landed_at = now
	var shadow := ground_shadow()
	if shadow != null:
		shadow.strength = 0.0
	var ring := _ring_at(feet())
	AttackTelegraph.clear_for(self)
	if not target.is_empty() and bool(target.get("active", false)) and _target_overlaps(ring, target):
		_route_immediate_attack(target, pattern("slamDamage", 12.0), pattern("slamKnockback", 220.0), -1.0, false)
	_cue(CUE_SLAM)
	_puff(DUST, feet())
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("slamShakeMs", 90.0), pattern("slamShakeIntensity", 0.002))
	_stomps_done += 1
	if _stomps_done < int(pattern("stomps", 1.0)):
		_transition(PHASE_SETTLE, now)
		set_frame(FRAME_STAND)
		return
	_transition(PHASE_OPEN, now)
	set_frame(FRAME_OPEN)
	_cue(CUE_OPEN)


func _walk(now: float) -> void:
	_transition(PHASE_WALK, now)
	set_frame(FRAME_STAND)
	_stomps_done = 0
	_asked = Vector2.ZERO


## The landing's squash, easing back after a slam.
func _settle_squash(now: float) -> Vector2:
	var t := clampf((now - _landed_at) / SLAM_SQUASH_MS, 0.0, 1.0)
	return SLAM_SQUASH.lerp(Vector2.ONE, t)


## The slam's ring round the ground point `at`: an ellipse `ringRadiusPx` x `ringRadiusYPx`.
func _ring_at(at: Vector2) -> Array[Dictionary]:
	var shape := ConvexPolygonShape2D.new()
	shape.points = AbilityWorld.ellipse_points(Vector2(pattern("ringRadiusPx", 52.0), pattern("ringRadiusYPx", 30.0)),
		RING_POINTS)
	var ring: Array[Dictionary] = [{"shape": shape, "transform": Transform2D(0.0, at)}]
	return ring


## The shadow grows with the ring (the Big Squint's is bigger).
func _shadow_scale() -> float:
	return pattern("ringRadiusPx", 52.0) / 52.0


## True while its visor is open (the Spear's moment).
func is_open() -> bool:
	return _phase == PHASE_OPEN


## Its armour: every hit clinks but the Spear's and a thrown thing's (THROWN_TAG, PatternedEnemyScript)
## while the visor is open (owner, 2026-10-22: the Squints take damage from throwables as well).
func _shields(request: Dictionary) -> bool:
	return not (_phase == PHASE_OPEN and (has_tag(request, SPEAR_TAG) or has_tag(request, THROWN_TAG)))


## In the air or rearing it does not slide; dazed and open, a hit's knockback moves it.
func _slides_when_stunned() -> bool:
	return _phase == PHASE_OPEN or _phase == PHASE_WALK


func _defeat() -> void:
	if is_defeated():
		return
	AttackTelegraph.clear_for(self)
	set_solid(true)
	var shadow := ground_shadow()
	if shadow != null:
		shadow.strength = 0.0
	super()
