extends "res://game/enemy/skeleton_enemy.gd"
class_name BoneLeaperScript
## Scene script `game.bone-leaper` (the bestiary's row 30, a pouncer; docs/godot/BESTIARY.md "Bone
## Leaper"): a small crouched skeleton with a red scarf, found only in the dungeons. It never chases.
##
## - **Watch:** it crouches still. It sees the slime when the slime is engaged (in its pen, or within
##   `targeting_radius`), within `sightPx` and in a clear line (the world's line of sight: walls,
##   statues and rocks block it, the pen's fence does not).
## - **Cast** (the tell, `castMs`): it rattles, its eye sockets glow brighter and brighter
##   (game/enemy/socket_glow.gd), and a ringed shadow darkens on the ground where it will land
##   (game/enemy/landing_mark.gd): where the slime stood when the cast began (`leapMaxPx` at most).
## - **Air** (`airMs`, `leapHeightPx`): one big leap there. In the air nothing hurts it (every hit
##   clinks) and the slime passes under it (not solid); a wall or the water ends the leap early.
## - **Landing:** the slime within `landHitRadiusPx` takes `landDamage` with `landKnockback`, and the
##   ground shakes a little.
## - **Stuck** (`stuckMs`): it lands so hard its feet sink in; it is open and takes
##   `stuckDamageTaken` times the damage (the reaction profile's `states.stuck` for rework hits).
##   Then it pulls itself free (`recoverMs`) and watches again, `castCooldownMs` before its next cast.
## - **The right tool:** Roll out of the shadow, then the Spear while it is stuck (40 health: two jabs
##   there).
## - With the slime away it creeps back to where it was placed (`homeSpeed`).
## A stun during the cast cancels the leap. Beaten, it falls into a bone pile (skeleton_enemy.gd).
##
## Owner: enemy builder.

const SocketGlowLook := preload("res://game/enemy/socket_glow.gd")
const LandingMarkLook := preload("res://game/enemy/landing_mark.gd")

const PHASE_WATCH := "watch"
const PHASE_CAST := "cast"
const PHASE_AIR := "air"
const PHASE_STUCK := "stuck"
const PHASE_RECOVER := "recover"
const FRAME_WATCH := 0
const FRAME_CAST := 1
const FRAME_AIR := 2
const FRAME_STUCK := 3
const CUE_CAST := &"GroundCreak"
const CUE_LEAP := &"Jump"
const CUE_LAND := &"StomperSlam"
const MARK_NAME := "LandingMark"
const GLOW_NAME := "SocketGlow"
## Presentation: the watch's breath, the cast's rattle and squash, the air's stretch, the landing's
## squash, the stuck wobble, the free hop, the shadows. The glowing eyes' pixels in each frame.
const BREATH := 0.025
const BREATH_MS := 380.0
const CAST_SQUASH := Vector2(1.1, 0.86)
const CAST_SHAKE_RAD := 0.07
const CAST_SHAKE_MS := 22.0
const AIR_STRETCH := Vector2(0.94, 1.08)
const LAND_SQUASH := Vector2(1.2, 0.8)
const STUCK_WOBBLE_RAD := 0.05
const STUCK_WOBBLE_MS := 150.0
const FREE_HOP_PX := 5.0
const SHADOW_SIZE := Vector2(18.0, 7.0)
const MARK_SIZE := Vector2(30.0, 12.0)
const EYES := {
	FRAME_CAST: [Vector2(115.0, 169.0), Vector2(151.0, 169.0)],
	FRAME_AIR: [Vector2(119.0, 154.0), Vector2(148.0, 154.0)],
}

var _ready_at: float = 0.0
var _mark: LandingMarkLook
var _glow: SocketGlowLook
var _sight_at: float = -INF
var _sight_ok: bool = false


func _ready() -> void:
	super()
	_watch(Services.now_ms())
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE
	if visual != null:
		_glow = SocketGlowLook.new()
		_glow.name = GLOW_NAME
		_glow.eyes = EYES
		visual.add_child.call_deferred(_glow)


func _exit_tree() -> void:
	_clear_mark()
	super()


func _step_skeleton(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_WATCH:
			var breath := sin(now / BREATH_MS) * BREATH
			set_look(0.0, Vector2(1.0 + breath, 1.0 - breath))
			if engaged:
				body.velocity = Vector2.ZERO
				face_x(slime.x - centre.x)
				if now >= _ready_at and _sees(now, target):
					_cast(now, slime)
			elif centre.distance_to(_home) > pattern("homeSlackPx", 8.0):
				body.velocity = _velocity_home(pattern("homeSpeed", 40.0), delta)
				face_x(body.velocity.x)
				show_walk(delta, FRAME_WATCH)
			else:
				body.velocity = Vector2.ZERO
				show_walk(delta, FRAME_WATCH)
		PHASE_CAST:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("castMs", 500.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE.lerp(CAST_SQUASH, t), sin(elapsed / CAST_SHAKE_MS) * CAST_SHAKE_RAD)
			_set_glow(lerpf(0.35, 1.0, t))
			if _mark != null:
				_mark.strength = t
				_mark.size = MARK_SIZE * lerpf(0.5, 1.0, t)
			if t >= 1.0:
				_leap(now)
		PHASE_AIR:
			var air_ms := maxf(1.0, pattern("airMs", 620.0))
			var t := clampf(elapsed / air_ms, 0.0, 1.0)
			# A wall or the water ends the leap early; the slime, the other bodies and the liftable
			# things do not (leap_step).
			if not leap_step(t, air_ms, delta):
				_land(now, target, engaged)
				return
			var height := pattern("leapHeightPx", 70.0)
			var lift := sin(PI * t) * height
			set_look(lift, AIR_STRETCH)
			var shadow := ground_shadow()
			if shadow != null:
				shadow.size = SHADOW_SIZE * lerpf(1.0, 0.55, lift / maxf(1.0, height))
		PHASE_STUCK:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2.ONE, sin(elapsed / STUCK_WOBBLE_MS) * STUCK_WOBBLE_RAD)
			if elapsed >= pattern("stuckMs", 1300.0):
				_transition(PHASE_RECOVER, now)
				set_frame(FRAME_WATCH)
				_puff(DUST, feet())
		PHASE_RECOVER:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("recoverMs", 320.0)), 0.0, 1.0)
			set_look(sin(PI * t) * FREE_HOP_PX)
			if t >= 1.0:
				_watch(now)
				_ready_at = now + pattern("castCooldownMs", 800.0)


## True when the slime is within `sightPx` and nothing of the world stands between (throttled).
func _sees(now: float, target: Dictionary) -> bool:
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	if centre.distance_to(slime) > pattern("sightPx", 220.0):
		return false
	if now - _sight_at < SIGHT_CHECK_MS:
		return _sight_ok
	_sight_at = now
	var world := Services.world()
	if world == null:
		_sight_ok = true
		return true
	var exclude: Array[RID] = [body.get_rid()]
	var player_body := target.get("body") as CharacterBody2D
	if player_body != null:
		exclude.append(player_body.get_rid())
	_sight_ok = world.line_of_sight(centre, slime, exclude)
	return _sight_ok


func _watch(now: float) -> void:
	_transition(PHASE_WATCH, now)
	set_frame(FRAME_WATCH)
	set_look(0.0)
	_set_glow(0.0)


## The tell: where it will land is where the slime stands now (`leapMaxPx` at most).
func _cast(now: float, slime: Vector2) -> void:
	_transition(PHASE_CAST, now)
	set_frame(FRAME_CAST)
	var offset := slime - get_centre()
	if offset.length() > pattern("leapMaxPx", 240.0):
		offset = offset.normalized() * pattern("leapMaxPx", 240.0)
	var landing := plan_leap(offset)
	face_x(offset.x)
	_cue(CUE_CAST)
	_clear_mark()
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent != null:
		_mark = LandingMarkLook.new()
		_mark.name = MARK_NAME
		_mark.strength = 0.0
		parent.add_child(_mark)
		_mark.global_position = landing


func _leap(now: float) -> void:
	_transition(PHASE_AIR, now)
	set_frame(FRAME_AIR)
	begin_leap()
	_set_glow(1.0)
	_cue(CUE_LEAP)
	_puff(DUST, feet())


func _land(now: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	end_leap()
	set_look(0.0, LAND_SQUASH)
	_set_glow(0.0)
	_clear_mark()
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE
	_transition(PHASE_STUCK, now)
	set_frame(FRAME_STUCK)
	_cue(CUE_LAND)
	_puff(DUST, feet())
	_puff(CHIPS, feet())
	_shake_camera(pattern("landShakeMs", 120.0), pattern("landShakeIntensity", 0.003))
	if engaged:
		_route_immediate_attack(target, pattern("landDamage", 10.0), pattern("landKnockback", 280.0),
			pattern("landHitRadiusPx", 38.0))


func _set_glow(strength: float) -> void:
	if _glow != null and is_instance_valid(_glow):
		_glow.strength = strength
		_glow.refresh()


func face_x(dx: float) -> void:
	super(dx)
	if _glow != null and is_instance_valid(_glow):
		_glow.refresh()


func _clear_mark() -> void:
	if _mark != null and is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null


## A stun in the cast cancels the leap.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_CAST:
		_clear_mark()
		_watch(now)
		_ready_at = get_hit_stun_until() + pattern("castCooldownMs", 800.0) * 0.5


func _skeleton_shields(_request: Dictionary) -> bool:
	return _phase == PHASE_AIR


## Old-style hits (the Roll's bonk, the classic game) while it is stuck: `stuckDamageTaken` times;
## a rework hit gets it from the reaction profile's `states.stuck.damageTaken`.
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	if _phase == PHASE_STUCK and not ReworkMode.is_rework_request(input.get("request", {})):
		damage *= pattern("stuckDamageTaken", 2.0)
	return damage


func _on_collapse(_now: float) -> void:
	_clear_mark()
	_set_glow(0.0)
	# A leap cut short lands first (its mask back); the pile then lies not solid (skeleton_enemy.gd).
	end_leap()
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE


func _on_stand_up(now: float) -> void:
	_watch(now)
	_ready_at = now + pattern("castCooldownMs", 800.0)
