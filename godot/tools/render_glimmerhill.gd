extends SceneTree
## Films Glimmerhill asleep and waking (docs/godot/VILLAGERS.md "Asleep until its Pearl comes home")
## and the Pearls' homecoming at the Wellspring (docs/godot/PROLOGUE.md "The homecoming") in the
## running game: it starts a world with the slime's feet at `--feet`, sets `--flags` (a part's wake
## flag wakes it on screen), waits `--settle-ms` and saves a still (`<--still>.png`); then, with
## `--then-flags`, sets those flags (a Pearl taken: `pearl.fatty-one-eye`, which plays the homecoming
## when the slime stands by the pool; or a wake flag), optionally moves the slime to `--move-to`, and
## films a frame every `--frame-ms` of real time for `--film-ms` (`frame-<n>.png`). Run windowed (it
## renders), one game window at a time, from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_glimmerhill.gd -- --out=<dir>
##         --map=<world id> --feet=<x>,<y> [--camera=<x>,<y>] [--zoom=<z>] [--window=<w>x<h>, 960x540]
##         [--flags=<flag>,...] [--settle-ms=600] [--still=still] [--then-flags=<flag>,...]
##         [--move-to=<x>,<y>] [--film-ms=0] [--frame-ms=400] [--close-cards-ms=2500] [--grid] [--hide-hud]
## `--close-cards-ms`: a ceremony card on screen that long is closed with a key press (the homecoming's).
## Before the still: `--recipes=a,b` are learned, `--items=<id>:<n>,...` go into the bag, `--coins=<n>`
## sets the coins and `--energy=<n>` the slime's energy. `--interact` presses the interact key on what
## the interaction offers once the still is saved (a campfire's craft panel, the shop counter, a
## fountain's drink) and saves `<still>-used.png` `--used-ms` (500) later; the film, if any, follows.
## `--camera` looks there with a camera of its own (at `--zoom`, else 1) instead of the game's;
## `--grid` draws the 64-unit cells with their world coordinates over the picture. `--pre-flags=a,b`
## are in the run before the world is built, set quietly (no end card, nothing woken on screen).

const Services := preload("res://game/shared/services.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://glimmerhill"

var _out := DEFAULT_OUT


func _initialize() -> void:
	var map := "west-village-b4"
	var feet := Vector2(1056.0, 1056.0)
	var zoom := 0.0
	var window := Vector2i(960, 540)
	var flags := PackedStringArray()
	var then_flags := PackedStringArray()
	var pre_flags := PackedStringArray()
	var settle_ms := 600.0
	var still := "still"
	var film_ms := 0.0
	var close_cards_ms := 2500.0
	var frame_ms := 400.0
	var grid := false
	var hide_hud := false
	var look_at := Vector2.INF
	var move_to := Vector2.INF
	var recipes := PackedStringArray()
	var items := PackedStringArray()
	var coins := -1
	var energy := -1.0
	var interact := false
	var used_ms := 500.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--feet="):
			feet = _point(arg.trim_prefix("--feet="))
		elif arg.begins_with("--camera="):
			look_at = _point(arg.trim_prefix("--camera="))
		elif arg.begins_with("--move-to="):
			move_to = _point(arg.trim_prefix("--move-to="))
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(wh[0]), int(wh[1]))
		elif arg.begins_with("--flags="):
			flags = arg.trim_prefix("--flags=").split(",", false)
		elif arg.begins_with("--pre-flags="):
			pre_flags = arg.trim_prefix("--pre-flags=").split(",", false)
		elif arg.begins_with("--then-flags="):
			then_flags = arg.trim_prefix("--then-flags=").split(",", false)
		elif arg.begins_with("--settle-ms="):
			settle_ms = float(arg.trim_prefix("--settle-ms="))
		elif arg.begins_with("--still="):
			still = arg.trim_prefix("--still=")
		elif arg.begins_with("--film-ms="):
			film_ms = float(arg.trim_prefix("--film-ms="))
		elif arg.begins_with("--close-cards-ms="):
			close_cards_ms = float(arg.trim_prefix("--close-cards-ms="))
		elif arg.begins_with("--frame-ms="):
			frame_ms = float(arg.trim_prefix("--frame-ms="))
		elif arg.begins_with("--recipes="):
			recipes = arg.trim_prefix("--recipes=").split(",", false)
		elif arg.begins_with("--items="):
			items = arg.trim_prefix("--items=").split(",", false)
		elif arg.begins_with("--coins="):
			coins = int(arg.trim_prefix("--coins="))
		elif arg.begins_with("--energy="):
			energy = float(arg.trim_prefix("--energy="))
		elif arg == "--interact":
			interact = true
		elif arg.begins_with("--used-ms="):
			used_ms = float(arg.trim_prefix("--used-ms="))
		elif arg == "--grid":
			grid = true
		elif arg == "--hide-hud":
			hide_hud = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(window)
	# The autoloads are in the tree (their data loaded) one frame in.
	await process_frame
	var early := Services.run()
	if early != null and not pre_flags.is_empty():
		early.ensure_started()
		var known: Array = early.call(&"_flags")
		for flag in pre_flags:
			if not flag in known:
				known.append(flag)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 30:
		await process_frame
	_place(feet)
	var run := Services.run()
	if run != null:
		for flag in flags:
			run.set_flag(flag)
		if not recipes.is_empty():
			run.learn_recipes(Array(recipes))
		for item in items:
			var parts := item.split(":")
			run.add_item(parts[0], int(parts[1]) if parts.size() > 1 else 1)
		if coins >= 0:
			run.add_coins(coins - run.coins())
	if energy >= 0.0 and Services.world() != null and Services.world().player != null:
		Services.world().player.call(&"set_energy", energy)
	if hide_hud:
		var hud: Variant = main.get(&"hud")
		if hud is CanvasItem or hud is CanvasLayer:
			hud.set(&"visible", false)
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
	var until := Time.get_ticks_msec() + int(settle_ms)
	while Time.get_ticks_msec() < until:
		await process_frame
	await _save(still)
	print("still: feet=%s camera=%s" % [str(feet),
		str(root.get_camera_2d().get_screen_center_position()) if root.get_camera_2d() != null else "-"])
	if interact:
		var interaction: Variant = main.get(&"interaction")
		if interaction != null and is_instance_valid(interaction):
			(interaction as Node).call(&"refresh", null)
			var offered: Dictionary = (interaction as Node).call(&"current")
			print("interact: %s -> %s" % [str(offered.get("prompt", "-")), str((interaction as Node).call(&"handle_interact"))])
		var used_until := Time.get_ticks_msec() + int(used_ms)
		while Time.get_ticks_msec() < used_until:
			await process_frame
		await _save(still + "-used")
	if not then_flags.is_empty() or film_ms > 0.0:
		if move_to != Vector2.INF:
			_place(move_to)
		if run != null:
			for flag in then_flags:
				run.set_flag(flag)
		var started := Time.get_ticks_msec()
		var next := started
		var frame := 0
		var card_since := -1
		while Time.get_ticks_msec() - started < int(film_ms):
			await process_frame
			var ceremony := root.get_node_or_null(^"AbilityCeremony")
			if ceremony != null and bool(ceremony.call(&"is_playing")):
				if card_since < 0:
					card_since = Time.get_ticks_msec()
				elif Time.get_ticks_msec() - card_since > int(close_cards_ms):
					_press_key()
					card_since = -1
			else:
				card_since = -1
			if Time.get_ticks_msec() < next:
				continue
			next += int(frame_ms)
			await _save("frame-%03d" % frame)
			print("%03d t=%5d camera=%s" % [frame, Time.get_ticks_msec() - started,
				str(root.get_camera_2d().get_screen_center_position()) if root.get_camera_2d() != null else "-"])
			frame += 1
	print("saved to %s" % ProjectSettings.globalize_path(_out))
	quit(0)


func _press_key() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = pressed
		Input.parse_input_event(key)


func _save(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(file_name + ".png")))


func _place(feet: Vector2) -> void:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player_body):
		return
	var body := world.player_body
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	if world.elevation != null:
		world.elevation.call(&"track", body)


static func _point(text: String) -> Vector2:
	var xy := text.split(",")
	return Vector2(float(xy[0]), float(xy[1]))


## The 64-unit cells over the world, every other cell's top-left corner labelled with its world point.
func _add_grid() -> void:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	var rect := world.world_rect()
	var overlay := Node2D.new()
	overlay.name = "RenderGrid"
	overlay.z_index = 200
	overlay.z_as_relative = false
	parent.add_child(overlay)
	var font := ThemeDB.fallback_font
	overlay.draw.connect(func() -> void:
		for x in range(0, int(rect.size.x) + 1, 64):
			overlay.draw_line(Vector2(x, 0), Vector2(x, rect.size.y), Color(1, 1, 1, 0.3), 1.0)
		for y in range(0, int(rect.size.y) + 1, 64):
			overlay.draw_line(Vector2(0, y), Vector2(rect.size.x, y), Color(1, 1, 1, 0.3), 1.0)
		for x in range(0, int(rect.size.x) + 1, 128):
			for y in range(0, int(rect.size.y) + 1, 128):
				overlay.draw_string(font, Vector2(x + 2, y + 12), "%d,%d" % [x, y], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(1, 1, 0.6, 0.95)))
	overlay.queue_redraw()
