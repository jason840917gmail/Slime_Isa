extends SceneTree
## Renders the world atlas (game/dev/world_atlas.tscn, docs/godot/WORLD_ATLAS.md) with every
## region's world drawn as the game draws it, for checking the atlas and the layout outside the
## editor. Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_world_atlas.gd -- --out=<dir>
## Writes <dir>/overview.png (the whole world and the interior shelf at 1/8), <dir>/region-<world>.png
## for each region whose world is shown (its block at 1/4) and <dir>/exit-<world>-<exit>.png around
## the exits of the hand-made worlds (at 1/2, at most MAX_EXIT_CLOSE_UPS), and prints the atlas's
## warnings.

const WorldAtlas := preload("res://game/world/atlas/world_atlas.gd")
const AtlasRegion := preload("res://game/world/atlas/atlas_region.gd")
const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const SCENE := "res://game/dev/world_atlas.tscn"
const DEFAULT_OUT := "user://world-atlas"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const OVERVIEW_ZOOM := 0.125
const REGION_ZOOM := 0.25
const EXIT_ZOOM := 0.5
## The square around an exit (world units).
const EXIT_VIEW := 2048.0
const MAX_EXIT_CLOSE_UPS := 8
## The worlds are read one per frame: give up after this many frames.
const MAX_WAIT_FRAMES := 3000


func _initialize() -> void:
	var out := DEFAULT_OUT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	var atlas := (load(SCENE) as PackedScene).instantiate() as WorldAtlas
	viewport.add_child(atlas)
	var frames := 0
	while atlas.busy() and frames < MAX_WAIT_FRAMES:
		await process_frame
		frames += 1
	print("worlds read in %d frames" % frames)
	# Outside the editor world_ground.gd and the painting layers mount nothing: mount each world's
	# drawing as WorldService.register_world does (one world each, so not through it).
	for holder in atlas.holders():
		var world := (holder as AtlasRegion).world()
		if world != null:
			_mount_drawing(world)
	for i in 4:
		await physics_frame
	var map: WorldMapData = atlas.plan
	var grid := Vector2(map.cols, map.rows) * map.cell_units()
	var margin := WorldAtlas.BANNER_SPACE
	var shelf := WorldAtlas.SHELF_GAP + map.chunk_units().y if atlas.show_interiors else 0.0
	var shots := {"overview": [Rect2(-margin, -margin, grid.x + 2.0 * margin, grid.y + shelf + 2.0 * margin), OVERVIEW_ZOOM]}
	for holder in atlas.holders():
		var slot := holder as AtlasRegion
		if not slot.interior and slot.world() != null:
			shots["region-" + slot.map_id] = [Rect2(slot.position, Vector2(slot.block_size) * slot.chunk_units), REGION_ZOOM]
	var close_ups := 0
	for judged: Dictionary in atlas._exits:
		var slot := atlas.slot_of(str(judged["key"]))
		if slot == null or bool(map.region(str(judged["key"])).get("placeholder", false)) or close_ups >= MAX_EXIT_CLOSE_UPS:
			continue
		var exit: Dictionary = judged["exit"]
		var centre := slot.position + (exit["rect"] as Rect2).get_center()
		shots["exit-%s-%s" % [slot.map_id, exit["name"]]] = [Rect2(centre - Vector2.ONE * EXIT_VIEW * 0.5, Vector2.ONE * EXIT_VIEW), EXIT_ZOOM]
		close_ups += 1
	for shot_name: String in shots:
		var area: Rect2 = shots[shot_name][0]
		var zoom: float = shots[shot_name][1]
		camera.zoom = Vector2(zoom, zoom)
		viewport.size = Vector2i((area.size * zoom).ceil())
		camera.position = area.position
		for i in 4:
			await process_frame
		var file := out.path_join(shot_name + ".png")
		viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
		print("saved ", file, " ", viewport.size)
	for line in atlas._get_configuration_warnings():
		print("warning: ", line)
	quit(0)


## The ground, water, terrain edges and light by height of each ground layer, then its cliffs.
func _mount_drawing(world: Node2D) -> void:
	for child: Node in world.get_children():
		var ground := child as TileMapLayer
		var script := ground.get_script() as Script if ground != null else null
		if script != null and script.resource_path == WORLD_GROUND:
			ground.call(&"refresh")
			Elevation.mount(ground, false)
