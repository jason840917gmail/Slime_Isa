extends SceneTree
## Renders a world's forest with the game's own drawing, for judging tree art at play scale
## (docs/godot/FORESTS.md). A slime stands in the picture for scale.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_forest.gd -- \
##         --scene=res://game/scenes/worlds/chunks/gloop-forest-e5.tscn [--rect=x,y,w,h] [--out=<dir>]
## --rect is in cells (default: the 20 x 12 window whose forest cover is nearest half); --solid
## tints the painted cells' solid parts (as the layer's collision shapes them), to spot open
## ground inside a wall. Writes
## <dir>/<scene>.png at 1x (the game's base view is 20 x 11 cells) and <dir>/<scene>-2x.png, the
## middle of it at 2x; <dir>/<scene>-sway-<n>.png are four moments of the sway, at 2x.
## --canopy=<column> repaints every painted cell with that palette tile first (18: the canopy wall,
## FORESTS.md "Canopy walls"), to compare the two kinds of wood on the same cells; the file names
## get "-canopy". A canopy atlas the editor has not imported yet is read from its file.

const Services := preload("res://game/shared/services.gd")
const DEFAULT_OUT := "user://forest-render"
const CELL := 64.0
const WINDOW := Vector2i(20, 12)
const SLIME_SHEET := "res://asset/characters/256x256-tile_8x8-slime-v2-page-1.webp"
const CanopyWalls := preload("res://game/world/forest/canopy_walls.gd")


func _initialize() -> void:
	var out := DEFAULT_OUT
	var scene_path := ""
	var rect := Rect2i()
	var solid := false
	var canopy := -1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg == "--solid":
			solid = true
		elif arg.begins_with("--canopy="):
			canopy = int(arg.trim_prefix("--canopy="))
		elif arg.begins_with("--rect="):
			var p := arg.trim_prefix("--rect=").split(",")
			rect = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var world := (load(scene_path) as PackedScene).instantiate() as Node2D
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	viewport.add_child(camera)
	viewport.add_child(world)
	Services.world().register_world(world)
	var forest := _forest(world)
	if canopy >= 0 and forest != null:
		_preload_canopy_textures()
		_add_missing_palette_tile(forest, Vector2i(canopy, 0))
		for cell in forest.get_used_cells():
			forest.set_cell(cell, 0, Vector2i(canopy, 0))
		await process_frame
		await process_frame
	if rect.size == Vector2i.ZERO:
		var definition := world.get_node_or_null(^"world-definition")
		var bounds := Rect2i(0, 0, int(definition.get(&"columns")), int(definition.get(&"rows"))) \
				if definition != null else forest.get_used_rect()
		rect = _busy_window(forest, bounds)
	var trees := forest.get_node(^"Trees").get_child_count() if forest != null and forest.has_node(^"Trees") else 0
	print("forest cells ", forest.get_used_cells().size() if forest else 0, ", trees ", trees, ", window ", rect)
	_add_slime(world, forest, rect)
	if solid and forest != null:
		forest.add_child(_solid_overlay(forest))
	for i in 4:
		await physics_frame
	var name := scene_path.get_file().get_basename() + ("-canopy" if canopy >= 0 else "")
	var shots := [[1.0, Rect2(rect), name + ".png"]]
	var middle := Rect2(Vector2(rect.position) + Vector2(rect.size) * 0.25, Vector2(rect.size) * 0.5)
	shots.append([2.0, middle, name + "-2x.png"])
	for zoom_rect_file: Array in shots:
		await _shot(viewport, camera, zoom_rect_file[0], zoom_rect_file[1], out.path_join(zoom_rect_file[2]))
	for n in 4:
		await create_timer(0.8).timeout
		await _shot(viewport, camera, 2.0, middle, out.path_join("%s-sway-%d.png" % [name, n]))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


func _shot(viewport: SubViewport, camera: Camera2D, zoom: float, area: Rect2, path: String) -> void:
	camera.zoom = Vector2(zoom, zoom)
	viewport.size = Vector2i(area.size * CELL * zoom)
	camera.position = area.position * CELL
	for i in 4:
		await process_frame
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _forest(world: Node) -> TileMapLayer:
	for node in world.find_children("*", "TileMapLayer", true, false):
		if node is ForestLayer:
			return node as TileMapLayer
	return null


## The window of WINDOW cells inside `used` whose forest cover is nearest half (a wall and open
## ground).
func _busy_window(forest: TileMapLayer, used: Rect2i) -> Rect2i:
	if forest == null:
		return Rect2i(Vector2i.ZERO, WINDOW)
	var painted := {}
	for cell in forest.get_used_cells():
		painted[cell] = true
	var best := Rect2i(used.position, WINDOW)
	var best_score := INF
	for y in range(used.position.y, used.end.y - WINDOW.y + 1, 2):
		for x in range(used.position.x, used.end.x - WINDOW.x + 1, 2):
			var count := 0
			for dy in WINDOW.y:
				for dx in WINDOW.x:
					if painted.has(Vector2i(x + dx, y + dy)):
						count += 1
			var score := absf(count / float(WINDOW.x * WINDOW.y) - 0.5)
			if score < best_score:
				best_score = score
				best = Rect2i(x, y, WINDOW.x, WINDOW.y)
	return best


## A slime (the player's look and size) on the open cell nearest the window's middle.
func _add_slime(world: Node2D, forest: TileMapLayer, rect: Rect2i) -> void:
	var spot := Vector2(rect.get_center())
	if forest != null:
		var best := INF
		for y in range(rect.position.y + 2, rect.end.y - 2):
			for x in range(rect.position.x + 2, rect.end.x - 2):
				var open := true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						open = open and forest.get_cell_source_id(Vector2i(x + dx, y + dy)) < 0
				var d := Vector2(x, y).distance_to(Vector2(rect.get_center()))
				if open and d < best:
					best = d
					spot = Vector2(x, y) + Vector2(0.5, 0.7)
	var slime := Sprite2D.new()
	slime.texture = load(SLIME_SHEET)
	slime.hframes = 8
	slime.vframes = 8
	slime.frame = 7
	slime.centered = false
	slime.offset = Vector2(-128, -128)
	slime.scale = Vector2(0.28125, 0.28125)
	var body := Node2D.new()
	body.position = spot * CELL
	slime.position = Vector2(0, -27.56)
	body.add_child(slime)
	(forest.get_parent() if forest != null else world).add_child(body)


## The canopy atlases, read from their files when the editor has not imported them yet.
func _preload_canopy_textures() -> void:
	for set_name: String in (CanopyWalls.table().get("sets", {}) as Dictionary):
		var path := str(CanopyWalls.table()["sets"][set_name]["texture"])
		var info := ConfigFile.new()
		# imported: its .import names the imported file (a fresh .import from the packer does not)
		if info.load(path + ".import") == OK and str(info.get_value("remap", "path", "")) != "":
			continue
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		image.generate_mipmaps()
		CanopyWalls._textures[path] = ImageTexture.create_from_image(image)
		print("canopy atlas read from its file (not imported yet): ", path)


## A palette tile the tile set could not make because the editor has not reimported the rebuilt
## palette picture yet (it lies outside the old one): the picture read from its file, and the tile
## made with its data from forest_tileset.tres.
func _add_missing_palette_tile(forest: TileMapLayer, coords: Vector2i) -> void:
	var source := forest.tile_set.get_source(0) as TileSetAtlasSource
	if source == null or source.has_tile(coords):
		return
	var picture := Image.load_from_file(ProjectSettings.globalize_path("res://asset/MAPS/forest/forest_paint_tiles.png"))
	source.texture = ImageTexture.create_from_image(picture)
	source.create_tile(coords)
	var data := source.get_tile_data(coords, 0)
	var text := FileAccess.get_file_as_string(ForestLayer.TILESET)
	for layer in 2:
		var key := "%d:%d/0/custom_data_%d = \"" % [coords.x, coords.y, layer]
		var at := text.find(key)
		if at >= 0:
			var start := at + key.length()
			data.set_custom_data_by_layer_id(layer, text.substr(start, text.find("\"", start) - start))
	print("palette tile %s made from its file (the palette is not reimported yet)" % coords)


## A see-through tint over each painted cell's solid part, drawn above everything.
func _solid_overlay(forest: TileMapLayer) -> Node2D:
	var overlay := Node2D.new()
	overlay.z_index = 100
	var size := Vector2(forest.tile_set.tile_size)
	var foot := ForestLayer.FOOT
	var trunk := ForestLayer.TRUNK_HEIGHT
	overlay.draw.connect(func() -> void:
		var painted := {}
		for cell in forest.get_used_cells():
			painted[cell] = true
		for cell: Vector2i in painted:
			var top := 0.0 if painted.has(cell + Vector2i.UP) else foot.y - trunk
			var bottom := size.y if painted.has(cell + Vector2i.DOWN) else foot.y
			overlay.draw_rect(Rect2(Vector2(cell) * size + Vector2(0.0, top), Vector2(size.x, bottom - top)), Color(0.1, 0.9, 0.9, 0.28)))
	return overlay
