extends SceneTree
## Builds the Weaver Hollow, Chapter 2's dungeon (docs/design/2026-10-16-dungeon-weaver-hollow.md;
## docs/godot/DUNGEONS.md "The Weaver Hollow"): one world scene per floor, painted on a canvas
## (tools/weaver_hollow/hollow_canvas.gd) and assembled by tools/weaver_hollow/hollow_scene.gd.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_weaver_hollow.gd [-- --only=<floor>]
## Writes res://game/scenes/worlds/weaver-hollow-<floor>.tscn for the floors trunk, roots, boughs and
## crown. The scenes are the builder's: rebuilding overwrites edits made in the editor, so change the
## floor here (tools/weaver_hollow/hollow_floors.gd) and build again.

const HollowFloors := preload("res://tools/weaver_hollow/hollow_floors.gd")
const SceneSave := preload("res://tools/lib/scene_save.gd")

const PATH := "res://game/scenes/worlds/weaver-hollow-%s.tscn"


func _initialize() -> void:
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var failed := false
	for floor_name: String in HollowFloors.FLOORS:
		if only != "" and floor_name != only:
			continue
		var root: Node2D = HollowFloors.build(floor_name)
		if root == null:
			continue
		var path := PATH % floor_name
		var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		var err := SceneSave.save(root, path, before)
		root.free()
		if err != OK:
			push_error("build_weaver_hollow: could not save %s (%s)" % [path, error_string(err)])
			failed = true
		else:
			print("built ", path)
	quit(1 if failed else 0)
