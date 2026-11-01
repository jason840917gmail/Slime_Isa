extends RefCounted
## Crossing a border between two overworld regions by coordinates (2026-10-31, docs/design/
## 2026-10-31-crossings-and-arrivals.md D5). Every overworld chunk world is a square of the atlas
## grid (game/data/world-map.json: `chunks` columns and rows, `tilesPerCell`, `tileSize`; chunk "A1"
## is the north-west one, the letter its column, the number its row), so where the slime leaves one
## chunk through an edge is a point on the whole overworld, and the chunk across that edge, in
## whichever region, is where it comes out: at the same place along the edge, as between the chunks
## of one region (world_exit.gd `keep_along`). A world exit into a neighbouring region asks
## `across` and travels there (main.gd scrolls into it), instead of arriving at a marker.
##
## Owner: world (atlas).

const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")

const MAP_PATH := "res://game/data/world-map.json"
const WORLD_EXIT_SCRIPT := "res://game/scripts/world_exit.gd"
const COLUMN_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const EDGES: PackedStringArray = ["north", "east", "south", "west"]

## World units per chunk side (0 until the map is read; NAN when it could not be).
static var _chunk_units: float = 0.0
## The scene `way_back_along` last read, kept loaded for the travel into it.
static var _held_scene: PackedScene
## `way_back_along`'s answers this session, by scene, the worlds back, edge and stretch of the edge.
static var _way_back: Dictionary = {}


## Where the slime comes out when it leaves chunk world `from_map` through its `edge_out` edge at
## `centre` (its old Phaser centre, in `from_map`'s units) toward `target_area` (a region's world or
## one of its chunks): {"world": the chunk across the edge, "edge": the edge it arrives at there,
## "along": where along that edge}. {} when either side is not on the atlas grid or the chunk across
## the edge is not one of `target_area`'s.
static func across(from_map: String, target_area: String, edge_out: String, centre: Vector2) -> Dictionary:
	var origin: Variant = chunk_origin(from_map)
	if not origin is Vector2 or not edge_out in EDGES:
		return {}
	var units := chunk_units()
	var point: Vector2 = (origin as Vector2) + centre
	var cell := Vector2i(floori(point.x / units), floori(point.y / units)) + _step(edge_out)
	var target := _chunk_at(target_area, cell)
	if target.is_empty():
		return {}
	var local: Vector2 = point - (chunk_origin(target) as Vector2)
	var edge_in := _opposite(edge_out)
	return {"world": target, "edge": edge_in, "along": local.y if edge_in == "east" or edge_in == "west" else local.x}


## Where the slime comes in across the border for `crossing` (from `across`): through the opening back
## into one of `back_to` in that chunk (`way_back_along`), else the nearest opening back along the
## same border line in the target region's other chunks (the two sides of a border drawn apart:
## gloop-forest's long west edge against level-1's one gate). {"world", "edge", "along"}, or {} when
## no exit leads back along that border.
static func opening_back(crossing: Dictionary, back_to: PackedStringArray, slack: float) -> Dictionary:
	var world := str(crossing["world"])
	var edge := str(crossing["edge"])
	var along := float(crossing["along"])
	var found := way_back_along(WorldChunks.scene_path(world), back_to, edge, along, slack)
	if not is_nan(found):
		return {"world": world, "edge": edge, "along": found}
	var cell: Variant = chunk_cell(WorldChunks.chunk_of(world))
	var region := WorldChunks.world_of(world)
	if not cell is Vector2i or region.is_empty():
		return {}
	var east_west := edge == "east" or edge == "west"
	var units := chunk_units()
	var line_along := along + float((cell as Vector2i).y if east_west else (cell as Vector2i).x) * units
	var best := {}
	var best_gap := INF
	for chunk_world: String in WorldChunks.chunks(region):
		var other: Variant = chunk_cell(WorldChunks.chunk_of(chunk_world))
		if chunk_world == world or not other is Vector2i:
			continue
		if (east_west and (other as Vector2i).x != (cell as Vector2i).x) or (not east_west and (other as Vector2i).y != (cell as Vector2i).y):
			continue
		var offset := float((other as Vector2i).y if east_west else (other as Vector2i).x) * units
		var at := way_back_along(WorldChunks.scene_path(chunk_world), back_to, edge, line_along - offset, slack)
		if not is_nan(at) and absf(at + offset - line_along) < best_gap:
			best_gap = absf(at + offset - line_along)
			best = {"world": chunk_world, "edge": edge, "along": at}
	return best


## Where along its `edge` the world scene at `scene_path` lets the slime in when it crosses at
## `along` from one of `back_to` (worlds or regions' worlds): through the world exit there that leads
## back (its area, grown by `slack`, holds the point: `along` itself), else through the nearest
## exit back along that edge (the middle of its opening: the two sides of an opening drawn apart);
## NAN when no exit leads back along that edge (an opening drawn on one side only, a placeholder's
## way into a hand-made world, docs/godot/WORLD_ATLAS.md). Read from the scene's state, without
## building it (the scene stays loaded for the travel that follows).
static func way_back_along(scene_path: String, back_to: PackedStringArray, edge: String, along: float, slack: float) -> float:
	# Asked every step while the slime stands in a refused exit (a lock): read each place once.
	var key := "%s|%s|%s|%d" % [scene_path, ",".join(back_to), edge, floori(along / slack) if slack > 0.0 else int(along)]
	if _way_back.has(key):
		return float(_way_back[key])
	var found := _read_way_back(scene_path, back_to, edge, along, slack)
	_way_back[key] = found
	return found


static func _read_way_back(scene_path: String, back_to: PackedStringArray, edge: String, along: float, slack: float) -> float:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return NAN
	_held_scene = load(scene_path) as PackedScene
	if _held_scene == null:
		return NAN
	var state := _held_scene.get_state()
	var positions := {}
	var shapes := {}
	var exits: Array[Dictionary] = []
	for index: int in state.get_node_count():
		var path := str(state.get_node_path(index))
		var target := ""
		var area_path := ""
		var is_exit := false
		for p: int in state.get_node_property_count(index):
			var property := str(state.get_node_property_name(index, p))
			var value: Variant = state.get_node_property_value(index, p)
			match property:
				"position":
					positions[path] = value
				"shape":
					shapes[path.get_base_dir()] = value
				"script":
					is_exit = value is Script and (value as Script).resource_path == WORLD_EXIT_SCRIPT
				"target_area_id":
					target = str(value)
				"area":
					area_path = str(value)
		if is_exit:
			exits.append({"target": target, "area": _join(path, area_path if not area_path.is_empty() else "..")})
	var size := chunk_units()
	var across_edge := edge == "east" or edge == "west"
	var line := 0.0 if edge == "west" or edge == "north" else size
	var point := Vector2(line, along) if across_edge else Vector2(along, line)
	var nearest := NAN
	for exit: Dictionary in exits:
		var target := str(exit["target"])
		var region := WorldChunks.world_of(target)
		if not (target in back_to or (not region.is_empty() and region in back_to)):
			continue
		var shape := shapes.get(str(exit["area"])) as RectangleShape2D
		if shape == null:
			continue
		var rect := Rect2(_scene_position(str(exit["area"]), positions) - shape.size * 0.5, shape.size)
		if rect.grow(slack).has_point(point):
			return along
		# An exit back lying against this edge, elsewhere along it.
		var off_line := absf((rect.get_center().x if across_edge else rect.get_center().y) - line)
		if off_line > slack:
			continue
		var middle := rect.get_center().y if across_edge else rect.get_center().x
		if is_nan(nearest) or absf(middle - along) < absf(nearest - along):
			nearest = middle
	return nearest


## The overworld position of chunk world `map_id`'s origin (its chunk's corner on the atlas grid), or
## null when it is no chunk world.
static func chunk_origin(map_id: String) -> Variant:
	var chunk := WorldChunks.chunk_of(map_id)
	var cell: Variant = chunk_cell(chunk)
	if not cell is Vector2i or not is_finite(chunk_units()):
		return null
	return Vector2(cell as Vector2i) * chunk_units()


## "D6" -> Vector2i(3, 5); null when it is not a chunk name.
static func chunk_cell(chunk: String) -> Variant:
	if chunk.length() < 2:
		return null
	var column := COLUMN_LETTERS.find(chunk.left(1).to_upper())
	var row_text := chunk.substr(1)
	if column < 0 or not row_text.is_valid_int():
		return null
	return Vector2i(column, int(row_text) - 1)


## World units per chunk side (2048 for the 8 x 8 chunk overworld): read once from the world map.
static func chunk_units() -> float:
	if _chunk_units != 0.0:
		return _chunk_units
	_chunk_units = NAN
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH)) if FileAccess.file_exists(MAP_PATH) else null
	if parsed is Dictionary:
		var map: Dictionary = parsed
		var chunks: Dictionary = map.get("chunks", {})
		var columns := int(chunks.get("cols", 0))
		if columns > 0:
			_chunk_units = float(int(map.get("cols", 0)) / columns * int(map.get("tilesPerCell", 0)) * int(map.get("tileSize", 0)))
	if not is_finite(_chunk_units) or _chunk_units <= 0.0:
		push_warning("BorderCrossing: cannot read the chunk size from %s" % MAP_PATH)
		_chunk_units = NAN
	return _chunk_units


## The chunk world of `target_area` (a cut region's world, or one of its chunks) on chunk `cell`; ""
## when it has none there.
static func _chunk_at(target_area: String, cell: Vector2i) -> String:
	var region := WorldChunks.world_of(target_area)
	if region.is_empty():
		region = target_area
	for chunk_world: String in WorldChunks.chunks(region):
		if chunk_cell(WorldChunks.chunk_of(chunk_world)) == cell:
			return chunk_world
	return ""


## A node path of a scene's state ("exit-1/world-exit-script") with `relative` ("..") applied.
static func _join(path: String, relative: String) -> String:
	var parts := Array(path.split("/", false))
	for part: String in relative.split("/", false):
		if part == "..":
			if not parts.is_empty():
				parts.pop_back()
		elif part != ".":
			parts.append(part)
	return "/".join(PackedStringArray(parts)) if not parts.is_empty() else "."


## Where the node at state path `path` stands in its scene: the positions of it and its parents
## added up (scenes laid out without rotation or scale, as the world builders write them).
static func _scene_position(path: String, positions: Dictionary) -> Vector2:
	var at := Vector2.ZERO
	var walk := path
	while not walk.is_empty() and walk != ".":
		at += positions.get(walk, Vector2.ZERO) as Vector2
		walk = walk.get_base_dir() if walk.contains("/") else ""
	return at


## One chunk over through `edge`.
static func _step(edge: String) -> Vector2i:
	match edge:
		"north":
			return Vector2i.UP
		"south":
			return Vector2i.DOWN
		"west":
			return Vector2i.LEFT
	return Vector2i.RIGHT


static func _opposite(edge: String) -> String:
	match edge:
		"north":
			return "south"
		"south":
			return "north"
		"west":
			return "east"
	return "west"
