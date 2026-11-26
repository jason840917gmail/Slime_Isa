extends SceneTree
## Builds the prop layers' palettes (docs/godot/PROPS.md): the `props` layer's (64-unit cells,
## game/world/props/props_cell_tileset.tres) and the `details` layer's (32-unit cells,
## props_detail_tileset.tres). Every scenery scene of a palette's sources is rendered with the
## game's own drawing at its true size (a unit a pixel) into a block of whole cells just big enough
## for its visible picture (1 x 1, 2 x 1, 1 x 2, ...): a prop at most TOLERANCE bigger than a
## one- or two-cell block is shrunk to fit it, bigger props keep their size. A sized source gives
## each prop three tiles side by side: small, normal (the fitted size) and big. The cell painted is
## the block's bottom-left one; the picture stands centred in the block on its floor, and the tile is
## drawn exactly there, so the brush preview and the painted squares show the prop as it will be.
## Run windowed (it renders), with the Godot editor closed (it would save its own copies of the tile
## sets and worlds over these):
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/build_prop_palettes.gd
## Then open the editor and let it import the palette images.
##
## Spare rows (2026-11-25): a game run loads a palette's tiles against its picture as the editor last
## imported it, and a tile past that picture's edge is no tile (every world that paints the palette
## fails to load). So each picture is taller than its tiles: its height in cells is kept in the
## manifest ("height", written once), with SPARE_ROWS (or SPARE_SHARE of it) empty rows below the last
## tile, and a new prop goes into them without changing the picture's size: the worlds keep loading
## before the editor has imported the new picture (only the Scenery dock waits for that import). Only
## when the tiles outgrow the spare rows does the picture grow again (with new spare rows); the end
## of the run says loudly which palettes need the editor's import before any game run. A picture, a
## tile set or the manifest is written only when it changed.
##
## A scene is scenery when its only scripts are presentation (idle animation, sound;
## tools/lib/prop_pictures.gd, shared with tools/build_old_prop_palettes.gd). The manifest
## game/world/props/prop_palettes.json keeps every scene's place and its tiles' slots, so a rebuild
## never moves a painted prop to another tile: new scenes get new slots after the last row, a deleted
## scene leaves a gap. A prop whose picture outgrew its block gets a new slot, and the painted cells
## of every world that used the old one are moved to it. The `old-props` palette is built by
## tools/build_old_prop_palettes.gd; the `large-props` one ("walls" in the manifest) is kept as it
## is.

const MANIFEST := "res://game/world/props/prop_palettes.json"
const Props := preload("res://game/world/props/prop_layer.gd")
const SceneSave := preload("res://tools/lib/scene_save.gd")
const Pictures := preload("res://tools/lib/prop_pictures.gd")
const GAME := "res://game/"
const ART_DIR := "res://asset/MAPS/palettes/"
## A sized source's sizes, from its fitted (normal) size: small, normal, big.
const SIZES: Array[float] = [0.7, 1.0, 1.3]
## Any other source's one size.
const ONE_SIZE: Array[float] = [1.0]
## How much bigger than a one- or two-cell block a picture may be and still be shrunk to fit it.
const TOLERANCE := 1.25
## The share of a block a fitted picture fills at most (a little room to its edges).
const FILL := 0.94
## A new source's sheet is about this many times wider than tall (the TileMap panel is wide).
const ASPECT := 3.0
## The largest palette image a source should make (Godot's texture limit).
const MAX_IMAGE := 16384
## The empty rows (cells) a palette picture keeps below its last tile, at least SPARE_ROWS and at
## least SPARE_SHARE of its tiles' rows (see "Spare rows" above).
const SPARE_ROWS := 4
const SPARE_SHARE := 0.2
## palette -> its tile set, cell (units) and sources (name, scene path prefixes, sized).
const PALETTES := {
	"cell": {
		"tileset": "res://game/world/props/props_cell_tileset.tres", "tile": 64,
		"sources": [
			["nature", ["decoration-world-solid", "decoration-world-ambient"], true],
			["rocks", ["rock-world-wall-decorative"], true],
			["water life", ["water-life"], false],
			["rock walls", ["rock-world-wall-solid"], false],
			["crystal walls", ["crystal-cluster-wall"], true],
			["houses", ["house-world-solid", "town/houses/"], false],
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
			# the dungeons' own decor (2026-10-17 builds): the Lair's, the Weaver Hollow's, the mine's
			["dungeon decor", [
				"decoration-world-solid--pearl-altar", "decoration-world-solid--war-banner",
				"decoration-world-solid--weigh-beam-scale", "decoration-world-solid--weigh-weights",
				"decoration-world-solid--worm-bunk", "weaver-hollow/", "brazier-lit", "brazier-unlit",
				"cocoon-prize", "crystal-pillar", "ore-heap", "rock-stump", "dungeon-decor/",
			], true],
			# the town set (2026-11-01, the West village; its houses are under "houses")
			["town", ["town/props/"], true],
			["garden", ["town/garden/"], true],
		],
	},
	"detail": {
		"tileset": "res://game/world/props/props_detail_tileset.tres", "tile": 32,
		"sources": [
			["ground", ["interiors/mushroom-floor/"], true],
		],
	},
}


func _initialize() -> void:
	await process_frame
	var manifest := _load_manifest()
	var before := {}
	for palette: String in PALETTES:
		var config: Dictionary = PALETTES[palette]
		var sources: Array = manifest.get(palette, [])
		for entry: Dictionary in sources:
			entry["retired"] = true
		for source_config: Array in config["sources"]:
			var entry := _source_entry(sources, source_config[0])
			if entry.is_empty():
				entry = {"name": source_config[0], "sized": source_config[2], "scenes": []}
				sources.append(entry)
			entry.erase("retired")
			var scenes: Array = entry["scenes"]
			for path in Pictures.scenery(source_config[1]):
				if not scenes.has(path) and _owner(path, config["sources"]) == source_config[0] \
						and not _listed(path, sources):
					scenes.append(path)
			for i in scenes.size():
				if not str(scenes[i]).is_empty() and not ResourceLoader.exists(scenes[i]):
					scenes[i] = ""
		manifest[palette] = sources
		before[config["tileset"]] = _tile_index(sources)
	var written := true
	for palette: String in PALETTES:
		var config: Dictionary = PALETTES[palette]
		var sources: Array = manifest[palette]
		var layouts := {}
		for i in sources.size():
			if not sources[i].get("retired", false):
				layouts[i] = await _render_source(palette, config["tile"], sources[i])
		written = _write_tileset(palette, config, sources, layouts) and written
	written = _save_manifest(manifest) and written
	if not written:
		# The worlds still match the tile sets on disk; moving their cells now would break them.
		push_error("build_prop_palettes: a tile set or the manifest was not written; no world was changed. Run it again.")
		quit(1)
		return
	_move_painted(manifest, before)
	_report_imports()
	quit(0)


## Palette pictures written this run, the ones whose size changed, and the ones whose tiles reach past
## the picture the editor last imported (those break every world load until it imports again).
var _written: Array[String] = []
var _resized: Array[String] = []
var _past_import: Array[String] = []


func _report_imports() -> void:
	if not _past_import.is_empty():
		push_error("build_prop_palettes: the tiles of %s reach past the picture the editor last imported: EVERY WORLD LOAD FAILS until the Godot editor has imported %s (give it focus). No game run before that." % [", ".join(_past_import), ART_DIR])
	if not _resized.is_empty():
		print("palette pictures that changed size (their tiles grew into new rows): ", ", ".join(_resized))
	if _written.is_empty():
		print("prop palettes: no picture changed")
	elif _past_import.is_empty():
		print("prop palettes: %d pictures written; every tile lies inside the pictures the editor last imported, so game runs keep working; the Scenery dock shows the new pictures once the editor has imported %s" % [_written.size(), ART_DIR])


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _save_manifest(manifest: Dictionary) -> bool:
	var err := _write_if_changed(MANIFEST, JSON.stringify(manifest, "\t") + "\n")
	if err != OK:
		push_error("build_prop_palettes: cannot write %s (%s)" % [MANIFEST, error_string(err)])
	return err == OK


## Writes `text` to `path` unless the file already holds it (no churn, and an open editor's copy stays
## the file's).
static func _write_if_changed(path: String, text: String) -> Error:
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text:
		return OK
	return SceneSave.write_text(path, text)


## The source a new scene goes to: the one with the longest prefix it matches ("dungeon decor"'s
## `decoration-world-solid--war-banner` wins over "nature"'s `decoration-world-solid`).
static func _owner(path: String, source_configs: Array) -> String:
	var rel := path.trim_prefix(Pictures.OBJECTS)
	var best := ""
	var best_length := -1
	for source_config: Array in source_configs:
		for prefix: String in source_config[1]:
			if rel.begins_with(prefix) and prefix.length() > best_length:
				best = source_config[0]
				best_length = prefix.length()
	return best


## Whether a live source of the palette already lists `path` (a scene keeps its source and slots).
static func _listed(path: String, sources: Array) -> bool:
	for entry: Dictionary in sources:
		if not entry.get("retired", false) and (entry["scenes"] as Array).has(path):
			return true
	return false


func _source_entry(sources: Array, source_name: String) -> Dictionary:
	for entry: Dictionary in sources:
		if entry["name"] == source_name:
			return entry
	return {}


## A tile's key in its source's slots: its scene and size index.
static func _key(scene: String, size_index: int) -> String:
	return "%s|%d" % [scene, size_index]


static func _sizes(entry: Dictionary) -> Array[float]:
	return SIZES if entry["sized"] else ONE_SIZE


## Each tile's place now: source id -> {"x:y": key}.
func _tile_index(sources: Array) -> Dictionary:
	var out := {}
	for i in sources.size():
		var index := {}
		var slots: Dictionary = sources[i].get("slots", {})
		for key: String in slots:
			index["%d:%d" % [slots[key][0], slots[key][1]]] = key
		out[i] = index
	return out


## Moves every painted cell whose tile got a new slot (its picture outgrew its block) to it, in every
## world, and saves the worlds that changed.
func _move_painted(manifest: Dictionary, before: Dictionary) -> void:
	var by_tileset := {}
	for palette: String in PALETTES:
		by_tileset[PALETTES[palette]["tileset"]] = manifest[palette]
	for path in Pictures.scenes_under(GAME):
		var text := FileAccess.get_file_as_string(path)
		var uses := false
		for tileset: String in by_tileset:
			uses = uses or text.contains(tileset)
		if not uses:
			continue
		var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var moved := 0
		for layer in root.find_children("*", "TileMapLayer", true, false):
			var tile_set := (layer as TileMapLayer).tile_set
			if layer.get_script() != Props or tile_set == null or not by_tileset.has(tile_set.resource_path):
				continue
			var sources: Array = by_tileset[tile_set.resource_path]
			for cell in (layer as TileMapLayer).get_used_cells():
				var source_id := (layer as TileMapLayer).get_cell_source_id(cell)
				if source_id < 0 or source_id >= sources.size():
					continue
				var coords := (layer as TileMapLayer).get_cell_atlas_coords(cell)
				var key: Variant = (before[tile_set.resource_path].get(source_id, {}) as Dictionary).get("%d:%d" % [coords.x, coords.y])
				var slot: Variant = null if key == null else (sources[source_id].get("slots", {}) as Dictionary).get(key)
				if slot != null and Vector2i(slot[0], slot[1]) != coords:
					(layer as TileMapLayer).set_cell(cell, source_id, Vector2i(slot[0], slot[1]), (layer as TileMapLayer).get_cell_alternative_tile(cell))
					moved += 1
		if moved > 0:
			var err := SceneSave.save(root, path, text)
			if err == OK:
				print("%s: %d painted props moved to their new tiles" % [path.get_file(), moved])
			else:
				push_error("build_prop_palettes: %s not saved (%s): restore the palette files and worlds from git and run again" % [path, error_string(err)])
		root.free()


func _art_path(palette: String, entry: Dictionary) -> String:
	return ART_DIR + "%s-%s.png" % [palette, str(entry["name"]).replace(" ", "-")]


## The cells a block needs along one side for a picture `length` units long, and the scale that
## fits the picture in it: within TOLERANCE of one or two cells it shrinks to fit, else it keeps its
## size. [cells, scale].
static func _fit_side(length: float, tile: int) -> Array:
	var cells := maxi(1, ceili(length / (tile * TOLERANCE)))
	if cells <= 2:
		return [cells, minf(1.0, cells * tile * FILL / length)]
	return [ceili(length / tile), 1.0]


## Where the foot stands in the painted cell (units) for `picture` (its box from the foot) centred
## in a block of `block` cells on its floor: the painted cell is the block's bottom-left one.
static func _anchor(picture: Rect2, block: Vector2i, tile: int) -> Vector2:
	return Vector2(block.x * tile / 2.0 - picture.get_center().x, tile - 1.0 - picture.end.y).round()


## A tile's layout: {size (the prop's scale), block (cells), picture (its box from the foot at that
## size)}, or {} when it shows nothing.
func _tile_layout(scene: String, size_index: int, entry: Dictionary, tile: int) -> Dictionary:
	var natural := Pictures.picture(scene, 1.0)
	if not natural.has_area():
		return {}
	var fit_x := _fit_side(natural.size.x, tile)
	var fit_y := _fit_side(natural.size.y, tile)
	var factor := _sizes(entry)[size_index]
	var size := minf(fit_x[1], fit_y[1]) * factor
	var picture := natural if is_equal_approx(size, 1.0) else Pictures.picture(scene, size)
	var block := Vector2i(fit_x[0], fit_y[0])
	if not is_equal_approx(factor, 1.0):
		block = Vector2i(maxi(1, ceili(picture.size.x / tile - 0.02)), maxi(1, ceili(picture.size.y / tile - 0.02)))
	return {"size": snappedf(size, 0.001), "block": block, "picture": picture}


## Gives every tile of a source a slot (cells: [x, y, width, height]) the size of its block: slots
## already given stay unless the block grew (then the tile's block is its slot); new ones are packed
## in rows, a scene's sizes side by side, after the last row.
func _allocate(entry: Dictionary, layouts: Dictionary) -> void:
	var slots: Dictionary = entry.get("slots", {})
	var groups: Array = []
	var area := 0
	var widest := 1
	for scene: String in entry["scenes"]:
		if scene.is_empty():
			continue
		var group: Array = []
		for i in _sizes(entry).size():
			var key := _key(scene, i)
			if not layouts.has(key):
				continue
			var block: Vector2i = layouts[key]["block"]
			var slot: Variant = slots.get(key)
			if slot != null and slot[2] >= block.x and slot[3] >= block.y:
				layouts[key]["block"] = Vector2i(slot[2], slot[3])
				continue
			group.append([key, block])
			area += block.x * block.y
		if not group.is_empty():
			groups.append(group)
			widest = maxi(widest, group.reduce(func(sum: int, item: Array) -> int: return sum + item[1].x, 0))
	if not entry.has("width"):
		entry["width"] = maxi(widest, ceili(sqrt(ASPECT * area)))
	var width := maxi(int(entry["width"]), widest)
	entry["width"] = width
	var row_y := 0
	for slot: Array in slots.values():
		row_y = maxi(row_y, slot[1])
	var row_h := 0
	var x := 0
	for slot: Array in slots.values():
		if slot[1] == row_y:
			row_h = maxi(row_h, slot[3])
			x = maxi(x, slot[0] + slot[2])
	for group: Array in groups:
		var group_w: int = group.reduce(func(sum: int, item: Array) -> int: return sum + item[1].x, 0)
		if x + group_w > width:
			row_y += row_h
			row_h = 0
			x = 0
		for item: Array in group:
			slots[item[0]] = [x, row_y, item[1].x, item[1].y]
			x += item[1].x
			row_h = maxi(row_h, item[1].y)
	entry["slots"] = slots


## Lays out and renders one source's palette image, every prop at its tile's size standing in its
## slot as it will stand in its block. Returns {key: layout} for the tiles it drew.
func _render_source(palette: String, tile: int, entry: Dictionary) -> Dictionary:
	var layouts := {}
	for scene: String in entry["scenes"]:
		if scene.is_empty():
			continue
		for i in _sizes(entry).size():
			var layout := _tile_layout(scene, i, entry, tile)
			if not layout.is_empty():
				layouts[_key(scene, i)] = layout
	_allocate(entry, layouts)
	var slots: Dictionary = entry["slots"]
	var tiles_end := Vector2i(1, 1)
	for key: String in layouts:
		var slot: Array = slots[key]
		tiles_end = Vector2i(maxi(tiles_end.x, slot[0] + slot[2]), maxi(tiles_end.y, slot[1] + slot[3]))
	# the picture's height stays as the manifest keeps it while the tiles fit; past it, it grows to
	# the tiles' rows and new spare rows (see "Spare rows" at the top)
	var height := int(entry.get("height", 0))
	if tiles_end.y > height:
		height = tiles_end.y + maxi(SPARE_ROWS, ceili(tiles_end.y * SPARE_SHARE))
		entry["height"] = height
	var sheet := Vector2i(int(entry["width"]), height) * tile
	_check_import(palette, entry, tiles_end * tile)
	if sheet.x > MAX_IMAGE or sheet.y > MAX_IMAGE:
		push_warning("%s / %s: palette image %s is over %d px" % [palette, entry["name"], sheet, MAX_IMAGE])
	var viewport := SubViewport.new()
	viewport.size = sheet
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for key: String in layouts:
		var layout: Dictionary = layouts[key]
		var prop := Props.make_prop({"scene": key.get_slice("|", 0), "at": Vector2.ZERO, "size": layout["size"], "flip": false})
		if prop == null:
			continue
		Pictures.still(prop)
		var slot: Array = slots[key]
		# the slot's top-left is the block's: the painted cell's top-left, (height - 1) cells up
		var anchor := _anchor(layout["picture"], layout["block"], tile)
		prop.position = Vector2(slot[0], slot[1]) * tile + anchor + Vector2(0, (slot[3] - 1) * tile)
		viewport.add_child(prop)
	for f in 6:
		await process_frame
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_DIR))
	var file := ProjectSettings.globalize_path(_art_path(palette, entry))
	var old := Image.load_from_file(file) if FileAccess.file_exists(file) else null
	if old != null:
		old.convert(Image.FORMAT_RGBA8)
	if old == null or old.get_size() != image.get_size() or old.get_data() != image.get_data():
		if old == null or old.get_size() != image.get_size():
			_resized.append("%s %s (%s -> %s)" % [palette, entry["name"], Vector2i.ZERO if old == null else old.get_size(), image.get_size()])
		for attempt in SceneSave.TRIES:
			if image.save_png(file) == OK:
				break
			OS.delay_msec(SceneSave.RETRY_MS)
		_written.append("%s %s" % [palette, entry["name"]])
	viewport.free()
	print("%s / %s: %d tiles, %s px" % [palette, entry["name"], layouts.size(), sheet])
	return layouts


## Notes the palette when its tiles (up to `tiles_px`) reach past the picture the editor last
## imported: a game run builds the tiles against that one, and a tile past its edge is no tile.
func _check_import(palette: String, entry: Dictionary, tiles_px: Vector2i) -> void:
	var path := _art_path(palette, entry)
	if not ResourceLoader.exists(path):
		_past_import.append("%s %s (never imported)" % [palette, entry["name"]])
		return
	var imported := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if imported == null or imported.get_width() < tiles_px.x or imported.get_height() < tiles_px.y:
		_past_import.append("%s %s (tiles to %s, imported %s)" % [palette, entry["name"], tiles_px, Vector2.ZERO if imported == null else imported.get_size()])


## The tile set of `palette`: one atlas source per palette source (a retired one leaves its id
## unused) on a grid of its cells, each tile covering its slot and carrying its scene, anchor, size
## and the mirror flag (custom data the PropLayer reads). Godot draws a tile's texture centred on its
## cell, moved back by the texture origin; the origin here puts the texture's bottom-left cell on
## the painted cell.
func _write_tileset(palette: String, config: Dictionary, sources: Array, layouts: Dictionary) -> bool:
	var tile: int = config["tile"]
	var lines := PackedStringArray(['[gd_resource type="TileSet" format=3]', ""])
	var live := range(sources.size()).filter(func(i: int) -> bool: return not sources[i].get("retired", false))
	for i: int in live:
		lines.append('[ext_resource type="Texture2D" path="%s" id="tex_%d"]' % [_art_path(palette, sources[i]), i])
	lines.append("")
	for i: int in live:
		var entry: Dictionary = sources[i]
		var tiles: Dictionary = layouts[i]
		var slots: Dictionary = entry["slots"]
		lines.append('[sub_resource type="TileSetAtlasSource" id="src_%d"]' % i)
		lines.append('resource_name = "%s"' % entry["name"])
		lines.append('texture = ExtResource("tex_%d")' % i)
		lines.append("texture_region_size = Vector2i(%d, %d)" % [tile, tile])
		for key: String in tiles:
			var layout: Dictionary = tiles[key]
			var slot: Array = slots[key]
			var at := "%d:%d" % [slot[0], slot[1]]
			var origin := Vector2i(tile * (1 - slot[2]) / 2, tile * (slot[3] - 1) / 2)
			var anchor := _anchor(layout["picture"], layout["block"], tile)
			lines.append("%s/size_in_atlas = Vector2i(%d, %d)" % [at, slot[2], slot[3]])
			lines.append("%s/0 = 0" % at)
			lines.append("%s/0/texture_origin = Vector2i(%d, %d)" % [at, origin.x, origin.y])
			lines.append('%s/0/custom_data_0 = "%s"' % [at, key.get_slice("|", 0)])
			lines.append("%s/0/custom_data_1 = Vector2(%s, %s)" % [at, anchor.x, anchor.y])
			lines.append("%s/0/custom_data_2 = %s" % [at, layout["size"]])
			lines.append("%s/0/custom_data_3 = true" % at)
		lines.append("")
	lines.append("[resource]")
	lines.append("tile_size = Vector2i(%d, %d)" % [tile, tile])
	lines.append('custom_data_layer_0/name = "%s"' % Props.SCENE_DATA)
	lines.append("custom_data_layer_0/type = %d" % TYPE_STRING)
	lines.append('custom_data_layer_1/name = "%s"' % Props.ANCHOR_DATA)
	lines.append("custom_data_layer_1/type = %d" % TYPE_VECTOR2)
	lines.append('custom_data_layer_2/name = "%s"' % Props.SIZE_DATA)
	lines.append("custom_data_layer_2/type = %d" % TYPE_FLOAT)
	lines.append('custom_data_layer_3/name = "%s"' % Props.MIRROR_DATA)
	lines.append("custom_data_layer_3/type = %d" % TYPE_BOOL)
	for i: int in live:
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
	var err := _write_if_changed(path, "\n".join(lines))
	if err != OK:
		push_error("build_prop_palettes: cannot write %s (%s)" % [path, error_string(err)])
		return false
	print("%s: %s" % [palette, path])
	return true
