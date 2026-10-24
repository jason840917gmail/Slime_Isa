extends SceneTree
## Films the plank lab (docs/godot/DUNGEONS.md "Falling planks over water"; tools/build_plank_lab.gd)
## in the running game, a few frames per moment, each the game's own view with the HUD: a Roll held
## across the long bridge (the planks dropping into the lake behind it), a walk onto it (the plank
## gives, the slime sinks with a splash, it is back on the bank with less health), and a chest on the
## island giving its Goo Heart (the heart rising out of it). The classic game (the Roll held rolls
## on; in the body-shapes mode the charged Roll does the same); the ceremonies' cards are off.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/film_planks.gd -- --out=<dir>
## Writes <dir>/<nn>-<shot>.png and <dir>/shots.json (each frame's caption).

const Services := preload("res://game/shared/services.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://plank-film"
const MAP_ID := "playground-planks"
const CELL := 64.0
const FEET := 27.56
const LONG_X := 5.5 * CELL
const SOUTH_SHORE := 12.0 * CELL
## The slack after a fall before the planks are all back (the slab return time and its rise).
const PLANKS_BACK_MS := 11500.0

var _main: Node
var _out := DEFAULT_OUT
var _captions: Array = []
var _index := 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(Vector2i(1024, 768))
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set(&"map_id", MAP_ID)
	_main.set(&"ability_ceremonies", false)
	root.add_child(_main)
	for i in 90:
		await process_frame
	var run := Services.run()
	if not run.has_learned_ability("dodge"):
		run.learn_session_ability("dodge")
	# 1. The Roll held across the long bridge.
	await _stand(Vector2(LONG_X, SOUTH_SHORE - FEET + 27.0), Vector2.UP)
	await _shot("bank", "The long bridge: eight loose planks over the lake, no landing")
	_push(&"move_up", true)
	_push(&"dodge", true)
	await _wait_ms(320.0)
	await _shot("roll-spin", "The Roll held: it spins up on the bank")
	await _wait_ms(330.0)
	await _shot("roll-1", "It rolls on: each plank creaks and gives behind it")
	await _wait_ms(330.0)
	await _shot("roll-2", "Behind the ball the planks drop into the water")
	await _wait_ms(330.0)
	await _shot("roll-3", "Still rolling: no landing to stop on")
	# Held until the feet are on the island.
	var real_start := Time.get_ticks_msec()
	while Services.world().player_body.global_position.y > 4.0 * CELL - 16.0 and Time.get_ticks_msec() - real_start < 4000:
		await physics_frame
	_push(&"dodge", false)
	_push(&"move_up", false)
	await _wait_ms(900.0)
	await _shot("roll-island", "Over, on the island: only a Roll that keeps rolling crosses; the planks sink behind")
	await _wait_ms(PLANKS_BACK_MS)
	# 2. A walk onto it.
	await _stand(Vector2(LONG_X, SOUTH_SHORE - FEET + 27.0), Vector2.UP)
	_push(&"move_up", true)
	await _wait_ms(280.0)
	await _shot("walk-1", "Walking: the first plank creaks and shakes")
	await _wait_ms(260.0)
	_push(&"move_up", false)
	await _shot("walk-2", "It drops: the slime sinks with a splash")
	await _wait_ms(260.0)
	await _shot("walk-3", "Rings on the water where it fell in")
	await _wait_ms(700.0)
	await _shot("walk-back", "Back on the bank it came from, a little health lost")
	# 3. The heart chest.
	await _stand(Vector2(9.3 * CELL, 3.7 * CELL - FEET), Vector2.LEFT)
	await _shot("chest", "On the island: a closed chest")
	var chest := Services.world().world_root.get_node_or_null(^"heart-chest/ChestScript")
	if chest != null:
		chest.call(&"request_open")
	await _wait_ms(250.0)
	await _shot("heart-1", "Opened: a Goo Heart rises out of it")
	await _wait_ms(450.0)
	await _shot("heart-2", "+10 max HP, health full (no chest window: only the heart was inside)")
	await _wait_ms(500.0)
	await _shot("heart-3", "The chest stays open for good")
	var json := FileAccess.open(ProjectSettings.globalize_path(_out.path_join("shots.json")), FileAccess.WRITE)
	json.store_string(JSON.stringify(_captions, "\t"))
	json.close()
	print("saved to ", ProjectSettings.globalize_path(_out))
	quit(0)


func _stand(centre: Vector2, facing: Vector2) -> void:
	var player: Node = Services.world().player
	var body := Services.world().player_body
	player.call(&"teleport", centre)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	player.call(&"face", facing)
	for i in 20:
		await physics_frame


func _shot(shot_name: String, caption: String) -> void:
	await RenderingServer.frame_post_draw
	_index += 1
	var file := "%02d-%s.png" % [_index, shot_name]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(file)))
	_captions.append({"file": file, "caption": caption})
	print("shot ", file)


## Waits `ms` of game time (at most three times as long in real time).
func _wait_ms(ms: float) -> void:
	var started := Services.now_ms()
	var real_start := Time.get_ticks_msec()
	while Services.now_ms() - started < ms and Time.get_ticks_msec() - real_start < ms * 3.0 + 2000.0:
		await physics_frame


## The key as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)
