extends Node
## Autoload `GameConstants`: read-only access to the game data in
## res://game/data/ (game-constants.json, enemy-types.json, items.json,
## collision-layers.json). Replaces Phaser `src/game/Constant.ts`.
##
## Rules (conventions "GDScript rules"): cross-feature gameplay values come only from here or
## from scene properties. Lookups use the JSON's own camelCase dotted paths, e.g.
## `number("character.player.movement.baseSpeed")` -> 200. A missing path is a content error:
## the getters push_error() and return a neutral value (0 / "" / {}), never a balance fallback.
## Access from scripts: `Services.constants()` (res://game/shared/services.gd).
##
## Owner: world builder.

const DATA_DIR := "res://game/data/"
const CONSTANTS_FILE := "game-constants.json"

var _constants: Dictionary = {}
var _files: Dictionary = {}
var _loaded: bool = false


## Loads game-constants.json in `_enter_tree` so every later autoload and scene can read it in
## its own `_ready`. A missing/invalid file push_error()s once and leaves the store empty.
func _enter_tree() -> void:
	if _loaded:
		return
	var parsed: Variant = _read_json(DATA_DIR + CONSTANTS_FILE)
	if parsed is Dictionary:
		_constants = parsed
		_files[CONSTANTS_FILE] = parsed
		_loaded = true
	else:
		push_error("GameConstants: %s%s is missing or not a JSON object" % [DATA_DIR, CONSTANTS_FILE])


## True once game-constants.json was parsed successfully.
func is_loaded() -> bool:
	return _loaded


## Value at a dotted camelCase path ("input.bufferMs"), or `fallback` when absent (no error).
## Use for optional keys only.
func value(path: String, fallback: Variant = null) -> Variant:
	var found: Array = _lookup(path)
	return found[1] if found[0] else fallback


## Number at `path` as float; push_error() + 0.0 when absent or not a number.
func number(path: String) -> float:
	var found: Array = _lookup(path)
	if not found[0]:
		push_error("GameConstants: missing number '%s'" % path)
		return 0.0
	var raw: Variant = found[1]
	if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
		return float(raw)
	push_error("GameConstants: '%s' is not a number" % path)
	return 0.0


## Number at `path` rounded to int; push_error() + 0 when absent or not a number.
func integer(path: String) -> int:
	var found: Array = _lookup(path)
	if not found[0]:
		push_error("GameConstants: missing integer '%s'" % path)
		return 0
	var raw: Variant = found[1]
	if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
		return roundi(float(raw))
	push_error("GameConstants: '%s' is not a number" % path)
	return 0


## Dictionary at `path` (camelCase keys kept); push_error() + {} when absent.
func dictionary(path: String) -> Dictionary:
	var found: Array = _lookup(path)
	if found[0] and found[1] is Dictionary:
		return found[1]
	push_error("GameConstants: missing object '%s'" % path)
	return {}


## Parsed contents of res://game/data/<file_name> (e.g. "enemy-types.json"), cached after
## the first read; null + push_error() when missing or invalid JSON.
func data_file(file_name: String) -> Variant:
	if _files.has(file_name):
		return _files[file_name]
	var parsed: Variant = _read_json(DATA_DIR + file_name)
	if parsed == null:
		push_error("GameConstants: data file %s%s is missing or invalid JSON" % [DATA_DIR, file_name])
		return null
	_files[file_name] = parsed
	return parsed


## [found: bool, value]. Walks Dictionaries by key and Arrays by integer index.
func _lookup(path: String) -> Array:
	if not _loaded or path.is_empty():
		return [false, null]
	var current: Variant = _constants
	for segment: String in path.split("."):
		if current is Dictionary:
			var dict: Dictionary = current
			if not dict.has(segment):
				return [false, null]
			current = dict[segment]
		elif current is Array and segment.is_valid_int():
			var list: Array = current
			var index := segment.to_int()
			if index < 0 or index >= list.size():
				return [false, null]
			current = list[index]
		else:
			return [false, null]
	return [true, current]


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("GameConstants: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
