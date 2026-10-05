extends SceneTree
## Verifies the scene converter's output (scripts/godot/convert-scenes.mjs).
##
## Run headless from the repository root:
##   "<godot console exe>" --headless --path godot -s res://tools/verify_generated.gd
##
## 1. Loads and instantiates every scene in res://generated/scene_index.json
##    and compares its node count with `expectedTreeNodes` from
##    res://generated/conversion_report.json (instanced subtrees included).
##    Every property the .tscn sets must exist on its node and keep its value,
##    and every Node-typed export must resolve (Godot skips both silently).
## 2. Checks every TileMapLayer cell against the source scene JSON: cell count,
##    tile id (TileSet custom data), atlas coords and texture, using Phaser's
##    frame selection (tile hash, sheet-wrap) re-implemented here.
## 3. Adds level-1, the player slime, a worm swordsman and the basic sword to
##    the tree for a few frames and checks the tiles again in the tree.
##
## Engine errors and warnings are captured with a Logger. Those raised in
## hand-written gameplay scripts (res://game/ outside res://game/runtime/)
## belong to their authors and are listed as "foreign" without failing the
## run; every other error or warning while a scene loads or plays fails it.
## Exits 1 on any failure.
##
## Owner: converter builder.

const INDEX_PATH := "res://generated/scene_index.json"
const REPORT_PATH := "res://generated/conversion_report.json"
const AUTHORED_DIR := "../src/game/content/scenes/authored/"
const TILE_SET_JSON := "../src/game/content/scenes/authored/resources/terrain/terrain.tile-set.resource.json"
const ASSETS_JSON := "../asset/assets.json"
const PLAY_SCENE_ID := "world.level-1"
const PLAY_ACTORS := ["character.player-slime", "character.worm-swordsman", "weapon.basic-sword"]
const PLAY_FRAMES := 30


## Records engine errors and warnings (thread-safe; the engine may log from any thread).
class ErrorCollector extends Logger:
	var _mutex := Mutex.new()
	var _entries: Array[Dictionary] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var frames := PackedStringArray()
		for backtrace in script_backtraces:
			for index in backtrace.get_frame_count():
				frames.append("%s:%d" % [backtrace.get_frame_file(index), backtrace.get_frame_line(index)])
		var message := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_entries.append({
			"warning": error_type == ERROR_TYPE_WARNING,
			"message": message,
			"where": "%s:%d (%s)" % [file, line, function],
			"frames": frames,
		})
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[Dictionary]:
		_mutex.lock()
		var taken := _entries.duplicate()
		_entries.clear()
		_mutex.unlock()
		return taken


var _collector: ErrorCollector
var _failures := PackedStringArray()
var _foreign := PackedStringArray()
var _tile_set_json: Dictionary = {}
var _assets_json: Dictionary = {}
var _report: Dictionary = {}
var _play_root: Node
var _frames := 0
var _finished := false


func _initialize() -> void:
	_collector = ErrorCollector.new()
	OS.add_logger(_collector)
	var index := _read_json(INDEX_PATH)
	_report = _read_json(REPORT_PATH)
	_tile_set_json = _read_json(_repo_path(TILE_SET_JSON))
	_assets_json = _read_json(_repo_path(ASSETS_JSON))
	if index.is_empty() or _report.is_empty():
		_failures.append("missing %s or %s; run pnpm godot:convert" % [INDEX_PATH, REPORT_PATH])
		_finish()
		return
	_check_all_scenes(index)
	_start_play(index)


func _process(_delta: float) -> bool:
	if _finished:
		return true
	if _play_root == null:
		_finish()
		return true
	_frames += 1
	if _frames < PLAY_FRAMES:
		return false
	_drain("play %s" % PLAY_SCENE_ID)
	print("verify_generated: %s played %d frames in the tree (%d nodes, actors: %s)" % [
		PLAY_SCENE_ID, _frames, _count_nodes(_play_root), ", ".join(PLAY_ACTORS)])
	_check_tiles(_play_root, PLAY_SCENE_ID, "in tree")
	_drain("play %s" % PLAY_SCENE_ID)
	_finish()
	return true


func _check_all_scenes(index: Dictionary) -> void:
	var scene_reports: Dictionary = _report.get("scenes", {})
	var ids := index.keys()
	ids.sort()
	var total_nodes := 0
	for scene_id: String in ids:
		var path: String = index[scene_id]
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			_drain(scene_id)
			_failures.append("%s: %s did not load" % [scene_id, path])
			continue
		var instance := packed.instantiate()
		if instance == null:
			_drain(scene_id)
			_failures.append("%s: %s did not instantiate" % [scene_id, path])
			continue
		var count := _count_nodes(instance)
		total_nodes += count
		var expected := int((scene_reports.get(scene_id, {}) as Dictionary).get("expectedTreeNodes", -1))
		if count != expected:
			_failures.append("%s: %d nodes, expected %d" % [scene_id, count, expected])
		_check_properties(packed.get_state(), instance, scene_id)
		_check_tiles(instance, scene_id, "instantiated")
		instance.free()
		_drain(scene_id)
	print("verify_generated: %d scenes loaded and instantiated, %d nodes" % [ids.size(), total_nodes])


func _start_play(index: Dictionary) -> void:
	if not index.has(PLAY_SCENE_ID):
		_failures.append("%s is not in the scene index" % PLAY_SCENE_ID)
		return
	_play_root = (load(index[PLAY_SCENE_ID]) as PackedScene).instantiate()
	root.add_child(_play_root)
	var spawn := _play_root.get_node_or_null("player-spawn") as Node2D
	var origin := spawn.position if spawn != null else Vector2.ZERO
	var offset := 0.0
	for actor_id: String in PLAY_ACTORS:
		if not index.has(actor_id):
			_failures.append("%s is not in the scene index" % actor_id)
			continue
		var actor := (load(index[actor_id]) as PackedScene).instantiate() as Node2D
		actor.position = origin + Vector2(offset, 0)
		offset += 96.0
		_play_root.add_child(actor)
	_drain("enter tree %s" % PLAY_SCENE_ID)


## Every property the .tscn sets must exist on its node (Godot ignores
## unknown names silently) and hold the stored value after instantiation
## (catches values a typed property refused). Node-typed exports
## (`node_paths`) must resolve to the node their NodePath names.
func _check_properties(state: SceneState, instance: Node, scene_id: String) -> void:
	for index in state.get_node_count():
		var path := state.get_node_path(index)
		var node := instance.get_node_or_null(path)
		if node == null:
			_failures.append("%s: node %s missing after instantiation" % [scene_id, path])
			continue
		var script := node.get_script() as Script
		var script_path := script.resource_path if script != null else ""
		var foreign_script := not script_path.is_empty() and not script_path.begins_with("res://game/runtime/")
		if script != null and not script.can_instantiate():
			_foreign.append("%s: %s script %s failed to load; its properties are unchecked" % [scene_id, path, script_path])
			continue
		var names := {}
		for property in node.get_property_list():
			names[property["name"]] = true
		var script_names := {}
		if script != null:
			for property in script.get_script_property_list():
				script_names[property["name"]] = true
		for property_index in state.get_node_property_count(index):
			var property := String(state.get_node_property_name(index, property_index))
			var stored: Variant = state.get_node_property_value(index, property_index)
			if not names.has(property):
				_failures.append("%s: %s has no property '%s'" % [scene_id, path, property])
				continue
			# A hand-written script may legitimately transform what it is given (setters).
			var lenient := foreign_script and script_names.has(property)
			var actual: Variant = node.get(property)
			if stored is NodePath and (actual is Object or actual == null) and not (stored as NodePath).is_empty():
				if actual == null or node.get_node_or_null(stored) != actual:
					_record(lenient, "%s: %s:%s = %s did not resolve" % [scene_id, path, property, stored])
				continue
			if stored is Object or actual is Object:
				continue
			if not _same_value(stored, actual):
				_record(lenient, "%s: %s:%s stored %s but holds %s" % [scene_id, path, property, str(stored).left(80), str(actual).left(80)])


func _record(foreign: bool, line: String) -> void:
	if foreign:
		_foreign.append(line)
	else:
		_failures.append(line)


func _same_value(stored: Variant, actual: Variant) -> bool:
	if typeof(stored) in [TYPE_INT, TYPE_FLOAT] and typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(stored), float(actual))
	if typeof(stored) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(actual) in [TYPE_STRING, TYPE_STRING_NAME]:
		return String(stored) == String(actual)
	if typeof(stored) != typeof(actual):
		return false
	return stored == actual


## Compares every TileMapLayer under `node` with the tile data in the source scene JSON.
func _check_tiles(node: Node, scene_id: String, phase: String) -> void:
	var layers := node.find_children("*", "TileMapLayer", true, false)
	if node is TileMapLayer:
		layers.push_front(node)
	if layers.is_empty():
		return
	var source := _source_tile_layers(scene_id)
	for layer: TileMapLayer in layers:
		var label := "%s (%s) %s" % [scene_id, phase, layer.name]
		var used := layer.get_used_cells()
		var meta_count := int(layer.get_meta("source_cell_count", -1))
		if used.size() != meta_count:
			_failures.append("%s: %d cells, metadata says %d" % [label, used.size(), meta_count])
		if not source.has(String(layer.name)):
			_failures.append("%s: no tile layer of that name in the source JSON" % label)
			continue
		_compare_cells(layer, source[String(layer.name)], label)


func _compare_cells(layer: TileMapLayer, data: Dictionary, label: String) -> void:
	var cells: Array = data["cells"]
	var tile_seed: int = data["seed"]
	if layer.get_used_cells().size() != cells.size():
		_failures.append("%s: %d cells, source JSON has %d" % [label, layer.get_used_cells().size(), cells.size()])
	var tiles: Dictionary = _tile_set_json.get("tiles", {})
	var assets: Dictionary = _assets_json.get("assets", {})
	var mismatches := 0
	for cell: Dictionary in cells:
		var coords := Vector2i(int(cell["x"]), int(cell["y"]))
		var tile_id: String = cell["tileId"]
		var tile: Dictionary = tiles.get(tile_id, {})
		var asset_ids: Array = tile.get("assetIds", [])
		if asset_ids.is_empty():
			mismatches += 1
			continue
		var asset_id: String = asset_ids[tile_hash(coords.x, coords.y, tile_seed) % asset_ids.size()]
		var asset_source: Dictionary = (assets.get(asset_id, {}) as Dictionary).get("source", {})
		var expected_coords := Vector2i.ZERO
		if tile.get("selection", "") == "sheet-wrap":
			var frame: Dictionary = asset_source.get("frame", {})
			expected_coords = Vector2i(posmod(coords.x, int(frame.get("cols", 1))), posmod(coords.y, int(frame.get("rows", 1))))
		var problem := _cell_problem(layer, coords, tile_id, expected_coords, "res://asset/%s" % asset_source.get("path", ""))
		if not problem.is_empty():
			mismatches += 1
			if mismatches <= 5:
				_failures.append("%s: cell %s %s" % [label, coords, problem])
	if mismatches > 5:
		_failures.append("%s: %d mismatched cells in all" % [label, mismatches])


func _cell_problem(layer: TileMapLayer, coords: Vector2i, tile_id: String, atlas: Vector2i, texture_path: String) -> String:
	var source_id := layer.get_cell_source_id(coords)
	if source_id < 0:
		return "is empty, expected '%s'" % tile_id
	if layer.get_cell_atlas_coords(coords) != atlas:
		return "atlas %s, expected %s" % [layer.get_cell_atlas_coords(coords), atlas]
	var tile_data := layer.get_cell_tile_data(coords)
	if tile_data == null or String(tile_data.get_custom_data("tile_id")) != tile_id:
		return "tile id '%s', expected '%s'" % [tile_data.get_custom_data("tile_id") if tile_data else "?", tile_id]
	var atlas_source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if atlas_source == null or atlas_source.texture == null or atlas_source.texture.resource_path != texture_path:
		return "texture %s, expected %s" % [atlas_source.texture.resource_path if atlas_source and atlas_source.texture else "?", texture_path]
	return ""


## Tile layers of the source scene JSON: layer name → { cells, seed }.
func _source_tile_layers(scene_id: String) -> Dictionary:
	var scene_report: Dictionary = (_report.get("scenes", {}) as Dictionary).get(scene_id, {})
	var document := _read_json(_repo_path(AUTHORED_DIR + String(scene_report.get("file", ""))))
	var resources := {}
	for resource: Dictionary in document.get("subresources", []):
		resources[resource.get("resourceId", "")] = resource
	var layers := {}
	for node: Dictionary in document.get("nodes", []):
		if node.get("type", "") != "TileMapLayer2D":
			continue
		var properties: Dictionary = node.get("properties", {})
		var data_id: String = (properties.get("tileData", {}) as Dictionary).get("resourceId", "")
		var data: Dictionary = resources.get(data_id, {})
		layers[node.get("name", "")] = {"cells": data.get("cells", []), "seed": int(properties.get("seed", 0))}
	return layers


## Phaser's tile hash: (imul(x + seed·17, 374761393) ^ imul(y − seed·31, 668265263)) >>> 0.
static func tile_hash(x: int, y: int, tile_seed: int) -> int:
	return (_imul(x + tile_seed * 17, 374761393) ^ _imul(y - tile_seed * 31, 668265263)) & 0xFFFFFFFF


static func _i32(value: int) -> int:
	var low := value & 0xFFFFFFFF
	return low - 0x100000000 if low >= 0x80000000 else low


static func _imul(a: int, b: int) -> int:
	return _i32(_i32(a) * _i32(b))


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


## Sorts captured engine errors into converter failures and foreign ones.
func _drain(context: String) -> void:
	for entry in _collector.take():
		var line := "%s: %s%s at %s" % [context, "warning: " if entry["warning"] else "", entry["message"], entry["where"]]
		if _is_foreign(entry):
			_foreign.append(line)
		else:
			_failures.append(line)


## An error from a hand-written gameplay script (or its parse/load) is not the converter's.
func _is_foreign(entry: Dictionary) -> bool:
	var texts := PackedStringArray([entry["message"], entry["where"]])
	texts.append_array(entry["frames"])
	for text in texts:
		var at := text.find("res://game/")
		while at >= 0:
			if not text.substr(at).begins_with("res://game/runtime/"):
				return true
			at = text.find("res://game/", at + 1)
	return false


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _play_root != null and is_instance_valid(_play_root):
		_play_root.queue_free()
	if not _foreign.is_empty():
		print("verify_generated: %d error(s) from hand-written gameplay scripts (not converter failures):" % _foreign.size())
		for line in _unique_head(_foreign, 25):
			print("  [foreign] %s" % line)
	if _failures.is_empty():
		print("verify_generated: OK")
		quit(0)
		return
	printerr("verify_generated: %d failure(s):" % _failures.size())
	for line in _unique_head(_failures, 60):
		printerr("  %s" % line)
	quit(1)


func _unique_head(lines: PackedStringArray, limit: int) -> PackedStringArray:
	var seen := {}
	var result := PackedStringArray()
	for line in lines:
		if seen.has(line):
			continue
		seen[line] = true
		if result.size() < limit:
			result.append(line)
	if seen.size() > limit:
		result.append("... %d more distinct" % (seen.size() - limit))
	return result


func _repo_path(relative_to_project: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(relative_to_project).simplify_path()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
