extends "res://game/enemy/patterned_enemy.gd"
class_name GlintBatScript
## Scene script `game.glint-bat` (the bestiary's row 24, a flyer; docs/godot/BESTIARY.md "Glint
## Bat"): a cave bat of the dark. While its room is not fully lit it wakes and swoops at the slime;
## once the room is fully lit (its dark room's candles all lit) it sleeps. It belongs only in rooms
## with the dark mechanic (owner, 2026-10-23).
##
## It flies like the Rook Thief: its body is neither solid nor stopped (layer and mask 0), its root
## is the ground point under it (its shadow) and its art and hurtbox ride `height` above it.
## - **Asleep:** hanging `roostHeightPx` up, wings wrapped, out of reach (no hurtbox); in a dark room
##   only its eyes glint (game/enemy/dark_eyes.gd), as slits.
## - **Wake** (the tell, `wakeMs`; owner, 2026-10-23: "awake while the room is not 100% lit, asleep
##   once it is; that gives the Lantern more use"): its roost is in a dark room that is still dark
##   (DarkRoom.is_dark_at) and the slime is engaged (in its pen or within its targeting radius), at
##   least `restMs` after its last swoop: its eyes open wide and glint, it squeaks, its shadow
##   darkens. Lighting every candle of the room (the Lantern) puts it to sleep for good: it flies home
##   and stays there.
## - **Swoop** (`swoopMs`): a dive from its roost through the point where the slime stood at the
##   tell's end, `swoopOvershootPx` on (kept in its pen), weaving `waveAmpPx` side to side
##   (`waveCount` times), down to `swoopLowPx` in its middle. Under `lowHeightPx` it can be hit;
##   touching the slime there (ground points within `biteRadiusPx`) it bites once per swoop.
## - **Return** (`returnMs`): it flutters back up to its roost and hangs there again.
## - **The right tool:** a Lantern puff as it dives (a hit tagged `fire` while it is low, the only
##   time a flame can reach it) burns it out of the air at once (`_kill_hit`); a Spear jab as it
##   swoops low hurts it (20 health: two jabs). The Bow's hook: `on_arrow_hit` (any height).
## A stun holds it in the air and holds its swoop's clock.
##
## Owner: enemy builder.

## Its room's darkness: awake while it lasts (`_in_darkness`).
const DarkRoom := preload("res://game/world/darkness/dark_room.gd")
const DarkEyes := preload("res://game/enemy/dark_eyes.gd")

const PHASE_ASLEEP := "asleep"
const PHASE_WAKE := "wake"
const PHASE_SWOOP := "swoop"
const PHASE_RETURN := "return"
const FRAME_ASLEEP := 0
const FRAME_WOKEN := 1
const FRAME_SWOOP := 2
const FRAME_DOWN := 3
const FIRE_TAG := "fire"
const BOW_TARGETS := &"bow_targets"
const CUE_WAKE := &"TalkBlip"
const CUE_SWOOP := &"Lash"
const CUE_BITE := &"HitDull"
const CUE_BURN := &"StatusBurn"
const CUE_FALL := &"FallDown"
const FEATHERS := &"dodge-dust"
## Presentation: the wake's shiver, the flap's bob, the hanging sway, the shadow by height, the
## hurtbox over the art's middle, the eyes (golden; their pixels in each frame's 256 px cell).
const SHIVER_RAD := 0.06
const SHIVER_MS := 30.0
const SWAY_RAD := 0.04
const SWAY_MS := 900.0
const FLAP_PX := 3.0
const FLAP_MS := 70.0
const SHADOW_SIZE := Vector2(18.0, 6.0)
const HURTBOX_RISE_PX := 10.0
const EYE_COLOR := Color(1.0, 0.82, 0.3)
const EYES := {
	FRAME_ASLEEP: [Vector2(115, 207), Vector2(139, 207)],
	FRAME_WOKEN: [Vector2(114, 197), Vector2(143, 196)],
	FRAME_SWOOP: [Vector2(114, 192), Vector2(142, 202)],
}
## A sleeping bat's eyes glint now and then (presentation, real time).
const GLINT_MS := 2300.0
const GLINT_LEN_MS := 260.0

var _height: float = 0.0
var _roost: Vector2 = Vector2.INF
var _swoop_from: Vector2 = Vector2.ZERO
var _swoop_to: Vector2 = Vector2.ZERO
var _return_from: Vector2 = Vector2.ZERO
var _return_height: float = 0.0
var _rest_until: float = 0.0
var _bitten: bool = false
var _last_ms: float = -1.0
var _fall_from: float = 0.0
var _fell_at: float = -1.0
var _eyes: DarkEyes
var _seed: float = 0.0


func _ready() -> void:
	super()
	add_to_group(BOW_TARGETS)
	_height = pattern("roostHeightPx", 100.0)
	_transition(PHASE_ASLEEP, Services.now_ms())
	set_hurtbox(false)
	set_frame(FRAME_ASLEEP)
	_seed = randf() * GLINT_MS
	if visual != null:
		_eyes = DarkEyes.new()
		_eyes.name = "DarkEyes"
		_eyes.color = EYE_COLOR
		_eyes.radius_px = 2.0
		_eyes.halo_px = 5.5
		for frame: int in EYES:
			_eyes.eyes[frame] = PackedVector2Array(EYES[frame])
		visual.add_child(_eyes)


func get_height() -> float:
	return _height


func is_low() -> bool:
	return _height <= pattern("lowHeightPx", 36.0)


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	_last_ms = now
	if _roost == Vector2.INF:
		_roost = feet()
	var elapsed := _elapsed(now)
	var roost_height := pattern("roostHeightPx", 100.0)
	match _phase:
		PHASE_ASLEEP:
			_height = move_toward(_height, roost_height, pattern("climbSpeed", 160.0) * delta)
			_fly_to(_roost, delta)
			set_hurtbox(false)
			if now >= _rest_until and engaged and _in_darkness():
				_transition(PHASE_WAKE, now)
				set_frame(FRAME_WOKEN)
				_cue(CUE_WAKE)
		PHASE_WAKE:
			body.velocity = Vector2.ZERO
			if elapsed >= pattern("wakeMs", 650.0):
				# The room lit during the tell (its last candle) sends it back to sleep: no last swoop.
				if engaged and _in_darkness():
					_begin_swoop(now, target)
				else:
					_sleep(now)
		PHASE_SWOOP:
			var t := clampf(elapsed / maxf(1.0, pattern("swoopMs", 1300.0)), 0.0, 1.0)
			var dive := clampf(sin(PI * t) * pattern("swoopDipShare", 1.5), 0.0, 1.0)
			_height = lerpf(roost_height, pattern("swoopLowPx", 12.0), dive)
			var line := _swoop_to - _swoop_from
			var side := line.orthogonal().normalized() if line.length() > 0.0 else Vector2.RIGHT
			var weave := sin(TAU * pattern("waveCount", 1.5) * t) * pattern("waveAmpPx", 36.0) * sin(PI * t)
			_fly_to(_swoop_from.lerp(_swoop_to, t) + side * weave, delta)
			var low := is_low()
			set_hurtbox(low)
			if low and engaged and not _bitten:
				_try_bite(target)
			if t >= 1.0:
				_begin_return(now)
		PHASE_RETURN:
			var t := clampf(elapsed / maxf(1.0, pattern("returnMs", 1400.0)), 0.0, 1.0)
			_height = lerpf(_return_height, roost_height, clampf(t * 2.0, 0.0, 1.0))
			set_hurtbox(is_low())
			_fly_to(_return_from.lerp(_roost, t), delta)
			if t >= 1.0:
				_sleep(now)
	_place_art(now)


## The Bow's hook (bow_arrow.gd): an arrow brings it down from any height. `hit` is the
## arrow's hit (unused). True when it fell.
func on_arrow_hit(_hit: Dictionary) -> bool:
	if is_defeated():
		return false
	_cue(CUE_FALL)
	_defeat()
	return true


## True while its roost lies in a dark room that is not lit yet (not 100% light).
func _in_darkness() -> bool:
	return DarkRoom.is_dark_at(get_tree(), _roost if _roost != Vector2.INF else feet())


func _begin_swoop(now: float, target: Dictionary) -> void:
	_transition(PHASE_SWOOP, now)
	set_frame(FRAME_SWOOP)
	_bitten = false
	_swoop_from = feet()
	var slime_body := target.get("body") as Node2D
	var aim: Vector2 = slime_body.global_position if slime_body != null else _roost
	var line := aim - _swoop_from
	var unit := line.normalized() if line.length() > 0.0 else Vector2.DOWN
	_swoop_to = _inside_arena(aim + unit * pattern("swoopOvershootPx", 120.0))
	face_x(unit.x)
	_cue(CUE_SWOOP)


func _begin_return(now: float) -> void:
	_return_from = feet()
	_return_height = _height
	_transition(PHASE_RETURN, now)
	set_frame(FRAME_SWOOP)


func _sleep(now: float) -> void:
	_transition(PHASE_ASLEEP, now)
	set_frame(FRAME_ASLEEP)
	set_hurtbox(false)
	_rest_until = now + pattern("restMs", 1200.0)


func _try_bite(target: Dictionary) -> void:
	var slime_body := target.get("body") as Node2D
	if slime_body == null or feet().distance_to(slime_body.global_position) > pattern("biteRadiusPx", 26.0):
		return
	_bitten = true
	if _route_immediate_attack(target, pattern("biteDamage", 20.0), pattern("biteKnockback", 160.0)):
		_cue(CUE_BITE)


## A point kept `arenaInsetPx` inside its pen (the point itself without a pen).
func _inside_arena(point: Vector2) -> Vector2:
	if _arena.is_empty():
		return point
	var inset := pattern("arenaInsetPx", 32.0)
	var x := float(_arena.get("x", point.x))
	var y := float(_arena.get("y", point.y))
	var w := float(_arena.get("w", 0.0))
	var h := float(_arena.get("h", 0.0))
	return Vector2(clampf(point.x, x + inset, x + w - inset), clampf(point.y, y + inset, y + h - inset))


## Velocity that puts the ground point on `point` this step (it flies through everything).
func _fly_to(point: Vector2, delta: float) -> void:
	var velocity := (point - feet()) / maxf(delta, 0.0001)
	if absf(velocity.x) > WALK_SPEED_THRESHOLD and _phase != PHASE_ASLEEP:
		face_x(velocity.x)
	body.velocity = velocity


## The art, the hurtbox and the shadow at its height; the sway, the shiver, the flap; the eyes.
func _place_art(now: float) -> void:
	var lean := 0.0
	var bob := 0.0
	match _phase:
		PHASE_ASLEEP:
			lean = sin(now / SWAY_MS) * SWAY_RAD
		PHASE_WAKE:
			lean = sin(now / SHIVER_MS) * SHIVER_RAD
		PHASE_SWOOP, PHASE_RETURN:
			bob = sin(now / FLAP_MS) * FLAP_PX
	set_look(_height + bob, Vector2.ONE, lean)
	if damage_area != null:
		damage_area.position = Vector2(0.0, -_height - HURTBOX_RISE_PX)
	var shadow := ground_shadow()
	if shadow != null:
		var near := 1.0 - clampf(_height / maxf(1.0, pattern("roostHeightPx", 100.0)), 0.0, 1.0)
		shadow.size = SHADOW_SIZE * lerpf(0.55, 1.0, near)
		shadow.strength = 1.0 if _phase == PHASE_WAKE or _phase == PHASE_SWOOP else lerpf(0.35, 0.8, near)
	if _eyes != null:
		if _phase == PHASE_ASLEEP:
			var glint := fposmod(float(Time.get_ticks_msec()) + _seed, GLINT_MS) < GLINT_LEN_MS
			_eyes.squint = 0.7 if glint else 0.45
			_eyes.strength = 1.0 if glint else 0.75
		else:
			_eyes.squint = 1.0
			_eyes.strength = 1.0


## A flame's hit while it dives burns it out of the air.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, FIRE_TAG)


func commit_damage(commit: Dictionary) -> void:
	var burnt := _kill_hit(commit.get("request", {}))
	super(commit)
	if burnt:
		_cue(CUE_BURN)


## It flies: a stun holds it where it is, and holds its swoop's clock.
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(now: float, _delta: float) -> void:
	if _last_ms >= 0.0:
		_phase_started_at += now - _last_ms
	_last_ms = now
	_place_art(now)


## The fall to the ground once beaten (the defeated step does not run the pattern).
func _after_enemy_step(_delta: float) -> void:
	if not is_defeated() or _fell_at < 0.0:
		return
	var t := clampf((Services.now_ms() - _fell_at) / maxf(1.0, pattern("fallMs", 280.0)), 0.0, 1.0)
	_height = lerpf(_fall_from, 0.0, t * t)
	set_look(_height)
	var shadow := ground_shadow()
	if shadow != null:
		shadow.size = SHADOW_SIZE * lerpf(0.7, 1.0, t)


func _defeat() -> void:
	if is_defeated():
		return
	_fall_from = _height
	_fell_at = Services.now_ms()
	_puff(FEATHERS, feet())
	if damage_area != null:
		damage_area.position = Vector2(0.0, -HURTBOX_RISE_PX)
	super()
	set_look(_fall_from)
	if _eyes != null:
		_eyes.strength = 0.0
