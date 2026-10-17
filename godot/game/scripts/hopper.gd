extends "res://game/enemy/patterned_enemy.gd"
class_name HopperScript
## Scene script `game.hopper` (the bestiary's row 7, a jumper; docs/godot/BESTIARY.md "Hopper"): a
## springy shell bug that hops in arcs toward the slime.
##
## - **Rest** (`landMs`): it has landed and stands open: the Spear's moment.
## - **Crouch** (the tell, `crouchMs`): it folds its legs, and a shadow on the ground marks where it
##   will land: toward the slime, `hopPx` at most (toward its home while the slime is away).
## - **Air** (`airMs`): it flies there in an arc `hopHeightPx` high. In the air nothing hurts it
##   (every hit clinks) and the slime passes under it (not solid); a wall ends the hop early.
## - **Landing:** the slime within `landHitRadiusPx` of it takes `contactDamage` (attributes) with
##   `knockbackStrength`, then it rests again.
## A hit that stuns it in its crouch cancels the hop.
##
## Owner: enemy builder.

const PHASE_REST := "rest"
const PHASE_CROUCH := "crouch"
const PHASE_AIR := "air"
const FRAME_STAND := 0
const FRAME_CROUCH := 1
const FRAME_AIR := 2
const CUE_JUMP := &"Jump"
const CUE_LAND := &"Land"
const DUST := &"dodge-dust"
const MARK_NAME := "LandingMark"
## A blocked hop: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## Presentation: the crouch's squash, the rest's breath, the shadows.
const CROUCH_SQUASH := Vector2(1.14, 0.8)
const BREATH := 0.03
const BREATH_MS := 300.0
const SHADOW_SIZE := Vector2(20.0, 7.0)
const MARK_SIZE := Vector2(22.0, 8.0)

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _asked: Vector2 = Vector2.ZERO
var _mark: GroundShadowLook


func _ready() -> void:
	super()
	_transition(PHASE_REST, Services.now_ms())
	set_frame(FRAME_STAND)
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE


func _exit_tree() -> void:
	_clear_mark()
	super()


func _step_pattern(now: float, _delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_REST:
			body.velocity = Vector2.ZERO
			var breath := sin(now / BREATH_MS) * BREATH
			set_look(0.0, Vector2(1.0 + breath, 1.0 - breath))
			if elapsed < pattern("landMs", 500.0):
				return
			var slime: Vector2 = target.get("centre", get_centre())
			if engaged:
				_crouch(now, slime)
			elif get_centre().distance_to(_home) > pattern("homeSlackPx", 24.0):
				_crouch(now, _home)
		PHASE_CROUCH:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("crouchMs", 320.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE.lerp(CROUCH_SQUASH, t))
			if _mark != null:
				_mark.strength = t
				_mark.size = MARK_SIZE * lerpf(0.5, 1.0, t)
			if t >= 1.0:
				_leap(now)
		PHASE_AIR:
			var air_ms := maxf(1.0, pattern("airMs", 600.0))
			var t := clampf(elapsed / air_ms, 0.0, 1.0)
			var blocked := _asked != Vector2.ZERO and elapsed > 0.0 \
				and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			if t >= 1.0 or blocked:
				_land(now, target, engaged)
				return
			var lift := sin(PI * t) * pattern("hopHeightPx", 48.0)
			set_look(lift, Vector2(0.94, 1.08))
			var shadow := ground_shadow()
			if shadow != null:
				shadow.size = SHADOW_SIZE * lerpf(1.0, 0.6, lift / maxf(1.0, pattern("hopHeightPx", 48.0)))
			_asked = (_to - _from) / (air_ms / 1000.0)
			body.velocity = _asked


## The tell: where it will land, toward `goal` (an old centre), `hopPx` at most.
func _crouch(now: float, goal: Vector2) -> void:
	_transition(PHASE_CROUCH, now)
	set_frame(FRAME_CROUCH)
	var centre := get_centre()
	var offset := goal - centre
	var reach := minf(offset.length(), pattern("hopPx", 120.0))
	var step := offset.normalized() * reach if offset.length() > 0.0 else Vector2.ZERO
	_from = feet()
	_to = _from + step
	face_x(step.x)
	_clear_mark()
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent != null:
		_mark = GroundShadowLook.new()
		_mark.name = MARK_NAME
		_mark.strength = 0.0
		parent.add_child(_mark)
		_mark.global_position = _to


func _leap(now: float) -> void:
	_transition(PHASE_AIR, now)
	set_frame(FRAME_AIR)
	set_solid(false)
	_asked = Vector2.ZERO
	_cue(CUE_JUMP)
	_puff(DUST, feet())


func _land(now: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	set_solid(true)
	set_look(0.0, Vector2(1.12, 0.88))
	_clear_mark()
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE
	_transition(PHASE_REST, now)
	set_frame(FRAME_STAND)
	_cue(CUE_LAND)
	_puff(DUST, feet())
	if engaged:
		_route_immediate_attack(target, _attribute("contactDamage"), _attribute("knockbackStrength"),
			pattern("landHitRadiusPx", 34.0))


func _clear_mark() -> void:
	if _mark != null and is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null


## A stun in the crouch cancels the hop.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_CROUCH:
		_clear_mark()
		_transition(PHASE_REST, now)
		set_frame(FRAME_STAND)
		set_look(0.0)


func _shields(_request: Dictionary) -> bool:
	return _phase == PHASE_AIR


func _defeat() -> void:
	_clear_mark()
	set_solid(true)
	super()
