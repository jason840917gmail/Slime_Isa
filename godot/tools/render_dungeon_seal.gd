extends SceneTree
## Renders the dungeon's seal and the Pearl's take (docs/godot/DUNGEONS.md "The seal") in the running
## game, in the dungeon lab: the Pearl risen on its altar once its guard fell, the take's roar (dust
## over the screen), the glimpse of the entrance's seal slamming shut, the seal standing shut, the
## boss in his rage with his name red on the boss bar, and the seal breaking at his fall. For tuning
## the look; nothing is saved.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_dungeon_seal.gd -- --out=<dir>
## Writes <dir>/seal-<nn>-<moment>.png.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SealMoment := preload("res://game/dungeon/seal_moment.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://seal-render"
const LAB := "dungeon-lab"
const GUARD := "dungeon-lab-guard"
const BOSS := "dungeon-lab-boss"
const PEARL_WATCH := Vector2(2560, 1420)
const PEARL_AT := Vector2(2560, 1171.2)
const SEAL_WATCH := Vector2(1536, 3300)
const BOSS_WATCH := Vector2(1536, 640)

var _out: String = DEFAULT_OUT
var _shot: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(Vector2i(1024, 1024))
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", LAB)
	main.set(&"playground_abilities", false)
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 60:
		await process_frame
	var run := Services.run()
	# The Pearl room: its guard falls, the Pearl rises on its altar.
	_take_guard_out()
	_place_slime(PEARL_WATCH)
	DungeonState.mark_boss_beaten(run, LAB, GUARD)
	await _wait_ms(1400.0)
	await _save("pearl-risen")
	# The take: the roar and its dust, then the glimpse of the entrance's seal.
	_place_slime(PEARL_AT + Vector2(72, 30))
	print("render_dungeon_seal: the take at %d ms" % Time.get_ticks_msec())
	await _wait_real_ms(120.0)
	await _save("roar")

	await _wait_real_ms(700.0)
	await _save("glimpse-slam")
	await _wait_real_ms(60.0)
	await _save("glimpse-sealed")
	await _wait_real_ms(1400.0)
	await _save("back")
	# The seal shut, close.
	_place_slime(SEAL_WATCH)
	await _wait_ms(900.0)
	await _save("seal-shut")
	# A distant roar's dust, and the roar's.
	SealMoment.dust(Services.world().world_root, Color("#efe3c4"), 140)
	await _wait_real_ms(500.0)
	await _save("dust")
	# The boss in his rage.
	_place_slime(BOSS_WATCH)
	await _wait_ms(1500.0)
	await _save("boss-enraged")
	await _wait_ms(500.0)
	await _save("boss-enraged-b")
	# His fall: the seal breaks.
	DungeonState.mark_boss_beaten(run, LAB, BOSS)
	_place_slime(SEAL_WATCH)
	await _wait_ms(700.0)
	await _save("seal-breaking")
	await _wait_ms(800.0)
	await _save("seal-broken")
	print("render_dungeon_seal: sealed %s" % DungeonState.is_sealed(run, LAB))
	quit(0)


## The Pearl's guard leaves (the render does not fight him): his fight finished quietly.
func _take_guard_out() -> void:
	var fight := Services.world().world_root.find_child("c1-fight", true, false)
	if fight != null:
		fight.call(&"finish_quietly")


func _place_slime(centre: Vector2) -> void:
	var body := Services.world().player_body
	body.global_position = centre + Vector2(0.0, 27.56)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	if Services.world().elevation != null:
		Services.world().elevation.call(&"track", body)


func _wait_ms(ms: float) -> void:
	var started := Services.now_ms()
	while Services.now_ms() - started < ms:
		await physics_frame


func _wait_real_ms(ms: float) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < ms:
		await process_frame


func _save(moment: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var file := "seal-%02d-%s.png" % [_shot, moment]
	_shot += 1
	var path := ProjectSettings.globalize_path(_out.path_join(file))
	root.get_texture().get_image().save_png(path)
	var sequence := Services.world().world_root.find_child("SealMoment", true, false)
	print("render_dungeon_seal: %s (%d ms, glimpse %s)" % [path, Time.get_ticks_msec(),
		sequence.call(&"is_glimpsing") if sequence != null else "-"])
