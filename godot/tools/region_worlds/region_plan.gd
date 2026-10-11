extends RefCounted
## The whole-map part of the placeholder region worlds (godot/tools/build_region_worlds.gd): the
## world map sketch (res://game/data/world-map.json, through world_map_data.gd) cleaned up and its
## passages chosen, for every region at once, so both sides of every border agree.
##
## - Ground levels per cell: each region's elevation digits smoothed (a cell keeps its digit when
##   LEVEL_KEEP cells of its 3 x 3 neighbourhood share it, else it takes the digit most of them
##   have), then normalised (the region's lowest ground is level 0, nothing above MAX_LEVEL);
##   mountains stand one level higher, lava is a level -1 pit and the abyss a level -3 one.
## - A lone cell of open ground (no neighbour of its kind), and rock the smoothing lowered, takes
##   the ground most of its neighbours have.
## - Passages (the Zelda rule: touching regions meet only at designated places): one opening per
##   pair of touching regions and per stretch of their shared border, OPENING_CELLS wide, with a
##   corridor CORRIDOR_CELLS deep on both sides. It goes where a gate marker of the sketch, an exit a
##   built world already has or a sketch road crosses the border, else to the middle-most spot whose
##   corridor is walkable ground on one level, away from the stretch's ends and corners.
##
## Owner: world (atlas).

const Self := preload("res://tools/region_worlds/region_plan.gd")
const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const WorldExit := preload("res://game/scripts/world_exit.gd")

const SCENE_INDEX := "res://game/scenes/scene_index.json"
const MAX_LEVEL := 3
const LAVA_LEVEL := -1
const ABYSS_LEVEL := -3
## Terrain kinds nothing walks on: deep water, mountain, lava, abyss.
const BLOCKED := "wmlv"
## Terrain kinds that sink into a pit (their own level, never smoothed).
const PITS := "lv"
## Terrain kinds that are roads on the sketch: path, bridge, town paving.
const ROADS := "pht"
## Open ground whose lone cells take their neighbours' ground (not water, roads or forest).
const LONE_KINDS := ".gbdrnixkc"
## A cell keeps its digit when this many cells of its 3 x 3 neighbourhood (itself included) share it.
const LEVEL_KEEP := 4
const SMOOTH_PASSES := 4
## An opening's width and its corridor's depth on each side (cells).
const OPENING_CELLS := 2
const CORRIDOR_CELLS := 2
## How near (cells) a gate marker or a built world's exit must be to an opening's middle to pick it.
const GATE_REACH := 2.5
const EXIT_HINT_REACH := 2.0
## A built world's exit is a hint when its trigger is at most this long (tiles): a gate-sized
## opening, not a whole edge.
const EXIT_HINT_TILES := 8
## Scores of a candidate opening (the highest wins).
const SCORE_GATE := 200.0
const SCORE_EXIT_HINT := 2000.0
const SCORE_PER_CELL_FROM_HINT := -100.0
const SCORE_ROAD_CELL := 30.0
const SCORE_BLOCKED := -150.0
const SCORE_SHALLOW := -25.0
const SCORE_FOREST := -5.0
const SCORE_OFF_LEVEL := -40.0
const SCORE_BLOCKED_BEYOND := -20.0
const SCORE_NEAR_CORNER := -500.0
const SCORE_CUT_OFF := -1000.0
const SCORE_PER_CELL_FROM_MIDDLE := -2.0
const SCORE_PER_RUN_CELL := 1.0
## The widest deep water a road bridges (cells).
const MAX_BRIDGE_CELLS := 3
const NEIGHBOURS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var map: WorldMapData
var cols := 0
var rows := 0
## Terrain kind per cell (ASCII), cleaned up.
var terrain := PackedByteArray()
## Ground level per cell, per region (see above).
var levels := PackedInt32Array()
## Every opening, in the order of `passages()`: {a, b (the region keys west or north of the border
## and east or south of it), line ("v" between two columns, "h" between two rows), at (Vector2i:
## b's first cell of the opening; the opening runs OPENING_CELLS down a "v" border, across an "h"
## one), levels ({key: the level its corridor is flattened to}), kind ("gate" | "exit" | "road" |
## "path"), label, index (1, 2, ... among the openings of the same two regions)}.
var openings: Array[Dictionary] = []
## The exits built worlds already have that look like gates: [{keys (sorted pair), cell (Vector2)}].
var exit_hints: Array[Dictionary] = []
var warnings := PackedStringArray()

## Rock cells the smoothing lowered (a lone outcrop, a line one cell thin): cell -> true. They take
## the ground around them (the region worlds put boulders on some).
var lowered_rock := {}
## Region key -> its main walkable ground (`_main_ground`).
var _main_grounds := {}


static func create(source: WorldMapData) -> Self:
	var plan := Self.new()
	plan._build(source)
	return plan


func _build(source: WorldMapData) -> void:
	map = source
	cols = map.cols
	rows = map.rows
	terrain.resize(cols * rows)
	for y in rows:
		for x in cols:
			terrain[y * cols + x] = map.terrain_at(Vector2i(x, y)).unicode_at(0)
	_compute_levels()
	_clean_lone_cells()
	_read_exit_hints()
	_choose_openings()


# --- cells ----------------------------------------------------------------------------------

func kind_at(cell: Vector2i) -> String:
	if not map.has_cell(cell):
		return ""
	return String.chr(terrain[cell.y * cols + cell.x])


func level_at(cell: Vector2i) -> int:
	return levels[cell.y * cols + cell.x] if map.has_cell(cell) else 0


func key_at(cell: Vector2i) -> String:
	return map.region_key_at(cell)


func is_blocked(cell: Vector2i) -> bool:
	var kind := kind_at(cell)
	return kind == "" or BLOCKED.contains(kind)


func _compute_levels() -> void:
	levels.resize(cols * rows)
	levels.fill(0)
	for entry: Dictionary in map.regions():
		var key := str(entry.get("key", ""))
		var cells := map.region_cells(key)
		if cells.is_empty():
			continue
		var digits := {}
		for cell in cells:
			digits[cell] = map.elevation_at(cell)
		for _pass in SMOOTH_PASSES:
			var changes := {}
			for cell in cells:
				if PITS.contains(kind_at(cell)):
					continue
				var counts := {}
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var near := cell + Vector2i(dx, dy)
						if digits.has(near) and not PITS.contains(kind_at(near)):
							counts[digits[near]] = int(counts.get(digits[near], 0)) + 1
				var own: int = digits[cell]
				var best := own
				var best_count := int(counts.get(own, 0))
				if best_count >= LEVEL_KEEP:
					continue
				for digit: int in counts:
					if int(counts[digit]) > best_count:
						best = digit
						best_count = int(counts[digit])
				if best != own:
					changes[cell] = best
			if changes.is_empty():
				break
			for cell: Vector2i in changes:
				digits[cell] = changes[cell]
		var base := 1 << 20
		for cell in cells:
			if not PITS.contains(kind_at(cell)) and kind_at(cell) != "m":
				base = mini(base, int(digits[cell]))
		if base == 1 << 20:
			base = 0
		for cell in cells:
			var level := clampi(int(digits[cell]) - base, 0, MAX_LEVEL)
			match kind_at(cell):
				"m":
					level = mini(level + 1, MAX_LEVEL)
				"l":
					level = LAVA_LEVEL
				"v":
					level = ABYSS_LEVEL
			levels[cell.y * cols + cell.x] = level
			if kind_at(cell) == "r" and int(digits[cell]) < map.elevation_at(cell):
				lowered_rock[cell] = true


func _clean_lone_cells() -> void:
	var changes := {}
	for y in rows:
		for x in cols:
			var cell := Vector2i(x, y)
			var kind := kind_at(cell)
			if not LONE_KINDS.contains(kind):
				continue
			if lowered_rock.has(cell):
				# Rock the smoothing brought down to its neighbours' level is their ground.
				kind = ""
			var key := key_at(cell)
			var counts := {}
			var same := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var near := cell + Vector2i(dx, dy)
					if near == cell or key_at(near) != key:
						continue
					var other := kind_at(near)
					if other == kind:
						same += 1
					elif (LONE_KINDS.contains(other) or other == "f") and not lowered_rock.has(near) and other != "r":
						counts[other] = int(counts.get(other, 0)) + 1
			if same > 0 or counts.is_empty():
				continue
			var best := ""
			for other: String in counts:
				if best == "" or int(counts[other]) > int(counts[best]) or (int(counts[other]) == int(counts[best]) and other < best):
					best = other
			changes[cell] = best
	for cell: Vector2i in changes:
		terrain[cell.y * cols + cell.x] = str(changes[cell]).unicode_at(0)


# --- exits built worlds already have --------------------------------------------------------

## The short exits (gates) of the built worlds (regions that are not placeholders) whose target is
## another region's world, as hints for where their opening goes.
func _read_exit_hints() -> void:
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENE_INDEX))
	if not index is Dictionary:
		return
	for entry: Dictionary in map.regions():
		var world := str(entry.get("world", ""))
		var path := str((index as Dictionary).get("world." + world, ""))
		if bool(entry.get("placeholder", false)) or world == "" or path == "" or not ResourceLoader.exists(path):
			continue
		var rect := map.region_chunk_rect(str(entry.get("key", "")))
		if not rect.has_area():
			continue
		var origin := Vector2(map.chunk_rect_cells(rect).position)
		var root := (load(path) as PackedScene).instantiate()
		for node in root.find_children("*", "Node", true, false):
			if node.get_script() != WorldExit:
				continue
			var target := map.region_for_map(str(node.get(&"target_area_id")))
			var area := node.get_parent() as Area2D
			if target.is_empty() or area == null:
				continue
			var shapes := area.find_children("*", "CollisionShape2D", false, false)
			var shape := shapes[0] as CollisionShape2D if not shapes.is_empty() else null
			var box := shape.shape as RectangleShape2D if shape != null else null
			if box == null or maxf(box.size.x, box.size.y) > EXIT_HINT_TILES * map.tile_size:
				continue
			var keys := [str(entry.get("key", "")), str(target.get("key", ""))]
			keys.sort()
			exit_hints.append({"keys": keys, "cell": origin + (area.position + shape.position) / map.cell_units()})
		root.free()


# --- passages -------------------------------------------------------------------------------

## The passages for world-map.json: {a, b, x, y, w, h (cells: the opening's cells on both sides),
## kind, label (when a marker names it)}.
func passages() -> Array:
	var out: Array = []
	for opening in openings:
		var at: Vector2i = opening["at"]
		var cell := at - (Vector2i(1, 0) if opening["line"] == "v" else Vector2i(0, 1))
		var passage := {"a": opening["a"], "b": opening["b"], "x": cell.x, "y": cell.y, "w": 2, "h": 2, "kind": opening["kind"]}
		if str(opening["label"]) != "":
			passage["label"] = opening["label"]
		out.append(passage)
	return out


## The cells of `opening`'s corridor on `key`'s side, from the border inwards ([depth][along]).
func corridor_cells(opening: Dictionary, key: String, depth: int = CORRIDOR_CELLS) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at: Vector2i = opening["at"]
	var inward := -direction(opening, key)
	var first := at if key == opening["b"] else at - (Vector2i(1, 0) if opening["line"] == "v" else Vector2i(0, 1))
	var along := Vector2i(0, 1) if opening["line"] == "v" else Vector2i(1, 0)
	for d in depth:
		for i in OPENING_CELLS:
			out.append(first + inward * d + along * i)
	return out


## The way out of `key`'s side through `opening` (a unit step towards the other region).
func direction(opening: Dictionary, key: String) -> Vector2i:
	var towards_b := Vector2i(1, 0) if opening["line"] == "v" else Vector2i(0, 1)
	return towards_b if key == opening["a"] else -towards_b


## The openings of region `key`.
func openings_of(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for opening in openings:
		if opening["a"] == key or opening["b"] == key:
			out.append(opening)
	return out


func _choose_openings() -> void:
	var by_pair := {}
	for y in rows:
		for x in cols:
			var here := key_at(Vector2i(x, y))
			if here == WorldMapData.NO_REGION:
				continue
			for line in 2:
				var other := key_at(Vector2i(x + 1 - line, y + line))
				if other == "" or other == WorldMapData.NO_REGION or other == here:
					continue
				var pair := [here, other]
				pair.sort()
				var pair_key := "".join(pair)
				if not by_pair.has(pair_key):
					by_pair[pair_key] = []
				(by_pair[pair_key] as Array).append(Vector3i(x, y, line))
	var pairs := by_pair.keys()
	pairs.sort()
	for pair_key: String in pairs:
		var stretches := _stretches(by_pair[pair_key])
		var found: Array[Dictionary] = []
		for stretch in stretches:
			var best := _best_opening(stretch)
			if best.is_empty():
				warnings.append("no room for an opening between %s and %s (a stretch of %d cells)" % [pair_key[0], pair_key[1], stretch.size()])
				continue
			found.append(best)
		found.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
			var pa: Vector2i = p["at"]
			var qa: Vector2i = q["at"]
			return pa.y < qa.y or (pa.y == qa.y and pa.x < qa.x))
		for i in found.size():
			found[i]["index"] = i + 1
			openings.append(found[i])


## The border edges of one pair cut into stretches (edges that touch end to end): Array of
## Array[Vector3i] (x, y: the cell west or north of the edge; z: 0 for a vertical edge, 1 for a
## horizontal one).
func _stretches(edges: Array) -> Array:
	var ends := {}
	for edge: Vector3i in edges:
		for end in _edge_ends(edge):
			if not ends.has(end):
				ends[end] = []
			(ends[end] as Array).append(edge)
	var seen := {}
	var out: Array = []
	for start: Vector3i in edges:
		if seen.has(start):
			continue
		var component := _component(start, ends)
		for edge in component:
			seen[edge] = true
		out.append(component)
	return out


func _component(start: Vector3i, ends: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var seen := {start: true}
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var edge: Vector3i = queue.pop_back()
		out.append(edge)
		for end in _edge_ends(edge):
			for next: Vector3i in ends[end]:
				if not seen.has(next):
					seen[next] = true
					queue.append(next)
	return out


static func _edge_ends(edge: Vector3i) -> Array[Vector2i]:
	if edge.z == 0:
		return [Vector2i(edge.x + 1, edge.y), Vector2i(edge.x + 1, edge.y + 1)]
	return [Vector2i(edge.x, edge.y + 1), Vector2i(edge.x + 1, edge.y + 1)]


## The best opening of a stretch (see `openings`), {} when it has no two edges in a row. Besides
## `_score`, an opening likes the middle of the longest straight run of the stretch (an L-shaped
## border's middle is its corner).
func _best_opening(stretch: Array) -> Dictionary:
	var place := {}
	var runs := {}
	for edge: Vector3i in stretch:
		place[edge] = true
		var line_key := Vector2i(edge.z, edge.x if edge.z == 0 else edge.y)
		if not runs.has(line_key):
			runs[line_key] = []
		(runs[line_key] as Array).append(edge.y if edge.z == 0 else edge.x)
	# Each edge's straight run: Vector2i(first, last position along its line).
	var run_of := {}
	for line_key: Vector2i in runs:
		var positions: Array = runs[line_key]
		positions.sort()
		var first: int = positions[0]
		for i in positions.size():
			var at: int = positions[i]
			if i + 1 == positions.size() or int(positions[i + 1]) != at + 1:
				for p in range(first, at + 1):
					var edge := Vector3i(line_key.y, p, 0) if line_key.x == 0 else Vector3i(p, line_key.y, 1)
					run_of[edge] = Vector2i(first, at)
				if i + 1 < positions.size():
					first = positions[i + 1]
	var best := {}
	var best_score := -INF
	for edge: Vector3i in stretch:
		var line := edge.z
		var partner := edge + (Vector3i(0, 1, 0) if line == 0 else Vector3i(1, 0, 0))
		if not place.has(partner):
			continue
		var low := Vector2i(edge.x, edge.y)
		var a := key_at(low)
		var b := key_at(low + (Vector2i(1, 0) if line == 0 else Vector2i(0, 1)))
		if key_at(Vector2i(partner.x, partner.y)) != a:
			continue
		var opening := {
			"a": a, "b": b, "line": "v" if line == 0 else "h",
			"at": low + (Vector2i(1, 0) if line == 0 else Vector2i(0, 1)),
			"levels": {}, "kind": "path", "label": "", "index": 1,
		}
		var run: Vector2i = run_of[edge]
		var along := float(edge.y if line == 0 else edge.x) + 1.0
		var score := _score(opening) + SCORE_PER_CELL_FROM_MIDDLE * absf(along - (run.x + run.y + 1) * 0.5) 				+ SCORE_PER_RUN_CELL * (run.y - run.x + 1)
		if score > best_score:
			best_score = score
			best = opening
	return best


## How good `opening` is (it also fills in its levels, kind and label).
func _score(opening: Dictionary) -> float:
	var score := 0.0
	var middle := _middle(opening)
	var nearest := GATE_REACH
	for marker: Dictionary in map.markers():
		var at := Vector2(float(marker.get("x", 0)) + 0.5, float(marker.get("y", 0)) + 0.5)
		if str(marker.get("type", "")) == "gate" and at.distance_to(middle) <= nearest:
			nearest = at.distance_to(middle)
			score = SCORE_GATE
			opening["kind"] = "gate"
			opening["label"] = str(marker.get("label", ""))
	var keys := [opening["a"], opening["b"]]
	keys.sort()
	for hint in exit_hints:
		var off := (hint["cell"] as Vector2).distance_to(middle)
		if hint["keys"] == keys and off <= EXIT_HINT_REACH:
			score += SCORE_EXIT_HINT + SCORE_PER_CELL_FROM_HINT * off
			opening["kind"] = "exit"
	var roads := 0
	for key: String in [opening["a"], opening["b"]]:
		var cells := corridor_cells(opening, key)
		var counts := {}
		for cell in cells:
			if key_at(cell) != key:
				return -INF
			if not is_blocked(cell):
				counts[level_at(cell)] = int(counts.get(level_at(cell), 0)) + 1
		var level := 0
		var level_count := -1
		for candidate: int in counts:
			if int(counts[candidate]) > level_count or (int(counts[candidate]) == level_count and candidate < level):
				level = candidate
				level_count = int(counts[candidate])
		opening["levels"][key] = level
		var reaches := false
		for cell in cells.slice(OPENING_CELLS):
			reaches = reaches or _main_ground(key).has(cell)
		if not reaches:
			score += SCORE_CUT_OFF
		for i in cells.size():
			var cell := cells[i]
			var kind := kind_at(cell)
			if i < OPENING_CELLS and ROADS.contains(kind):
				roads += 1
			if is_blocked(cell):
				score += SCORE_BLOCKED
			elif kind == "s":
				score += SCORE_SHALLOW
			elif kind == "f":
				score += SCORE_FOREST
			if not is_blocked(cell) and level_at(cell) != level:
				score += SCORE_OFF_LEVEL
			# A third region beside the corridor: the opening sits in a corner.
			for step in NEIGHBOURS:
				var near := key_at(cell + step)
				if near != "" and near != WorldMapData.NO_REGION and near != opening["a"] and near != opening["b"]:
					score += SCORE_NEAR_CORNER
		for beyond in corridor_cells(opening, key, CORRIDOR_CELLS + 1).slice(CORRIDOR_CELLS * OPENING_CELLS):
			if key_at(beyond) != key or is_blocked(beyond):
				score += SCORE_BLOCKED_BEYOND
		# The cells beside the opening along the border: the same regions, or it is at a stretch's end.
		var along := Vector2i(0, 1) if opening["line"] == "v" else Vector2i(1, 0)
		if key_at(cells[0] - along) != key or key_at(cells[OPENING_CELLS - 1] + along) != key:
			score += SCORE_NEAR_CORNER
	if roads > 0:
		score += SCORE_ROAD_CELL * roads
		if opening["kind"] == "path":
			opening["kind"] = "road"
	return score


## The biggest piece of region `key`'s walkable cells off its border band: cell -> true. Cells join their 4-neighbours
## on their level, and those a level lower or higher where a flight of stairs could go (the cell past
## the lower one, in line, is on its level), and ground on their level across up to
## MAX_BRIDGE_CELLS of deep water (a bridge). An opening whose corridor misses it would lead nowhere
## (an island in a lake, a ledge among lava pits).
func _main_ground(key: String) -> Dictionary:
	if _main_grounds.has(key):
		return _main_grounds[key]
	var seen := {}
	var best := {}
	for start in map.region_cells(key):
		if seen.has(start) or is_blocked(start) or not _inner(start):
			continue
		var piece := {start: true}
		seen[start] = true
		var queue: Array[Vector2i] = [start]
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			for step in NEIGHBOURS:
				var next := cell + step
				if is_blocked(next) and kind_at(next) == "w":
					# A bridge: over up to MAX_BRIDGE_CELLS of deep water to ground on the same level.
					var span := 1
					while span <= MAX_BRIDGE_CELLS and kind_at(cell + step * span) == "w":
						span += 1
					next = cell + step * span
					if span > MAX_BRIDGE_CELLS or level_at(next) != level_at(cell):
						continue
				elif not _joined(cell, step):
					continue
				if not seen.has(next) and key_at(next) == key and not is_blocked(next) and _inner(next):
					seen[next] = true
					piece[next] = true
					queue.append(next)
		if piece.size() > best.size():
			best = piece
	_main_grounds[key] = best
	return best


## True when the cells around `cell` are all its region's: no border band there.
func _inner(cell: Vector2i) -> bool:
	var key := key_at(cell)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if key_at(cell + Vector2i(dx, dy)) != key:
				return false
	return true


## True when a body could go from `cell` to its neighbour along `step`: the same level, or one level
## down or up with the next cell past the lower one on the lower level (room for the flight's foot).
func _joined(cell: Vector2i, step: Vector2i) -> bool:
	var next := cell + step
	var drop := level_at(cell) - level_at(next)
	if drop == 0:
		return true
	var foot := next + step if drop == 1 else cell - step
	var low := next if drop == 1 else cell
	return absi(drop) == 1 and key_at(foot) == key_at(cell) and not is_blocked(foot) and level_at(foot) == level_at(low)


## The middle of `opening` on the border line (cells).
func _middle(opening: Dictionary) -> Vector2:
	var at := Vector2(opening["at"])
	return at + (Vector2(0.0, 1.0) if opening["line"] == "v" else Vector2(1.0, 0.0))
