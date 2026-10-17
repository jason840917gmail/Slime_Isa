extends "res://game/enemy/patterned_enemy.gd"
class_name ShardbackScript
## Scene script `game.shardback` (the bestiary's row 28, an armoured mini-boss; docs/godot/
## BESTIARY.md "Shardback"): an old tortoise under a shell of crystal that turns brittle in fire
## light.
##
## - **Walk:** it plods toward the slime at `walkSpeed` (home at `homeSpeed` while the slime is out
##   of its pen).
## - **Rear** (the tell, `rearMs`): within `slamRangePx` of the slime (at most every
##   `slamCooldownMs`) it rears up on its hind legs, its crystals glowing, and the ground it will
##   slam darkens (an ellipse `slamRx` x `slamRy` round its feet).
## - **Slam** (`slamPoseMs`): it comes down: the slime's feet in the ellipse take `slamDamage` with
##   `slamKnockback`; crystal shards fly and the ground shakes.
## - **Recover** (`recoverMs`): it stands, then walks again.
## - **The shell:** unlit, every hit is armor (the reaction profile: heavy, poise 4) and only
##   `shellDamageTaken` of it hurts (a clink, so it can still be worn down with patience: about 40
##   jabs). **Brittle** in fire light: inside a burning candle's or brazier's light (any light
##   source but the slime's own ember, game/enemy/light_sense.gd), and for `brittleLingerMs` after
##   it leaves it, or for `brittleMs` after a Lantern flame (a hit tagged `fire`) hits it, its shell
##   glows hot and cracks: hits take `brittleDamageTaken` (140 health: a Spear chain or two there).
## A stun (its poise broken) in the rear cancels the slam.
##
## Owner: enemy builder.

const LightSense := preload("res://game/enemy/light_sense.gd")

const PHASE_WALK := "walk"
const PHASE_REAR := "rear"
const PHASE_SLAM := "slam"
const PHASE_RECOVER := "recover"
const FRAME_WALK := 0
const FRAME_REAR := 1
const FRAME_SLAM := 2
const FIRE_TAG := "fire"
const CUE_REAR := &"SlamWindup"
const CUE_SLAM := &"StomperSlam"
const CUE_CLINK := &"HitBlocked"
const CUE_CRACK := &"BreakGlass"
const CUE_BRITTLE := &"StatusBurn"
const SHARDS := &"stone-chip"
const DUST := &"dodge-dust"
const ZONE_NAME := "SlamZone"
## The slam's zone on the ground: a dark red, stronger than a shadow.
const ZONE_TINT := Color(0.32, 0.05, 0.02, 0.5)
## Presentation: the plod's bob, the brittle glow (a warm pulse on the shell's art).
const STEP_MS := 260.0
const STEP_BOB := 0.025
const BRITTLE_TINT := Color(1.35, 0.92, 0.72)
const BRITTLE_PULSE_MS := 140.0

var _brittle_until: float = 0.0
var _slam_ready_at: float = 0.0
var _slam_at: Vector2 = Vector2.ZERO
var _zone: GroundShadowLook
var _was_brittle: bool = false


func _ready() -> void:
	super()
	_transition(PHASE_WALK, Services.now_ms())
	set_frame(FRAME_WALK)


func _exit_tree() -> void:
	_clear_zone()
	super()


## True while fire light has its shell brittle.
func is_brittle() -> bool:
	return Services.now_ms() < _brittle_until


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	_sense_light(now)
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_WALK:
			if engaged:
				body.velocity = _velocity_toward(slime, pattern("walkSpeed", 38.0), delta)
				face_x(slime.x - centre.x)
				if centre.distance_to(slime) <= pattern("slamRangePx", 96.0) and now >= _slam_ready_at:
					_rear(now)
			else:
				body.velocity = _velocity_toward(_home, pattern("homeSpeed", 50.0), delta)
				face_x(body.velocity.x)
			var bob := sin(now / STEP_MS * PI) * STEP_BOB if body.velocity.length() > WALK_SPEED_THRESHOLD else 0.0
			set_look(0.0, Vector2(1.0 + bob, 1.0 - bob))
		PHASE_REAR:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("rearMs", 800.0)), 0.0, 1.0)
			set_look(0.0, Vector2(1.0 - 0.04 * t, 1.0 + 0.06 * t))
			if _zone != null:
				_zone.strength = lerpf(0.2, 1.0, t)
			if t >= 1.0:
				_slam(now, target, engaged)
		PHASE_SLAM:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2(1.08, 0.92))
			if elapsed >= pattern("slamPoseMs", 450.0):
				_transition(PHASE_RECOVER, now)
				set_frame(FRAME_WALK)
		PHASE_RECOVER:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if elapsed >= pattern("recoverMs", 900.0):
				_transition(PHASE_WALK, now)
	_brittle_look(now)


## Fire light on it keeps its shell brittle a little longer.
func _sense_light(now: float) -> void:
	if LightSense.light_at(get_tree(), get_centre(), pattern("lightPadPx", 26.0), true) > 0.0:
		_brittle_until = maxf(_brittle_until, now + pattern("brittleLingerMs", 1200.0))


func _rear(now: float) -> void:
	_transition(PHASE_REAR, now)
	set_frame(FRAME_REAR)
	_cue(CUE_REAR)
	_slam_at = feet()
	_clear_zone()
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent != null:
		_zone = GroundShadowLook.new()
		_zone.name = ZONE_NAME
		_zone.size = Vector2(pattern("slamRx", 88.0), pattern("slamRy", 60.0))
		_zone.tint = ZONE_TINT
		_zone.strength = 0.2
		parent.add_child(_zone)
		_zone.global_position = _slam_at


func _slam(now: float, target: Dictionary, engaged: bool) -> void:
	_transition(PHASE_SLAM, now)
	set_frame(FRAME_SLAM)
	_clear_zone()
	_slam_ready_at = now + pattern("slamPoseMs", 450.0) + pattern("recoverMs", 900.0) + pattern("slamCooldownMs", 1200.0)
	_cue(CUE_SLAM)
	_puff(SHARDS, _slam_at)
	_puff(DUST, _slam_at)
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("slamShakeMs", 200.0), pattern("slamShake", 0.006))
	var slime_body := target.get("body") as Node2D
	if not engaged or slime_body == null:
		return
	var offset := slime_body.global_position - _slam_at
	var rx := maxf(1.0, pattern("slamRx", 88.0))
	var ry := maxf(1.0, pattern("slamRy", 60.0))
	if (offset.x / rx) * (offset.x / rx) + (offset.y / ry) * (offset.y / ry) <= 1.0:
		_route_hit_from(get_centre(), target, pattern("slamDamage", 26.0), pattern("slamKnockback", 320.0))


func _brittle_look(now: float) -> void:
	var brittle := now < _brittle_until
	if brittle and not _was_brittle:
		_cue(CUE_BRITTLE)
	_was_brittle = brittle
	if pose == null:
		return
	if brittle:
		var pulse := 0.5 + 0.5 * sin(now / BRITTLE_PULSE_MS)
		pose.modulate = Color.WHITE.lerp(BRITTLE_TINT, 0.7 + 0.3 * pulse)
	else:
		pose.modulate = Color.WHITE


func _clear_zone() -> void:
	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()
	_zone = null


## Its shell: a share of each hit unlit, more than the hit brittle.
func mitigate_damage(input: Dictionary) -> float:
	var share := pattern("brittleDamageTaken", 1.6) if is_brittle() else pattern("shellDamageTaken", 0.3)
	return super(input) * share


## A flame on its shell makes it brittle; a hit clinks on hard crystal and cracks brittle crystal.
func commit_damage(commit: Dictionary) -> void:
	var request: Dictionary = commit.get("request", {})
	var brittle := is_brittle()
	if has_tag(request, FIRE_TAG):
		_brittle_until = maxf(_brittle_until, Services.now_ms() + pattern("brittleMs", 4000.0))
	super(commit)
	if is_defeated():
		return
	var result: Dictionary = commit.get("result", {})
	if int(result.get("actual_damage", 0)) > 0 or brittle:
		_cue(CUE_CRACK if brittle else CUE_CLINK)
		if brittle:
			_puff(SHARDS, get_centre())


## A stun (its poise broken) in the rear cancels the slam.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_REAR:
		_clear_zone()
		_transition(PHASE_RECOVER, now)
		set_frame(FRAME_WALK)
		_slam_ready_at = now + pattern("slamCooldownMs", 1200.0)
	_brittle_look(now)


func _defeat() -> void:
	if is_defeated():
		return
	_clear_zone()
	_cue(CUE_CRACK)
	_puff(SHARDS, get_centre())
	if pose != null:
		pose.modulate = Color.WHITE
	super()
