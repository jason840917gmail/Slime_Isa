extends "res://game/enemy/patterned_enemy.gd"
class_name RookThiefScript
## Scene script `game.rook-thief` (the bestiary's row 10, a thief; docs/godot/BESTIARY.md "Rook
## Thief"): a rook in a red scarf that flies a fixed loop round its home and robs the slime.
##
## It flies: its body is neither solid nor stopped by anything (layer and mask 0), its root is the
## ground point under it (its shadow) and its art and hurtbox ride `height` above it.
## - **Loop:** round its home on an ellipse (`loopRadiusX` x `loopRadiusY`) at `loopSpeed`,
##   `flyHeightPx` up, out of reach (no hurtbox).
## - **Tell** (`tellMs`): `swoopEveryMs` after its last swoop, while the slime is in reach of the
##   loop, it caws, folds its wings and its shadow darkens, still on the loop.
## - **Swoop** (`swoopMs`): a straight dive from the loop through the point where the slime stood
##   at the tell's end, on `swoopOvershootPx`, down to `swoopLowPx` at its middle. While it is
##   under `lowHeightPx` it can be hit. Touching the slime there (the ground points within
##   `stealRadiusPx`) it steals `stealCoins` coins (as many as the slime has) and flies off with the
##   pouch, higher (`carryHeightPx`), for `carryMs` before it swoops again; it keeps what it took.
## - **Rise** (`riseMs`): back up to its loop.
## - **Knocked down** (`fallMs`, then `downMs` on the ground, open): a thrown thing that hits it
##   (a pot thrown as it swoops low; tag `thrown`), or the Bow's arrow (`on_arrow_hit`, the hook
##   for the coming Bow: any height). It drops every coin it took (they go back to the slime) and
##   then flies back up. Other hits only hurt it; a Spear jab as it swoops past can beat it too.
## Defeated, it drops what it took as well.
##
## Owner: enemy builder.

const PHASE_LOOP := "loop"
const PHASE_TELL := "tell"
const PHASE_SWOOP := "swoop"
const PHASE_RISE := "rise"
const PHASE_DOWN := "down"
const FRAME_GLIDE := 0
const FRAME_SWOOP := 1
const FRAME_AWAY := 2
const FRAME_DOWN := 3
## The Bow's future targets: `on_arrow_hit(hit: Dictionary) -> bool`.
const BOW_TARGETS := &"bow_targets"
const CUE_CAW := &"NpcBlip"
const CUE_SWOOP := &"Lash"
const CUE_STEAL := &"RookSteal"
const CUE_KNOCKED := &"RollBonk"
const FEATHERS := &"dodge-dust"
## Presentation: the wing flap's bob, the shadow by height, the hurtbox over the art's middle.
const FLAP_PX := 3.0
const FLAP_MS := 110.0
const SHADOW_SIZE := Vector2(24.0, 8.0)
const HURTBOX_RISE_PX := 10.0

var _home_feet: Vector2 = Vector2.INF
var _angle: float = 0.0
var _height: float = 0.0
var _carried: int = 0
var _carry_until: float = 0.0
var _next_swoop_at: float = 0.0
var _swoop_from: Vector2 = Vector2.ZERO
var _swoop_to: Vector2 = Vector2.ZERO
var _rise_from: Vector2 = Vector2.ZERO
var _rise_height: float = 0.0
var _stole_this_swoop: bool = false


func _ready() -> void:
	super()
	add_to_group(BOW_TARGETS)
	_height = pattern("flyHeightPx", 90.0)
	_transition(PHASE_LOOP, Services.now_ms())
	_next_swoop_at = Services.now_ms() + pattern("firstSwoopMs", 1200.0)
	set_hurtbox(false)
	set_frame(FRAME_GLIDE)


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	if _home_feet == Vector2.INF:
		_home_feet = feet()
		_angle = 0.0
	var elapsed := _elapsed(now)
	var carrying := now < _carry_until
	match _phase:
		PHASE_LOOP, PHASE_TELL:
			var speed := pattern("loopSpeed", 150.0) * (pattern("carrySpeedScale", 1.4) if carrying else 1.0)
			_angle = wrapf(_angle + speed / maxf(1.0, _mean_radius()) * delta, 0.0, TAU)
			var cruise := pattern("carryHeightPx", 130.0) if carrying else pattern("flyHeightPx", 90.0)
			_height = move_toward(_height, cruise, pattern("climbSpeed", 120.0) * delta)
			_fly_to(_loop_point(_angle), delta)
			if _phase == PHASE_LOOP:
				set_frame(FRAME_AWAY if _carried > 0 else FRAME_GLIDE)
				_set_shadow(0.0)
				if engaged and not carrying and now >= _next_swoop_at and _in_reach(target):
					_transition(PHASE_TELL, now)
					set_frame(FRAME_SWOOP)
					_cue(CUE_CAW)
			else:
				_set_shadow(clampf(elapsed / maxf(1.0, pattern("tellMs", 650.0)), 0.0, 1.0))
				if not engaged:
					_transition(PHASE_LOOP, now)
				elif elapsed >= pattern("tellMs", 650.0):
					_begin_swoop(now, target)
		PHASE_SWOOP:
			var t := clampf(elapsed / maxf(1.0, pattern("swoopMs", 900.0)), 0.0, 1.0)
			var fly := pattern("flyHeightPx", 90.0)
			_height = lerpf(fly, pattern("swoopLowPx", 12.0), sin(PI * t))
			_fly_to(_swoop_from.lerp(_swoop_to, t), delta)
			_set_shadow(1.0)
			var low := _height <= pattern("lowHeightPx", 34.0)
			set_hurtbox(low)
			if low and engaged and not _stole_this_swoop:
				_try_steal(now, target)
			if t >= 1.0:
				_begin_rise(now)
		PHASE_RISE:
			var t := clampf(elapsed / maxf(1.0, pattern("riseMs", 700.0)), 0.0, 1.0)
			var cruise := pattern("carryHeightPx", 130.0) if carrying else pattern("flyHeightPx", 90.0)
			_height = lerpf(_rise_height, cruise, t)
			set_hurtbox(_height <= pattern("lowHeightPx", 34.0))
			_fly_to(_rise_from.lerp(_loop_point(_angle), t), delta)
			_set_shadow(1.0 - t)
			if t >= 1.0:
				_transition(PHASE_LOOP, now)
		PHASE_DOWN:
			body.velocity = Vector2.ZERO
			var fall := clampf(elapsed / maxf(1.0, pattern("fallMs", 250.0)), 0.0, 1.0)
			_height = lerpf(_rise_height, 0.0, fall)
			if elapsed >= pattern("fallMs", 250.0) + pattern("downMs", 2200.0):
				_begin_rise(now)
	_place_art(now)


## Knocks it to the ground (a thrown thing, the Bow): it drops what it took. False when it is
## already down or defeated.
func knock_down() -> bool:
	if is_defeated() or _phase == PHASE_DOWN:
		return false
	var now := Services.now_ms()
	_rise_height = _height
	_transition(PHASE_DOWN, now)
	set_frame(FRAME_DOWN)
	set_hurtbox(true)
	_cue(CUE_KNOCKED)
	_puff(FEATHERS, feet())
	_drop_coins()
	_carry_until = 0.0
	_next_swoop_at = now + pattern("fallMs", 250.0) + pattern("downMs", 2200.0) + pattern("swoopEveryMs", 2600.0)
	return true


## The Bow's hook (the coming Bow, Chapter 3): an arrow knocks it down from any height. `hit` is the
## arrow's hit (unused yet). True when it fell.
func on_arrow_hit(_hit: Dictionary) -> bool:
	return knock_down()


## The coins it carries (stolen and not dropped yet).
func carried_coins() -> int:
	return _carried


func is_low() -> bool:
	return _height <= pattern("lowHeightPx", 34.0)


func get_height() -> float:
	return _height


## A thrown thing that reaches it knocks it down.
func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if not is_defeated() and has_tag(commit.get("request", {}), THROWN_TAG):
		knock_down()


func _begin_swoop(now: float, target: Dictionary) -> void:
	_transition(PHASE_SWOOP, now)
	set_frame(FRAME_SWOOP)
	_stole_this_swoop = false
	_swoop_from = feet()
	var slime_body := target.get("body") as Node2D
	var aim: Vector2 = slime_body.global_position if slime_body != null else _home_feet
	var line := aim - _swoop_from
	var unit := line.normalized() if line.length() > 0.0 else Vector2.DOWN
	_swoop_to = aim + unit * pattern("swoopOvershootPx", 140.0)
	face_x(unit.x)
	_cue(CUE_SWOOP)


func _begin_rise(now: float) -> void:
	_rise_from = feet()
	_rise_height = _height
	# Back onto the loop at the point nearest where it is.
	var offset := _rise_from - _home_feet
	_angle = atan2(offset.y / maxf(1.0, pattern("loopRadiusY", 120.0)), offset.x / maxf(1.0, pattern("loopRadiusX", 170.0)))
	_transition(PHASE_RISE, now)
	set_frame(FRAME_AWAY if _carried > 0 else FRAME_GLIDE)
	_next_swoop_at = maxf(_next_swoop_at, now + pattern("riseMs", 700.0) + pattern("swoopEveryMs", 2600.0))


func _try_steal(now: float, target: Dictionary) -> void:
	var slime_body := target.get("body") as Node2D
	if slime_body == null or feet().distance_to(slime_body.global_position) > pattern("stealRadiusPx", 28.0):
		return
	_stole_this_swoop = true
	var run := Services.run()
	var have: int = run.coins() if run != null else 0
	var take := mini(have, int(pattern("stealCoins", 5.0)))
	var feel := Services.feel()
	if take > 0:
		run.add_coins(-take)
		_carried += take
		if feel != null:
			feel.floating_text(get_centre() - Vector2(0.0, _height + 12.0), "-%dc" % take, &"red", false)
	_cue(CUE_STEAL)
	_carry_until = now + pattern("carryMs", 3200.0)
	set_frame(FRAME_AWAY)


## The stolen coins go back to the slime ("+Nc" over the rook).
func _drop_coins() -> void:
	if _carried <= 0:
		return
	var run := Services.run()
	if run != null:
		run.add_coins(_carried)
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(get_centre() - Vector2(0.0, 20.0), "+%dc" % _carried, &"yellow", false)
	_carried = 0


## The slime is close enough to the loop to be swooped at.
func _in_reach(target: Dictionary) -> bool:
	var slime_body := target.get("body") as Node2D
	if slime_body == null:
		return false
	return slime_body.global_position.distance_to(_home_feet) <= _mean_radius() + pattern("swoopReachPx", 160.0)


func _loop_point(angle: float) -> Vector2:
	return _home_feet + Vector2(cos(angle) * pattern("loopRadiusX", 170.0), sin(angle) * pattern("loopRadiusY", 120.0))


func _mean_radius() -> float:
	return (pattern("loopRadiusX", 170.0) + pattern("loopRadiusY", 120.0)) * 0.5


## Velocity that puts the ground point on `point` this step (it flies through everything).
func _fly_to(point: Vector2, delta: float) -> void:
	var step := maxf(delta, 0.0001)
	var velocity := (point - feet()) / step
	if absf(velocity.x) > WALK_SPEED_THRESHOLD:
		face_x(velocity.x)
	body.velocity = velocity


## The art and the hurtbox at `height`, the wings' bob while it flies.
func _place_art(now: float) -> void:
	var flap := sin(now / FLAP_MS) * FLAP_PX if _phase != PHASE_DOWN else 0.0
	set_look(_height + flap)
	if damage_area != null:
		damage_area.position = Vector2(0.0, -_height - HURTBOX_RISE_PX)
	var shadow := ground_shadow()
	if shadow != null:
		var near := 1.0 - clampf(_height / maxf(1.0, pattern("carryHeightPx", 130.0)), 0.0, 1.0)
		shadow.size = SHADOW_SIZE * lerpf(0.6, 1.0, near)


func _set_shadow(tell: float) -> void:
	var shadow := ground_shadow()
	if shadow != null:
		shadow.strength = lerpf(0.55, 1.0, tell)


## It flies: a stun holds it where it is.
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(now: float, _delta: float) -> void:
	_place_art(now)


func _defeat() -> void:
	if is_defeated():
		return
	_drop_coins()
	_height = 0.0
	if damage_area != null:
		damage_area.position = Vector2(0.0, -HURTBOX_RISE_PX)
	super()
