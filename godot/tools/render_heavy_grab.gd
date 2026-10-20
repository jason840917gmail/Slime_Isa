extends SceneTree
## Records the Heavy grab's poses (docs/godot/SKINS.md "Heavy") in the running game: it starts the
## playground (the body-shapes mode is on there), lends the Heavy skin, stands the slime beside the
## Skins corner's heavy statue on each side in turn (west, east, north, south of it), and records a
## touch (the hint), the grab held still, a push and a pull, saving a frame every FRAME_MS of game
## time. The statue goes back to its cell between the sides. Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_heavy_grab.gd -- --out=<dir>
##         [--block=<x>,<y>] [--sides=west,east,north,south] [--plain] [--map=<world id> --direct]
##         [--quick]
## Writes <dir>/<side>-<n>.png (1920 x 1080) and prints a line per frame (phase, the grab's pose, its
## clip, the block's place, the slime's feet in the frame's pixels). `--plain` leaves the skin off (the
## strain). `--map` starts another world (with `--direct` as F6 on it does: its `dungeon.devPowers`, the
## Heavy skin in Fatty's Lair); `--quick` grabs at once, as a player who knows the key does (no touch
## phase). Each line also names the control hint showing. Nothing is saved; the scenes are not changed.

const Services := preload("res://game/shared/services.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://heavy-grab"
const FRAME_MS := 80.0
## The Skins corner's heavy statue (game/dev/corners/skins_corner.tscn).
const DEFAULT_BLOCK := Vector2(7140.0, 940.0)
## Side -> the way the slime faces the block from there.
const SIDES := {"west": Vector2.RIGHT, "east": Vector2.LEFT, "north": Vector2.DOWN, "south": Vector2.UP}
## The phases of one side: [name, held actions ("toward" / "away" name the walk keys), ms].
const PHASES: Array = [
	["touch", ["toward"], 400.0],
	["grab", ["interact"], 400.0],
	["push", ["interact", "toward"], 1500.0],
	["hold", ["interact"], 300.0],
	["pull", ["interact", "away"], 1500.0],
	["let-go", [], 300.0],
]
const KEYS := {Vector2.RIGHT: &"move_right", Vector2.LEFT: &"move_left", Vector2.DOWN: &"move_down", Vector2.UP: &"move_up"}


func _initialize() -> void:
	var out := DEFAULT_OUT
	var block_at := DEFAULT_BLOCK
	var sides: PackedStringArray = ["west", "east", "north", "south"]
	var plain := false
	var map := "playground"
	var direct := false
	var quick := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--block="):
			var xy := arg.trim_prefix("--block=").split(",")
			block_at = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--sides="):
			sides = arg.trim_prefix("--sides=").split(",", false)
		elif arg == "--plain":
			plain = true
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg == "--direct":
			direct = true
		elif arg == "--quick":
			quick = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	# The game's own view size, so a frame's pixels are the screen's (the log's screen positions).
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"direct_world_run", direct)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	# The world settles first (a room's entry, the area banner): a press right after the load is lost.
	for i in 120:
		await process_frame
	if not plain and not SkinState.is_on(null, SkinState.HEAVY):
		SkinState.lend(SkinState.HEAVY)
	var hints := main.get_node_or_null(^"ControlHints")
	var player: Node = Services.world().player
	var body := player.get(&"body") as CharacterBody2D
	var block := _block_near(block_at)
	if block == null:
		push_error("render_heavy_grab: no heavy block near %s" % block_at)
		quit(1)
		return
	var home := block.global_position
	var frames := 0
	for side: String in sides:
		var facing: Vector2 = SIDES[side]
		block.global_position = home
		block.reset_physics_interpolation()
		# The grab's stand point (heavy_grab.gd `_stand_point`): the body's 30 x 26 rect 3 px off the
		# block's 58 x 50 footprint; the feet are 13 under the body's middle.
		var distance := (29.0 + 15.0 + 3.0) if facing.x != 0.0 else (25.0 + 13.0 + 3.0)
		body.global_position = home - facing * distance + Vector2(0.0, 13.0)
		body.velocity = Vector2.ZERO
		body.reset_physics_interpolation()
		player.call(&"face", facing)
		for i in 20:
			await physics_frame
		var shot := 0
		# Keys held from one phase into the next stay down (letting go of interact would let go).
		var down: Array[StringName] = []
		for phase: Array in PHASES:
			if quick and phase[0] == "touch":
				continue
			var held: Array[StringName] = []
			for name: String in phase[1]:
				held.append(KEYS[facing] if name == "toward" else KEYS[-facing] if name == "away" else StringName(name))
			for action in down:
				if not held.has(action):
					_push(action, false)
			for action in held:
				if not down.has(action):
					_push(action, true)
			down = held
			var started := Services.now_ms()
			var next := started
			while Services.now_ms() - started < float(phase[2]):
				await physics_frame
				if Services.now_ms() >= next:
					next += FRAME_MS
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join("%s-%03d.png" % [side, shot])))
					var grab: Variant = player.get(&"_grab")
					# The window's pixels (the stretch scales the 1024-tall view to the window).
					var screen := root.get_final_transform() * body.get_global_transform_with_canvas().origin
					print("%s %s %03d t=%4.0f pose=%s clip=%s block=(%.0f, %.0f) screen=(%.0f, %.0f) hint=%s" % [side,
							phase[0], shot, Services.now_ms() - started, str(grab.call(&"pose")) if grab != null else "?",
							str((player.get(&"animation") as AnimationPlayer).assigned_animation),
							block.global_position.x, block.global_position.y, screen.x, screen.y,
							str(hints.get(&"current")) if hints != null else "?"])
					shot += 1
					frames += 1
		for action in down:
			_push(action, false)
		for i in 30:
			await physics_frame
	print("saved %d frames to %s" % [frames, ProjectSettings.globalize_path(out)])
	quit(0)


func _block_near(at: Vector2) -> Node2D:
	var best: Node2D = null
	for node: Node in root.get_tree().get_nodes_in_group(&"heavy_blocks"):
		var candidate := node as Node2D
		if candidate != null and (best == null or candidate.global_position.distance_to(at) < best.global_position.distance_to(at)):
			best = candidate
	return best if best != null and best.global_position.distance_to(at) < 64.0 else null


## The key as the game reads it (tests/lib/test_context.gd `_push`): an action event through the
## viewport.
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)
