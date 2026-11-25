extends "res://game/enemy/patterned_enemy.gd"
class_name GloomlingScript
## Scene script `game.gloomling` (the bestiary's row 23, a shadow; docs/godot/BESTIARY.md
## "Gloomling"): a blob of living shadow that sits on something the slime wants (a key, a switch).
## It is the one enemy nothing hurts: it has no hurtbox and no solid body, so blows, throws and the
## flame pass through it. Only light moves it: it runs from every light, and in full darkness it
## comes for the slime and hurts it on contact (owner, 2026-11-13).
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
## - **Rise** (the tell, `huntTellMs`): full darkness (`_full_dark`: no light on it, no light on
##   the slime, both in a dark room that is still dark, the slime in its arena): it swells and its
##   eyes turn red.
## - **Hunt:** it comes straight for the slime at `huntSpeed`; touching it (`contactReachPx`, at
##   most every `contactCooldownMs`) it bites for `contactDamage` with `contactKnockback`, then
##   holds still for `biteRestMs`. Any light on it makes it flinch and flee as ever; light on the
##   slime (its ember, a candle it stands by, a bomb) or the slime out of the dark calls the hunt
##   off and it creeps home.
## - **Chased off:** full dread, it breaks up into wisps and is gone (`_defeat`, nothing hurt it);
##   the pen brings it back.
## The flame of the Lantern is its right tool: the ember's glow makes it run, a puff makes it bolt.
## Without a light the slime can only keep away from it (it is slower than the slime).
##
## Owner: enemy builder.

const LightSense := preload("res://game/enemy/light_sense.gd")
const DarkEyes := preload("res://game/enemy/dark_eyes.gd")

const PHASE_SIT := "sit"
const PHASE_FLINCH := "flinch"
const PHASE_FLEE := "flee"
const PHASE_CREEP := "creep"
const PHASE_RISE := "rise"
const PHASE_HUNT := "hunt"
const FRAME_REST := 0
const FRAME_FLINCH := 1
const FRAME_SCUTTLE := 2
const FRAME_FADE := 3
## candle.gd SMOTHER_GROUP, and how near its feet must be to a candle's foot to smother it.
const SMOTHER_GROUP := &"candle_smotherers"
const SMOTHER_RADIUS_PX := 40.0
const CUE_FLINCH := &"TalkBlip"
const CUE_BOLT := &"WebStruggle"
const CUE_GONE := &"GulpWearOff"
## Stand-ins until the owner picks its own in the Sound Picker (docs/TOOLING.md).
const CUE_RISE := &"GroundCreak"
const CUE_BITE := &"HitDull"
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
const EYE_RADIUS_PX := 1.8
const EYE_HALO_PX := 5.0
## The hunt's look: red, larger, narrowed eyes, and the smoke swollen.
const HUNT_EYE_COLOR := Color(1.0, 0.24, 0.2)
const HUNT_EYE_RADIUS_PX := 2.6
const HUNT_EYE_HALO_PX := 8.0
const HUNT_EYE_SQUINT := 0.62
const HUNT_SWELL := 1.15
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
## After a bite it holds still until then.
var _rest_until: float = 0.0
## 0 calm .. 1 hunting: the eyes' red and the smoke's swell.
var _heat: float = 0.0
var _eyes: DarkEyes


func _ready() -> void:
	super()
	add_to_group(SMOTHER_GROUP)
	set_hurtbox(false)
	set_solid(false)
	_transition(PHASE_SIT, Services.now_ms())
	set_frame(FRAME_REST)
	if visual != null:
		_eyes = DarkEyes.new()
		_eyes.name = "DarkEyes"
		_eyes.color = EYE_COLOR
		_eyes.radius_px = EYE_RADIUS_PX
		_eyes.halo_px = EYE_HALO_PX
		for frame: int in EYES:
			_eyes.eyes[frame] = PackedVector2Array(EYES[frame])
		visual.add_child(_eyes)


## How full its dread is (0..1; at 1 it is chased off).
func get_dread() -> float:
	return _dread


## A candle at `point` (its foot) is smothered while this shadow sits on it (candle.gd
## SMOTHER_GROUP; the Crystal Mine's dark maze: drive it off with light first, then light the candle).
func smothers(point: Vector2) -> bool:
	if is_defeated() or body == null:
		return false
	return body.global_position.distance_to(point) <= SMOTHER_RADIUS_PX


## True while it hunts or rises to (its eyes are red).
func is_hunting() -> bool:
	return _phase == PHASE_HUNT or _phase == PHASE_RISE


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
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
	var dark := _full_dark(target, engaged)
	match _phase:
		PHASE_SIT:
			body.velocity = Vector2.ZERO
			set_frame(FRAME_REST)
			if _lit > 0.0:
				_flinch(now)
			elif dark:
				_rise(now)
			elif get_centre().distance_to(_home) > pattern("homeSlackPx", 6.0):
				_transition(PHASE_CREEP, now)
		PHASE_RISE:
			body.velocity = Vector2.ZERO
			if _lit > 0.0:
				_flinch(now)
			elif not dark:
				_transition(PHASE_CREEP, now)
			elif elapsed >= pattern("huntTellMs", 450.0):
				_transition(PHASE_HUNT, now)
				set_frame(FRAME_SCUTTLE)
		PHASE_HUNT:
			if _lit > 0.0:
				_flinch(now)
			elif not dark:
				body.velocity = Vector2.ZERO
				_transition(PHASE_CREEP, now)
				set_frame(FRAME_REST)
			elif now < _rest_until:
				body.velocity = Vector2.ZERO
			else:
				var slime: Vector2 = target.get("centre", get_centre())
				body.velocity = _velocity_toward(slime, pattern("huntSpeed", 110.0), delta)
				face_x(-body.velocity.x)
				if _contact(target, pattern("contactDamage", 20.0), pattern("contactKnockback", 180.0),
						pattern("contactReachPx", 26.0)):
					_rest_until = now + pattern("biteRestMs", 500.0)
					body.velocity = Vector2.ZERO
					_cue(CUE_BITE)
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
			elif dark:
				_rise(now)
			else:
				body.velocity = _velocity_home(pattern("creepSpeed", 40.0), delta)
				set_frame(FRAME_SCUTTLE if body.velocity.length() > WALK_SPEED_THRESHOLD else FRAME_REST)
				face_x(-body.velocity.x)
				if body.velocity == Vector2.ZERO:
					_transition(PHASE_SIT, now)
	_look(now, step_ms)


## Full darkness, where it hunts: no light on it, the slime a live target in its arena with no light
## on it either (its ember, a candle's or a bomb's light it stands in), and both of them in a dark
## room that is still dark (game/enemy/light_sense.gd `dark_at`).
func _full_dark(target: Dictionary, engaged: bool) -> bool:
	if not engaged or _lit > 0.0:
		return false
	var tree := get_tree()
	var slime: Vector2 = target.get("centre", Vector2.INF)
	if slime == Vector2.INF or not LightSense.dark_at(tree, get_centre()) or not LightSense.dark_at(tree, slime):
		return false
	return LightSense.light_at(tree, slime) <= 0.0


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


## The hunt's tell: it swells and its eyes turn red (`_look`).
func _rise(now: float) -> void:
	_transition(PHASE_RISE, now)
	set_frame(FRAME_REST)
	body.velocity = Vector2.ZERO
	_cue(CUE_RISE)


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


## Its size by its dread, the smoke's motion, and the hunt's heat in its eyes.
func _look(now: float, step_ms: float) -> void:
	_heat = move_toward(_heat, 1.0 if is_hunting() else 0.0, step_ms / maxf(1.0, pattern("huntTellMs", 450.0)))
	var size := _scale() * lerpf(1.0, HUNT_SWELL, _heat)
	var breath := sin(now / BREATH_MS) * BREATH
	var sway := sin(now / SWAY_MS) * SWAY_RAD
	match _phase:
		PHASE_FLINCH:
			set_look(0.0, FLINCH_SQUASH * size, 0.0)
		PHASE_FLEE, PHASE_CREEP, PHASE_HUNT:
			var wobble := sin(now / SCUTTLE_MS) * SCUTTLE_WOBBLE
			set_look(0.0, Vector2(size * (1.0 + wobble), size * (1.0 - wobble)), sway)
		_:
			set_look(0.0, Vector2(size * (1.0 + breath), size * (1.0 - breath)), sway)
	if _eyes != null:
		_eyes.strength = lerpf(1.0, 0.45, _dread)
		_eyes.radius_px = lerpf(EYE_RADIUS_PX, HUNT_EYE_RADIUS_PX, _heat)
		_eyes.halo_px = lerpf(EYE_HALO_PX, HUNT_EYE_HALO_PX, _heat)
		_eyes.color = EYE_COLOR.lerp(HUNT_EYE_COLOR, _heat)
		_eyes.squint = lerpf(1.0, HUNT_EYE_SQUINT, _heat)


func _scale() -> float:
	return lerpf(1.0, pattern("minScale", 0.4), _dread)


## Nothing reaches it: there is nothing to hit.
func _shields(_request: Dictionary) -> bool:
	return true


func _on_stunned(_now: float, _delta: float) -> void:
	body.velocity = Vector2.ZERO
