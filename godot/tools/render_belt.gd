extends SceneTree
## Renders the potion belt (docs/godot/specs/crafting.md 12.4) in the running game, for the owner's
## pictures: it starts `--map` with the slime's feet at `--feet`, learns `--learn` quietly (the HUD's
## Ability and Roll slots), opens three belt slots quietly, puts 3 Slime Tonics and 1 Fizzy Brew in
## the bag and sets them to slots 1 and 2 (slot 3 stays empty), then saves:
## - `hud.png`: the HUD console with the potions group;
## - `bag.png`: the bag with the Slime Tonic selected and its Belt row;
## - `ceremony.png`: the fourth belt slot found (its ceremony card), then `hud-four.png` with all four.
## Run windowed (it renders), one game window at a time, from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_belt.gd -- --out=<dir>
##         [--map=level-1-c4] [--feet=<x>,<y>] [--window=<w>x<h>, 1280x960] [--learn=dodge,goo-bombs]

const Services := preload("res://game/shared/services.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://belt"
const CEREMONY_CARD_MS := 2400
const RENDER_SAVES := "user://render-saves"

var _out := DEFAULT_OUT


func _initialize() -> void:
	var map := "level-1-c4"
	var feet := Vector2(1024.0, 1088.0)
	var window := Vector2i(1280, 960)
	var learn := PackedStringArray(["dodge", "goo-bombs"])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--feet="):
			var xy := arg.trim_prefix("--feet=").split(",")
			feet = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(wh[0]), int(wh[1]))
		elif arg.begins_with("--learn="):
			learn = arg.trim_prefix("--learn=").split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(window)
	await process_frame
	# The run's autosave goes to a folder of its own, never over the player's slot 0.
	if Services.run() != null:
		Services.run().save_root = RENDER_SAVES
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 30:
		await process_frame
	_place(feet)
	var run := Services.run()
	for ability_id in learn:
		run.learn_ability(ability_id, true)
	run.quiet_items = true
	run.add_item("belt-slot", 3)
	run.quiet_items = false
	run.add_item("hp-potion", 3)
	run.add_item("energy-potion", 1)
	run.set_potion_belt_kind(0, "hp-potion")
	run.set_potion_belt_kind(1, "energy-potion")
	print("belt: open=%d kinds=%s" % [run.potion_belt_open(), str(run.potion_belt_kinds())])
	await _wait_ms(700)
	await _save("hud")
	var menus := root.get_tree().get_first_node_in_group(&"menu_windows")
	if menus != null:
		menus.call(&"open_bag")
		await _wait_ms(300)
		var bag: Node = menus.get(&"bag")
		var slots := run.slots()
		for index in slots.size():
			if str(slots[index]["item_id"]) == "hp-potion":
				bag.call(&"select_item", index)
				break
		await _wait_ms(300)
		await _save("bag")
		bag.call(&"close")
		await _wait_ms(400)
	run.add_item("belt-slot", 1)
	await _wait_ms(CEREMONY_CARD_MS)
	await _save("ceremony")
	_press_key()
	await _wait_ms(1200)
	await _save("hud-four")
	print("saved to %s" % ProjectSettings.globalize_path(_out))
	quit(0)


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await process_frame


func _press_key() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = pressed
		Input.parse_input_event(key)


func _save(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(file_name + ".png")))


func _place(at: Vector2) -> void:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player_body):
		return
	var body := world.player_body
	body.global_position = at
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	if world.elevation != null:
		world.elevation.call(&"track", body)
