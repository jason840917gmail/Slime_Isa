extends "res://game/enemy/patterned_enemy.gd"
class_name SilkLurkerScript
## Scene script `game.silk-lurker` (the bestiary's row 18, an ambusher; docs/godot/BESTIARY.md
## "Silk Lurker"): a fat furry spider with a pale skull on its back that hangs high in the canopy
## on a silk thread, over its own shadow.
##
## It hangs: its body is not solid (the slime walks under it) and never slides; its root is the
## ground point under it (its shadow), and its art, hurtbox and thread ride `height` above it.
## - **Lurk:** `lurkHeightPx` up, out of reach (no hurtbox), legs folded. Its shadow on the ground
##   and the thread going up are the tell of where it waits.
## - **Tell** (`tellMs`): the slime's feet come within `dropRangePx` of its shadow (at most every
##   `redropMs`): it shivers on its creaking thread and its shadow grows dark.
## - **Drop** (`dropMs`): it falls on its thread down to `hangHeightPx`, legs flung open; the
##   slime's feet within `biteRangePx` of its shadow take `dropDamage` with `dropKnockback`.
## - **Hang** (`hangMs`): it dangles low, swinging toward the slime, open; touching it there hurts
##   (`swayDamage` within `swayReachPx`). A hit sets it **spinning** like a pinata (`spinMs`, each
##   hit starts it again): dizzy, harmless and open. Then it **climbs** back up (`climbMs`).
## - **Cut down:** the Bow's arrow (`on_arrow_hit`, group `bow_targets`, bow_arrow.gd: any
##   height) or a thrown thing that hits it low (tag `thrown`) cuts it off its thread: it falls
##   (`fallMs`) and lies on its back for `downMs` (open, every old-style hit `downDamageTaken`
##   times; rework hits: the profile's `states.down`), then climbs a new thread.
## Its hurtbox is on while it is under `reachHeightPx`.
##
## Owner: enemy builder.

const PHASE_LURK := "lurk"
const PHASE_TELL := "tell"
const PHASE_DROP := "drop"
const PHASE_HANG := "hang"
const PHASE_SPIN := "spin"
const PHASE_CLIMB := "climb"
const PHASE_FALL := "fall"
const PHASE_DOWN := "down"
const FRAME_HANG := 0
const FRAME_DROP := 1
const FRAME_SPIN := 2
const FRAME_DOWN := 3
## What the Bow's arrow strikes (bow_arrow.gd): `on_arrow_hit(hit: Dictionary) -> bool`.
const BOW_TARGETS := &"bow_targets"
const CUE_TELL := &"GroundCreak"
const CUE_DROP := &"Lash"
const CUE_SPIN := &"NpcBlip"
const CUE_CUT := &"WebTear"
const CUE_LAND := &"Land"
const DUST := &"dodge-dust"
const THREAD_NAME := "Thread"
## Presentation: the thread (where it leaves the spider's back, how far up it shows, its look),
## the shiver, the swing and the spin, the shadow by height, the hurtbox over the art's middle.
const THREAD_ATTACH_PX := 44.0
const THREAD_UP_PX := 260.0
const THREAD_WIDTH := 1.6
const THREAD_COLOR := Color(0.93, 0.93, 0.98, 0.85)
const SHIVER_PX := 1.6
const SHIVER_MS := 28.0
const SWING_PX := 12.0
const SWING_MS := 260.0
const SPIN_FLIP_MS := 80.0
const SPIN_LEAN_RAD := 0.32
const SPIN_SWING_PX := 9.0
const LURK_BOB_PX := 2.0
const LURK_BOB_MS := 520.0
const SHADOW_SIZE := Vector2(24.0, 9.0)
const SHADOW_HIGH_STRENGTH := 0.8
const TELL_SHADOW_GROW := 1.4
const HURTBOX_RISE_PX := 24.0

var _height: float = 0.0
var _ready_at: float = 0.0
var _climb_from: float = 0.0
var _swing: float = 0.0
var _cut: bool = false
var _thread: Line2D
## Sprung by a tripwire (game/world/webs/tripwire.gd): its tell and drop run on even with the slime
## out of its range; cleared once it hangs.
var _tripped: bool = false


func _ready() -> void:
	super()
	add_to_group(BOW_TARGETS)
	_height = pattern("lurkHeightPx", 150.0)
	_transition(PHASE_LURK, Services.now_ms())
	set_frame(FRAME_HANG)
	set_hurtbox(false)
	set_solid(false)
	_make_thread()


func _step_pattern(now: float, _delta: float, target: Dictionary, engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var elapsed := _elapsed(now)
	var slime_feet := _slime_feet(target)
	match _phase:
		PHASE_LURK:
			_height = pattern("lurkHeightPx", 150.0)
			_swing = 0.0
			if engaged and now >= _ready_at and feet().distance_to(slime_feet) <= pattern("dropRangePx", 50.0):
				_transition(PHASE_TELL, now)
				_cue(CUE_TELL)
		PHASE_TELL:
			_swing = sin(now / SHIVER_MS) * SHIVER_PX
			if not engaged and not _tripped:
				_transition(PHASE_LURK, now)
			elif elapsed >= pattern("tellMs", 450.0):
				_transition(PHASE_DROP, now)
				set_frame(FRAME_DROP)
				face_x(slime_feet.x - feet().x)
				_cue(CUE_DROP)
		PHASE_DROP:
			var t := clampf(elapsed / maxf(1.0, pattern("dropMs", 200.0)), 0.0, 1.0)
			_height = lerpf(pattern("lurkHeightPx", 150.0), pattern("hangHeightPx", 22.0), t * t)
			_swing = 0.0
			if t >= 1.0:
				_transition(PHASE_HANG, now)
				_tripped = false
				_puff(DUST, feet())
				if engaged and feet().distance_to(slime_feet) <= pattern("biteRangePx", 34.0):
					_route_immediate_attack(target, pattern("dropDamage", 18.0), pattern("dropKnockback", 220.0))
		PHASE_HANG:
			_height = pattern("hangHeightPx", 22.0)
			# It swings toward the slime on its thread.
			var side := signf(slime_feet.x - feet().x) if engaged else 0.0
			_swing = lerpf(_swing, side * SWING_PX + sin(now / SWING_MS) * SWING_PX * 0.4, 0.12)
			if engaged:
				face_x(slime_feet.x - feet().x)
				_contact(target, pattern("swayDamage", 8.0), pattern("swayKnockback", 140.0), pattern("swayReachPx", 26.0) + _rise())
			if elapsed >= pattern("hangMs", 2600.0):
				_begin_climb(now)
		PHASE_SPIN:
			_height = pattern("hangHeightPx", 22.0)
			if elapsed >= pattern("spinMs", 1400.0):
				_begin_climb(now)
		PHASE_CLIMB:
			var t := clampf(elapsed / maxf(1.0, pattern("climbMs", 800.0)), 0.0, 1.0)
			_height = lerpf(_climb_from, pattern("lurkHeightPx", 150.0), t)
			_swing = lerpf(_swing, 0.0, 0.1)
			if t >= 1.0:
				_transition(PHASE_LURK, now)
				_ready_at = now + pattern("redropMs", 1400.0)
		PHASE_FALL:
			var t := clampf(elapsed / maxf(1.0, pattern("fallMs", 260.0)), 0.0, 1.0)
			_height = lerpf(_climb_from, 0.0, t * t)
			_swing = 0.0
			if t >= 1.0:
				_transition(PHASE_DOWN, now)
				_cue(CUE_LAND)
				_puff(DUST, feet())
		PHASE_DOWN:
			_height = 0.0
			if elapsed >= pattern("downMs", 2400.0):
				# It spins a new thread and climbs back up.
				_cut = false
				_begin_climb(now)
	_place_art(now)


## A tripwire's pull (game/world/webs/tripwire.gd; Gloop Forest's River Roads, 2026-11-21): a
## lurking spider starts its tell at once and drops, wherever the slime is. False when it is not
## lurking (already dropping, hanging, climbing or cut down).
func trip() -> bool:
	if _phase != PHASE_LURK or _cut:
		return false
	_tripped = true
	_transition(PHASE_TELL, Services.now_ms())
	_cue(CUE_TELL)
	return true


## Cuts it off its thread (the Bow, a thrown thing): it falls and lies on its back. False when it
## is already down or defeated.
func knock_down() -> bool:
	if is_defeated() or _phase == PHASE_FALL or _phase == PHASE_DOWN:
		return false
	var now := Services.now_ms()
	_climb_from = _height
	_cut = true
	_transition(PHASE_FALL, now)
	set_frame(FRAME_DOWN)
	_cue(CUE_CUT)
	_ready_at = now + pattern("fallMs", 260.0) + pattern("downMs", 2400.0) + pattern("redropMs", 1400.0)
	_place_art(now)
	return true


## The Bow's hook (bow_arrow.gd): an arrow cuts its thread from any height. `hit` is
## the arrow's hit (unused yet). True when it fell.
func on_arrow_hit(_hit: Dictionary) -> bool:
	return knock_down()


func get_height() -> float:
	return _height


## True while it dangles low enough to be hit.
func is_low() -> bool:
	return _height <= pattern("reachHeightPx", 48.0)


func is_thread_cut() -> bool:
	return _cut


## A hit while it dangles sets it spinning; a thrown thing cuts it down.
func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if is_defeated():
		return
	var request: Dictionary = commit.get("request", {})
	var hanging := _phase == PHASE_HANG or _phase == PHASE_SPIN or _phase == PHASE_DROP
	if hanging and has_tag(request, THROWN_TAG):
		knock_down()
	elif hanging:
		_spin(Services.now_ms())


func _spin(now: float) -> void:
	if _phase != PHASE_SPIN:
		_cue(CUE_SPIN)
	_transition(PHASE_SPIN, now)
	set_frame(FRAME_SPIN)
	_height = pattern("hangHeightPx", 22.0)


func _begin_climb(now: float) -> void:
	_climb_from = _height
	_transition(PHASE_CLIMB, now)
	set_frame(FRAME_HANG)


## Old-style hits on its back: `downDamageTaken` times (rework hits: `states.down.damageTaken`).
func mitigate_damage(input: Dictionary) -> float:
	var damage := super(input)
	if _phase == PHASE_DOWN and not ReworkMode.is_rework_request(input.get("request", {})):
		damage *= pattern("downDamageTaken", 1.5)
	return damage


## It hangs on a thread: a stun holds it where it is (and a spin goes on spinning).
func _slides_when_stunned() -> bool:
	return false


func _on_stunned(now: float, _delta: float) -> void:
	body.velocity = Vector2.ZERO
	_place_art(now)


func _defeat() -> void:
	if is_defeated():
		return
	_height = 0.0
	_swing = 0.0
	_cut = true
	if damage_area != null:
		damage_area.position = Vector2(0.0, -HURTBOX_RISE_PX)
	super()
	_place_art(Services.now_ms())


# --- the look --------------------------------------------------------------------------------------

## The art, the hurtbox and the thread at `height`, swung `_swing` px to the side.
func _place_art(now: float) -> void:
	var lift := _height
	var lean := 0.0
	if _phase == PHASE_LURK:
		lift += sin(now / LURK_BOB_MS) * LURK_BOB_PX
	elif _phase == PHASE_SPIN and not is_defeated():
		# Round and round like a pinata: the art flips side to side and swings.
		if visual != null:
			visual.flip_h = int(now / SPIN_FLIP_MS) % 2 == 0
		lean = sin(now / SPIN_FLIP_MS * 0.9) * SPIN_LEAN_RAD
		_swing = sin(now / (SPIN_FLIP_MS * 1.7)) * SPIN_SWING_PX
	set_look(lift, Vector2.ONE, lean)
	if pose != null:
		pose.position.x = _swing
	set_hurtbox(not is_defeated() and _height <= pattern("reachHeightPx", 48.0))
	if damage_area != null and not is_defeated():
		damage_area.position = Vector2(_swing, -lift - HURTBOX_RISE_PX)
	_place_thread(lift)
	var shadow := ground_shadow()
	if shadow != null:
		# High up it is a soft dark spot; the tell grows and darkens it.
		var near := 1.0 - clampf(_height / maxf(1.0, pattern("lurkHeightPx", 150.0)), 0.0, 1.0)
		var tell := clampf(_elapsed(now) / maxf(1.0, pattern("tellMs", 450.0)), 0.0, 1.0) if _phase == PHASE_TELL else 0.0
		shadow.size = SHADOW_SIZE * maxf(lerpf(0.9, 1.15, near), lerpf(0.9, TELL_SHADOW_GROW, tell))
		shadow.strength = lerpf(SHADOW_HIGH_STRENGTH, 1.0, maxf(tell, near))


## Its rise over the feet for reach checks against the slime's centre.
func _rise() -> float:
	return _height * 0.5


func _make_thread() -> void:
	if body == null:
		return
	_thread = Line2D.new()
	_thread.name = THREAD_NAME
	_thread.width = THREAD_WIDTH
	_thread.default_color = THREAD_COLOR
	var fade := Gradient.new()
	fade.set_color(0, THREAD_COLOR)
	fade.set_color(1, Color(THREAD_COLOR, 0.0))
	_thread.gradient = fade
	_thread.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	if body.is_node_ready():
		body.add_child(_thread)
		body.move_child(_thread, 0)
	else:
		body.add_child.call_deferred(_thread)
		body.move_child.call_deferred(_thread, 0)


## The thread from the spider's back straight up into the canopy (hidden once it is cut).
func _place_thread(lift: float) -> void:
	if _thread == null or not is_instance_valid(_thread):
		return
	_thread.visible = not _cut
	var attach := Vector2(_swing, -lift - THREAD_ATTACH_PX)
	var top := Vector2(0.0, -pattern("lurkHeightPx", 150.0) - THREAD_ATTACH_PX - THREAD_UP_PX)
	_thread.points = PackedVector2Array([attach, top])


func _slime_feet(target: Dictionary) -> Vector2:
	var slime_body := target.get("body") as Node2D
	return slime_body.global_position if slime_body != null else Vector2.INF
