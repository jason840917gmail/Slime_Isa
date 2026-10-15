extends RefCounted
## The Q state machine of the rework mode (body-shapes plan section 5, the mouth table, owner's
## second version of 2026-10-11; BODY_SHAPES.md "Mouth"). What a press does depends on the mouth
## when Q goes down (`press`); something caught during a press waits for the next press:
##
## - **Empty mouth** (rows 6-8): a one-second suck burst (`gulp.rework.suckBurstMs`, Q held or not;
##   Mouth.begin_burst) that ends early on a catch; nothing in reach ends it with a puff of dust.
##   It never pulls a live enemy (only essences and liftables are suckable). After a burst,
##   `burstCooldownMs` keeps a new burst from starting, so Q cannot be mashed. **In a form**, if Q is
##   still held at `tapMs` and nothing has been caught (or is flying in), the spit ring starts
##   ("Spit out Stone"); a catch cancels it; at `spitHoldMs` the form is spat out whole, 44 px ahead
##   (GulpController.spit_out: "Ptoo!"). A swimming form over deep water says "Swim back to the
##   shallows first" once instead.
## - **A liftable** (row 1): the release throws it along the aim, however long Q was held.
## - **An essence** (rows 2-5): a tap (released before `tapMs`) spits it out whole, 44 px ahead. A
##   hold shows the swallow ring in the essence's colour ("Swallow Stone") with a rising throat
##   sound; letting go drains the ring over `ringCancelMs` and keeps the essence; at
##   `swallowHoldMs` it is swallowed (the Swallow ability; the old form's essence lands whole beside
##   the slime and stays, gulp_controller.gd). Instead of the ring: "Already Stone" once for the
##   current form's essence, "Swim back to the shallows first" once for one that cannot swim while
##   a swimming form is over deep water, and, before Swallow is learned, no ring and "It won't go
##   down yet" once at `swallowHoldMs`.
## - **Cancels** (`cancel`): a hit, knockback, death, a door or window (`clear_input`), sleep, and a
##   suppressed body (a door's leave fade, a Roll): the burst ends (a pull already in flight
##   finishes), the ring drains, the press is forgotten.
##
## While a burst or a ring runs (`roots_player`) the slime stands still and its attack, ability and
## Roll presses are dropped (player.gd `_rework_owns_step`). All times are on `Services.now_ms()`;
## the ring's drain and the sound are presentation.
##
## player.gd makes it in the rework mode (`PlayerScript.get_mouth_hold`, on first use) and calls:
## `press()` on every `eat` press, `step(now_ms, held)` every physics step while alive (instead of
## `Mouth.update`), `cancel(reason)` on the cancels above.
##
## Owner: mouth.

const Services := preload("res://game/shared/services.gd")
const Mouth := preload("res://game/player/gulp/mouth.gd")
const GulpController := preload("res://game/player/gulp/gulp_controller.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const GooRing := preload("res://game/shapes/goo_ring.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")

## What the press in progress is about, decided by the mouth when Q went down.
enum Press { NONE, EMPTY, LIFTABLE, ESSENCE }
## The hold ring that fills.
enum Ring { NONE, SWALLOW, SPIT }

## What an essence hold turned out to be at `tapMs` (the table's rows 2-5).
const VERDICT_RING := "ring"
const VERDICT_ALREADY := "already"
const VERDICT_WATER := "water"
const VERDICT_LOCKED := "locked"

## The player clip of a throw or a spit (player.gd CLIP_SPIT).
const CLIP_SPIT := "spit"
## Texts over the slime (body-shapes plan section 5).
const TEXT_SWALLOW := "Swallow %s"
const TEXT_SPIT_FORM := "Spit out %s"
const TEXT_ALREADY := "Already %s"
const TEXT_NOT_YET := "It won't go down yet"
const RING_TEXT_COLOR := &"cyan"
const MESSAGE_COLOR := &"white"
## The ring lies on the ground under the slime: flattened, behind the slime's art, and turned so
## its fill starts at the front, where it shows.
const RING_GROUND_SCALE_Y := 0.55
const RING_START_TURN := PI
## The arc the slime's 72 px art leaves visible at ringRadiusPx 30 x 0.55 (the back 26 % is hidden):
## the fill grows both ways from the front over it, so it never seems to stall behind the slime.
const RING_VISIBLE_SPAN := 1.45 * PI
const RING_NODE_NAME := "MouthRing"
## An empty burst ends with this puff of dust this far ahead along the aim.
const PUFF_PRESET := &"dodge-dust"
const PUFF_AHEAD_PX := 26.0
## The swallow ring's rising throat sound: this global cue's sound, replayed while the ring fills,
## its pitch rising from FROM to TO (a cue of its own comes with the audio pass).
const THROAT_SOURCE_CUE := &"GulpSuck"
const THROAT_PITCH_FROM := 0.75
const THROAT_PITCH_TO := 1.5
const THROAT_NODE_NAME := "MouthThroat"

## The slime (player.gd): body, face, play_action_clip, get_gulp_aim, get_centre, is_learned,
## use_ability, is_movement_suppressed.
var _player: Node
var _mouth: Mouth
var _gulp: GulpController

var _press: Press = Press.NONE
## When the press began (simulation ms).
var _press_ms: float = 0.0
## What the mouth held at the press ({} for an empty mouth).
var _press_held: Dictionary = {}
## The hold was judged at `tapMs` (the ring started, a message said, or nothing to do).
var _judged: bool = false
## An essence hold's verdict (VERDICT_*), "" before `tapMs`.
var _verdict: String = ""
## Texts said during this press (each only once).
var _said: Dictionary = {}

## A suck burst runs (until the Mouth's suck ends: a catch, its time, or a cancel).
var _burst_on: bool = false
## No new burst before this (simulation ms).
var _cooldown_until_ms: float = -INF

var _ring: Ring = Ring.NONE
var _ring_fill: float = 0.0
var _ring_view: GooRing
var _throat: AudioStreamPlayer


func setup(player: Node, mouth: Mouth, gulp: GulpController) -> void:
	_player = player
	_mouth = mouth
	_gulp = gulp


## A Q press (also while the mouth roots the slime). Ignored while a burst runs or a pull finishes;
## with an empty mouth also during the burst cooldown.
func press() -> void:
	if not _can_act():
		return
	var now := Services.now_ms()
	if _burst_on or _mouth.is_sucking():
		return
	if _press != Press.NONE:
		# Q went up and down again between two physics steps: the old press ends as a release.
		_release(now - _press_ms)
	if _mouth.is_holding():
		_press_held = _mouth.held.duplicate()
		var kind := Press.LIFTABLE
		if str(_press_held.get("kind", "")) == "essence":
			kind = Press.ESSENCE
		_begin_press(kind, now)
		return
	if now < _cooldown_until_ms:
		return
	if _mouth.begin_burst(now, _number("gulp.rework.suckBurstMs")):
		_burst_on = true
		_press_held = {}
		_begin_press(Press.EMPTY, now)


## Every physics step while alive: `held` is whether Q is still down. Runs the Mouth's burst, then
## the press in progress.
func step(now_ms: float, held: bool) -> void:
	if not _can_act():
		return
	_mouth.update(now_ms, held, _aim())
	if _burst_on:
		_follow_burst(now_ms)
	if _press == Press.NONE and not _burst_on:
		return
	if bool(_player.call(&"is_movement_suppressed")):
		cancel("suppressed")
		return
	if _press == Press.NONE:
		return
	var held_ms := now_ms - _press_ms
	if not held:
		_release(held_ms)
		return
	match _press:
		Press.EMPTY:
			_hold_empty(held_ms)
		Press.LIFTABLE:
			if not _still_holding():
				_end_press()
		Press.ESSENCE:
			_hold_essence(held_ms)


## True while a burst or a hold ring runs: the slime stands still and drops its attack, ability and
## Roll presses.
func roots_player() -> bool:
	return _burst_on or _ring != Ring.NONE


## Ends a burst or a ring for `reason` ("hit", "knockback", "death", "input-cleared", "sleep",
## "suppressed"); a pull already in flight finishes. The ring drains (at once on death).
func cancel(reason: String) -> void:
	if _ring != Ring.NONE:
		if reason == "death":
			_close_ring()
		else:
			_drain_ring()
	_stop_throat()
	if _burst_on:
		_burst_on = false
		if _mouth != null:
			_mouth.end_burst()
		_cooldown_until_ms = Services.now_ms() + _number("gulp.rework.burstCooldownMs")
	_end_press()


## The hold ring's fill, 0..1 (0 when no ring fills); for the HUD.
func ring_progress() -> float:
	return _ring_fill if _ring != Ring.NONE else 0.0


## The press in progress: "none", "empty", "liftable" or "essence" (tests and the HUD).
func press_kind() -> String:
	match _press:
		Press.EMPTY:
			return "empty"
		Press.LIFTABLE:
			return "liftable"
		Press.ESSENCE:
			return "essence"
	return "none"


## The ring that fills: "none", "swallow" or "spit".
func ring_kind() -> String:
	match _ring:
		Ring.SWALLOW:
			return "swallow"
		Ring.SPIT:
			return "spit"
	return "none"


## True while a suck burst runs.
func is_bursting() -> bool:
	return _burst_on


# --- the press ---------------------------------------------------------------------------------

func _begin_press(kind: Press, now: float) -> void:
	_press = kind
	_press_ms = now
	_judged = false
	_verdict = ""
	_said = {}


func _end_press() -> void:
	if _ring != Ring.NONE:
		_drain_ring()
	_press = Press.NONE
	_press_held = {}
	_judged = false
	_verdict = ""
	_said = {}


## Q went up `held_ms` after the press.
func _release(held_ms: float) -> void:
	match _press:
		Press.LIFTABLE:
			if _still_holding():
				_throw()
		Press.ESSENCE:
			if held_ms < _number("gulp.rework.tapMs") and _still_holding():
				_throw()
			elif _ring != Ring.NONE:
				_drain_ring()
		Press.EMPTY:
			if _ring != Ring.NONE:
				_drain_ring()
	_end_press()


## The burst after this step's Mouth update: a pull starting cancels the spit ring; the suck's end
## (a catch, or its time with nothing in reach) ends the burst and starts the cooldown.
func _follow_burst(now_ms: float) -> void:
	if _ring == Ring.SPIT and _mouth.is_pulling():
		_drain_ring()
	if _mouth.is_sucking():
		return
	_burst_on = false
	_cooldown_until_ms = now_ms + _number("gulp.rework.burstCooldownMs")
	if _mouth.is_holding():
		# Caught: it waits for the next press.
		if _press == Press.EMPTY:
			_end_press()
	else:
		_puff()


## An empty-mouth press still held: in a form, the spit ring from `tapMs` to `spitHoldMs`.
func _hold_empty(held_ms: float) -> void:
	var form := _gulp.form
	if form.is_empty():
		return # Holding changes nothing.
	var tap_ms := _number("gulp.rework.tapMs")
	var hold_ms := _number("gulp.rework.spitHoldMs")
	if _ring == Ring.SPIT:
		_fill_ring((held_ms - tap_ms) / maxf(1.0, hold_ms - tap_ms))
		if held_ms >= hold_ms:
			_spit_form()
		return
	if _judged or held_ms < tap_ms:
		return
	if _mouth.is_pulling() or _mouth.is_holding():
		return # Something is coming in: no ring.
	_judged = true
	if _gulp.held_by_water():
		_say(GulpController.SWIM_MESSAGE)
		return
	_start_ring(Ring.SPIT, form.get("color", Color.WHITE), TEXT_SPIT_FORM % str(form.get("name", "")))


## An essence press still held: judged at `tapMs`, then the swallow ring to `swallowHoldMs`.
func _hold_essence(held_ms: float) -> void:
	if not _still_holding():
		_end_press()
		return
	var tap_ms := _number("gulp.rework.tapMs")
	var hold_ms := _number("gulp.rework.swallowHoldMs")
	if _ring == Ring.SWALLOW:
		var fill := (held_ms - tap_ms) / maxf(1.0, hold_ms - tap_ms)
		_fill_ring(fill)
		_rise_throat(fill)
		if held_ms >= hold_ms:
			_swallow()
		return
	if not _judged:
		if held_ms >= tap_ms:
			_judged = true
			_judge_essence()
		return
	if _verdict == VERDICT_LOCKED and held_ms >= hold_ms:
		_say(TEXT_NOT_YET)


## Rows 2-5 at `tapMs`: the swallow ring, or the reason there is none.
func _judge_essence() -> void:
	var next := GulpForms.for_essence(str(_press_held.get("essence", "")))
	if next.is_empty():
		return
	var form_name := str(next.get("name", ""))
	if not _gulp.form.is_empty() and _gulp.form.get("id") == next.get("id"):
		_verdict = VERDICT_ALREADY
		_say(TEXT_ALREADY % form_name)
		return
	if _gulp.held_by_water() and not bool(next.get("swims", false)):
		_verdict = VERDICT_WATER
		_say(GulpController.SWIM_MESSAGE)
		return
	if not bool(_player.call(&"is_learned", AbilityDefinitions.SWALLOW)):
		_verdict = VERDICT_LOCKED
		return
	_verdict = VERDICT_RING
	_start_ring(Ring.SWALLOW, next.get("color", Color.WHITE), TEXT_SWALLOW % form_name)
	_start_throat()


# --- what a press does -------------------------------------------------------------------------

## Throws the liftable held, or spits the essence held out whole, along the aim.
func _throw() -> void:
	var aim := _aim()
	_player.call(&"face", aim)
	if _mouth.throw(aim):
		_player.call(&"play_action_clip", CLIP_SPIT)


## The swallow ring filled: the Swallow ability swallows the essence held (the swap rule in
## gulp_controller.gd).
func _swallow() -> void:
	_close_ring()
	_player.call(&"use_ability", AbilityDefinitions.SWALLOW)
	_end_press()


## The spit ring filled: the form drops out whole ahead along the aim and stays.
func _spit_form() -> void:
	_close_ring()
	_player.call(&"face", _aim())
	if _gulp.spit_out() != "nothing":
		_player.call(&"play_action_clip", CLIP_SPIT)
	_end_press()


func _puff() -> void:
	var feel := Services.feel()
	var body := _body()
	if feel != null and body != null:
		feel.particles(PUFF_PRESET, body.global_position + _aim() * PUFF_AHEAD_PX)


## `text` over the slime, once per press.
func _say(text: String, color: StringName = MESSAGE_COLOR) -> void:
	if text.is_empty() or _said.has(text):
		return
	_said[text] = true
	var feel := Services.feel()
	if feel != null:
		var centre: Vector2 = _player.call(&"get_centre")
		feel.floating_text(centre - Vector2(0.0, GulpController.MESSAGE_RISE), text, color, false)


# --- the ring and its sound ----------------------------------------------------------------------

func _start_ring(kind: Ring, color: Color, text: String) -> void:
	_ring = kind
	_ring_fill = 0.0
	var view := _ring_node()
	if view != null:
		view.set_color(color)
		view.set_radius(_number("gulp.rework.ringRadiusPx"))
		view.set_progress(0.0)
		view.show()
	_say(text, RING_TEXT_COLOR)


func _fill_ring(t: float) -> void:
	_ring_fill = clampf(t, 0.0, 1.0)
	var view := _ring_node()
	if view != null:
		view.set_progress(_ring_fill)


## Let go early: the ring drains over `ringCancelMs` and the hold is over.
func _drain_ring() -> void:
	_ring = Ring.NONE
	_ring_fill = 0.0
	_stop_throat()
	if _ring_view != null and is_instance_valid(_ring_view):
		_ring_view.drain(_number("gulp.rework.ringCancelMs"))


## The ring filled (or the slime died): it goes at once.
func _close_ring() -> void:
	_ring = Ring.NONE
	_ring_fill = 0.0
	_stop_throat()
	if _ring_view != null and is_instance_valid(_ring_view):
		_ring_view.set_progress(0.0)
		_ring_view.hide()


## The goo ring under the slime (game/shapes/goo_ring.gd), made on first use: a child of the body
## at the feet, drawn just before the slime's art, filling both ways from the front over the arc the
## art leaves visible (RING_VISIBLE_SPAN).
func _ring_node() -> GooRing:
	if _ring_view != null and is_instance_valid(_ring_view):
		return _ring_view
	var body := _body()
	if body == null:
		return null
	_ring_view = GooRing.new()
	_ring_view.name = RING_NODE_NAME
	_ring_view.scale = Vector2(1.0, RING_GROUND_SCALE_Y)
	_ring_view.rotation = RING_START_TURN
	_ring_view.fill_span = RING_VISIBLE_SPAN
	_ring_view.fill_both_ways = true
	_ring_view.visible = false
	body.add_child(_ring_view)
	var visual := _player.get(&"visual") as Node
	if visual != null and visual.get_parent() == body:
		body.move_child(_ring_view, visual.get_index())
	return _ring_view


func _start_throat() -> void:
	var feel := Services.feel()
	var body := _body()
	if feel == null or body == null:
		return
	var root := feel.global_audio()
	var source := root.find_child(String(THROAT_SOURCE_CUE), true, false) as AudioStreamPlayer if root != null else null
	if source == null or source.stream == null:
		return
	if _throat == null or not is_instance_valid(_throat):
		_throat = AudioStreamPlayer.new()
		_throat.name = THROAT_NODE_NAME
		body.add_child(_throat)
	_throat.stream = source.stream
	_throat.bus = source.bus
	_throat.volume_db = source.volume_db
	_throat.pitch_scale = THROAT_PITCH_FROM
	_throat.play()


## The throat sound rises with the ring's fill `t` and plays again while the ring fills.
func _rise_throat(t: float) -> void:
	if _throat == null or not is_instance_valid(_throat):
		return
	_throat.pitch_scale = lerpf(THROAT_PITCH_FROM, THROAT_PITCH_TO, clampf(t, 0.0, 1.0))
	if not _throat.playing:
		_throat.play()


func _stop_throat() -> void:
	if _throat != null and is_instance_valid(_throat):
		_throat.stop()


# --- helpers -------------------------------------------------------------------------------------

func _can_act() -> bool:
	return _player != null and is_instance_valid(_player) and _mouth != null and _gulp != null


## The mouth still holds what it held at the press (a hit makes it drop it).
func _still_holding() -> bool:
	return _mouth.is_holding() and str(_mouth.held.get("kind", "")) == str(_press_held.get("kind", "")) \
		and str(_mouth.held.get("essence", "")) == str(_press_held.get("essence", ""))


## Where the mouth sucks, throws and spits: the pointer's aim, else the facing.
func _aim() -> Vector2:
	var aim: Vector2 = _player.call(&"get_gulp_aim")
	return aim.normalized() if aim != Vector2.ZERO else Vector2.DOWN


func _body() -> Node2D:
	return _player.get(&"body") as Node2D if _can_act() else null


static func _number(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0
