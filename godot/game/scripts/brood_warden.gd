extends "res://game/enemy/patterned_enemy.gd"
class_name BroodWardenScript
## Scene script `game.brood-warden` (the bestiary's row 22, the Weaver Hollow's mini-boss;
## docs/godot/BESTIARY.md "Brood Warden"): a hulking guard spider in rust-red armour plates with two
## scythe-blade forelegs.
##
## - **Guard:** it faces the slime and stalks it at `walkSpeed` until it is within `sweepRangePx`
##   (and `nextSweepMs` after its last plant); while the slime is away it walks home (`homeSpeed`).
## - **Wind-up** (the tell, `windupMs`; the second sweep's `windup2Ms`): it pulls both blades back to
##   one side, and the sweep's half-ring (`sweepArcDeg` wide, `sweepRadiusPx` round its centre,
##   aimed at the slime) glows on the ground.
## - **Sweep** (`sweepMs`): the blades slash across the half-ring: the slime inside takes
##   `sweepDamage` with `sweepKnockback`. Then `betweenMs`, and the second sweep from the other side
##   (aimed again).
## - **Planted** (`plantedMs`): after the second sweep its legs stay dug in and its back plates open
##   on soft glowing joints: the only time it can be hurt (old-style hits `plantedDamageTaken`
##   times; rework hits: the profile's `states.planted`). Every other hit clinks off its armour.
## - **Recover** (`recoverMs`), then it guards again.
##
## Owner: enemy builder.

const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")

const PHASE_GUARD := "guard"
const PHASE_WINDUP := "windup"
const PHASE_SWEEP := "sweep"
const PHASE_BETWEEN := "between"
const PHASE_PLANTED := "planted"
const PHASE_RECOVER := "recover"
const FRAME_GUARD := 0
const FRAME_WINDUP := 1
const FRAME_SWEEP := 2
const FRAME_PLANTED := 3
const CUE_WINDUP := &"SlamWindup"
const CUE_SWEEP := &"Lash"
const CUE_PLANT := &"StomperSlam"
const CUE_RISE := &"Land"
const DUST := &"dodge-dust"
## Presentation: the half-ring's points, the wind-up's lean, the walk's sway, the planted pant.
const ARC_POINTS := 16
const WINDUP_LEAN_RAD := 0.08
const WALK_SWAY_RAD := 0.035
const WALK_SWAY_MS := 160.0
const PANT := 0.025
const PANT_MS := 140.0

var _sweep: int = 0
var _aim: Vector2 = Vector2.DOWN
var _ready_at: float = 0.0
var _zone: Array[Dictionary] = []


func _ready() -> void:
	super()
	_guard(Services.now_ms())


func _exit_tree() -> void:
	AttackTelegraph.clear_for(self)
	super()


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_GUARD:
			if engaged:
				face_x(slime.x - centre.x)
				var near := centre.distance_to(slime) <= pattern("sweepRangePx", 104.0)
				body.velocity = Vector2.ZERO if near else _velocity_toward(slime, pattern("walkSpeed", 45.0), delta)
				if near and now >= _ready_at:
					_sweep = 0
					_wind_up(now, slime)
			else:
				body.velocity = _velocity_toward(_home, pattern("homeSpeed", 60.0), delta)
				face_x(body.velocity.x)
			var walking := body.velocity.length() > WALK_SPEED_THRESHOLD
			set_look(0.0, Vector2.ONE, sin(now / WALK_SWAY_MS) * WALK_SWAY_RAD if walking else 0.0)
		PHASE_WINDUP:
			body.velocity = Vector2.ZERO
			var windup := pattern("windupMs", 650.0) if _sweep == 0 else pattern("windup2Ms", 450.0)
			var t := clampf(elapsed / maxf(1.0, windup), 0.0, 1.0)
			set_look(0.0, Vector2(1.0 + 0.04 * t, 1.0 - 0.04 * t), (WINDUP_LEAN_RAD if visual.flip_h else -WINDUP_LEAN_RAD) * t)
			if t >= 1.0:
				_slash(now, target, engaged)
		PHASE_SWEEP:
			body.velocity = Vector2.ZERO
			if elapsed >= pattern("sweepMs", 180.0):
				_sweep += 1
				if _sweep >= int(pattern("sweeps", 2.0)):
					_plant(now)
				else:
					_transition(PHASE_BETWEEN, now)
					set_frame(FRAME_GUARD)
		PHASE_BETWEEN:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if elapsed >= pattern("betweenMs", 250.0):
				if engaged:
					_wind_up(now, slime, true)
				else:
					_guard(now)
		PHASE_PLANTED:
			body.velocity = Vector2.ZERO
			var pant := sin(now / PANT_MS) * PANT
			set_look(0.0, Vector2(1.0 + pant, 1.0 - pant))
			if elapsed >= pattern("plantedMs", 1200.0):
				_transition(PHASE_RECOVER, now)
				set_frame(FRAME_GUARD)
				set_look(0.0)
				_cue(CUE_RISE)
		PHASE_RECOVER:
			body.velocity = Vector2.ZERO
			if elapsed >= pattern("recoverMs", 500.0):
				_guard(now)
				_ready_at = now + pattern("nextSweepMs", 600.0)


func _guard(now: float) -> void:
	AttackTelegraph.clear_for(self)
	_transition(PHASE_GUARD, now)
	set_frame(FRAME_GUARD)
	set_look(0.0)


## The tell: blades back on one side (the second sweep: the other side), the half-ring on the
## ground aimed at the slime.
func _wind_up(now: float, slime: Vector2, other_side: bool = false) -> void:
	var centre := get_centre()
	_aim = (slime - centre).normalized() if slime != centre else Vector2.DOWN
	_transition(PHASE_WINDUP, now)
	set_frame(FRAME_WINDUP)
	# The second sweep winds up where the first one ended (the blades stay on that side).
	if not other_side:
		face_x(_aim.x if absf(_aim.x) > 0.01 else 1.0)
	_zone = _half_ring(centre, _aim)
	AttackTelegraph.show_for(self, _zone)
	_cue(CUE_WINDUP)


## The slash across the half-ring.
func _slash(now: float, target: Dictionary, engaged: bool) -> void:
	_transition(PHASE_SWEEP, now)
	set_frame(FRAME_SWEEP)
	if visual != null:
		# The blades end on the other side.
		visual.flip_h = not visual.flip_h
	set_look(0.0)
	AttackTelegraph.clear_for(self)
	_cue(CUE_SWEEP)
	_puff(DUST, feet() + _aim * pattern("sweepRadiusPx", 100.0) * 0.6)
	if engaged and not target.is_empty() and AreaShapes.overlaps_area(_zone, target.get("hurtbox") as Area2D, target.get("centre", Vector2.INF)):
		_route_immediate_attack(target, pattern("sweepDamage", 20.0), pattern("sweepKnockback", 300.0))


func _plant(now: float) -> void:
	_transition(PHASE_PLANTED, now)
	set_frame(FRAME_PLANTED)
	_cue(CUE_PLANT)
	_puff(DUST, feet() + Vector2(-26.0, 0.0))
	_puff(DUST, feet() + Vector2(26.0, 0.0))
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("plantShakeMs", 120.0), pattern("plantShakeIntensity", 0.003))


## The sweep's ground zone: a half-ring (`sweepArcDeg`, `sweepRadiusPx`) round `centre`, facing
## `aim`, as an AreaShapes entry (a convex fan).
func _half_ring(centre: Vector2, aim: Vector2) -> Array[Dictionary]:
	var radius := pattern("sweepRadiusPx", 100.0)
	var arc := deg_to_rad(clampf(pattern("sweepArcDeg", 170.0), 10.0, 180.0))
	var points := PackedVector2Array([Vector2.ZERO])
	for i in ARC_POINTS + 1:
		var angle := aim.angle() - arc * 0.5 + arc * float(i) / float(ARC_POINTS)
		points.append(Vector2.from_angle(angle) * radius)
	var shape := ConvexPolygonShape2D.new()
	shape.points = points
	var zone: Array[Dictionary] = [{"shape": shape, "transform": Transform2D(0.0, centre)}]
	return zone


func is_planted() -> bool:
	return _phase == PHASE_PLANTED


## Its armour turns every hit but while it is planted.
func _shields(_request: Dictionary) -> bool:
	return _phase != PHASE_PLANTED


## Old-style hits on its joints: `plantedDamageTaken` times (rework hits: `states.planted`).
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	if _phase == PHASE_PLANTED and not ReworkMode.is_rework_request(input.get("request", {})):
		damage *= pattern("plantedDamageTaken", 1.0)
	return damage


## Heavy and dug in: a stun never slides it.
func _slides_when_stunned() -> bool:
	return false


func _defeat() -> void:
	if is_defeated():
		return
	AttackTelegraph.clear_for(self)
	super()
