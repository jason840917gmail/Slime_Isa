extends "res://game/enemy/patterned_enemy.gd"
class_name BroodlingScript
## Scene script `game.broodling` (the bestiary's row 20, a swarm; docs/godot/BESTIARY.md
## "Broodling"): a tiny fuzzy cream spiderling with orange spots and huge black eyes that pours out
## of an egg sac (game/scripts/egg_sac.gd). Every hit pops it (tiny: a few hit points).
##
## - **Hatch** (`hatchMs`): it hops out of the sac.
## - **Scuttle:** it zigzags at the slime at `scuttleSpeed` (`zigzagRad` either side, every
##   `zigzagMs`), keeping `spreadPx` from the others; while the slime is away it goes back to where
##   it hatched at `homeSpeed`.
## - **Crouch** (the tell, `crouchMs`): within `leapRangePx` of the slime (`leapCooldownMs` after its
##   last leap) it stops and squats, the slime's centre locked.
## - **Leap** (`leapMs`): it springs `leapPx` at that point, `leapHeightPx` high; the slime within
##   `biteRangePx` takes `biteDamage` with `biteKnockback`.
## - **Recover** (`recoverMs`): it stands, then scuttles again.
##
## Owner: enemy builder.

const PHASE_HATCH := "hatch"
const PHASE_SCUTTLE := "scuttle"
const PHASE_CROUCH := "crouch"
const PHASE_LEAP := "leap"
const PHASE_RECOVER := "recover"
const FRAME_SCUTTLE_A := 0
const FRAME_SCUTTLE_B := 1
const FRAME_LEAP := 2
const FRAME_POPPED := 3
const BROOD_GROUP := &"broodlings"
const CUE_LEAP := &"Jump"
## Presentation: the scuttle's leg step, the crouch's squash, the hatch hop, the shadow.
const STEP_MS := 85.0
const CROUCH_SQUASH := Vector2(1.18, 0.78)
const HATCH_HOP_PX := 12.0
const SHADOW_SIZE := Vector2(9.0, 3.5)

var _leap_from: Vector2 = Vector2.ZERO
var _leap_to: Vector2 = Vector2.ZERO
var _ready_at: float = 0.0
var _zig_seed: float = 0.0


func _enter_tree() -> void:
	add_to_group(BROOD_GROUP)


func _ready() -> void:
	super()
	_zig_seed = randf() * TAU
	_transition(PHASE_HATCH, Services.now_ms())
	set_frame(FRAME_LEAP)
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE


## The sac it came from (its old centre): where it goes back to while the slime is away.
func set_hatched_from(centre: Vector2) -> void:
	set_home(centre)


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_HATCH:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("hatchMs", 280.0)), 0.0, 1.0)
			set_look(sin(t * PI) * HATCH_HOP_PX)
			if t >= 1.0:
				_scuttle(now)
		PHASE_SCUTTLE:
			var goal := slime if engaged else _home
			var speed := pattern("scuttleSpeed", 115.0) if engaged else pattern("homeSpeed", 60.0)
			var velocity := _velocity_toward(goal, speed, delta) if engaged else _velocity_home(speed, delta)
			if velocity != Vector2.ZERO and engaged:
				var zig := sin(now / maxf(1.0, pattern("zigzagMs", 160.0)) + _zig_seed) * pattern("zigzagRad", 0.5)
				velocity = velocity.rotated(zig)
			body.velocity = velocity + _spread()
			face_x(body.velocity.x)
			var moving := body.velocity.length() > WALK_SPEED_THRESHOLD
			if not show_walk(delta, FRAME_SCUTTLE_A):
				set_frame(FRAME_SCUTTLE_B if moving and int(now / STEP_MS) % 2 == 1 else FRAME_SCUTTLE_A)
			set_look(0.0)
			if engaged and now >= _ready_at and centre.distance_to(slime) <= pattern("leapRangePx", 70.0):
				_transition(PHASE_CROUCH, now)
				set_frame(FRAME_SCUTTLE_A)
				_leap_from = feet()
				var offset := slime - centre
				var reach := minf(offset.length(), pattern("leapPx", 80.0))
				_leap_to = _leap_from + (offset.normalized() * reach if offset.length() > 0.0 else Vector2.ZERO)
				face_x(offset.x)
		PHASE_CROUCH:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("crouchMs", 220.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE.lerp(CROUCH_SQUASH, t))
			if not engaged:
				_scuttle(now)
			elif t >= 1.0:
				_transition(PHASE_LEAP, now)
				set_frame(FRAME_LEAP)
				_cue(CUE_LEAP)
		PHASE_LEAP:
			var leap_ms := maxf(1.0, pattern("leapMs", 240.0))
			var t := clampf(elapsed / leap_ms, 0.0, 1.0)
			body.velocity = (_leap_to - _leap_from) / (leap_ms / 1000.0)
			set_look(sin(t * PI) * pattern("leapHeightPx", 14.0), Vector2(0.92, 1.1))
			if engaged:
				_contact(target, pattern("biteDamage", 6.0), pattern("biteKnockback", 120.0), pattern("biteRangePx", 24.0))
			if t >= 1.0:
				body.velocity = Vector2.ZERO
				_transition(PHASE_RECOVER, now)
				set_frame(FRAME_SCUTTLE_A)
				set_look(0.0, Vector2(1.1, 0.9))
				_ready_at = now + pattern("recoverMs", 420.0) + pattern("leapCooldownMs", 700.0)
		PHASE_RECOVER:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if elapsed >= pattern("recoverMs", 420.0):
				_scuttle(now)


func _scuttle(now: float) -> void:
	_transition(PHASE_SCUTTLE, now)
	set_frame(FRAME_SCUTTLE_A)
	set_look(0.0)


## A push away from the other Broodlings within `spreadPx`, so the swarm does not stack.
func _spread() -> Vector2:
	var push := Vector2.ZERO
	var reach := pattern("spreadPx", 20.0)
	var here := get_centre()
	for node: Node in get_tree().get_nodes_in_group(BROOD_GROUP):
		if node == self:
			continue
		var other := node as EnemyScript
		if other == null or other.is_defeated():
			continue
		var away := here - other.get_centre()
		var distance := away.length()
		if distance > 0.01 and distance < reach:
			push += away / distance * (reach - distance) * pattern("spreadPush", 6.0)
	return push


## A stun in the crouch calls the leap off.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_CROUCH:
		_scuttle(now)
