extends SceneTree
## Renders a room painted with every closed-door tile of the interior walls' palette (docs/godot/
## INTERIOR_WALLS.md "Painting a room"): the doors are made by the layer from the paint
## (InteriorWallLayer.sync_doors), as in the editor. Run windowed:
##     "<Godot console exe>" --path godot -s res://tools/render_interior_palette_room.gd -- --out=<dir> [--style=lair-stone]
## Writes <dir>/palette-room-<style>.png at 2 px a unit.

const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const TILESET := "res://game/world/interior/interior_wall_tileset.tres"
const SIZE := Vector2i(22, 16)
const DEPTH := 2
## [side, first cell along, kind]
const DOORS := [["n", 4, "key1"], ["n", 10, "key2"], ["n", 16, "boss"], ["s", 4, "bolt"], ["s", 10, "shutter"],
	["s", 16, "seal"], ["w", 7, "barricade"], ["e", 7, "doorway"]]


func _initialize() -> void:
	var out := "user://palette-room"
	var style := "lair-stone"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--style="):
			style = arg.trim_prefix("--style=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await process_frame
	var viewport := SubViewport.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(SIZE * 128)
	root.add_child(viewport)
	var camera := Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.zoom = Vector2(2, 2)
	viewport.add_child(camera)
	var room := Node2D.new()
	room.name = "palette-room"
	viewport.add_child(room)
	var objects := Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	room.add_child(objects)
	var layer := InteriorWalls.new()
	layer.name = "interior-walls"
	layer.tile_set = load(TILESET)
	var tiles := _tiles(layer.tile_set, style)
	for y in SIZE.y:
		for x in SIZE.x:
			if x < DEPTH or y < DEPTH or x >= SIZE.x - DEPTH or y >= SIZE.y - DEPTH:
				layer.set_cell(Vector2i(x, y), 0, tiles[""])
	for door: Array in DOORS:
		for d in DEPTH:
			for i in 2:
				var along := int(door[1]) + i
				var cell: Vector2i
				match str(door[0]):
					"n":
						cell = Vector2i(along, d)
					"s":
						cell = Vector2i(along, SIZE.y - 1 - d)
					"w":
						cell = Vector2i(d, along)
					_:
						cell = Vector2i(SIZE.x - 1 - d, along)
				layer.set_cell(cell, 0, tiles[str(door[2])])
	room.add_child(layer)
	for i in 3:
		await process_frame
	print("doors made: ", layer.sync_doors(true))
	for i in 10:
		await process_frame
	for node: Node in objects.get_children():
		if node.has_method(&"shut_quietly"):
			node.call(&"shut_quietly")
		elif node.has_method(&"shut"):
			node.call(&"shut")
	for i in 20:
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join("palette-room-%s.png" % style)))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit(0)


func _tiles(tile_set: TileSet, style: String) -> Dictionary:
	var out := {}
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if str(data.get_custom_data(InteriorWalls.STYLE_DATA)) == style:
			out[str(data.get_custom_data(InteriorWalls.OPENING_DATA))] = coords
	return out
