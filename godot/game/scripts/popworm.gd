extends "res://game/enemy/patterned_enemy.gd"
class_name PopwormScript
## Scene script `game.popworm` (the bestiary's row 5, a burrower; docs/godot/BESTIARY.md "Popworm"):
## a pink earthworm that travels underground.
##
## - **Burrowed:** a dirt mound slides toward the slime at `burrowSpeed` (home at `homeSpeed` while
##   the slime is away). Nothing hurts it (no hurtbox) and the slime walks over it (not solid).
## - **Tell** (`tellMs`): within `surfaceRangePx` of the slime (and `resurfaceMs` after it last went
##   down) it stops and its leafy tail flicks up out of the mound.
## - **Up** (`upMs`): it pops out of the ground and bites `biteAtMs` later (`biteDamage`,
##   `biteKnockback`, the slime within `biteRangePx`). It is open the whole time it is up: the
##   Spear's moment.
## - **Sink** (`sinkMs`): it squashes back into the mound and goes on underground.
## - **Dazed** (`dazedMs`): a heavy shake near the mound (GroundShake: a Heavy Roll's bonk within
##   its reach, or a Heavy Roll rumbling past within `rollHeavyRumbleRadiusPx`; within the shake's
##   radius + `shakeReachPx`) throws it out of the ground, limp on top of the soil, open, then it
##   sinks.
##
## Owner: enemy builder.

const GroundShake := preload("res://game/enemy/ground_shake.gd")

const PHASE_BURROWED := "burrowed"
const PHASE_TELL := "tell"
const PHASE_UP := "up"
const PHASE_SINK := "sink"
const PHASE_DAZED := "dazed"
const FRAME_MOUND := 0
const FRAME_TAIL := 1
const FRAME_BITE := 2
const FRAME_DAZED := 3
const CUE_TELL := &"GroundCreak"
const CUE_POP := &"DropPop"
const CUE_BITE := &"Lash"
const CUE_THROWN_OUT := &"RollBonk"
const DUST := &"dodge-dust"
## Presentation: the mound's wobble while it travels, the dust it leaves, the pop's hop and the
## tail's flick.
const WOBBLE := 0.05
const WOBBLE_MS := 85.0
const DUST_EVERY_MS := 240.0
const POP_PX := 10.0
const POP_MS := 160.0
const FLICK_RAD := 0.12
const FLICK_MS := 60.0
const SINK_SQUASH := 0.45
const DAZE_SWAY_RAD := 0.08
const DAZE_SWAY_MS := 260.0

var _bitten: bool = false
var _next_surface_at: float = 0.0
var _dust_at: float = 0.0


func _ready() -> void:
	super()
	add_to_group(GroundShake.GROUP)
	_burrow(Services.now_ms())


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_BURROWED:
			var goal: Vector2 = target.get("centre", _home) if engaged else _home
			var speed := pattern("burrowSpeed", 90.0) if engaged else pattern("homeSpeed", 60.0)
			body.velocity = _velocity_toward(goal, speed, delta)
			var wobble := sin(now / WOBBLE_MS) * WOBBLE
			set_look(0.0, Vector2(1.0 + wobble, 1.0 - wobble))
			if body.velocity.length() > WALK_SPEED_THRESHOLD and now >= _dust_at:
				_dust_at = now + DUST_EVERY_MS
				_puff(DUST, feet())
			if engaged and now >= _next_surface_at \
					and get_centre().distance_to(target.get("centre", Vector2.INF)) <= pattern("surfaceRangePx", 44.0):
				body.velocity = Vector2.ZERO
				_transition(PHASE_TELL, now)
				set_frame(FRAME_TAIL)
				face_x((target.get("centre", get_centre()) as Vector2).x - get_centre().x)
				_cue(CUE_TELL)
		PHASE_TELL:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2.ONE, sin(elapsed / FLICK_MS) * FLICK_RAD)
			if elapsed >= pattern("tellMs", 550.0):
				_surface(now, target)
		PHASE_UP:
			body.velocity = Vector2.ZERO
			var pop := clampf(elapsed / POP_MS, 0.0, 1.0)
			set_look(sin(pop * PI) * POP_PX, Vector2(1.0 - 0.1 * (1.0 - pop), 1.0 + 0.15 * (1.0 - pop)))
			if not _bitten and elapsed >= pattern("biteAtMs", 120.0):
				_bitten = true
				_cue(CUE_BITE)
				if engaged:
					_route_immediate_attack(target, pattern("biteDamage", 18.0), pattern("biteKnockback", 220.0),
						pattern("biteRangePx", 64.0))
			if elapsed >= pattern("upMs", 950.0):
				_sink(now)
		PHASE_SINK:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("sinkMs", 260.0)), 0.0, 1.0)
			set_look(0.0, Vector2(1.0 + 0.1 * t, 1.0 - SINK_SQUASH * t))
			if t >= 1.0:
				_burrow(now)
		PHASE_DAZED:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2.ONE, sin(elapsed / DAZE_SWAY_MS) * DAZE_SWAY_RAD)
			if elapsed >= pattern("dazedMs", 2200.0):
				_sink(now)


## Out of the ground: open, solid, the bite on its way.
func _surface(now: float, target: Dictionary) -> void:
	_transition(PHASE_UP, now)
	set_frame(FRAME_BITE)
	set_hurtbox(true)
	set_solid(true)
	_bitten = false
	face_x((target.get("centre", get_centre()) as Vector2).x - get_centre().x)
	_puff(DUST, feet())
	_cue(CUE_POP)


func _sink(now: float) -> void:
	_transition(PHASE_SINK, now)
	set_frame(FRAME_TAIL)
	set_hurtbox(false)


func _burrow(now: float) -> void:
	_transition(PHASE_BURROWED, now)
	set_frame(FRAME_MOUND)
	set_look(0.0)
	set_hurtbox(false)
	set_solid(false)
	_next_surface_at = now + pattern("resurfaceMs", 1300.0)


## GroundShake: a heavy shake within its reach throws it out of the ground, dazed.
func on_ground_shake(at: Vector2, radius: float, heavy: bool) -> void:
	if not heavy or is_defeated() or not (_phase in [PHASE_BURROWED, PHASE_TELL, PHASE_SINK]):
		return
	if feet().distance_to(at) > radius + pattern("shakeReachPx", 24.0):
		return
	var now := Services.now_ms()
	_transition(PHASE_DAZED, now)
	set_frame(FRAME_DAZED)
	set_hurtbox(true)
	set_solid(true)
	body.velocity = Vector2.ZERO
	_puff(DUST, feet())
	_cue(CUE_THROWN_OUT)


## True while it is in the ground (the hurtbox is off then too).
func is_burrowed() -> bool:
	return _phase in [PHASE_BURROWED, PHASE_TELL, PHASE_SINK]


func _shields(_request: Dictionary) -> bool:
	return is_burrowed()
