extends SceneTree
## Adds the three-quarter top-down slime pages to the Godot-owned player scene
## (res://game/characters/player_slime.tscn) and saves it.
##
## For every page listed in PAGES it reads the packer's manifest
## (asset/Originals/characters/slime-v2/page-N.json, written by
## scripts/characters/pack-slime-v2-page.py) and (re)builds one looping clip per row, named after
## the row (`idle-down`, `walk-side`, ...): a discrete `Visual:frame` track over the row's 8 cells
## at the row's playback fps, and a discrete `Visual:texture` track selecting that page.
## Every other clip still drawn from the old side-view sheet gets a `Visual:texture` key for that
## sheet, so switching clips always switches to the right texture. The sprite's default texture
## and the autoplay clip become the new page's `idle-down`.
##
## Run with the Godot 4.7.2 console exe:
##     --headless --path godot -s res://tools/build_player_clips.gd
## then reload the scene in an open editor. Safe to re-run: it replaces what it built before.

const SCENE_PATH := "res://game/characters/player_slime.tscn"
const OLD_SHEET := "res://asset/characters/slime_normalized.webp"
const PAGES := [
	{
		"texture": "res://asset/characters/256x256-tile_8x8-slime-v2-page-1.webp",
		"manifest": "../asset/Originals/characters/slime-v2/page-1.json",
	},
]
const LIBRARY := &""


func _initialize() -> void:
	var exit_code := 0
	if not _build():
		exit_code = 1
	quit(exit_code)


func _build() -> bool:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("build_player_clips: cannot load %s" % SCENE_PATH)
		return false
	var root := packed.instantiate()
	var player := root.get_node_or_null("Animation") as AnimationPlayer
	var visual := root.get_node_or_null("Visual") as Sprite2D
	if player == null or visual == null or not player.has_animation_library(LIBRARY):
		push_error("build_player_clips: the scene needs Visual (Sprite2D) and Animation (AnimationPlayer) with a default library")
		return false
	var library := player.get_animation_library(LIBRARY)
	var old_sheet := load(OLD_SHEET) as Texture2D

	var built: Array[StringName] = []
	var first_clip := StringName()
	for page: Dictionary in PAGES:
		var texture := load(page["texture"]) as Texture2D
		var manifest := _read_manifest(page["manifest"])
		if texture == null or manifest.is_empty():
			push_error("build_player_clips: missing texture or manifest for %s" % page["texture"])
			return false
		var columns: int = int(manifest["columns"])
		var rows: Dictionary = manifest["rows"]
		for clip_name: String in rows:
			var row: Dictionary = rows[clip_name]
			var animation := _row_clip(int(row["first_frame"]), columns, float(row["fps"]), texture)
			if library.has_animation(clip_name):
				library.remove_animation(clip_name)
			library.add_animation(clip_name, animation)
			built.append(StringName(clip_name))
			if first_clip == StringName():
				first_clip = StringName(clip_name)
			print("build_player_clips: %s (frames %d-%d at %s fps)" % [clip_name, int(row["first_frame"]), int(row["first_frame"]) + columns - 1, row["fps"]])

	for clip_name: StringName in library.get_animation_list():
		if clip_name in built:
			continue
		_set_texture_track(library.get_animation(clip_name), old_sheet)

	var idle := StringName("idle-down") if library.has_animation("idle-down") else first_clip
	visual.texture = (load(PAGES[0]["texture"]) as Texture2D)
	visual.frame = 0
	player.autoplay = idle

	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result != OK:
		push_error("build_player_clips: pack failed (%d)" % result)
		return false
	result = ResourceSaver.save(scene, SCENE_PATH)
	root.free()
	if result != OK:
		push_error("build_player_clips: save failed (%d)" % result)
		return false
	print("build_player_clips: saved %s with %d new clips; autoplay %s" % [SCENE_PATH, built.size(), idle])
	return true


## One looping clip over a page row: `columns` frames at `fps`, starting at `first_frame`.
func _row_clip(first_frame: int, columns: int, fps: float, texture: Texture2D) -> Animation:
	var animation := Animation.new()
	animation.length = columns / fps
	animation.loop_mode = Animation.LOOP_LINEAR
	animation.step = 1.0 / fps
	var frames := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(frames, NodePath("Visual:frame"))
	animation.value_track_set_update_mode(frames, Animation.UPDATE_DISCRETE)
	animation.track_set_interpolation_type(frames, Animation.INTERPOLATION_NEAREST)
	animation.track_set_interpolation_loop_wrap(frames, false)
	for column in columns:
		animation.track_insert_key(frames, column / fps, first_frame + column)
	_set_texture_track(animation, texture)
	return animation


## Replaces (or adds) the clip's `Visual:texture` track with one discrete key at 0.
func _set_texture_track(animation: Animation, texture: Texture2D) -> void:
	var existing := animation.find_track(NodePath("Visual:texture"), Animation.TYPE_VALUE)
	if existing >= 0:
		animation.remove_track(existing)
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Visual:texture"))
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	animation.track_insert_key(track, 0.0, texture)


func _read_manifest(relative_to_project: String) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(relative_to_project).simplify_path()
	if not FileAccess.file_exists(path):
		push_error("build_player_clips: manifest %s not found" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
