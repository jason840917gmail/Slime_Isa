extends "res://game/enemy/patterned_enemy.gd"
class_name BrambleBoarScript
## Scene script `game.bramble-boar` (the bestiary's row 8, a charger; docs/godot/BESTIARY.md
## "Bramble Boar"): a stocky boar wrapped in brambles.
##
## - **Idle:** it turns to face the slime; while the slime is away it walks home at `homeSpeed`.
## - **Scrape** (the tell, `scrapeMs`): once it sees the slime (a clear line, `scrapeCooldownMs`
##   after its last charge) it lowers its head and scrapes the ground, kicking dust back.
## - **Charge:** at the scrape's end it locks the line to the slime's centre and runs it at
##   `chargeSpeed` until it hits something. Its bramble front shrugs every hit off (a clink).
##   - The slime (within `chargeHitPx`): `chargeDamage` with `chargeKnockback`, and the boar skids
##     to a stop (`skidMs`).
##   - Anything else that stops it (a wall, a rock, the pen's fence, another enemy): it bounces
##     off onto its back, **stunned** for `stunMs`, its soft belly up: every hit there deals
##     `stunnedDamageTaken` times its damage (the reaction profile's `states.stunned`; old-style
##     hits here). The right tool: Roll aside and let it hit the wall.
##   - After `chargeMaxMs` without a hit it skids to a stop.
## A hit that stuns it during the scrape cancels the charge.
##
## Owner: enemy builder.

const PHASE_IDLE := "idle"
const PHASE_SCRAPE := "scrape"
const PHASE_CHARGE := "charge"
const PHASE_SKID := "skid"
const PHASE_STUNNED := "stunned"
const FRAME_STAND := 0
const FRAME_SCRAPE := 1
const FRAME_CHARGE := 2
const FRAME_STUNNED := 3
## Its own wind-up sound (Sound Picker round 13, 2026-11-21; it played the slime's SlamWindup before).
const CUE_SCRAPE := &"BoarScrape"
const CUE_CHARGE := &"RollLaunch"
const CUE_CRASH := &"RollBonk"
const CUE_GET_UP := &"Land"
const DUST := &"dodge-dust"
const SPARKS := &"hit-spark"
## A blocked charge: the mover left less than this share of the asked speed.
const BLOCKED_SHARE := 0.5
## Presentation: the scrape's dust, the charge's dust trail, the waddle, the crash's bounce.
const SCRAPE_DUST_MS := 150.0
const TRAIL_DUST_MS := 90.0
const WADDLE_RAD := 0.05
const WADDLE_MS := 120.0
const CHARGE_BOB_PX := 2.5
const CHARGE_BOB_MS := 45.0
const CRASH_BOUNCE_PX := 14.0
const CRASH_BOUNCE_MS := 260.0
const DAZE_SWAY_RAD := 0.06
const DAZE_SWAY_MS := 200.0

var _dir: Vector2 = Vector2.RIGHT
var _asked: Vector2 = Vector2.ZERO
var _ready_at: float = 0.0
var _dust_at: float = 0.0


func _ready() -> void:
	super()
	_idle(Services.now_ms())


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_IDLE:
			if engaged:
				body.velocity = Vector2.ZERO
				face_x(slime.x - centre.x)
				set_look(0.0)
				if now >= _ready_at and _sees(target):
					_transition(PHASE_SCRAPE, now)
					set_frame(FRAME_SCRAPE)
					_cue(CUE_SCRAPE)
			else:
				body.velocity = _velocity_home(pattern("homeSpeed", 50.0), delta)
				face_x(body.velocity.x)
				var walking := body.velocity.length() > WALK_SPEED_THRESHOLD
				if show_walk(delta, FRAME_STAND):
					set_look(0.0)
				else:
					set_look(0.0, Vector2.ONE, sin(now / WADDLE_MS) * WADDLE_RAD if walking else 0.0)
		PHASE_SCRAPE:
			body.velocity = Vector2.ZERO
			face_x(slime.x - centre.x)
			set_look(0.0, Vector2(1.04, 0.96), -0.06 if not visual.flip_h else 0.06)
			if now >= _dust_at:
				_dust_at = now + SCRAPE_DUST_MS
				var behind := -1.0 if not visual.flip_h else 1.0
				_puff(DUST, feet() + Vector2(behind * 14.0, 0.0))
			if not engaged:
				_idle(now)
			elif elapsed >= pattern("scrapeMs", 900.0):
				_dir = (slime - centre).normalized() if slime != centre else Vector2.RIGHT
				_transition(PHASE_CHARGE, now)
				set_frame(FRAME_CHARGE)
				face_x(_dir.x)
				_asked = Vector2.ZERO
				_cue(CUE_CHARGE)
		PHASE_CHARGE:
			# The last move: did something stop it?
			var blocked := _asked != Vector2.ZERO and body.velocity.length() < _asked.length() * BLOCKED_SHARE
			if engaged and _contact(target, pattern("chargeDamage", 10.0), pattern("chargeKnockback", 340.0),
					pattern("chargeHitPx", 44.0)):
				_skid(now)
				return
			if blocked:
				if centre.distance_to(slime) <= pattern("chargeHitPx", 44.0) + pattern("slimeBlockSlackPx", 14.0):
					_skid(now)
				else:
					_crash(now)
				return
			if elapsed >= pattern("chargeMaxMs", 2500.0):
				_skid(now)
				return
			_asked = _dir * pattern("chargeSpeed", 300.0)
			body.velocity = _asked
			set_look(absf(sin(now / CHARGE_BOB_MS)) * CHARGE_BOB_PX)
			if now >= _dust_at:
				_dust_at = now + TRAIL_DUST_MS
				_puff(DUST, feet() - _dir * 18.0)
		PHASE_SKID:
			var t := clampf(elapsed / maxf(1.0, pattern("skidMs", 350.0)), 0.0, 1.0)
			body.velocity = _dir * pattern("chargeSpeed", 300.0) * 0.5 * (1.0 - t)
			set_look(0.0, Vector2.ONE, (0.08 if not visual.flip_h else -0.08) * (1.0 - t))
			if t >= 1.0:
				_idle(now)
		PHASE_STUNNED:
			body.velocity = Vector2.ZERO
			var bounce := clampf(elapsed / CRASH_BOUNCE_MS, 0.0, 1.0)
			set_look(sin(bounce * PI) * CRASH_BOUNCE_PX, Vector2.ONE, sin(elapsed / DAZE_SWAY_MS) * DAZE_SWAY_RAD)
			if elapsed >= pattern("stunMs", 2200.0):
				_cue(CUE_GET_UP)
				_idle(now)


func _idle(now: float) -> void:
	_transition(PHASE_IDLE, now)
	set_frame(FRAME_STAND)
	set_look(0.0)
	_asked = Vector2.ZERO


func _skid(now: float) -> void:
	_transition(PHASE_SKID, now)
	set_frame(FRAME_STAND)
	_asked = Vector2.ZERO
	_ready_at = now + pattern("skidMs", 350.0) + pattern("scrapeCooldownMs", 900.0)


## It ran into something: on its back, stunned, its soft belly up.
func _crash(now: float) -> void:
	body.velocity = Vector2.ZERO
	_asked = Vector2.ZERO
	_transition(PHASE_STUNNED, now)
	set_frame(FRAME_STUNNED)
	_ready_at = now + pattern("stunMs", 2200.0) + pattern("scrapeCooldownMs", 900.0)
	_cue(CUE_CRASH)
	_puff(SPARKS, get_centre() + _dir * 20.0)
	_puff(DUST, feet() + _dir * 16.0)
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("crashShakeMs", 140.0), pattern("crashShakeIntensity", 0.004))


## A clear line to the slime (walls block it, water does not).
func _sees(target: Dictionary) -> bool:
	var world := Services.world()
	if world == null:
		return true
	var exclude: Array[RID] = [body.get_rid()]
	var player_body := target.get("body") as CollisionObject2D
	if player_body != null:
		exclude.append(player_body.get_rid())
	return world.line_of_sight(get_centre(), target.get("centre", get_centre()), exclude)


## A stun in the scrape cancels the charge.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_SCRAPE:
		_idle(now)
		_ready_at = get_hit_stun_until() + pattern("scrapeCooldownMs", 900.0)


## True while it lies on its back (open, every hit doubled).
func is_stunned_on_back() -> bool:
	return _phase == PHASE_STUNNED


func _shields(_request: Dictionary) -> bool:
	return _phase == PHASE_CHARGE


## Old-style hits (the Roll's bonk, the classic game) on its belly: `stunnedDamageTaken` times; a
## rework hit gets it from the reaction profile's `states.stunned.damageTaken`.
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	if _phase == PHASE_STUNNED and not ReworkMode.is_rework_request(input.get("request", {})):
		damage *= pattern("stunnedDamageTaken", 2.0)
	return damage
