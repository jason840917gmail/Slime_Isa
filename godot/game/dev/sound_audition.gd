extends CanvasLayer
## Sound audition (dev; `?audition` on the web, `-- --audition` on desktop; docs/godot/specs/audio.md
## §10.3): hear the Sound Picker's options in the game before picking. F8 and F7 step through the
## option sets (what the game plays, A, B, round 2). Each cue staged in AUDITION_MANIFEST that has
## the set's option plays those takes, at the volume measured for them; the others keep what the
## game plays. A panel in the top-left corner names the set and the ground under the slime.
##
## scripts/audio/stage-round.py writes the audition folder; applying the final picks removes it.
##
## Owner: audio.

const Services := preload("res://game/shared/services.gd")
const AUDITION_MANIFEST := "res://asset/audio/sfx/audition/audition.json"
const FOOTSTEPS_PREFIX := "Footsteps/"
const SETS: Array[Dictionary] = [
	{"key": "", "label": "In game: what the game plays now"},
	{"key": "a", "label": "A: real footsteps and natural takes"},
	{"key": "b", "label": "B: slime hops and cartoon takes"},
	{"key": "r2", "label": "Round 2: the steps kept in round 2"},
]
const NEXT_KEY := KEY_F8
const PREVIOUS_KEY := KEY_F7
## Players are looked up again this often: the player's Footsteps come back with every respawn and
## world change.
const REFRESH_S := 0.5
const ORIGINAL_META := &"audition_original"

## cue id -> {"node", "inGame", "options": {key: {"label", "takes", "volume_db"}}}
var _cues: Dictionary = {}
var _set: int = 0
var _label: Label
## "cue:key" -> AudioStreamRandomizer
var _streams: Dictionary = {}
## player instance id -> the set it plays
var _applied: Dictionary = {}
var _since_refresh: float = 0.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDITION_MANIFEST))
	if parsed is Dictionary:
		_cues = (parsed as Dictionary).get("cues", {})
	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_color_override(&"font_color", Color("#e5eee4"))
	_label.add_theme_color_override(&"font_outline_color", Color("#121814"))
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.add_theme_font_size_override(&"font_size", 18)
	add_child(_label)
	_refresh_label()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == NEXT_KEY:
		_step(1)
	elif key.keycode == PREVIOUS_KEY:
		_step(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < REFRESH_S:
		return
	_since_refresh = 0.0
	_apply()
	_refresh_label()


func _step(by: int) -> void:
	_set = posmod(_set + by, SETS.size())
	_applied.clear()
	_apply()
	_refresh_label()


func _apply() -> void:
	var key := str(SETS[_set]["key"])
	for cue_id: String in _cues:
		var entry: Dictionary = _cues[cue_id]
		var player := _player_for(str(entry["node"]))
		if player == null or int(_applied.get(player.get_instance_id(), -1)) == _set:
			continue
		_applied[player.get_instance_id()] = _set
		if not player.has_meta(ORIGINAL_META):
			player.set_meta(ORIGINAL_META, [player.stream, player.volume_db])
		var options: Dictionary = entry["options"]
		if key.is_empty() or not options.has(key):
			var original: Array = player.get_meta(ORIGINAL_META)
			player.stream = original[0]
			player.volume_db = float(original[1])
			continue
		var option: Dictionary = options[key]
		player.stream = _stream(cue_id, key, option["takes"])
		player.volume_db = float(option["volume_db"])


func _stream(cue_id: String, key: String, takes: Array) -> AudioStream:
	var cache_key := "%s:%s" % [cue_id, key]
	if not _streams.has(cache_key):
		var randomizer := AudioStreamRandomizer.new()
		randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM
		randomizer.random_pitch = 1.0
		for path: Variant in takes:
			var take := load(str(path)) as AudioStream
			if take != null:
				randomizer.add_stream(-1, take)
		_streams[cache_key] = randomizer
	return _streams[cache_key]


## `Footsteps/<X>` under the player, else the global `Effects/<X>`.
func _player_for(node_path: String) -> AudioStreamPlayer:
	if node_path.begins_with(FOOTSTEPS_PREFIX):
		var footsteps := _footsteps()
		return footsteps.get_node_or_null(NodePath(node_path.trim_prefix(FOOTSTEPS_PREFIX))) as AudioStreamPlayer if footsteps != null else null
	var feel := Services.feel()
	var root: Node = feel.global_audio() if feel != null else null
	return root.find_child(node_path, true, false) as AudioStreamPlayer if root != null else null


func _footsteps() -> Node:
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player):
		return null
	return world.player.get_node_or_null(^"Footsteps")


func _refresh_label() -> void:
	var ground := "-"
	var footsteps := _footsteps()
	var world := Services.world()
	if footsteps != null and world != null and world.player_body != null:
		ground = String(footsteps.call(&"surface_at", world.player_body.global_position))
	_label.text = "Sound audition: %s\nGround: %s   ·   F7 / F8 switch options" % [SETS[_set]["label"], ground if not ground.is_empty() else "-"]
