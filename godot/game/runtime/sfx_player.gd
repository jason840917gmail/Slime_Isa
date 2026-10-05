extends AudioStreamPlayer
## Audio cue player the scene converter attaches to every AudioStreamPlayer
## (runtime spec section 4.12). Connections whose JSON handler is `play` /
## `stop` call `play_cue` / `stop_cue`; both accept 0 or 1 argument.
##
## - `pitch_randomness`: each one-shot plays at `pitch_scale · (1 + U(−r, +r))`.
##   Godot applies pitch per player, so overlapping voices share the newest pitch.
## - `min_interval_ms`: a one-shot requested sooner than this after the last
##   accepted one is dropped.
## - `payload_filter`: `field.path=v1|v2`, matched against the signal payload.
## - `loop`: the stream loops; a repeated play while playing is ignored; the
##   loop resumes when the node re-enters the tree.
## - `autoplay_cue`: plays once in `_ready` (Godot's own `autoplay` stays off so
##   the randomness rules apply).
##
## Owner: converter builder.

const CueRules := preload("res://game/runtime/audio_cue_rules.gd")

@export var pitch_randomness: float = 0.0
@export var min_interval_ms: float = 0.0
@export var payload_filter: String = ""
@export var loop: bool = false
@export var autoplay_cue: bool = false

var _base_pitch: float = 1.0
var _last_accepted_ms: int = -1
var _loop_wanted: bool = false
var _prepared: bool = false


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
	if loop:
		_loop_wanted = true
		if not playing:
			play()
		return
	var now := CueRules.now_ms()
	if min_interval_ms > 0.0 and _last_accepted_ms >= 0 and now - _last_accepted_ms < int(min_interval_ms):
		return
	_last_accepted_ms = now
	pitch_scale = CueRules.randomized_pitch(_base_pitch, pitch_randomness)
	play()


## Stops every voice if `payload` passes the filter (JSON handler `stop`).
func stop_cue(payload: Variant = null) -> void:
	if not CueRules.payload_matches(payload_filter, payload):
		return
	_loop_wanted = false
	stop()


## Stops every voice and forgets the last accepted one-shot, so `min_interval_ms` cannot drop the
## next `play_cue` (`stop()` keeps it). Tests start a "did it play?" check from here: a shared
## player can carry a cue from the previous test that a fast run puts within the interval.
func reset_cue() -> void:
	_last_accepted_ms = -1
	_loop_wanted = false
	stop()
