extends SceneTree
## Renders a world's forest with the game's own drawing, for judging tree art at play scale
## (docs/godot/FORESTS.md). A slime stands in the picture for scale.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_forest.gd -- \
##         --scene=res://game/scenes/worlds/chunks/gloop-forest-e5.tscn [--rect=x,y,w,h] [--out=<dir>]
## --rect is in cells (default: the 20 x 12 window whose forest cover is nearest half). Writes
## <dir>/<scene>.png at 1x (the game's base view is 20 x 11 cells) and <dir>/<scene>-2x.png, the
## middle of it at 2x; <dir>/<scene>-sway-<n>.png are four moments of the sway, at 2x.

const Services := preload("res://game/shared/services.gd")
const DEFAULT_OUT := "user://forest-render"
const CELL := 64.0
const WINDOW := Vector2i(20, 12)
const SLIME_SHEET := "res://asset/characters/256x256-tile_8x8-slime-v2-page-1.webp"


func _initialize() -> void:
	var out := DEFAULT_OUT
	var scene_path := ""
	var rect := Rect2i()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
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
	if rect.size == Vector2i.ZERO:
		var definition := world.get_node_or_null(^"world-definition")
		var bounds := Rect2i(0, 0, int(definition.get(&"columns")), int(definition.get(&"rows"))) \
				if definition != null else forest.get_used_rect()
		rect = _busy_window(forest, bounds)
	print("forest cells ", forest.get_used_cells().size() if forest else 0, ", window ", rect)
	_add_slime(world, forest, rect)
	for i in 4:
		await physics_frame
	var name := scene_path.get_file().get_basename()
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
