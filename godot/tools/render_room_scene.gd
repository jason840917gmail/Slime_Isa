extends SceneTree
## Renders one room scene on its own, as the editor shows it (its interior walls, floor and objects,
## no game around it), at 2 px a unit (docs/godot/INTERIOR_WALLS.md). Run windowed:
##     "<Godot console exe>" --path godot -s res://tools/render_room_scene.gd -- --scene=res://... --out=<dir>
## Writes <dir>/<scene name>.png.


const Elevation := preload("res://game/world/elevation/elevation.gd")


func _initialize() -> void:
	var scene := ""
	var out := "user://room-scene"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var room := (load(scene) as PackedScene).instantiate() as Node2D
	var walls := room.get_node_or_null("interior-walls") as TileMapLayer
	var size := Vector2(1152, 1024)
	if walls != null:
		size = Vector2(walls.get_used_rect().end) * 64.0
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(size * 2.0)
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.zoom = Vector2(2, 2)
	viewport.add_child(camera)
	viewport.add_child(room)
	# as the editor does: the elevation layer's preview of the pits and holes
	var ground := room.get_node_or_null("ground") as TileMapLayer
	if ground != null:
		Elevation.mount(ground, false)
	for i in 20:
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join(scene.get_file().get_basename() + ".png")))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)
