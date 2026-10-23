extends SceneTree
## Captures a room world in the running game with its collision drawn over it (docs/godot/
## INTERIOR_WALLS.md "Pits and holes"): each elevation level's outline or painted cells in its
## colour (LevelCollisionLayer.LEVEL_COLOURS: 0 red, -1 blue, 1 yellow, 2 cyan, 3 green, -2 violet,
## -3 magenta), every static body's shape (white), the kit's decks (green) and hazards (orange: its
## rectangle, and filled the cells it catches on) and the slime's body (cyan). Run windowed:
##     "<Godot console exe>" --path godot -s res://tools/render_room_collision.gd -- --map=<world> --out=<dir>
##         [--prefix=x] [--feet=<x>,<y>] [--level=<n>] [--hold=<action>[+<action>]] [--hold-ms=<ms>]
##         [--automatic] [--no-overlay]
## Writes <dir>/<prefix>.png at a 1600 x 900 window, the slime's feet at `feet` (room units); with
## `hold` the slime walks with those input actions held for `hold-ms` (230: less than a ledge push)
## before the capture, to show where the collision stops it (`--hold=move_down+move_right`). Prints the
## slime's feet and the camera's screen transform, to crop a close-up. `level` puts the slime on that
## level (else the one it walks on there); `automatic` clears the world's painted `level-collision`
## for the run (never saved) to show its automatic collision.

const Services := preload("res://game/shared/services.gd")
const LevelCollision := preload("res://game/world/elevation/level_collision_layer.gd")


func _initialize() -> void:
	var out := "user://room-collision"
	var prefix := "room"
	var map_id := "fatty-lair-r7-bell-bridge"
	var feet := Vector2(-1, -1)
	var overlay := true
	var hold: PackedStringArray = []
	var hold_ms := 230.0
	var level := -99
	var automatic := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--prefix="):
			prefix = arg.trim_prefix("--prefix=")
		elif arg.begins_with("--map="):
			map_id = arg.trim_prefix("--map=")
		elif arg.begins_with("--feet="):
			var xy := arg.trim_prefix("--feet=").split(",")
			feet = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--hold="):
			hold = arg.trim_prefix("--hold=").split("+")
		elif arg.begins_with("--hold-ms="):
			hold_ms = float(arg.trim_prefix("--hold-ms="))
		elif arg.begins_with("--level="):
			level = int(arg.trim_prefix("--level="))
		elif arg == "--automatic":
			automatic = true
		elif arg == "--no-overlay":
			overlay = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	Services.run().ensure_started()
	Services.run().autosave_enabled = false
	var main := (load("res://game/main.tscn") as PackedScene).instantiate()
	main.set(&"map_id", map_id)
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 90:
		await process_frame
	var world := Services.world()
	var painted_layer := LevelCollisionLayer.find_beside(world.ground_layer)
	if automatic and painted_layer != null:
		painted_layer.clear()
		world.elevation.rebuild()
		for i in 4:
			await process_frame
	if feet.x >= 0.0:
		var player = world.player
		var body := world.player_body
		player.teleport(feet - (body.global_position - player.get_centre()))
		if level != -99:
			world.elevation.track(body, level)
		else:
			world.elevation.track(body)
		body.reset_physics_interpolation()
		world.camera.start_follow(body, true)
	for i in 30:
		await process_frame
	if not hold.is_empty():
		for action in hold:
			_push(action, true)
		var until := Time.get_ticks_msec() + int(hold_ms)
		while Time.get_ticks_msec() < until:
			await physics_frame
		for action in hold:
			_push(action, false)
		for i in 10:
			await process_frame
	if overlay:
		_draw(world)
	print("feet ", world.player_body.global_position, " canvas ", world.world_root.get_viewport().get_canvas_transform())
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join(prefix + ".png")))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit()


## An input action pressed or released, as the game reads it (tests/lib/test_context.gd `_push`).
func _push(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)


func _line(parent: Node, a: Vector2, b: Vector2, colour: Color, width: float = 2.0) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = colour
	line.points = PackedVector2Array([a, b])
	line.z_index = 100
	line.z_as_relative = false
	parent.add_child(line)


func _box(parent: Node, rect: Rect2, colour: Color) -> void:
	var p := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		_line(parent, p[i], p[(i + 1) % 4], colour)


func _draw(world: Node) -> void:
	var holder := Node2D.new()
	holder.name = "CollisionOverlay"
	world.world_root.add_child(holder)
	var colours := LevelCollision.LEVEL_COLOURS
	var elevation: Node = world.elevation
	if elevation != null:
		for body: Node in elevation.get_node("Collision").get_children():
			for shape_node: Node in body.get_children():
				var shape := shape_node as CollisionShape2D
				if shape == null:
					continue
				var level := int(str(body.name).trim_prefix("Level")) if str(body.name).begins_with("Level") else 9
				var colour: Color = colours.get(level, Color.WHITE)
				if shape.shape is ConcavePolygonShape2D:
					var segs := (shape.shape as ConcavePolygonShape2D).segments
					for i in range(0, segs.size(), 2):
						_line(holder, shape.to_global(segs[i]), shape.to_global(segs[i + 1]), colour)
				elif shape.shape is RectangleShape2D:
					var size := (shape.shape as RectangleShape2D).size
					_box(holder, Rect2(shape.global_position - size / 2.0, size), colour)
	for node: Node in world.world_root.find_children("*", "CollisionShape2D", true, false):
		var shape := node as CollisionShape2D
		if elevation != null and elevation.is_ancestor_of(shape):
			continue
		if shape.disabled or not shape.shape is RectangleShape2D or not shape.get_parent() is StaticBody2D:
			continue
		var size := (shape.shape as RectangleShape2D).size
		_box(holder, Rect2(shape.global_position - size / 2.0, size), Color.WHITE)
	# hazards: the rectangle thin, the floor cells of its level it catches on filled
	for node: Node in world.world_root.get_tree().get_nodes_in_group(&"hazards"):
		if not node.has_method(&"rect"):
			continue
		var area: Rect2 = node.call(&"rect")
		_box(holder, area, Color(1, 0.6, 0.1, 0.6))
		for cell: Rect2 in node.call(&"_pit_floor_cells"):
			var fill := Polygon2D.new()
			var at := area.position + cell.position
			fill.polygon = PackedVector2Array([at, at + Vector2(cell.size.x, 0), at + cell.size, at + Vector2(0, cell.size.y)])
			fill.color = Color(1, 0.6, 0.1, 0.22)
			fill.z_index = 99
			fill.z_as_relative = false
			holder.add_child(fill)
	for node: Node in world.world_root.get_tree().get_nodes_in_group(&"hazard_deck"):
		if node.has_method(&"deck_rects"):
			for r: Rect2 in node.call(&"deck_rects"):
				_box(holder, r.grow(-2), Color(0.3, 1, 0.3))
	# the slime's body (its collision rect)
	var body: CharacterBody2D = world.player_body
	for node: Node in body.get_children():
		var shape := node as CollisionShape2D
		if shape != null and shape.shape is RectangleShape2D:
			var size := (shape.shape as RectangleShape2D).size
			_box(holder, Rect2(shape.global_position - size / 2.0, size), Color(0.2, 1, 1))
