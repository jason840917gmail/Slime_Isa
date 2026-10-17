extends "res://game/enemy/patterned_enemy.gd"
class_name SpitcapScript
## Scene script `game.spitcap` (the bestiary's row 6, a turret; docs/godot/BESTIARY.md "Spitcap"):
## a toadstool rooted to the spot.
##
## - **Hidden:** its cap pulled down to the ground, a shell: every hit clinks but the seed thrown
##   back. It hides while the slime is within `hideRangePx` (and while the slime is away), and
##   comes up `unhideMs` after the slime has stepped back out of that range.
## - **Up** (popping up over `riseMs`): it turns to the slime's nearer axis (the cardinal nearest
##   to it, game/enemy/four_way_aim.gd) and spits on a steady beat, every `spitIntervalMs`, but only
##   along a line: four-way (owner, 2026-10-16), it waits until the slime is lined up, its hurtbox
##   middle within `alignTolerancePx` of the Spitcap's row or column.
## - **Charge** (the tell, `spitWindupMs`): it swells and shakes, its aim locked along that line at
##   the start; then it spits a spore seed (`projectile.spore-seed`, game/scripts/spore_seed.gd: the
##   scene's `projectile` and `attributes.projectileSpeed`) straight down the line (a slime that
##   stepped off it is missed) and shows its spitting pose for `spitPoseMs`. The slime coming close
##   cancels the charge (it hides).
## - **The right tool:** the Gulp catches the seed in flight (it is suckable) and throws it back: a
##   hit tagged `spore-seed` kills the Spitcap at once, even hidden (`_kill_hit`). The Spear reaches
##   it from just outside its hiding range (the jab's line is 110 px from the slime's centre).
##
## Owner: enemy builder.

const SeedScript := preload("res://game/scripts/spore_seed.gd")
const FourWayAim := preload("res://game/enemy/four_way_aim.gd")

const PHASE_HIDDEN := "hidden"
const PHASE_UP := "up"
const PHASE_CHARGE := "charge"
const PHASE_SPIT := "spit"
const FRAME_HIDDEN := 0
const FRAME_UP := 1
const FRAME_SPIT := 2
const CUE_RISE := &"DropPop"
const CUE_HIDE := &"HitBlocked"
const CUE_CHARGE := &"SpitcapCharge"
const CUE_SPIT := &"SpitcapSpit"
const SPORES := &"slime-splash"
## Presentation: the pop up, the charge's swell and shake, the breath while up.
const RISE_SQUASH := 0.55
const CHARGE_SWELL := 0.16
const CHARGE_SHAKE_RAD := 0.05
const CHARGE_SHAKE_MS := 35.0
const BREATH := 0.03
const BREATH_MS := 420.0
## The seed leaves this far along the aim from the centre.
const MOUTH_PX := 16.0

var _next_spit_at: float = 0.0
var _clear_since: float = 0.0
var _aim: Vector2 = Vector2.DOWN


func _ready() -> void:
	super()
	_hide(Services.now_ms(), false)


func _step_pattern(now: float, _delta: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	var close := engaged and centre.distance_to(slime) <= pattern("hideRangePx", 88.0)
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_HIDDEN:
			set_look(0.0)
			if close or not engaged:
				_clear_since = now
			elif now - _clear_since >= pattern("unhideMs", 600.0):
				_rise(now)
		PHASE_UP:
			var rise := clampf(elapsed / maxf(1.0, pattern("riseMs", 180.0)), 0.0, 1.0)
			var breath := sin(now / BREATH_MS) * BREATH
			set_look(0.0, Vector2(1.0 - breath, lerpf(RISE_SQUASH, 1.0, rise) + breath))
			# Four-way: it faces the slime's nearer axis and spits only along a line it shares.
			var aim_at := _aim_point(target)
			var nearer := FourWayAim.snap(aim_at - centre)
			if nearer != Vector2.ZERO:
				_aim = nearer
			face_x(_aim.x)
			var line := FourWayAim.line_direction(centre, aim_at, pattern("alignTolerancePx", 16.0))
			if close or not engaged:
				_hide(now)
			elif now >= _next_spit_at and rise >= 1.0 and line != Vector2.ZERO:
				_aim = line
				_transition(PHASE_CHARGE, now)
				_cue(CUE_CHARGE)
		PHASE_CHARGE:
			var t := clampf(elapsed / maxf(1.0, pattern("spitWindupMs", 520.0)), 0.0, 1.0)
			set_look(0.0, Vector2.ONE * (1.0 + CHARGE_SWELL * t), sin(elapsed / CHARGE_SHAKE_MS) * CHARGE_SHAKE_RAD * t)
			if close or not engaged:
				_hide(now)
			elif t >= 1.0:
				_spit(now)
		PHASE_SPIT:
			set_look(0.0, Vector2(1.08, 0.94))
			if elapsed >= pattern("spitPoseMs", 260.0):
				_transition(PHASE_UP, now - pattern("riseMs", 180.0))
				set_frame(FRAME_UP)


func _rise(now: float) -> void:
	_transition(PHASE_UP, now)
	set_frame(FRAME_UP)
	_next_spit_at = maxf(_next_spit_at, now + pattern("firstSpitMs", 500.0))
	_cue(CUE_RISE)


func _hide(now: float, sound: bool = true) -> void:
	_transition(PHASE_HIDDEN, now)
	set_frame(FRAME_HIDDEN)
	set_look(0.0)
	_clear_since = now
	if sound:
		_cue(CUE_HIDE)


func _spit(now: float) -> void:
	_transition(PHASE_SPIT, now)
	set_frame(FRAME_SPIT)
	face_x(_aim.x)
	_next_spit_at = now + pattern("spitIntervalMs", 1800.0)
	var config := _projectile_config()
	if not config.is_empty():
		_attack_direction = _aim
		_fire_projectile(get_centre() + _aim * MOUTH_PX, config)
	_cue(CUE_SPIT)
	_puff(SPORES, get_centre() + _aim * MOUTH_PX)


## A hit that stuns it cancels the charge, as every stun cancels an enemy's shot (the reactions'
## rule); the beat starts again after the stun.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_CHARGE:
		_transition(PHASE_UP, now - pattern("riseMs", 180.0))
		set_frame(FRAME_UP)
		set_look(0.0)
		_next_spit_at = get_hit_stun_until() + pattern("spitIntervalMs", 1800.0) * 0.5


func _shields(_request: Dictionary) -> bool:
	return _phase == PHASE_HIDDEN


## Its own seed thrown back.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, SeedScript.KIND)


## Rooted: a knockback does not move it.
func _slides_when_stunned() -> bool:
	return false
