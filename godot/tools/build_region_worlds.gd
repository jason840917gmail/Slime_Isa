extends SceneTree
## Builds the placeholder region worlds of the world map (res://game/data/world-map.json, read
## through game/world/atlas/world_map_data.gd): every region marked `"placeholder": true` becomes
## a walkable world scene, res://game/scenes/worlds/<world>.tscn (scene id world.<world>), from the
## sketch's terrain, elevation and markers. The whole map is planned at once so both sides of every
## border agree (tools/region_worlds/region_plan.gd): touching regions meet only at one opening per
## stretch of shared border, written to the map's "passages"; each world is walled by trees along
## its outline except there, roads join its openings and landmarks, with stairs and bridges, and
## no drop leads where there is no way back (tools/region_worlds/region_canvas.gd), and exits lead
## through the openings into the neighbours' worlds (tools/region_worlds/region_scene.gd). Run from
## the repo:
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_region_worlds.gd [-- --only=<region key or world id>,...] [--force] [--dry-run]
## --only builds those regions (the plan and the passages stay the whole map's); --dry-run prints
## the summary and writes nothing. It never touches a region whose `placeholder` is false, and it
## does not overwrite a scene whose root lacks the metadata world_map_placeholder = true (a world
## someone took over) unless given --force. It also adds world.<world> to scene_index.json and the
## scene to the release "Web" export preset's exclude_filter. It prints, per world, the pockets it
## closed, then what each hand-made world needs at its openings, then every warning again (an
## opening no road joins after a layout change, a pocket it could not close): check those.

const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const RegionPlan := preload("res://tools/region_worlds/region_plan.gd")
const RegionCanvas := preload("res://tools/region_worlds/region_canvas.gd")
const RegionScene := preload("res://tools/region_worlds/region_scene.gd")

const WORLDS_DIR := "res://game/scenes/worlds/"
const SCENE_INDEX := "res://game/scenes/scene_index.json"
const EXPORT_PRESETS := "res://export_presets.cfg"
const RELEASE_PRESET := "Web"
const WRITE_ATTEMPTS := 5
const WRITE_RETRY_MS := 400


func _initialize() -> void:
	var only := PackedStringArray()
	var force := false
	var dry_run := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
		elif arg == "--force":
			force = true
		elif arg == "--dry-run":
			dry_run = true
	var map := WorldMapData.load_file()
	if map == null:
		quit(1)
		return
	var plan := RegionPlan.create(map)
	var canvases := {}
	for entry: Dictionary in map.regions():
		var key := str(entry.get("key", ""))
		if bool(entry.get("placeholder", false)) and str(entry.get("world", "")) != "" and map.region_chunk_rect(key).has_area():
			var canvas := RegionCanvas.new(plan, key)
			canvas.build()
			canvases[key] = canvas
	for key: String in canvases:
		(canvases[key] as RegionCanvas).backdrop(canvases)
	var warnings := PackedStringArray()
	for warning in plan.warnings:
		print("  ! ", warning)
		warnings.append(warning)
	var layout_hash := map.layout_hash()
	var failed := false
	for key: String in canvases:
		var canvas: RegionCanvas = canvases[key]
		if not only.is_empty() and not only.has(key) and not only.has(canvas.world):
			continue
		var stats := canvas.stats()
		print("%s (%s): %d x %d tiles, %d own tiles, %d trees, %d openings, %d exits, %d stairs, %d bridges, %d props" % [
				canvas.world, key, stats["size"].x, stats["size"].y, stats["tiles"], stats["trees"],
				stats["openings"], stats["exits"], stats["stairs"], stats["bridges"], stats["props"]])
		print("  pockets with no way back: %d found, %d left (%d joined by road, %d cells levelled, %d tiles fenced)" % [
				stats["pockets_found"], stats["pockets_left"], stats["pocket_roads"], stats["levelled_cells"], stats["fenced_tiles"]])
		for warning in canvas.warnings:
			print("  ! ", warning)
			warnings.append("%s: %s" % [canvas.world, warning])
		if dry_run:
			continue
		var path := WORLDS_DIR + canvas.world + ".tscn"
		if not force and not _is_placeholder_scene(path):
			print("  not written: %s exists and is not a placeholder (add -- --force to replace it)" % path)
			continue
		var err := RegionScene.save(RegionScene.build(canvas, layout_hash), path)
		print("  ", "wrote " + path if err == OK else "FAILED to write %s (%d)" % [path, err])
		failed = failed or err != OK
	_print_real_openings(plan)
	if not warnings.is_empty():
		print("WARNINGS (%d): check these before using the worlds:" % warnings.size())
		for warning in warnings:
			print("  ! ", warning)
	if not dry_run:
		var worlds := PackedStringArray()
		for key: String in canvases:
			var world: String = (canvases[key] as RegionCanvas).world
			if FileAccess.file_exists(WORLDS_DIR + world + ".tscn"):
				worlds.append(world)
		worlds.sort()
		_register_scenes(worlds)
		_exclude_from_release(worlds)
		_write_passages(plan, layout_hash)
	quit(1 if failed else 0)


## True when `path` is free or holds a scene this tool made (its root has world_map_placeholder).
func _is_placeholder_scene(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return false
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == StringName("metadata/%s" % RegionScene.PLACEHOLDER_META):
			return bool(state.get_node_property_value(0, i))
	return false


## The openings on built worlds' edges: what such a world needs for its side of the opening (the
## placeholder's exit already arrives at the marker named there; until the built world has it, the
## travel falls back to its `player-entry-<edge>` marker or its spawn, and the way is one-way).
func _print_real_openings(plan: RegionPlan) -> void:
	print("openings on hand-made worlds (block tiles and units; one-way until the hand-made world has its exit and marker there):")
	for opening in plan.openings:
		for side: String in [opening["a"], opening["b"]]:
			var entry := plan.map.region(side)
			if bool(entry.get("placeholder", false)):
				continue
			var other: String = opening["b"] if side == opening["a"] else opening["a"]
			var other_entry := plan.map.region(other)
			var place := RegionCanvas.opening_place(plan, opening, side)
			var tiles: Rect2i = place["tiles"]
			var edge: String = place["edge"]
			var line := "  %s %s edge (tiles x %d-%d, y %d-%d), to %s (%s%s)" % [entry.get("world", ""), edge,
					tiles.position.x, tiles.end.x - 1, tiles.position.y, tiles.end.y - 1, other_entry.get("world", ""),
					opening["kind"], ": " + str(opening["label"]) if str(opening["label"]) != "" else ""]
			if bool(other_entry.get("placeholder", false)):
				var arrive: Vector2 = place["arrive"]
				line += ": an exit with target_area_id \"%s\", entry \"%s\", entry_marker \"arrive-from-%s-%d\"; a marker \"arrive-from-%s-%d\" at (%d, %d)" % [
						other_entry.get("world", ""), RegionCanvas.OPPOSITE_EDGES[edge], entry.get("world", ""), int(opening["index"]),
						other_entry.get("world", ""), int(opening["index"]), roundi(arrive.x), roundi(arrive.y)]
			elif side != opening["a"]:
				continue
			else:
				line += ": both worlds are built"
			print(line)


## Adds "world.<world>" to scene_index.json for every world in `worlds` it lacks, in order among the
## world lines, keeping the rest of the file as it is.
func _register_scenes(worlds: PackedStringArray) -> void:
	var text := FileAccess.get_file_as_string(SCENE_INDEX)
	if text.is_empty():
		push_error("build_region_worlds: cannot read %s" % SCENE_INDEX)
		return
	var lines := text.split("\n")
	var changed := false
	for world in worlds:
		var id := "world." + world
		if text.contains("\"%s\":" % id):
			continue
		var entry := "  \"%s\": \"%s%s.tscn\"" % [id, WORLDS_DIR, world]
		var last := -1
		var before := -1
		for i in lines.size():
			if lines[i].begins_with("  \"world."):
				last = i
				if before < 0 and lines[i].trim_prefix("  \"").get_slice("\"", 0) > id:
					before = i
		if before >= 0:
			lines.insert(before, entry + ",")
		elif last >= 0:
			if not lines[last].ends_with(","):
				lines[last] += ","
				entry += "" if lines[last + 1].strip_edges() == "}" else ","
			else:
				entry += ","
			lines.insert(last + 1, entry)
		else:
			push_error("build_region_worlds: no world lines in %s" % SCENE_INDEX)
			return
		text = "\n".join(lines)
		changed = true
	if not changed:
		return
	if not JSON.parse_string(text) is Dictionary:
		push_error("build_region_worlds: %s would not parse; not written" % SCENE_INDEX)
		return
	if _write_text(SCENE_INDEX, text):
		print("registered the worlds in ", SCENE_INDEX)


## Appends the worlds' scenes to the release preset's exclude_filter (the "Web (dev)" preset keeps
## every world).
func _exclude_from_release(worlds: PackedStringArray) -> void:
	var text := FileAccess.get_file_as_string(EXPORT_PRESETS)
	if text.is_empty():
		push_error("build_region_worlds: cannot read %s" % EXPORT_PRESETS)
		return
	var lines := text.split("\n")
	var in_release := false
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.begins_with("["):
			in_release = false
		elif line == "name=\"%s\"" % RELEASE_PRESET:
			in_release = true
		elif in_release and line.begins_with("exclude_filter=\""):
			var value := line.trim_prefix("exclude_filter=\"").trim_suffix("\"")
			var filters := value.split(",", false)
			var added := false
			for world in worlds:
				var scene := WORLDS_DIR.trim_prefix("res://") + world + ".tscn"
				if not filters.has(scene):
					filters.append(scene)
					added = true
			if not added:
				return
			lines[i] = lines[i].replace(line, "exclude_filter=\"%s\"" % ",".join(filters))
			if _write_text(EXPORT_PRESETS, "\n".join(lines)):
				print("excluded the worlds from the \"%s\" preset in %s" % [RELEASE_PRESET, EXPORT_PRESETS])
			return
	push_error("build_region_worlds: no \"%s\" preset exclude_filter in %s" % [RELEASE_PRESET, EXPORT_PRESETS])


## Writes the plan's passages into the map file (read again now, so only "passages" changes),
## unless the layout changed since it was read.
func _write_passages(plan: RegionPlan, layout_hash: int) -> void:
	var fresh := WorldMapData.load_file()
	if fresh == null:
		return
	if fresh.layout_hash() != layout_hash:
		push_warning("build_region_worlds: world-map.json changed while building; passages not written (run again)")
		return
	var passages := plan.passages()
	if JSON.stringify(fresh.to_dictionary()["passages"]) == JSON.stringify(passages):
		return
	fresh.head["passages"] = passages
	if fresh.save_file() == OK:
		print("wrote %d passages to %s" % [passages.size(), fresh.path])


## Writes `text` to `path` (a few tries: an open editor may hold the file for a moment). True when
## written.
func _write_text(path: String, text: String) -> bool:
	for attempt in WRITE_ATTEMPTS:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
			return true
		OS.delay_msec(WRITE_RETRY_MS)
	push_error("build_region_worlds: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
	return false
