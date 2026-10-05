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
## particles, floating text, the player's input capture and real-time flash keep going). Ended in
## `_process` when real time passes `frozen_until`. Overlapping stops take the max, never add.
## Engine.time_scale is not used.
##
## The pause itself is applied deferred (end of the current frame): Phaser checks `frozen` only
## at the start of the next update, so the rest of the fixed step that triggered the stop (other
## enemies, the remaining targets of a swing) still runs, as it did there.
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")
const FloatingTextLayer := preload("res://game/feel/floating_text_layer.gd")
const ParticleFx := preload("res://game/feel/particle_fx.gd")

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

## Settings (OUT in the trial; defaults as Phaser): screenShake 0..1 and reduce motion.
var screen_shake_scale: float = 1.0
var reduce_motion: bool = false

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


## PROCESS_MODE_ALWAYS; creates the FloatingTextLayer and ParticleFx children.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_floating_text = FloatingTextLayer.new()
	_floating_text.name = "FloatingTextLayer"
	add_child(_floating_text)
	_particles = ParticleFx.new()
	_particles.name = "ParticleFx"
	add_child(_particles)


## Ends the hit-stop when `Time.get_ticks_msec() >= frozen_until`.
func _process(_delta: float) -> void:
	if _pause_held and _now_real() >= _frozen_until_real_ms:
		_set_hit_stop_pause(false)


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
func audio_cue(cue: StringName, payload: Variant = null) -> void:
	var root := _ensure_global_audio()
	if root == null:
		return
	var player := root.find_child(String(cue), true, false)
	if player == null:
		return
	if player.has_method("play_cue"):
		player.call("play_cue", payload)
	elif player is AudioStreamPlayer:
		(player as AudioStreamPlayer).play()
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).play()


# --- private ---------------------------------------------------------------------------------

func _now_real() -> float:
	return float(Time.get_ticks_msec())


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
