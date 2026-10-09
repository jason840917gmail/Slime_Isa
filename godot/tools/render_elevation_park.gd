extends SceneTree
## Renders the Elevation Park of the playground (game/scenes/worlds/playground.tscn,
## scripts/maps/build-elevation-park.py) with the game's own drawing, for checking the cliffs and
## their wall styles (docs/godot/ELEVATION.md "Wall styles").
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_elevation_park.gd -- --out=<dir>
## Writes <dir>/<area>.png for each of AREAS at 1x, and <dir>/<area>-2x.png for each of CLOSE_UPS.

const Services := preload("res://game/shared/services.gd")
const SCENE := "res://game/scenes/worlds/playground.tscn"
const DEFAULT_OUT := "user://elevation-park"
const CELL := 64.0
## The park's rows: name -> rect in cells.
const AREAS := {
	"squares": Rect2(0, 29, 40, 11),
	"diamonds": Rect2(0, 41, 40, 11),
	"octagons": Rect2(0, 53, 40, 11),
	"holes": Rect2(0, 64, 40, 13),
	"terraces-plateaus": Rect2(0, 77, 40, 11),
	"ridge": Rect2(0, 87, 40, 11),
	"lake": Rect2(0, 99, 40, 13),
	"ground-row": Rect2(0, 114, 40, 11),
	"showcase": Rect2(0, 129, 40, 15),
}
## Close-ups at 2x: name -> rect in cells.
const CLOSE_UPS := {
	"ridge-styles": Rect2(14, 86, 25, 10),
	"lake-styles": Rect2(12, 99, 18, 8),
	"octagon-hole": Rect2(26, 62, 14, 12),
	"masonry-octagon": Rect2(0, 53, 12, 10),
	"sandstone-diamond": Rect2(1, 41, 11, 10),
	"showcase-railings": Rect2(2, 129, 14, 13),
}


func _initialize() -> void:
	var out := DEFAULT_OUT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
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
	var elevation := Services.world().elevation
	var styles := {}
	for style: String in elevation.band_styles:
		styles[style] = int(styles.get(style, 0)) + 1
	print("walls per style: ", styles)
	for i in 4:
		await physics_frame
	for zoom: float in [1.0, 2.0]:
		var areas: Dictionary = AREAS if zoom == 1.0 else CLOSE_UPS
		camera.zoom = Vector2(zoom, zoom)
		for area_name: String in areas:
			var area: Rect2 = areas[area_name]
			viewport.size = Vector2i(area.size * CELL * zoom)
			camera.position = area.position * CELL
			for i in 4:
				await process_frame
			var file := area_name + ("" if zoom == 1.0 else "-2x") + ".png"
			viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join(file)))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)
