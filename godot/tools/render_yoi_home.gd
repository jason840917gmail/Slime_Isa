extends SceneTree
## Renders steps B4 to B6 of the Release 1 plan in the running game, for the owner's pictures (Yoi's
## home, the Charged Roll, the weight cue, the war journal): one `--shot` per run, saved as PNGs in
## `--out`. Run windowed (it renders), one game window at a time, from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_yoi_home.gd -- --out=<dir>
##         --shot=<yard|hatch-open|home|card|weights|page|recipe|journal> [--window=<w>x<h>, 1280x720]
## - `yard`: Lili's west yard (level-1-c4) with the heap of crates over Yoi's hatch (`yard.png`);
## - `hatch-open`: the same after every crate of the heap is gulped away (`hatch-open.png`);
## - `home`: Yoi's den with Yoi (`home.png`), then his first talk (`home-talk.png`);
## - `card`: the Charged Roll found in his chest: its card (`charged-roll-card.png`);
## - `weights`: the weight cue on a light pot (`weight-light.png`), a medium crate (`weight-medium.png`)
##   and a heavy keg at Gulp level 1 (`weight-heavy.png`), and a try at the keg (`weight-strain.png`);
## - `page`: war-journal page 2 found: its reading panel (`page.png`);
## - `recipe`: the sally port's recipe page: its panel (`recipe-page.png`);
## - `journal`: pages 1 and 2 found and two tips heard: the journal's War journal section
##   (`journal.png`).
## Its autosaves go to `user://tool-saves` (RunState, a run from res://tools/), never over the player's slots.

const Services := preload("res://game/shared/services.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://yoi-home"
const CARD_MS := 2400

var _out := DEFAULT_OUT


func _initialize() -> void:
	var shot := "yard"
	var window := Vector2i(1280, 720)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(window)
	await process_frame
	var run := Services.run()
	if run != null:
		run.ensure_started()
		# Past the prologue (Plop met), so nothing of it plays.
		run.quiet_items = true
		run.set_flag("prologue.done")
		run.quiet_items = false
	var map := "level-1-c4"
	if shot in ["home", "card", "weights", "page", "recipe", "journal"]:
		map = "slimeshire-yoi-home"
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 30:
		await process_frame
	match shot:
		"yard":
			_place(Vector2(440.0, 1010.0))
			_camera(Vector2(345.0, 900.0), 1.6)
			await _wait_ms(700)
			await _save("yard")
		"hatch-open":
			_place(Vector2(440.0, 1010.0))
			_camera(Vector2(345.0, 900.0), 1.6)
			await _wait_ms(400)
			var hatch := _find(main, "yoi-hatch")
			var heap: Array = hatch.call(&"heap_on_it") if hatch != null else []
			for crate: Node in heap:
				var script := crate.get_node_or_null(^"LiftableScript")
				if script != null:
					script.call(&"take")
			await _wait_ms(900)
			print("hatch open: %s, flag: %s" % [str(hatch.call(&"is_open")) if hatch != null else "-",
				str(run.has_flag("level-1.yoi-hatch-open"))])
			await _save("hatch-open")
		"home":
			_place(Vector2(470.0, 420.0))
			_face(Vector2.RIGHT)
			await _wait_ms(800)
			await _save("home")
			var interaction: Variant = main.get(&"interaction")
			if interaction != null and is_instance_valid(interaction):
				(interaction as Node).call(&"refresh", null)
				print("interact: %s" % str((interaction as Node).call(&"handle_interact")))
			await _wait_ms(900)
			await _save("home-talk")
		"card":
			_place(Vector2(520.0, 600.0))
			await _wait_ms(500)
			run.add_item("charged-roll", 1)
			await _wait_ms(CARD_MS)
			print("roll-charge learned: %s" % str(run.has_learned_ability("roll-charge")))
			await _save("charged-roll-card")
		"weights":
			var feet := Vector2(560.0, 280.0)
			_place(feet)
			_face(Vector2.RIGHT)
			_camera(feet + Vector2(20.0, 0.0), 1.6)
			var pot := ThrowAmmo.spawn_liftable("clay-pot", feet + Vector2(36.0, 2.0), {"weight": "light", "pop": false})
			await _wait_ms(500)
			await _save("weight-light")
			pot.queue_free()
			var crate := ThrowAmmo.spawn_liftable("crate", feet + Vector2(36.0, 2.0), {"weight": "medium", "pop": false})
			await _wait_ms(400)
			await _save("weight-medium")
			crate.queue_free()
			_face(Vector2.DOWN)
			var keg := ThrowAmmo.spawn_liftable("keg", feet + Vector2(0.0, 36.0), {"weight": "heavy", "pop": false})
			await _wait_ms(400)
			await _save("weight-heavy")
			var player: Node = Services.world().player
			var hold: Object = player.call(&"get_mouth_hold")
			if hold != null:
				hold.call(&"press")
			await _wait_ms(300)
			await _save("weight-strain")
			print("keg too heavy: %s" % str(keg.get_node(^"LiftableScript").call(&"is_too_heavy")))
		"page":
			_place(Vector2(520.0, 440.0))
			await _wait_ms(400)
			run.add_item("war-journal-page-2", 1)
			await _wait_ms(700)
			await _save("page")
		"recipe":
			_place(Vector2(520.0, 440.0))
			await _wait_ms(400)
			run.add_item("recipe-page-berry-basket", 1)
			await _wait_ms(700)
			print("basket known: %s" % str(run.knows_recipe("cook-berry-basket")))
			await _save("recipe-page")
		"journal":
			_place(Vector2(520.0, 440.0))
			run.quiet_items = true
			run.add_item("war-journal-page-1", 1)
			run.add_item("war-journal-page-2", 1)
			run.quiet_items = false
			run.hear_tip("yoi.old-gates")
			run.hear_tip("yoi.fallen-helmets")
			await _wait_ms(300)
			var menus := root.get_tree().get_first_node_in_group(&"menu_windows")
			if menus != null:
				menus.call(&"toggle_journal")
			await _wait_ms(300)
			var journal := root.get_tree().get_first_node_in_group(&"quest_journal")
			if journal != null:
				var rows: Array = (journal.call(&"model") as Dictionary).get("rows", [])
				for index in rows.size():
					if str((rows[index] as Dictionary).get("id", "")) == "@war-journal":
						journal.call(&"select_quest", index)
			await _wait_ms(400)
			await _save("journal")
	print("saved to %s" % ProjectSettings.globalize_path(_out))
	quit(0)


func _find(from: Node, node_name: String) -> Node:
	return from.find_child(node_name, true, false)


func _camera(at: Vector2, zoom: float) -> void:
	var camera := Camera2D.new()
	camera.name = "RenderCamera"
	camera.zoom = Vector2.ONE * zoom
	camera.position_smoothing_enabled = false
	root.add_child(camera)
	camera.global_position = at
	camera.make_current()


func _face(direction: Vector2) -> void:
	var world := Services.world()
	if world != null and world.player != null:
		world.player.call(&"face", direction)


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await process_frame


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
