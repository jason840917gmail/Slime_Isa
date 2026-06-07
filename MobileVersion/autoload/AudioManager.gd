extends Node

var music_volume := 0.8
var sfx_volume := 1.0
var _sfx_player: AudioStreamPlayer
var _known_sfx := {
	&"pickup": 880.0,
	&"click": 660.0,
	&"error": 220.0,
	&"ability": 1040.0,
	&"interact": 520.0,
}

func _ready() -> void:
	_sfx_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.12
	_sfx_player.stream = stream
	add_child(_sfx_player)

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(music_volume))


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)


func play_sfx(id: StringName) -> void:
	if not _known_sfx.has(id):
		if OS.is_debug_build():
			push_warning("Missing placeholder SFX: %s" % id)
		return

	_sfx_player.play()
	var playback := _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return

	playback.clear_buffer()
	var sample_rate := 22050.0
	var duration := 0.08
	var frames := int(sample_rate * duration)
	var frequency := float(_known_sfx[id])

	for i in range(frames):
		var t := float(i) / sample_rate
		var fade := 1.0 - (float(i) / float(frames))
		var sample := sin(TAU * frequency * t) * 0.18 * fade * sfx_volume
		playback.push_frame(Vector2(sample, sample))
