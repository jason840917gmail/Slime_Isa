extends "res://game/enemy/patterned_enemy.gd"
class_name ThornGuardScript
## Scene script `game.thorn-guard` (the bestiary's row 9, a patroller; docs/godot/BESTIARY.md "Thorn
## Guard Statue"): an old stone soldier from the war, asleep in the Wilds.
##
## - **Asleep:** a statue: it never moves and every hit clinks. Statues with the same `guard_group`
##   stand as a set: when the slime's centre passes between two of them (within `wakeCorridorPx`
##   of the line from one to the other) the whole set wakes.
## - **Wake** (the tell, `wakeMs`): its eyes light up, it shakes the moss off (still a clink).
## - **March:** it walks in a straight line at `marchSpeed` (first along the axis the slime is
##   furthest along), and when something stops it, it turns: a quarter turn toward the slime's
##   side, else the other way, else back. Touching the slime is `contactDamage` (attributes) with
##   `knockbackStrength`. Heavy and old: hits are armor (the reaction profile), enough Spear hits
##   break it.
## - **The right tool:** a Heavy Roll (the Roll's bonk with the Heavy skin, tags `roll` + `heavy`)
##   knocks it back to rubble at once, awake or asleep.
## - **Back to sleep:** once the slime has been away `sleepAfterMs`, it marches home and sleeps
##   there again, whole.
##
## Owner: enemy builder.

const GROUP := &"thorn_guards"
const PHASE_ASLEEP := "asleep"
const PHASE_WAKE := "wake"
const PHASE_MARCH := "march"
const PHASE_RETURN := "return"
const FRAME_ASLEEP := 0
const FRAME_MARCH_A := 1
const FRAME_MARCH_B := 2
const CUE_WAKE := &"GroundCreak"
const CUE_STEP := &"StairsStep"
const CUE_TURN := &"HitBlocked"
const CUE_RUBBLE := &"BreakStone"
const DUST := &"dodge-dust"
## A blocked march: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## How far ahead a turn is tested before it is taken.
const TURN_PROBE_PX := 10.0
## Presentation: the wake's shake, the march's stomp.
const WAKE_SHAKE_RAD := 0.05
const WAKE_SHAKE_MS := 30.0
const STOMP_PX := 3.0

## Statues with the same group wake together; "" = only itself (it never wakes by the line rule).
@export var guard_group: String = ""

var _dir: Vector2 = Vector2.DOWN
var _asked: Vector2 = Vector2.ZERO
var _away_since: float = -1.0
var _step_flip: bool = false


func _ready() -> void:
	super()
	add_to_group(GROUP)
	_sleep(Services.now_ms())


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_ASLEEP:
			body.velocity = Vector2.ZERO
			if engaged and _slime_between_mates(slime):
				for mate: ThornGuardScript in _mates(true):
					mate.wake(now)
		PHASE_WAKE:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2.ONE, sin(elapsed / WAKE_SHAKE_MS) * WAKE_SHAKE_RAD)
			if elapsed >= pattern("wakeMs", 700.0):
				var to_slime := slime - centre
				_dir = Vector2(signf(to_slime.x), 0.0) if absf(to_slime.x) > absf(to_slime.y) else Vector2(0.0, signf(to_slime.y))
				if _dir == Vector2.ZERO:
					_dir = Vector2.DOWN
				_transition(PHASE_MARCH, now)
				_asked = Vector2.ZERO
				_away_since = -1.0
		PHASE_MARCH:
			if engaged:
				_away_since = -1.0
				_contact(target, _attribute("contactDamage"), _attribute("knockbackStrength"), pattern("contactReachPx", 40.0))
			elif _away_since < 0.0:
				_away_since = now
			elif now - _away_since >= pattern("sleepAfterMs", 1500.0):
				_transition(PHASE_RETURN, now)
				return
			var blocked := _asked != Vector2.ZERO and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			if blocked:
				_turn(slime - centre)
			_asked = _dir * movement_speed
			body.velocity = _asked
			_animate_march(now, delta)
		PHASE_RETURN:
			body.velocity = _velocity_toward(_home, movement_speed, delta)
			_animate_march(now, delta)
			if engaged:
				_transition(PHASE_MARCH, now)
				_asked = Vector2.ZERO
			elif body.velocity == Vector2.ZERO or elapsed >= pattern("returnMaxMs", 6000.0):
				_sleep(now)


## Wakes it (a mate saw the slime pass between them); nothing unless it sleeps.
func wake(now: float) -> void:
	if _phase != PHASE_ASLEEP or is_defeated():
		return
	_transition(PHASE_WAKE, now)
	set_frame(FRAME_MARCH_A)
	_cue(CUE_WAKE)
	_puff(DUST, feet())


func is_asleep() -> bool:
	return _phase == PHASE_ASLEEP


func _sleep(now: float) -> void:
	_transition(PHASE_ASLEEP, now)
	set_frame(FRAME_ASLEEP)
	set_look(0.0)
	_asked = Vector2.ZERO
	body.velocity = Vector2.ZERO
	_restore_health(max_health)


## A quarter turn toward the slime's side when it is free, else the other way, else back.
func _turn(to_slime: Vector2) -> void:
	var side := Vector2(-_dir.y, _dir.x)
	if side.dot(to_slime) < 0.0:
		side = -side
	var choices: Array[Vector2] = [side, -side, -_dir]
	for choice: Vector2 in choices:
		if not body.test_move(body.global_transform, choice * TURN_PROBE_PX):
			_dir = choice
			_cue(CUE_TURN)
			return
	_dir = -_dir


## Its march: the walk cycles (`walk_frame`) when its sheet has them, else its two march steps; a
## stomp bob and a step sound every `stepMs`.
func _animate_march(now: float, delta: float) -> void:
	var step_ms := maxf(1.0, pattern("stepMs", 280.0))
	var flip := int(now / step_ms) % 2 == 1
	if flip != _step_flip:
		_step_flip = flip
		_cue(CUE_STEP)
	var t := fmod(now, step_ms) / step_ms
	set_look(sin(t * PI) * STOMP_PX)
	if show_walk(delta, FRAME_MARCH_A):
		return
	set_frame(FRAME_MARCH_B if flip else FRAME_MARCH_A)
	if absf(body.velocity.x) > WALK_SPEED_THRESHOLD:
		face_x(body.velocity.x)


## The statues of its set (`guard_group`) that are not defeated; `asleep_only` keeps the sleeping
## ones. Includes itself.
func _mates(asleep_only: bool) -> Array[ThornGuardScript]:
	var found: Array[ThornGuardScript] = []
	if guard_group.is_empty():
		return found
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var guard := node as ThornGuardScript
		if guard == null or guard.is_defeated() or guard.guard_group != guard_group:
			continue
		if asleep_only and not guard.is_asleep():
			continue
		found.append(guard)
	return found


## True when the slime's centre is within `wakeCorridorPx` of the line between this statue and
## another sleeping one of its set (between their ends).
func _slime_between_mates(slime: Vector2) -> bool:
	var corridor := pattern("wakeCorridorPx", 40.0)
	var me := get_centre()
	for mate: ThornGuardScript in _mates(true):
		if mate == self:
			continue
		var other := mate.get_centre()
		var line := other - me
		var length_sq := line.length_squared()
		if length_sq <= 0.0:
			continue
		var t := (slime - me).dot(line) / length_sq
		if t < 0.0 or t > 1.0:
			continue
		if slime.distance_to(me + line * t) <= corridor:
			return true
	return false


func _shields(_request: Dictionary) -> bool:
	return _phase == PHASE_ASLEEP or _phase == PHASE_WAKE


## The Heavy Roll knocks it back to rubble.
func _kill_hit(request: Dictionary) -> bool:
	return is_heavy_roll(request)


## Asleep or waking it stands rooted.
func _slides_when_stunned() -> bool:
	return _phase == PHASE_MARCH or _phase == PHASE_RETURN


func _defeat() -> void:
	if is_defeated():
		return
	_cue(CUE_RUBBLE)
	_puff(DUST, feet())
	super()
