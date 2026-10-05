extends AudioStreamPlayer2D
## Positional audio cue player the scene converter attaches to every
## AudioStreamPlayer2D (runtime spec section 4.12). Same cue rules as
## `sfx_player.gd`, plus:
##
## - `detached`: a one-shot outlives its node (death and pickup sounds). Each
##   play spawns a one-shot clone at the node's global position under the tree
##   root, which frees itself when done; `max_polyphony` caps the live clones.
## - `pan_distance`: Phaser pans `(x − camera_x) / pan_distance` (clamped ±1)
##   every frame, in world units, so zoom does not change it
##   (`AudioStreamPlayer2DNode.ts` 351-363). Godot pans the screen-space offset
##   `dx · zoom / viewport_width · panning_strength · 2d_panning_strength`, so
##   `panning_strength` is recomputed every frame while a voice plays (and on
##   each play), dividing out the canvas zoom; running loops and live detached
##   clones follow camera zoom and viewport size changes. Attenuation is already
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
		_update_panning()
		play()


# Runs while paused too: the converter sets PROCESS_MODE_ALWAYS on audio players.
func _process(_delta: float) -> void:
	if playing or not _clones.is_empty():
		_update_panning()


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
	_stop_all()


## Stops every voice and forgets the last accepted one-shot, so `min_interval_ms` cannot drop the
## next `play_cue` (`stop()` keeps it); see SfxPlayer.reset_cue (tests).
func reset_cue() -> void:
	_last_accepted_ms = -1
	_stop_all()


func _stop_all() -> void:
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
	var viewport := get_viewport()
	var viewport_width := viewport.get_visible_rect().size.x
	var global_strength: float = ProjectSettings.get_setting("audio/general/2d_panning_strength", 0.5)
	# Godot measures the source offset through the same transform: screen dx = world dx · zoom.
	var zoom := absf((viewport.get_global_canvas_transform() * viewport.get_canvas_transform()).get_scale().x)
	if global_strength <= 0.0 or zoom <= 0.0:
		return
	# Godot: pan offset = dx·zoom / width · strength · global · 0.5 (half of the ±1 swing);
	# Phaser: dx / pan_distance on the same ±1 swing.
	var strength := viewport_width / (pan_distance * zoom * global_strength)
	if not is_equal_approx(panning_strength, strength):
		panning_strength = strength
	if _clones.is_empty():
		return
	var live: Array[AudioStreamPlayer2D] = []
	for clone in _clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			live.append(clone)
			clone.panning_strength = strength
	_clones = live
