extends SceneTree
## Bakes the elevation cache (docs/godot/ELEVATION.md "Baked cache") of every world in
## game/scenes/scene_index.json that paints elevation, or of the worlds given:
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/bake_elevation.gd [-- --world=<id>[,<id>...]]
## Each world is built from its painting (no cache read) and saved to
## res://game/scenes/worlds/elevation_cache/<world>.res. A game run from the project also saves the
## cache of a world it had to build; an exported game only reads them, so bake (and commit) before
## exporting.

const Services := preload("res://game/shared/services.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const SCENE_INDEX := "res://game/scenes/scene_index.json"


func _initialize() -> void:
	var only := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--world="):
			only = arg.trim_prefix("--world=").split(",", false)
	await process_frame
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE_INDEX))
	Elevation.ignore_cache = true
	var baked := 0
	var failed := 0
	for id: String in index:
		if not id.begins_with("world."):
			continue
		var world_id := id.trim_prefix("world.")
		if not only.is_empty() and not only.has(world_id):
			continue
		var packed := load(str(index[id])) as PackedScene
		if packed == null:
			continue
		var world := packed.instantiate() as Node2D
		var ground := world.get_node_or_null("ground") as TileMapLayer
		var painted := Elevation.find_layer(ground) if ground != null else null
		if painted == null or painted.get_used_cells().is_empty():
			world.free()
			continue
		root.add_child(world)
		var started := Time.get_ticks_msec()
		Services.world().register_world(world)
		var elevation: Elevation = Services.world().elevation
		var err := elevation.save_cache() if elevation != null else ERR_UNAVAILABLE
		if err == OK:
			baked += 1
			print("%s: baked in %d ms -> %s" % [world_id, Time.get_ticks_msec() - started, elevation.cache_path()])
		else:
			failed += 1
			print("%s: not baked (%s)" % [world_id, error_string(err)])
		world.queue_free()
		await process_frame
	print("elevation caches: %d baked, %d failed" % [baked, failed])
	quit(0 if failed == 0 else 1)
