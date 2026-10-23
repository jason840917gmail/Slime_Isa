extends "res://game/enemy/patterned_enemy.gd"
class_name PrismEyeScript
## Scene script `game.prism-eye` (the bestiary's row 26, a sentinel; docs/godot/BESTIARY.md "Prism
## Eye"): a crystal orb on a rock pillar, rooted and solid, that turns its gaze round and burns a beam
## down it when the gaze meets the slime.
##
## How it aims is a switch, `aimDirections` (owner, 2026-10-16: some enemies shoot four ways, some
## eight, the eyes' kind is still open): 0 (the default, the first design) is free aim; 4 or 8 is
## line aim (game/enemy/four_way_aim.gd).
##
## - **Watch:** its gaze (a faint mark on the ground, `sightPx` long; the pupil on the orb follows it,
##   game/enemy/prism_look.gd). Free aim: the gaze turns smoothly at `turnDegPerS` and sees the
##   slime within `gazeHalfDeg` of it (a wedge). Line aim: the gaze holds one of the 4 (or 8) lines
##   for `holdMs`, turns to the next over `stepMs`, and sees the slime only on the line it holds (its
##   centre within `lineTolerancePx` of it; a band). Either way nothing solid may be between them: a
##   ray between their old centres (the bodies' middle height) on the `world` layer (walls, rocks,
##   statues, a pushed heavy block). Every hit clinks.
## - **Charge** (the tell, `chargeMs` 200: owner, 2026-10-16, "200 ms after they see you"): the orb
##   flashes white and blazes, a cue sounds, a thin aim line flickers on and the pupil shrinks to a
##   point. Free aim: the aim locks on the slime, then follows it at `trackDegPerS`. Line aim: the aim
##   stays on the line (a slime that steps off it is missed). So the answer is not to be seen.
## - **Fire** (`beamMs`): a beam along the aim from the orb to the first solid thing (`beamPx` at
##   most, inside its pen): the slime's centre within `beamHalfWidthPx` (+ `slimeRadiusPx`) of it
##   takes `beamDamage` with `beamKnockback` along the beam, once. A heavy block on the line takes the
##   beam instead.
## - **Cool** (`coolMs`): the crystal petals shut over the orb, then it watches again.
## - **Its back is open, its front clinks** (`_shields`, every phase): a hit from an attacker it looks
##   away from (`backDot`: the attacker behind it, against its gaze) lands, any other clinks. The
##   Spear from behind while its gaze is turned away (30 health: two jabs). A hit from behind alarms
##   it: for `alertMs` it turns toward the slime (free aim at `alertTurnDegPerS`; line aim: its next
##   turn is to the slime's line, over `alertStepMs`).
## - **The Bow's hook** (`on_arrow_hit`): an arrow into its eye (from in front of it) shatters it.
##
## The Watcher Eye (row 33, game/scripts/watcher_eye.gd) is this beam on a levitating stone eye that
## wanders round its area: it overrides the hooks `_next_line`, `_watch_move`, `_frame_now`,
## `_orb_px`, `_look_setup`, `_float_look` and `_pupil_shown`, and has numbers of its own.
##
## Owner: enemy builder.

const PrismLook := preload("res://game/enemy/prism_look.gd")
const FourWayAim := preload("res://game/enemy/four_way_aim.gd")

const PHASE_WATCH := "watch"
const PHASE_CHARGE := "charge"
const PHASE_FIRE := "fire"
const PHASE_COOL := "cool"
const FRAME_WATCH := 0
const FRAME_CHARGE := 1
const FRAME_SHUT := 2
const BOW_TARGETS := &"bow_targets"
## The layer its sight and its beam stop at (walls, rocks, props, heavy blocks).
const WORLD_LAYER := 1
const CUE_CHARGE := &"SlamWindup"
const CUE_FIRE := &"Lash"
const CUE_SHUT := &"HitBlocked"
const CUE_SHATTER := &"BreakGlass"
const SPARKS := &"hit-spark"
## The lines of line aim, clockwise from the right (4: the first, third, fifth and seventh).
const EIGHT_LINES: Array[Vector2] = [Vector2(1, 0), Vector2(0.70710678, 0.70710678), Vector2(0, 1),
	Vector2(-0.70710678, 0.70710678), Vector2(-1, 0), Vector2(-0.70710678, -0.70710678), Vector2(0, -1),
	Vector2(0.70710678, -0.70710678)]
## The orb's middle in the sheet cell (the pupil, the beam's start), the beam's look.
const ORB_PX := Vector2(131.0, 72.0)
## The beam's end is drawn this much over its line (the line runs at the bodies' middle height).
const BEAM_LIFT_PX := 4.0
const BEAM_Z := 40
## Presentation: the charge's shiver and its flash (the art brightened, fading over the charge).
const SHIVER_PX := 1.2
const SHIVER_MS := 28.0
const FLASH_TINT := Color(1.9, 1.9, 2.1)

var _gaze: float = PI * 0.5
var _aim: float = PI * 0.5
## Line aim: the line it holds (an index into `lines()`), and the turn to the next one.
var _line: int = 0
var _turning: bool = false
var _turn_from: float = 0.0
var _turn_started: float = 0.0
var _turn_ms: float = 300.0
var _hold_until: float = 0.0
var _beam_end: Vector2 = Vector2.ZERO
var _burnt: bool = false
var _last_ms: float = -1.0
var _gaze_look: PrismLook
var _beam_look: PrismLook
var _pupil: PrismLook
var _alert_until: float = 0.0


func _ready() -> void:
	super()
	add_to_group(BOW_TARGETS)
	_gaze = deg_to_rad(pattern("startGazeDeg", 90.0))
	if aim_directions() > 0:
		_line = _nearest_line(Vector2.RIGHT.rotated(_gaze))
		_gaze = lines()[_line].angle()
	_hold_until = Services.now_ms() + pattern("holdMs", 1300.0)
	_transition(PHASE_WATCH, Services.now_ms())
	set_frame(_frame_now())
	if body != null:
		_gaze_look = PrismLook.new()
		_gaze_look.name = "GazeLook"
		_gaze_look.mode = PrismLook.Mode.GAZE
		_gaze_look.z_index = -1
		_gaze_look.half_angle = deg_to_rad(pattern("gazeHalfDeg", 14.0))
		_gaze_look.half_width = pattern("lineTolerancePx", 16.0) if aim_directions() > 0 else 0.0
		_gaze_look.reach = pattern("sightPx", 300.0)
		body.add_child.call_deferred(_gaze_look)
		_beam_look = PrismLook.new()
		_beam_look.name = "BeamLook"
		_beam_look.mode = PrismLook.Mode.BEAM
		_beam_look.z_as_relative = false
		_beam_look.z_index = BEAM_Z
		_beam_look.beam_width = pattern("beamHalfWidthPx", 12.0)
		body.add_child.call_deferred(_beam_look)
	if visual != null:
		_pupil = PrismLook.new()
		_pupil.name = "Pupil"
		_pupil.mode = PrismLook.Mode.PUPIL
		_pupil.orb_px = _orb_px()
		visual.add_child(_pupil)
	_look_setup()


## Where it looks (radians, 0 = right).
func get_gaze() -> float:
	return _gaze


## How it aims: 0 free, 4 or 8 lines (`aimDirections`).
func aim_directions() -> int:
	var count := int(pattern("aimDirections", 0.0))
	return count if count == 4 or count == 8 else 0


## The lines of line aim (4 or 8 unit vectors, clockwise from the right); empty for free aim.
func lines() -> Array[Vector2]:
	var found: Array[Vector2] = []
	var count := aim_directions()
	if count == 0:
		return found
	for i in EIGHT_LINES.size():
		if count == 8 or i % 2 == 0:
			found.append(EIGHT_LINES[i])
	return found


## The line it holds (line aim; mid-turn, the one it turns to), or its gaze (free aim).
func get_line() -> Vector2:
	var all := lines()
	return all[_line] if not all.is_empty() else Vector2.RIGHT.rotated(_gaze)


## True while it turns between two lines (line aim: it sees nothing then).
func is_turning() -> bool:
	return _turning


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	_last_ms = now
	body.velocity = Vector2.ZERO
	var elapsed := _elapsed(now)
	var slime := target.get("body") as Node2D
	match _phase:
		PHASE_WATCH:
			if aim_directions() > 0:
				_step_gaze(now, slime if engaged else null)
			else:
				_gaze = wrapf(_watch_turn(now, delta, slime if engaged else null), -PI, PI)
			_watch_move(now, delta)
			_float_look(now, 0.0)
			if engaged and slime != null and _sees(_slime_centre(target)):
				# Free aim locks on the slime; line aim stays on its line.
				_aim = (_slime_centre(target) - get_centre()).angle() if aim_directions() == 0 else lines()[_line].angle()
				_gaze = _aim
				_transition(PHASE_CHARGE, now)
				_cue(CUE_CHARGE)
		PHASE_CHARGE:
			if aim_directions() == 0 and slime != null and engaged:
				var want := (_slime_centre(target) - get_centre()).angle()
				_aim = rotate_toward(_aim, want, deg_to_rad(pattern("trackDegPerS", 60.0)) * delta)
			_gaze = _aim
			_beam_end = _beam_end_along(_aim)
			var t := clampf(elapsed / maxf(1.0, pattern("chargeMs", 900.0)), 0.0, 1.0)
			_float_look(now, t)
			if visual != null:
				visual.position.x = sin(now / SHIVER_MS) * SHIVER_PX * t
			if t >= 1.0:
				_fire(now)
		PHASE_FIRE:
			if engaged and not _burnt and slime != null:
				_try_burn(target, _slime_centre(target))
			_float_look(now, 1.0)
			if elapsed >= pattern("beamMs", 300.0):
				_transition(PHASE_COOL, now)
				_cue(CUE_SHUT)
		PHASE_COOL:
			_float_look(now, 0.0)
			if elapsed >= pattern("coolMs", 1400.0):
				_transition(PHASE_WATCH, now)
				_hold_until = now + pattern("holdMs", 1300.0)
	_update_looks(now)


## Line aim: it holds a line for `holdMs`, then turns to the next (`_next_line`) over `_step_ms`.
func _step_gaze(now: float, slime: Node2D) -> void:
	var all := lines()
	if _turning:
		var t := clampf((now - _turn_started) / maxf(1.0, _turn_ms), 0.0, 1.0)
		_gaze = lerp_angle(_turn_from, all[_line].angle(), t)
		if t >= 1.0:
			_turning = false
			_gaze = all[_line].angle()
			_hold_until = now + pattern("holdMs", 1300.0)
		return
	if now >= _hold_until:
		var next := _next_line(now, slime)
		if next == _line:
			_hold_until = now + pattern("holdMs", 1300.0)
			return
		_turn_from = _gaze
		_line = next
		_turning = true
		_turn_started = now
		_turn_ms = _step_ms(now)


## The index of the line nearest `direction` (line aim).
func _nearest_line(direction: Vector2) -> int:
	var all := lines()
	var best := 0
	for i in all.size():
		if all[i].dot(direction) > all[best].dot(direction):
			best = i
	return best


# --- hooks (the Watcher Eye overrides them) ---------------------------------------------------------

## Free aim: the gaze while it watches (radians), turning at `turnDegPerS`; alarmed, toward the
## slime at `alertTurnDegPerS`. `slime` is the slime's body while it is in its pen (null else).
func _watch_turn(now: float, delta: float, slime: Node2D) -> float:
	if slime != null and now < _alert_until:
		var want := (slime.global_position - feet()).angle()
		return rotate_toward(_gaze, want, deg_to_rad(pattern("alertTurnDegPerS", 150.0)) * delta)
	return _gaze + deg_to_rad(pattern("turnDegPerS", 45.0)) * delta


## Line aim: the line it turns to next (an index into `lines()`): the next one round, clockwise;
## alarmed, the line toward the slime.
func _next_line(now: float, slime: Node2D) -> int:
	if slime != null and now < _alert_until:
		return _nearest_line(slime.global_position - feet())
	return posmod(_line + 1, maxi(1, lines().size()))


## Line aim: how long a turn to the next line takes (alarmed: `alertStepMs`).
func _step_ms(now: float) -> float:
	return pattern("alertStepMs", 160.0) if now < _alert_until else pattern("stepMs", 320.0)


## A hit from behind alarms it (and cuts a line hold short).
func _alarm(now: float) -> void:
	_alert_until = now + pattern("alertMs", 1400.0)
	_hold_until = minf(_hold_until, now)


## Its velocity while it watches: none (the tower is rooted; the Watcher Eye drifts). Every other
## phase stands still.
func _watch_move(_now: float, _delta: float) -> void:
	body.velocity = Vector2.ZERO


## The sheet frame for the phase now: the orb watching, blazing (charge, fire), shut (cool).
func _frame_now() -> int:
	match _phase:
		PHASE_CHARGE, PHASE_FIRE:
			return FRAME_CHARGE
		PHASE_COOL:
			return FRAME_SHUT
	return FRAME_WATCH


## The orb's middle in the sheet cell (the pupil, the beam's start).
func _orb_px() -> Vector2:
	return ORB_PX


## After the looks are made (the Watcher shapes its gaze line and iris).
func _look_setup() -> void:
	pass


## The pose (`set_look`) each step; `charge` 0..1 is the charge's progress (1 while firing).
func _float_look(_now: float, _charge: float) -> void:
	set_look(0.0)


## Whether the pupil shows on the current frame.
func _pupil_shown() -> bool:
	return _phase == PHASE_WATCH or _phase == PHASE_CHARGE


## The Bow's hook (the coming Bow, Chapter 3): an arrow into its eye (from in front of it) breaks
## it. `hit` may carry the arrow's `direction` (or `knock`); without one, an arrow while it charges
## does. True when it broke.
func on_arrow_hit(hit: Dictionary) -> bool:
	if is_defeated():
		return false
	var along: Variant = hit.get("direction", hit.get("knock", Vector2.ZERO))
	var into_eye := _phase == PHASE_CHARGE
	if along is Vector2 and (along as Vector2) != Vector2.ZERO:
		into_eye = (along as Vector2).normalized().dot(Vector2.RIGHT.rotated(_gaze)) < 0.0
	if not into_eye:
		_cue(CUE_SHUT)
		return false
	_defeat()
	return true


## True when the attacker of `request` is behind it (it looks away from them, `backDot`).
func is_from_behind(request: Dictionary) -> bool:
	var source: Variant = request.get("source")
	var from := Vector2.INF
	if is_instance_valid(source) and source is Node and (source as Node).has_method(&"get_centre"):
		from = (source as Node).call(&"get_centre")
	else:
		var impact: Variant = request.get("impact", {})
		if impact is Dictionary and (impact as Dictionary).get("position") is Vector2:
			from = (impact as Dictionary)["position"]
	if from == Vector2.INF:
		return false
	var toward := get_centre() - from
	if toward.length() < 1.0:
		return false
	return toward.normalized().dot(Vector2.RIGHT.rotated(_gaze)) > pattern("backDot", 0.2)


## A hit from behind alarms it.
func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if not is_defeated():
		_alarm(Services.now_ms())


## The slime's centre where its gaze can meet it (free aim: the wedge; line aim: on the line it
## holds, not mid-turn), within its sight, nothing solid between.
func _sees(slime_centre: Vector2) -> bool:
	var offset := slime_centre - get_centre()
	if offset.length() > pattern("sightPx", 300.0) or offset.length() < 1.0:
		return false
	if aim_directions() == 0:
		if absf(angle_difference(_gaze, offset.angle())) > deg_to_rad(pattern("gazeHalfDeg", 14.0)):
			return false
	else:
		if _turning:
			return false
		var line := lines()[_line]
		var along := offset.dot(line)
		var across := absf(offset.cross(line))
		if along <= 0.0 or across > pattern("lineTolerancePx", 16.0):
			return false
	return _ray(get_centre(), slime_centre).is_empty()


## The slime's old centre (its middle height, where the sight and the beam run).
func _slime_centre(target: Dictionary) -> Vector2:
	var slime := target.get("body") as Node2D
	return target.get("centre", slime.global_position if slime != null else get_centre())


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	var space := body.get_world_2d().direct_space_state if body != null and body.is_inside_tree() else null
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_LAYER, [body.get_rid()])
	return space.intersect_ray(query)


## The beam's end along `angle`: the first solid thing, else `beamPx` on, cut at its pen's edge.
func _beam_end_along(angle: float) -> Vector2:
	var from := get_centre()
	var to := from + Vector2.RIGHT.rotated(angle) * pattern("beamPx", 360.0)
	if not _arena.is_empty():
		var area := Rect2(float(_arena.get("x", 0.0)), float(_arena.get("y", 0.0)), float(_arena.get("w", 0.0)),
			float(_arena.get("h", 0.0)))
		to = _clip_to(area, from, to)
	var hit := _ray(from, to)
	return hit.get("position", to) if not hit.is_empty() else to


static func _clip_to(area: Rect2, from: Vector2, to: Vector2) -> Vector2:
	if area.has_point(to) or not area.has_point(from):
		return to
	var t := 1.0
	var d := to - from
	for axis in 2:
		var lo := area.position[axis]
		var hi := area.end[axis]
		if d[axis] > 0.0 and to[axis] > hi:
			t = minf(t, (hi - from[axis]) / d[axis])
		elif d[axis] < 0.0 and to[axis] < lo:
			t = minf(t, (lo - from[axis]) / d[axis])
	return from + d * clampf(t, 0.0, 1.0)


func _fire(now: float) -> void:
	_transition(PHASE_FIRE, now)
	_burnt = false
	_beam_end = _beam_end_along(_aim)
	if visual != null:
		visual.position.x = 0.0
	_cue(CUE_FIRE)
	_puff(SPARKS, _beam_end - Vector2(0.0, BEAM_LIFT_PX))


func _try_burn(target: Dictionary, slime_centre: Vector2) -> void:
	var from := get_centre()
	var closest := Geometry2D.get_closest_point_to_segment(slime_centre, from, _beam_end)
	if closest.distance_to(slime_centre) > pattern("beamHalfWidthPx", 12.0) + pattern("slimeRadiusPx", 12.0):
		return
	_burnt = true
	_route_hit_from(get_centre(), target, pattern("beamDamage", 22.0), pattern("beamKnockback", 260.0),
		Vector2.RIGHT.rotated(_aim))


func _update_looks(now: float) -> void:
	var charging := 0.0
	if _phase == PHASE_CHARGE:
		charging = clampf(_elapsed(now) / maxf(1.0, pattern("chargeMs", 900.0)), 0.2, 1.0)
	if _gaze_look != null:
		_gaze_look.gaze = _gaze
		_gaze_look.charging = charging
		_gaze_look.shown = _phase == PHASE_WATCH or _phase == PHASE_CHARGE
	if not is_defeated():
		set_frame(_frame_now())
	if visual != null:
		# The tell is short: a white flash that fades over the charge.
		var flash := 1.0 - clampf(_elapsed(now) / maxf(1.0, pattern("chargeMs", 200.0)), 0.0, 1.0) if _phase == PHASE_CHARGE else 0.0
		visual.self_modulate = Color.WHITE.lerp(FLASH_TINT, flash)
	if _pupil != null:
		_pupil.gaze = _gaze
		_pupil.charging = charging
		_pupil.shown = _pupil_shown() and not is_defeated()
	if _beam_look != null and visual != null:
		var scale_px := absf(visual.scale.x)
		var orb := visual.position + (visual.offset + _orb_px()) * scale_px
		if pose != null:
			orb += pose.position
		_beam_look.beam_from = orb
		_beam_look.beam_end = _beam_end - feet() - Vector2(0.0, BEAM_LIFT_PX)
		_beam_look.charging = charging
		var beam := 0.0
		if _phase == PHASE_FIRE:
			beam = 1.0 - clampf(_elapsed(now) / maxf(1.0, pattern("beamMs", 300.0)), 0.0, 1.0)
		_beam_look.beam = beam


## Its front clinks; its back is open.
func _shields(request: Dictionary) -> bool:
	return not is_from_behind(request)


## Rooted: a knockback does not move it; a stun holds the charge's clock.
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(now: float, _delta: float) -> void:
	body.velocity = Vector2.ZERO
	if _last_ms >= 0.0 and _phase == PHASE_CHARGE:
		_phase_started_at += now - _last_ms
	_last_ms = now
	_update_looks(now)


func _defeat() -> void:
	if is_defeated():
		return
	_cue(CUE_SHATTER)
	if visual != null:
		visual.position.x = 0.0
		visual.self_modulate = Color.WHITE
	super()
	if _gaze_look != null:
		_gaze_look.shown = false
	if _pupil != null:
		_pupil.shown = false
	if _beam_look != null:
		_beam_look.beam = 0.0
		_beam_look.charging = 0.0
