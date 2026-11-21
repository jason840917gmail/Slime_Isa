extends SceneTree
## Films the Bow (docs/godot/BODY_SHAPES.md "The Bow") in the running game: it starts a world, puts
## the slime's feet at `--feet`, lends it the Bow for the session and chooses it in the Ability Box,
## turns it to `--aim`, saves a still (`still.png`), then presses the use key, holds it `--hold-ms`
## (the body bent into the bow), lets go and films the arrow in flight every `--frame-ms` of game time for
## `--max-ms`. `--flags=a,b` sets story flags first; `--no-shot` saves the still only. Run windowed
## (it renders), one game window at a time, from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_bow_shot.gd -- --out=<dir>
##         --map=<world id> --feet=<x>,<y> [--aim=<x>,<y>] [--hold-ms=300] [--frame-ms=40] [--max-ms=900]
##         [--zoom=<camera zoom>] [--window=<w>x<h>, 960x540] [--flags=<flag>,...] [--no-shot] [--grid]
## `--grid` draws the 64-unit cells with their world coordinates over the picture (for placing things);
## `--camera=<x>,<y>` looks there with a camera of its own (at `--zoom`, else 1) instead of the game's;
## `--probe=<x>,<y>;<x>,<y>...` prints the elevation's level and top level at those world points;
## `--then=<x>,<y>,<aim x>,<aim y>;...` shoots again from each of those feet along that aim after the
## first shot (filmed the same way: a lock of several targets).
## Writes <dir>/still.png and <dir>/frame-<n>.png, and prints a line per frame (time, the slime's
## feet, the arrows in flight and where they are). The arrows and the slime's page 7 (the body-bow
## clips) are drawn from their source pictures (FRESH_ART, FRESH_PAGES, read from disk), so a picture
## changed since the last import shows as it is now (a run outside the editor does not import).

const Services := preload("res://game/shared/services.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://bow-shot"
const USE_ACTION := &"ability_use"
const BOW := &"bow"
## The node names the Bow's arrow uses, and its source picture.
const FRESH_ART := {
	"BowArrow": "res://asset/abilities/bow/arrow.webp",
}
## The slime's sheets read from disk before the game loads them (the body-bow clips draw page 7):
## a page packed since the last import shows as it is now.
const FRESH_PAGES: PackedStringArray = ["res://asset/characters/256x256-tile_8x8-slime-v2-page-7.webp"]

var _fresh: Dictionary = {}

var _frame := 0
var _out := DEFAULT_OUT
var _frame_ms := 40.0


func _initialize() -> void:
	# The Bow's first lock: the lake camp's bank in C5, below the west lens.
	var map := "level-1-c5"
	var feet := Vector2(1150.0, 610.0)
	var aim := Vector2.UP
	var hold_ms := 300.0
	var max_ms := 900.0
	var zoom := 0.0
	var window := Vector2i(960, 540)
	var flags := PackedStringArray()
	var shoot := true
	var grid := false
	var look_at := Vector2.INF
	var probes: Array[Vector2] = []
	var then: Array[PackedFloat32Array] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--feet="):
			var xy := arg.trim_prefix("--feet=").split(",")
			feet = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--aim="):
			var axy := arg.trim_prefix("--aim=").split(",")
			aim = Vector2(float(axy[0]), float(axy[1])).normalized()
		elif arg.begins_with("--hold-ms="):
			hold_ms = float(arg.trim_prefix("--hold-ms="))
		elif arg.begins_with("--frame-ms="):
			_frame_ms = float(arg.trim_prefix("--frame-ms="))
		elif arg.begins_with("--max-ms="):
			max_ms = float(arg.trim_prefix("--max-ms="))
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(wh[0]), int(wh[1]))
		elif arg.begins_with("--flags="):
			flags = arg.trim_prefix("--flags=").split(",", false)
		elif arg == "--no-shot":
			shoot = false
		elif arg == "--grid":
			grid = true
		elif arg.begins_with("--probe="):
			for pair: String in arg.trim_prefix("--probe=").split(";", false):
				var pxy := pair.split(",")
				probes.append(Vector2(float(pxy[0]), float(pxy[1])))
		elif arg.begins_with("--then="):
			for shot: String in arg.trim_prefix("--then=").split(";", false):
				var parts := shot.split(",")
				then.append(PackedFloat32Array([float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])]))
		elif arg.begins_with("--camera="):
			var cxy := arg.trim_prefix("--camera=").split(",")
			look_at = Vector2(float(cxy[0]), float(cxy[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(window)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 40:
		await process_frame
	var run := Services.run()
	if run != null:
		for flag in flags:
			run.set_flag(flag)
		run.learn_session_ability(String(BOW))
	var body := _body()
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	var elevation: Node = Services.world().elevation
	if elevation != null:
		elevation.call(&"track", body)
		for point in probes:
			print("probe (%.0f, %.0f): level %d, top level %d" % [point.x, point.y,
				int(elevation.call(&"level_at", point, -99)), int(elevation.call(&"top_level_at", point, -99))])
	var player := _player()
	AbilityBox.select(player, BOW)
	player.call(&"face", aim)
	player.call(&"play_animation", "idle", true)
	for i in 30:
		await physics_frame
	if look_at != Vector2.INF:
		var camera := Camera2D.new()
		camera.name = "RenderCamera"
		camera.zoom = Vector2.ONE * (zoom if zoom > 0.0 else 1.0)
		camera.position_smoothing_enabled = false
		root.add_child(camera)
		camera.global_position = look_at
		camera.make_current()
	elif zoom > 0.0 and root.get_camera_2d() != null:
		root.get_camera_2d().zoom = Vector2(zoom, zoom)
	if grid:
		_add_grid()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("still.png")))
	print("still: feet=(%.0f, %.0f) camera=%s" % [body.global_position.x, body.global_position.y,
		str(root.get_camera_2d().get_screen_center_position()) if root.get_camera_2d() != null else "-"])
	if shoot:
		Engine.time_scale = 0.25
		_push(USE_ACTION, true)
		await _film(&"draw", hold_ms)
		_push(USE_ACTION, false)
		await _film(&"shot", max_ms)
		for shot in then:
			body.global_position = Vector2(shot[0], shot[1])
			body.velocity = Vector2.ZERO
			body.reset_physics_interpolation()
			player.call(&"face", Vector2(shot[2], shot[3]).normalized())
			for i in 4:
				await physics_frame
			_push(USE_ACTION, true)
			await _film(&"draw", hold_ms)
			_push(USE_ACTION, false)
			await _film(&"shot", max_ms)
	print("saved %d frames to %s" % [_frame, ProjectSettings.globalize_path(_out)])
	quit(0)


## Films for `ms` of game time.
func _film(label: StringName, ms: float) -> void:
	var started := Services.now_ms()
	var next := started
	while Services.now_ms() - started < ms:
		await physics_frame
		if Services.now_ms() < next:
			continue
		next += _frame_ms
		_use_fresh_art()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("frame-%03d.png" % _frame)))
		var body := _body()
		var at := body.global_position if body != null else Vector2.ZERO
		var arrows: Array[String] = []
		var world := Services.world()
		var parent: Node = world.entities_root() if world != null else null
		if parent != null:
			for child: Node in parent.get_children():
				if child is Node2D and String(child.name).begins_with("BowArrow") and not child.is_queued_for_deletion():
					var arrow_at := (child as Node2D).global_position
					arrows.append("(%.0f, %.0f)" % [arrow_at.x, arrow_at.y])
		var player := _player()
		var energy := float(player.call(&"get_energy")) if player != null else 0.0
		print("%03d %s t=%4.0f feet=(%.0f, %.0f) energy=%.0f arrows=%s" % [_frame, label, Services.now_ms() - started,
			at.x, at.y, energy, ", ".join(arrows)])
		_frame += 1


## The 64-unit cells over the world, every cell's top-left corner labelled with its world point.
func _add_grid() -> void:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	var overlay := Node2D.new()
	overlay.name = "RenderGrid"
	overlay.z_index = 200
	overlay.z_as_relative = false
	parent.add_child(overlay)
	var font := ThemeDB.fallback_font
	overlay.draw.connect(func() -> void:
		for x in range(0, 2049, 64):
			overlay.draw_line(Vector2(x, 0), Vector2(x, 2048), Color(1, 1, 1, 0.35), 1.0)
		for y in range(0, 2049, 64):
			overlay.draw_line(Vector2(0, y), Vector2(2048, y), Color(1, 1, 1, 0.35), 1.0)
		for x in range(0, 2049, 64):
			for y in range(0, 2049, 64):
				overlay.draw_string(font, Vector2(x + 2, y + 10), "%d,%d" % [x, y], HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
					Color(1, 1, 0.6, 0.9)))
	overlay.queue_redraw()


## The arrows in flight drawn from their source picture, at the size the game gave them, and the
## slime's clips and Visual on the fresh pages (FRESH_PAGES).
func _use_fresh_art() -> void:
	var world := Services.world()
	if world == null:
		return
	_use_fresh_pages()
	var sprites: Array[Sprite2D] = []
	var parent: Node = world.entities_root()
	if parent != null:
		for child: Node in parent.get_children():
			if String(child.name).begins_with("BowArrow"):
				for part: Node in child.get_children():
					if part is Sprite2D and (part as Sprite2D).texture != null and (part as Sprite2D).texture.resource_path.ends_with("arrow.webp"):
						sprites.append(part as Sprite2D)
	for sprite in sprites:
		var key := "BowArrow"
		if sprite.has_meta(&"fresh"):
			continue
		var fresh := _fresh_texture(key)
		if fresh == null or sprite.texture == null:
			continue
		var old := sprite.texture.get_size()
		var new := fresh.get_size()
		var along := old.x / new.x
		sprite.texture = fresh
		sprite.scale *= along
		sprite.set_meta(&"fresh", true)


## Every texture key of the player's clips (and its Visual) that is one of FRESH_PAGES, swapped for
## the page read from disk, once.
func _use_fresh_pages() -> void:
	var player := _player()
	if player == null or player.has_meta(&"fresh_pages"):
		return
	player.set_meta(&"fresh_pages", true)
	var pages: Dictionary = {}
	for path in FRESH_PAGES:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null:
			pages[path] = ImageTexture.create_from_image(image)
	var clips := player.get(&"animation") as AnimationPlayer
	if clips != null:
		for library_name: StringName in clips.get_animation_library_list():
			var library := clips.get_animation_library(library_name)
			for clip_name: StringName in library.get_animation_list():
				var clip := library.get_animation(clip_name)
				for track in clip.get_track_count():
					for key in clip.track_get_key_count(track):
						var value: Variant = clip.track_get_key_value(track, key)
						if value is Texture2D and pages.has((value as Texture2D).resource_path):
							clip.track_set_key_value(track, key, pages[(value as Texture2D).resource_path])
	var visual := player.get(&"visual") as Sprite2D
	if visual != null and visual.texture != null and pages.has(visual.texture.resource_path):
		visual.texture = pages[visual.texture.resource_path]


func _fresh_texture(key: String) -> Texture2D:
	if _fresh.has(key):
		return _fresh[key]
	var image := Image.load_from_file(ProjectSettings.globalize_path(str(FRESH_ART[key])))
	var texture: Texture2D = ImageTexture.create_from_image(image) if image != null else null
	_fresh[key] = texture
	return texture


func _body() -> CharacterBody2D:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player_body):
		return null
	return world.player_body


func _player() -> Node:
	var world := Services.world()
	return world.get(&"player") if world != null else null


## The key as the game reads it (tests/lib/test_context.gd `_push`): an action event through the
## viewport.
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)
