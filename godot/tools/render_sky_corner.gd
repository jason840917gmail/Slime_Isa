extends SceneTree
## Renders the playground's sky corner (docs/godot/SKY_FLOOR.md) with the game's own drawing, for
## checking the sky floor's backdrop, its cloud bank and the islands' walls.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_sky_corner.gd -- --out=<dir>
## Writes <dir>/sky-corner.png (the whole corner at 1x) and <dir>/<name>-2x.png for each of CLOSE_UPS.
## `--cells=<x>,<y>,<w>,<h>` renders that rectangle of cells instead, at `--zoom=<n>` (2), as
## <dir>/sky-cells.png. `--no-lip` hides the sky floor's lips (the bank up the walls' feet), to see the
## walls as the elevation draws them.

const Services := preload("res://game/shared/services.gd")
const SCENE := "res://game/scenes/worlds/playground.tscn"
const DEFAULT_OUT := "user://sky-corner"
const CELL := 64.0
## The corner, in cells.
const CORNER := Rect2(100, 67, 24, 22)
## Close-ups at 2x: name -> rect in cells.
const CLOSE_UPS := {
	"north-west": Rect2(100, 67, 12, 11),
	"north-east": Rect2(112, 67, 12, 11),
	"south-west": Rect2(100, 78, 12, 11),
	"south-east": Rect2(112, 78, 12, 11),
}


func _initialize() -> void:
	var out := DEFAULT_OUT
	var cells := Rect2()
	var cells_zoom := 2.0
	var no_lip := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--cells="):
			var parts := arg.trim_prefix("--cells=").split_floats(",")
			if parts.size() == 4:
				cells = Rect2(parts[0], parts[1], parts[2], parts[3])
		elif arg == "--no-lip":
			no_lip = true
		elif arg.begins_with("--zoom="):
			cells_zoom = maxf(0.25, arg.trim_prefix("--zoom=").to_float())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var world := (load(SCENE) as PackedScene).instantiate() as Node2D
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	viewport.add_child(world)
	# As the game does: water, terrain edges and the elevation with its collision.
	Services.world().register_world(world)
	for i in 6:
		await physics_frame
	if no_lip:
		for lip: Node in world.find_children("SkyLip-*", "MeshInstance2D", true, false):
			(lip as CanvasItem).visible = false
	# name -> [rect in cells, zoom]
	var shots := {}
	if cells.has_area():
		shots["sky-cells"] = [cells, cells_zoom]
	else:
		shots["sky-corner"] = [CORNER, 1.0]
		for close_up: String in CLOSE_UPS:
			shots[close_up + "-2x"] = [CLOSE_UPS[close_up], 2.0]
	for shot: String in shots:
		var area: Rect2 = shots[shot][0]
		var zoom: float = shots[shot][1]
		camera.zoom = Vector2(zoom, zoom)
		viewport.size = Vector2i(area.size * CELL * zoom)
		camera.position = area.position * CELL
		for i in 6:
			await process_frame
		viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join(shot + ".png")))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)
