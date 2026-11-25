extends SceneTree
## Saves shipped sound takes as native AudioStreamWAV resources, so a game run plays them before the
## editor has imported their WAV files (as tools/pack_doorway_textures.gd does for pictures: an open
## editor imports new files only when it gets the focus, and until then a scene that names a WAV
## that is not imported does not load at all; game/scenes/audio/global.tscn is such a scene, so one
## new take would silence every global cue).
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/pack_cue_sounds.gd -- --cues=<category>/<cue>[,...]
## For each cue it reads res://asset/audio/sfx/library/<category>/<cue>.wav and <cue>-<n>.wav and
## writes res://asset/audio/sfx/packed/<category>/<same name>.res (outside the folders
## `pnpm audio:bake` prunes). The cue's player in global.tscn then names the .res files.
## Used for Sound Picker round 15 (the dungeon mechanisms: docs/godot/specs/audio.md section 17).

const LIBRARY := "res://asset/audio/sfx/library/"
const PACKED := "res://asset/audio/sfx/packed/"


func _initialize() -> void:
	var cues := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cues="):
			cues = arg.trim_prefix("--cues=").split(",", false)
	var failed := 0
	var written := 0
	for cue: String in cues:
		var folder := cue.get_base_dir()
		var stem := cue.get_file()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACKED + folder))
		var found := 0
		for file: String in DirAccess.get_files_at(LIBRARY + folder):
			if not file.ends_with(".wav"):
				continue
			var name := file.get_basename()
			if name != stem and not (name.begins_with(stem + "-") and name.trim_prefix(stem + "-").is_valid_int()):
				continue
			found += 1
			var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(LIBRARY + folder + "/" + file))
			if stream == null:
				failed += 1
				continue
			var error := ResourceSaver.save(stream, PACKED + folder + "/" + name + ".res", ResourceSaver.FLAG_COMPRESS)
			if error != OK:
				failed += 1
			else:
				written += 1
		if found == 0:
			push_error("pack_cue_sounds: no take for '%s'" % cue)
			failed += 1
	print("cue sounds: ", written, " written, ", failed, " failures")
	quit(1 if failed > 0 else 0)
