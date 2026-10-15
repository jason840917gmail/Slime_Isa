extends SceneTree
## Cuts a placeholder region's world into one world scene per chunk, to try worlds a chunk in size
## (owner, 2026-10-12): res://game/scenes/worlds/chunks/<world>-<chunk>.tscn (scene id
## world.<world>-<chunk>, e.g. world.south-wilds-a6), 32 x 32 tiles each, for every chunk the region
## owns (WorldMapData.region_chunks). Run from the repo:
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/split_region_chunks.gd -- --region=<region key or world id>[,...]
##
## Each chunk gets the region world's cells in it (ground, forest, fences; the elevation with
## Elevation.MAX_ROWS_ABOVE rows above it, so the walls of the tops just north of it still hang in),
## its props, notes, arrival markers and exits to other regions; a `player-spawn` (the open cell
## nearest its middle) and `player-entry-<edge>` markers; and, along every edge it shares with
## another of the region's chunks, an exit the whole edge long (world_exit.gd `keep_along`): the
## player arrives at the same place along the neighbour's opposite edge. The scenes are registered
## in scene_index.json and kept out of the release "Web" export, and game/data/world-chunks.json
## (game/world/atlas/world_chunks.gd) records each chunk and which chunk holds each arrival marker:
## travel into the region by a marker goes straight to that chunk. The region's own world scene
## is then deleted (the chunks are the scenes to edit; -- --keep-whole keeps it): to rebuild a region
## from the sketch, run build_region_worlds.gd for it, then this tool. Running it again rewrites the
## chunks, except those edited since they were cut (-- --force rewrites them too). Several
## regions: --region=a,b,c.
##
## Owner: world (atlas).

const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const RegionScene := preload("res://tools/region_worlds/region_scene.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const WorldServiceScript := preload("res://game/autoload/world_service.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")
const PropLayerScript := preload("res://game/world/props/prop_layer.gd")
const PropPictures := preload("res://tools/lib/prop_pictures.gd")

const WORLDS_DIR := "res://game/scenes/worlds/"
const CHUNKS_DIR := "res://game/scenes/worlds/chunks/"
const SCENE_INDEX := "res://game/scenes/scene_index.json"
const EXPORT_PRESETS := "res://export_presets.cfg"
const RELEASE_PRESET := "Web"
## How deep (world units) the exit along a shared edge reaches into the chunk (a line at the edge:
## the slime crosses only when it reaches the screen's limit, owner 2026-10-14); how far past a
## chunk's edge an exit of the region world may lie and still be the chunk's (`_exit_part`).
const EDGE_STRIP := 4.0
const EXIT_PULL := 64.0
## Clear cells around a spawn (a tree, a fence or another level within it rules the cell out), and
## how many cells north of it no higher top may stand (its wall would hang over the spawn).
const SPAWN_ROOM := 1
const MAX_WALL_ROWS := 3
const EDGES := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
const OPPOSITE := {"north": "south", "east": "west", "south": "north", "west": "east"}
## Scenery (scene file names starting so): static props a chunk also gets from its neighbours when
## their picture or collision reaches into it (`_overlaps`), so a house or a tree on a chunk border
## shows on both sides; anything else (chests, items, NPCs, doors) lives in one chunk only.
const SCENERY: PackedStringArray = ["tree-", "wall-stone-solid", "rock-world-wall", "decoration-world-",
		"crystal-cluster-wall", "house-world-solid", "water-life"]
## Forest cells a chunk also takes past its edges (left, top, right, bottom), for the trees whose
## canopy reaches into it.
const FOREST_MARGIN := [1, 1, 1, 3]
## Tries at writing a file an open editor may hold for a moment, and the pause between them (ms).
const WRITE_ATTEMPTS := 10
const WRITE_RETRY_MS := 500
const CHUNK_META := &"world_map_chunk"
const CHUNK_OF_META := &"world_map_chunk_of"


## Each scenery scene's reach around its origin (`_reach`), read once.
static var _reaches := {}
## --force: rewrite chunks edited since they were cut; --keep-whole: keep the region's whole scene.
var _force := false
var _keep_whole := false
## --hand-made: also cut hand-made worlds (a preview: chunks only); --adopt: make the cut real
## (the table, and the whole scene deleted).
var _hand_made := false
var _adopt := false
## The table as it was before this run (each chunk's `written` hash).
var _written := {}


func _initialize() -> void:
	var wanted := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--region="):
			wanted = arg.trim_prefix("--region=").split(",", false)
		elif arg == "--force":
			_force = true
		elif arg == "--keep-whole":
			_keep_whole = true
		elif arg == "--hand-made":
			_hand_made = true
		elif arg == "--adopt":
			_adopt = true
	var map := WorldMapData.load_file()
	if map == null or wanted.is_empty():
		push_error("split_region_chunks: give -- --region=<region key or world id>[,...]")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHUNKS_DIR))
	var ids := PackedStringArray()
	var table := {}
	var cut_worlds := PackedStringArray()
	var failed := false
	_written = WorldChunks.table()
	for name in wanted:
		var entry := map.region(name)
		if entry.is_empty():
			entry = map.region_for_map(name)
		if entry.is_empty():
			push_error("split_region_chunks: no region '%s'" % name)
			failed = true
			continue
		var hand_made := not bool(entry.get("placeholder", false))
		if hand_made and not _hand_made:
			push_error("split_region_chunks: '%s' is hand-made: cut it with -- --hand-made (a preview), then -- --hand-made --adopt" % name)
			failed = true
			continue
		var done := _split_hand_made(map, entry, ids) if hand_made else _split(map, entry, ids)
		if done.is_empty():
			failed = true
		elif not hand_made or _adopt:
			table[str(entry["world"])] = done
			cut_worlds.append(str(entry["world"]))
		else:
			print("preview: %s's chunks are written and registered (F6 on one walks them); travel still goes to %s.tscn until -- --adopt" % [entry["world"], entry["world"]])
	_register_scenes(ids)
	_write_table(table)
	_exclude_from_release(map)
	if not _keep_whole and not cut_worlds.is_empty():
		_remove_whole(cut_worlds)
	quit(1 if failed else 0)


## Writes the chunk worlds of region `entry` (adding their ids to `ids`). Returns its entry for
## world-chunks.json ({"chunks": {chunk world: chunk name}, "arrivals": {marker: chunk world}}),
## {} when it failed.
func _split(map: WorldMapData, entry: Dictionary, ids: PackedStringArray) -> Dictionary:
	var key := str(entry["key"])
	var world := str(entry["world"])
	var packed := load(WORLDS_DIR + world + ".tscn") as PackedScene
	if packed == null:
		push_error("split_region_chunks: no world scene for '%s'" % world)
		return {}
	var source := packed.instantiate() as Node2D
	var chunks := map.region_chunks(key)
	var block := map.region_chunk_rect(key)
	var size := map.chunk_units()
	var names := {}
	var arrivals := {}
	var written := {}
	var spawn := ""
	var before: Dictionary = (_written.get(world, {}) as Dictionary).get("written", {})
	var failed := false
	for chunk in chunks:
		var id := chunk_id(world, chunk)
		var path := CHUNKS_DIR + id + ".tscn"
		ids.append(id)
		names[id] = WorldMapData.chunk_name(chunk)
		var area := Rect2(Vector2(chunk - block.position) * size, size)
		for child in source.get_children():
			if child is Node2D and _is_arrival(str(child.name)) and area.has_point((child as Node2D).position):
				arrivals[str(child.name)] = id
			elif child is Node2D and str(child.name) == "player-spawn" and area.has_point((child as Node2D).position):
				spawn = id
		# A chunk edited since it was cut (its file is not what this tool wrote) is kept.
		if not _force and FileAccess.file_exists(path) and before.has(id) and FileAccess.get_file_as_string(path).hash() != int(before[id]):
			print("kept %s: edited since it was cut (-- --force rewrites it)" % path)
			written[id] = int(before[id])
			continue
		var root := _chunk_scene(map, source, key, world, chunk, block, chunks)
		var stats: Dictionary = root.get_meta(&"split_stats")
		root.remove_meta(&"split_stats")
		var err := RegionScene.save(root, path)
		failed = failed or err != OK
		if err == OK:
			written[id] = FileAccess.get_file_as_string(path).hash()
		print("%s %s: %d props, %d exits to other regions, %d chunk edges, spawn %s" % [
				"wrote" if err == OK else "FAILED (%d)" % err, path, stats["props"], stats["exits"], stats["edges"], stats["spawn"]])
	for child in source.get_children():
		if str(child.name).begins_with("arrive-from-") and not arrivals.has(str(child.name)):
			print("  ! %s lies in none of %s's chunks: travel to it goes to the region's spawn chunk" % [child.name, world])
	source.free()
	if spawn.is_empty() and not names.is_empty():
		spawn = names.keys()[0]
	return {} if failed else {"chunks": names, "arrivals": arrivals, "doors": {}, "spawn": spawn, "written": written}


## Markers travel arrives at: a neighbour's exit's `arrive-from-<world>-<n>`, an edge's
## `player-entry-<edge>`.
static func _is_arrival(node_name: String) -> bool:
	return node_name.begins_with("arrive-from-") or node_name.begins_with("player-entry-")


## Deletes the whole scenes of the cut `worlds` (the chunks replace them: owner, 2026-10-12) and
## takes them out of scene_index.json and the release preset's exclude_filter.
func _remove_whole(worlds: PackedStringArray) -> void:
	for world in worlds:
		var path := WORLDS_DIR + world + ".tscn"
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			print("removed %s (cut into chunks)" % path if err == OK else "could not remove %s (%d)" % [path, err])
	var text := FileAccess.get_file_as_string(SCENE_INDEX)
	var lines := text.split("\n")
	var kept := PackedStringArray()
	for line in lines:
		var drop := false
		for world in worlds:
			drop = drop or line.begins_with("  \"world.%s\":" % world)
		if not drop:
			kept.append(line)
	# The line before the closing brace has no comma.
	for i in range(kept.size() - 1, -1, -1):
		if kept[i].strip_edges() == "}":
			if i > 0 and kept[i - 1].ends_with(","):
				kept[i - 1] = kept[i - 1].trim_suffix(",")
			break
	var out := "\n".join(kept)
	if out != text and JSON.parse_string(out) is Dictionary:
		_write_text(SCENE_INDEX, out)
	var presets := FileAccess.get_file_as_string(EXPORT_PRESETS)
	var changed := presets
	for world in worlds:
		var scene := WORLDS_DIR.trim_prefix("res://") + world + ".tscn"
		changed = changed.replace(scene + ",", "").replace("," + scene + "\"", "\"")
	if changed != presets:
		_write_text(EXPORT_PRESETS, changed)


## Merges `table` (world -> its chunks and arrivals) into game/data/world-chunks.json (WorldChunks).
func _write_table(table: Dictionary) -> void:
	if table.is_empty():
		return
	var worlds := {}
	if FileAccess.file_exists(WorldChunks.PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WorldChunks.PATH))
		if parsed is Dictionary:
			worlds = (parsed as Dictionary).get("worlds", {})
	for world: String in table:
		worlds[world] = table[world]
	var keys := worlds.keys()
	keys.sort()
	var sorted := {}
	for world: String in keys:
		sorted[world] = worlds[world]
	if not _write_text(WorldChunks.PATH, JSON.stringify({"format": WorldChunks.FORMAT, "worlds": sorted}, "  ", false) + "\n"):
		return
	print("wrote %s (%s)" % [WorldChunks.PATH, ", ".join(PackedStringArray(keys))])


## "south-wilds-a6" for chunk A6 of south-wilds.
static func chunk_id(world: String, chunk: Vector2i) -> String:
	return "%s-%s" % [world, WorldMapData.chunk_name(chunk).to_lower()]


## The world scene of `chunk` (map chunk coordinates) cut from the region world `source`, whose
## block of chunks is `block`; `chunks` are the region's chunks (the neighbours it joins).
func _chunk_scene(map: WorldMapData, source: Node2D, key: String, world: String, chunk: Vector2i, block: Rect2i, chunks: Array[Vector2i]) -> Node2D:
	var tiles := map.chunk_tiles()
	var tile := float(map.tile_size)
	var origin_tiles := (chunk - block.position) * tiles
	var origin := Vector2(origin_tiles) * tile
	var size := Vector2(tiles) * tile
	var area := Rect2(origin, size)
	var id := chunk_id(world, chunk)
	var root := Node2D.new()
	root.name = id
	root.y_sort_enabled = true
	root.set_meta(RegionScene.REGION_META, key)
	root.set_meta(CHUNK_META, WorldMapData.chunk_name(chunk))
	root.set_meta(CHUNK_OF_META, world)
	if source.has_meta(RegionScene.LAYOUT_META):
		root.set_meta(RegionScene.LAYOUT_META, source.get_meta(RegionScene.LAYOUT_META))
	var own := Rect2i(Vector2i.ZERO, tiles)
	var ground := _copy_layer(source.get_node(^"ground") as TileMapLayer, origin_tiles, own)
	ground.set_meta(&"columns", tiles.x)
	ground.set_meta(&"rows", tiles.y)
	root.add_child(ground)
	root.add_child(_copy_layer(source.get_node(^"forest") as TileMapLayer, origin_tiles, _forest_keep(tiles)))
	var above := Rect2i(0, -Elevation.MAX_ROWS_ABOVE, tiles.x, tiles.y + Elevation.MAX_ROWS_ABOVE)
	root.add_child(_copy_layer(source.get_node(^"elevation") as TileMapLayer, origin_tiles, above))
	var fences := source.get_node_or_null(^"fences") as TileMapLayer
	if fences != null:
		root.add_child(_copy_layer(fences, origin_tiles, own))
	# The spawn: the open cell nearest the middle (the region's own may lie on a chunk's edge).
	var spawn := _open_spot(root, tiles / 2, tiles, tile)
	var entries := {}
	for edge: String in EDGES:
		var dir: Vector2i = EDGES[edge]
		var middle := tiles / 2 + Vector2i(dir.x * (tiles.x / 2 - 2), dir.y * (tiles.y / 2 - 2))
		entries[edge] = _open_spot(root, middle, tiles, tile)
	root.add_child(_definition(id, map.tile_size, tiles, spawn, entries))
	root.add_child(_marker("player-spawn", spawn))
	for edge: String in entries:
		root.add_child(_marker("player-entry-" + edge, entries[edge]))
	var exits: Array[Area2D] = []
	for child in source.get_children():
		if child is Area2D and child.has_node(^"world-exit-script"):
			var shape := (child.get_node(^"CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
			var part := _exit_part(Rect2((child as Area2D).position - shape.size / 2.0, shape.size), area)
			if not part.has_area():
				continue
			var script_node := child.get_node(^"world-exit-script")
			exits.append(_exit(str(child.name), Rect2(part.position - origin, part.size), id,
					str(script_node.get(&"exit_id")), str(script_node.get(&"target_area_id")), str(script_node.get(&"entry")),
					str(script_node.get(&"entry_marker")), false))
		elif child is Node2D and str(child.name).begins_with("arrive-from-") and area.has_point((child as Node2D).position):
			root.add_child(_marker(str(child.name), (child as Node2D).position - origin))
	var to_other_regions := exits.size()
	for edge: String in EDGES:
		var next: Vector2i = chunk + EDGES[edge]
		if not chunks.has(next):
			continue
		var strip: Rect2
		match edge:
			"north":
				strip = Rect2(0.0, 0.0, size.x, EDGE_STRIP)
			"south":
				strip = Rect2(0.0, size.y - EDGE_STRIP, size.x, EDGE_STRIP)
			"west":
				strip = Rect2(0.0, 0.0, EDGE_STRIP, size.y)
			_:
				strip = Rect2(size.x - EDGE_STRIP, 0.0, EDGE_STRIP, size.y)
		var next_id := chunk_id(world, next)
		exits.append(_exit("edge-" + edge, strip, id, "%s-to-%s" % [id, next_id], next_id, OPPOSITE[edge], "", true))
	for exit in exits:
		root.add_child(exit)
	var props := Node2D.new()
	props.name = "props"
	props.y_sort_enabled = true
	root.add_child(props)
	var source_props := source.get_node_or_null(^"props")
	if source_props != null:
		for prop in source_props.get_children():
			if prop is Node2D and not prop.scene_file_path.is_empty() and (area.has_point((prop as Node2D).position)
					or _overlaps(prop as Node2D, (prop as Node2D).position, area)):
				var instance := (load(prop.scene_file_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
				instance.name = prop.name
				instance.position = (prop as Node2D).position - origin
				instance.rotation = (prop as Node2D).rotation
				instance.scale = (prop as Node2D).scale
				props.add_child(instance)
	var notes := Node2D.new()
	notes.name = "notes"
	root.add_child(notes)
	var source_notes := source.get_node_or_null(^"notes")
	if source_notes != null:
		for note in source_notes.get_children():
			if note is Node2D and area.has_point((note as Node2D).position):
				var copy := Node2D.new()
				copy.set_script(note.get_script())
				copy.name = note.name
				copy.position = (note as Node2D).position - origin
				for property: StringName in [&"kind", &"label", &"notes"]:
					copy.set(property, note.get(property))
				notes.add_child(copy)
	RegionScene._own(root, root)
	for exit in exits:
		var script_node := exit.get_node(^"world-exit-script")
		exit.body_entered.connect(Callable(script_node, &"on_body_entered"), Object.CONNECT_PERSIST)
	root.set_meta(&"split_stats", {"props": props.get_child_count(), "exits": to_other_regions,
			"edges": exits.size() - to_other_regions, "spawn": spawn})
	return root


## The part of the exit over `rect` (region units) that chunk `area` gets: the generator puts an
## exit just past the region's border, so one lying within EXIT_PULL outside an edge of `area` is
## moved in against that edge; then what of it lies in `area` (an opening across two chunks is
## split between them). Empty when none.
static func _exit_part(rect: Rect2, area: Rect2) -> Rect2:
	var moved := rect
	if rect.position.y >= area.end.y and rect.position.y - area.end.y <= EXIT_PULL:
		moved.position.y = area.end.y - rect.size.y
	elif rect.end.y <= area.position.y and area.position.y - rect.end.y <= EXIT_PULL:
		moved.position.y = area.position.y
	if rect.position.x >= area.end.x and rect.position.x - area.end.x <= EXIT_PULL:
		moved.position.x = area.end.x - rect.size.x
	elif rect.end.x <= area.position.x and area.position.x - rect.end.x <= EXIT_PULL:
		moved.position.x = area.position.x
	return moved.intersection(area)


## A copy of `layer` with its cells in `keep` (chunk tiles) moved by -`origin` (region tiles).
static func _copy_layer(layer: TileMapLayer, origin: Vector2i, keep: Rect2i) -> TileMapLayer:
	var copy := TileMapLayer.new()
	copy.name = layer.name
	copy.z_index = layer.z_index
	copy.y_sort_enabled = layer.y_sort_enabled
	copy.tile_set = layer.tile_set
	for cell in layer.get_used_cells():
		var at := cell - origin
		if keep.has_point(at):
			copy.set_cell(at, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell))
	copy.set_script(layer.get_script())
	return copy


## The middle of the open cell nearest `target` (chunk tiles): ground that is not solid (deep water,
## rock wall), with no tree, fence or stairs within SPAWN_ROOM cells; `target`'s middle when none is.
static func _open_spot(root: Node2D, target: Vector2i, tiles: Vector2i, tile: float) -> Vector2:
	var ground := root.get_node(^"ground") as TileMapLayer
	var forest := root.get_node(^"forest") as TileMapLayer
	var elevation := root.get_node(^"elevation") as TileMapLayer
	var fences := root.get_node_or_null(^"fences") as TileMapLayer
	for radius in maxi(tiles.x, tiles.y):
		for y in range(target.y - radius, target.y + radius + 1):
			for x in range(target.x - radius, target.x + radius + 1):
				if maxi(absi(x - target.x), absi(y - target.y)) != radius:
					continue
				var at := Vector2i(x, y)
				if x < SPAWN_ROOM or y < SPAWN_ROOM or x >= tiles.x - SPAWN_ROOM or y >= tiles.y - SPAWN_ROOM:
					continue
				if _is_open(at, ground, forest, elevation, fences):
					return (Vector2(at) + Vector2(0.5, 0.5)) * tile
	return (Vector2(target) + Vector2(0.5, 0.5)) * tile


static func _is_open(at: Vector2i, ground: TileMapLayer, forest: TileMapLayer, elevation: TileMapLayer, fences: TileMapLayer) -> bool:
	var data := ground.get_cell_tile_data(at)
	if data == null:
		return false
	if ground.tile_set.has_custom_data_layer_by_name(WorldServiceScript.TILE_ID_DATA_LAYER):
		var tile_id: Variant = data.get_custom_data(WorldServiceScript.TILE_ID_DATA_LAYER)
		if tile_id is String and WorldServiceScript.SOLID_TILE_IDS.has(tile_id):
			return false
	var level: Variant = _level(elevation, at)
	if level == null:
		return false
	for dy in range(-SPAWN_ROOM, SPAWN_ROOM + 1):
		for dx in range(-SPAWN_ROOM, SPAWN_ROOM + 1):
			var near := at + Vector2i(dx, dy)
			if forest.get_cell_source_id(near) >= 0:
				return false
			if fences != null and fences.get_cell_source_id(near) >= 0:
				return false
			if _level(elevation, near) != level:
				return false
	# No higher top's wall hangs over it.
	for dy in range(1, MAX_WALL_ROWS + 1):
		var behind: Variant = _level(elevation, at - Vector2i(0, dy))
		if behind == null or int(behind) > int(level):
			return false
	return true


## The level painted at `at` (0 unpainted), null on stairs or a ramp.
static func _level(elevation: TileMapLayer, at: Vector2i) -> Variant:
	var painted := elevation.get_cell_tile_data(at)
	if painted == null:
		return 0
	if str(painted.get_custom_data(Elevation.KIND_DATA_LAYER)) != "":
		return null
	return int(painted.get_custom_data(Elevation.LEVEL_DATA_LAYER))


static func _definition(id: String, tile_size: int, tiles: Vector2i, spawn: Vector2, entries: Dictionary) -> Node:
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(RegionScene.WORLD_DEFINITION))
	var points := {}
	for edge: String in entries:
		points[edge] = _point(entries[edge])
	definition.set(&"map_id", id)
	definition.set(&"tile_size", tile_size)
	definition.set(&"columns", tiles.x)
	definition.set(&"rows", tiles.y)
	definition.set(&"camera_mode", "follow")
	definition.set(&"metadata", {"objects": [], "player": {"spawn": _point(spawn), "entries": points}})
	return definition


static func _marker(marker_name: String, position: Vector2) -> Node2D:
	var marker := Node2D.new()
	marker.name = marker_name
	marker.y_sort_enabled = true
	marker.position = position
	return marker


## An exit over `rect` (chunk units) as the region worlds have them (region_scene.gd).
static func _exit(exit_name: String, rect: Rect2, map_id: String, exit_id: String, target: String, entry: String, entry_marker: String, keep_along: bool) -> Area2D:
	var area := Area2D.new()
	area.name = exit_name
	area.position = rect.get_center()
	area.collision_layer = RegionScene.EXIT_LAYER
	area.collision_mask = RegionScene.EXIT_MASK
	area.monitorable = false
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	box.size = rect.size
	box.resource_scene_unique_id = "shape_" + exit_name.replace("-", "_")
	shape.shape = box
	area.add_child(shape)
	var script_node := Node.new()
	script_node.name = "world-exit-script"
	script_node.set_script(load(RegionScene.WORLD_EXIT))
	script_node.set(&"map_id", map_id)
	script_node.set(&"exit_id", exit_id)
	script_node.set(&"target_area_id", target)
	script_node.set(&"entry", entry)
	script_node.set(&"entry_marker", entry_marker)
	script_node.set(&"keep_along", keep_along)
	script_node.set(&"area", area)
	script_node.set(&"gate", {})
	area.add_child(script_node)
	return area


static func _point(position: Vector2) -> Dictionary:
	return {"x": roundi(position.x), "y": roundi(position.y)}


## Adds "world.<id>" -> the chunk scene to scene_index.json for every id it lacks, after the other
## world lines in order, keeping the rest of the file as it is.
func _register_scenes(ids: PackedStringArray) -> void:
	var text := FileAccess.get_file_as_string(SCENE_INDEX)
	if text.is_empty():
		push_error("split_region_chunks: cannot read %s" % SCENE_INDEX)
		return
	var lines := text.split("\n")
	var changed := false
	for chunk in ids:
		var id := "world." + chunk
		if text.contains("\"%s\":" % id):
			continue
		var entry := "  \"%s\": \"%s%s.tscn\"" % [id, CHUNKS_DIR, chunk]
		var at := -1
		var before := -1
		for i in lines.size():
			if lines[i].begins_with("  \"world."):
				at = i
				if lines[i].trim_prefix("  \"").get_slice("\"", 0) > id:
					before = i
					break
		if at < 0:
			push_error("split_region_chunks: no world lines in %s" % SCENE_INDEX)
			return
		if before >= 0:
			lines.insert(before, entry + ",")
		elif lines[at].ends_with(","):
			lines.insert(at + 1, entry + ",")
		else:
			# After the last entry of the file.
			lines[at] += ","
			lines.insert(at + 1, entry)
		text = "\n".join(lines)
		changed = true
	if not changed:
		return
	if not JSON.parse_string(text) is Dictionary:
		push_error("split_region_chunks: %s would not parse; not written" % SCENE_INDEX)
		return
	if not _write_text(SCENE_INDEX, text):
		return
	print("registered %d chunk worlds in %s" % [ids.size(), SCENE_INDEX])


## Keeps the chunks of the placeholder regions out of the release preset (`chunks/<world>-*`; the
## "Web (dev)" preset keeps every world); the chunks of hand-made worlds ship.
func _exclude_from_release(map: WorldMapData) -> void:
	WorldChunks.reload()
	var wanted := PackedStringArray()
	for world: String in WorldChunks.table():
		if bool(map.region_for_map(world).get("placeholder", false)):
			wanted.append(CHUNKS_DIR.trim_prefix("res://") + world + "-*")
	var text := FileAccess.get_file_as_string(EXPORT_PRESETS)
	var lines := text.split("
")
	var in_release := false
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.begins_with("["):
			in_release = false
		elif line == "name=\"%s\"" % RELEASE_PRESET:
			in_release = true
		elif in_release and line.begins_with("exclude_filter=\""):
			var filters := line.trim_prefix("exclude_filter=\"").trim_suffix("\"").split(",", false)
			var kept := PackedStringArray()
			for filter in filters:
				# The whole folder (before hand-made worlds were cut) and old per-world filters go.
				if not filter.begins_with(CHUNKS_DIR.trim_prefix("res://")):
					kept.append(filter)
			kept.append_array(wanted)
			if kept == filters:
				return
			lines[i] = lines[i].replace(line, "exclude_filter=\"%s\"" % ",".join(kept))
			if _write_text(EXPORT_PRESETS, "
".join(lines)):
				print("release preset: excluded the chunks of %d placeholder worlds" % wanted.size())
			return
	push_error("split_region_chunks: no \"%s\" preset exclude_filter in %s" % [RELEASE_PRESET, EXPORT_PRESETS])


## Writes `text` to `path`, trying again for a while (an open editor may hold the file for a
## moment). True when written.
func _write_text(path: String, text: String) -> bool:
	for attempt in WRITE_ATTEMPTS:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
			return true
		OS.delay_msec(WRITE_RETRY_MS)
	push_error("split_region_chunks: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
	return false


# --- hand-made worlds -------------------------------------------------------------------------

## The chunk worlds of a hand-made world (owner, 2026-10-12: "full cut, carefully"): any layout of
## nodes. Each chunk is the whole scene instanced again (with its edit state, so overrides inside
## instances survive) with what lies outside the chunk taken away (`_prune`): a group whose nodes
## all lie in one chunk stays whole there (scripts in it keep their node paths); a group across
## chunks is split node by node. Nodes with no place (the definition, music, scripts) go in every
## chunk. Exits are clipped to the chunk (`_exit_part`); every `map_id` naming the world names the
## chunk; doors are listed for travel back from interiors. Returns the world's table entry, {} when
## it failed.
func _split_hand_made(map: WorldMapData, entry: Dictionary, ids: PackedStringArray) -> Dictionary:
	var key := str(entry["key"])
	var world := str(entry["world"])
	var path := WORLDS_DIR + world + ".tscn"
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("split_region_chunks: no world scene for '%s'" % world)
		return {}
	var probe := packed.instantiate() as Node2D
	var definition := probe.get_node_or_null(^"world-definition")
	if definition == null:
		push_error("split_region_chunks: %s has no world-definition" % path)
		probe.free()
		return {}
	var tile := int(definition.get(&"tile_size"))
	var world_rect := Rect2(Vector2.ZERO, Vector2(int(definition.get(&"columns")), int(definition.get(&"rows"))) * tile)
	probe.free()
	var chunks := map.region_chunks(key)
	var block := map.region_chunk_rect(key)
	var size := map.chunk_units()
	var names := {}
	var arrivals := {}
	var doors := {}
	var written := {}
	var spawn := ""
	var before: Dictionary = (_written.get(world, {}) as Dictionary).get("written", {})
	var failed := false
	var cut_chunks: Array[Vector2i] = []
	for chunk in chunks:
		if Rect2(Vector2(chunk - block.position) * size, size).intersection(world_rect).has_area():
			cut_chunks.append(chunk)
	for chunk in cut_chunks:
		var id := chunk_id(world, chunk)
		var out_path := CHUNKS_DIR + id + ".tscn"
		var area := Rect2(Vector2(chunk - block.position) * size, size).intersection(world_rect)
		ids.append(id)
		names[id] = WorldMapData.chunk_name(chunk)
		if not _force and FileAccess.file_exists(out_path) and before.has(id) and FileAccess.get_file_as_string(out_path).hash() != int(before[id]):
			print("kept %s: edited since it was cut (-- --force rewrites it)" % out_path)
			written[id] = int(before[id])
			# Its places still count for travel.
			var kept := (load(out_path) as PackedScene).instantiate()
			_list_places(kept, id, arrivals, doors)
			if kept.has_node(^"player-spawn") and spawn.is_empty() and kept.has_meta(&"world_map_region_spawn"):
				spawn = id
			kept.free()
			continue
		var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		var notes := PackedStringArray()
		var had_spawn := _place_in_world(root.get_node_or_null(^"player-spawn"))
		_prune(root, area, Vector2.ZERO, notes)
		for name in _drop_broken_scripts(root):
			notes.append("dropped %s: what it points at is in another chunk" % name)
		var has_spawn := root.has_node(^"player-spawn")
		if has_spawn and had_spawn != Vector2.INF:
			spawn = id
			root.set_meta(&"world_map_region_spawn", true)
		for child in root.get_children():
			if child is TileMapLayer:
				_clip_layer(child as TileMapLayer, area, tile)
			elif child is Node2D:
				(child as Node2D).position -= area.position
		_rename_map_id(root, world, id)
		root.name = id
		root.set_meta(RegionScene.REGION_META, key)
		root.set_meta(CHUNK_META, WorldMapData.chunk_name(chunk))
		root.set_meta(CHUNK_OF_META, world)
		var tiles := Vector2i((area.size / tile).round())
		var ground := root.get_node_or_null(^"ground") as TileMapLayer
		if ground != null:
			ground.set_meta(&"columns", tiles.x)
			ground.set_meta(&"rows", tiles.y)
		var chunk_definition := root.get_node(^"world-definition")
		chunk_definition.set(&"map_id", id)
		chunk_definition.set(&"columns", tiles.x)
		chunk_definition.set(&"rows", tiles.y)
		if not has_spawn:
			var at := _spawn_spot(root, area.size)
			root.add_child(_marker("player-spawn", at))
		var spawn_at := (root.get_node(^"player-spawn") as Node2D).position
		var meta: Dictionary = chunk_definition.get(&"metadata")
		meta = meta.duplicate(true)
		var player: Dictionary = meta.get("player", {})
		player["spawn"] = _point(spawn_at)
		player["entries"] = {}
		meta["player"] = player
		chunk_definition.set(&"metadata", meta)
		# The whole edges this chunk shares with the region's other chunks.
		var edges: Array[Area2D] = []
		for edge: String in EDGES:
			var next: Vector2i = chunk + EDGES[edge]
			if not cut_chunks.has(next):
				continue
			var strip: Rect2
			match edge:
				"north":
					strip = Rect2(0.0, 0.0, area.size.x, EDGE_STRIP)
				"south":
					strip = Rect2(0.0, area.size.y - EDGE_STRIP, area.size.x, EDGE_STRIP)
				"west":
					strip = Rect2(0.0, 0.0, EDGE_STRIP, area.size.y)
				_:
					strip = Rect2(area.size.x - EDGE_STRIP, 0.0, EDGE_STRIP, area.size.y)
			var next_id := chunk_id(world, next)
			var exit := _exit("edge-" + edge, strip, id, "%s-to-%s" % [id, next_id], next_id, OPPOSITE[edge], "", true)
			root.add_child(exit)
			edges.append(exit)
		RegionScene._own(root, root)
		for exit in edges:
			exit.body_entered.connect(Callable(exit.get_node(^"world-exit-script"), &"on_body_entered"), Object.CONNECT_PERSIST)
		_list_places(root, id, arrivals, doors)
		var err := RegionScene.save(root, out_path)
		failed = failed or err != OK
		if err == OK:
			written[id] = FileAccess.get_file_as_string(out_path).hash()
		print("%s %s (%d x %d tiles)%s" % ["wrote" if err == OK else "FAILED (%d)" % err, out_path, tiles.x, tiles.y,
				"" if notes.is_empty() else "\n    " + "\n    ".join(notes)])
	if spawn.is_empty() and not names.is_empty():
		spawn = names.keys()[0]
	return {} if failed else {"chunks": names, "arrivals": arrivals, "doors": doors, "spawn": spawn, "written": written}


## Takes away what of `node`'s children lies outside `area` (world units; `offset` is `node`'s place
## in the world), as `_split_hand_made` says. Notes what it split that may need a look.
func _prune(node: Node, area: Rect2, offset: Vector2, notes: PackedStringArray) -> void:
	for child: Node in node.get_children():
		if child is TileMapLayer or not child is Node2D:
			continue
		var at := offset + (child as Node2D).position
		if _exit_script(child) != null:
			_clip_exit(child as Area2D, at, area)
			continue
		if _is_group(child):
			var spots := PackedVector2Array()
			_spots(child, at, spots)
			var inside := 0
			for spot in spots:
				if area.has_point(spot):
					inside += 1
			if inside == spots.size() and inside > 0:
				continue
			var scripted := false
			for part: Node in child.get_children():
				scripted = scripted or (not part is Node2D and part.get_script() != null)
			# A group with scripts (their node paths) is never copied in part into another chunk.
			if inside == 0 and scripted:
				child.free()
				continue
			if inside > 0 and scripted:
				notes.append("%s is split across chunks but has script nodes: check it" % child.name)
			_prune(child, area, at, notes)
			var left := 0
			for part: Node in child.get_children():
				left += 1 if part is Node2D else 0
			if left == 0:
				child.free()
		elif not area.has_point(at) and not _overlaps(child as Node2D, at, area) \
				and not (str(node.name) == "Scenery" and _picture_overlaps(child as Node2D, at, area)):
			child.free()


## A group: a plain Node2D of this scene (not an instance, no script) holding nodes.
static func _is_group(node: Node) -> bool:
	return node.scene_file_path.is_empty() and node.get_script() == null and node.get_child_count() > 0 \
			and node.get_class() == "Node2D"


## The places (world units) of the nodes in group `node` (at `at`): its Node2D children and their
## groups' nodes; an instance or a scripted node is one place.
static func _spots(node: Node, at: Vector2, out: PackedVector2Array) -> void:
	for child: Node in node.get_children():
		if not child is Node2D:
			continue
		var place := at + (child as Node2D).position
		if _is_group(child):
			_spots(child, place, out)
		else:
			out.append(place)


## The world_exit.gd node of an exit Area2D, null for anything else.
static func _exit_script(node: Node) -> Node:
	if not node is Area2D:
		return null
	for child: Node in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path == RegionScene.WORLD_EXIT:
			return child
	return null


## Clips the exit Area2D `area_node` (at `at` in the world) to the chunk `area` (`_exit_part`), or
## frees it when none of it is the chunk's.
static func _clip_exit(area_node: Area2D, at: Vector2, area: Rect2) -> void:
	var shape_node: CollisionShape2D = null
	for child: Node in area_node.get_children():
		if child is CollisionShape2D:
			shape_node = child
	var box := shape_node.shape as RectangleShape2D if shape_node != null else null
	if box == null:
		if not area.has_point(at):
			area_node.free()
		return
	var rect := Rect2(at + shape_node.position - box.size / 2.0, box.size)
	var part := _exit_part(rect, area)
	if not part.has_area():
		area_node.free()
		return
	var clipped := RectangleShape2D.new()
	clipped.size = part.size
	shape_node.shape = clipped
	shape_node.position = Vector2.ZERO
	area_node.position += part.get_center() - at


## Keeps `layer`'s cells in `area` (world units), moved to the chunk's corner, each layer on its own
## cell size: an elevation layer also MAX_ROWS_ABOVE rows above it, a ForestLayer FOREST_MARGIN past
## its edges (canopies), a PropLayer every cell whose prop's picture reaches into the chunk (props
## draw well past their cell), a WallLayer one cell past every edge with `shown_cells` the chunk's
## own (the margin only shapes the joins at the edge).
static func _clip_layer(layer: TileMapLayer, area: Rect2, tile: int) -> void:
	var size := Vector2(layer.tile_set.tile_size) if layer.tile_set != null else Vector2(tile, tile)
	var origin := Vector2i((area.position / size).round())
	var tiles := Vector2i((area.size / size).round())
	var script := layer.get_script() as Script
	var script_path := script.resource_path if script != null else ""
	var keep := Rect2i(Vector2i.ZERO, tiles)
	var props := script_path.ends_with("prop_layer.gd")
	if script_path.ends_with("elevation_layer.gd"):
		keep = Rect2i(0, -Elevation.MAX_ROWS_ABOVE, tiles.x, tiles.y + Elevation.MAX_ROWS_ABOVE)
	elif script_path.ends_with("forest_layer.gd"):
		keep = _forest_keep(tiles)
	elif script_path.ends_with("wall_layer.gd"):
		keep = Rect2i(-1, -1, tiles.x + 2, tiles.y + 2)
	var cells := []
	for cell in layer.get_used_cells():
		var at := cell - origin
		if keep.has_point(at) or (props and _prop_reaches(layer, cell, area)):
			cells.append([at, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)])
	layer.clear()
	for cell: Array in cells:
		layer.set_cell(cell[0], cell[1], cell[2], cell[3])
	if script_path.ends_with("wall_layer.gd"):
		layer.set(&"shown_cells", Rect2i(Vector2i.ZERO, tiles))


## Each painted prop tile's picture box around its cell's corner (`_prop_reaches`), read once.
static var _prop_boxes := {}


## True when the prop painted at `cell` of PropLayer `layer` shows inside `area` (layer space).
static func _prop_reaches(layer: TileMapLayer, cell: Vector2i, area: Rect2) -> bool:
	var corner := Vector2(cell) * Vector2(layer.tile_set.tile_size)
	var key := [layer.tile_set.resource_path, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell),
			layer.get_cell_alternative_tile(cell), cell.x % 2]
	if not _prop_boxes.has(key):
		var box := Rect2()
		var prop: Dictionary = layer.call(&"prop_at", cell)
		if not prop.is_empty():
			var node := PropLayerScript.make_prop(prop)
			if node != null:
				box = PropPictures.bounds(node, Transform2D.IDENTITY)
				box.position -= corner
				node.free()
		_prop_boxes[key] = box
	var reach: Rect2 = _prop_boxes[key]
	return reach.has_area() and Rect2(reach.position + corner, reach.size).intersects(area)


## Every `map_id` under `node` (instances' insides too) that names `world` names `chunk` instead; a
## node inside an instance (a boss camp's script) has its instances made editable in `root` so the
## chunk scene saves the new value.
static func _rename_map_id(node: Node, world: String, chunk: String, root: Node = null) -> void:
	if root == null:
		root = node
	var value: Variant = node.get(&"map_id")
	if value is String and value == world:
		node.set(&"map_id", chunk)
		var instance := node.owner
		while instance != null and instance != root:
			root.set_editable_instance(instance, true)
			instance = instance.owner
	for child: Node in node.get_children():
		_rename_map_id(child, world, chunk, root)


## The places travel arrives at in chunk world `root` (`id`): its arrival markers and its doors.
static func _list_places(root: Node, id: String, arrivals: Dictionary, doors: Dictionary) -> void:
	for node: Node in root.find_children("*", "", true, false):
		if node is Node2D and _is_arrival(str(node.name)):
			arrivals[str(node.name)] = id
		var door_id: Variant = node.get(&"door_id")
		var script := node.get_script() as Script
		if door_id is String and door_id != "" and script != null and script.resource_path.ends_with("/door.gd"):
			doors[door_id] = id


## `node`'s place in the world (its and its parents' positions), INF when it is null.
static func _place_in_world(node: Node) -> Vector2:
	if node == null:
		return Vector2.INF
	var at := Vector2.ZERO
	var current := node
	while current != null and current.get_parent() != null:
		if current is Node2D:
			at += (current as Node2D).position
		current = current.get_parent()
	return at


## A spawn for a chunk without the world's: an arrival marker or a door's arrival in it, else its
## middle (the game moves it off solid tiles).
static func _spawn_spot(root: Node, size: Vector2) -> Vector2:
	for node: Node in root.find_children("*", "Node2D", true, false):
		var node_name := str(node.name)
		if _is_arrival(node_name) or node_name == "arrival":
			var at := _place_in_world(node)
			if Rect2(Vector2.ZERO, size).grow(-64.0).has_point(at):
				return at
	return size / 2.0


# --- scenery across chunk edges ----------------------------------------------------------------

## The forest cells a chunk of `tiles` keeps (chunk tiles): its own and FOREST_MARGIN past its edges.
static func _forest_keep(tiles: Vector2i) -> Rect2i:
	return Rect2i(-FOREST_MARGIN[0], -FOREST_MARGIN[1], tiles.x + FOREST_MARGIN[0] + FOREST_MARGIN[2],
			tiles.y + FOREST_MARGIN[1] + FOREST_MARGIN[3])


## True when `node` (at `at` in the world) is scenery (SCENERY) whose picture or collision reaches
## into `area`.
static func _overlaps(node: Node2D, at: Vector2, area: Rect2) -> bool:
	if node == null or node.scene_file_path.is_empty():
		return false
	var file := node.scene_file_path.get_file()
	var scenery := false
	for prefix in SCENERY:
		scenery = scenery or file.begins_with(prefix)
	if not scenery:
		return false
	var reach := _reach(node.scene_file_path)
	if not reach.has_area():
		return false
	return (Transform2D(node.rotation, node.scale, node.skew, at) * reach).intersects(area)


## The box around its origin that scene `path` draws or collides in: its sprites and collision
## shapes (read once).
static func _reach(path: String) -> Rect2:
	if _reaches.has(path):
		return _reaches[path]
	var reach := Rect2()
	var packed := load(path) as PackedScene
	if packed != null:
		var instance := packed.instantiate()
		reach = _bounds(instance, Transform2D.IDENTITY, Rect2())
		instance.free()
	_reaches[path] = reach
	return reach


static func _bounds(node: Node, transform: Transform2D, box: Rect2) -> Rect2:
	var here := transform
	if node is Node2D:
		here = transform * (node as Node2D).transform
	var rect := Rect2()
	if node is Sprite2D:
		rect = (node as Sprite2D).get_rect()
	elif node is CollisionShape2D and (node as CollisionShape2D).shape != null:
		rect = (node as CollisionShape2D).shape.get_rect()
	elif node is CollisionPolygon2D and not (node as CollisionPolygon2D).polygon.is_empty():
		var polygon := (node as CollisionPolygon2D).polygon
		rect = Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			rect = rect.expand(point)
	if rect.has_area():
		var placed := here * rect
		box = placed if not box.has_area() else box.merge(placed)
	for child: Node in node.get_children():
		box = _bounds(child, here, box)
	return box


## True when `node` (a prop dragged in from the Scenery dock, at `at` in the world) draws inside
## `area`.
static func _picture_overlaps(node: Node2D, at: Vector2, area: Rect2) -> bool:
	if node.scene_file_path.is_empty():
		return false
	var box := PropPictures.bounds(node, Transform2D(node.rotation, node.scale, node.skew, at) * node.transform.affine_inverse())
	return box.intersects(area)


## Frees the script nodes under `root` (outside instances) whose node references point at nodes
## the cut took away (a story variant whose villagers live in another chunk); returns their names.
static func _drop_broken_scripts(root: Node) -> PackedStringArray:
	var dropped := PackedStringArray()
	for node: Node in root.find_children("*", "", true, true):
		if node is Node2D or node.get_script() == null or not is_instance_valid(node):
			continue
		for property: Dictionary in node.get_property_list():
			if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var value: Variant = node.get(property["name"])
			var broken: bool = (value is NodePath and not (value as NodePath).is_empty() and not node.has_node(value)) \
					or (typeof(value) == TYPE_OBJECT and not is_instance_valid(value))
			if broken:
				dropped.append(str(node.name))
				node.free()
				break
	return dropped
