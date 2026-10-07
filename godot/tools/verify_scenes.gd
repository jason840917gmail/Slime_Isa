extends SceneTree
## Verifies the scenes Godot owns (res://game/scenes/scene_index.json, docs/godot/CONVENTIONS.md
## "Scenes Godot owns").
##
## Run headless from the repository root:
##   "<godot console exe>" --headless --path godot -s res://tools/verify_scenes.gd
##
## 1. Loads and instantiates every scene in the index. Every property a .tscn sets must exist on
##    its node and keep its value, and every Node-typed export must resolve (Godot skips both
##    silently).
## 2. Adds level-1, the player slime, a worm swordsman and the basic sword to the tree for a few
##    frames.
##
## Engine errors and warnings are captured with a Logger. Those raised in hand-written gameplay
## scripts (res://game/ outside res://game/runtime/ and res://game/scenes/) are listed as
## "foreign" without failing the run; every other error or warning while a scene loads or plays
## fails it. Exits 1 on any failure.
##
## Replaces tools/verify_generated.gd, which compared the converter's output with the scene JSON
## until Phase 1 of the migration made the scenes Godot's (2026-10-05).

const INDEX_PATH := "res://game/scenes/scene_index.json"
const PLAY_SCENE_ID := "world.level-1"
const PLAY_ACTORS := ["character.player-slime", "character.worm-swordsman", "weapon.basic-sword"]
const PLAY_FRAMES := 30
## Paths whose errors are the scenes' own (not a gameplay script's).
const SCENE_PATHS := ["res://game/runtime/", "res://game/scenes/"]


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
var _play_root: Node
var _frames := 0
var _finished := false


func _initialize() -> void:
	_collector = ErrorCollector.new()
	OS.add_logger(_collector)
	var index := _read_json(INDEX_PATH)
	if index.is_empty():
		_failures.append("missing or empty %s" % INDEX_PATH)
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
	print("verify_scenes: %s played %d frames in the tree (%d nodes, actors: %s)" % [
		PLAY_SCENE_ID, _frames, _count_nodes(_play_root), ", ".join(PLAY_ACTORS)])
	_finish()
	return true


func _check_all_scenes(index: Dictionary) -> void:
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
		total_nodes += _count_nodes(instance)
		_check_properties(packed.get_state(), instance, scene_id)
		instance.free()
		_drain(scene_id)
	print("verify_scenes: %d scenes loaded and instantiated, %d nodes" % [ids.size(), total_nodes])


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


## Every property the .tscn sets must exist on its node (Godot ignores unknown names silently)
## and hold the stored value after instantiation (catches values a typed property refused).
## Node-typed exports (`node_paths`) must resolve to the node their NodePath names.
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


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


## Sorts captured engine errors into scene failures and foreign ones.
func _drain(context: String) -> void:
	for entry in _collector.take():
		var line := "%s: %s%s at %s" % [context, "warning: " if entry["warning"] else "", entry["message"], entry["where"]]
		if _is_foreign(entry):
			_foreign.append(line)
		else:
			_failures.append(line)


## An error from a hand-written gameplay script (or its parse/load) is not the scenes'.
func _is_foreign(entry: Dictionary) -> bool:
	var texts := PackedStringArray([entry["message"], entry["where"]])
	texts.append_array(entry["frames"])
	for text in texts:
		var at := text.find("res://game/")
		while at >= 0:
			var rest := text.substr(at)
			var own := false
			for prefix: String in SCENE_PATHS:
				own = own or rest.begins_with(prefix)
			if not own:
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
		print("verify_scenes: %d error(s) from hand-written gameplay scripts (not scene failures):" % _foreign.size())
		for line in _unique_head(_foreign, 25):
			print("  [foreign] %s" % line)
	if _failures.is_empty():
		print("verify_scenes: OK")
		quit(0)
		return
	printerr("verify_scenes: %d failure(s):" % _failures.size())
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


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
