extends SceneTree
## Captures a room world in the running game with its collision drawn over it (docs/godot/
## INTERIOR_WALLS.md "Pits and holes"): each elevation level's outline (level 0 red, -1 blue, 1
## yellow, -3 magenta), every static body's shape (white), the kit's decks (green) and hazards
## (orange: its rectangle, and filled the cells of its floor level it catches on). Run windowed:
##     "<Godot console exe>" --path godot -s res://tools/render_room_collision.gd -- --map=<world> --out=<dir>
##         [--prefix=x] [--feet=<x>,<y>] [--no-overlay]
## Writes <dir>/<prefix>.png at a 1600 x 900 window, the slime's feet at `feet` (room units).

const Services := preload("res://game/shared/services.gd")


func _initialize() -> void:
	var out := "user://room-collision"
	var prefix := "room"
	var map_id := "fatty-lair-r7-bell-bridge"
	var feet := Vector2(-1, -1)
	var overlay := true
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
	if feet.x >= 0.0:
		var player = world.player
		var body := world.player_body
		player.teleport(feet - (body.global_position - player.get_centre()))
		world.elevation.track(body)
		body.reset_physics_interpolation()
		world.camera.start_follow(body, true)
	for i in 30:
		await process_frame
	if overlay:
		_draw(world)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join(prefix + ".png")))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit()


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
	var colours := {-3: Color(1, 0.3, 1), -2: Color(0.8, 0.3, 1), -1: Color(0.3, 0.6, 1), 0: Color(1, 0.2, 0.2), 1: Color(1, 0.9, 0.2), 2: Color(0.2, 1, 1)}
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
