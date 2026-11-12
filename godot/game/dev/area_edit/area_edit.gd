@tool
extends RefCounted
## Editing a few chunk worlds as one scene (docs/godot/WORLD_ATLAS.md "Editing an area", owner
## 2026-11-01): rivers, roads and ridges cross chunk lines, which is hard to shape one chunk tab at a
## time. `open` joins a rectangle of whole chunks (at most MAX_CHUNKS) into one temporary scene,
## game/dev/area_edit/areas/area-<first>-<last>.tscn (not in git): every painted layer (ground,
## forest, elevation, cliffs, level-collision, walls, fences, the prop layers) is one layer over the
## whole area (a chunk's layer joins the one of its name, else of its kind: `_kind`), and each
## chunk's nodes stand under a locked holder named after the chunk world, at the chunk's place. Edit
## it with the usual tools; `write_back` cuts it into the chunk files again:
## - each chunk's file keeps its own root, metadata, script and layers' settings; the cells painted,
##   erased or changed inside the area go to every chunk that keeps that cell, in its own layer of
##   that kind (a chunk keeps a margin of some layers past its edges, and the prop cells whose
##   picture reaches into it: tools/lib/chunk_cut.gd); the cells changed past the area's edge are
##   not written (they belong to chunks outside it);
## - the ground's sheet frames (TerrainEdges.sheet_frame) count from the area's corner in the area
##   and from each chunk's own corner in a chunk written back (`cut`), as the game draws it;
## - each chunk gets its holder's nodes back, each after the layer it followed in the file; a node
##   dragged across a chunk line moves to the chunk it now stands in (`map_id`s naming the old chunk
##   name the new one); nodes dropped in at the area's own level (the Scenery dock's `Scenery` and
##   `Enemies`) go to the chunk under them; a node dragged out of the area, and an exit or a player
##   spawn dragged into another chunk, goes back where it stood;
## - scenery a chunk keeps from a neighbour because its picture reaches in is hidden in the area
##   (`MIRROR_META`), so each piece shows once; it goes when its original changes, and a changed or
##   new piece of scenery is copied into each chunk of the area it reaches into, as the cut does
##   (scenery reaching past the area's edge is only noted);
## - only the chunks that changed are written, each as close to its old file as Godot allows
##   (SceneSave.match_saved); a door that changed chunk is moved in game/data/world-chunks.json.
## All or nothing: nothing is written when a chunk's file changed on disk since the area was opened
## (a hash per chunk), or when a chunk that changed cannot be written (it cannot be cut, or the area
## cannot give it back exactly with nothing edited: `round_trip`).
##
## Owner: world (atlas).

const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")
const ChunkCut := preload("res://tools/lib/chunk_cut.gd")
const SceneSave := preload("res://tools/lib/scene_save.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")

const AREAS_DIR := "res://game/dev/area_edit/areas/"
## The copy of each area as opened (the write-back compares with it) and the cut chunks' scratch files.
const WORK_DIR := "user://area_edit/"
const ROOT_SCRIPT := "res://game/dev/area_edit/area_root.gd"
## The most chunks an area joins: a bigger scene makes the editor slow (the Wilds as one scene was).
const MAX_CHUNKS := 6
## The area root's record: {rect (Rect2i, map chunks), chunk_units, tile, base (the copy's path),
## base_pending (the editor's first save still to be copied), chunks: [{id, world, chunk, path,
## offset, hash, exact}]}.
const AREA_META := &"area_edit"
## A holder's chunk world; a hidden copy's original (its path from the area's root) and whether it
## showed in its chunk.
const CHUNK_META := &"area_chunk"
const MIRROR_META := &"area_mirror_of"
const SHOWN_META := &"area_mirror_shown"
const LOCK_META := &"_edit_lock_"
const SCENERY_GROUP := "Scenery"
## How close (units) two pieces of scenery stand to count as the same piece.
const SAME_SPOT := 0.5


# --- naming -------------------------------------------------------------------------------------

## The rectangle of chunks "E4:F5" (or "E4") names, in map chunk coordinates; empty when it names none.
static func parse_rect(text: String) -> Rect2i:
	var names := text.strip_edges().to_upper().replace(" ", "").split(":", false)
	if names.is_empty() or names.size() > 2:
		return Rect2i()
	var first := WorldMapData.chunk_coords(names[0])
	var last := WorldMapData.chunk_coords(names[names.size() - 1])
	if first.x < 0 or last.x < 0:
		return Rect2i()
	var corner := first.min(last)
	return Rect2i(corner, first.max(last) - corner + Vector2i.ONE)


## "E4:F5" for the rectangle from E4 to F5 ("E4" for one chunk).
static func rect_name(rect: Rect2i) -> String:
	var first := WorldMapData.chunk_name(rect.position)
	var last := WorldMapData.chunk_name(rect.end - Vector2i.ONE)
	return first if first == last else "%s:%s" % [first, last]


## The area scene of `rect`.
static func scene_path(rect: Rect2i) -> String:
	return AREAS_DIR + "area-%s.tscn" % rect_name(rect).to_lower().replace(":", "-")


## The copy of the area scene at `path` kept as it was opened (what the write-back compares with).
static func base_path(path: String) -> String:
	return WORK_DIR + path.get_file().get_basename() + ".base.tscn"


## True when the area scene at `path` holds edits not written back: it differs from its copy as
## opened (or the copy is gone). Closing its tab keeps them: the area lives until Close area.
static func has_edits(path: String) -> bool:
	var base := base_path(path)
	return not FileAccess.file_exists(base) or FileAccess.get_file_as_string(path) != FileAccess.get_file_as_string(base)


## Deletes the area scene at `path` and its copy (its edits not written back are lost).
static func discard(path: String) -> void:
	for file in [path, base_path(path)]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))


## The areas whose scenes exist (the ones being edited): {scene path: rect}.
static func open_areas() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(AREAS_DIR):
		return out
	for file in DirAccess.get_files_at(AREAS_DIR):
		if file.begins_with("area-") and file.ends_with(".tscn"):
			var rect := parse_rect(file.trim_prefix("area-").trim_suffix(".tscn").replace("-", ":"))
			if rect.has_area():
				out[AREAS_DIR + file] = rect
	return out


## The chunk worlds of `rect` in reading order: [{id, world, chunk (its name), path, offset (world
## units from the area's corner)}]; `problems` gets a line for each chunk without a chunk world.
static func parts_of(rect: Rect2i, chunk_units: Vector2, problems: PackedStringArray) -> Array[Dictionary]:
	WorldChunks.reload()
	var by_name := {}
	var table := WorldChunks.table()
	for world: String in table:
		var chunks: Dictionary = (table[world] as Dictionary).get("chunks", {})
		for id: String in chunks:
			by_name[str(chunks[id])] = [world, id]
	var parts: Array[Dictionary] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var chunk := Vector2i(x, y)
			var chunk_name := WorldMapData.chunk_name(chunk)
			var found: Variant = by_name.get(chunk_name)
			var path := WorldChunks.scene_path(str(found[1])) if found != null else ""
			if found == null or not FileAccess.file_exists(path):
				problems.append("%s has no chunk world" % chunk_name)
				continue
			parts.append({"id": str(found[1]), "world": str(found[0]), "chunk": chunk_name, "path": path,
					"offset": Vector2(chunk - rect.position) * chunk_units})
	return parts


# --- opening --------------------------------------------------------------------------------------

## Joins the chunk worlds of `rect` into its area scene (an existing one is replaced: the edits not
## written back are lost) and keeps a copy for the write-back (`for_editor`: the editor's first save
## of the area replaces it, area_root.gd). Returns {path, error, notes}: the notes name the chunks
## whose layers draw shifted in the area, and the chunks the area cannot give back exactly (an area
## with one is never written back).
static func open(rect: Rect2i, map: WorldMapData, for_editor: bool = false) -> Dictionary:
	var notes := PackedStringArray()
	var result := {"path": scene_path(rect), "error": "", "notes": notes}
	if not rect.has_area():
		result["error"] = "Name a rectangle of whole chunks, as E4:F5."
		return result
	if rect.get_area() > MAX_CHUNKS:
		result["error"] = "%s is %d chunks: an area holds at most %d (a bigger scene makes the editor slow)." % [
				rect_name(rect), rect.get_area(), MAX_CHUNKS]
		return result
	var problems := PackedStringArray()
	var parts := parts_of(rect, map.chunk_units(), problems)
	if not problems.is_empty():
		result["error"] = "; ".join(problems) + "."
		return result
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AREAS_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	var path: String = result["path"]
	var base := base_path(path)
	var root := build(rect, parts, map.chunk_units(), map.tile_size)
	var info: Dictionary = root.get_meta(AREA_META)
	info["base"] = base
	info["base_pending"] = for_editor
	var err := _save(root, path)
	if err != OK:
		root.free()
		result["error"] = "Could not save %s (%s)." % [path, error_string(err)]
		return result
	notes.append_array(info["notes"])
	# Each chunk as the area gives it back with nothing edited: a chunk that does not come back
	# exactly is never written.
	var check := round_trip(path)
	for part: Dictionary in info["chunks"]:
		var lines: int = check.get(part["id"], -1)
		part["exact"] = lines == 0
		if lines != 0:
			notes.append("%s does not come back exactly from the area (%s): it will not be written back" % [
					part["chunk"], "%d lines differ" % lines if lines > 0 else "it cannot be cut"])
	result["notes"] = notes
	root.set_meta(AREA_META, info)
	err = _save(root, path)
	root.free()
	if err == OK:
		err = SceneSave.write_text(base, FileAccess.get_file_as_string(path))
	if err != OK:
		result["error"] = "Could not save %s (%s)." % [path, error_string(err)]
	return result


## The area scene's root for the chunk worlds `parts` of `rect` (see the top).
static func build(rect: Rect2i, parts: Array[Dictionary], chunk_units: Vector2, tile: int) -> Node2D:
	var root := Node2D.new()
	root.name = "area-" + rect_name(rect).replace(":", "-")
	root.y_sort_enabled = true
	var chunks: Array[Node2D] = []
	var notes := PackedStringArray()
	for part in parts:
		var text := FileAccess.get_file_as_string(part["path"])
		part["hash"] = text.sha256_text()
		var packed := ResourceLoader.load(part["path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var chunk := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		var marked := _keep_hidden_edits(chunk, text)
		if not marked.is_empty():
			notes.append("%s: %s made editable (it holds changes Godot drops on any save while it is not; a write-back of the chunk adds its [editable] line)" % [
					part["chunk"], ", ".join(marked)])
		chunks.append(chunk)
	# One layer per kind (script and tile set), in the chunks' order: a chunk's layer joins the one
	# of its name, else one of its kind at its offset, or any forest (level-1's `ForestLayer` is
	# Gloop's `forest`).
	var layers: Array[TileMapLayer] = []
	var matches: Array[Dictionary] = []
	# For each chunk: the chunk's own name of each of the area's layers it has.
	var own_names: Array[Dictionary] = []
	for i in chunks.size():
		var own: Array[TileMapLayer] = []
		for child: Node in chunks[i].get_children():
			if child is TileMapLayer:
				own.append(child as TileMapLayer)
		var matched := {}
		var taken := {}
		for layer in own:
			var joined := _named(layers, str(layer.name))
			if joined != null and not taken.has(joined) and _kind(joined) == _kind(layer):
				matched[layer] = joined
				taken[joined] = true
		for layer in own:
			if matched.has(layer):
				continue
			for joined in layers:
				# Only a forest joins across offsets (level-1's ForestLayer stands 23 units up): walls
				# and `walls-shifted-32-0` are the same kind, 32 units apart on purpose.
				if not taken.has(joined) and _kind(joined) == _kind(layer) \
						and (joined.position == layer.position or ChunkCut.script_path(layer).ends_with("forest_layer.gd")):
					matched[layer] = joined
					taken[joined] = true
					break
		var after := -1
		var names := {}
		var shifted := PackedStringArray()
		for layer in own:
			if not matched.has(layer):
				var joined := layer.duplicate() as TileMapLayer
				joined.clear()
				layers.insert(after + 1, joined)
				matched[layer] = joined
			var joined: TileMapLayer = matched[layer]
			after = layers.find(joined)
			names[str(joined.name)] = str(layer.name)
			if joined.position != layer.position:
				shifted.append("%s %s (the area's %s %s)" % [layer.name, _placing(layer), joined.name, _placing(joined)])
			elif joined.visible != layer.visible:
				shifted.append("%s %s in its scene, %s in the area" % [layer.name, "shown" if layer.visible else "hidden",
						"shown" if joined.visible else "hidden"])
		if not shifted.is_empty():
			notes.append("%s: %s; it draws so here (its cells still go back where painted)" % [
					parts[i]["chunk"], ", ".join(shifted)])
		matches.append(matched)
		own_names.append(names)
	var whole_tiles := Vector2i((chunk_units / float(tile)).round()) * rect.size
	for joined in layers:
		if joined.has_meta(&"columns"):
			joined.set_meta(&"columns", whole_tiles.x)
			joined.set_meta(&"rows", whole_tiles.y)
		var chunk_cells := Vector2i((chunk_units / ChunkCut.cell_size(joined, tile)).round())
		if ChunkCut.is_wall_layer(joined):
			joined.set(&"shown_cells", Rect2i(Vector2i.ZERO, chunk_cells * rect.size))
		if ChunkCut.script_path(joined).ends_with("forest_layer.gd"):
			# Each chunk's trees grow as in the chunk's own scene.
			joined.set(&"seed_period", chunk_cells)
		root.add_child(joined)
		joined.owner = root
	# Each chunk's own cells, then what the chunks keep past the area's edges (canopies, the tops
	# just north of it); what a chunk keeps of a neighbour inside the area comes from the neighbour.
	for pass_index in 2:
		for i in parts.size():
			for child: Node in chunks[i].get_children():
				var layer := child as TileMapLayer
				if layer == null:
					continue
				var joined: TileMapLayer = matches[i][layer]
				# The ground's sheet frames counted from the area's corner, as its edges draw them
				# (a chunk counts from its own: `cut` gives each written chunk its own frames).
				var ground := _is_ground(joined)
				var size := ChunkCut.cell_size(layer, tile)
				var tiles := Vector2i((chunk_units / size).round())
				var offset := Vector2i((parts[i]["offset"] / size).round())
				var own := Rect2i(Vector2i.ZERO, tiles)
				var whole := Rect2i(Vector2i.ZERO, tiles * rect.size)
				for cell in layer.get_used_cells():
					var source := layer.get_cell_source_id(cell)
					if source < 0:
						continue
					var at := cell + offset
					var take := own.has_point(cell) if pass_index == 0 \
							else not own.has_point(cell) and not whole.has_point(at) and joined.get_cell_source_id(at) < 0
					if take:
						var frame: Variant = TerrainEdges.sheet_frame(joined.tile_set, source, at) if ground else null
						joined.set_cell(at, source, frame if frame != null else layer.get_cell_atlas_coords(cell),
								layer.get_cell_alternative_tile(cell))
	for i in parts.size():
		var holder := Node2D.new()
		holder.name = parts[i]["id"]
		holder.position = parts[i]["offset"]
		holder.y_sort_enabled = true
		holder.set_meta(CHUNK_META, parts[i]["id"])
		holder.set_meta(LOCK_META, true)
		root.add_child(holder)
		holder.owner = root
		var chunk := chunks[i]
		for child: Node in chunk.get_children():
			if not child is TileMapLayer:
				_move(child, holder, chunk, root)
		chunk.free()
	_hide_copies(root, parts, chunk_units)
	var records: Array = []
	for i in parts.size():
		var record := parts[i].duplicate()
		record["layers"] = own_names[i]
		records.append(record)
	root.set_meta(AREA_META, {"rect": rect, "chunk_units": chunk_units, "tile": tile, "base": "",
			"base_pending": false, "chunks": records, "notes": notes})
	root.set_script(load(ROOT_SCRIPT))
	return root


## Marks editable in `root` (a scene instanced from `text`, its file) each instance the file keeps
## changes inside without its being editable: an override of a node inside it, or a node added
## under one of its nodes (level-1-c4's sally-port door scripts, level-1-d4's burrow trunk door).
## Godot drops those on any save of the scene while the instance is not editable. Returns the
## instances' paths.
static func _keep_hidden_edits(root: Node, text: String) -> PackedStringArray:
	var instances := PackedStringArray()
	var editable := {}
	# The nodes the file itself adds (a type or an instance), and for each parent path whether an
	# override (neither) names it.
	var declared := {}
	var parents := {}
	for line in text.replace("\r", "").split("\n"):
		if line.begins_with("[editable path=\""):
			editable[line.get_slice("\"", 1)] = true
			continue
		var path := SceneSave.node_path(line)
		if path.is_empty() or path == ".":
			continue
		var added := line.contains(" type=\"") or line.contains(" instance=")
		if added:
			declared[path] = true
		if line.contains(" instance="):
			instances.append(path)
		var parent := line.get_slice(" parent=\"", 1).get_slice("\"", 0)
		parents[parent] = bool(parents.get(parent, false)) or not added
	var marked := PackedStringArray()
	for instance in instances:
		if editable.has(instance):
			continue
		for parent: String in parents:
			# An override of the instance's own node, or a node under one of its own nodes (not under
			# a node the file added to it, which needs no editable flag).
			var own_node := parent.begins_with(instance + "/") \
					and not declared.has(instance + "/" + parent.trim_prefix(instance + "/").get_slice("/", 0))
			if own_node or (parent == instance and bool(parents[parent])):
				var node := root.get_node_or_null(NodePath(instance))
				if node != null:
					root.set_editable_instance(node, true)
					marked.append(instance)
				break
	return marked


static func _named(layers: Array[TileMapLayer], layer_name: String) -> TileMapLayer:
	for layer in layers:
		if str(layer.name) == layer_name:
			return layer
	return null


## What a layer paints: its script and its tile set.
static func _kind(layer: TileMapLayer) -> String:
	return "%s|%s" % [ChunkCut.script_path(layer), layer.tile_set.resource_path if layer.tile_set != null else ""]


static func _placing(layer: TileMapLayer) -> String:
	return "at (%d, %d)" % [roundi(layer.position.x), roundi(layer.position.y)]


## Hides the copies of scenery a chunk keeps from a neighbour in the area (the same scene at the
## same place, the original standing in the neighbour), so each piece shows once.
static func _hide_copies(root: Node2D, parts: Array[Dictionary], chunk_units: Vector2) -> void:
	var originals := {}
	var copies: Array[Node2D] = []
	for part in parts:
		var own := Rect2(part["offset"], chunk_units)
		for unit in units(root.get_node(NodePath(part["id"]))):
			if unit.scene_file_path.is_empty():
				continue
			if own.has_point(ChunkCut.place_in_world(unit, root)):
				originals[_spot_key(unit, root)] = unit
			else:
				copies.append(unit)
	for copy in copies:
		var original := originals.get(_spot_key(copy, root)) as Node2D
		if original == null:
			continue
		copy.set_meta(MIRROR_META, str(root.get_path_to(original)))
		copy.set_meta(SHOWN_META, copy.visible)
		copy.visible = false


## What makes two pieces of scenery the same piece: scene, place (SAME_SPOT), turn and size.
static func _spot_key(node: Node2D, root: Node) -> String:
	var at := (ChunkCut.place_in_world(node, root) / SAME_SPOT).round()
	return "%s|%d|%d|%.3f|%.3f|%.3f" % [node.scene_file_path, at.x, at.y, node.rotation, node.scale.x, node.scale.y]


## The nodes under `node` that stand somewhere: its Node2D children, a group's nodes instead of
## the group (ChunkCut.is_group).
static func units(node: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	_units(node, out)
	return out


static func _units(node: Node, out: Array[Node2D]) -> void:
	for child: Node in node.get_children():
		if not child is Node2D:
			continue
		if ChunkCut.is_group(child):
			_units(child, out)
		else:
			out.append(child as Node2D)


## Moves `node` from the scene of `old_root` under `to`, in the scene of `new_root`: the nodes
## `old_root` owned are owned by `new_root` (the insides of instances keep their own).
static func _move(node: Node, to: Node, old_root: Node, new_root: Node) -> void:
	_release(node, old_root)
	node.get_parent().remove_child(node)
	to.add_child(node)
	_adopt(node, new_root)


static func _release(node: Node, owner_node: Node) -> void:
	if node.owner == owner_node:
		node.owner = null
	for child: Node in node.get_children():
		_release(child, owner_node)


static func _adopt(node: Node, root: Node) -> void:
	if node.owner == null:
		node.owner = root
	for child: Node in node.get_children():
		_adopt(child, root)


static func _save(root: Node, path: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	return err


# --- writing back -------------------------------------------------------------------------------

## For each chunk of the area scene at `path`, how many lines differ between the chunk cut from the
## area with nothing edited and the chunk saved again on its own (`resaved`: Godot brings the
## overrides inside instances up to date on any save, as the editor does); 0: it comes back exactly,
## -1: it could not be cut.
static func round_trip(path: String) -> Dictionary:
	var out := {}
	var area := _instance(path)
	if area == null:
		return out
	var info: Dictionary = area.get_meta(AREA_META, {})
	for part: Dictionary in info.get("chunks", []):
		var cut_part := cut(area, part, {}, info["chunk_units"], info["tile"])
		var alone := resaved(part["path"])
		if not str(cut_part["error"]).is_empty() or alone.is_empty():
			out[part["id"]] = -1
			continue
		out[part["id"]] = _lines_differ(cut_part["text"], alone)
	area.free()
	return out


## The scene at `path` as Godot saves it again with nothing changed (SceneSave.match_saved), "" when
## it cannot be read.
static func resaved(path: String) -> String:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return ""
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_keep_hidden_edits(root, FileAccess.get_file_as_string(path))
	var scratch := WORK_DIR + "resaved-%d-%s" % [OS.get_process_id(), path.get_file()]
	var err := _save(root, scratch)
	root.free()
	if err != OK:
		return ""
	var text := SceneSave.match_saved(FileAccess.get_file_as_string(scratch), FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	return text


## Cuts the area scene at `path` into its chunk files (see the top), all or nothing: every chunk is
## cut first, and when one that changed cannot be written (it does not come back exactly, or cannot
## be cut) nothing is written. With `dry_dir`, the chunk scenes that changed are written there
## instead and nothing else is touched. Returns {error, written: [chunk worlds], unchanged, refused
## (the chunks that stopped it), notes}; every chunk written is to have its elevation cache baked
## (its ground, cliffs or elevation may have changed: Elevation._cache_key).
static func write_back(path: String, dry_dir: String = "") -> Dictionary:
	var written := PackedStringArray()
	var unchanged := PackedStringArray()
	var refused := PackedStringArray()
	var notes := PackedStringArray()
	var error := ""
	var current := _instance(path)
	var base: Node2D = null
	var info: Dictionary = current.get_meta(AREA_META, {}) if current != null else {}
	if info.is_empty():
		error = "%s is no area scene." % path
	else:
		base = _instance(str(info["base"]))
		if base == null:
			error = "The copy of the area as it was opened is gone (%s): discard the area and open it again." % info["base"]
	var parts: Array = info.get("chunks", [])
	if error.is_empty():
		var stale := PackedStringArray()
		for part: Dictionary in parts:
			if FileAccess.get_file_as_string(part["path"]).sha256_text() != str(part["hash"]):
				stale.append(str(part["chunk"]))
		if not stale.is_empty():
			error = "Not written: %s changed on disk since the area was opened. Discard the area (it reads the chunks again) and redo the edit there." % ", ".join(stale)
	var texts := {}
	var doors := {}
	if error.is_empty():
		var chunk_units: Vector2 = info["chunk_units"]
		var tile: int = info["tile"]
		var diffs := _inside(cell_changes(base, current), current, base, chunk_units * Vector2(info["rect"].size), tile, notes)
		_settle_nodes(current, base, parts, chunk_units, info["rect"].size, notes)
		for part: Dictionary in parts:
			var id := str(part["id"])
			var was := cut(base, part, {}, chunk_units, tile)
			var now := cut(current, part, diffs, chunk_units, tile)
			var problem := str(now["error"]) if not str(now["error"]).is_empty() else str(was["error"])
			if problem.is_empty() and now["text"] == was["text"]:
				unchanged.append(id)
				continue
			if problem.is_empty() and not bool(part.get("exact", false)):
				problem = "it was edited but does not come back exactly from the area"
			if not problem.is_empty():
				refused.append(id)
				notes.append("%s: %s" % [part["chunk"], problem])
				continue
			texts[id] = now["text"]
			doors[id] = now["doors"]
			if int(now["snapped"]) > 0:
				notes.append("%s: %d ground cells take the sheet pattern from the chunk's own corner, as the game draws it" % [
						part["chunk"], now["snapped"]])
		if not refused.is_empty():
			error = "Nothing written: %s cannot be written (below). The edits stay in the area." % ", ".join(refused)
	if current != null:
		current.free()
	if base != null:
		base.free()
	if error.is_empty():
		for part: Dictionary in parts:
			var id := str(part["id"])
			if not texts.has(id):
				continue
			var target := str(part["path"]) if dry_dir.is_empty() else dry_dir.path_join(id + ".tscn")
			var err := SceneSave.write_text(target, texts[id])
			if err != OK:
				error = "Could not write %s (%s)%s." % [target, error_string(err),
						"; written before it: " + ", ".join(written) if not written.is_empty() else ""]
				break
			written.append(id)
		if dry_dir.is_empty() and not written.is_empty():
			var written_doors := {}
			for id in written:
				written_doors[id] = doors[id]
			var moved := _update_doors(written_doors, parts)
			if not moved.is_empty():
				notes.append(moved)
	return {"error": error, "written": written, "unchanged": unchanged, "refused": refused, "notes": notes}


## The cell changes `diffs` (cell_changes) inside the area (`size`, world units); the changes
## past its edges (the margins the chunks keep, shown in the area) are dropped and noted: written
## only into the area's chunks, they would part from the chunks beyond that own them.
static func _inside(diffs: Dictionary, current: Node, base: Node, size: Vector2, tile: int, notes: PackedStringArray) -> Dictionary:
	var out := {}
	for layer_name: String in diffs:
		var model := current.get_node_or_null(NodePath(layer_name)) as TileMapLayer
		if model == null:
			model = base.get_node_or_null(NodePath(layer_name)) as TileMapLayer
		var whole := Rect2i(Vector2i.ZERO, Vector2i((size / ChunkCut.cell_size(model, tile)).round()))
		var kept := {}
		var dropped := 0
		var changes: Dictionary = diffs[layer_name]
		for cell: Vector2i in changes:
			if whole.has_point(cell):
				kept[cell] = changes[cell]
			else:
				dropped += 1
		if dropped > 0:
			notes.append("%d %s cells changed past the area's edge: not written (open an area that holds them)" % [dropped, layer_name])
		if not kept.is_empty():
			out[layer_name] = kept
	return out


static func _instance(path: String) -> Node2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D if packed != null else null


## The cells of the area's layers that differ between `base` and `current`: {layer name: {cell:
## [source, atlas coords, alternative], or null where erased}}.
static func cell_changes(base: Node, current: Node) -> Dictionary:
	var names := PackedStringArray()
	for root: Node in [base, current]:
		for child: Node in root.get_children():
			if child is TileMapLayer and not names.has(str(child.name)):
				names.append(str(child.name))
	var diffs := {}
	for layer_name in names:
		var was := _cells(base.get_node_or_null(NodePath(layer_name)) as TileMapLayer)
		var now := _cells(current.get_node_or_null(NodePath(layer_name)) as TileMapLayer)
		var changes := {}
		for cell: Vector2i in now:
			if not was.has(cell) or was[cell] != now[cell]:
				changes[cell] = now[cell]
		for cell: Vector2i in was:
			if not now.has(cell):
				changes[cell] = null
		if not changes.is_empty():
			diffs[layer_name] = changes
	return diffs


static func _cells(layer: TileMapLayer) -> Dictionary:
	var out := {}
	if layer == null:
		return out
	for cell in layer.get_used_cells():
		var source := layer.get_cell_source_id(cell)
		if source >= 0:
			out[cell] = [source, layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]
	return out


## Puts the area's nodes in the chunks they now stand in (see the top), noting what it did. The
## area is `area_chunks` chunks big.
static func _settle_nodes(current: Node2D, base: Node2D, parts: Array, chunk_units: Vector2, area_chunks: Vector2i,
		notes: PackedStringArray) -> void:
	var rects := {}
	var holders := {}
	var names := {}
	for part: Dictionary in parts:
		rects[part["id"]] = Rect2(part["offset"], chunk_units)
		holders[part["id"]] = current.get_node_or_null(NodePath(str(part["id"])))
		names[part["id"]] = part["chunk"]
		if holders[part["id"]] == null:
			holders[part["id"]] = _holder(current, part)
			notes.append("%s's holder was gone: its chunk gets no nodes from the area" % part["chunk"])
	# Scenery new, moved or turned: copied into the chunks of the area it reaches into.
	var touched: Array[Node2D] = []
	# The paths (in the area as opened) of the nodes moved to another chunk.
	var moved := {}
	# Nodes dropped in at the area's own level go to the chunk under them.
	for child: Node in current.get_children():
		if child is TileMapLayer or child.has_meta(CHUNK_META):
			continue
		if not child is Node2D:
			notes.append("%s stands nowhere (not under a chunk): not written" % child.name)
			continue
		# (a typed array: `[child]` in a conditional expression is untyped and cannot be assigned)
		var pieces: Array[Node2D] = []
		if ChunkCut.is_group(child):
			pieces = units(child)
		else:
			pieces.append(child as Node2D)
		for unit in pieces:
			var target := _chunk_at(rects, ChunkCut.place_in_world(unit, current), true)
			_move_unit(unit, current, holders[target], current)
			touched.append(unit)
			notes.append("%s (new) goes to %s" % [unit.name, names[target]])
		if is_instance_valid(child) and child.get_parent() == current and child.get_child_count() == 0:
			child.free()
	# Nodes dragged across a chunk line move to the chunk they stand in; one dragged out of the area,
	# and an exit or a spawn dragged into another chunk, goes back where it stood.
	for id: String in holders:
		var holder: Node2D = holders[id]
		for unit in units(holder):
			if unit.has_meta(MIRROR_META):
				continue
			var at := ChunkCut.place_in_world(unit, current)
			var path := current.get_path_to(unit)
			var was := base.get_node_or_null(path) as Node2D
			var then := ChunkCut.place_in_world(was, base) if was != null else Vector2.INF
			var same_place := was != null and at.distance_to(then) < 0.01
			if was == null or not same_place or was.rotation != unit.rotation or was.scale != unit.scale:
				touched.append(unit)
			if same_place:
				continue
			var target := _chunk_at(rects, at, false)
			if target == id or (was != null and _chunk_at(rects, then, false) == target):
				continue
			var keeps_chunk := ChunkCut.exit_script(unit) != null or (unit.get_parent() == holder and str(unit.name) == "player-spawn")
			if was != null and (target.is_empty() or keeps_chunk):
				unit.position += then - at
				notes.append("%s of %s was dragged %s: put back where it stood" % [unit.name, names[id],
						"out of the area" if target.is_empty() else "into %s (exits and spawns stay in their chunk)" % names[target]])
				continue
			if target.is_empty() or keeps_chunk:
				notes.append("%s (new) stands %s: written into %s where it stands" % [unit.name,
						"outside the area" if target.is_empty() else "in " + names[target], names[id]])
				continue
			moved[str(path)] = true
			var group := unit.get_parent()
			var old_name := str(unit.name)
			_move_unit(unit, holder, holders[target], current)
			ChunkCut.rename_map_id(unit, id, target, current)
			notes.append("%s moved from %s to %s%s" % [old_name, names[id], names[target],
					"" if str(unit.name) == old_name else " (as %s: the name was taken there)" % unit.name])
			for part: Node in group.get_children() if is_instance_valid(group) else []:
				if not part is Node2D and part.get_script() != null:
					notes.append("%s left group %s, which has script nodes: check it" % [unit.name, group.name])
					break
	# A hidden copy goes when its original changed or went (a new copy follows below).
	for id: String in holders:
		for unit in units(holders[id]):
			if not unit.has_meta(MIRROR_META):
				continue
			var path := NodePath(str(unit.get_meta(MIRROR_META)))
			var original := current.get_node_or_null(path) as Node2D
			var was := base.get_node_or_null(path) as Node2D
			if original != null and was != null and _spot_key(original, current) == _spot_key(was, base):
				continue
			var group := unit.get_parent()
			group.remove_child(unit)
			unit.free()
			_drop_if_empty(group, holders[id])
	for unit in touched:
		if not is_instance_valid(unit):
			continue
		var home := _home(unit)
		var in_scenery := _under(unit, SCENERY_GROUP, home)
		if home == null or not (ChunkCut.is_scenery(unit) or (in_scenery and not unit.scene_file_path.is_empty())):
			continue
		var at := ChunkCut.place_in_world(unit, current)
		var key := _spot_key(unit, current)
		for id: String in holders:
			var holder: Node2D = holders[id]
			if holder == home:
				continue
			var rect: Rect2 = rects[id]
			if not ChunkCut.overlaps(unit, at, rect) and not (in_scenery and ChunkCut.picture_overlaps(unit, at, rect)):
				continue
			var have := false
			for other in units(holder):
				have = have or _spot_key(other, current) == key
			if have:
				continue
			var copy := _copy_of(unit)
			var parent := _groups_in(holder, home, unit.get_parent(), current)
			parent.add_child(copy, true)
			_adopt(copy, current)
			copy.position = at - ChunkCut.place_in_world(parent, current)
			notes.append("%s also goes into %s (its picture reaches in)" % [unit.name, names[id]])
	# Scenery reaching past the area's edge: the chunk beyond keeps a copy the area cannot update.
	var area := Rect2(Vector2.ZERO, chunk_units * Vector2(area_chunks))
	for unit in touched:
		if is_instance_valid(unit) and _reaches_out(unit, current, area):
			notes.append("%s reaches past the area's edge: check its copy in the chunk beyond" % unit.name)
	for id: String in holders:
		var holder := base.get_node_or_null(NodePath(id))
		for unit in units(holder) if holder != null else []:
			var path := str(base.get_path_to(unit))
			if not unit.has_meta(MIRROR_META) and not moved.has(path) and current.get_node_or_null(path) == null \
					and _reaches_out(unit, base, area):
				notes.append("%s (deleted) reached past the area's edge: check its copy in the chunk beyond" % unit.name)


## True when `unit` (scenery in the scene of `root`) draws or collides past `area`.
static func _reaches_out(unit: Node2D, root: Node, area: Rect2) -> bool:
	var in_scenery := _under(unit, SCENERY_GROUP, root)
	if not ChunkCut.is_scenery(unit) and not (in_scenery and not unit.scene_file_path.is_empty()):
		return false
	var at := ChunkCut.place_in_world(unit, root)
	var far := maxf(area.size.x, area.size.y)
	for side in [Rect2(area.position - Vector2(far, far), Vector2(far, area.size.y + 2.0 * far)),
			Rect2(Vector2(area.end.x, area.position.y - far), Vector2(far, area.size.y + 2.0 * far)),
			Rect2(area.position - Vector2(0.0, far), Vector2(area.size.x, far)),
			Rect2(Vector2(area.position.x, area.end.y), Vector2(area.size.x, far))]:
		if ChunkCut.overlaps(unit, at, side) or (in_scenery and ChunkCut.picture_overlaps(unit, at, side)):
			return true
	return false


## A copy of the scene instance `node`: its scene instanced as the editor does, with what was changed
## on it and inside it (Node.duplicate would save every property of the copy, not only the changes).
static func _copy_of(node: Node2D) -> Node2D:
	var packed := load(node.scene_file_path) as PackedScene
	if packed == null:
		return node.duplicate() as Node2D
	var copy := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	copy.name = node.name
	_copy_changes(node, copy, node)
	return copy


static func _copy_changes(from: Node, to: Node, instance: Node) -> void:
	for property: Dictionary in from.get_property_list():
		var key: StringName = property["name"]
		if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE) or key == &"script":
			continue
		var value: Variant = from.get(key)
		if to.get(key) != value:
			to.set(key, value)
	for child: Node in from.get_children():
		var other := to.get_node_or_null(NodePath(str(child.name)))
		if other != null and child.owner == instance:
			_copy_changes(child, other, instance)


## A holder made for a chunk whose holder is gone.
static func _holder(current: Node2D, part: Dictionary) -> Node2D:
	var holder := Node2D.new()
	holder.name = part["id"]
	holder.position = part["offset"]
	holder.set_meta(CHUNK_META, part["id"])
	current.add_child(holder)
	holder.owner = current
	return holder


## The chunk (of `rects`) holding `at`; the nearest one when none does and `nearest`, else "".
static func _chunk_at(rects: Dictionary, at: Vector2, nearest: bool) -> String:
	var best := ""
	var best_distance := INF
	for id: String in rects:
		var rect: Rect2 = rects[id]
		if rect.has_point(at):
			return id
		var distance := at.distance_to(at.clamp(rect.position, rect.end))
		if distance < best_distance:
			best = id
			best_distance = distance
	return best if nearest else ""


## Moves `unit` (under `from`: a chunk's holder or the area's root) into holder `to`, under groups of
## the same names (made at the chunk's corner when missing), at the same place; a group it leaves
## empty goes.
static func _move_unit(unit: Node2D, from: Node, to: Node2D, root: Node) -> void:
	var at := ChunkCut.place_in_world(unit, root)
	var old_parent := unit.get_parent()
	var parent := _groups_in(to, from, old_parent, root)
	_release(unit, root)
	old_parent.remove_child(unit)
	parent.add_child(unit, true)
	_adopt(unit, root)
	unit.position = at - ChunkCut.place_in_world(parent, root)
	_drop_if_empty(old_parent, from)


## The node under `to` at the path `source_parent` has under `from` (each missing group made, a
## plain Node2D at the chunk's corner with the old group's sorting).
static func _groups_in(to: Node2D, from: Node, source_parent: Node, root: Node) -> Node2D:
	var chain: Array[Node] = []
	var node := source_parent
	while node != null and node != from:
		chain.push_front(node)
		node = node.get_parent()
	var into := to
	for group in chain:
		var next := into.get_node_or_null(NodePath(str(group.name))) as Node2D
		if next == null:
			next = Node2D.new()
			next.name = group.name
			next.y_sort_enabled = (group as CanvasItem).y_sort_enabled if group is CanvasItem else false
			next.z_index = (group as CanvasItem).z_index if group is CanvasItem else 0
			into.add_child(next)
			next.owner = root
		into = next
	return into


## Frees `group` (and the groups above it, up to `top`) when it is a plain group left empty.
static func _drop_if_empty(group: Node, top: Node) -> void:
	while group != null and group != top and group.get_child_count() == 0 and group.scene_file_path.is_empty() \
			and group.get_script() == null and group.get_class() == "Node2D":
		var parent := group.get_parent()
		parent.remove_child(group)
		group.free()
		group = parent


## The holder (chunk) `node` stands under, null when none.
static func _home(node: Node) -> Node2D:
	var current := node.get_parent()
	while current != null and not current.has_meta(CHUNK_META):
		current = current.get_parent()
	return current as Node2D


static func _under(node: Node, group_name: String, top: Node) -> bool:
	var current := node.get_parent()
	while current != null and current != top:
		if str(current.name) == group_name:
			return true
		current = current.get_parent()
	return false


## The text chunk `part`'s file gets from the area `area` (whose holder's nodes it takes): its file's
## root, settings and layers with the area's cell changes `diffs` applied, then the holder's nodes,
## each after the layer it followed in the file (in the holder's order; new ones last). Returns
## {text, doors ({door id: chunk world}), error}.
static func cut(area: Node2D, part: Dictionary, diffs: Dictionary, chunk_units: Vector2, tile: int) -> Dictionary:
	var result := {"text": "", "doors": {}, "error": "", "snapped": 0}
	var before := FileAccess.get_file_as_string(part["path"])
	var packed := ResourceLoader.load(part["path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var holder := area.get_node_or_null(NodePath(str(part["id"])))
	if packed == null or holder == null:
		result["error"] = "cannot read %s" % part["path"] if packed == null else "no holder %s in the area" % part["id"]
		return result
	var out := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	# The layer each of the file's nodes followed ("" before the first layer).
	var follows := {}
	var last_layer := ""
	for child: Node in out.get_children():
		if child is TileMapLayer:
			last_layer = str(child.name)
		else:
			follows[str(child.name)] = last_layer
			out.remove_child(child)
			child.free()
	# A ground written to gets its sheet frames counted from the chunk's own corner, where the game
	# draws its edges and its 128 px ground from: the painted cells (the area counts from its own
	# corner, and a cell the editor did not snap keeps the frame picked in the palette) and the
	# cells around them, so they meet without a seam.
	for ground: TileMapLayer in _apply_cells(out, area, part, diffs, chunk_units, tile):
		result["snapped"] += TerrainEdges.snap_frames(ground)
	var after := {}
	var new_nodes: Array[Node] = []
	for node: Node in holder.get_children():
		var node_name := str(node.name)
		if follows.has(node_name):
			if not after.has(follows[node_name]):
				after[follows[node_name]] = []
			(after[follows[node_name]] as Array).append(node)
		else:
			new_nodes.append(node)
	var order: Array = after.get("", []).duplicate()
	for child: Node in out.get_children():
		order.append(child)
		order.append_array(after.get(str(child.name), []))
	order.append_array(new_nodes)
	for node: Node in order:
		if node.get_parent() != out:
			_move(node, out, area, out)
	for i in order.size():
		out.move_child(order[i], i)
	for node: Node in out.find_children("*", "", true, false):
		if node.has_meta(MIRROR_META):
			(node as CanvasItem).visible = bool(node.get_meta(SHOWN_META, true))
			node.remove_meta(MIRROR_META)
			node.remove_meta(SHOWN_META)
	var arrivals := {}
	ChunkCut.list_places(out, str(part["id"]), arrivals, result["doors"])
	var scene := PackedScene.new()
	var err := scene.pack(out)
	out.free()
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
		var scratch := WORK_DIR + "cut-%d-%s.tscn" % [OS.get_process_id(), part["id"]]
		err = ResourceSaver.save(scene, scratch)
		if err == OK:
			result["text"] = SceneSave.match_saved(FileAccess.get_file_as_string(scratch), before)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	if err != OK:
		result["error"] = "could not pack it (%s)" % error_string(err)
	return result


## Applies the area's cell changes `diffs` to chunk `out`'s layers (each area layer to the chunk's
## own layer of it, by the record's `layers`): each cell to the chunk when it keeps that cell
## (ChunkCut.keep_rect, or a prop cell whose picture reaches in); a layer the chunk lacks is made like
## the area's. Returns the chunk's ground layers a cell was painted on.
static func _apply_cells(out: Node2D, area: Node2D, part: Dictionary, diffs: Dictionary, chunk_units: Vector2, tile: int) -> Array[TileMapLayer]:
	var grounds: Array[TileMapLayer] = []
	var own_names: Dictionary = part.get("layers", {})
	for layer_name: String in diffs:
		var joined := area.get_node_or_null(NodePath(layer_name)) as TileMapLayer
		var layer := out.get_node_or_null(NodePath(str(own_names.get(layer_name, layer_name)))) as TileMapLayer
		var model := joined if joined != null else layer
		if model == null:
			continue
		var size := ChunkCut.cell_size(model, tile)
		var tiles := Vector2i((chunk_units / size).round())
		var offset := Vector2i((part["offset"] / size).round())
		var keep := ChunkCut.keep_rect(model, tiles)
		var props := ChunkCut.is_prop_layer(model)
		var view := Rect2(part["offset"] - model.position, chunk_units)
		var changes: Dictionary = diffs[layer_name]
		for cell: Vector2i in changes:
			var local := cell - offset
			var value: Variant = changes[cell]
			if value == null:
				if layer != null and layer.get_cell_source_id(local) >= 0 and (props or keep.has_point(local)):
					layer.erase_cell(local)
				continue
			if not keep.has_point(local) and not (props and joined != null and ChunkCut.prop_reaches(joined, cell, view)):
				continue
			if layer == null:
				layer = _new_layer(out, joined, tiles)
			layer.set_cell(local, value[0], value[1], value[2])
			if _is_ground(layer) and not grounds.has(layer):
				grounds.append(layer)
	return grounds


## True for a world's ground layer (game/world/world_ground.gd), whose sheet frames wrap every 19
## cells (TerrainEdges.sheet_frame).
static func _is_ground(layer: TileMapLayer) -> bool:
	return layer != null and ChunkCut.script_path(layer).ends_with("world_ground.gd")


## A layer like the area's `joined`, empty, for a chunk `tiles` cells big, after the chunk's layers.
static func _new_layer(out: Node2D, joined: TileMapLayer, tiles: Vector2i) -> TileMapLayer:
	var layer := joined.duplicate() as TileMapLayer
	layer.clear()
	if layer.has_meta(&"columns"):
		layer.set_meta(&"columns", tiles.x)
		layer.set_meta(&"rows", tiles.y)
	if ChunkCut.is_wall_layer(layer):
		layer.set(&"shown_cells", Rect2i(Vector2i.ZERO, tiles))
	if ChunkCut.script_path(layer).ends_with("forest_layer.gd"):
		layer.set(&"seed_period", Vector2i.ZERO)
	var last := -1
	for child: Node in out.get_children():
		if child is TileMapLayer:
			last = child.get_index()
	out.add_child(layer)
	out.move_child(layer, last + 1)
	layer.owner = out
	return layer


## How many lines of `a` and `b` differ (lines only in one count; carriage returns aside).
static func _lines_differ(a: String, b: String) -> int:
	var left := a.replace("\r", "").split("\n")
	var right := b.replace("\r", "").split("\n")
	var counts := {}
	for line in left:
		counts[line] = int(counts.get(line, 0)) + 1
	var differ := 0
	for line in right:
		if int(counts.get(line, 0)) > 0:
			counts[line] = int(counts[line]) - 1
		else:
			differ += 1
	for line: String in counts:
		differ += int(counts[line])
	return differ


## Moves the doors of the chunks written (`doors`: chunk world -> {door id: chunk world}) in
## game/data/world-chunks.json, so travel back from an interior lands in the chunk with the door.
## Returns a note when doors moved, else "".
static func _update_doors(doors: Dictionary, parts: Array) -> String:
	var text := FileAccess.get_file_as_string(WorldChunks.PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return "%s could not be read: its doors were not checked" % WorldChunks.PATH
	var worlds: Dictionary = (parsed as Dictionary).get("worlds", {})
	var moved := PackedStringArray()
	for part: Dictionary in parts:
		var id := str(part["id"])
		if not doors.has(id) or not worlds.has(part["world"]):
			continue
		var table: Dictionary = (worlds[part["world"]] as Dictionary).get("doors", {})
		for door: String in table.keys():
			if str(table[door]) == id and not (doors[id] as Dictionary).has(door):
				table.erase(door)
				moved.append("%s left %s" % [door, part["chunk"]])
		for door: String in doors[id]:
			if str(table.get(door, "")) != id:
				# A door that left another world's chunk leaves that world's table.
				for world: String in worlds:
					((worlds[world] as Dictionary).get("doors", {}) as Dictionary).erase(door)
				table[door] = id
				moved.append("%s is in %s" % [door, part["chunk"]])
		(worlds[part["world"]] as Dictionary)["doors"] = table
	if moved.is_empty():
		return ""
	var out := JSON.stringify(parsed, "  ", false) + "\n"
	if text.contains("\r\n"):
		out = out.replace("\n", "\r\n")
	if SceneSave.write_text(WorldChunks.PATH, out) != OK:
		return "doors moved (%s) but %s could not be written" % [", ".join(moved), WorldChunks.PATH]
	WorldChunks.reload()
	return "doors: " + ", ".join(moved)
