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
## - Body-shapes rework (docs/godot/BODY_SHAPES.md "Juice"): a Dictionary payload
##   with a PAYLOAD_PITCH number plays the one-shot at `pitch_scale · pitch`, and
##   its PAYLOAD_PITCH_RANDOMNESS (when given) replaces `pitch_randomness` for that
##   play (GameFeel's rising impact pitch). No old payload carries either key.
## - The throw feel (docs/godot/THROW_COMBAT.md): a Dictionary payload with a PAYLOAD_VOLUME_DB
##   number plays that one-shot that many dB louder (or, negative, quieter) than the cue's own
##   `volume_db` (a miss's duller break, a rebound's thud). It plays on a one-off copy of the player
##   (`_play_offset`), freed when it ends: setting `volume_db` on this player would change every
##   voice of it still playing (and stick until the next play), so the offset never touches it.
##   `stop_cue` does not stop such a copy (short one-shots).
##
## Owner: converter builder (the pitch payload: juice; the volume payload: throw combat's sender).

const CueRules := preload("res://game/runtime/audio_cue_rules.gd")
const PAYLOAD_PITCH := "pitch"
const PAYLOAD_PITCH_RANDOMNESS := "pitch_randomness"
const PAYLOAD_VOLUME_DB := "volume_db"

@export var pitch_randomness: float = 0.0
@export var min_interval_ms: float = 0.0
@export var payload_filter: String = ""
@export var loop: bool = false
@export var autoplay_cue: bool = false

## Cues started since `reset_cue` (one-shots accepted, loops started). Tests ask this rather than
## `playing`: a short cue can already have finished when a starved headless mixer catches up.
var cues_played: int = 0

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
			cues_played += 1
			play()
		return
	var now := CueRules.now_ms()
	if min_interval_ms > 0.0 and _last_accepted_ms >= 0 and now - _last_accepted_ms < int(min_interval_ms):
		return
	_last_accepted_ms = now
	cues_played += 1
	var pitch := CueRules.randomized_pitch(_base_pitch * _payload_number(payload, PAYLOAD_PITCH, 1.0),
		_payload_number(payload, PAYLOAD_PITCH_RANDOMNESS, pitch_randomness))
	var offset_db := _payload_offset_db(payload)
	if not is_zero_approx(offset_db) and is_inside_tree():
		_play_offset(pitch, offset_db)
		return
	pitch_scale = pitch
	play()


## One play at `pitch` and `offset_db` from the cue's own volume, on a copy of this player that
## frees itself when it ends (see the header).
func _play_offset(pitch: float, offset_db: float) -> void:
	var copy := AudioStreamPlayer.new()
	copy.name = "%sOffset" % name
	copy.stream = stream
	copy.bus = bus
	copy.volume_db = volume_db + offset_db
	copy.pitch_scale = pitch
	copy.process_mode = Node.PROCESS_MODE_ALWAYS
	copy.finished.connect(copy.queue_free)
	add_child(copy)
	copy.play()


## `payload[PAYLOAD_VOLUME_DB]` as a finite number of dB (negative = quieter), else 0.
static func _payload_offset_db(payload: Variant) -> float:
	if not (payload is Dictionary) or not (payload as Dictionary).has(PAYLOAD_VOLUME_DB):
		return 0.0
	var raw: Variant = (payload as Dictionary)[PAYLOAD_VOLUME_DB]
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return 0.0
	return float(raw) if is_finite(float(raw)) else 0.0


## Stops every voice if `payload` passes the filter (JSON handler `stop`).
func stop_cue(payload: Variant = null) -> void:
	if not CueRules.payload_matches(payload_filter, payload):
		return
	_loop_wanted = false
	stop()


## `payload[key]` as a finite number >= 0 (a pitch must be > 0), else `fallback` (any other payload).
static func _payload_number(payload: Variant, key: String, fallback: float) -> float:
	if not (payload is Dictionary) or not (payload as Dictionary).has(key):
		return fallback
	var raw: Variant = (payload as Dictionary)[key]
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return fallback
	var number := float(raw)
	if not is_finite(number) or number < 0.0 or (key == PAYLOAD_PITCH and number <= 0.0):
		return fallback
	return number


## Stops every voice and forgets the last accepted one-shot, so `min_interval_ms` cannot drop the
## next `play_cue` (`stop()` keeps it). Tests start a "did it play?" check from here: a shared
## player can carry a cue from the previous test that a fast run puts within the interval.
func reset_cue() -> void:
	_last_accepted_ms = -1
	cues_played = 0
	_loop_wanted = false
	stop()
