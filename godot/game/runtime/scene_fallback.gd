extends RefCounted
## A scene that would not load because some of its sound files are not ready (owner, 2026-11-22:
## after a new sound round every sound went silent, "i dont hear now my sound, suck, roll throw").
## Godot loads a sound file only once the editor has imported it, and one file it cannot load fails
## the whole scene: the global cue scene (`audio.global`, every shared sound) fell silent at once
## when a round's new takes were in it before the editor imported them.
##
## `load_without_missing_audio(path)` loads a copy of the scene instead, with every sound file that
## cannot load yet swapped for a silent stream, and warns which ones (they play once the editor has
## imported them: give it focus). Only audio files are swapped; a scene that fails for any other
## reason still fails. WorldService `packed_scene` asks for it when a scene does not load.
##
## Owner: runtime.

const FALLBACK_DIR := "user://scene_fallback"
## The silent stream the missing files are swapped for (an AudioStreamWAV with no data).
const SILENCE_ID := "MissingAudioSilence"
const EXT_PATTERN := "(?m)^\\[ext_resource type=\"(AudioStream\\w+)\"[^\\]\\n]*?path=\"([^\"]+)\"[^\\]\\n]*?id=\"([^\"]+)\"\\]\\n?"


## The scene at `path` (a .tscn) with its audio files that cannot load swapped for silence, or null
## when it has none (it fails for another reason) or still does not load. Warns with the files.
static func load_without_missing_audio(path: String) -> PackedScene:
	if not path.ends_with(".tscn") or not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var pattern := RegEx.create_from_string(EXT_PATTERN)
	var missing: Array[String] = []
	var missing_ids: Array[String] = []
	var lines_out: Array[String] = []
	for found: RegExMatch in pattern.search_all(text):
		var file := found.get_string(2)
		if _loads(file):
			continue
		missing.append(file)
		missing_ids.append(found.get_string(3))
		lines_out.append(found.get_string(0))
	if missing.is_empty():
		return null
	for line: String in lines_out:
		text = text.replace(line, "")
	for id: String in missing_ids:
		text = text.replace("ExtResource(\"%s\")" % id, "SubResource(\"%s\")" % SILENCE_ID)
	# The silent stream goes before the first sub-resource or node (resources come before their use).
	var first := text.find("\n[sub_resource")
	if first < 0:
		first = text.find("\n[node")
	if first < 0:
		return null
	text = text.substr(0, first + 1) + "[sub_resource type=\"AudioStreamWAV\" id=\"%s\"]\n\n" % SILENCE_ID \
		+ text.substr(first + 1)
	text = RegEx.create_from_string("load_steps=\\d+ ").sub(text, "", true)
	DirAccess.make_dir_recursive_absolute(FALLBACK_DIR)
	var copy := FALLBACK_DIR.path_join(path.trim_prefix("res://").trim_prefix("user://").replace("/", "__"))
	var file_out := FileAccess.open(copy, FileAccess.WRITE)
	if file_out == null:
		return null
	file_out.store_string(text)
	file_out.close()
	var packed := ResourceLoader.load(copy, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed != null:
		push_warning("%s loaded without %d sound file(s) the editor has not imported yet (silent until it does: give the editor focus): %s"
			% [path, missing.size(), ", ".join(missing)])
	return packed


## True when the sound file at `file` loads (imported, or loadable as it is).
static func _loads(file: String) -> bool:
	if not ResourceLoader.exists(file):
		return false
	return ResourceLoader.load(file) != null
