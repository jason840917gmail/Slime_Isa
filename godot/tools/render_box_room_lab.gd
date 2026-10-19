extends SceneTree
## Renders the box-room lab (game/dev/interior/box-room-lab.tscn, tools/build_box_room_lab.gd) with
## the game's own drawing, for checking the interior walls (docs/godot/INTERIOR_WALLS.md). Run
## windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_box_room_lab.gd -- --out=<dir> [--collision]
## Writes <dir>/lab-world.png (the whole lab at 1 px a unit), <dir>/lab-<room>.png (each room at
## 2 px a unit, the art's own density) and close-ups (lab-close-*.png, 2 px a unit). Shutters and
## the seal are shown shut. `--collision` outlines the wall layer's collision in red.

const Services := preload("res://game/shared/services.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const SCENE := "res://game/dev/interior/box-room-lab.tscn"
const DEFAULT_OUT := "user://box-room-lab"
const CELL := 64.0
const WORLD := Rect2(0, 0, 48, 28)
## Rooms and close-ups at 2x: name -> rect in cells.
const SHOTS := {
	"a-square": Rect2(0, 0, 16, 14),
	"b-l-room": Rect2(16, 0, 32, 28),
	"c-hall": Rect2(0, 14, 32, 14),
	"close-a-corner-north-shutter": Rect2(0, 0, 10, 5),
	"close-a-east-key-door": Rect2(11, 3, 9, 7),
	"close-b-boss-door": Rect2(26, 0, 10, 5),
	"close-b-inner-corner-bolt": Rect2(28, 10, 9, 13),
	"close-c-south-seal-shutter": Rect2(4, 23, 20, 5),
}


func _initialize() -> void:
	var out := DEFAULT_OUT
	var collision := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--collision":
			collision = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var world := (load(SCENE) as PackedScene).instantiate() as Node2D
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	viewport.add_child(world)
	Services.world().register_world(world)
	for i in 4:
		await physics_frame
	# shut what can be shut, so the pictures show the leaves and blocks in their gaps
	for node: Node in world.find_children("*", "Node2D", true, false):
		if node.has_method(&"shut_quietly"):
			node.call(&"shut_quietly")
		elif node.has_method(&"shut") and node.has_method(&"is_shut"):
			node.call(&"shut")
	for i in 30:
		await physics_frame
	# the pictures show the world only (no HUD, no room mask)
	for layer: Node in viewport.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	if collision:
		_draw_collision(world)
	for zoom: float in [1.0, 2.0]:
		var shots: Dictionary = {"world": WORLD} if zoom == 1.0 else SHOTS
		camera.zoom = Vector2(zoom, zoom)
		for name: String in shots:
			var area: Rect2 = shots[name]
			viewport.size = Vector2i(area.size * CELL * zoom)
			camera.position = area.position * CELL
			camera.reset_physics_interpolation()
			var image: Image
			for attempt in 10:
				for i in 6:
					await RenderingServer.frame_post_draw
				image = viewport.get_texture().get_image()
				if image != null and not image.is_empty():
					break
			image.save_png(ProjectSettings.globalize_path(out.path_join("lab-" + name + ".png")))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


func _draw_collision(world: Node2D) -> void:
	var layer := InteriorWalls.find(self)
	if layer == null:
		return
	var body := layer.get_node_or_null(InteriorWalls.COLLISION)
	if body == null:
		return
	for shape_node: Node in body.get_children():
		var shape := shape_node as CollisionShape2D
		var box := shape.shape as RectangleShape2D
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color(1, 0.15, 0.15)
		var r := Rect2(shape.position - box.size / 2.0, box.size)
		line.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
		line.z_index = 50
		world.add_child(line)
