extends "res://game/scripts/enemy.gd"
class_name ClodStomperScript
## Scene script `game.clod-stomper` (owner, 2026-10-08; roadmap 8.12): the Clod Stomper, a squat
## golem of mud and pebbles, a small Fatty One Eye. It shows the slime what a stone essence and a
## Squash Slam will let it do, and beaten it always drops a stone essence (`gulp.essenceDrops`,
## res://game/world_objects/enemy_loot.gd).
##
## It walks after the slime as a camp enemy (the whole base enemy step: territory, AI, hits). In
## reach it never swings: it stomps.
## - **Crouch** (`crouch_ms`): it stops and squats behind a ring telegraph, the `SlamZone` shapes
##   at its feet (res://game/bosses/attack_telegraph.gd).
## - **Hop** (`air_ms`): it springs straight up `hop_px` and comes down where it stood.
## - **Slam**: everything in the ring takes `slam_damage` with `slam_knockback`; the screen shakes
##   and the ground cracks (`landing_effect_id`); cracked ground within `crack_radius` of its feet
##   gives way (res://game/scripts/cracked_ground.gd `break_open`).
## - **Dazed** (`recovery_ms`): it stands still, the time to hit it; the next stomp waits
##   `stomp_cooldown_ms` after that.
## Hits never break a stomp (it is heavy); a rolling slime's i-frames dodge the slam.
##
## Clips: `idle-*` and `walk-*` (base AI, all three facings on the same side frames, mirrored for
## left), `crouch`, `air`, `slam`, `dazed`, `knockback-*` and `die-*`. Outside the chase the base
## step's idle and walk clips are held back (`_play_animation`).
##
## Owner: enemy builder.

const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")
const CrackedGround := preload("res://game/scripts/cracked_ground.gd")

const PHASE_CHASE := "chase"
const PHASE_CROUCH := "crouch"
const PHASE_AIR := "air"
const PHASE_DAZED := "dazed"
const PHASE_DEAD := "dead"
const CLIP_CROUCH := "crouch"
const CLIP_AIR := "air"
const CLIP_SLAM := "slam"
const CLIP_DAZED := "dazed"
const PHASE_CLIPS: Array[String] = [CLIP_CROUCH, CLIP_AIR, CLIP_SLAM, CLIP_DAZED]
const CUE_CROUCH := &"SlamWindup"
const CUE_HOP := &"Jump"
const CUE_SLAM := &"StomperSlam"

## The ring the slam hits (its shapes; telegraphed during the crouch).
@export var slam_zone: Area2D
@export var crouch_ms: float = 700.0
@export var air_ms: float = 340.0
@export var hop_px: float = 30.0
@export var recovery_ms: float = 700.0
@export var stomp_cooldown_ms: float = 1400.0
@export var slam_damage: float = 26.0
@export var slam_knockback: float = 300.0
## Cracked ground whose root is this close to the stomper's feet breaks under the slam.
@export var crack_radius: float = 90.0
## `effect.<id>` played under the slam; "" = none.
@export var landing_effect_id: String = "boss-ground-crack"
@export var landing_shake_ms: float = 90.0
@export var landing_shake_intensity: float = 0.002

## Payload {"phase": String, "time": float (Services.now_ms())}.
signal phase_changed(payload: Dictionary)

var _phase: String = PHASE_CHASE
var _phase_started_at: float = 0.0
var _next_stomp_at: float = 0.0
var _visual_rest: Vector2 = Vector2.ZERO


func _ready() -> void:
	super()
	if visual != null:
		_visual_rest = visual.position
	var world := Services.world()
	if world != null and not landing_effect_id.is_empty():
		world.packed_scene("effect." + landing_effect_id)


func _exit_tree() -> void:
	AttackTelegraph.clear_for(self)
	super()


## "chase", "crouch", "air", "dazed" or "dead".
func get_phase() -> String:
	return _phase


## Gameplay time the next stomp may start.
func get_next_stomp_at() -> float:
	return _next_stomp_at


func _after_enemy_step(_delta: float) -> void:
	if is_defeated() or _phase == PHASE_DEAD or body == null:
		return
	var now := Services.now_ms()
	if _phase == PHASE_CHASE:
		if get_runtime_state() == EnemyAI.STATE_ATTACK and now >= _next_stomp_at:
			_begin_crouch(now)
		return
	body.velocity = Vector2.ZERO
	var elapsed := now - _phase_started_at
	match _phase:
		PHASE_CROUCH:
			if elapsed >= maxf(1.0, crouch_ms):
				_transition_to(PHASE_AIR, now)
				_play_animation(CLIP_AIR, true)
				_cue(CUE_HOP)
		PHASE_AIR:
			var t := clampf(elapsed / maxf(1.0, air_ms), 0.0, 1.0)
			_set_lift(sin(PI * t) * hop_px)
			if t >= 1.0:
				_slam(now)
		PHASE_DAZED:
			if elapsed >= maxf(1.0, recovery_ms):
				_next_stomp_at = now + maxf(0.0, stomp_cooldown_ms)
				_transition_to(PHASE_CHASE, now)
				_play_facing("idle", true)


func _begin_crouch(now: float) -> void:
	cancel_attack()
	body.velocity = Vector2.ZERO
	_transition_to(PHASE_CROUCH, now)
	_play_animation(CLIP_CROUCH, true)
	AttackTelegraph.show_for(self, AreaShapes.of_area(slam_zone))
	_cue(CUE_CROUCH)


func _slam(now: float) -> void:
	_set_lift(0.0)
	AttackTelegraph.clear_for(self)
	_transition_to(PHASE_DAZED, now)
	_play_animation(CLIP_SLAM, true)
	var target := _primary_target()
	if not target.is_empty() and bool(target.get("active", false)) and _target_overlaps(AreaShapes.of_area(slam_zone), target):
		_route_immediate_attack(target, slam_damage, slam_knockback, -1.0, false)
	_spawn_effect_at(landing_effect_id, get_centre())
	_shake_camera(landing_shake_ms, landing_shake_intensity)
	_cue(CUE_SLAM)
	_break_ground_near(body.global_position)


## Cracked ground in reach of the feet gives way, as under a Heavy slime's Squash Slam.
func _break_ground_near(feet: Vector2) -> void:
	for node: Node in get_tree().get_nodes_in_group(CrackedGround.GROUP):
		var ground := node as CrackedGround
		var root := ground.get_parent() as Node2D if ground != null else null
		if root != null and not ground.is_broken() and root.global_position.distance_to(feet) <= crack_radius + ground.radius:
			ground.break_open()


## Raises the art `px` above its rest (the hop); the body stays on the ground.
func _set_lift(px: float) -> void:
	if visual != null:
		visual.position = _visual_rest - Vector2(0.0, px)


func _transition_to(phase: String, now: float) -> void:
	_phase = phase
	_phase_started_at = now
	phase_changed.emit({"phase": phase, "time": now})


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


# --- base hooks -------------------------------------------------------------------------------

## It never swings: in reach it stomps (`_after_enemy_step`).
func _can_run_common_attack() -> bool:
	return false


## Outside the chase the base step's idle and walk clips wait for the stomp to end.
func _play_animation(clip: String, restart: bool) -> void:
	if _phase != PHASE_CHASE and not is_defeated() and not clip in PHASE_CLIPS:
		return
	super(clip, restart)


func _defeat() -> void:
	if is_defeated():
		return
	AttackTelegraph.clear_for(self)
	_set_lift(0.0)
	_phase = PHASE_DEAD
	super()
