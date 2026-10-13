extends RefCounted
## The region worlds cut into chunk worlds (godot/tools/split_region_chunks.gd, which writes
## game/data/world-chunks.json; docs/godot/WORLD_ATLAS.md "Chunk worlds"). A cut region has no
## whole world scene: travel into it, by an arrival marker, a door, an edge or nothing at all, goes
## to the chunk that holds the place it arrives at (`redirect`). A chunk world knows its region's
## world and its chunk (`world_of`, `chunk_of`), for the discovered areas, the map and the atlas.
##
## Owner: world (atlas).

const PATH := "res://game/data/world-chunks.json"
const FORMAT := "slime-isa-world-chunks"
const SCENES_DIR := "res://game/scenes/worlds/chunks/"

## world -> {"chunks": {chunk world: chunk name ("A6")}, "arrivals": {marker name: chunk world},
## "doors": {door id: chunk world}, "spawn": chunk world, "written": {chunk world: hash of the file
## the tool wrote}}.
static var _worlds: Dictionary = {}
## chunk world -> its region's world, and -> its chunk's name.
static var _world_of: Dictionary = {}
static var _chunk_of: Dictionary = {}
static var _loaded := false


## The world to load for travel to `map_id`: when `map_id` was cut into chunks, the chunk that holds
## the Node2D `entry_marker`, else the door `entry_door`, else the `player-entry-<entry_edge>` marker,
## else the region's spawn; `map_id` itself otherwise.
static func redirect(map_id: String, entry_marker: String = "", entry_edge: String = "", entry_door: String = "") -> String:
	_load()
	if not _worlds.has(map_id):
		return map_id
	var world: Dictionary = _worlds[map_id]
	var arrivals: Dictionary = world.get("arrivals", {})
	var doors: Dictionary = world.get("doors", {})
	if not entry_marker.is_empty() and arrivals.has(entry_marker):
		return str(arrivals[entry_marker])
	if not entry_door.is_empty() and doors.has(entry_door):
		return str(doors[entry_door])
	if not entry_edge.is_empty() and arrivals.has("player-entry-" + entry_edge):
		return str(arrivals["player-entry-" + entry_edge])
	return str(world.get("spawn", map_id))


## True when world `map_id` was cut into chunk worlds.
static func is_cut(map_id: String) -> bool:
	_load()
	return _worlds.has(map_id)


## The chunk worlds of cut world `map_id`: {chunk world: chunk name}; {} when it is not cut.
static func chunks(map_id: String) -> Dictionary:
	_load()
	return ((_worlds.get(map_id, {}) as Dictionary).get("chunks", {}) as Dictionary).duplicate()


## The scene of chunk world `chunk_world`.
static func scene_path(chunk_world: String) -> String:
	return SCENES_DIR + chunk_world + ".tscn"


## The region world chunk world `map_id` was cut from ("south-wilds" for "south-wilds-a6"); "" when
## it is no chunk world.
static func world_of(map_id: String) -> String:
	_load()
	return str(_world_of.get(map_id, ""))


## The chunk ("A6") chunk world `map_id` covers; "" when it is no chunk world.
static func chunk_of(map_id: String) -> String:
	_load()
	return str(_chunk_of.get(map_id, ""))


## The table as read from disk (`world` entries), for the cutting tool.
static func table() -> Dictionary:
	_load()
	return _worlds.duplicate(true)


## Reads the file again (the editor keeps the last read; the tool may have written it since).
static func reload() -> void:
	_loaded = false
	_worlds = {}
	_world_of = {}
	_chunk_of = {}
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or str((parsed as Dictionary).get("format", "")) != FORMAT:
		push_warning("WorldChunks: %s is not a %s file" % [PATH, FORMAT])
		return
	_worlds = (parsed as Dictionary).get("worlds", {})
	for world: String in _worlds:
		var chunk_names: Dictionary = (_worlds[world] as Dictionary).get("chunks", {})
		for id: String in chunk_names:
			_world_of[id] = world
			_chunk_of[id] = str(chunk_names[id])
