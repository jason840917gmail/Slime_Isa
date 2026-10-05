extends SceneTree
## Builds the three-quarter top-down slime clips into the Godot-owned player scene
## (res://game/characters/player_slime.tscn) and saves it.
##
## Sheet clips: for every page listed in PAGES it reads the packer's manifest
## (asset/Originals/characters/slime-v2/page-N.json, written by
## scripts/characters/pack-slime-v2-page.py) and builds one clip per row, named after the row
## (`idle-down`, `roll-side`, ...): a discrete `Visual:frame` track over the row's 8 cells at the
## row's playback fps, looping unless the row says `"loop": false` (the rolls), and a discrete
## `Visual:texture` track selecting that page.
##
## Keyed clips (ATTACKS): `attack-1-down`, `-up`, `-side` and `-left` reuse page 1's idle art and
## carry the swing in keys: a wind-up on the row's most squashed frame with a short pull back, then
## a lunge toward the swing on its most stretched frame (`Visual:offset`, plus a `Visual:skew` lean
## for the side). `-left` exists because flip_h mirrors the art but not the offset: it is the side
## clip mirrored, with a `Visual:flip_h` key so it previews right in the editor.
##
## Every other clip, still drawn from the old side-view sheet, gets a `Visual:texture` key for that
## sheet, so switching clips always switches to the right texture.
##
## Run with the Godot 4.7.2 console exe (close the scene in an open editor first, then reload it):
##     --headless --path godot -s res://tools/build_player_clips.gd [-- --only=roll,attack-1]
## `--only` rebuilds just the clips whose names start with one of the prefixes and leaves the rest
## (say, idle timing tuned in the editor) as they are. Without it every clip above is rebuilt, and
## the sprite's default texture and the autoplay clip become page 1's `idle-down`.

const SCENE_PATH := "res://game/characters/player_slime.tscn"
const OLD_SHEET := "res://asset/characters/slime_normalized.webp"
const PAGES := [
	{
		"texture": "res://asset/characters/256x256-tile_8x8-slime-v2-page-1.webp",
		"manifest": "../asset/Originals/characters/slime-v2/page-1.json",
	},
	{
		"texture": "res://asset/characters/256x256-tile_8x8-slime-v2-page-2.webp",
		"manifest": "../asset/Originals/characters/slime-v2/page-2.json",
	},
]
const LIBRARY := &""

## The basic sword's `characterActionId` for every direction (combat spec 1).
const ATTACK_CLIP := "attack-1"
## Per direction: the page-1 idle row the swing draws, its [rest, squashed, stretched] columns
## (measured from the cells' bounding boxes), which way it lunges, whether the art is mirrored,
## and the basic sword's swing that way: its length (the attack plan's durationMs) and `strike`,
## when its slash is widest on screen (read off the running game), where the lunge peaks.
const ATTACKS := {
	"down": {"row": "idle-down", "columns": [0, 5, 3], "toward": Vector2(0, 1), "flip": false,
			"length": 0.29167, "strike": 0.17},
	"up": {"row": "idle-up", "columns": [0, 2, 5], "toward": Vector2(0, -1), "flip": false,
			"length": 0.33333, "strike": 0.21},
	"side": {"row": "idle-side", "columns": [0, 0, 2], "toward": Vector2(1, 0), "flip": false,
			"length": 0.41667, "strike": 0.25},
	"left": {"row": "idle-side", "columns": [0, 0, 2], "toward": Vector2(-1, 0), "flip": true,
			"length": 0.41667, "strike": 0.25},
}
## The swing's keys: [phase (0 start, 1 strike, 2 end; 0.5 is halfway to the strike, 1.5 halfway
## from it to the end), column slot (0 rest, 1 squashed, 2 stretched), reach toward the swing in
## world px (negative pulls back), side lean in radians (toward the swing), transition to the next
## key (Animation easing: < 1 eases out, negative eases in and out)].
const SWING_KEYS := [
	[0.0, 0, 0.0, 0.0, 0.5],
	[0.55, 1, -4.0, -0.1, 0.35],
	[1.0, 2, 14.0, 0.2, 1.0],
	[1.4, 0, 10.0, 0.1, -2.0],
	[2.0, 0, 0.0, 0.0, 1.0],
]


func _initialize() -> void:
	var exit_code := 0
	if not _build(_only_prefixes()):
		exit_code = 1
	quit(exit_code)


func _build(only: PackedStringArray) -> bool:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("build_player_clips: cannot load %s" % SCENE_PATH)
		return false
	var root := packed.instantiate()
	var player := root.get_node_or_null("Animation") as AnimationPlayer
	var visual := root.get_node_or_null("Visual") as Sprite2D
	if player == null or visual == null or not player.has_animation_library(LIBRARY):
		push_error("build_player_clips: the scene needs Visual (Sprite2D) and Animation (AnimationPlayer) with a default library")
		root.free()
		return false
	var library := player.get_animation_library(LIBRARY)
	var old_sheet := load(OLD_SHEET) as Texture2D

	# Every clip this tool owns, built or kept, so the old-sheet pass below leaves them alone.
	var owned: Array[String] = []
	var page_rows := {}
	var built := 0
	for page: Dictionary in PAGES:
		var texture := load(page["texture"]) as Texture2D
		var manifest := _read_manifest(page["manifest"])
		if texture == null or manifest.is_empty():
			push_error("build_player_clips: missing texture or manifest for %s" % page["texture"])
			root.free()
			return false
		var columns: int = int(manifest["columns"])
		var rows: Dictionary = manifest["rows"]
		for clip_name: String in rows:
			var row: Dictionary = rows[clip_name]
			page_rows[clip_name] = {"first_frame": int(row["first_frame"]), "texture": texture}
			owned.append(clip_name)
			if not _selected(clip_name, only):
				continue
			var looping := bool(row.get("loop", true))
			_replace(library, clip_name, _row_clip(int(row["first_frame"]), columns, float(row["fps"]), looping, texture))
			built += 1
			print("build_player_clips: %s (frames %d-%d at %s fps%s)" % [clip_name, int(row["first_frame"]),
					int(row["first_frame"]) + columns - 1, row["fps"], "" if looping else ", once"])

	for direction: String in ATTACKS:
		var clip_name := "%s-%s" % [ATTACK_CLIP, direction]
		owned.append(clip_name)
		if not _selected(clip_name, only):
			continue
		var spec: Dictionary = ATTACKS[direction]
		var source: Dictionary = page_rows.get(spec["row"], {})
		if source.is_empty():
			push_error("build_player_clips: %s needs the %s row" % [clip_name, spec["row"]])
			root.free()
			return false
		_replace(library, clip_name, _swing_clip(spec, source, visual))
		built += 1
		print("build_player_clips: %s (keyed swing on %s)" % [clip_name, spec["row"]])

	for clip_name: StringName in library.get_animation_list():
		if String(clip_name) in owned:
			continue
		_set_texture_track(library.get_animation(clip_name), old_sheet)

	if only.is_empty():
		visual.texture = load(PAGES[0]["texture"]) as Texture2D
		visual.frame = 0
		player.autoplay = &"idle-down"

	var scene := PackedScene.new()
	var result := scene.pack(root)
	root.free()
	if result != OK:
		push_error("build_player_clips: pack failed (%d)" % result)
		return false
	result = ResourceSaver.save(scene, SCENE_PATH)
	if result != OK:
		push_error("build_player_clips: save failed (%d)" % result)
		return false
	print("build_player_clips: saved %s with %d clips rebuilt%s" % [SCENE_PATH, built,
			"" if only.is_empty() else " (only %s)" % ", ".join(only)])
	return true


## One clip over a page row: `columns` frames at `fps`, starting at `first_frame`.
func _row_clip(first_frame: int, columns: int, fps: float, looping: bool, texture: Texture2D) -> Animation:
	var animation := Animation.new()
	animation.length = columns / fps
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	animation.step = 1.0 / fps
	var frames := _discrete_track(animation, "Visual:frame")
	for column in columns:
		animation.track_insert_key(frames, column / fps, first_frame + column)
	_set_texture_track(animation, texture)
	return animation


## A one-shot swing on page-1 idle art (see ATTACKS and SWING_KEYS).
func _swing_clip(spec: Dictionary, source: Dictionary, visual: Sprite2D) -> Animation:
	var animation := Animation.new()
	var length: float = spec["length"]
	var strike: float = spec["strike"]
	animation.length = length
	animation.loop_mode = Animation.LOOP_NONE
	animation.step = 0.01
	var first_frame: int = source["first_frame"]
	var picks: Array = spec["columns"]
	var toward: Vector2 = spec["toward"]
	# Offsets are in texture pixels, before the Visual's scale.
	var px_per_world := 1.0 / maxf(visual.scale.x, 0.001)
	var frames := _discrete_track(animation, "Visual:frame")
	var offset := _continuous_track(animation, "Visual:offset")
	var skew := -1
	if toward.y == 0.0:
		skew = _continuous_track(animation, "Visual:skew")
	for key: Array in SWING_KEYS:
		var phase: float = key[0]
		var time := phase * strike if phase <= 1.0 else strike + (phase - 1.0) * (length - strike)
		var transition: float = key[4]
		animation.track_insert_key(frames, time, first_frame + int(picks[int(key[1])]))
		animation.track_insert_key(offset, time, visual.offset + toward * float(key[2]) * px_per_world, transition)
		if skew >= 0:
			animation.track_insert_key(skew, time, visual.skew + float(key[3]) * signf(toward.x), transition)
	_set_texture_track(animation, source["texture"])
	if bool(spec["flip"]):
		animation.track_insert_key(_discrete_track(animation, "Visual:flip_h"), 0.0, true)
	return animation


func _discrete_track(animation: Animation, path: String) -> int:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	animation.track_set_interpolation_loop_wrap(track, false)
	return track


func _continuous_track(animation: Animation, path: String) -> int:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	animation.track_set_interpolation_loop_wrap(track, false)
	return track


## Replaces (or adds) the clip's `Visual:texture` track with one discrete key at 0.
func _set_texture_track(animation: Animation, texture: Texture2D) -> void:
	var existing := animation.find_track(NodePath("Visual:texture"), Animation.TYPE_VALUE)
	if existing >= 0:
		animation.remove_track(existing)
	animation.track_insert_key(_discrete_track(animation, "Visual:texture"), 0.0, texture)


func _replace(library: AnimationLibrary, clip_name: String, animation: Animation) -> void:
	if library.has_animation(clip_name):
		library.remove_animation(clip_name)
	library.add_animation(clip_name, animation)


func _selected(clip_name: String, only: PackedStringArray) -> bool:
	if only.is_empty():
		return true
	for prefix in only:
		if clip_name.begins_with(prefix):
			return true
	return false


## `--only=a,b` from the user arguments (after `--`); empty means everything.
func _only_prefixes() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return arg.trim_prefix("--only=").split(",", false)
	return PackedStringArray()


func _read_manifest(relative_to_project: String) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(relative_to_project).simplify_path()
	if not FileAccess.file_exists(path):
		push_error("build_player_clips: manifest %s not found" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
