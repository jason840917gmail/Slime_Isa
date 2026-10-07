extends RefCounted
## Shared Phaser audio-cue rules for `sfx_player.gd` and `sfx_player_2d.gd`
## (runtime spec section 4.12): payload filters, min-interval gating, per-play
## pitch and looping streams.
##
## Owner: converter builder (the converter attached the players to the scenes).


## True when `payload` passes `filter` (`field.path=v1|v2`; empty accepts all).
## Walks Dictionary keys; the leaf must be a String, number or bool whose text
## (integral floats without ".0", as JavaScript's String()) is one of the values.
static func payload_matches(filter: String, payload: Variant) -> bool:
	if filter.is_empty():
		return true
	var separator := filter.find("=")
	if separator <= 0:
		return false
	var path := filter.substr(0, separator).split(".")
	var accepted := filter.substr(separator + 1).split("|")
	var current: Variant = payload
	for key: String in path:
		if not (current is Dictionary) or not (current as Dictionary).has(key):
			return false
		current = (current as Dictionary)[key]
	var text := ""
	match typeof(current):
		TYPE_STRING, TYPE_STRING_NAME:
			text = String(current)
		TYPE_BOOL:
			text = "true" if current else "false"
		TYPE_INT:
			text = str(current)
		TYPE_FLOAT:
			var number: float = current
			text = str(int(number)) if is_equal_approx(number, roundf(number)) and absf(number) < 1e15 else str(number)
		_:
			return false
	return accepted.has(text)


## Phaser one-shot rate: `pitch · (1 + U(−r, +r))`.
static func randomized_pitch(base_pitch: float, randomness: float) -> float:
	if randomness <= 0.0:
		return base_pitch
	return base_pitch * (1.0 + randf_range(-randomness, randomness))


## A looping copy of `stream` (Ogg/MP3 `loop`, WAV forward loop over the whole
## sample). The looped files are only ever used looped, but the copy keeps the
## shared imported resource untouched.
static func looping_copy(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var copy: AudioStream = stream.duplicate()
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	elif copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	else:
		push_warning("audio_cue_rules: cannot loop stream of type %s" % copy.get_class())
	return copy


## Milliseconds clock for min-interval gating (wall clock; keeps counting while paused).
static func now_ms() -> int:
	return Time.get_ticks_msec()
