extends Node
## The resident shape controller (body-shapes plan section 3; combat-feel plan sections 3-4, 7 and 8
## `shape_controller.gd`; BODY_SHAPES.md "Shapes"). In the rework mode main.gd makes it, a child
## "ShapeController" of the player root, calls `setup(player)` and hands it to the player
## (`PlayerScript.set_shapes`). It owns the chain on `Services.now_ms()` (a hit-stop pauses it with
## the world, so a freeze never eats a hold or a link window):
## - **Presses fire on their release** (owner, 2026-10-12). An Attack press only records its time and
##   aim. Let go before `combat.chain.chargeStartMs` it is a **tap**, which fires a chain step on the
##   release (below); held that long it arms the charge ring instead, and nothing strikes. So holding
##   Attack never strikes first.
## - **Steps.** A tap starts the next step of the current shape's chain (`shapes.<name>.chain`): its
##   wind-up, its active window (one DamageRouter activation; the line, the swept arc or the impact
##   circle re-aimed each step, each receiver hit once: ShapeStrike), its recovery. A tap pressed
##   during a step, from its first active frame, waits and fires at the step's cancel point; a tap
##   inside the link window after it (`combat.chain.linkMs`) fires at once (also while the step's
##   recovery still plays) and continues the chain, a later one starts at step 1 again. The link is
##   judged at the tap's press, so a tap pressed in the window and let go just after it still links.
##   After the last step the chain rests (`combat.chain.restMs`), then a waiting tap starts a new
##   chain. From their cancel point the slime may walk out of steps 1-2 (`walkCancel`); the finisher
##   cannot be walked out of. A whiff does not end a chain.
## - **Holds.** Each hit's `hold_ms` comes from the hold formula (ShapeDefs.hold_ms), capped at
##   `combat.chain.holdCapMs`; its `holdMarginMs` also covers the next tap's own press.
## - **Charges.** Attack held `chargeStartMs` arms the goo ring: it fills after the running step (after
##   the rest for a finisher) over the charge's `ringMs`; a release when it is full fires the charge
##   (the Lunge, the Spin, the Quake), which spends its `energy` (PlayerScript.spend_energy) or
##   fizzles with a small cue when the slime is short; a release before it is full drains the ring
##   quietly (no attack, no energy). While the ring fills or waits full (`is_charging`) the slime
##   walks at `combat.chain.chargeWalkScale` of its speed (`walk_scale`, player.gd). A charge ends the
##   chain.
## - **The last step loads** (owner, 2026-10-12): a chain's last step has an `anticipation` block.
##   Through its wind-up the slime's art pulls back from the aim and squashes, then springs into the
##   strike (the War Axe's chop also hops `jumpPx` and lands on the contact frame), on the player's
##   effects channel (ShapeVisuals.art_pose; the body never rises), while the shape loads (its strike
##   animation: the spear retracts and glints, the axe rises behind, the hammer lifts higher).
## - **Switching** (`cycle`, `set_current`): through the learned shapes, wrapping; instant between
##   strikes; during one the switch waits for the step's cancel point, or for the end of a charge
##   (a switch never aborts a strike: a wind-up, a finisher or a paid charge always plays out). A
##   switch resets the chain (and cancels a charge ring); a press not let go yet survives it.
## - **What ends a chain** (`reset_chain`): no tap in time, a clink (the slime recoils
##   `combat.chain.clink.recoilPx` through PlayerScript.recoil), being hit, a switch, Q, a box
##   ability, the Roll, a door or window (`stop_movement`), death.
## - **Aim.** `press_attack(aim)`: the pointer's aim from the slime's centre, where every shape strikes
##   from (PlayerScript.get_strike_aim), or ZERO for the facing; a tap strikes along its press's aim.
##   Every shape aims 4-way (owner, 2026-10-12, round 2: `aim` "snap4"; ShapeDefs.aim_for: the
##   nearest of right, down, left and up, an exact diagonal to the side; the `exact` and `snap8` modes
##   stay for data); the slime faces the snapped aim and shows its strike (below).
##   A charge aims where the pointer is at the release (the same strike aim, or the facing).
## - **Strikes** (owner, 2026-10-12; game/shapes/shape_poses.gd, shape_strikes.gd, StrikeLibrary): every
##   step and charge but the Axe's Spin plays its strike animation on the step's own timeline (the
##   Spear's jabs `spear-jab`, its lunging jab and Lunge `spear-finisher`; the Axe's sweep, backswing and
##   chop and the Hammer's Thud, BOOM and Quake their own), in the aim's down / up / side direction; the
##   Spin shows the slime's drawn key poses (page 6 of its sheet: its two swings in turn), and a strike
##   with neither (a strike file missing) plays the stand-in `attack-1`. The Spear's hit line starts at
##   the full-lean frame's socket (`_with_strike`), where the drawn spear leaves the body. Every chain
##   step hits with the reach of its strike file in the aim's direction (the Axe's radius, the Hammer's
##   offset, the Spear's reach: StrikeLibrary.chain_hit; game-constants.json holds none for them), the
##   charges with their own numbers. While the charge ring fills or waits full the slime holds its
##   charge's strike wind-up frame (the strike's hold), or the Axe's `load` pose (`held_pose_clip`, asked
##   by player.gd's locomotion clip). Once a strike ends or is cancelled the controller is idle and the
##   player plays idle or walk again. On the strike frames no code squash plays (the anticipation's nor
##   the strike squash): each strip keeps one scale, and the rigid weapon is drawn under (and its neck
##   over) the slime's Visual.
## - **The slime's step.** While a step owns the slime (`is_busy`), player.gd drives its body with
##   `step_velocity()`: each step's small lunge (`stepPx` from `stepFromMs` to `stepToMs`, by default
##   over the wind-up and the active window; the Hammer steps into its smash, a finisher after its
##   pull-back), the finisher's recoil after it hit (`combat.chain.finisherRecoilPx` over its
##   recovery), the Lunge's dart (`dashPx` in `dashMs`). The controller never moves the body itself.
## - **Feel** (ShapeStrike.feel_swing): GameFeel.play_hit once per swing, sparks and a number per
##   target, the strike squash (`combat.chain.strikeSquash`), the swing and impact cues; a Hammer
##   impact in the Stone form is a Heavy impact (PlayerScript.record_slam), so cracked ground breaks.
## - **Visuals**: game/shapes/shape_visuals.gd, a child of the player body.
##
## What player.gd does with it (rework mode only):
## - every physics step, alive: `update(now_ms, delta)` (after the abilities advance);
## - an `attack` press: `press_attack(aim)` (its release is read here, with `is_action_held`);
## - `weapon_next` / `weapon_previous`: `cycle(+1 / -1)`;
## - while `is_busy()` the slime does not walk: player.gd sets its velocity to `step_velocity()`
##   every step and still feeds it presses; while `is_charging()` it walks at `walk_scale()`;
## - `reset_chain(reason)` on: "hurt" (a hit with damage), "death", "roll", "ability" (a box ability
##   started), "mouth" (a Q press), "stopped" (doors, windows, a modal pause: `stop_movement`);
## - `drop_press()` when it clears its input (`clear_input`), so a held press is never let go there;
## - the click and moba schemes' attack order asks `reaches(aim, area)`.
## It never calls `player.stop_movement()` (that resets the chain) and reads the hold with
## `player.is_action_held(&"attack")`.
##
## Owner: shapes.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapePoses := preload("res://game/shapes/shape_poses.gd")
const ShapeStrike := preload("res://game/shapes/shape_strike.gd")
const ShapeStrikes := preload("res://game/shapes/shape_strikes.gd")
const StrikeLibrary := preload("res://game/shapes/strike_library.gd")
const AnimationType := preload("res://game/shapes/strike_animation.gd")
const ShapeVisuals := preload("res://game/shapes/shape_visuals.gd")
const SquashStretch := preload("res://game/player/squash_stretch.gd")

## The current shape changed. Payload: {"shape_id": String}.
signal shape_changed(payload: Dictionary)

## IDLE: nothing owns the slime (it may rest, wait in a link window or fill a charge ring);
## STEP: a chain step runs; CHARGE: a charge runs. STEP and CHARGE make the controller busy.
enum Phase { IDLE, STEP, CHARGE }

const ATTACK_ACTION := &"attack"
## The walk keys (a held one walks the slime out of steps 1-2 after their cancel point).
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
## The player clip a strike plays when it has neither its strike animation nor drawn poses (ShapePoses: a
## strike file missing).
const STAND_IN_CLIP := "attack-1"
const VISUALS_NAME := "ShapeVisuals"
## Cues (audio.global) until the shapes get their own sounds: the swing, the Hammer's impact, the
## switch (the old EquipBlade / EquipTool), the charge ring's chime when full, the fizzle.
const SWING_CUES := {"spear": &"Lash", "axe": &"Dodge", "hammer": &"SlamWindup"}
const IMPACT_CUES := {"hammer": &"SlamImpact"}
const SWITCH_CUES := {"spear": &"EquipBlade", "axe": &"EquipBlade", "hammer": &"EquipTool"}
const RING_FULL_CUE := &"Heal"
const FIZZLE_CUE := &"AbilityDenied"
## The fizzle's small puff at the feet.
const FIZZLE_PARTICLES := &"dodge-dust"
## The shared ring's cancel drain (the mouth's too).
const RING_CANCEL_PATH := "gulp.rework.ringCancelMs"
const HAMMER := "hammer"
const FINISHER_CLASS := "finisher"
const RESET_CLINK := "clink"
const RESET_SWITCH := "switch"

## The shape last made current, kept across world builds (the controller is made again with the
## player on every build). Not saved with the run yet (BODY_SHAPES.md "Status").
static var _last_shape_id: StringName = &""

var _player: PlayerScript
var _current: StringName = &""
var _visuals: ShapeVisuals
var _hitbox: Area2D
## The running strike's frames on the slime: its strike animation, or the Spin's drawn key poses.
var _poses: ShapePoses = ShapePoses.new()

# --- the running step or charge ---
var _phase: Phase = Phase.IDLE
var _shape: StringName = &""
## The running step's index in the chain (0-based; 0 for a charge).
var _index: int = 0
## The running step's or charge's numbers (shared with GameConstants: never changed), and the numbers
## its hit area and drawing use: `_data`, or a copy with its strike frames' keys (`_with_strike`).
var _data: Dictionary = {}
var _hit_data: Dictionary = {}
var _started_ms: float = 0.0
## The hit's aim (the shape's aim mode: the 4-way snap for every shape) and the arc's sweep sign
## (+1 clockwise on screen), mirrored for left-facing swings so the Axe always sweeps down in front.
var _aim: Vector2 = Vector2.DOWN
var _sweep: float = 1.0
## The line's reach after the wall ray (0 for other kinds).
var _reach: float = 0.0
## The swing's crit (rolled once per step or charge).
var _crit: bool = false
var _activation: int = 0
## Receivers already tried in this step (instance id -> true): each once per step.
var _resolved: Dictionary = {}
var _contact_done: bool = false
var _feel_played: bool = false
## Creatures this swing hit (its feel), and every hit it landed (resources too: a chopped tree is no
## whiff, so a rock in the same sweep does not clink).
var _swing_hits: int = 0
var _swing_landed: int = 0
var _cancel_reached: bool = false
## The finisher hit something at this time (< 0: no): the slime recoils over its recovery.
var _recoil_from_ms: float = -1.0
## The next tick of a charge that hits in ticks.
var _tick: int = 0
## The slime's art carries a last step's anticipation pose (ShapeVisuals.art_pose).
var _posed: bool = false

# --- the chain between steps ---
## The step the next tap starts while the link window is open (until `_link_until_ms`).
var _next_index: int = 0
var _link_until_ms: float = -1.0
## After a finisher: no new chain before this.
var _rest_until_ms: float = 0.0
## A tap waiting for the cancel point or the end of the rest: its aim and its press's time.
var _queued: bool = false
var _queued_aim: Vector2 = Vector2.ZERO
var _queued_ms: float = 0.0
## A switch waiting for the step's cancel point (or the end of a charge).
var _pending_switch: StringName = &""

# --- the press not let go yet ---
## The Attack press whose release (a tap) or hold (the charge ring) is not known yet (< 0: none):
## its time and its aim.
var _press_ms: float = -1.0
var _press_aim: Vector2 = Vector2.ZERO

# --- the charge ring ---
## The ring fills from this time (< 0: no ring armed); its shape; whether it is full.
var _ring_from_ms: float = -1.0
var _ring_shape: StringName = &""
var _ring_full: bool = false

var _squash_tween: Tween


## Remembers the player and picks the current shape: the last one used, else the first learned.
## Makes the visuals (a child of the player body at the slime's centre) and the ShapeHitbox.
func setup(player: PlayerScript) -> void:
	_player = player
	# The strike animations, built from their resources (StrikeLibrary), on the player's AnimationPlayer.
	StrikeLibrary.install(player.animation)
	_poses.setup(player)
	var learned := learned_shape_ids()
	if learned.has(_last_shape_id):
		_current = _last_shape_id
	elif not learned.is_empty():
		_current = learned[0]
	else:
		_current = &""
	_make_parts()


func _exit_tree() -> void:
	_close_activation()
	_end_pose()
	if _visuals != null and is_instance_valid(_visuals):
		_visuals.queue_free()
	_visuals = null


## Every physics step while the slime is alive (player.gd, rework mode): a waiting switch, the
## running step or charge (its contacts, cancel point, walk-out, end), a waiting switch again (the
## strike may have reached its cancel point or ended this step: the switch goes before a waiting
## tap, which then starts the new shape's first step), the press not let go yet (a tap on its
## release, the charge ring once held long enough), the charge ring, a waiting tap, then the running
## strike's frame (ShapePoses) and the last step's anticipation pose on the art.
func update(now_ms: float, _delta: float) -> void:
	if not _player_valid():
		return
	_update_switch(now_ms)
	match _phase:
		Phase.STEP:
			_advance_step(now_ms)
		Phase.CHARGE:
			_advance_charge(now_ms)
	_update_switch(now_ms)
	_update_press(now_ms)
	_update_hold(now_ms)
	_fire_queued(now_ms)
	_advance_poses(now_ms)
	_update_pose(now_ms)


## An `attack` press toward `aim` (unit, or ZERO = the facing). Nothing strikes yet: the press fires
## on its release (a tap, `_update_press`) or, held `combat.chain.chargeStartMs`, arms the charge
## ring. True when the press was taken (it waits for its release); false when it was dropped (no
## shape, dead, or in a step's wind-up, before its first active frame).
func press_attack(aim: Vector2) -> bool:
	if not _player_valid() or _current.is_empty() or _player.is_dead():
		return false
	var now := Services.now_ms()
	var toward := aim if aim != Vector2.ZERO else _player.get_facing()
	if _phase != Phase.IDLE and now - _started_ms < ShapeDefs.contact_start_ms(_data):
		return false
	# A press already waiting for its release (a click order repeats its press) keeps its time.
	if _press_ms < 0.0:
		_press_ms = now
	_press_aim = toward
	return true


## Forgets the press not let go yet and disarms the charge ring (its drawing drains), so input that is
## cleared (PlayerScript.clear_input: a window, focus loss) never reads as a release that taps or
## fires a charge. A running step or charge plays on.
func drop_press() -> void:
	_press_ms = -1.0
	_cancel_ring(true)


## The next (`step` +1) or previous (-1) learned shape, wrapping; nothing with fewer than two.
## During a strike the switch waits (`_update_switch`). A switch resets the chain ("switch").
func cycle(step: int) -> void:
	var learned := learned_shape_ids()
	if learned.size() < 2 or step == 0:
		return
	var base := _pending_switch if not _pending_switch.is_empty() else _current
	var index := learned.find(base)
	var next := learned[posmod(index + signi(step), learned.size())] if index >= 0 else learned[0]
	if is_busy():
		_pending_switch = next
		return
	_pending_switch = &""
	set_current(next)


## The current shape (&"" when none is learned).
func current_shape_id() -> StringName:
	return _current


## The learned shapes, in ShapeDefs.IDS order.
func learned_shape_ids() -> Array[StringName]:
	var learned: Array[StringName] = []
	var run := Services.run()
	for id: StringName in ShapeDefs.IDS:
		if run != null and run.has_learned_ability(String(id)):
			learned.append(id)
	return learned


## Makes `id` current (a learned shape only); resets the chain and plays the switch cue. False when
## refused.
func set_current(id: StringName) -> bool:
	if not learned_shape_ids().has(id):
		return false
	if id == _current:
		return true
	reset_chain(RESET_SWITCH)
	_current = id
	_last_shape_id = id
	_cue(SWITCH_CUES, id)
	shape_changed.emit({"shape_id": String(id)})
	return true


## True while a step or a charge owns the slime (it does not walk; player.gd drives the body with
## `step_velocity`).
func is_busy() -> bool:
	return _phase != Phase.IDLE


## True from the moment the charge ring starts to fill until the charge fires or the ring is let go
## (it fills or waits full): the slime walks at `walk_scale()` then, and the HUD's charge hint learns.
func is_charging() -> bool:
	return _ring_from_ms >= 0.0 and Services.now_ms() >= _ring_from_ms


## The share of its walk speed the slime keeps now: `combat.chain.chargeWalkScale` while charging
## (`is_charging`), else 1.
func walk_scale() -> float:
	if not is_charging():
		return 1.0
	return clampf(ShapeDefs.chain_number("chargeWalkScale"), 0.0, 1.0)


## The pose the slime holds while no strike runs: while the charge ring fills or waits full
## (`is_charging`), for a charge that plays a strike (the Spear's Lunge: spear-finisher; the Hammer's
## Quake: hammer-boom) its hold in the facing's direction (`strikes/<strike>-<direction>-hold`,
## StrikeLibrary: the frame the strike animation starts on, mirrored for left by the player's flip), so
## the release goes on from the same frame without a pop; else the shape's `load` pose (the Axe's, for
## the Spin), a base clip (ShapePoses.ring_clip) the player plays in its facing's `-down`, `-up` or
## `-side` version; "" otherwise, or when the player lacks it. player.gd's locomotion clip asks for it,
## so the slime stands and walks (at `walk_scale`) in it.
func held_pose_clip() -> String:
	if not is_charging() or not _player_valid():
		return ""
	var strike := ShapeStrikes.strike_for(ShapeDefs.short_name(_ring_shape), ShapeDefs.charge(_ring_shape))
	if not strike.is_empty():
		var direction := ShapePoses.direction_of(_player.get_facing())
		var hold := ShapeStrikes.hold_name(strike, direction)
		if ShapeStrikes.is_complete(strike, direction) and _player.strike_animation(hold) != null:
			return "%s/%s" % [ShapeStrikes.ANIMATION_LIBRARY, hold]
	var clip := ShapePoses.ring_clip(_ring_shape)
	if clip.is_empty() or _player.clip_length_ms_of(clip) <= 0.0:
		return ""
	return clip


## How full the charge ring is (0..1), or -1 while none fills.
func charge_progress() -> float:
	if not is_charging():
		return -1.0
	var ring_ms := ShapeDefs.num(ShapeDefs.charge(_ring_shape), "ringMs")
	return clampf((Services.now_ms() - _ring_from_ms) / ring_ms, 0.0, 1.0) if ring_ms > 0.0 else 1.0


## The chain step the next tap starts (1-based: 1 when a new chain starts).
func next_step_number() -> int:
	return _next_step_index(Services.now_ms()) + 1


## The slime's velocity this physics step while `is_busy()`: the step's lunge (`stepPx` over its
## `stepFromMs`..`stepToMs`), the finisher's recoil over its recovery once it hit, the Lunge's dart;
## else ZERO.
func step_velocity() -> Vector2:
	if _phase == Phase.IDLE or not _player_valid():
		return Vector2.ZERO
	var elapsed := Services.now_ms() - _started_ms
	var windup := ShapeDefs.num(_data, "windupMs")
	var active := ShapeDefs.num(_data, "activeMs")
	if _phase == Phase.CHARGE:
		var dash := ShapeDefs.num(_data, "dashPx")
		var dash_ms := ShapeDefs.num(_data, "dashMs")
		if dash > 0.0 and dash_ms > 0.0 and elapsed >= windup and elapsed < windup + dash_ms:
			return _aim * dash / (dash_ms / 1000.0)
		return Vector2.ZERO
	var step_px := ShapeDefs.num(_data, "stepPx")
	var step_from := ShapeDefs.step_from_ms(_data)
	var step_to := ShapeDefs.step_to_ms(_data)
	if step_px > 0.0 and step_to > step_from and elapsed >= step_from and elapsed < step_to:
		return _aim * step_px / ((step_to - step_from) / 1000.0)
	var move_ms := windup + active
	if _recoil_from_ms >= 0.0 and elapsed >= move_ms:
		var recovery := ShapeDefs.num(_data, "recoveryMs")
		if recovery > 0.0 and elapsed < move_ms + recovery:
			return -_aim * ShapeDefs.chain_number("finisherRecoilPx") / (recovery / 1000.0)
	return Vector2.ZERO


## Ends the chain for `reason` (BODY_SHAPES.md: hurt, death, roll, ability, mouth, stopped, switch;
## and clink): the running step or charge, a waiting tap, the link window, the charge (its ring
## drains) and, except for a switch, the press not let go yet. The rest after a finisher stays. The
## strike's drawing goes at once, except on a clink (the shape pulls back on its own), and the art
## leaves its anticipation pose and the strike's frames (the player's own clip follows).
func reset_chain(reason: String) -> void:
	var was_running := _phase != Phase.IDLE
	_close_activation()
	_phase = Phase.IDLE
	_queued = false
	_link_until_ms = -1.0
	_next_index = 0
	_recoil_from_ms = -1.0
	if reason != RESET_SWITCH:
		_press_ms = -1.0
	_cancel_ring(true)
	# The strike's frames stop; the clip that cancelled the strike (or idle and walk) takes the art.
	_poses.finish()
	_end_pose()
	if was_running and reason != RESET_CLINK and _visuals != null and is_instance_valid(_visuals):
		_visuals.clear()


## True when the current shape's next step toward `aim` (unit) would reach the hurtbox `area` from
## where the slime stands (the whole area: an arc fully swept, the Spear's line cut at walls).
func reaches(aim: Vector2, area: Area2D) -> bool:
	if not _player_valid() or _current.is_empty() or area == null or not is_instance_valid(area):
		return false
	var data := ShapeDefs.step(_current, _next_step_index(Services.now_ms()))
	if data.is_empty():
		return false
	var direction := ShapeDefs.aim_for(_current, aim if aim != Vector2.ZERO else _player.get_facing())
	if direction == Vector2.ZERO:
		return false
	var origin := _player.get_centre()
	var hit_data := _with_strike(_current, data, _poses.strike_frames_for(_current, data, direction),
		ShapePoses.direction_of(direction), ShapePoses.mirrors(direction), false)
	var reach := ShapeDefs.num(hit_data, "reach")
	if ShapeDefs.area_kind(hit_data) == ShapeDefs.AREA_LINE and ShapeDefs.line_check(_current):
		reach = ShapeStrike.wall_reach(_player, origin, direction, reach, ShapeStrike.hit_offset(hit_data))
	var sweep := _sweep_for(data, ShapeDefs.snap8(direction))
	return ShapeStrike.areas_in(_player, ShapeStrike.area_shapes(hit_data, origin, direction, reach, sweep, 1.0)).has(area)


# --- steps -----------------------------------------------------------------------------------------

## The step a tap pressed at `at` starts: the next one when the link window was still open then
## (it opens at the running step's cancel point, so a press during the step counts too), else step 1.
func _next_step_index(at: float) -> int:
	if _link_until_ms >= 0.0 and at <= _link_until_ms and _next_index < ShapeDefs.step_count(_current):
		return _next_index
	return 0


func _begin_step(index: int, toward: Vector2) -> void:
	var count := ShapeDefs.step_count(_current)
	if count <= 0:
		return
	var at := index if index >= 0 and index < count else 0
	_begin_unit(Phase.STEP, ShapeDefs.step(_current, at), toward)
	_index = at
	_link_until_ms = -1.0
	_next_index = 0
	# A ring armed meanwhile waits for this step (`_ring_start_ms`).
	_retime_ring()


## Starts a step or a charge of the current shape with `data` toward `toward`: faces and aims, cuts
## the Spear's line at walls, rolls the crit, shows its first strike frame or drawn pose (else plays
## the stand-in; the strike frames move its hit line to their socket), the swing cue and the drawing.
func _begin_unit(phase: Phase, data: Dictionary, toward: Vector2) -> void:
	_close_activation()
	_phase = phase
	_shape = _current
	_data = data
	_hit_data = data
	_index = 0
	_started_ms = Services.now_ms()
	_tick = 0
	_reset_contact()
	_set_aim(toward)
	_crit = randf() < ShapeDefs.crit_chance()
	# The wind-up's start (a charge: its release): the first strike frame or drawn pose, along the hit's aim
	# (the facing `_set_aim` just set mirrors a side one for left), else the stand-in; then the hit's numbers
	# (a chain step's reach from its strike file, in the aim's direction) and the line's wall-cut reach.
	if not _poses.begin(_shape, data, _aim):
		_player.play_animation(STAND_IN_CLIP, true)
	_hit_data = _with_strike(_shape, data, _poses.strike_id(), ShapePoses.direction_of(_aim), ShapePoses.mirrors(_aim),
		phase == Phase.CHARGE)
	_reach = _line_reach(_player.get_centre())
	_cue(SWING_CUES, _shape)
	if _visuals != null and is_instance_valid(_visuals):
		_visuals.show_step(_shape, _visual_data(), _aim, ShapeDefs.length_ms(data))


## The step's contacts, its cancel point (the link window opens, or the rest after the last step), a
## waiting tap (made before the cancel point or after it, in the link window or later: the step ends
## and `_fire_queued` starts the step the link window decides), the walk-out of steps 1-2 and the
## step's end.
func _advance_step(now: float) -> void:
	var elapsed := now - _started_ms
	_contact(now, elapsed)
	if _phase != Phase.STEP:
		return
	var last := _index >= ShapeDefs.step_count(_shape) - 1
	var cancel := ShapeDefs.cancel_ms(_data)
	if not _cancel_reached and elapsed >= cancel:
		_cancel_reached = true
		if last:
			_rest_until_ms = _started_ms + cancel + ShapeDefs.rest_ms(_shape)
			_link_until_ms = -1.0
			_next_index = 0
			_end_unit()
			return
		_link_until_ms = _started_ms + cancel + ShapeDefs.chain_number("linkMs")
		_next_index = _index + 1
	# A tap waiting for the cancel point, or let go after it while the recovery plays, fires now
	# (inside the link window it links; the Thud's recovery outlasts its window).
	if _cancel_reached and _queued and not last:
		_end_unit()
		return
	if _cancel_reached and ShapeDefs.walk_cancel(_data) and _wants_walk():
		_end_unit()
		return
	if elapsed >= ShapeDefs.length_ms(_data):
		_end_unit()


## The charge's contacts (the ticks of a charge that has them) and its end.
func _advance_charge(now: float) -> void:
	var elapsed := now - _started_ms
	var ticks := ShapeDefs.charge_ticks(_data)
	if ticks.is_empty():
		_contact(now, elapsed)
	else:
		_contact_ticks(now, elapsed, ticks)
	if _phase == Phase.CHARGE and elapsed >= ShapeDefs.length_ms(_data):
		_end_unit()


## The running unit is over: its activation closes and the slime is free. Its drawing plays out; its
## frames stop (the player plays idle or walk on this physics step, or the next step's frame shows).
func _end_unit() -> void:
	_close_activation()
	_phase = Phase.IDLE
	_poses.finish()


# --- contacts --------------------------------------------------------------------------------------

## One physics step of a step's or a non-tick charge's contact: from its first active frame its
## activation opens (a chop lands its short impact then); a line or an arc is queried every step of
## the active window (the arc as far as it swept, a chop's whole sector, the Spin round from the
## aim), an impact once, on its frame, with its ring; every new receiver is hit once; the batch's
## feel plays (the hit-stop once per swing). A clink ends the chain.
func _contact(now: float, elapsed: float) -> void:
	if _contact_done:
		return
	var start := ShapeDefs.contact_start_ms(_data)
	if elapsed < start:
		return
	var router := Services.router()
	if router == null or _hitbox == null or not is_instance_valid(_hitbox):
		_contact_done = true
		return
	if _activation == 0:
		_activation = router.begin_activation(_player, [_hitbox])
		# The contact frame (jab, thrust, chop, smash) shows before the hits, so a hit-stop freezes it.
		_poses.advance(elapsed)
		_squash_strike()
		if ShapeDefs.is_chop(_data) and _visuals != null and is_instance_valid(_visuals):
			_visuals.show_chop()
	var origin := _player.get_centre()
	var active := ShapeDefs.num(_data, "activeMs")
	var impact := ShapeDefs.impact_only(_data)
	var progress := 1.0 if impact or active <= 0.0 else clampf((elapsed - start) / active, 0.0, 1.0)
	var reach := _line_reach(origin)
	var centre := ShapeStrike.impact_centre(_hit_data, origin, _aim)
	if impact:
		_on_impact(centre)
	var mode := str(_data.get("knockMode", ShapeDefs.KNOCK_AIM))
	var shapes := ShapeStrike.area_shapes(_hit_data, origin, _aim, reach, _sweep, progress)
	var outcomes := _hit_all(ShapeStrike.targets_in(_player, shapes), _data, centre, _is_last(), _main_hold(elapsed), mode)
	if impact:
		var ring := ShapeDefs.ring_of(_data)
		if not ring.is_empty() and _activation != 0:
			outcomes.append_array(_hit_all(ShapeStrike.targets_in(_player, ShapeStrike.ring_shapes(ring, centre)), ring,
				centre, true, ShapeDefs.num(ring, "bounceMs"), ShapeDefs.KNOCK_RADIAL))
	_after_batch(outcomes, now, _data)
	if _phase == Phase.IDLE:
		return
	if impact or elapsed >= start + active:
		_contact_done = true
		_close_activation()
	if impact and _swing_hits == 0:
		# The ground smash shakes even when it hits nothing.
		var feel := Services.feel()
		if feel != null:
			feel.add_trauma(ShapeDefs.num(_data, "trauma"), _aim)


## The ticks of a charge that hits in ticks (`charge.ticks`; no charge has them since the Spin hits
## once, owner 2026-10-12) that are due: each its own activation and swing (the full circle around
## the slime), with the tick's numbers over the charge's (`damageScale`, `last`, `launchSpeed`,
## `hitStopMs`) and its hold (ShapeDefs.tick_hold_ms).
func _contact_ticks(now: float, elapsed: float, ticks: Array) -> void:
	var start := ShapeDefs.contact_start_ms(_data)
	var router := Services.router()
	while _tick < ticks.size() and _phase == Phase.CHARGE:
		var tick: Dictionary = ticks[_tick] if ticks[_tick] is Dictionary else {}
		if elapsed < start + ShapeDefs.num(tick, "atMs"):
			return
		var index := _tick
		_tick += 1
		if router == null or _hitbox == null or not is_instance_valid(_hitbox):
			continue
		var unit := _data.duplicate()
		unit.erase("ticks")
		unit.merge(tick, true)
		_reset_contact()
		_activation = router.begin_activation(_player, [_hitbox])
		if index == 0:
			_squash_strike()
		var origin := _player.get_centre()
		var shapes := ShapeStrike.area_shapes(unit, origin, _aim, 0.0, _sweep, 1.0)
		var outcomes := _hit_all(ShapeStrike.targets_in(_player, shapes), unit, origin, bool(tick.get("last", false)),
			ShapeDefs.tick_hold_ms(_data, index), str(unit.get("knockMode", ShapeDefs.KNOCK_RADIAL)))
		_after_batch(outcomes, now, unit)
		_close_activation()


## Hits every target not yet tried in this step: `data` (a step, a ring, a tick) gives the class,
## the launch and the damage scale; the knock follows `knock_mode` from `from` (the slime, or the
## Hammer's impact); the damage carries the swing's crit and the target modifiers.
func _hit_all(targets: Array[Dictionary], data: Dictionary, from: Vector2, last: bool, hold_ms: float,
		knock_mode: String) -> Array[Dictionary]:
	var outcomes: Array[Dictionary] = []
	var crit_factor := ShapeDefs.crit_multiplier() if _crit else 1.0
	var scale := ShapeDefs.num(data, "damageScale", 1.0)
	for target: Dictionary in targets:
		if _activation == 0 or not _player_valid():
			break
		var receiver: Variant = target.get("receiver")
		if not (receiver is Object) or not is_instance_valid(receiver):
			continue
		var key := (receiver as Object).get_instance_id()
		if _resolved.has(key):
			continue
		_resolved[key] = true
		var position: Vector2 = target.get("position", from)
		var knock := ShapeStrike.knock_for(knock_mode, _aim, from, position, _sweep)
		var hit := ShapeStrike.make_hit(_shape, data, _step_number(), last, hold_ms, knock)
		var tags: Array = target.get("tags", [])
		var damage := ShapeStrike.damage_for(_shape, scale, crit_factor, tags)
		outcomes.append(ShapeStrike.deliver(_player, _shape, hit, _activation, target, damage))
	return outcomes


## The feel of a batch (ShapeStrike.feel_swing: once per swing, then sparks and numbers), the
## reactions' slime recoil, the finisher's recoil once it landed, and a clink: its tick at the tip,
## the slime's recoil and the end of the chain (only while the swing has landed nothing else).
func _after_batch(outcomes: Array[Dictionary], now: float, data: Dictionary) -> void:
	if outcomes.is_empty():
		return
	var summary := ShapeStrike.feel_swing(data, outcomes, not _feel_played, _crit, _aim)
	var hits := int(summary.get("hits", 0))
	var landed := int(summary.get("landed", 0))
	if hits > 0:
		_feel_played = true
		_swing_hits += hits
	if landed > 0:
		_swing_landed += landed
		if _phase == Phase.STEP and str(_data.get("class", "")) == FINISHER_CLASS:
			_recoil_from_ms = now
	var recoil := float(summary.get("recoil_px", 0.0))
	if recoil > 0.0:
		_recoil(recoil)
	if bool(summary.get("clink", false)) and _swing_landed == 0:
		if _visuals != null and is_instance_valid(_visuals):
			_visuals.show_clink(summary.get("clink_point", _player.get_centre()))
		_recoil(ShapeDefs.chain_number("clink.recoilPx"))
		reset_chain(RESET_CLINK)


## An impact frame (the Hammer, the Quake): the crack, dust and shock ring, the impact cue, and in
## the Stone form a Heavy impact at the head (PlayerScript.record_slam: cracked ground breaks).
func _on_impact(centre: Vector2) -> void:
	if _visuals != null and is_instance_valid(_visuals):
		_visuals.show_impact(centre, ShapeDefs.num(_hit_data, "radius"), ShapeDefs.num(ShapeDefs.ring_of(_data), "radius"))
	_cue(IMPACT_CUES, _shape)
	if ShapeDefs.short_name(_shape) == HAMMER and _player.presses_plates():
		_player.record_slam(centre)


## The hit's hold at `elapsed` into the running unit (the hold formula; a charge's own rule).
func _main_hold(elapsed: float) -> float:
	if _phase == Phase.CHARGE:
		return ShapeDefs.charge_hold_ms(_data, elapsed)
	return ShapeDefs.hold_ms(_shape, _index, elapsed)


## 1-3 in a chain; 0 for a charge.
func _step_number() -> int:
	return _index + 1 if _phase == Phase.STEP else 0


## The chain's last step, or a charge (its own last hit).
func _is_last() -> bool:
	if _phase == Phase.CHARGE:
		return true
	return _index >= ShapeDefs.step_count(_shape) - 1


func _reset_contact() -> void:
	_close_activation()
	_resolved = {}
	_contact_done = false
	_feel_played = false
	_swing_hits = 0
	_swing_landed = 0
	_cancel_reached = false
	_recoil_from_ms = -1.0


func _close_activation() -> void:
	if _activation > 0:
		var router := Services.router()
		if router != null:
			router.end_activation(_activation)
	_activation = 0


# --- the press, the queue, the switch, the charge --------------------------------------------------

## The press not let go yet: let go before `combat.chain.chargeStartMs` it is a tap (`_tap`); held
## that long it arms the charge ring instead (`_arm_ring`), and nothing strikes.
func _update_press(now: float) -> void:
	if _press_ms < 0.0:
		return
	if _current.is_empty():
		_press_ms = -1.0
		return
	if not _player.is_action_held(ATTACK_ACTION):
		var pressed_at := _press_ms
		_press_ms = -1.0
		_tap(_press_aim, pressed_at, now)
	elif now - _press_ms >= ShapeDefs.chain_number("chargeStartMs"):
		_press_ms = -1.0
		_arm_ring(now)


## A tap pressed at `pressed_at`, let go now: the next chain step at once (the link window judged at
## the press), or it waits for the running step's cancel point, a charge's end or the rest.
func _tap(toward: Vector2, pressed_at: float, now: float) -> void:
	if _phase != Phase.IDLE or now < _rest_until_ms:
		_queue(toward, pressed_at)
		return
	_begin_step(_next_step_index(pressed_at), toward)


func _queue(toward: Vector2, pressed_at: float) -> void:
	_queued = true
	_queued_aim = toward
	_queued_ms = pressed_at


## A waiting tap starts its step once nothing runs and the rest is over (the link window, judged at
## its press, decides which step).
func _fire_queued(now: float) -> void:
	if not _queued or _phase != Phase.IDLE or now < _rest_until_ms or _current.is_empty():
		return
	_queued = false
	_begin_step(_next_step_index(_queued_ms), _queued_aim)


## A switch made during a strike: at the step's cancel point, or at the end of a charge (a charge
## never reaches a cancel point); at once when nothing runs. It never aborts a strike. A tap that
## waited with it survives the switch's chain reset and starts the new shape's first step (as does a
## press not let go yet).
func _update_switch(_now: float) -> void:
	if _pending_switch.is_empty():
		return
	if is_busy() and not _cancel_reached:
		return
	var id := _pending_switch
	_pending_switch = &""
	var queued := _queued
	var queued_aim := _queued_aim
	var queued_ms := _queued_ms
	if set_current(id) and queued:
		_queue(queued_aim, queued_ms)


## A hold past `chargeStartMs`: the charge ring is armed (no strike). It fills after the running step
## or charge (after the rest for a finisher).
func _arm_ring(now: float) -> void:
	if ShapeDefs.charge(_current).is_empty():
		return
	_ring_shape = _current
	_ring_from_ms = maxf(now, _ring_start_ms())
	_ring_full = false


## The armed ring: it fills over `ringMs` from `_ring_from_ms` (a chime when full); a release when
## full fires the charge, an earlier release drains it quietly (no attack, no energy).
func _update_hold(now: float) -> void:
	if _ring_from_ms < 0.0:
		return
	var charge := ShapeDefs.charge(_ring_shape)
	if _ring_shape != _current or charge.is_empty() or _player.is_swimming() or not _player.held().is_empty():
		_cancel_ring(true)
		return
	if not _player.is_action_held(ATTACK_ACTION):
		if _ring_full:
			_fire_charge()
		else:
			_cancel_ring(true)
		return
	if now < _ring_from_ms:
		return
	var ring_ms := ShapeDefs.num(charge, "ringMs")
	var progress := clampf((now - _ring_from_ms) / ring_ms, 0.0, 1.0) if ring_ms > 0.0 else 1.0
	if progress >= 1.0 and not _ring_full:
		_ring_full = true
		_player.action_cue(RING_FULL_CUE)
	if _visuals != null and is_instance_valid(_visuals):
		_visuals.show_charge(_ring_shape, progress)


## When an armed ring starts to fill: after the running step (after the rest for the last step),
## after a running charge, else after the rest.
func _ring_start_ms() -> float:
	if _phase == Phase.STEP:
		var end := _started_ms + ShapeDefs.length_ms(_data)
		if _index >= ShapeDefs.step_count(_shape) - 1:
			end = maxf(end, _started_ms + ShapeDefs.cancel_ms(_data) + ShapeDefs.rest_ms(_shape))
		return end
	if _phase == Phase.CHARGE:
		return _started_ms + ShapeDefs.length_ms(_data)
	return _rest_until_ms


## A step started after the ring was armed (a waiting tap fired first): the ring starts again after
## it, empty.
func _retime_ring() -> void:
	if _ring_from_ms < 0.0:
		return
	_ring_from_ms = maxf(_ring_from_ms, _ring_start_ms())
	_ring_full = false
	if _visuals != null and is_instance_valid(_visuals):
		_visuals.show_charge(_ring_shape, -1.0)


## The release of a full ring: the charge ends the chain; it spends its energy, or fizzles (a small
## cue and a puff, the ring drains) when the slime is short.
func _fire_charge() -> void:
	var shape := _ring_shape
	var charge := ShapeDefs.charge(shape)
	_link_until_ms = -1.0
	_next_index = 0
	if shape != _current or charge.is_empty() or _player.is_dead() or _phase != Phase.IDLE:
		_cancel_ring(true)
		return
	var energy := ShapeDefs.num(charge, "energy")
	if energy > 0.0 and not _player.spend_energy(energy):
		_cancel_ring(true)
		_player.action_cue(FIZZLE_CUE)
		var feel := Services.feel()
		if feel != null and _player.body != null:
			feel.particles(FIZZLE_PARTICLES, _player.body.global_position)
		return
	_ring_from_ms = -1.0
	_ring_full = false
	if _visuals != null and is_instance_valid(_visuals):
		_visuals.show_charge(shape, -1.0)
	# The pointer's aim from the strike's origin (the slime's centre), else the facing.
	var aim := _player.get_strike_aim()
	_begin_unit(Phase.CHARGE, charge, aim if aim != Vector2.ZERO else _player.get_facing())


## Disarms the ring; a ring already on screen drains (`gulp.rework.ringCancelMs`) when `drain`.
func _cancel_ring(drain: bool) -> void:
	if _ring_from_ms < 0.0:
		return
	var shown := Services.now_ms() >= _ring_from_ms
	_ring_from_ms = -1.0
	_ring_full = false
	if _visuals == null or not is_instance_valid(_visuals):
		return
	var constants := Services.constants()
	if drain and shown and constants != null:
		_visuals.drain_charge(float(constants.value(RING_CANCEL_PATH, 0.0)))
	else:
		_visuals.show_charge(_ring_shape, -1.0)


# --- aim, feel, parts ------------------------------------------------------------------------------

## Sets the hit's aim for `toward` (the facing when ZERO) by the shape's aim mode, faces its 8-way
## direction (the 4-way aim itself for a `snap4` shape) and sets the sweep.
func _set_aim(toward: Vector2) -> void:
	var direction := toward.normalized() if toward != Vector2.ZERO else _player.get_facing()
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	_aim = ShapeDefs.aim_for(_shape, direction)
	var eight := ShapeDefs.snap8(_aim)
	_player.face(eight)
	_sweep = _sweep_for(_data, eight)


## The sweep sign of `data` facing the 8-way `eight`: +1 for a "cw" sweep (the angle grows), -1 for
## "ccw", mirrored for left-facing strikes, so the Axe's first swing always comes down in front and a
## line's `sidePx` lies on the same side of the slime.
static func _sweep_for(data: Dictionary, eight: Vector2) -> float:
	return ShapeDefs.sweep_sign(data, eight)


## The running unit's line reach from `origin`: its hit's `reach` (a strike animation's `hit_reach`),
## cut at the first wall for the Spear (`lineCheck`); 0 for other kinds.
func _line_reach(origin: Vector2) -> float:
	if ShapeDefs.area_kind(_hit_data) != ShapeDefs.AREA_LINE:
		return 0.0
	var reach := ShapeDefs.num(_hit_data, "reach")
	if ShapeDefs.line_check(_shape):
		reach = ShapeStrike.wall_reach(_player, origin, _aim, reach, ShapeStrike.hit_offset(_hit_data))
	return reach


## The running unit's numbers for the drawing, with the wall-cut reach and the sweep sign (and the
## strike frames' keys, `_with_strike`).
func _visual_data() -> Dictionary:
	var data := _hit_data.duplicate()
	if ShapeDefs.area_kind(_data) == ShapeDefs.AREA_LINE:
		data["reach"] = _reach
	data["sweepSign"] = _sweep
	return data


## The hit's numbers of `data` (a step or charge of `shape_id`) toward `direction` ("side", "down", "up"),
## `mirrored` for a left side strike, on a copy (GameConstants' dictionary is never changed): a chain step hits
## with its strike file's `hit_reach` and `hit_center` in that direction (StrikeLibrary.chain_hit: the Axe's
## radius, the Hammer's offset, the Spear's reach, measured from the hit centre, `ShapeStrikes.HIT_CENTER_KEY`;
## game-constants.json holds none for the chain steps); a `charge` keeps its own numbers. While the strike frames
## of `strike` show ("" for none), also the strike, its direction and its mirror for the drawing, and for a line
## (the Spear) where its hit line starts (`ShapeStrikes.LINE_FROM_KEY`: the strike's socket at its contact,
## StrikeLibrary.contact_socket, in px from the slime's centre, mirrored for left: where the drawn spear's
## visible part starts; a line without that socket keeps the plain line).
func _with_strike(shape_id: StringName, data: Dictionary, strike: String, direction: String, mirrored: bool,
		charge: bool) -> Dictionary:
	var out := data.duplicate() if charge else StrikeLibrary.chain_hit(ShapeDefs.short_name(shape_id), data, direction,
		mirrored)
	if strike.is_empty():
		return out
	var resource := _strike_resource(strike, direction)
	var line := ShapeDefs.area_kind(out) == ShapeDefs.AREA_LINE
	var line_from := StrikeLibrary.contact_socket(resource, direction) if resource != null else Vector2.INF
	if line and not line_from.is_finite():
		return out
	if mirrored and line_from.is_finite():
		line_from.x = -line_from.x
	out[ShapeStrikes.STRIKE_KEY] = strike
	out[ShapeStrikes.DIRECTION_KEY] = direction
	out[ShapeStrikes.MIRRORED_KEY] = mirrored
	if line:
		out[ShapeStrikes.LINE_FROM_KEY] = line_from
	return out


## The strike's resource (StrikeLibrary) when the player plays its `strikes/<strike>-<direction>` animation; null
## otherwise.
func _strike_resource(strike: String, direction: String) -> AnimationType:
	if not _player_valid() or strike.is_empty():
		return null
	if _player.strike_animation(ShapeStrikes.animation_name(strike, direction)) == null:
		return null
	return StrikeLibrary.animation(strike)


## The running strike's frame `now` (ShapePoses: its strike animation sought on the step's clock, or the
## Spin's drawn poses and their swaps; the wind-up's start and the contact frame show theirs as they happen).
func _advance_poses(now: float) -> void:
	if _phase != Phase.IDLE:
		_poses.advance(now - _started_ms)


## The last step's anticipation pose on the slime's art (ShapeVisuals.art_pose: the pull-back and its
## squash, the spring into the strike, the chop's hop), through the player's effects channel: the
## offset through the step's active window, the scale through its wind-up (the strike squash takes the
## scale from the contact frame), softened like every squash (GameFeel.squash_scale) and by
## ShapePoses.squash_share (none of it on the strike frames). Skipped while an ability owns the channel;
## the art goes back to rest when no such step runs.
func _update_pose(now: float) -> void:
	if _phase == Phase.IDLE or ShapeDefs.anticipation(_data).is_empty() or _player.is_ability_busy():
		_end_pose()
		return
	var elapsed := now - _started_ms
	var pose := ShapeVisuals.art_pose(_data, elapsed, _aim)
	var offset: Vector2 = pose.get("offset", Vector2.ZERO)
	_player.set_effect_offset(offset)
	if elapsed < ShapeDefs.contact_start_ms(_data):
		var feel := Services.feel()
		var share := feel.squash_scale() if feel != null else 1.0
		share *= _poses.squash_share()
		_kill_squash()
		var shape: Vector2 = pose.get("scale", Vector2.ONE)
		_player.set_effect_scale(Vector2.ONE.lerp(shape, share))
	_posed = true


## The art back at rest after an anticipation pose (the strike squash, if it still plays, springs the
## scale back itself). While an ability owns the effects channel it waits (`_update_pose` asks again
## every step), so a box ability started mid-pose never leaves the art shifted.
func _end_pose() -> void:
	if not _posed:
		return
	if not _player_valid():
		_posed = false
		return
	if _player.is_ability_busy():
		return
	_posed = false
	_player.set_effect_offset(Vector2.ZERO)
	if _squash_tween == null or not _squash_tween.is_valid():
		_player.set_effect_scale(Vector2.ONE)


## The strike squash (`combat.chain.strikeSquash`) on the slime's art, through its effects channel,
## springing back over its `ms` (softened under reduce motion, skipped while an ability runs). Not on
## the Spear's strike frames: each strip is drawn at one scale, and the rigid spear under the Visual
## would squash with it (ShapePoses.shows_strike_frames).
func _squash_strike() -> void:
	if _player.is_ability_busy() or _poses.shows_strike_frames():
		return
	var squash := Vector2(ShapeDefs.chain_number("strikeSquash.x"), ShapeDefs.chain_number("strikeSquash.y"))
	var ms := ShapeDefs.chain_number("strikeSquash.ms")
	var feel := Services.feel()
	var start := SquashStretch.squash_start(squash, feel != null and feel.reduce_motion)
	_kill_squash()
	_player.set_effect_scale(start)
	var tween := _player.effect_tween()
	if tween == null or ms <= 0.0:
		_player.set_effect_scale(Vector2.ONE)
		return
	var player := _player
	tween.tween_method(func(t: float) -> void: player.set_effect_scale(start.lerp(Vector2.ONE, t)), 0.0, 1.0, ms / 1000.0)
	_squash_tween = tween


func _kill_squash() -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_squash_tween = null


## A recoil of `px` away from the aim over `combat.chain.clink.recoilMs`, through the player's own
## recoil (PlayerScript.recoil: the knockback's movement without its hurt clip; the Heavy form and
## the Slam shrug it off there).
func _recoil(px: float) -> void:
	var ms := ShapeDefs.chain_number("clink.recoilMs")
	if px <= 0.0 or ms <= 0.0:
		return
	_player.recoil(-_aim, px / (ms / 1000.0), ms)


## True when the player asks to walk (a walk key held, or a click order walking).
func _wants_walk() -> bool:
	for action: StringName in MOVE_ACTIONS:
		if _player.is_action_held(action):
			return true
	return _player.is_click_moving()


## The cue of `table` for shape `shape_id`, if any.
func _cue(table: Dictionary, shape_id: StringName) -> void:
	var cue: Variant = table.get(ShapeDefs.short_name(shape_id), &"")
	if cue is StringName and not (cue as StringName).is_empty():
		_player.action_cue(cue)


## The visuals (a child of the player body at the slime's centre) and the ShapeHitbox.
func _make_parts() -> void:
	if not _player_valid() or _player.body == null:
		return
	if _visuals == null:
		_visuals = ShapeVisuals.new()
		_visuals.name = VISUALS_NAME
		_visuals.position = FeetAnchor.local_phaser_origin(_player.body)
		_visuals.setup(_player)
		_player.body.add_child.call_deferred(_visuals)
	_hitbox = ShapeStrike.hitbox_of(_player)


func _player_valid() -> bool:
	return _player != null and is_instance_valid(_player)
