extends AudioStreamPlayer2D
## Positional audio cue player the scene converter attaches to every
## AudioStreamPlayer2D (runtime spec section 4.12). Same cue rules as
## `sfx_player.gd`, plus:
##
## - `detached`: a one-shot outlives its node (death and pickup sounds). Each
##   play spawns a one-shot clone at the node's global position under the tree
##   root, which frees itself when done; `max_polyphony` caps the live clones.
## - `pan_distance`: Phaser pans `(x − camera_x) / pan_distance` (clamped ±1).
##   Godot pans `dx / viewport_width · panning_strength · 2d_panning_strength`,
##   so `panning_strength` is set at each play to match. Attenuation is already
##   Phaser's linear `1 − d / max_distance` (`attenuation = 1`).
##
## Owner: converter builder.

const CueRules := preload("res://game/runtime/audio_cue_rules.gd")

@export var pitch_randomness: float = 0.0
@export var min_interval_ms: float = 0.0
@export var payload_filter: String = ""
@export var loop: bool = false
@export var autoplay_cue: bool = false
@export var detached: bool = false
@export var pan_distance: float = 400.0

var _base_pitch: float = 1.0
var _last_accepted_ms: int = -1
var _loop_wanted: bool = false
var _prepared: bool = false
var _clones: Array[AudioStreamPlayer2D] = []


func _ready() -> void:
	_prepare()
	if autoplay_cue:
		play_cue()


func _enter_tree() -> void:
	if _prepared and loop and _loop_wanted and not playing:
		play()


func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	_base_pitch = pitch_scale
	if loop and stream != null:
		stream = CueRules.looping_copy(stream)


## Plays the cue if `payload` passes the filter (JSON handler `play`).
func play_cue(payload: Variant = null) -> void:
	if not CueRules.payload_matches(payload_filter, payload):
		return
	_prepare()
	_update_panning()
	if loop:
		_loop_wanted = true
		if not playing:
			play()
		return
	var now := CueRules.now_ms()
	if min_interval_ms > 0.0 and _last_accepted_ms >= 0 and now - _last_accepted_ms < int(min_interval_ms):
		return
	_last_accepted_ms = now
	var pitch := CueRules.randomized_pitch(_base_pitch, pitch_randomness)
	if detached and is_inside_tree():
		_play_detached(pitch)
		return
	pitch_scale = pitch
	play()


## Stops every voice (and live detached clones) if `payload` passes the filter.
func stop_cue(payload: Variant = null) -> void:
	if not CueRules.payload_matches(payload_filter, payload):
		return
	_loop_wanted = false
	stop()
	for clone in _clones:
		if is_instance_valid(clone):
			clone.queue_free()
	_clones.clear()


func _play_detached(pitch: float) -> void:
	var live: Array[AudioStreamPlayer2D] = []
	for existing in _clones:
		if is_instance_valid(existing) and not existing.is_queued_for_deletion():
			live.append(existing)
	_clones = live
	while _clones.size() >= maxi(1, max_polyphony):
		var oldest: AudioStreamPlayer2D = _clones.pop_front()
		oldest.queue_free()
	var clone := AudioStreamPlayer2D.new()
	clone.name = "%sDetached" % name
	clone.stream = stream
	clone.volume_db = volume_db
	clone.pitch_scale = pitch
	clone.bus = bus
	clone.max_distance = max_distance
	clone.attenuation = attenuation
	clone.panning_strength = panning_strength
	clone.process_mode = Node.PROCESS_MODE_ALWAYS
	clone.autoplay = true
	clone.finished.connect(clone.queue_free)
	clone.position = global_position
	_clones.append(clone)
	get_tree().root.add_child.call_deferred(clone)


func _update_panning() -> void:
	if not is_inside_tree() or pan_distance <= 0.0:
		return
	var viewport_width := get_viewport().get_visible_rect().size.x
	var global_strength: float = ProjectSettings.get_setting("audio/general/2d_panning_strength", 0.5)
	if global_strength <= 0.0:
		return
	# Godot: pan offset = dx / width · strength · global · 0.5 (half of the ±1 swing).
	panning_strength = viewport_width / (pan_distance * global_strength)
