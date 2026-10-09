extends SceneTree
## Renders the ability ceremony (game/ui/ceremony/ability_ceremony.gd) in the running game, for
## tuning it without playing to a quest: it starts the playground like a new run, learns an
## ability (the Roll by default) and saves screenshots as the bubble rises, the card shows, and the
## slime gulps the bubble down after a key press.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_ceremony.gd -- --out=<dir> [--ability=swallow]
## Writes <dir>/ceremony-<n>.png.

const Services := preload("res://game/shared/services.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://ceremony"
## Moments on the ceremony's own clock (it runs slower than the wall clock here: every screenshot
## stalls a frame) at which a screenshot is taken; the key is pressed at PRESS_AT, and the last two
## shots follow the gulp.
const SHOTS: Array[float] = [0.35, 0.8, 1.3, 2.1]
const PRESS_AT := 2.2
const GULP_SHOTS: Array[float] = [0.2, 0.45]


func _initialize() -> void:
	var out := DEFAULT_OUT
	var ability := "dodge"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--ability="):
			ability = arg.trim_prefix("--ability=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", "playground")
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 30:
		await process_frame
	Services.run().learn_ability(ability)
	var ceremony: Node = null
	while ceremony == null or not bool(ceremony.call(&"is_playing")):
		await process_frame
		ceremony = root.get_node_or_null(^"AbilityCeremony")
	var shot := 0
	for at: float in SHOTS:
		while float(ceremony.get(&"_age")) < at:
			await process_frame
		_save(out, shot)
		shot += 1
	while float(ceremony.get(&"_age")) < PRESS_AT:
		await process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key)
	for at: float in GULP_SHOTS:
		while float(ceremony.get(&"_gulp_age")) < at:
			await process_frame
		_save(out, shot)
		shot += 1
	quit(0)


func _save(out: String, shot: int) -> void:
	var path := ProjectSettings.globalize_path(out.path_join("ceremony-%d.png" % shot))
	root.get_texture().get_image().save_png(path)
	print("render_ceremony: shot %d -> %s" % [shot, path])
