extends SceneTree
## Renders a room scene with its floor trimmed, one picture per trim (docs/godot/INTERIOR_WALLS.md
## "Floor trim"): a `floor-trim` layer takes the place of the room's own (in memory, the scene is not
## changed) and every floor cell is painted with the trim, so its band runs along every wall. Run windowed:
##     "<Godot console exe>" --path godot -s res://tools/render_floor_trim.gd -- --scene=res://... --out=<dir> [--trims=framed-cream,bricks-slate,...]
## (every trim when --trims is left out). Writes <dir>/<scene name>-<trim>.png at 1 px a unit.
## `--painted` renders the room once with its own trim as painted (<dir>/<scene name>-painted.png).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const TrimLayer := preload("res://game/world/interior/interior_trim_layer.gd")


func _initialize() -> void:
	var scene := ""
	var out := "user://floor-trim"
	var wanted: Array[String] = []
	var painted := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--trims="):
			for name in arg.trim_prefix("--trims=").split(",", false):
				wanted.append(name)
		elif arg == "--painted":
			painted = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var tile_set := load(TrimLayer.TILESET) as TileSet
	var tiles := {}
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		tiles[str(source.get_tile_data(coords, 0).get_custom_data(TrimLayer.TRIM_DATA))] = coords
	if painted:
		wanted = ["painted"]
	elif wanted.is_empty():
		for name: String in tiles:
			wanted.append(name)
	for trim in wanted:
		if not painted and not tiles.has(trim):
			print("no trim ", trim)
			continue
		var room := (load(scene) as PackedScene).instantiate() as Node2D
		# the room's own trim makes way for the one rendered
		for child in room.get_children():
			if child is TrimLayer and not painted:
				room.remove_child(child)
				child.free()
		var walls := room.get_node_or_null("interior-walls") as InteriorWallLayer
		var size := Vector2(walls.get_used_rect().end) * 64.0
		var viewport := SubViewport.new()
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.size = Vector2i(size)
		root.add_child(viewport)
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		viewport.add_child(camera)
		viewport.add_child(room)
		var ground := room.get_node_or_null("ground") as TileMapLayer
		if ground != null:
			Elevation.mount(ground, false)
		if not painted:
			_trim_everywhere(room, walls, tile_set, tiles[trim])
		for i in 12:
			await RenderingServer.frame_post_draw
		var path := out.path_join("%s-%s.png" % [scene.get_file().get_basename(), trim])
		viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		viewport.free()
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


## A trim layer in `room`, `tile` painted on every floor cell of its walls.
func _trim_everywhere(room: Node2D, walls: InteriorWallLayer, tile_set: TileSet, tile: Vector2i) -> void:
	var layer := TrimLayer.new()
	layer.name = "floor-trim"
	layer.tile_set = tile_set
	var used := walls.get_used_rect()
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if walls.is_floor(Vector2i(x, y)):
				layer.set_cell(Vector2i(x, y), 0, tile)
	room.add_child(layer)
	room.move_child(layer, walls.get_index() + 1)
