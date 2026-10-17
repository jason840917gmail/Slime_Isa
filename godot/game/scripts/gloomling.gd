extends "res://game/enemy/patterned_enemy.gd"
class_name GloomlingScript
## Scene script `game.gloomling` (the bestiary's row 23, a shadow; docs/godot/BESTIARY.md
## "Gloomling"): a blob of living shadow that sits on something the slime wants (a key, a switch).
## It is the one enemy nothing hurts: it has no hurtbox and no solid body, so blows, throws and the
## flame pass through it. Only light moves it.
##
## - **Sit:** on its post, round and calm, half-closed eyes; in a dark room only its eyes show
##   (game/enemy/dark_eyes.gd).
## - **Flinch** (the tell, `flinchMs`): light reaches it (any light source, game/enemy/
##   light_sense.gd: the slime's ember in a dark room, a candle, a flame, a bomb): it squeezes tall
##   and its eyes go wide.
## - **Flee:** it scuttles straight away from the brightest light at `fleeSpeed` (`boltSpeed` for
##   `boltMs` after a Lantern flame's light touched it), shrinking as its dread grows: dread fills
##   while light is on it (all of it in `dreadMs`; a flame's light adds `flameDread` at once) and
##   drains out of the light (all of it in `recoverMs`); it is drawn from 1 down to `minScale`.
## - **Creep:** `calmMs` out of the light it creeps back to its post at `creepSpeed`, growing back.
## - **Chased off:** full dread, it breaks up into wisps and is gone (`_defeat`, nothing hurt it);
##   the pen brings it back.
## The flame of the Lantern is its right tool: the ember's glow makes it run, a puff makes it bolt.
##
## Owner: enemy builder.

const LightSense := preload("res://game/enemy/light_sense.gd")
const DarkEyes := preload("res://game/enemy/dark_eyes.gd")

const PHASE_SIT := "sit"
const PHASE_FLINCH := "flinch"
const PHASE_FLEE := "flee"
const PHASE_CREEP := "creep"
const FRAME_REST := 0
const FRAME_FLINCH := 1
const FRAME_SCUTTLE := 2
const FRAME_FADE := 3
const CUE_FLINCH := &"TalkBlip"
const CUE_BOLT := &"WebStruggle"
const CUE_GONE := &"GulpWearOff"
const WISPS := &"dodge-dust"
## Presentation: the smoke's breath and sway, the flinch's squeeze, the eyes (lilac, in the 256 px
## cell of each frame).
const BREATH := 0.05
const BREATH_MS := 380.0
const SWAY_RAD := 0.05
const SWAY_MS := 610.0
const FLINCH_SQUASH := Vector2(0.82, 1.18)
const SCUTTLE_WOBBLE := 0.08
const SCUTTLE_MS := 70.0
const EYE_COLOR := Color(0.86, 0.74, 1.0)
const EYES := {
	FRAME_REST: [Vector2(113, 203), Vector2(158, 196)],
	FRAME_FLINCH: [Vector2(119, 138), Vector2(155, 136)],
	FRAME_SCUTTLE: [Vector2(48, 212), Vector2(70, 220)],
	FRAME_FADE: [Vector2(70, 191), Vector2(92, 199)],
}

var _dread: float = 0.0
var _lit: float = 0.0
var _away_from: Vector2 = Vector2.INF
var _dark_since: float = 0.0
var _bolt_until: float = 0.0
var _flame_seen: bool = false
var _last_ms: float = -1.0
var _eyes: DarkEyes


func _ready() -> void:
	super()
	set_hurtbox(false)
	set_solid(false)
	_transition(PHASE_SIT, Services.now_ms())
	set_frame(FRAME_REST)
	if visual != null:
		_eyes = DarkEyes.new()
		_eyes.name = "DarkEyes"
		_eyes.color = EYE_COLOR
		_eyes.radius_px = 1.8
		_eyes.halo_px = 5.0
		for frame: int in EYES:
			_eyes.eyes[frame] = PackedVector2Array(EYES[frame])
		visual.add_child(_eyes)


## How full its dread is (0..1; at 1 it is chased off).
func get_dread() -> float:
	return _dread


func _step_pattern(now: float, delta: float, _target: Dictionary, _engaged: bool) -> void:
	var step_ms := now - _last_ms if _last_ms >= 0.0 else 0.0
	_last_ms = now
	_sense_light(now)
	if _lit > 0.0:
		_dread += step_ms / maxf(1.0, pattern("dreadMs", 2400.0))
		_dark_since = now
	else:
		_dread -= step_ms / maxf(1.0, pattern("recoverMs", 3000.0))
	_dread = clampf(_dread, 0.0, 1.0)
	if _dread >= 1.0:
		_chased_off()
		return
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_SIT:
			body.velocity = Vector2.ZERO
			set_frame(FRAME_REST)
			if _lit > 0.0:
				_flinch(now)
			elif get_centre().distance_to(_home) > pattern("homeSlackPx", 6.0):
				_transition(PHASE_CREEP, now)
		PHASE_FLINCH:
			body.velocity = Vector2.ZERO
			if elapsed >= pattern("flinchMs", 260.0):
				_transition(PHASE_FLEE, now)
				set_frame(FRAME_SCUTTLE)
		PHASE_FLEE:
			if _lit <= 0.0 and now - _dark_since >= pattern("calmMs", 600.0) and now >= _bolt_until:
				_transition(PHASE_CREEP, now)
				set_frame(FRAME_REST)
			else:
				var speed := pattern("boltSpeed", 240.0) if now < _bolt_until else pattern("fleeSpeed", 150.0)
				var away := get_centre() - _away_from if _away_from != Vector2.INF else Vector2.ZERO
				body.velocity = away.normalized() * speed if away.length() > 0.5 else Vector2.ZERO
				face_x(-body.velocity.x)
		PHASE_CREEP:
			if _lit > 0.0:
				_flinch(now)
			else:
				body.velocity = _velocity_toward(_home, pattern("creepSpeed", 40.0), delta)
				set_frame(FRAME_SCUTTLE if body.velocity.length() > WALK_SPEED_THRESHOLD else FRAME_REST)
				face_x(-body.velocity.x)
				if body.velocity == Vector2.ZERO:
					_transition(PHASE_SIT, now)
	_look(now)


## The light on it now: how strongly (`_lit`), where from (`_away_from`), and a flame's bolt.
func _sense_light(now: float) -> void:
	var tree := get_tree()
	var centre := get_centre()
	var pad := pattern("bodyRadiusPx", 18.0) * _scale()
	_lit = LightSense.light_at(tree, centre, pad)
	if _lit > 0.0:
		_away_from = LightSense.brightest_from(tree, centre, pad)
	var flame := LightSense.flame_at(tree, centre, pad)
	if flame and not _flame_seen:
		_dread = minf(1.0, _dread + pattern("flameDread", 0.4))
		_bolt_until = now + pattern("boltMs", 600.0)
		_cue(CUE_BOLT)
		if _phase != PHASE_FLEE:
			_transition(PHASE_FLEE, now)
			set_frame(FRAME_SCUTTLE)
	_flame_seen = flame


func _flinch(now: float) -> void:
	_transition(PHASE_FLINCH, now)
	set_frame(FRAME_FLINCH)
	body.velocity = Vector2.ZERO
	_cue(CUE_FLINCH)


func _chased_off() -> void:
	body.velocity = Vector2.ZERO
	_puff(WISPS, feet())
	_cue(CUE_GONE)
	_defeat()
	set_frame(FRAME_FADE)
	set_look(0.0, Vector2.ONE * pattern("minScale", 0.4))


## Its size by its dread, and the smoke's motion.
func _look(now: float) -> void:
	var size := _scale()
	var breath := sin(now / BREATH_MS) * BREATH
	var sway := sin(now / SWAY_MS) * SWAY_RAD
	match _phase:
		PHASE_FLINCH:
			set_look(0.0, FLINCH_SQUASH * size, 0.0)
		PHASE_FLEE, PHASE_CREEP:
			var wobble := sin(now / SCUTTLE_MS) * SCUTTLE_WOBBLE
			set_look(0.0, Vector2(size * (1.0 + wobble), size * (1.0 - wobble)), sway)
		_:
			set_look(0.0, Vector2(size * (1.0 + breath), size * (1.0 - breath)), sway)
	if _eyes != null:
		_eyes.strength = lerpf(1.0, 0.45, _dread)


func _scale() -> float:
	return lerpf(1.0, pattern("minScale", 0.4), _dread)


## Nothing reaches it: there is nothing to hit.
func _shields(_request: Dictionary) -> bool:
	return true


func _on_stunned(_now: float, _delta: float) -> void:
	body.velocity = Vector2.ZERO
