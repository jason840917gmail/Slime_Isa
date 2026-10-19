extends SceneTree
## Captures the pictures of the Pearl's glimpse in Fatty's Lair (docs/godot/DUNGEONS.md "The seal";
## the owner, 2026-10-18: the Lair is one world per room, so the take shows a picture of the
## entrance sealing, made in advance): R1's south doorway with its seal down, then up, the world
## only (no slime, no HUD), saved as textures the take shows (`Dungeon.glimpse_pictures` in
## game/scenes/objects/dungeon/fatty-lair-dungeon.tscn) and as PNGs to look at. Capture again after
## repainting R1. Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/capture_lair_seal.gd [-- --out=<dir>]
## Writes res://asset/MAPS/objects/fattys-lair/seal-glimpse-open.res and -shut.res (ImageTextures:
## no import needed) and <dir>/seal-glimpse-open.png, -shut.png (default user://seal-glimpse).

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const MAIN_SCENE := "res://game/main.tscn"
const WORLD := "fatty-lair"
const SEAL := "Objects/r1-seal"
const OUT_RES := "res://asset/MAPS/objects/fattys-lair/seal-glimpse-%s.res"
const DEFAULT_OUT := "user://seal-glimpse"
## The view's middle above the seal: the doorway in the lower part of the picture, clear of the HUD.
const LOOK_UP := 260.0

var _out := DEFAULT_OUT


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", WORLD)
	main.set(&"playground_abilities", false)
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 60:
		await process_frame
	var world := Services.world()
	var seal := world.world_root.get_node(SEAL) as Node2D
	world.player_body.visible = false
	_hide_overlays()
	var camera: Node = world.camera
	camera.call(&"stop_follow")
	camera.call(&"center_on", seal.global_position - Vector2(0.0, LOOK_UP))
	for i in 20:
		await process_frame
	await _save("open")
	DungeonState.seal(Services.run(), "fatty-lair", "fatty-one-eye", "capture")
	seal.call(&"engage")
	seal.call(&"slam")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 1200:
		await process_frame
	camera.call(&"center_on", seal.global_position - Vector2(0.0, LOOK_UP))
	_hide_overlays()
	await _save("shut")
	DungeonState.unseal(Services.run(), "fatty-lair")
	quit(0)


## Every screen layer but the room mask (the HUD, the dungeon's key chip and minimap, the area's
## title, the fade): the picture is the room only.
func _hide_overlays() -> void:
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		if node.name != "RoomMask":
			(node as CanvasLayer).visible = false
	# The minimap sits under a plain Node in the HUD, so the HUD's layer does not hide it.
	var map_ui := root.get_tree().get_first_node_in_group(&"map_ui")
	var minimap: Variant = map_ui.get(&"minimap") if map_ui != null else null
	if minimap is CanvasItem:
		(minimap as CanvasItem).visible = false


func _save(moment: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(_out.path_join("seal-glimpse-%s.png" % moment)))
	var texture := ImageTexture.create_from_image(image)
	var err := ResourceSaver.save(texture, OUT_RES % moment, ResourceSaver.FLAG_COMPRESS)
	print("capture_lair_seal: %s -> %s (%s)" % [moment, OUT_RES % moment, error_string(err)])
