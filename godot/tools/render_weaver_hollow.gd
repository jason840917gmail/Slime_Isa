extends SceneTree
## Renders the Weaver Hollow's floors (tools/build_weaver_hollow.gd) with the game's own drawing, for
## checking them by picture. Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_weaver_hollow.gd -- --out=<dir> [--floor=<name>] [--zoom=<z>] [--rooms] [--collision]
## `--scene=res://...` renders that world instead (whole, at `--zoom`).
## Writes <dir>/<world>.png (the whole floor at `--zoom`, 0.5 by default) and, with `--rooms`,
## <dir>/<world>-<room>.png for each of its camera rooms at 1x. `--collision` draws each level's
## collision outline over it (level 0 red, 1 yellow, 2 cyan, holes blue).

const Services := preload("res://game/shared/services.gd")
const FLOORS: PackedStringArray = ["trunk", "roots", "boughs", "crown"]
const PATH := "res://game/scenes/worlds/weaver-hollow-%s.tscn"
const DEFAULT_OUT := "user://weaver-hollow"
const CELL := 64.0


func _initialize() -> void:
	var out := DEFAULT_OUT
	var only := ""
	var zoom := 0.5
	var rooms := false
	var collision := false
	var scene := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--floor="):
			only = arg.trim_prefix("--floor=")
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--rooms":
			rooms = true
		elif arg == "--collision":
			collision = true
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	if scene != "":
		await _render(scene, out, zoom, rooms, collision)
		print("saved to ", ProjectSettings.globalize_path(out))
		quit(0)
		return
	for floor_name in FLOORS:
		if only != "" and floor_name != only:
			continue
		var path := PATH % floor_name
		if not ResourceLoader.exists(path):
			continue
		await _render(path, out, zoom, rooms, collision)
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


func _render(path: String, out: String, zoom: float, rooms: bool, collision: bool) -> void:
	var world := (load(path) as PackedScene).instantiate() as Node2D
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	var ground := world.get_node("ground") as Node
	var columns := int(ground.get_meta("columns", 48))
	var rows_count := int(ground.get_meta("rows", 42))
	viewport.add_child(world)
	var started := Time.get_ticks_msec()
	Services.world().register_world(world)
	print("%s registered in %d ms" % [world.name, Time.get_ticks_msec() - started])
	for i in 4:
		await physics_frame
	if collision and Services.world().elevation != null:
		_draw_collision(Services.world().elevation)
	var shots := {str(world.name): [Rect2(0, 0, columns * CELL, rows_count * CELL), zoom]}
	if rooms:
		for room: Node in (world.get_node("CameraRooms").get_children() if world.has_node("CameraRooms") else []):
			var rect: Rect2 = room.call(&"rect")
			shots["%s-%s" % [world.name, room.name]] = [rect, 1.0]
	for shot_name: String in shots:
		var rect: Rect2 = shots[shot_name][0]
		var z: float = shots[shot_name][1]
		camera.zoom = Vector2(z, z)
		viewport.size = Vector2i(rect.size * z)
		camera.position = rect.position
		camera.reset_physics_interpolation()
		for i in 2:
			await physics_frame
		var image: Image
		for attempt in 10:
			for i in 6:
				await RenderingServer.frame_post_draw
			image = viewport.get_texture().get_image()
			if not _blank(image):
				break
		image.save_png(ProjectSettings.globalize_path(out.path_join(shot_name + ".png")))
	Services.world().clear()
	viewport.queue_free()
	await process_frame


func _draw_collision(elevation: Node2D) -> void:
	var colours := {-1: Color(0.3, 0.5, 1.0), 0: Color(1.0, 0.2, 0.2), 1: Color(1.0, 0.9, 0.2), 2: Color(0.2, 1.0, 1.0), 3: Color(1.0, 0.3, 1.0)}
	for body: Node in elevation.get_node("Collision").get_children():
		var level := int(str(body.name).trim_prefix("Level"))
		var holder := body.get_child(0) as CollisionShape2D if body.get_child_count() > 0 else null
		if holder == null or not holder.shape is ConcavePolygonShape2D:
			continue
		var shape := holder.shape as ConcavePolygonShape2D
		var segments := shape.segments
		for i in range(0, segments.size(), 2):
			var line := Line2D.new()
			line.width = 3.0
			line.default_color = colours.get(level, Color.WHITE)
			line.points = PackedVector2Array([segments[i], segments[i + 1]])
			elevation.add_child(line)


## True when every sampled pixel of `image` is the same colour (a frame not drawn yet).
func _blank(image: Image) -> bool:
	var first := image.get_pixel(image.get_width() / 3, image.get_height() / 3)
	for k in 9:
		var at := Vector2i((k % 3 + 1) * image.get_width() / 4, (k / 3 + 1) * image.get_height() / 4)
		if not image.get_pixelv(at).is_equal_approx(first):
			return false
	return true
