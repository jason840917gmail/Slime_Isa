extends SceneTree
## Builds the prop layers' palettes (docs/godot/PROPS.md): a thumbnail of every scenery scene,
## rendered with the game's own drawing, packed per palette source, and the tile sets that paint
## them (game/world/props/walls_tileset.tres, props_tileset.tres). Run windowed (it renders):
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/build_prop_palettes.gd
## Then let the editor import the palette images (focus it, or filesystem scan).
##
## The walls and houses are in both palettes: on the walls layer (64-unit grid) a drag paints a
## clean row, on the props layer (8-unit grid) they go anywhere.
## A scene is scenery when its only scripts are presentation (idle animation, sound); scenes with
## gameplay scripts (resources, collectibles, beds, workbenches...) stay out. The manifest
## game/world/props/prop_palettes.json keeps every scene's place in its palette and its anchor, so a
## rebuild never moves a painted prop: new scenes are appended, a deleted scene leaves a gap.
## Sized sources give each prop a row of SIZES; the others a grid of COLUMNS props.

const MANIFEST := "res://game/world/props/prop_palettes.json"
const Props := preload("res://game/world/props/prop_layer.gd")
const OBJECTS := "res://game/scenes/objects/"
const WORLDS := "res://game/scenes/worlds/"
const ART_DIR := "res://asset/MAPS/palettes/"
const THUMB := 64
const COLUMNS := 16
const SIZES: Array[float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3]
## Scripts a scenery scene may carry.
const PRESENTATION: PackedStringArray = [
	"res://game/runtime/animation_player.gd", "res://game/runtime/sfx_player_2d.gd",
	"res://game/runtime/sfx_player.gd",
]
## palette -> its tile set, grid, default anchor and sources (name, scene path prefixes, sized).
const PALETTES := {
	"walls": {
		"tileset": "res://game/world/props/walls_tileset.tres", "tile": 64, "anchor": Vector2(32, 64),
		"sources": [
			["stone walls", ["wall-stone-solid"], false],
			["rock walls", ["rock-world-wall-solid"], false],
			["crystal walls", ["crystal-cluster-wall"], true],
			["houses", ["house-world-solid"], false],
		],
	},
	"props": {
		"tileset": "res://game/world/props/props_tileset.tres", "tile": 8, "anchor": Vector2.ZERO,
		"sources": [
			["nature", ["decoration-world-solid", "decoration-world-ambient"], true],
			["stone walls", ["wall-stone-solid"], false],
			["rock walls", ["rock-world-wall-solid"], false],
			["crystal walls", ["crystal-cluster-wall"], true],
			["houses", ["house-world-solid"], false],
			["rocks", ["rock-world-wall-decorative"], true],
			["water life", ["water-life"], false],
			["trees", ["tree-forest-wall"], true],
			["ground", ["interiors/mushroom-floor/"], true],
			["interior beds", ["interiors/beds/"], false],
			["interior decor", ["interiors/decor/"], true],
			["interior kitchen", ["interiors/kitchen/"], false],
			["interior mushroom decor", ["interiors/mushroom-decor/"], true],
			["interior mushroom furniture", ["interiors/mushroom-furniture/"], false],
			["interior mushroom large", ["interiors/mushroom-large/"], false],
			["interior mushroom shell", ["interiors/mushroom-shell/"], false],
			["interior mushroom structure", ["interiors/mushroom-structure/"], false],
			["interior seating", ["interiors/seating/"], false],
			["interior specialty", ["interiors/specialty/"], false],
			["interior storage", ["interiors/storage/"], false],
			["interior structure", ["interiors/structure/"], false],
			["interior tables", ["interiors/tables/"], false],
			["interior workshop", ["interiors/workshop/"], false],
		],
	},
}


func _initialize() -> void:
	await process_frame
	var manifest := _load_manifest()
	var placements := _world_placements()
	for palette: String in PALETTES:
		var config: Dictionary = PALETTES[palette]
		var sources: Array = manifest.get(palette, [])
		for source_config: Array in config["sources"]:
			var entry := _source_entry(sources, source_config[0])
			if entry.is_empty():
				entry = {"name": source_config[0], "sized": source_config[2], "scenes": [], "anchors": {}}
				sources.append(entry)
			var scenes: Array = entry["scenes"]
			for path in _scenery(source_config[1]):
				if not scenes.has(path):
					scenes.append(path)
			for i in scenes.size():
				if not str(scenes[i]).is_empty() and not ResourceLoader.exists(scenes[i]):
					scenes[i] = ""
			var anchors: Dictionary = entry["anchors"]
			for path: String in scenes:
				if not path.is_empty() and not anchors.has(path):
					var anchor := _anchor(placements.get(path, []), config["tile"], config["anchor"])
					anchors[path] = [anchor.x, anchor.y]
		manifest[palette] = sources
		for i in sources.size():
			await _render_source(palette, i, sources[i])
		_write_tileset(palette, config, sources)
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	print("prop palettes written; let the editor import ", ART_DIR)
	quit(0)


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _source_entry(sources: Array, source_name: String) -> Dictionary:
	for entry: Dictionary in sources:
		if entry["name"] == source_name:
			return entry
	return {}


## The scenery scenes under OBJECTS whose path (after OBJECTS) starts with one of `prefixes`.
func _scenery(prefixes: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for path in _scenes_under(OBJECTS):
		var rel := path.trim_prefix(OBJECTS)
		var matched := false
		for prefix: String in prefixes:
			matched = matched or rel.begins_with(prefix)
		if matched and _is_scenery(path):
			out.append(path)
	out.sort()
	return out


func _scenes_under(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scenes_under(dir.path_join(sub)))
	return out


func _is_scenery(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var scripts := RegEx.create_from_string("path=\"(res://[^\"]+\\.gd)\"")
	for found in scripts.search_all(text):
		if not PRESENTATION.has(found.get_string(1)):
			return false
	return true


## scene path -> its instances' positions in every world scene (for the anchors).
func _world_placements() -> Dictionary:
	var out := {}
	var ext := RegEx.create_from_string("\\[ext_resource type=\"PackedScene\"[^\\]]*path=\"(res://game/scenes/objects/[^\"]+)\" id=\"([^\"]+)\"\\]")
	var node := RegEx.create_from_string("\\[node name=\"[^\"]+\" parent=\"[^\"]*\"[^\\]]*instance=ExtResource\\(\"([^\"]+)\"\\)\\]\\n(?:[^\\[\\n][^\\n]*\\n)*?position = Vector2\\(([-\\d.e]+), ([-\\d.e]+)\\)")
	for path in _scenes_under(WORLDS):
		var text := FileAccess.get_file_as_string(path)
		var ids := {}
		for found in ext.search_all(text):
			ids[found.get_string(2)] = found.get_string(1)
		for found in node.search_all(text):
			var scene: Variant = ids.get(found.get_string(1))
			if scene != null:
				if not out.has(scene):
					out[scene] = []
				(out[scene] as Array).append(Vector2(float(found.get_string(2)), float(found.get_string(3))))
	return out


## The most common spot of `positions` within their `tile` cells (y 0 counts as the cell's
## bottom: a prop stands in the cell above that line); `fallback` when there are none.
func _anchor(positions: Array, tile: int, fallback: Vector2) -> Vector2:
	if tile <= 8 or positions.is_empty():
		return fallback
	var counts := {}
	for p: Vector2 in positions:
		var spot := Vector2(fposmod(p.x, tile), fposmod(p.y, tile))
		if is_zero_approx(spot.y):
			spot.y = tile
		counts[spot] = int(counts.get(spot, 0)) + 1
	var best := fallback
	var most := 0
	for spot: Vector2 in counts:
		if counts[spot] > most:
			most = counts[spot]
			best = spot
	return best


## The palette tile of scene `index` at size column `size_index` (sized sources) .
static func tile_coords(entry: Dictionary, index: int, size_index: int) -> Vector2i:
	if entry["sized"]:
		return Vector2i(size_index, index)
	return Vector2i(index % COLUMNS, index / COLUMNS)


func _art_path(palette: String, entry: Dictionary) -> String:
	return ART_DIR + "%s-%s.png" % [palette, str(entry["name"]).replace(" ", "-")]


## Renders the thumbnails of one source into its palette image.
func _render_source(palette: String, source_index: int, entry: Dictionary) -> void:
	var scenes: Array = entry["scenes"]
	var sized: bool = entry["sized"]
	var columns := SIZES.size() if sized else COLUMNS
	var rows := maxi(1, scenes.size() if sized else ceili(scenes.size() / float(COLUMNS)))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(columns * THUMB, rows * THUMB)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for i in scenes.size():
		var path := str(scenes[i])
		if path.is_empty():
			continue
		var base := Props.make_prop({"scene": path, "at": Vector2.ZERO, "size": 1.0, "flip": false})
		if base == null:
			continue
		var box := _bounds(base, Transform2D.IDENTITY)
		base.free()
		if not box.has_area():
			box = Rect2(-32, -64, 64, 64)
		var room := THUMB * 0.9 / (SIZES[-1] if sized else 1.0)
		var fit := minf(room / box.size.x, room / box.size.y)
		var sizes: Array = SIZES if sized else [1.0]
		for s in sizes.size():
			var prop := Props.make_prop({"scene": path, "at": Vector2.ZERO, "size": sizes[s], "flip": false})
			_still(prop)
			var bounds := _bounds(prop, Transform2D.IDENTITY)
			var slot := Node2D.new()
			slot.scale = Vector2(fit, fit)
			var cell := Vector2(tile_coords(entry, i, s)) * THUMB + Vector2(THUMB, THUMB) * 0.5
			slot.position = cell - bounds.get_center() * fit
			slot.add_child(prop)
			viewport.add_child(slot)
	for f in 6:
		await process_frame
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_DIR))
	image.save_png(ProjectSettings.globalize_path(_art_path(palette, entry)))
	viewport.free()
	print("%s / %s: %d props" % [palette, entry["name"], scenes.filter(func(p): return not str(p).is_empty()).size()])


## Keeps `node`'s idle animations from starting (a swimming fish would leave its thumbnail).
func _still(node: Node) -> void:
	for player in node.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).autoplay = ""


## The box `node`'s visible sprites cover, in the space `transform` maps `node`'s parent to.
func _bounds(node: Node, transform: Transform2D) -> Rect2:
	var here := transform * (node as Node2D).transform if node is Node2D else transform
	var box := Rect2()
	if node is Sprite2D and (node as Sprite2D).visible and (node as Sprite2D).texture != null:
		box = here * (node as Sprite2D).get_rect()
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var inner := _bounds(child, here)
		if inner.has_area():
			box = inner if not box.has_area() else box.merge(inner)
	return box


## The tile set of `palette`: one atlas source per palette source, each tile carrying its scene,
## anchor and size (custom data the PropLayer reads).
func _write_tileset(palette: String, config: Dictionary, sources: Array) -> void:
	var tile: int = config["tile"]
	var lines := PackedStringArray(['[gd_resource type="TileSet" format=3]', ""])
	for i in sources.size():
		lines.append('[ext_resource type="Texture2D" path="%s" id="tex_%d"]' % [_art_path(palette, sources[i]), i])
	lines.append("")
	for i in sources.size():
		var entry: Dictionary = sources[i]
		lines.append('[sub_resource type="TileSetAtlasSource" id="src_%d"]' % i)
		lines.append('resource_name = "%s"' % entry["name"])
		lines.append('texture = ExtResource("tex_%d")' % i)
		lines.append("texture_region_size = Vector2i(%d, %d)" % [THUMB, THUMB])
		var scenes: Array = entry["scenes"]
		var anchors: Dictionary = entry["anchors"]
		var sizes: Array = SIZES if entry["sized"] else [1.0]
		for k in scenes.size():
			var path := str(scenes[k])
			if path.is_empty():
				continue
			var anchor: Array = anchors.get(path, [0, 0])
			for s in sizes.size():
				var at := tile_coords(entry, k, s)
				var key := "%d:%d/0" % [at.x, at.y]
				lines.append("%s = 0" % key)
				lines.append('%s/custom_data_0 = "%s"' % [key, path])
				lines.append("%s/custom_data_1 = Vector2(%s, %s)" % [key, anchor[0], anchor[1]])
				lines.append("%s/custom_data_2 = %s" % [key, sizes[s]])
		lines.append("")
	lines.append("[resource]")
	lines.append("tile_size = Vector2i(%d, %d)" % [tile, tile])
	lines.append('custom_data_layer_0/name = "%s"' % Props.SCENE_DATA)
	lines.append("custom_data_layer_0/type = %d" % TYPE_STRING)
	lines.append('custom_data_layer_1/name = "%s"' % Props.ANCHOR_DATA)
	lines.append("custom_data_layer_1/type = %d" % TYPE_VECTOR2)
	lines.append('custom_data_layer_2/name = "%s"' % Props.SIZE_DATA)
	lines.append("custom_data_layer_2/type = %d" % TYPE_FLOAT)
	for i in sources.size():
		lines.append('sources/%d = SubResource("src_%d")' % [i, i])
	lines.append("")
	var path: String = config["tileset"]
	var uid := ""
	if FileAccess.file_exists(path):
		var found := RegEx.create_from_string("\\[gd_resource [^\\]]*uid=\"([^\"]+)\"").search(FileAccess.get_file_as_string(path))
		if found != null:
			uid = found.get_string(1)
	if not uid.is_empty():
		lines[0] = '[gd_resource type="TileSet" format=3 uid="%s"]' % uid
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	print("%s: %s" % [palette, path])
