extends SceneTree
## Renders an octagon hill (levels 1 and 2) with the game's own elevation drawing, as the backdrop
## for the stairs mockups (stairs_mockup.py, README.md). Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s "<absolute path to this file>" -- --out=<dir>
## Writes <dir>/octagon-L1.png and octagon-L2.png (2 px per world unit, origin at world 0, 0).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")
const DEFAULT_OUT := "user://stairs-mockup"
const CELL := 64
const SHEET := 19
## The octagon as painted (screen rows), x ranges per row.
const ROWS := [[3, 9], [2, 10], [1, 11], [0, 12], [0, 12], [0, 12], [1, 11], [2, 10], [3, 9]]
const AREA := Rect2i(0, 0, 25, 24)
## Where the octagon's first row starts (cells).
const AT := Vector2i(6, 8)
const ZOOM := 2.0


func _initialize() -> void:
	var out := DEFAULT_OUT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	await process_frame
	var playground := (load("res://game/scenes/worlds/playground.tscn") as PackedScene).instantiate()
	var pg := playground.get_node("ground") as TileMapLayer
	var sample := Vector2i(10, 50)
	var source := pg.get_cell_source_id(sample)
	print("ground ", pg.get_cell_tile_data(sample).get_custom_data("tile_id"), " source ", source)
	var tiles := pg.tile_set
	var level_tiles := (playground.get_node("elevation") as TileMapLayer).tile_set
	playground.free()
	for level in [1, 2]:
		var viewport := SubViewport.new()
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.size = Vector2i(int(AREA.size.x * CELL * ZOOM), int(AREA.size.y * CELL * ZOOM))
		root.add_child(viewport)
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		camera.position = Vector2(AREA.position * CELL)
		camera.zoom = Vector2(ZOOM, ZOOM)
		viewport.add_child(camera)
		var world := Node2D.new()
		viewport.add_child(world)
		var ground := TileMapLayer.new()
		ground.name = "ground"
		ground.tile_set = tiles
		ground.set_meta("columns", AREA.size.x)
		ground.set_meta("rows", AREA.size.y)
		world.add_child(ground)
		var painted := TileMapLayer.new()
		painted.name = "elevation"
		painted.tile_set = level_tiles
		painted.visible = false
		world.add_child(painted)
		for y in range(AREA.position.y, AREA.end.y):
			for x in range(AREA.position.x, AREA.end.x):
				ground.set_cell(Vector2i(x, y), source, Vector2i(posmod(x, SHEET), posmod(y, SHEET)))
		for r in ROWS.size():
			for x in range(ROWS[r][0], ROWS[r][1] + 1):
				painted.set_cell(AT + Vector2i(x, r), 0, Vector2i(2 + level, 0))
		TerrainEdges.mount(ground)
		Elevation.mount(ground, false)
		for i in 8:
			await process_frame
		var image := viewport.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path(out.path_join("octagon-L%d.png" % level)))
		print("saved L", level, " ", image.get_size(), " origin ", AREA.position * CELL)
		viewport.queue_free()
		await process_frame
	quit(0)
