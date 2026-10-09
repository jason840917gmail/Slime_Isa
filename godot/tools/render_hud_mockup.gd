extends SceneTree
## Renders the frames under the HUD console mockup (docs/design/2026-10-07-hud-console-mockup.md):
## plays the game (main.tscn) inside a SubViewport at 2x and saves
## - `before.png`: today's view and HUD on an 8:7 window (the 1024 x 896 base);
## - `frame-window.png` and `frame-wide.png`: the console's base (1024 x 1024) on an 8:7 window
##   (1170 x 1024) and on a 16:9 one (1820 x 1024), with every CanvasLayer hidden and the view
##   lifted by half the console, so the slime sits in the middle of the 16 x 14 play area above it.
## `scripts/art/build-hud-console-mockup.py` then draws the console over them.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_hud_mockup.gd -- --map=level-1 --out=<dir>
## The run's saves go to <dir>/saves, never to the player's.

const Services := preload("res://game/shared/services.gd")
const MAIN := "res://game/main.tscn"
const SCALE := 2
const CONSOLE := 128.0
const BEFORE := Vector2i(1024, 896)
const SHOTS := {"window": Vector2i(1170, 1024), "wide": Vector2i(1820, 1024)}
## Frames to let the world, its NPCs and the HUD settle before the first capture.
const SETTLE_FRAMES := 240

var _out := "user://hud-mockup"


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	await process_frame
	Services.run().save_root = _out.path_join("saves")
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size_2d_override_stretch = true
	_size(viewport, BEFORE)
	root.add_child(viewport)
	var main := (load(MAIN) as PackedScene).instantiate()
	viewport.add_child(main)
	for i in SETTLE_FRAMES:
		await process_frame
	var camera := main.get_node("WorldCamera") as Camera2D
	_save(viewport, "before.png")
	_hide_layers(main)
	for shot: String in SHOTS:
		_size(viewport, SHOTS[shot])
		camera.process_mode = Node.PROCESS_MODE_INHERIT
		for i in 30:
			await process_frame
		camera.process_mode = Node.PROCESS_MODE_DISABLED
		camera.offset = Vector2.ZERO
		camera.global_position += Vector2(0.0, CONSOLE * 0.5)
		for i in 4:
			await process_frame
		_save(viewport, "frame-%s.png" % shot)
	quit(0)


func _save(viewport: SubViewport, file: String) -> void:
	var path := ProjectSettings.globalize_path(_out.path_join(file))
	viewport.get_texture().get_image().save_png(path)
	print("saved ", path)


func _size(viewport: SubViewport, canvas: Vector2i) -> void:
	viewport.size = canvas * SCALE
	viewport.size_2d_override = canvas


## Hides every CanvasLayer above the world (HUD, windows, hints, fps) and the CanvasItems under it
## (the minimap hangs under a plain Node, which a hidden layer does not hide).
func _hide_layers(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer and (child as CanvasLayer).layer >= 1:
			(child as CanvasLayer).visible = false
			_hide_items(child)
		_hide_layers(child)


func _hide_items(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		_hide_items(child)
