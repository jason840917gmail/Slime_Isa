extends "res://game/enemy/patterned_enemy.gd"
class_name PipeWormScript
## Scene script `game.pipe-worm` (the bestiary's row 12, a turret; docs/godot/BESTIARY.md "Pipe
## Worm"): a banded worm living in an old clay pipe set in a wall, facing `aim_direction`. The wall
## is the world's (the Bestiary pen's is a short fieldstone wall); the scene is the pipe and the
## worm, its feet at the wall's foot.
##
## - **Hidden:** down in its pipe, two eyes glinting in the dark. Blows never reach it in the pipe
##   (every hit clinks). It hides while the slime is away or within `hideRangePx`, and looks out
##   again `unhideMs` after the slime stepped back.
## - **Up** (popping up over `riseMs`): it spits on a steady beat, every `spitIntervalMs` (the first
##   `firstSpitMs` after it comes up), but only straight out of its pipe: four-way (owner,
##   2026-10-16; game/enemy/four_way_aim.gd), it waits until the slime crosses the pipe's line, its
##   hurtbox middle within `alignTolerancePx` of the line out of the pipe (`aim_direction`, snapped
##   to the nearest of up, down, left and right).
## - **Charge** (the tell, `spitWindupMs`): it swells and shakes; then it spits a mud glob
##   (`projectile.mud-glob`, game/scripts/mud_glob.gd: the scene's `projectile` and
##   `attributes.projectileSpeed`) straight out along the pipe's line (a slime that stepped off it
##   is missed) and shows its spitting pose for `spitPoseMs`.
## - **The right tool:** the Gulp catches the glob in flight and throws it back: a hit tagged
##   `mud-glob` kills it at once, hidden or not (`_kill_hit`).
## - **Shaken out** (`dazedMs`): a Roll's bonk within `bonkReachPx` of its feet (GroundShake: the
##   slime rolling into the wall under its pipe) jolts it out of the pipe; it lies on the floor in
##   front of it, dazed and open to every hit (the Spear), then wriggles back in.
##
## Owner: enemy builder.

const GlobScript := preload("res://game/scripts/mud_glob.gd")
const GroundShake := preload("res://game/enemy/ground_shake.gd")
const FourWayAim := preload("res://game/enemy/four_way_aim.gd")

const PHASE_HIDDEN := "hidden"
const PHASE_UP := "up"
const PHASE_CHARGE := "charge"
const PHASE_SPIT := "spit"
const PHASE_DAZED := "dazed"
const FRAME_HOLE := 0
const FRAME_UP := 1
const FRAME_SPIT := 2
const FRAME_DAZED := 3
const CUE_RISE := &"DropPop"
const CUE_HIDE := &"HitBlocked"
const CUE_CHARGE := &"PipeWormCharge"
const CUE_SPIT := &"PipeWormSpit"
const CUE_SHAKEN := &"RollBonk"
const CUE_BACK := &"DropLand"
const MUD := &"dodge-dust"
## Presentation: the pop up, the charge's swell and shake, the breath while up, the daze's sway.
const RISE_SQUASH := 0.7
const CHARGE_SWELL := 0.14
const CHARGE_SHAKE_RAD := 0.05
const CHARGE_SHAKE_MS := 35.0
const BREATH := 0.03
const BREATH_MS := 380.0
const DAZE_SWAY_RAD := 0.06
const DAZE_SWAY_MS := 260.0
## The glob leaves this far along the aim from the pipe's centre (past the wall's foot).
const MOUTH_PX := 38.0
## Shaken out, the worm lies this far below its pipe, and its hurtbox follows it there.
const FALLEN_POSE_PX := 16.0
const FALLEN_HURTBOX_PX := 30.0

## The way its pipe faces (the wall's open side); it spits only straight along it, snapped to the
## nearest of up, down, left and right.
@export var aim_direction: Vector2 = Vector2.DOWN
## The empty pipe, shown while the worm is out of it.
@export var hole: Sprite2D
## The eyes glinting in the dark while it hides (game/enemy/eye_glint.gd).
@export var glint: Node2D

var _next_spit_at: float = 0.0
var _clear_since: float = 0.0
var _aim: Vector2 = Vector2.DOWN
var _hurtbox_rest: Vector2 = Vector2.ZERO


func _ready() -> void:
	super()
	add_to_group(GroundShake.GROUP)
	if damage_area != null:
		_hurtbox_rest = damage_area.position
	_aim = _pipe_line()
	_hide(Services.now_ms(), false)


func _step_pattern(now: float, _delta: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	var close := engaged and centre.distance_to(slime) <= pattern("hideRangePx", 72.0)
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_HIDDEN:
			set_look(0.0)
			if close or not engaged:
				_clear_since = now
			elif now - _clear_since >= pattern("unhideMs", 500.0):
				_rise(now)
		PHASE_UP:
			var rise := clampf(elapsed / maxf(1.0, pattern("riseMs", 200.0)), 0.0, 1.0)
			var breath := sin(now / BREATH_MS) * BREATH
			set_look(0.0, Vector2(1.0 - breath, lerpf(RISE_SQUASH, 1.0, rise) + breath))
			if close or not engaged:
				_hide(now)
			elif now >= _next_spit_at and rise >= 1.0 and _crosses_line(centre, _aim_point(target)):
				_aim = _pipe_line()
				_transition(PHASE_CHARGE, now)
				_cue(CUE_CHARGE)
		PHASE_CHARGE:
			var t := clampf(elapsed / maxf(1.0, pattern("spitWindupMs", 550.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE * (1.0 + CHARGE_SWELL * t), sin(elapsed / CHARGE_SHAKE_MS) * CHARGE_SHAKE_RAD * t)
			if close or not engaged:
				_hide(now)
			elif t >= 1.0:
				_spit(now)
		PHASE_SPIT:
			set_look(0.0, Vector2(1.06, 0.96))
			if elapsed >= pattern("spitPoseMs", 300.0):
				_transition(PHASE_UP, now - pattern("riseMs", 200.0))
				set_frame(FRAME_UP)
		PHASE_DAZED:
			set_look(-FALLEN_POSE_PX, Vector2.ONE, sin(elapsed / DAZE_SWAY_MS) * DAZE_SWAY_RAD)
			if elapsed >= pattern("dazedMs", 2600.0):
				_cue(CUE_BACK)
				_hide(now, false)


## The line out of its pipe: `aim_direction` snapped to the nearest cardinal (down when unset).
func _pipe_line() -> Vector2:
	var line := FourWayAim.snap(aim_direction)
	return line if line != Vector2.ZERO else Vector2.DOWN


## True when `aim_at` (the slime's hurtbox middle) is in front of the pipe, within
## `alignTolerancePx` of its line.
func _crosses_line(centre: Vector2, aim_at: Vector2) -> bool:
	var line := _pipe_line()
	var offset := aim_at - centre
	return offset.dot(line) > 0.0 and absf(offset.cross(line)) <= pattern("alignTolerancePx", 16.0)


func _rise(now: float) -> void:
	_transition(PHASE_UP, now)
	set_frame(FRAME_UP)
	_show_worm_in_pipe(true)
	_show_glint(false)
	_next_spit_at = maxf(_next_spit_at, now + pattern("firstSpitMs", 400.0))
	_cue(CUE_RISE)


func _hide(now: float, sound: bool = true) -> void:
	_transition(PHASE_HIDDEN, now)
	set_frame(FRAME_HOLE)
	set_look(0.0)
	_show_worm_in_pipe(true)
	_clear_since = now
	_show_glint(true)
	if sound:
		_cue(CUE_HIDE)


func _spit(now: float) -> void:
	_transition(PHASE_SPIT, now)
	set_frame(FRAME_SPIT)
	_next_spit_at = now + pattern("spitIntervalMs", 1700.0)
	var config := _projectile_config()
	var mouth := get_centre() + _aim * MOUTH_PX
	if not config.is_empty():
		_attack_direction = _aim
		_fire_projectile(mouth, config)
	_cue(CUE_SPIT)
	_puff(MUD, mouth)


## The worm in its pipe (the Visual's pipe frames) or out on the floor (the Visual is the fallen
## worm, the empty pipe shows behind it and the hurtbox follows the worm).
func _show_worm_in_pipe(in_pipe: bool) -> void:
	if hole != null:
		hole.visible = not in_pipe
	if not in_pipe:
		_show_glint(false)
	if damage_area != null:
		damage_area.position = _hurtbox_rest + (Vector2.ZERO if in_pipe else Vector2(0.0, FALLEN_HURTBOX_PX))


func _show_glint(on: bool) -> void:
	if glint != null:
		glint.set(&"shown", on)


## A Roll's bonk against the wall under its pipe (any bonk, heavy or not) shakes it out.
func on_ground_shake(at: Vector2, _radius: float, _heavy: bool) -> void:
	if is_defeated() or _phase == PHASE_DAZED or feet().distance_to(at) > pattern("bonkReachPx", 60.0):
		return
	var now := Services.now_ms()
	_transition(PHASE_DAZED, now)
	set_frame(FRAME_DAZED)
	_show_worm_in_pipe(false)
	set_look(-FALLEN_POSE_PX)
	_cue(CUE_SHAKEN)
	_puff(MUD, feet())


## True while it lies out of its pipe, shaken out.
func is_shaken_out() -> bool:
	return _phase == PHASE_DAZED


## Blows never reach it in its pipe; shaken out it is open.
func _shields(_request: Dictionary) -> bool:
	return _phase != PHASE_DAZED


## Its own glob thrown back.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, GlobScript.GLOB_KIND)


## Rooted in its pipe: a knockback does not move it.
func _slides_when_stunned() -> bool:
	return false


func _defeat() -> void:
	if is_defeated():
		return
	_show_worm_in_pipe(false)
	super()
	set_look(-FALLEN_POSE_PX)
