extends SceneTree
## Renders the cliff sides lab (game/scenes/worlds/cliff-sides-lab.tscn, tools/build_cliff_sides_lab.gd)
## with the game's own drawing, for checking the side walls (docs/godot/ELEVATION.md "Side walls").
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_cliff_sides_lab.gd -- --out=<dir> [--only=<name>] [--look=<look>]
## Writes <dir>/<area>.png for each of AREAS at 1x and <dir>/<area>-2x.png for each of CLOSE_UPS
## (with `--only`, those whose name begins with it).
## `--look=front` draws the lab with the front-only cliffs instead (the ground's `cliff_look`), for
## comparing; `--collision` draws each level's collision outline over it (level 0 red, 1 yellow,
## 2 cyan, 3 magenta, holes blue). `--scene=res://...` renders another world instead, whole at 1x
## (`world.png`), with `--look` and `--wall-style=<style>` (its grass's wall style) set in memory
## only: the scene file is not touched; `--rect=<x>,<y>,<w>,<h>` (cells) adds a close-up of it at 2x
## (`close-2x.png`).

const Services := preload("res://game/shared/services.gd")
const SCENE := "res://game/scenes/worlds/cliff-sides-lab.tscn"
const DEFAULT_OUT := "user://cliff-sides-lab"
const CELL := 64.0
## Whole rows at 1x: name -> rect in cells.
const AREAS := {
	"lab": Rect2(0, 0, 70, 52),
	"grounds": Rect2(0, 51, 70, 31),
}
## Close-ups at 2x (the art's own resolution): name -> rect in cells.
const CLOSE_UPS := {
	"reference": Rect2(0, 1, 17, 14),
	"blocks": Rect2(16, 2, 34, 13),
	"l-shape": Rect2(49, 1, 18, 14),
	"u-shapes": Rect2(0, 16, 31, 13),
	"octagon": Rect2(30, 16, 16, 12),
	"terrace": Rect2(46, 15, 23, 18),
	"hole-open-u": Rect2(1, 35, 32, 10),
	"ramps-diamond": Rect2(33, 35, 29, 10),
	"grounds-a": Rect2(0, 51, 35, 14),
	"grounds-b": Rect2(33, 51, 35, 14),
	"grounds-c": Rect2(0, 65, 35, 14),
	"grounds-d": Rect2(33, 65, 35, 14),
}


func _initialize() -> void:
	var out := DEFAULT_OUT
	var only := ""
	var look := "sides"
	var collision := false
	var scene := SCENE
	var wall_style := ""
	var close_rect := Rect2()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--look="):
			look = arg.trim_prefix("--look=")
		elif arg == "--collision":
			collision = true
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--wall-style="):
			wall_style = arg.trim_prefix("--wall-style=")
		elif arg.begins_with("--rect="):
			var r := arg.trim_prefix("--rect=").split(",")
			close_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var world := (load(scene) as PackedScene).instantiate() as Node2D
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	var ground := world.get_node("ground") as Node
	ground.set_meta(&"cliff_look", look)
	if wall_style != "":
		var styles: Dictionary = ground.get_meta(&"cliff_wall_styles", {}).duplicate()
		styles["highland"] = wall_style
		ground.set_meta(&"cliff_wall_styles", styles)
	var areas_1x := AREAS
	var close_ups := CLOSE_UPS
	if scene != SCENE:
		areas_1x = {"world": Rect2(0, 0, int(ground.get_meta("columns", 64)), int(ground.get_meta("rows", 64)))}
		close_ups = {"close": close_rect} if close_rect.size != Vector2.ZERO else {}
	viewport.add_child(world)
	# As the game does: water, terrain edges and the elevation with its collision.
	var started := Time.get_ticks_msec()
	Services.world().register_world(world)
	var vertices := 0
	var sides := Services.world().elevation.get_node_or_null("Sides")
	for mesh_instance: Node in (sides.get_children() if sides != null else []):
		vertices += ((mesh_instance as MeshInstance2D).mesh as ArrayMesh).surface_get_array_len(0)
	print("world registered in %d ms; side meshes: %d vertices" % [Time.get_ticks_msec() - started, vertices])
	for i in 4:
		await physics_frame
	if collision:
		_draw_collision(Services.world().elevation)
	for zoom: float in [1.0, 2.0]:
		var areas: Dictionary = areas_1x if zoom == 1.0 else close_ups
		camera.zoom = Vector2(zoom, zoom)
		for area_name: String in areas:
			if only != "" and not area_name.begins_with(only):
				continue
			var area: Rect2 = areas[area_name]
			viewport.size = Vector2i(area.size * CELL * zoom)
			camera.position = area.position * CELL
			camera.reset_physics_interpolation()
			for i in 2:
				await physics_frame
			# A freshly resized viewport sometimes hands back a blank frame: wait until it has a picture.
			var image: Image
			for attempt in 10:
				for i in 6:
					await RenderingServer.frame_post_draw
				image = viewport.get_texture().get_image()
				if not _blank(image):
					break
			var file := area_name + ("" if zoom == 1.0 else "-2x") + ".png"
			image.save_png(ProjectSettings.globalize_path(out.path_join(file)))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


func _draw_collision(elevation: Node2D) -> void:
	var colours := {-1: Color(0.3, 0.5, 1.0), 0: Color(1.0, 0.2, 0.2), 1: Color(1.0, 0.9, 0.2), 2: Color(0.2, 1.0, 1.0), 3: Color(1.0, 0.3, 1.0)}
	for body: Node in elevation.get_node("Collision").get_children():
		var level := int(str(body.name).trim_prefix("Level"))
		var shape := (body.get_child(0) as CollisionShape2D).shape as ConcavePolygonShape2D
		var segments := shape.segments
		for i in range(0, segments.size(), 2):
			var line := Line2D.new()
			line.width = 2.0
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
