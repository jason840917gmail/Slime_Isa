extends SceneTree
## Builds the `old-props` layer's palette (docs/godot/PROPS.md): free placement on an 8-unit grid
## (game/world/props/props_tileset.tres, "props" in the manifest). Every scenery scene of a source
## is rendered with the game's own drawing at its true size (a unit a pixel) into a slot of 16 px
## squares, at least SQUARE (64 px; 32 for the ground details) so every tile is easy to see and
## pick, and written as a tile whose texture origin puts the picture's foot on the prop's foot: the
## brush preview shows the prop where it will stand. A sized source gives each prop three tiles side
## by side: small (filling about one SQUARE, never under 70 % or over the normal size; left out when
## it would be the normal one), normal (its true size) and big (130 %). Run windowed (it renders),
## with the Godot editor closed (it would save its own copies of the tile set and worlds over these):
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/build_old_prop_palettes.gd
## Then open the editor and let it import the palette images.
##
## The manifest (game/world/props/prop_palettes.json) keeps every scene's place, anchor and its
## tiles' slots, so a rebuild never moves a painted prop to another tile: new scenes get new slots
## after the last row, a deleted scene leaves a gap. A prop whose picture outgrew its slot gets a new
## one, and the painted cells of every world that used the old one are moved to it. A size painted
## that the palette no longer offers is kept: an alternative of the prop's normal tile carries it
## (`legacy`, drawn transparent as its picture would be the normal one). A mirrored prop's preview
## shows 8 units right of where it stands: Godot mirrors a tile about its cell's middle, these props
## mirror about their foot, the cell's corner. The `cell-props` and `details` palettes are
## tools/build_prop_palettes.gd's.

const MANIFEST := "res://game/world/props/prop_palettes.json"
const Props := preload("res://game/world/props/prop_layer.gd")
const SceneSave := preload("res://tools/lib/scene_save.gd")
const Pictures := preload("res://tools/lib/prop_pictures.gd")
const GAME := "res://game/"
const ART_DIR := "res://asset/MAPS/palettes/"
## A sized source's normal and big sizes (the small one is each prop's own).
const NORMAL := 1.0
const BIG := 1.3
## The smallest a small size goes.
const SMALL_MIN := 0.7
## The share of a SQUARE a small picture fills at most.
const FILL := 0.94
## The palette images' grid, px: every tile covers whole squares.
const GRID := 16
## A new source's sheet is about this many times wider than tall (the TileMap panel is wide).
const ASPECT := 3.0
## The largest palette image a source should make (Godot's texture limit).
const MAX_IMAGE := 16384
## The palette: its tile set, grid, anchor and sources (name, scene path prefixes, sized, SQUARE).
const PALETTE := "props"
const CONFIG := {
	"tileset": "res://game/world/props/props_tileset.tres", "tile": 8, "anchor": Vector2.ZERO,
	"sources": [
		["nature", ["decoration-world-solid", "decoration-world-ambient"], true, 64],
		["rocks", ["rock-world-wall-decorative"], true, 64],
		["water life", ["water-life"], false, 64],
		["ground", ["interiors/mushroom-floor/"], true, 32],
		["interior beds", ["interiors/beds/"], false, 64],
		["interior decor", ["interiors/decor/"], true, 64],
		["interior kitchen", ["interiors/kitchen/"], false, 64],
		["interior mushroom decor", ["interiors/mushroom-decor/"], true, 64],
		["interior mushroom furniture", ["interiors/mushroom-furniture/"], false, 64],
		["interior mushroom large", ["interiors/mushroom-large/"], false, 64],
		["interior mushroom shell", ["interiors/mushroom-shell/"], false, 64],
		["interior mushroom structure", ["interiors/mushroom-structure/"], false, 64],
		["interior seating", ["interiors/seating/"], false, 64],
		["interior specialty", ["interiors/specialty/"], false, 64],
		["interior storage", ["interiors/storage/"], false, 64],
		["interior structure", ["interiors/structure/"], false, 64],
		["interior tables", ["interiors/tables/"], false, 64],
		["interior workshop", ["interiors/workshop/"], false, 64],
		["rock walls", ["rock-world-wall-solid"], false, 64],
		["crystal walls", ["crystal-cluster-wall"], true, 64],
		["houses", ["house-world-solid"], false, 64],
	],
}


func _initialize() -> void:
	await process_frame
	var manifest := _load_manifest()
	var sources: Array = manifest.get(PALETTE, [])
	for entry: Dictionary in sources:
		entry["retired"] = true
	for source_config: Array in CONFIG["sources"]:
		var entry := _source_entry(sources, source_config[0])
		if entry.is_empty():
			entry = {"name": source_config[0], "sized": source_config[2], "scenes": [], "anchors": {}}
			sources.append(entry)
		entry.erase("retired")
		entry["square"] = source_config[3]
		var scenes: Array = entry["scenes"]
		for path in Pictures.scenery(source_config[1]):
			if not scenes.has(path):
				scenes.append(path)
		for i in scenes.size():
			if not str(scenes[i]).is_empty() and not ResourceLoader.exists(scenes[i]):
				scenes[i] = ""
		var anchors: Dictionary = entry["anchors"]
		for path: String in scenes:
			if not path.is_empty() and not anchors.has(path):
				anchors[path] = [CONFIG["anchor"].x, CONFIG["anchor"].y]
	manifest[PALETTE] = sources
	# What each tile showed before anything moves, and the sizes each prop now offers.
	var before := _tile_index(sources)
	var offered := {}
	for i in sources.size():
		if not sources[i].get("retired", false):
			offered[i] = _offered_sizes(sources[i])
	_keep_painted_sizes(sources, before, offered)
	var layouts := {}
	for i in sources.size():
		if not sources[i].get("retired", false):
			layouts[i] = await _render_source(sources[i], offered[i])
	var written := _write_tileset(sources, layouts)
	written = _save_manifest(manifest) and written
	if not written:
		# The worlds still match the tile set on disk; moving their cells now would break them.
		push_error("build_old_prop_palettes: the tile set or the manifest was not written; no world was changed. Run it again.")
		quit(1)
		return
	_move_painted(sources, before, offered)
	print("old-props palette written; open the editor to import ", ART_DIR)
	quit(0)


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _save_manifest(manifest: Dictionary) -> bool:
	var err := SceneSave.write_text(MANIFEST, JSON.stringify(manifest, "\t") + "\n")
	if err != OK:
		push_error("build_old_prop_palettes: cannot write %s (%s)" % [MANIFEST, error_string(err)])
	return err == OK


func _source_entry(sources: Array, source_name: String) -> Dictionary:
	for entry: Dictionary in sources:
		if entry["name"] == source_name:
			return entry
	return {}


## The key of a scene at a size, in a source's slots and legacy sizes.
static func _key(scene: String, size: float) -> String:
	return "%s|%.2f" % [scene, size]


## scene -> the sizes it offers, small first: a sized source's small one fills about one SQUARE
## (between SMALL_MIN and NORMAL; left out when it is NORMAL), then NORMAL and BIG.
func _offered_sizes(entry: Dictionary) -> Dictionary:
	var out := {}
	for scene: String in entry["scenes"]:
		if scene.is_empty():
			continue
		if not entry["sized"]:
			out[scene] = [NORMAL]
			continue
		var natural := Pictures.picture(scene, NORMAL)
		var longest := maxf(natural.size.x, natural.size.y)
		var small := NORMAL if longest <= 0.0 else clampf(int(entry["square"]) * FILL / longest, SMALL_MIN, NORMAL)
		small = snappedf(small, 0.01)
		out[scene] = [NORMAL, BIG] if small >= NORMAL - 0.005 else [small, NORMAL, BIG]
	return out


static func _is_offered(offered: Dictionary, scene: String, size: float) -> bool:
	for kept: float in offered.get(scene, []):
		if is_equal_approx(snappedf(kept, 0.01), snappedf(size, 0.01)):
			return true
	return false


## What each tile shows now: source id -> {"x:y:alternative": [scene, size]}.
func _tile_index(sources: Array) -> Dictionary:
	var out := {}
	for i in sources.size():
		var entry: Dictionary = sources[i]
		var index := {}
		var slots: Dictionary = entry.get("slots", {})
		for key: String in slots:
			index["%d:%d:0" % [int(slots[key][0]), int(slots[key][1])]] = [key.get_slice("|", 0), float(key.get_slice("|", 1))]
		var legacy: Dictionary = entry.get("legacy", {})
		for key: String in legacy:
			var scene := key.get_slice("|", 0)
			var normal: Variant = slots.get(_key(scene, NORMAL))
			if normal != null:
				index["%d:%d:%d" % [int(normal[0]), int(normal[1]), int(legacy[key])]] = [scene, float(key.get_slice("|", 1))]
		out[i] = index
	return out


## Every world scene with an old-props layer, edited: [[root, path, text, layer]].
func _worlds() -> Array:
	var out := []
	for path in Pictures.scenes_under(GAME):
		var text := FileAccess.get_file_as_string(path)
		if not text.contains(CONFIG["tileset"]):
			continue
		var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		for layer in root.find_children("*", "TileMapLayer", true, false):
			if layer.get_script() == Props and (layer as TileMapLayer).tile_set != null \
					and (layer as TileMapLayer).tile_set.resource_path == CONFIG["tileset"]:
				out.append([root, path, text, layer])
	return out


## [scene, size] painted on `cell` of `layer`, read from `index` (by source), or null.
static func _shown(index: Dictionary, layer: TileMapLayer, cell: Vector2i) -> Variant:
	var coords := layer.get_cell_atlas_coords(cell)
	var alternative := layer.get_cell_alternative_tile(cell) & ~Props.FLIP_FLAGS
	return (index.get(layer.get_cell_source_id(cell), {}) as Dictionary).get("%d:%d:%d" % [coords.x, coords.y, alternative])


## Gives every size painted in a world that its prop no longer offers an alternative id of its
## normal tile (`legacy`, kept in the manifest).
func _keep_painted_sizes(sources: Array, before: Dictionary, offered: Dictionary) -> void:
	var added := 0
	var roots := {}
	for item: Array in _worlds():
		roots[item[0]] = true
		var layer: TileMapLayer = item[3]
		for cell in layer.get_used_cells():
			var source_id := layer.get_cell_source_id(cell)
			if not offered.has(source_id):
				continue
			var shown: Variant = _shown(before, layer, cell)
			if shown == null or _is_offered(offered[source_id], shown[0], shown[1]):
				continue
			var entry: Dictionary = sources[source_id]
			var legacy: Dictionary = entry.get("legacy", {})
			var key := _key(shown[0], shown[1])
			if not legacy.has(key):
				var taken := 0
				for other: String in legacy:
					if other.get_slice("|", 0) == shown[0]:
						taken = maxi(taken, int(legacy[other]))
				legacy[key] = taken + 1
				added += 1
			entry["legacy"] = legacy
	for root: Node in roots:
		root.free()
	if added > 0:
		print("kept %d more painted sizes the palette no longer offers" % added)


## Where a scene at a size is painted now: [coords, alternative], or [] when it has no tile.
static func _place(entry: Dictionary, offered: Dictionary, scene: String, size: float) -> Array:
	var slots: Dictionary = entry.get("slots", {})
	if _is_offered(offered, scene, size):
		for kept: float in offered[scene]:
			if is_equal_approx(snappedf(kept, 0.01), snappedf(size, 0.01)):
				var slot: Variant = slots.get(_key(scene, kept))
				return [] if slot == null else [Vector2i(int(slot[0]), int(slot[1])), 0]
	var normal: Variant = slots.get(_key(scene, NORMAL))
	var legacy: Variant = (entry.get("legacy", {}) as Dictionary).get(_key(scene, size))
	return [] if normal == null or legacy == null else [Vector2i(int(normal[0]), int(normal[1])), int(legacy)]


## Moves every painted cell whose tile moved to its new tile, in every world, and saves the worlds
## that changed.
func _move_painted(sources: Array, before: Dictionary, offered: Dictionary) -> void:
	var moved := {}
	var lost := {}
	var items := _worlds()
	for item: Array in items:
		var layer: TileMapLayer = item[3]
		for cell in layer.get_used_cells():
			var source_id := layer.get_cell_source_id(cell)
			if not offered.has(source_id):
				continue
			var shown: Variant = _shown(before, layer, cell)
			if shown == null:
				continue
			var place := _place(sources[source_id], offered[source_id], shown[0], shown[1])
			if place.is_empty():
				lost[item[1]] = int(lost.get(item[1], 0)) + 1
				continue
			var flags := layer.get_cell_alternative_tile(cell) & Props.FLIP_FLAGS
			if place[0] != layer.get_cell_atlas_coords(cell) or place[1] | flags != layer.get_cell_alternative_tile(cell):
				layer.set_cell(cell, source_id, place[0], place[1] | flags)
				moved[item[1]] = int(moved.get(item[1], 0)) + 1
	var saved := {}
	for item: Array in items:
		var path: String = item[1]
		if moved.has(path) and not saved.has(path):
			saved[path] = true
			var err := SceneSave.save(item[0], path, item[2])
			if err == OK:
				print("%s: %d painted props moved to their new tiles" % [path.get_file(), moved[path]])
			else:
				push_error("build_old_prop_palettes: %s not saved (%s): restore the palette files and worlds from git and run again" % [path, error_string(err)])
		if lost.has(path):
			push_warning("%s: %d painted props have no tile any more" % [path.get_file(), lost[path]])
	var freed := {}
	for item: Array in items:
		if not freed.has(item[0]):
			freed[item[0]] = true
			(item[0] as Node).free()


func _art_path(entry: Dictionary) -> String:
	return ART_DIR + "%s-%s.png" % [PALETTE, str(entry["name"]).replace(" ", "-")]


## How far a prop's visible picture reaches from its foot at `size` (units): {left, right, up,
## down}, or {} when it shows nothing.
func _reach(scene: String, size: float) -> Dictionary:
	var box := Pictures.picture(scene, size)
	if not box.has_area():
		return {}
	return {"left": ceili(maxf(-box.position.x, 0.0)), "right": ceili(maxf(box.end.x, 0.0)),
			"up": ceili(maxf(-box.position.y, 1.0)), "down": ceili(maxf(box.end.y, 0.0))}


## The squares a picture of `reach` needs, its foot in the slot's middle, never under `square` px.
static func _squares(reach: Dictionary, square: int) -> Vector2i:
	var half := maxi(int(reach["left"]), int(reach["right"])) + 1
	var least := ceili(square / float(GRID))
	return Vector2i(maxi(least, ceili(2 * half / float(GRID))), maxi(least, ceili((reach["up"] + reach["down"] + 2) / float(GRID))))


## Gives every tile of a source a slot (squares: [x, y, width, height]) big enough for its picture:
## slots already given stay unless the picture outgrew them or the source's SQUARE changed; new ones
## are packed in rows, a scene's sizes side by side, after the last row.
func _allocate(entry: Dictionary, reaches: Dictionary, offered: Dictionary) -> void:
	var slots: Dictionary = entry.get("slots", {})
	if int(entry.get("slot_square", 0)) != int(entry["square"]):
		# a new least square: lay the whole source out again (the worlds' cells follow)
		slots = {}
		entry.erase("width")
		entry["slot_square"] = entry["square"]
	var groups: Array = []
	var area := 0
	var widest := 1
	for scene: String in entry["scenes"]:
		if scene.is_empty():
			continue
		var group: Array = []
		for size: float in offered.get(scene, []):
			var key := _key(scene, size)
			if not reaches.has(key):
				continue
			var need := _squares(reaches[key], int(entry["square"]))
			var slot: Variant = slots.get(key)
			if slot != null and int(slot[2]) >= need.x and int(slot[3]) >= need.y:
				continue
			group.append([key, need])
			area += need.x * need.y
		if not group.is_empty():
			groups.append(group)
			widest = maxi(widest, group.reduce(func(sum: int, item: Array) -> int: return sum + item[1].x, 0))
	if not entry.has("width"):
		entry["width"] = maxi(widest, ceili(sqrt(ASPECT * area)))
	var width := maxi(int(entry["width"]), widest)
	entry["width"] = width
	var row_y := 0
	for slot: Array in slots.values():
		row_y = maxi(row_y, int(slot[1]))
	var row_h := 0
	var x := 0
	for slot: Array in slots.values():
		if int(slot[1]) == row_y:
			row_h = maxi(row_h, int(slot[3]))
			x = maxi(x, int(slot[0]) + int(slot[2]))
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


## Where a picture's foot goes in its slot (px): the middle, its lowest pixel on the slot's floor.
static func _foot(slot: Array, reach: Dictionary) -> Vector2i:
	return Vector2i(int(slot[2]) * GRID / 2, int(slot[3]) * GRID - int(reach["down"]) - 1)


## Lays out and renders one source's palette image, every prop at its true size in its slot.
## Returns {key: reach} for the tiles it drew.
func _render_source(entry: Dictionary, offered: Dictionary) -> Dictionary:
	var reaches := {}
	for scene: String in entry["scenes"]:
		if scene.is_empty():
			continue
		for size: float in offered.get(scene, []):
			var reach := _reach(scene, size)
			if not reach.is_empty():
				reaches[_key(scene, size)] = reach
	_allocate(entry, reaches, offered)
	var slots: Dictionary = entry["slots"]
	var sheet := Vector2i(int(entry["width"]), 1)
	for key: String in reaches:
		var slot: Array = slots[key]
		sheet.y = maxi(sheet.y, int(slot[1]) + int(slot[3]))
	sheet *= GRID
	if sheet.x > MAX_IMAGE or sheet.y > MAX_IMAGE:
		push_warning("%s / %s: palette image %s is over %d px" % [PALETTE, entry["name"], sheet, MAX_IMAGE])
	var viewport := SubViewport.new()
	viewport.size = sheet
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for key: String in reaches:
		var prop := Props.make_prop({"scene": key.get_slice("|", 0), "at": Vector2.ZERO,
				"size": float(key.get_slice("|", 1)), "flip": false})
		if prop == null:
			continue
		Pictures.still(prop)
		var slot: Array = slots[key]
		prop.position = Vector2(Vector2i(int(slot[0]), int(slot[1])) * GRID + _foot(slot, reaches[key]))
		viewport.add_child(prop)
	for f in 6:
		await process_frame
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART_DIR))
	for attempt in SceneSave.TRIES:
		if image.save_png(ProjectSettings.globalize_path(_art_path(entry))) == OK:
			break
		OS.delay_msec(SceneSave.RETRY_MS)
	viewport.free()
	print("%s / %s: %d tiles, %s px" % [PALETTE, entry["name"], reaches.size(), sheet])
	return reaches


## The tile set: one atlas source per palette source (a retired one leaves its id unused) on a GRID
## px grid, each tile covering its slot and carrying its scene, anchor and size (custom data the
## PropLayer reads), the sizes kept for painted props as alternatives of the normal tile (drawn
## transparent: their picture is the normal one). Its texture origin draws the picture's foot on
## the prop's foot: Godot draws a tile's texture centred on its cell, moved back by the origin, so
## centre - slot / 2 - origin + foot must be the cell's corner + anchor.
func _write_tileset(sources: Array, layouts: Dictionary) -> bool:
	var tile: int = CONFIG["tile"]
	var lines := PackedStringArray(['[gd_resource type="TileSet" format=3]', ""])
	var live := range(sources.size()).filter(func(i: int) -> bool: return not sources[i].get("retired", false))
	for i: int in live:
		lines.append('[ext_resource type="Texture2D" path="%s" id="tex_%d"]' % [_art_path(sources[i]), i])
	lines.append("")
	for i: int in live:
		var entry: Dictionary = sources[i]
		var reaches: Dictionary = layouts[i]
		var slots: Dictionary = entry["slots"]
		var anchors: Dictionary = entry["anchors"]
		var legacy: Dictionary = entry.get("legacy", {})
		lines.append('[sub_resource type="TileSetAtlasSource" id="src_%d"]' % i)
		lines.append('resource_name = "%s"' % entry["name"])
		lines.append('texture = ExtResource("tex_%d")' % i)
		lines.append("texture_region_size = Vector2i(%d, %d)" % [GRID, GRID])
		for key: String in reaches:
			var scene := key.get_slice("|", 0)
			var size := float(key.get_slice("|", 1))
			var slot: Array = slots[key]
			var anchor: Array = anchors.get(scene, [0, 0])
			var foot := _foot(slot, reaches[key])
			var origin := foot - Vector2i(int(slot[2]), int(slot[3])) * GRID / 2 + Vector2i(tile, tile) / 2 \
					- Vector2i(roundi(anchor[0]), roundi(anchor[1]))
			var at := "%d:%d" % [int(slot[0]), int(slot[1])]
			lines.append("%s/size_in_atlas = Vector2i(%d, %d)" % [at, int(slot[2]), int(slot[3])])
			var alternatives := [[0, size]]
			if is_equal_approx(size, NORMAL):
				for kept: String in legacy:
					if kept.get_slice("|", 0) == scene:
						alternatives.append([int(legacy[kept]), float(kept.get_slice("|", 1))])
			for alternative: Array in alternatives:
				var data := "%s/%d" % [at, alternative[0]]
				lines.append("%s = %d" % [data, alternative[0]])
				if alternative[0] != 0:
					# a kept size shows the normal picture, so its square would not match: draw none
					lines.append("%s/modulate = Color(1, 1, 1, 0)" % data)
				lines.append("%s/texture_origin = Vector2i(%d, %d)" % [data, origin.x, origin.y])
				lines.append('%s/custom_data_0 = "%s"' % [data, scene])
				lines.append("%s/custom_data_1 = Vector2(%s, %s)" % [data, anchor[0], anchor[1]])
				lines.append("%s/custom_data_2 = %s" % [data, alternative[1]])
		lines.append("")
	lines.append("[resource]")
	lines.append("tile_size = Vector2i(%d, %d)" % [tile, tile])
	lines.append('custom_data_layer_0/name = "%s"' % Props.SCENE_DATA)
	lines.append("custom_data_layer_0/type = %d" % TYPE_STRING)
	lines.append('custom_data_layer_1/name = "%s"' % Props.ANCHOR_DATA)
	lines.append("custom_data_layer_1/type = %d" % TYPE_VECTOR2)
	lines.append('custom_data_layer_2/name = "%s"' % Props.SIZE_DATA)
	lines.append("custom_data_layer_2/type = %d" % TYPE_FLOAT)
	for i: int in live:
		lines.append('sources/%d = SubResource("src_%d")' % [i, i])
	lines.append("")
	var path: String = CONFIG["tileset"]
	var uid := ""
	if FileAccess.file_exists(path):
		var found := RegEx.create_from_string("\\[gd_resource [^\\]]*uid=\"([^\"]+)\"").search(FileAccess.get_file_as_string(path))
		if found != null:
			uid = found.get_string(1)
	if not uid.is_empty():
		lines[0] = '[gd_resource type="TileSet" format=3 uid="%s"]' % uid
	var err := SceneSave.write_text(path, "\n".join(lines))
	if err != OK:
		push_error("build_old_prop_palettes: cannot write %s (%s)" % [path, error_string(err)])
		return false
	print("%s: %s" % [PALETTE, path])
	return true
