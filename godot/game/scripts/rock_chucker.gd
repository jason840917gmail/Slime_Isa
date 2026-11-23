extends "res://game/enemy/patterned_enemy.gd"
class_name RockChuckerScript
## Scene script `game.rock-chucker` (a climb monster, docs/godot/BESTIARY.md "Rock Chucker"; the
## owner, 2026-11-13: "one on the top of the cliff that throws bouncing rocks that come down
## bouncing on the walls from one side to the other"): a burly helmeted worm of Gorge's army that
## squats on a cliff's rim and throws boulders down its face.
##
## - **Its post:** where it is placed, on the high ground at the rim of a front wall. It never
##   leaves it (a hit does not move it). The face under it is read from the elevation once (its
##   rim and its foot, straight below it); placed over no wall it never throws.
## - **Throw** (`throwEveryMs`, `windupMs` tell with the boulder over its head, then
##   `throwPoseMs`): while the slime is below its rim, within `reachXPx` across and `reachYPx`
##   down, it throws a boulder (game/enemy/wall_rock.gd) down the face.
## - **The boulder** bounces down the face in hops (`hopDownPx` each, `hopMs` long), every bounce on
##   the other side of a lane `laneHalfPx` each side of the thrower, the first toward the slime's
##   side, and shatters at the foot. It hits the slime it touches (`rockDamage`, `rockKnockback`): a
##   climbing slime is knocked off the wall.
## - Anything can hurt it (30 health): the slime that gets up over the rim beats it.
##
## Owner: enemy builder.

const WallRock := preload("res://game/enemy/wall_rock.gd")

const PHASE_READY := "ready"
const PHASE_WINDUP := "windup"
const PHASE_THROWN := "thrown"
const FRAME_READY := 0
const FRAME_WINDUP := 1
const FRAME_THROWN := 2
## Its own wind-up sound (Sound Picker round 13, 2026-11-21; it played the slime's SlamWindup before).
const CUE_WINDUP := &"ChuckerWindup"
const CUE_THROW := &"Lash"
## level_at's answer on a wall's face (no level there).
const ON_WALL := -1000
## The rim and the foot are looked for in steps of this many px.
const PROBE_STEP_PX := 8.0

## Its face: (rim y, foot y) under it, Vector2.ZERO before it is read, Vector2.INF with none.
var _face: Vector2 = Vector2.ZERO
var _next_throw_at: float = 0.0
var _last_side: float = -1.0


func _ready() -> void:
	super()
	_transition(PHASE_READY, Services.now_ms())
	set_frame(FRAME_READY)
	_next_throw_at = Services.now_ms() + pattern("firstThrowMs", 700.0)


## The face under it: (rim y, foot y), or Vector2.INF when it stands over no wall.
func get_face() -> Vector2:
	if _face == Vector2.ZERO:
		_face = _find_face()
	return _face


func _step_pattern(now: float, _delta: float, target: Dictionary, _engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	match _phase:
		PHASE_READY:
			set_frame(FRAME_READY)
			set_look(0.0)
			if now >= _next_throw_at and get_face().is_finite() and _in_reach(target):
				_transition(PHASE_WINDUP, now)
				set_frame(FRAME_WINDUP)
				_cue(CUE_WINDUP)
		PHASE_WINDUP:
			var t := clampf(_elapsed(now) / maxf(1.0, pattern("windupMs", 600.0)), 0.0, 1.0)
			set_look(0.0, Vector2(1.0 - 0.05 * t, 1.0 + 0.06 * t))
			if t >= 1.0:
				_throw(now, target)
		PHASE_THROWN:
			set_look(0.0, Vector2(1.06, 0.95))
			if _elapsed(now) >= pattern("throwPoseMs", 300.0):
				_transition(PHASE_READY, now)
				_next_throw_at = now + pattern("throwEveryMs", 2200.0)


## The slime below its rim, within reach across and down.
func _in_reach(target: Dictionary) -> bool:
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return false
	var centre: Vector2 = target.get("centre", Vector2.INF)
	if not centre.is_finite():
		return false
	var offset := centre - feet()
	return offset.y > 0.0 and offset.y <= pattern("reachYPx", 1200.0) and absf(offset.x) <= pattern("reachXPx", 240.0)


func _throw(now: float, target: Dictionary) -> void:
	_transition(PHASE_THROWN, now)
	set_frame(FRAME_THROWN)
	_cue(CUE_THROW)
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	# The first bounce toward the slime's side (alternating when it is straight below).
	var centre: Vector2 = target.get("centre", feet())
	var side := signf(centre.x - feet().x)
	if absf(centre.x - feet().x) < 8.0:
		side = -_last_side
	_last_side = side
	var rock := WallRock.new()
	rock.points = bounce_points(side)
	rock.hop_ms = pattern("hopMs", 380.0)
	rock.arc_px = pattern("hopArcPx", 34.0)
	rock.picture_scale = pattern("rockScale", 0.8)
	rock.hit_px = pattern("rockHitPx", 26.0)
	rock.damage = pattern("rockDamage", 14.0)
	rock.knockback = pattern("rockKnockback", 220.0)
	rock.thrower = self
	parent.add_child(rock)
	rock.start()


## Where a boulder thrown toward `side` (-1 left, 1 right) bounces: from its hands over its head,
## down the face from side to side of its lane, the last bounce at the foot.
func bounce_points(side: float) -> PackedVector2Array:
	var face := get_face()
	var x := feet().x
	var points := PackedVector2Array([feet() - Vector2(0.0, pattern("handLiftPx", 56.0))])
	if not face.is_finite():
		return points
	var hops := maxi(1, roundi((face.y - face.x) / maxf(1.0, pattern("hopDownPx", 96.0))))
	var lane := pattern("laneHalfPx", 80.0)
	for hop in range(1, hops + 1):
		var across := side * lane * (1.0 if hop % 2 == 1 else -1.0)
		points.append(Vector2(x + across, face.x + (face.y - face.x) * float(hop) / float(hops)))
	return points


## The rim and the foot of the front wall straight below its feet, from the elevation: the first
## point down from it on no level (the face), then the first on a lower level again (its foot).
func _find_face() -> Vector2:
	var world := Services.world()
	var elevation: Node = world.elevation if world != null else null
	if elevation == null or body == null:
		return Vector2.INF
	var level := int(elevation.call(&"level_of", body))
	var at := feet()
	var limit := at.y + pattern("reachYPx", 1200.0)
	var rim := INF
	while at.y < limit:
		at.y += PROBE_STEP_PX
		var seen := int(elevation.call(&"level_at", at, ON_WALL))
		if is_inf(rim):
			if seen == ON_WALL:
				rim = at.y
			elif seen < level:
				return Vector2.INF
		elif seen != ON_WALL:
			return Vector2(rim, at.y) if seen < level else Vector2.INF
	return Vector2.INF


## At its post: a hit does not move it.
func _slides_when_stunned() -> bool:
	return false
