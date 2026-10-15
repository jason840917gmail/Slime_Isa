extends Node
## Autoload `GameFeel` (Phaser `features/feel/GameFeel.ts`, `ParticlePresets.ts`, the floating
## text surface and `AudioEventBridge` global cues). Combat spec 10, 12, 13; player spec 8.
## Access: `Services.feel()`.
##
## PROCESS_MODE_ALWAYS. Creates its children in `_ready`: a FloatingTextLayer (CanvasLayer,
## screen space) and a ParticleFx (world-space Node2D, high z_index). Both run during hit-stop.
##
## Hit-stop = `Services.world().set_pause_reason(WorldService.PAUSE_HIT_STOP, true)` (tree pause:
## physics, SimClock, AnimationPlayers, tweens and every pausable script stop; camera, shake,
## particles, floating text, the player's input capture and real-time flash keep going; in the
## rework mode the particles and floating text hold too, `picture_speed` below). Ended in
## `_process` when real time passes `frozen_until`. Overlapping stops take the max, never add.
## Engine.time_scale is not used.
##
## The pause itself is applied deferred (end of the current frame): Phaser checks `frozen` only
## at the start of the next update, so the rest of the fixed step that triggered the stop (other
## enemies, the remaining targets of a swing) still runs, as it did there.
##
## Body-shapes rework (combat-feel plan section 6 "Juice"; docs/godot/BODY_SHAPES.md "Juice"): new
## functions beside the old ones, which are unchanged. `play_hit(spec, position, direction)` plays
## one swing's feel (game/feel/hit_juice.gd builds the spec): the hit-stop once per call (capped at
## `combat.chain.hitStop.capMs`), the trauma shake and the kick (world_camera.gd), the sparks in a
## cone along the hit tinted by material, the impact ring and the debris (ParticleFx), the impact
## sound at its step's pitch (+-3 %) plus the material and thump cues, the white-then-tint flash of
## any sprites it is given, and the damage number (small and white, or big and yellow with a pop;
## only with the Damage numbers setting). `add_trauma`, `kick`, `room_clear` (a freeze, then a
## stutter slow motion through the hit-stop reason, and a music dip when MusicDirector has one),
## `flash_hit`, `burst`, `show_damage_number` and `squash_scale` / `jitter_allowed` (for the hit
## motion) are public too. Reduce motion turns off every freeze, shake, kick and stutter and plays
## the squash at REDUCED_SQUASH_SCALE; the screen-shake slider scales the trauma and the kick. Each
## layer also has a dev switch and a demo (HitJuice.LAYERS; the juice panel, made the first time the
## rework mode is on; the demo's exaggerated replays use `room_clear_scaled` and
## `show_damage_number_scaled`). `audio_cue` reads a "pitch" key in a Dictionary payload
## (CUE_PITCH_KEY).
## In the rework mode a hit-stop holds the whole picture: the tree pause stops the slime, the victims,
## their AnimationPlayers, tweens and particles, SimClock and the shapes' drawing, and `picture_speed`
## also holds this node's own real-time pictures (the ParticleFx bursts and the floating numbers) at
## FROZEN_PICTURE_SPEED, and slows them to the stutter's share during the room clear's slow motion.
## The camera's shake and kick, the victim's jitter and the white flash keep real time on purpose
## (they are how the freeze reads). With the mode off the bursts and numbers run through every freeze
## as before.
##
## Owner: combat builder (the rework juice: juice).

const Services := preload("res://game/shared/services.gd")
const FloatingTextLayer := preload("res://game/feel/floating_text_layer.gd")
const ParticleFx := preload("res://game/feel/particle_fx.gd")
const HitJuice := preload("res://game/feel/hit_juice.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const JuiceDevPanel := preload("res://game/feel/juice_dev_panel.gd")

## GameFeel.ts:35-51 presets: event -> {"shake_ms", "intensity", "hit_stop_ms"}.
## Presentation values owned here (as in Phaser), not balance.
const PRESETS := {
	&"hit": {"shake_ms": 0.0, "intensity": 0.0, "hit_stop_ms": 65.0},
	&"critical-hit": {"shake_ms": 80.0, "intensity": 0.006, "hit_stop_ms": 95.0},
	&"combo-finisher": {"shake_ms": 120.0, "intensity": 0.008, "hit_stop_ms": 100.0},
	&"slam": {"shake_ms": 150.0, "intensity": 0.01, "hit_stop_ms": 90.0},
	&"player-hurt": {"shake_ms": 110.0, "intensity": 0.005, "hit_stop_ms": 70.0},
	&"boss-landing": {"shake_ms": 100.0, "intensity": 0.003, "hit_stop_ms": 0.0},
	&"boss-defeated": {"shake_ms": 450.0, "intensity": 0.012, "hit_stop_ms": 180.0},
	&"player-defeated": {"shake_ms": 400.0, "intensity": 0.012, "hit_stop_ms": 150.0},
	&"ground-crack": {"shake_ms": 260.0, "intensity": 0.012, "hit_stop_ms": 0.0},
	&"building-restored": {"shake_ms": 320.0, "intensity": 0.006, "hit_stop_ms": 0.0},
}
## Floating text palette (FloatingTextSurfacePort.ts:10-11).
const TEXT_COLORS := {
	&"white": Color("#ffffff"), &"yellow": Color("#ffdf8a"), &"orange": Color("#ffad66"),
	&"green": Color("#7be08a"), &"red": Color("#ff6f88"), &"cyan": Color("#72d8ff"),
	&"blue": Color("#4a90e2"),
}
## Scene id of the global cue scene (audio/global.scene.json: AudioStreamPlayers named Dodge,
## Respawn, Crit, AbilityDenied, ...).
const GLOBAL_AUDIO_SCENE_ID := "audio.global"
## WorldService.PAUSE_HIT_STOP (repeated so this file does not depend on the world service type).
const PAUSE_HIT_STOP := &"hit-stop"
## The rework's default sparks preset and the damage number's rise above the struck point.
const HIT_SPARK_PRESET := &"hit-spark"
const HIT_NUMBER_RISE_PX := 30.0
## The Hammer's ground dust (spec "dust").
const DUST_PRESET := &"dodge-dust"
## Reduce motion plays the rework's squash and stretch at this share (combat-feel plan section 6
## "Reduce motion": squash at 35 %; presentation).
const REDUCED_SQUASH_SCALE := 0.35
## A Dictionary payload's keys for the cue's pitch multiplier and its randomness for that play
## (rework; the same keys as game/runtime/sfx_player.gd PAYLOAD_PITCH / PAYLOAD_PITCH_RANDOMNESS).
const CUE_PITCH_KEY := "pitch"
const CUE_PITCH_RANDOMNESS_KEY := "pitch_randomness"
## The stutter slow motion steps first in every physics step (before SimClock's -1000), so a paused
## step stops the whole step.
const STUTTER_PHYSICS_PRIORITY := -1001
## Rework (presentation): the speed of this node's own pictures (bursts, numbers) while a hit-stop
## freezes the tree. Not 0: a CPUParticles2D burst started on the frozen frame spawns only when its
## time moves, so it shows at the struck point and barely moves until the freeze ends.
const FROZEN_PICTURE_SPEED := 0.08

## Settings (OUT in the trial; defaults as Phaser): screenShake 0..1 and reduce motion.
var screen_shake_scale: float = 1.0
var reduce_motion: bool = false
## The "Damage numbers" setting (GameSettings `damage_numbers`, on by default): rework hits show
## their damage only while it is on (`play_hit`). The old damage numbers do not read it.
var show_damage_numbers: bool = true

var _frozen_until_real_ms: float = 0.0
var _floating_text: FloatingTextLayer
var _particles: ParticleFx
var _global_audio: Node
## True once the global audio scene was found missing (no repeated lookups / errors).
var _global_audio_missing: bool = false
## A deferred pause request is queued.
var _pause_queued: bool = false
## This node currently holds the hit-stop pause reason.
var _pause_held: bool = false
## Rework room-clear stutter: its real-ms window, its step pattern, the steps counted so far and
## whether it holds the hit-stop pause reason now.
var _stutter_from_ms: float = 0.0
var _stutter_until_ms: float = 0.0
var _stutter_paused_steps: int = 0
var _stutter_cycle_steps: int = 1
var _stutter_step: int = 0
var _stutter_held: bool = false
## The juice dev panel (rework mode only; made the first time the mode is on).
var _dev_panel: JuiceDevPanel


## PROCESS_MODE_ALWAYS; creates the FloatingTextLayer and ParticleFx children. The physics step
## (the rework's stutter) sleeps until `room_clear` wakes it.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_floating_text = FloatingTextLayer.new()
	_floating_text.name = "FloatingTextLayer"
	add_child(_floating_text)
	_particles = ParticleFx.new()
	_particles.name = "ParticleFx"
	add_child(_particles)
	process_physics_priority = STUTTER_PHYSICS_PRIORITY
	set_physics_process(false)


## Ends the hit-stop when `Time.get_ticks_msec() >= frozen_until`. Rework: hands `picture_speed` to
## the bursts and the floating numbers (before they process: they are children), and makes the juice
## dev panel the first time the rework mode is on.
func _process(_delta: float) -> void:
	if _pause_held and _now_real() >= _frozen_until_real_ms:
		_set_hit_stop_pause(false)
	var speed := picture_speed()
	if _particles != null:
		_particles.set_picture_speed(speed)
	if _floating_text != null:
		_floating_text.set_picture_speed(speed)
	if _dev_panel == null and ReworkMode.is_on():
		_dev_panel = JuiceDevPanel.new()
		_dev_panel.name = "JuiceDevPanel"
		add_child(_dev_panel)


## Rework room-clear stutter (awake only during one): `combat.roomClear.slowPausedSteps` of every
## `slowCycleSteps` physics steps hold the hit-stop pause reason; a running hit-stop owns the pause
## meanwhile.
func _physics_process(_delta: float) -> void:
	var now := _now_real()
	if now >= _stutter_until_ms:
		_end_stutter()
		return
	if now < _stutter_from_ms or is_frozen() or _pause_queued or _pause_held:
		return
	var paused := (_stutter_step % _stutter_cycle_steps) < _stutter_paused_steps
	_stutter_step += 1
	_set_stutter_pause(paused)


## `GameFeel.play(event)`: shake(preset) then hit_stop(preset). Unknown events are ignored.
func play(event: StringName) -> void:
	if not PRESETS.has(event):
		return
	var preset: Dictionary = PRESETS[event]
	shake(float(preset["shake_ms"]), float(preset["intensity"]))
	hit_stop(float(preset["hit_stop_ms"]))


## Skipped when ms <= 0, intensity <= 0 or the shake scale is 0 (reduce motion); else
## `Services.world().camera.shake(ms, intensity * screen_shake_scale)` (the camera ignores a
## new shake while one runs).
func shake(duration_ms: float, intensity: float) -> void:
	var scale := 0.0 if reduce_motion else screen_shake_scale
	if duration_ms <= 0.0 or intensity <= 0.0 or scale <= 0.0:
		return
	var world := Services.world()
	if world == null or world.camera == null or not is_instance_valid(world.camera):
		return
	world.camera.shake(duration_ms, intensity * scale)


## Skipped under reduce motion; `frozen_until = max(frozen_until, now_real + ms)` and pause the
## tree with the hit-stop reason.
func hit_stop(duration_ms: float) -> void:
	if duration_ms <= 0.0 or reduce_motion or not is_finite(duration_ms):
		return
	_frozen_until_real_ms = maxf(_frozen_until_real_ms, _now_real() + duration_ms)
	if not _pause_held and not _pause_queued:
		_pause_queued = true
		_apply_queued_pause.call_deferred()


## True while a hit-stop is active.
func is_frozen() -> bool:
	return _now_real() < _frozen_until_real_ms


# --- body-shapes rework (docs/godot/BODY_SHAPES.md "Juice"; combat-feel plan section 6) ----------
# Additive: the old functions above are unchanged.

## One swing's feel at `world_position` along `direction` (unit; ZERO = none). `spec`
## (game/feel/hit_juice.gd): "hit_stop_ms" (absent: the "hit" preset's), "trauma", "kick_px",
## "sparks" (a count), "spark_preset", "tint" (the sparks' colour), "pitch", "sound_cue",
## "number", "number_big", and optionally "impact_ring", "debris_preset" / "debris_tint" /
## "debris_scale", "dust", "material_cue", "thump_cue", and "flash_visuals" (CanvasItems to flash
## white-then-tint, with "flash_big" and "flash_tint"). Order: the freeze (once per call, capped at
## `combat.chain.hitStop.capMs`; none under reduce motion), the trauma and the kick (none under
## reduce motion, scaled by the shake slider), the flash, the particles, the sounds (the impact cue
## at "pitch" +-HitJuice.PITCH_VARIANCE, the material and thump cues as they are), then the number
## (only with `show_damage_numbers`). Each layer follows its HitJuice dev switch.
func play_hit(spec: Dictionary, world_position: Vector2, direction: Vector2) -> void:
	var dir := direction.normalized() if direction.is_finite() and direction != Vector2.ZERO else Vector2.ZERO
	if HitJuice.layer_on(HitJuice.LAYER_FREEZE):
		var stop_ms := float(spec.get("hit_stop_ms", (PRESETS[&"hit"] as Dictionary)["hit_stop_ms"]))
		hit_stop(minf(stop_ms, _hit_stop_cap_ms()))
	add_trauma(float(spec.get("trauma", 0.0)), dir)
	kick(float(spec.get("kick_px", 0.0)), dir)
	var visuals: Variant = spec.get("flash_visuals", [])
	if visuals is Array:
		var tint_value: Variant = spec.get("flash_tint", HitFlash.HURT_TINT)
		var flash_tint: Color = tint_value if tint_value is Color else HitFlash.HURT_TINT
		for visual: Variant in visuals:
			if visual is CanvasItem:
				flash_hit(visual as CanvasItem, bool(spec.get("flash_big", false)), flash_tint)
	_play_hit_particles(spec, world_position, dir)
	_play_hit_sounds(spec)
	var number := int(spec.get("number", 0))
	if number > 0:
		show_damage_number(world_position - Vector2(0.0, HIT_NUMBER_RISE_PX), number, bool(spec.get("number_big", false)))


## Adds camera trauma (0..1 per call; the camera caps the sum at 1) along `direction` (the axis of
## the shake's directional share; ZERO = none): `WorldCamera.add_trauma`, scaled by the shake
## slider (`screen_shake_scale`). It adds to the old shake, which keeps running on its own. Nothing
## under reduce motion, with the slider at 0 or the trauma switch off.
func add_trauma(amount: float, direction: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0.0 or not is_finite(amount) or reduce_motion or screen_shake_scale <= 0.0:
		return
	if not HitJuice.layer_on(HitJuice.LAYER_TRAUMA):
		return
	var camera := _camera()
	if camera != null:
		camera.add_trauma(amount * screen_shake_scale, direction)


## The camera kick: the picture jolts `px` screen px along `direction` and eases back
## (`WorldCamera.kick`), scaled by the shake slider. Nothing under reduce motion, without a
## direction or with the kick switch off.
func kick(px: float, direction: Vector2) -> void:
	if px <= 0.0 or not is_finite(px) or reduce_motion or screen_shake_scale <= 0.0:
		return
	if direction == Vector2.ZERO or not HitJuice.layer_on(HitJuice.LAYER_KICK):
		return
	var camera := _camera()
	if camera != null:
		camera.kick(px * screen_shake_scale, direction)


## The room-clear moment (dungeon rooms, ambushes, bosses; `combat.roomClear`): the music drops
## `musicDropDb` for `musicDropMs` (when MusicDirector has `dip(db, ms)`), then a `freezeMs` freeze,
## then `slowMs` of stutter slow motion (`slowPausedSteps` of every `slowCycleSteps` physics steps
## paused with the hit-stop reason). Reduce motion keeps only the music drop.
func room_clear() -> void:
	room_clear_scaled(1.0)


## `room_clear` with every length (the music drop's, the freeze's, the stutter's) x `length_scale`
## (the juice panel's shown replay; 1 = the real one).
func room_clear_scaled(length_scale: float) -> void:
	var constants := Services.constants()
	if constants == null:
		return
	var scale := length_scale if is_finite(length_scale) and length_scale > 0.0 else 1.0
	_dip_music(constants.number("combat.roomClear.musicDropDb"), constants.number("combat.roomClear.musicDropMs") * scale)
	if reduce_motion:
		return
	var freeze_ms := 0.0
	if HitJuice.layer_on(HitJuice.LAYER_FREEZE):
		freeze_ms = maxf(0.0, constants.number("combat.roomClear.freezeMs")) * scale
		hit_stop(freeze_ms)
	if not HitJuice.layer_on(HitJuice.LAYER_SLOWMO):
		return
	var cycle := maxi(1, constants.integer("combat.roomClear.slowCycleSteps"))
	_stutter_cycle_steps = cycle
	_stutter_paused_steps = clampi(constants.integer("combat.roomClear.slowPausedSteps"), 0, cycle - 1)
	_stutter_from_ms = _now_real() + freeze_ms
	_stutter_until_ms = _stutter_from_ms + maxf(0.0, constants.number("combat.roomClear.slowMs")) * scale
	_stutter_step = 0
	set_physics_process(true)


## True while the room-clear stutter runs.
func is_stuttering() -> bool:
	return is_physics_processing() and _now_real() < _stutter_until_ms


## Rework (presentation): how fast this node's own real-time pictures (the ParticleFx bursts, the
## floating numbers) run now, so a hit-stop holds them with the world: FROZEN_PICTURE_SPEED while a
## hit-stop freezes the tree, the share of running physics steps during the room clear's stutter
## (after its freeze), else 1. Always 1 with the rework mode off (they run through every freeze, as
## before), and through every other pause (menus).
func picture_speed() -> float:
	if not ReworkMode.is_on():
		return 1.0
	if is_frozen():
		return FROZEN_PICTURE_SPEED
	if is_stuttering() and _now_real() >= _stutter_from_ms:
		var cycle := maxi(1, _stutter_cycle_steps)
		return float(cycle - clampi(_stutter_paused_steps, 0, cycle - 1)) / float(cycle)
	return 1.0


## The rework's white-then-tint flash of a struck sprite (combat-feel plan section 6 "Flash":
## `HitFlash.flash_curve`, real time): taps white for one frame then `tint` fades over 90 ms; `big`
## (finishers, charges, the Hammer, the Slam) white for 50 ms then 120 ms. Off with the flash switch.
func flash_hit(visual: CanvasItem, big: bool = false, tint: Color = HitFlash.HURT_TINT) -> void:
	if not HitJuice.layer_on(HitJuice.LAYER_FLASH):
		return
	HitFlash.flash_curve(visual, tint, big)


## One particle burst with the rework's options (ParticleFx.emit_burst): `direction` (a cone along
## it), `tint` and `count_scale`. Not switched: `play_hit` checks the sparks switch itself.
func burst(preset: StringName, world_position: Vector2, direction: Vector2 = Vector2.ZERO,
		tint: Color = Color.WHITE, count_scale: float = 1.0) -> void:
	if _particles == null:
		return
	_particles.emit_burst(preset, world_position, direction, tint, count_scale)


## A rework damage number at `world_position` (combat-feel plan section 6 "Number";
## `combat.damageNumbers`): small in `smallColor`, or big in `bigColor` popping from `popScale` to
## 1.0 over `popMs`. Only with the Damage numbers setting (`show_damage_numbers`) and its switch.
func show_damage_number(world_position: Vector2, damage: int, big: bool) -> void:
	show_damage_number_scaled(world_position, damage, big, 1.0)


## `show_damage_number` with the number's pop and its life x `length_scale` (the juice panel's shown
## replay; 1 = the real one, with the text layer's own lengths).
func show_damage_number_scaled(world_position: Vector2, damage: int, big: bool, length_scale: float) -> void:
	if damage <= 0 or not show_damage_numbers or _floating_text == null:
		return
	if not HitJuice.layer_on(HitJuice.LAYER_NUMBERS):
		return
	var scale := length_scale if is_finite(length_scale) and length_scale > 0.0 else 1.0
	var life_ms := -1.0
	if not is_equal_approx(scale, 1.0):
		life_ms = (FloatingTextLayer.BIG_DURATION_MS if big else FloatingTextLayer.SMALL_DURATION_MS) * scale
	var constants := Services.constants()
	var key := "combat.damageNumbers.%s" % ("bigColor" if big else "smallColor")
	var color_name := StringName(str(constants.value(key, "")) if constants != null else "")
	var tint: Color = TEXT_COLORS.get(color_name, TEXT_COLORS[&"yellow"] if big else TEXT_COLORS[&"white"])
	if not big:
		_floating_text.spawn(world_position, str(damage), tint, false, life_ms)
		return
	var pop_scale := float(constants.value("combat.damageNumbers.popScale", 1.0)) if constants != null else 1.0
	var pop_ms := float(constants.value("combat.damageNumbers.popMs", 0.0)) if constants != null else 0.0
	_floating_text.spawn_pop(world_position, str(damage), tint, true, pop_scale, pop_ms * scale, life_ms)


## The share of the rework's squash and stretch the hit motion plays (EnemyHitMotion): 0 with the
## squash switch off, REDUCED_SQUASH_SCALE under reduce motion, else 1.
func squash_scale() -> float:
	if not HitJuice.layer_on(HitJuice.LAYER_SQUASH):
		return 0.0
	return REDUCED_SQUASH_SCALE if reduce_motion else 1.0


## True when a frozen victim may jitter (EnemyHitMotion): the jitter switch is on and reduce motion
## is off (no freeze then, so no jitter).
func jitter_allowed() -> bool:
	return HitJuice.layer_on(HitJuice.LAYER_JITTER) and not reduce_motion


## Whether the juice `layer` (HitJuice.LAYERS) is switched on; always true outside the rework mode.
func juice_layer_on(layer: StringName) -> bool:
	return HitJuice.layer_on(layer)


## World-space floating text (combat spec 12): `color` is a TEXT_COLORS key; big = 22 px,
## 900 ms, rise 48; small = 15 px, 700 ms, rise 34; real-time clock; pool of 24.
## `duration_ms < 0` uses the default for the size.
func floating_text(world_position: Vector2, text: String, color: StringName = &"white", big: bool = false, duration_ms: float = -1.0) -> void:
	if _floating_text == null:
		return
	var tint: Color = TEXT_COLORS.get(color, TEXT_COLORS[&"white"])
	_floating_text.spawn(world_position, text, tint, big, duration_ms)


## One-shot particle burst (combat spec 13 / player spec 8): presets "hit-spark",
## "slime-splash", "dodge-dust", "boss-burst" at a world position.
func particles(preset: StringName, world_position: Vector2) -> void:
	if _particles == null:
		return
	_particles.emit_burst(preset, world_position)


## Global audio cue (Phaser AudioEventBridge): mounts `audio.global` once (lazily, under this
## node) and calls `play_cue(payload)` on its AudioStreamPlayer named `cue` (e.g. "Dodge",
## "Respawn", "Crit", "AbilityDenied"). Missing scene or cue -> silently ignored.
## Rework: a Dictionary payload with a CUE_PITCH_KEY number plays the cue at that pitch multiplier,
## and its CUE_PITCH_RANDOMNESS_KEY replaces the cue's own randomness (the cue players,
## game/runtime/sfx_player.gd, read both; a plain player gets the pitch here). No old payload carries
## the keys, so every old cue plays as before.
func audio_cue(cue: StringName, payload: Variant = null) -> void:
	var root := _ensure_global_audio()
	if root == null:
		return
	var player := root.find_child(String(cue), true, false)
	if player == null:
		return
	if player.has_method("play_cue"):
		player.call("play_cue", payload)
		return
	var pitch := _payload_pitch(payload)
	if pitch != 1.0:
		_set_plain_pitch(player, pitch)
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).play()
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).play()


## The mounted `audio.global` scene (its `Effects/<Cue>` players), or null without one. The sound
## audition (game/dev/sound_audition.gd) swaps their takes.
func global_audio() -> Node:
	return _ensure_global_audio()


## Stops a global cue started with `audio_cue` (a loop such as "SleepBreath"; Phaser
## `GlobalAudioCuePort.stop`). Missing cue -> silently ignored.
func stop_audio_cue(cue: StringName) -> void:
	var root := _ensure_global_audio()
	if root == null:
		return
	var player := root.find_child(String(cue), true, false)
	if player == null:
		return
	if player.has_method("stop_cue"):
		player.call("stop_cue")
	elif player is AudioStreamPlayer:
		(player as AudioStreamPlayer).stop()
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).stop()


# --- private ---------------------------------------------------------------------------------

func _now_real() -> float:
	return float(Time.get_ticks_msec())


## The world camera, or null without a world.
func _camera() -> WorldCamera:
	var world := Services.world()
	if world == null or world.camera == null or not is_instance_valid(world.camera):
		return null
	return world.camera


## `combat.chain.hitStop.capMs` (no cap without it).
func _hit_stop_cap_ms() -> float:
	var constants := Services.constants()
	var cap: Variant = constants.value("combat.chain.hitStop.capMs", INF) if constants != null else INF
	return float(cap) if typeof(cap) == TYPE_FLOAT or typeof(cap) == TYPE_INT else INF


## `play_hit`'s particles (sparks switch): the sparks scaled to the spec's count, the impact ring,
## the material debris and the Hammer's dust.
func _play_hit_particles(spec: Dictionary, world_position: Vector2, direction: Vector2) -> void:
	if _particles == null or not HitJuice.layer_on(HitJuice.LAYER_SPARKS):
		return
	var sparks := int(spec.get("sparks", 0))
	if sparks > 0:
		var preset := StringName(str(spec.get("spark_preset", HIT_SPARK_PRESET)))
		var base := ParticleFx.preset_count(preset)
		burst(preset, world_position, direction, _color(spec.get("tint"), Color.WHITE),
			float(sparks) / float(base) if base > 0 else 1.0)
	if bool(spec.get("impact_ring", false)):
		burst(HitJuice.IMPACT_RING_PRESET, world_position)
	var debris := StringName(str(spec.get("debris_preset", "")))
	if not debris.is_empty():
		burst(debris, world_position, direction, _color(spec.get("debris_tint"), Color.WHITE),
			float(spec.get("debris_scale", 1.0)))
	if bool(spec.get("dust", false)):
		burst(DUST_PRESET, world_position)


## `play_hit`'s sounds: the impact cue at the spec's pitch with HitJuice.PITCH_VARIANCE in place of
## the cue's own randomness (with the pitch switch off: as the cue always plays), then the material
## and thump cues as they are. Missing cues are silent.
func _play_hit_sounds(spec: Dictionary) -> void:
	var cue := StringName(str(spec.get("sound_cue", "")))
	if not cue.is_empty():
		var pitch := float(spec.get("pitch", 1.0))
		if HitJuice.layer_on(HitJuice.LAYER_PITCH) and is_finite(pitch) and pitch > 0.0:
			audio_cue(cue, {CUE_PITCH_KEY: pitch, CUE_PITCH_RANDOMNESS_KEY: HitJuice.PITCH_VARIANCE})
		else:
			audio_cue(cue)
	for key: String in ["material_cue", "thump_cue"]:
		var extra := StringName(str(spec.get(key, "")))
		if not extra.is_empty():
			audio_cue(extra)


static func _color(value: Variant, fallback: Color) -> Color:
	return value if value is Color else fallback


## The music drop of a room clear, when MusicDirector offers one (`dip(db, duration_ms)`).
func _dip_music(db: float, duration_ms: float) -> void:
	if db <= 0.0 or duration_ms <= 0.0:
		return
	var music := Services.music()
	if music != null and music.has_method(&"dip"):
		music.call(&"dip", db, duration_ms)


## Holds (or releases) the hit-stop pause reason for one stutter step.
func _set_stutter_pause(active: bool) -> void:
	_stutter_held = active
	var world := Services.world()
	if world != null:
		world.set_pause_reason(PAUSE_HIT_STOP, active)
	elif is_inside_tree():
		get_tree().paused = active


## Ends the stutter: the pause reason goes back unless a hit-stop holds it.
func _end_stutter() -> void:
	set_physics_process(false)
	if _stutter_held and not _pause_held and not _pause_queued and not is_frozen():
		_set_stutter_pause(false)
	_stutter_held = false


## A Dictionary payload's CUE_PITCH_KEY as a positive finite number, else 1.0.
static func _payload_pitch(payload: Variant) -> float:
	if not (payload is Dictionary) or not (payload as Dictionary).has(CUE_PITCH_KEY):
		return 1.0
	var raw: Variant = (payload as Dictionary)[CUE_PITCH_KEY]
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return 1.0
	var pitch := float(raw)
	return pitch if is_finite(pitch) and pitch > 0.0 else 1.0


## A plain cue player (no `play_cue`) plays at its first pitch (remembered in a meta) x `pitch`.
static func _set_plain_pitch(player: Node, pitch: float) -> void:
	if not (player is AudioStreamPlayer or player is AudioStreamPlayer2D):
		return
	if not player.has_meta(&"feel_base_pitch"):
		player.set_meta(&"feel_base_pitch", float(player.get(&"pitch_scale")))
	player.set(&"pitch_scale", float(player.get_meta(&"feel_base_pitch")) * pitch)


func _apply_queued_pause() -> void:
	_pause_queued = false
	if _now_real() < _frozen_until_real_ms:
		_set_hit_stop_pause(true)


func _set_hit_stop_pause(active: bool) -> void:
	_pause_held = active
	var world := Services.world()
	if world != null:
		world.set_pause_reason(PAUSE_HIT_STOP, active)
	elif is_inside_tree():
		get_tree().paused = active


## Mounts the global audio scene (`audio.global`) now instead of on the first cue, so the
## first dodge or hit does not stall on loading it. Safe to call more than once.
func warm_up() -> void:
	_ensure_global_audio()


func _ensure_global_audio() -> Node:
	if _global_audio != null and is_instance_valid(_global_audio):
		return _global_audio
	if _global_audio_missing:
		return null
	var world := Services.world()
	if world == null:
		return null
	if world.scene_path(GLOBAL_AUDIO_SCENE_ID).is_empty():
		_global_audio_missing = true
		return null
	var instance := world.instantiate_scene(GLOBAL_AUDIO_SCENE_ID)
	if instance == null:
		_global_audio_missing = true
		return null
	instance.name = "GlobalAudio"
	add_child(instance)
	_global_audio = instance
	return _global_audio
