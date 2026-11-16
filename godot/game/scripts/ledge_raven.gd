extends "res://game/enemy/patterned_enemy.gd"
class_name LedgeRavenScript
## Scene script `game.ledge-raven` (a climb monster, docs/godot/BESTIARY.md "Ledge Raven"; the owner,
## 2026-11-13: "a raven that sits at the balconies and makes circular and short flights when in
## range, its movement fixed so the player can avoid getting damage on contact"; 2026-11-14, from
## his drawing: "2 circular loops, then back to its place"): a black raven perched on a balcony.
##
## - **Perched** (its feet where it was placed, on a balcony's floor): it watches. Hits hurt it
##   here (30 health), and only here: its one open moment.
## - **Tell** (`tellMs`): the slime's centre within `wakeRangePx` of its perch, `restMs` after it
##   last landed, it caws and ruffles.
## - **Flight** (`loopSpeed`, two loops: `loops`): it takes off, sweeps out onto a circle of
##   `loopRadiusPx` round a point `loopRisePx` over its perch, flies round it `loops` times
##   (`clockwise`) and glides back in to land. The path is the same every time, so the slime can
##   learn it and stay clear. Touching the slime on the way (`contactReachPx`) is a hit with
##   knockback: a climbing slime is knocked off the wall. In flight every hit clinks.
##
## It flies on the wall's face (a front view): the path is drawn as it is on screen, with no height
## and no shadow. Its body is neither solid nor stopped (layer and mask 0).
##
## Owner: enemy builder.

const PHASE_PERCH := "perch"
const PHASE_TELL := "tell"
const PHASE_FLY := "fly"
const FRAME_PERCH := 0
const FRAME_FLAP_UP := 1
const FRAME_FLAP_DOWN := 2
const FRAME_DOWN := 3
const CUE_CAW := &"NpcBlip"
const CUE_TAKE_OFF := &"Lash"
const CUE_LAND := &"Land"
const FEATHERS := &"dodge-dust"
## Presentation: the wings beat every FLAP_MS; the tell's ruffle.
const FLAP_MS := 110.0
const RUFFLE_PX := 3.0
const RUFFLE_MS := 70.0
## Share of the flight spent sweeping out onto the circle (and as much gliding back in).
const SWEEP_SHARE := 0.14

## Which way round it flies its loops (on screen).
@export var clockwise: bool = true

var _perch: Vector2 = Vector2.INF
var _rest_until: float = 0.0
var _flight_ms: float = 1.0


func _ready() -> void:
	super()
	_transition(PHASE_PERCH, Services.now_ms())
	set_frame(FRAME_PERCH)
	_rest_until = Services.now_ms() + pattern("firstRestMs", 600.0)


## Its perch (feet; Vector2.INF before its first step).
func get_perch() -> Vector2:
	return _perch


## True while it flies its loops.
func is_flying() -> bool:
	return _phase == PHASE_FLY


## Where its flight puts its feet at share `t` (0 to 1) of the way: out from the perch onto the
## circle, `loops` times round, and back in.
func flight_point(t: float) -> Vector2:
	var centre := _perch - Vector2(0.0, pattern("loopRisePx", 40.0))
	var radius := pattern("loopRadiusPx", 150.0)
	var ease := smoothstep(0.0, SWEEP_SHARE, t) * smoothstep(0.0, SWEEP_SHARE, 1.0 - t)
	var turn := TAU * pattern("loops", 2.0) * t * (1.0 if clockwise else -1.0)
	# Its first way is straight up from the circle's middle (and on round).
	var on_circle := centre + Vector2.UP.rotated(turn) * radius
	return _perch.lerp(on_circle, ease)


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	if _perch == Vector2.INF:
		_perch = feet()
	match _phase:
		PHASE_PERCH:
			body.velocity = _velocity_to(_perch, delta)
			set_frame(FRAME_PERCH)
			set_look(0.0)
			if engaged and now >= _rest_until and _in_range(target):
				_transition(PHASE_TELL, now)
				_cue(CUE_CAW)
		PHASE_TELL:
			body.velocity = Vector2.ZERO
			set_look(absf(sin(now / RUFFLE_MS)) * RUFFLE_PX, Vector2(1.06, 0.94))
			if _elapsed(now) >= pattern("tellMs", 450.0):
				_take_off(now)
		PHASE_FLY:
			var t := clampf(_elapsed(now) / _flight_ms, 0.0, 1.0)
			var point := flight_point(t)
			body.velocity = _velocity_to(point, delta)
			if absf(body.velocity.x) > WALK_SPEED_THRESHOLD:
				face_x(body.velocity.x)
			set_frame(FRAME_FLAP_UP if int(now / FLAP_MS) % 2 == 0 else FRAME_FLAP_DOWN)
			set_look(0.0)
			if t >= 1.0:
				_land(now)
			else:
				_contact(target, _attribute("contactDamage"), _attribute("knockbackStrength"), pattern("contactReachPx", 30.0))


func _take_off(now: float) -> void:
	# The flight's length from its speed round the loops (the sweeps out and in are part of them).
	var loops_px := TAU * pattern("loopRadiusPx", 150.0) * pattern("loops", 2.0)
	_flight_ms = maxf(1.0, loops_px / maxf(1.0, pattern("loopSpeed", 340.0)) * 1000.0)
	_transition(PHASE_FLY, now)
	_cue(CUE_TAKE_OFF)
	_puff(FEATHERS, feet())


func _land(now: float) -> void:
	body.velocity = Vector2.ZERO
	_transition(PHASE_PERCH, now)
	_rest_until = now + pattern("restMs", 1400.0)
	set_frame(FRAME_PERCH)
	_cue(CUE_LAND)


## The slime is near enough to its perch to set it off.
func _in_range(target: Dictionary) -> bool:
	var centre: Vector2 = target.get("centre", Vector2.INF)
	return centre.is_finite() and centre.distance_to(_perch) <= pattern("wakeRangePx", 220.0)


## Velocity that puts its feet on `point` this step (it flies through everything).
func _velocity_to(point: Vector2, delta: float) -> Vector2:
	return (point - feet()) / maxf(delta, 0.0001)


## In flight every hit clinks; perched (and cawing) it can be hurt.
func _shields(_request: Dictionary) -> bool:
	return _phase == PHASE_FLY


## It flies its path: a stun holds it where it is (and holds its flight's clock).
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(now: float, delta: float) -> void:
	body.velocity = Vector2.ZERO
	_phase_started_at += delta * 1000.0 if _phase == PHASE_FLY else 0.0
	_rest_until = maxf(_rest_until, now)


func _defeat() -> void:
	if is_defeated():
		return
	super()
	set_frame(FRAME_DOWN)
