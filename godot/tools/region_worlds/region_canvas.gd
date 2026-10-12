extends RefCounted
## One placeholder region world as tiles and nodes (godot/tools/build_region_worlds.gd), built
## from the whole-map plan (region_plan.gd). The world covers the region's block of chunks; every
## sketch cell is `tiles_per_cell` x `tiles_per_cell` tiles. In order:
##
## 1. Cells: the region's own cells keep the plan's ground and level; its openings' corridors
##    become path on one level; the cells of the block that belong to other regions take the level
##    of the nearest own cell, so no cliff hangs at the border.
## 2. Roads (one cell wide) join the openings and the region's markers (towns, landmarks, dungeons,
##    caves, bosses, notes), and in the Wilds trails reach into every chunk, along the cheapest
##    walkable way (Dijkstra on cells): sketch paths are
##    cheap, forests and fords dear; never through deep water, mountains or pits, and never up a
##    step of 2 levels or more. A 1-level step is climbed by a flight of stairs two tiles wide (the
##    top it leaves on the higher cell, the flight on the lower one, its foot on the next); a crossing of
##    1-3 cells of deep water is a bridge (path, and the wooden footbridge over east-west ones).
##    An opening no road reaches gets its corridor on the level beyond it, then a flight where only
##    higher ground beside the flight was in the way, that ground lowered (`_carve_flights`); one
##    still cut off is a warning.
## 3. Ground from the terrain (TERRAIN_SOURCES; swamps get pools of shallow water), elevation tiles
##    from the levels, walls where the elevation hangs them (to keep trees, props and roads off).
## 4. The border: a band two tiles deep inside the whole outline, trees where it is walkable,
##    nothing where deep water, a wall, a mountain or a pit already blocks, open at the openings.
##    Trees on every forest cell, a few lone ones; the mix follows the theme (the Wilds by noise).
## 5. Fences around pits.
## 6. No soft-locks (`_close_pockets`): the tiles are walked with the game's movement rules (one
##    level on foot, stairs both ways, a ledge drop off any unfenced rim to lower ground) from the
##    openings; a pocket a drop leads into that has no way back to an opening is levelled into the
##    ground around it when small, else joined to the roads by a flight of stairs when one fits,
##    else fenced (stone, on the higher side of every rim that drops into it).
## 7. Dressing (boulders on rock and where the sketch's thin rock ridges were, crystals, broken
##    walls in the ruins and around any marker named a ruin, the village's houses) off roads,
##    corridors, water, walls and fences.
## 8. Travel: an exit at every opening into the neighbour's world (it arrives at the neighbour's
##    `arrive-from-<world>-<n>` marker; a hand-made world gets that marker when it gets its side of
##    the opening), an arrival marker three tiles inside it for the neighbour's exit, a
##    `player-entry-<edge>` marker per edge, the spawn.
## 9. The sketch's markers in the region as MapNote nodes.
##
## Everything is seeded by the region key, so a rebuild gives the same world.
##
## Owner: world (atlas).

const RegionPlan := preload("res://tools/region_worlds/region_plan.gd")

## Terrain sources (game/world/terrain_tileset.tres).
const AMBERLEAF := 0
const CAVERN_FLOOR := 1
const CRYSTAL_FLOOR := 2
const DEEP_WATER := 3
const FOREST_FLOOR := 4
const FOREST_MOSS := 5
const FROZEN := 6
const GRASS := 7
const SAND := 10
const WATER := 11
const TOWN_COBBLE := 19
## Sketch terrain kind -> ground source ("r" and "m" follow the theme: `_rock_source`; paths and
## roads `_road_source`: light sand as in A Link to the Past, dark earth where the ground is sand).
## There is no lava ground yet: a lava pit's floor is the dark cavern floor, so it reads as a crater.
const TERRAIN_SOURCES := {
	".": GRASS, "g": GRASS, "f": FOREST_MOSS, "t": TOWN_COBBLE, "b": SAND,
	"d": SAND, "s": WATER, "w": DEEP_WATER, "x": FOREST_MOSS, "n": FROZEN, "i": WATER,
	"l": CAVERN_FLOOR, "k": CRYSTAL_FLOOR, "c": CAVERN_FLOOR, "v": CAVERN_FLOOR,
}
## Ground sheets wrap every 19 tiles (the atlas coords are the tile's position modulo it).
const SHEET_TILES := 19
## Forest mixes (game/world/forest/forest_tileset.tres, row 0).
const MIXED := 0
const PINE := 1
const GREEN := 2
const LIGHT_GREEN := 3
const AUTUMN := 4
const DEAD := 5
const SNOW := 6
## Stairs (game/world/elevation/elevation_tileset.tres row 2, once an open landing: since
## 2026-10-11 the same flights as row 1) per direction.
const STAIRS_ROW := 2
const STAIRS_COLUMNS := {"s": 0, "sw": 1, "w": 2, "nw": 3, "n": 4, "ne": 5, "e": 6, "se": 7}
## The fence painted around pits (game/world/elevation/fences/fence_tileset.tres: stone).
const FENCE_STONE := Vector2i(3, 0)
## The edge of a world each way out leads through.
const EDGE_NAMES := {Vector2i.RIGHT: "east", Vector2i.LEFT: "west", Vector2i.DOWN: "south", Vector2i.UP: "north"}
const OPPOSITE_EDGES := {"east": "west", "west": "east", "south": "north", "north": "south"}
## The border band's depth and how far inside an opening the arrival markers stand (tiles); an exit
## trigger's depth (world units).
const BAND_TILES := 2
const ARRIVAL_TILES := 3
const EXIT_DEPTH := 32.0
## Markers roads lead to.
const ROAD_MARKERS: PackedStringArray = ["town", "landmark", "dungeon", "cave", "boss", "note"]
## How far (cells) from a marker its road may end when the marker's own cell takes no road.
const MARKER_REACH := 4
## Road costs per cell entered, by terrain kind (anything else costs 1).
const ROAD_COSTS := {
	"p": 0.6, "h": 0.6, "t": 0.6, "g": 1.0, ".": 1.0, "b": 1.1, "d": 1.1, "n": 1.1, "r": 1.3,
	"c": 1.3, "k": 1.3, "i": 1.4, "x": 1.6, "f": 2.5, "s": 3.0,
}
const STAIRS_COST := 2.0
## A flight that needs higher ground beside it lowered (`_carve_flights`): dear, the last resort.
const CARVE_COST := 30.0
const BRIDGE_COST := 2.5
const COVERED_ROW_COST := 2.0
const NEAR_BAND_COST := 0.3
const NEAR_PIT_COST := 1.0
const ROAD_ATTEMPTS := 6
const CARVE_ATTEMPTS := 2
## The id of a Wilds trail among the road targets (openings count from 0, markers are -1), and of
## a pocket's road (`_close_pockets`).
const TRAIL := -2
const POCKET := -3
## `_flight_room`: no flight there, a flight fits, a flight fits once higher ground beside it is
## lowered.
const NO_FLIGHT := 0
const FLIGHT_FITS := 1
const FLIGHT_IF_CARVED := 2
## Soft-locks (`_close_pockets`): how many times the pockets are looked for and fixed, and the most
## cells a pocket may have to be levelled into the ground around it.
const POCKET_PASSES := 6
const MAX_LEVELLED_CELLS := 6
## A pocket's level when its tiles lie on more than one.
const NO_POCKET_LEVEL := -100
const DIAGONALS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
## The footbridge (decoration-world-floor--wooden-footbridge.tscn): an east-west deck DECK_LENGTH
## long (about 4.5 tiles) standing on its bottom centre, the deck's middle DECK_RISE above it; one
## spans deep water up to FOOTBRIDGE_CELLS wide.
const FOOTBRIDGE := "res://game/scenes/objects/decoration-world-floor--wooden-footbridge.tscn"
const DECK_RISE := 77.0
const DECK_LENGTH := 288.0
const FOOTBRIDGE_CELLS := 2
## Dressing.
const ROCK_SCENE := "res://game/scenes/objects/rock-world-wall-solid--field-%02d.tscn"
## The plain boulders of the field rocks (the others carry ore or crystals).
const ROCK_VARIANTS: Array[int] = [13, 15, 17, 18, 19, 20, 21, 22, 23, 24]
const LARGE_ROCK_SCENES: PackedStringArray = [
	"res://game/scenes/objects/rock-world-wall-solid--large-02.tscn",
	"res://game/scenes/objects/rock-world-wall-solid--large-03.tscn",
]
const CRYSTAL_SCENE := "res://game/scenes/objects/crystal-cluster-wall--%02d.tscn"
const CRYSTAL_VARIANTS := 16
const WALL_SCENES := {
	"h": "res://game/scenes/objects/wall-stone-solid--horizontal-%02d.tscn",
	"v": "res://game/scenes/objects/wall-stone-solid--vertical-%02d.tscn",
}
const WALL_VARIANTS := {"h": [2, 8], "v": [1, 8]}
const HOUSE_SCENES: PackedStringArray = [
	"res://game/scenes/objects/house-world-solid--cottage-blue.tscn",
	"res://game/scenes/objects/house-world-solid.tscn",
	"res://game/scenes/objects/house-world-solid--forge-red.tscn",
	"res://game/scenes/objects/house-world-solid--house-mushroom.tscn",
]
## A house stands on its bottom centre over a HOUSE_TILES footprint (its collision, about 280 x 160
## units, fits inside), the house's front row on a road.
const HOUSE_TILES := Vector2i(5, 4)
const HOUSE_LIFT := 8.0
const MAX_HOUSES := 6
const HOUSE_REACH := 18
const ROCK_CHANCE := 0.04
## Where the sketch had rock the smoothing lowered (a thin ridge): a boulder now and then.
const LOWERED_ROCK_CHANCE := 0.2
const LARGE_ROCK_SHARE := 0.2
const MOUNTAIN_ROCK_CHANCE := 0.3
const CRYSTAL_CHANCE := 0.12
const ICE_CRYSTAL_CHANCE := 0.025
const LONE_TREE_CHANCE := 0.012
const SWAMP_TREE_CHANCE := 0.12
const SWAMP_POOL_LEVEL := 0.3
const RUIN_RINGS: Array[int] = [5, 9]
const MARKED_RUIN_RINGS: Array[int] = [4]
const RUIN_WALL_CHANCE := 0.7
const RUIN_RUBBLE_BEYOND := 5
const RUIN_RUBBLE_CHANCE := 0.015
const NOISE_FREQUENCY := 0.035

## Tile flags.
const OWN := 1
const ROAD := 2
const CORRIDOR := 4
const BAND := 8
const STAIRS := 16
const WET := 32
const BLOCKED := 64
const WALL := 128
const PROP := 256
const TREE := 512
## What keeps dressing off a tile.
const NOT_FREE := ROAD | CORRIDOR | BAND | STAIRS | WET | BLOCKED | WALL | PROP | TREE

var plan: RegionPlan
var key := ""
var world := ""
var theme := ""
var tile_size := 64
var per_cell := 2
## The region's block (cells of the whole map) and its size in cells and tiles.
var block := Rect2i()
var cells := Vector2i.ZERO
var size := Vector2i.ZERO
## Per cell of the block.
var kind := PackedByteArray()
var own := PackedByteArray()
var cell_level := PackedInt32Array()
var road := PackedByteArray()
var corridor := PackedByteArray()
var ring := PackedByteArray()
## Stairs flights: lower cell (block cells) -> direction down the flight ("s", "n", "e", "w").
var flights := {}
## Cells a flight stands on or leaves (the top behind it, its cell, its foot): no trees or props.
var flight_cells := {}
## Bridges: {cells (block cells of the deep water crossed), step (Vector2i)}.
var bridges: Array[Dictionary] = []
## Per tile of the block.
var ground := PackedInt32Array()
var level := PackedInt32Array()
var stairs := PackedInt32Array()
var trees := PackedInt32Array()
var fences := PackedByteArray()
var flags := PackedInt32Array()
## Nodes: {scene, position, name}; {name, rect (world units), target, entry, entry_marker, exit_id};
## {name, position}; edge -> position; {kind, label, notes, position}.
var props: Array[Dictionary] = []
var exits: Array[Dictionary] = []
var arrivals: Array[Dictionary] = []
var entries := {}
var notes: Array[Dictionary] = []
var spawn := Vector2.ZERO
var warnings := PackedStringArray()
## Soft-locks (`_close_pockets`): the pockets found at first and left at the end, roads with
## stairs that join one, cells levelled, tiles fenced.
var pockets_found := 0
var pockets_left := 0
var pocket_roads := 0
var levelled_cells := 0
var fenced_tiles := 0

var _rng := RandomNumberGenerator.new()
var _seed := 0
var _mix_noise := FastNoiseLite.new()
var _pool_noise := FastNoiseLite.new()
## Corridor levels changed from the plan's (`_plan_roads`): opening index -> level, and the levels
## tried per opening.
var _corridor_levels := {}
var _tried_levels := {}
## Cells given another level than the plan's (block cells -> level): pockets levelled, ground
## lowered for a flight (`_carve_flights`). Corridors still win.
var _levelled := {}
## While true, `_route` takes flights that need ground lowered (recorded in `_carves`).
var _relaxed := false
var _carves := {}
## Pockets to join by road (Array of block cell lists), and the cells already tried.
var _pocket_targets: Array[Array] = []
var _pocket_tried := {}
## Tiles fenced to close pockets (tile index -> true).
var _fenced := {}
var _cost := PackedFloat64Array()
var _previous := PackedInt32Array()
var _heap_cost := PackedFloat64Array()
var _heap_cell := PackedInt32Array()


func _init(source: RegionPlan, region_key: String) -> void:
	plan = source
	key = region_key
	var entry := plan.map.region(key)
	world = str(entry.get("world", ""))
	theme = str(entry.get("theme", ""))
	tile_size = plan.map.tile_size
	per_cell = plan.map.tiles_per_cell
	block = plan.map.chunk_rect_cells(plan.map.region_chunk_rect(key))
	cells = block.size
	size = cells * per_cell
	var seed_value := hash("region-worlds:" + key)
	_seed = seed_value
	_rng.seed = seed_value
	_mix_noise.seed = seed_value & 0x7fffffff
	_mix_noise.frequency = NOISE_FREQUENCY
	_pool_noise.seed = (seed_value >> 7) & 0x7fffffff
	_pool_noise.frequency = NOISE_FREQUENCY * 3.0


## Builds the region's own tiles and nodes (`backdrop` fills in the rest of its block).
func build() -> void:
	_read_cells()
	_plan_roads()
	_paint()
	_close_pockets()
	_place_bridges()
	_place_rocks_and_crystals()
	match theme:
		"ruins":
			_place_ruins(_marker_tile(["landmark", "dungeon", "note"]), RUIN_RINGS)
		"village":
			_place_houses()
	_place_marked_ruins()
	_place_travel()
	_place_notes()


## Paints the tiles of the block that belong to other regions with their ground and trees (from
## their canvases in `canvases`, key -> canvas, else the sketch's ground): seen past the border,
## never walked on. Their levels stay flat (`_read_cells`).
func backdrop(canvases: Dictionary) -> void:
	for ty in size.y:
		for tx in size.x:
			var index := ty * size.x + tx
			if flags[index] & OWN:
				continue
			var global_tile := block.position * per_cell + Vector2i(tx, ty)
			var global_cell := Vector2i(global_tile.x / per_cell, global_tile.y / per_cell)
			var other: Variant = canvases.get(plan.key_at(global_cell))
			if other != null:
				var there: Vector2i = global_tile - (other.block.position as Vector2i) * per_cell
				var there_index: int = there.y * (other.size.x as int) + there.x
				ground[index] = other.ground[there_index]
				trees[index] = other.trees[there_index]
			else:
				ground[index] = _source_of(plan.kind_at(global_cell))


## Counts for the summary.
func stats() -> Dictionary:
	var own_tiles := 0
	var tree_tiles := 0
	for index in flags.size():
		if flags[index] & OWN:
			own_tiles += 1
			if trees[index] >= 0:
				tree_tiles += 1
	return {
		"size": size, "tiles": own_tiles, "trees": tree_tiles, "openings": plan.openings_of(key).size(),
		"exits": exits.size(), "stairs": flights.size(), "bridges": bridges.size(), "props": props.size(),
		"pockets_found": pockets_found, "pockets_left": pockets_left, "pocket_roads": pocket_roads,
		"levelled_cells": levelled_cells, "fenced_tiles": fenced_tiles,
	}


# --- cells ----------------------------------------------------------------------------------

func _cell_index(cell: Vector2i) -> int:
	return cell.y * cells.x + cell.x


func _has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cells.x and cell.y < cells.y


func _tile_index(tile: Vector2i) -> int:
	return tile.y * size.x + tile.x


func _has_tile(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y


func _kind(cell: Vector2i) -> String:
	return String.chr(kind[_cell_index(cell)]) if _has_cell(cell) else ""


func _is_own(cell: Vector2i) -> bool:
	return _has_cell(cell) and own[_cell_index(cell)] == 1


func _level(cell: Vector2i) -> int:
	return cell_level[_cell_index(cell)]


func _read_cells() -> void:
	var count := cells.x * cells.y
	kind.resize(count)
	own.resize(count)
	cell_level.resize(count)
	road.resize(count)
	road.fill(0)
	corridor.resize(count)
	corridor.fill(0)
	ring.resize(count)
	ring.fill(0)
	for y in cells.y:
		for x in cells.x:
			var global_cell := block.position + Vector2i(x, y)
			var index := y * cells.x + x
			kind[index] = plan.kind_at(global_cell).unicode_at(0)
			own[index] = 1 if plan.key_at(global_cell) == key else 0
			cell_level[index] = plan.level_at(global_cell)
			if own[index] == 1 and _levelled.has(Vector2i(x, y)):
				cell_level[index] = int(_levelled[Vector2i(x, y)])
	var fixed := {}
	var openings := plan.openings_of(key)
	for opening_index in openings.size():
		var opening := openings[opening_index]
		var flat: int = _corridor_levels.get(opening_index, opening["levels"][key])
		for global_cell in plan.corridor_cells(opening, key):
			var cell := global_cell - block.position
			kind[_cell_index(cell)] = "p".unicode_at(0)
			cell_level[_cell_index(cell)] = flat
			corridor[_cell_index(cell)] = 1
		var other: String = opening["b"] if opening["a"] == key else opening["a"]
		for global_cell in plan.corridor_cells(opening, other):
			var cell := global_cell - block.position
			if _has_cell(cell):
				cell_level[_cell_index(cell)] = flat
				fixed[cell] = true
	# The rest of the block takes the level of the nearest own cell (or of the corridor it continues).
	var queue: Array[Vector2i] = []
	var reached := {}
	for y in cells.y:
		for x in cells.x:
			var cell := Vector2i(x, y)
			if _is_own(cell) or fixed.has(cell):
				queue.append(cell)
				reached[cell] = true
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step in RegionPlan.NEIGHBOURS:
			var next := cell + step
			if _has_cell(next) and not reached.has(next):
				reached[next] = true
				cell_level[_cell_index(next)] = cell_level[_cell_index(cell)]
				queue.append(next)
	# The outer ring of own cells (touching another region or the map's edge) holds the border band.
	for y in cells.y:
		for x in cells.x:
			var cell := Vector2i(x, y)
			if not _is_own(cell):
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var near := cell + Vector2i(dx, dy)
					if not _is_own(near) or not plan.map.has_cell(block.position + near):
						ring[_cell_index(cell)] = 1
	_fill_tile_levels()


func _fill_tile_levels() -> void:
	var count := size.x * size.y
	level.resize(count)
	flags.resize(count)
	for ty in size.y:
		for tx in size.x:
			var cell := Vector2i(tx / per_cell, ty / per_cell)
			level[ty * size.x + tx] = _level(cell)
			flags[ty * size.x + tx] = OWN if _is_own(cell) else 0
	_mark_walls()


## Flags the tiles a cliff wall covers: below an edge whose north tile is higher (level a) than the
## south one (level b), the wall covers a - b rows, unless a row of level l at depth d (from the
## edge) with d >= a - l hides it first (game/world/elevation/elevation_grid.gd).
func _mark_walls() -> void:
	for index in flags.size():
		flags[index] &= ~WALL
	for tx in size.x:
		for ty in range(1, size.y):
			var top := level[(ty - 1) * size.x + tx]
			var below := level[ty * size.x + tx]
			if top <= below:
				continue
			for depth in top - below:
				var row := ty + depth
				if row >= size.y or depth >= top - level[row * size.x + tx]:
					break
				flags[row * size.x + tx] |= WALL


## How many of the cell's tile rows a wall covers.
func _covered_rows(cell: Vector2i) -> int:
	var rows_covered := 0
	for dy in per_cell:
		if flags[_tile_index(cell * per_cell + Vector2i(0, dy))] & WALL:
			rows_covered += 1
	return rows_covered


# --- roads ----------------------------------------------------------------------------------

func _road_cell(cell: Vector2i) -> bool:
	if not _is_own(cell) or RegionPlan.BLOCKED.contains(_kind(cell)):
		return false
	var index := _cell_index(cell)
	if ring[index] == 1 and corridor[index] == 0:
		return false
	return _covered_rows(cell) < per_cell and not flights.has(cell)


func _road_cost(cell: Vector2i) -> float:
	var cost := float(ROAD_COSTS.get(_kind(cell), 1.0))
	if road[_cell_index(cell)] == 1:
		cost *= 0.5
	cost += COVERED_ROW_COST * _covered_rows(cell)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var near := cell + Vector2i(dx, dy)
			if not _has_cell(near):
				continue
			if ring[_cell_index(near)] == 1 and corridor[_cell_index(near)] == 0:
				cost += NEAR_BAND_COST
			if _level(near) < 0:
				cost += NEAR_PIT_COST
	return cost


## A flight from `top` (the top it leaves, a level above) down `step` onto the next cell, its foot on the
## one after: both on one level, nothing higher beside the flight or over it.
func _flight_fits(top: Vector2i, step: Vector2i) -> bool:
	return _flight_room(top, step) == FLIGHT_FITS


## Whether a flight from `top` down `step` fits (FLIGHT_FITS), would fit once the higher ground
## beside it or over it is lowered to the flight's foot (FLIGHT_IF_CARVED: every such cell is one
## of the region's own that may be lowered, `_carvable`), or not (NO_FLIGHT).
func _flight_room(top: Vector2i, step: Vector2i) -> int:
	var lower := top + step
	var foot := lower + step
	if not _road_cell(top) or not _road_cell(lower) or not _road_cell(foot):
		return NO_FLIGHT
	var low := _level(lower)
	if _level(top) != low + 1 or _level(foot) != low or road[_cell_index(lower)] == 1:
		return NO_FLIGHT
	var blockers := _flight_blockers(top, step)
	if blockers.is_empty():
		return FLIGHT_FITS
	for cell in blockers:
		if not _carvable(cell):
			return NO_FLIGHT
	return FLIGHT_IF_CARVED


## The cells higher than a flight's foot beside the flight (from `top` down `step`), beside its
## foot, or over them.
func _flight_blockers(top: Vector2i, step: Vector2i) -> Array[Vector2i]:
	var lower := top + step
	var foot := lower + step
	var low := _level(lower)
	var across := Vector2i(step.y, step.x)
	var around: Array[Vector2i] = [lower + across, lower - across, foot + across, foot - across]
	if step != Vector2i.DOWN:
		around.append(lower + Vector2i.UP)
	if step != Vector2i.UP:
		around.append(foot + Vector2i.UP)
	var out: Array[Vector2i] = []
	for cell in around:
		if _has_cell(cell) and _level(cell) > low and not out.has(cell):
			out.append(cell)
	return out


## True when `cell` may be lowered for a flight: one of the region's own cells, not an opening's
## corridor, a mountain, a flight's or a road's.
func _carvable(cell: Vector2i) -> bool:
	if not _is_own(cell) or corridor[_cell_index(cell)] == 1 or road[_cell_index(cell)] == 1:
		return false
	return _kind(cell) != "m" and not flight_cells.has(cell)


## The deep water cells a bridge from `from` along `step` crosses to reach road ground on the same
## level (1 to RegionPlan.MAX_BRIDGE_CELLS of them), [] when there is none.
func _bridge_from(from: Vector2i, step: Vector2i) -> Array[Vector2i]:
	var crossed: Array[Vector2i] = []
	if _kind(from) == "w":
		return crossed
	for i in range(1, RegionPlan.MAX_BRIDGE_CELLS + 2):
		var cell := from + step * i
		if not _is_own(cell):
			return []
		if _kind(cell) == "w":
			if ring[_cell_index(cell)] == 1 or i > RegionPlan.MAX_BRIDGE_CELLS:
				return []
			crossed.append(cell)
			continue
		if crossed.is_empty() or not _road_cell(cell) or _level(cell) != _level(from):
			return []
		return crossed
	return []


## Joins the openings and markers by roads. When an opening's corridor is cut off on its level (a
## pocket in a plateau), its corridor takes the level of the ground beyond it and the roads are
## planned again (up to ROAD_ATTEMPTS times); when that does not help, a flight goes where only
## higher ground beside it was in the way, that ground lowered (`_carve_flights`, CARVE_ATTEMPTS
## times). An opening still cut off is a warning: its exit would lead into a corner of the world.
func _plan_roads() -> void:
	var carved := 0
	for attempt in ROAD_ATTEMPTS:
		var missing := _join_targets()
		if missing.is_empty():
			break
		var releveled := false
		for opening_index: int in missing:
			releveled = _relevel_corridor(opening_index) or releveled
		if not releveled and carved < CARVE_ATTEMPTS:
			carved += 1
			releveled = _carve_flights()
		if not releveled or attempt == ROAD_ATTEMPTS - 1:
			for opening_index: int in missing:
				if opening_index < 0:
					_warn("no road reaches a marker")
				else:
					_warn_cut_off(plan.openings_of(key)[opening_index])
			break
		_read_cells()
	# A bridge's water takes its banks' level.
	for bridge in bridges:
		for cell: Vector2i in bridge["cells"]:
			cell_level[_cell_index(cell)] = int(bridge["level"])
	_fill_tile_levels()


## Plans the roads from scratch: the first opening's corridor (else the first marker) is the start,
## then the nearest target not joined yet, again and again; in the Wilds then a trail into every
## chunk no road crosses yet (to its open cell nearest the chunk's middle; one cut off by water or
## cliffs stays without). Returns the openings (indices in `plan.openings_of(key)`; -1 for a marker)
## no road reached; when none was reached at all, the start's opening too.
func _join_targets() -> Array[int]:
	road.fill(0)
	flights.clear()
	flight_cells.clear()
	bridges.clear()
	var openings := plan.openings_of(key)
	var network := {}
	var targets: Array[Array] = []
	var target_ids: Array[int] = []
	for i in openings.size():
		var cells_of: Array[Vector2i] = []
		for global_cell in plan.corridor_cells(openings[i], key):
			cells_of.append(global_cell - block.position)
		if i == 0:
			for cell in cells_of:
				network[cell] = true
		else:
			targets.append(cells_of)
			target_ids.append(i)
	for marker: Dictionary in plan.map.markers():
		var cell := Vector2i(int(marker.get("x", 0)), int(marker.get("y", 0))) - block.position
		if not _is_own(cell) or not ROAD_MARKERS.has(str(marker.get("type", ""))):
			continue
		var near := _cells_near(cell)
		if near.is_empty():
			_warn("no road reaches the marker '%s'" % marker.get("label", ""))
			continue
		if network.is_empty():
			for c in near:
				network[c] = true
		else:
			targets.append(near)
			target_ids.append(-1)
	var missing: Array[int] = []
	if network.is_empty():
		return missing
	for cell: Vector2i in network:
		road[_cell_index(cell)] = 1
	var total := targets.size()
	missing = _connect(network, targets, target_ids)
	if missing.size() == total and total > 0 and not openings.is_empty():
		missing.append(0)
	if theme == "wilds" and missing.is_empty():
		var trails: Array[Array] = []
		var trail_ids: Array[int] = []
		for chunk in plan.map.region_chunks(key):
			var trail := _chunk_trail(chunk)
			if not trail.is_empty():
				trails.append(trail)
				trail_ids.append(TRAIL)
		_connect(network, trails, trail_ids)
	# The pockets' roads (`_close_pockets`), one by one: one that finds no way misses only itself.
	pocket_roads = 0
	for target in _pocket_targets:
		var goal: Array[Vector2i] = []
		for cell: Vector2i in target:
			if _road_cell(cell):
				goal.append(cell)
		if goal.is_empty():
			continue
		var one: Array[Array] = [goal]
		var one_id: Array[int] = [POCKET]
		if _connect(network, one, one_id, false).is_empty():
			pocket_roads += 1
	return missing


## Joins `targets` (cell lists, with their ids) to `network` one by one, nearest first; a joined
## target's cells become road too unless `pave` is false (a pocket: only the road into it). Returns
## the ids of the targets no road reaches.
func _connect(network: Dictionary, targets: Array[Array], ids: Array[int], pave: bool = true) -> Array[int]:
	while not targets.is_empty():
		var touching := -1
		for i in targets.size():
			for cell: Vector2i in targets[i]:
				if network.has(cell):
					touching = i
		if touching >= 0:
			for cell: Vector2i in targets[touching]:
				if pave:
					network[cell] = true
					road[_cell_index(cell)] = 1
			targets.remove_at(touching)
			ids.remove_at(touching)
			continue
		var goal := {}
		for i in targets.size():
			for cell: Vector2i in targets[i]:
				goal[cell] = i
		var reached := _route(network, goal)
		if reached.is_empty():
			return ids.duplicate()
		var done: int = goal[reached[reached.size() - 1]]
		for cell: Vector2i in reached:
			network[cell] = true
			road[_cell_index(cell)] = 1
		for cell: Vector2i in targets[done]:
			if pave and not network.has(cell) and _road_cell(cell):
				network[cell] = true
				road[_cell_index(cell)] = 1
		targets.remove_at(done)
		ids.remove_at(done)
	return []


## The end of a trail into `chunk` (map chunk coordinates): its road cell nearest the chunk's middle,
## [] when a road already crosses the chunk or it has no room for one.
func _chunk_trail(chunk: Vector2i) -> Array[Vector2i]:
	var rect := plan.map.chunk_rect_cells(Rect2i(chunk, Vector2i.ONE))
	rect.position -= block.position
	var middle := Vector2(rect.get_center())
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not _has_cell(cell):
				continue
			if road[_cell_index(cell)] == 1:
				return []
			if _road_cell(cell) and _kind(cell) != "s" and Vector2(cell).distance_to(middle) < best_distance:
				best_distance = Vector2(cell).distance_to(middle)
				best = cell
	var out: Array[Vector2i] = []
	if best.x >= 0:
		out.append(best)
	return out


## Gives opening `opening_index`'s corridor the level most of the walkable cells just beyond it
## have, when that differs from its own and was not tried yet. True when it changed.
func _relevel_corridor(opening_index: int) -> bool:
	if opening_index < 0:
		return false
	var opening := plan.openings_of(key)[opening_index]
	var beyond := plan.corridor_cells(opening, key, RegionPlan.CORRIDOR_CELLS + 1).slice(RegionPlan.CORRIDOR_CELLS * RegionPlan.OPENING_CELLS)
	var counts := {}
	for global_cell in beyond:
		var cell: Vector2i = global_cell - block.position
		if _is_own(cell) and not RegionPlan.BLOCKED.contains(_kind(cell)):
			counts[_level(cell)] = int(counts.get(_level(cell), 0)) + 1
	var current: int = _corridor_levels.get(opening_index, opening["levels"][key])
	var best := current
	var best_count := 0
	for candidate: int in counts:
		if candidate != current and int(counts[candidate]) > best_count:
			best = candidate
			best_count = int(counts[candidate])
	var tried: Array = _tried_levels.get(opening_index, [current])
	if best == current or tried.has(best):
		return false
	tried.append(best)
	_tried_levels[opening_index] = tried
	_corridor_levels[opening_index] = best
	return true


## Tries harder to join what `_join_targets` could not: plans the roads again taking flights that
## fit once the higher ground beside them is lowered (at CARVE_COST each), and lowers that ground
## (`_levelled`) for the next plan. True when it lowered any.
func _carve_flights() -> bool:
	_relaxed = true
	_carves.clear()
	_join_targets()
	_relaxed = false
	for cell: Vector2i in _carves:
		_levelled[cell] = _carves[cell]
	return not _carves.is_empty()


func _warn(text: String) -> void:
	if not warnings.has(text):
		warnings.append(text)


## The warning for an opening no road joins: where it is, and what it means.
func _warn_cut_off(opening: Dictionary) -> void:
	var other: String = opening["b"] if opening["a"] == key else opening["a"]
	var place := opening_place(plan, opening, key)
	var tiles: Rect2i = place["tiles"]
	_warn("no road joins the opening to %s (%s edge, cell %s, tiles x %d-%d, y %d-%d): its exit leads into a part of %s cut off from the other openings; change the sketch there or move the opening" % [
			plan.map.region(other).get("world", other), place["edge"], plan.corridor_cells(opening, key)[0],
			tiles.position.x, tiles.end.x - 1, tiles.position.y, tiles.end.y - 1, world])


## The road cells around a marker: its own cell, else the nearest within MARKER_REACH.
func _cells_near(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _road_cell(cell):
		out.append(cell)
		return out
	var seen := {cell: 0}
	var queue: Array[Vector2i] = [cell]
	var head := 0
	var found_at := -1
	while head < queue.size():
		var here := queue[head]
		head += 1
		var distance: int = seen[here]
		if found_at >= 0 and distance > found_at:
			break
		if _road_cell(here):
			found_at = distance
			out.append(here)
			continue
		if distance >= MARKER_REACH:
			continue
		for step in RegionPlan.NEIGHBOURS:
			var next := here + step
			if _is_own(next) and not seen.has(next):
				seen[next] = distance + 1
				queue.append(next)
	return out


## The cheapest way from any `network` cell to any `goal` cell (Dijkstra on cells, stairs and
## bridges as single moves): its cells from the network outwards, ending on the goal; [] when none.
## Records the flights of stairs and the bridges it takes.
func _route(network: Dictionary, goal: Dictionary) -> Array[Vector2i]:
	var count := cells.x * cells.y
	_cost.resize(count)
	_cost.fill(INF)
	_previous.resize(count)
	_previous.fill(-1)
	var settled := PackedByteArray()
	settled.resize(count)
	settled.fill(0)
	_heap_cost.clear()
	_heap_cell.clear()
	for cell: Vector2i in network:
		_cost[_cell_index(cell)] = 0.0
		_push(0.0, _cell_index(cell))
	var found := -1
	while not _heap_cell.is_empty():
		var index := _pop()
		if settled[index] == 1:
			continue
		settled[index] = 1
		var here := _cost[index]
		var cell := Vector2i(index % cells.x, index / cells.x)
		if goal.has(cell) and not network.has(cell):
			found = index
			break
		for step in RegionPlan.NEIGHBOURS:
			var next := cell + step
			if _road_cell(next) and _level(next) == _level(cell):
				_relax(index, next, here + _road_cost(next))
			# Down a flight from here, or up one to here's level + 1.
			var down := _flight_room(cell, step)
			var up := _flight_room(cell + step * 2, -step)
			var room := FLIGHT_FITS if FLIGHT_FITS in [down, up] else maxi(down, up)
			if room == FLIGHT_FITS or (_relaxed and room == FLIGHT_IF_CARVED):
				_relax(index, cell + step * 2, here + _road_cost(cell + step) + _road_cost(cell + step * 2) + STAIRS_COST
						+ (CARVE_COST if room == FLIGHT_IF_CARVED else 0.0))
			var crossed := _bridge_from(cell, step)
			if not crossed.is_empty():
				var far := cell + step * (crossed.size() + 1)
				_relax(index, far, here + BRIDGE_COST * (crossed.size() + 1) + _road_cost(far))
	var out: Array[Vector2i] = []
	if found < 0:
		return out
	var index := found
	while index >= 0:
		var cell := Vector2i(index % cells.x, index / cells.x)
		var back := _previous[index]
		out.push_front(cell)
		if back >= 0:
			var from := Vector2i(back % cells.x, back / cells.x)
			var span := cell - from
			if absi(span.x) + absi(span.y) > 1:
				var step := Vector2i(signi(span.x), signi(span.y))
				var between: Array[Vector2i] = []
				var at := from + step
				while at != cell:
					between.append(at)
					at += step
				if _kind(between[0]) == "w":
					bridges.append({"cells": between, "step": step, "level": _level(from)})
				else:
					var top_cell := from if _level(from) > _level(cell) else cell
					var down := step if top_cell == from else -step
					if _relaxed and _flight_room(top_cell, down) == FLIGHT_IF_CARVED:
						for blocker in _flight_blockers(top_cell, down):
							_carves[blocker] = _level(top_cell + down)
					flights[top_cell + down] = _direction_name(down)
					for c in [top_cell, top_cell + down, top_cell + down * 2]:
						flight_cells[c] = true
				for c in between:
					out.push_front(c)
		index = back
	return out


func _relax(from: int, to: Vector2i, value: float) -> void:
	var index := _cell_index(to)
	if value < _cost[index]:
		_cost[index] = value
		_previous[index] = from
		_push(value, index)


## A binary heap of cells by cost (_heap_cost, _heap_cell side by side).
func _push(priority: float, index: int) -> void:
	_heap_cost.append(priority)
	_heap_cell.append(index)
	var i := _heap_cell.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if _heap_cost[parent] <= _heap_cost[i]:
			break
		_swap(parent, i)
		i = parent


## The cheapest cell, taken off the heap.
func _pop() -> int:
	var top := _heap_cell[0]
	var last := _heap_cell.size() - 1
	_swap(0, last)
	_heap_cost.resize(last)
	_heap_cell.resize(last)
	var i := 0
	while true:
		var smallest := i
		for child in [2 * i + 1, 2 * i + 2]:
			if child < last and _heap_cost[child] < _heap_cost[smallest]:
				smallest = child
		if smallest == i:
			break
		_swap(smallest, i)
		i = smallest
	return top


func _swap(a: int, b: int) -> void:
	var cost := _heap_cost[a]
	_heap_cost[a] = _heap_cost[b]
	_heap_cost[b] = cost
	var cell := _heap_cell[a]
	_heap_cell[a] = _heap_cell[b]
	_heap_cell[b] = cell


static func _direction_name(step: Vector2i) -> String:
	return {Vector2i.DOWN: "s", Vector2i.UP: "n", Vector2i.RIGHT: "e", Vector2i.LEFT: "w"}[step]


# --- ground, levels, trees ------------------------------------------------------------------

## Rock and badlands: the sketch's brown, as bare earth (red leaf litter in the volcano and the
## desert, snow in the frost, stone in the crystal caverns).
func _rock_source() -> int:
	match theme:
		"volcano", "desert":
			return AMBERLEAF
		"frost":
			return FROZEN
		"crystal":
			return CAVERN_FLOOR
	return FOREST_FLOOR


## Roads, paths, bridges and the openings' corridors: light sand, dark earth in the desert.
func _road_source() -> int:
	return FOREST_FLOOR if theme == "desert" else SAND


func _source_of(terrain_kind: String) -> int:
	if terrain_kind == "r":
		return _rock_source()
	if terrain_kind == "p" or terrain_kind == "h":
		return _road_source()
	if terrain_kind == "m":
		return FROZEN if theme == "frost" else (AMBERLEAF if theme == "volcano" else CAVERN_FLOOR)
	return int(TERRAIN_SOURCES.get(terrain_kind, GRASS))


## Paints the tiles from the cells and the roads: ground, levels and stairs, the band and the trees,
## the fences (the same trees every time: the random numbers start over).
func _paint() -> void:
	_rng.seed = _seed
	_paint_ground()
	_paint_levels()
	_paint_band_and_trees()
	_paint_fences()


func _paint_ground() -> void:
	var count := size.x * size.y
	ground.resize(count)
	ground.fill(-1)
	var bridge_cells := {}
	for bridge in bridges:
		for cell: Vector2i in bridge["cells"]:
			bridge_cells[cell] = true
	for cy in cells.y:
		for cx in cells.x:
			var cell := Vector2i(cx, cy)
			if not _is_own(cell):
				continue
			var terrain_kind := _kind(cell)
			var source := _source_of(terrain_kind)
			var on_road := road[_cell_index(cell)] == 1 or corridor[_cell_index(cell)] == 1
			if bridge_cells.has(cell) or (on_road and terrain_kind != "t" and terrain_kind != "s"):
				source = _road_source()
			for dy in per_cell:
				for dx in per_cell:
					var tile := cell * per_cell + Vector2i(dx, dy)
					var index := _tile_index(tile)
					var here := source
					if terrain_kind == "x" and not on_road and ring[_cell_index(cell)] == 0 \
							and _pool_noise.get_noise_2d(tile.x + block.position.x * per_cell, tile.y + block.position.y * per_cell) > SWAMP_POOL_LEVEL:
						here = WATER
					ground[index] = here
					if on_road or bridge_cells.has(cell):
						flags[index] |= ROAD
					if corridor[_cell_index(cell)] == 1:
						flags[index] |= CORRIDOR
					if here == WATER or here == DEEP_WATER:
						flags[index] |= WET
					if here == DEEP_WATER or terrain_kind == "m" or _level(cell) < 0:
						flags[index] |= BLOCKED


func _paint_levels() -> void:
	stairs.resize(size.x * size.y)
	stairs.fill(-1)
	for lower: Vector2i in flights:
		var direction: String = flights[lower]
		var step: Vector2i = {"s": Vector2i.DOWN, "n": Vector2i.UP, "e": Vector2i.RIGHT, "w": Vector2i.LEFT}[direction]
		# The first tiles past the rim, on the lower side: the two of the lower cell next to the top.
		for i in per_cell:
			var tile := lower * per_cell
			match direction:
				"s":
					tile += Vector2i(i, 0)
				"n":
					tile += Vector2i(i, per_cell - 1)
				"e":
					tile += Vector2i(0, i)
				"w":
					tile += Vector2i(per_cell - 1, i)
			stairs[_tile_index(tile)] = int(STAIRS_COLUMNS[direction])
		for c: Vector2i in [lower - step, lower, lower + step]:
			for dy in per_cell:
				for dx in per_cell:
					flags[_tile_index(c * per_cell + Vector2i(dx, dy))] |= STAIRS


## The forest mix of a tree at `tile` (block tiles): the theme's, the Wilds' and swamps' by noise.
func _mix_at(tile: Vector2i) -> int:
	var value := _mix_noise.get_noise_2d(tile.x + block.position.x * per_cell, tile.y + block.position.y * per_cell)
	match theme:
		"wilds":
			if value < -0.2:
				return GREEN
			if value < 0.05:
				return MIXED
			if value < 0.25:
				return LIGHT_GREEN
			return AUTUMN
		"forest", "meadow":
			return GREEN if value < 0.0 else MIXED
		"village":
			return LIGHT_GREEN
		"ruins":
			return MIXED
		"crystal":
			return PINE
		"frost":
			return SNOW
		"volcano", "desert":
			return DEAD
		"swamp":
			return DEAD if value < 0.0 else GREEN
	return GREEN


func _paint_band_and_trees() -> void:
	var count := size.x * size.y
	trees.resize(count)
	trees.fill(-1)
	for ty in size.y:
		for tx in size.x:
			var tile := Vector2i(tx, ty)
			var index := ty * size.x + tx
			if not flags[index] & OWN:
				continue
			# The band: tiles within BAND_TILES of a tile that is not the region's (or off the world).
			var in_band := false
			for dy in range(-BAND_TILES, BAND_TILES + 1):
				for dx in range(-BAND_TILES, BAND_TILES + 1):
					var near := tile + Vector2i(dx, dy)
					if not _has_tile(near) or (flags[_tile_index(near)] & OWN) == 0:
						in_band = true
			var cell := Vector2i(tx / per_cell, ty / per_cell)
			if in_band:
				flags[index] |= BAND
				if (flags[index] & (CORRIDOR | BLOCKED | WALL)) != 0:
					continue
				if ground[index] == WATER:
					# Shallow water in the band deepens, so nobody wades past the border.
					ground[index] = DEEP_WATER
					flags[index] |= BLOCKED
					continue
				_plant(index, tile)
				continue
			if (flags[index] & (CORRIDOR | ROAD | STAIRS | BLOCKED | WALL | WET)) != 0 or flight_cells.has(cell):
				continue
			var terrain_kind := _kind(cell)
			if terrain_kind == "f" and theme != "desert":
				_plant(index, tile)
			elif terrain_kind == "x" and _rng.randf() < SWAMP_TREE_CHANCE:
				_plant(index, tile)
			elif (terrain_kind == "g" or terrain_kind == ".") and theme != "desert" and _rng.randf() < LONE_TREE_CHANCE \
					and not _near_flag(tile, ROAD | CORRIDOR | STAIRS, 1):
				_plant(index, tile)


func _plant(index: int, tile: Vector2i) -> void:
	trees[index] = _mix_at(tile)
	flags[index] |= TREE


## True when a tile within `reach` of `tile` has any of `mask`.
func _near_flag(tile: Vector2i, mask: int, reach: int) -> bool:
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var near := tile + Vector2i(dx, dy)
			if _has_tile(near) and flags[_tile_index(near)] & mask:
				return true
	return false


## Fences on the ground around pits, so nobody drops into the lava or the abyss, and on the rims
## that would drop into a pocket with no way back (`_fenced`, `_close_pockets`).
func _paint_fences() -> void:
	fences.resize(size.x * size.y)
	fences.fill(0)
	for ty in size.y:
		for tx in size.x:
			var index := ty * size.x + tx
			if not flags[index] & OWN or level[index] < 0 or flags[index] & WALL:
				continue
			if _fenced.has(index):
				fences[index] = 1
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var near := Vector2i(tx + dx, ty + dy)
					if _has_tile(near) and level[_tile_index(near)] < 0:
						fences[index] = 1


# --- soft-locks -----------------------------------------------------------------------------

## Makes sure every place a player can reach from an opening leads back to one: walks the tiles as
## the game moves the slime (`_find_pockets`) and closes each pocket with no way back, then looks
## again (POCKET_PASSES times at most): a small one is levelled into the ground around it
## (`_level_pocket`), else a road with stairs joins it (`_pocket_road`; once), else its rims are
## fenced (`_fence_pocket`), as are those over a drop that lands only in trees (a forest at a
## cliff's foot) or off the region. The roads and the tiles are planned and painted again after a
## change.
func _close_pockets() -> void:
	var pockets := _find_pockets()
	pockets_found = pockets.size()
	for pass_index in POCKET_PASSES:
		if pockets.is_empty():
			break
		var replan := false
		var fenced := false
		for pocket in pockets:
			if int(pocket["open"]) > 0 and (_level_pocket(pocket) or _pocket_road(pocket)):
				replan = true
			else:
				_fence_pocket(pocket)
				fenced = true
		if replan:
			_read_cells()
			_plan_roads()
			_paint()
		elif fenced:
			_paint_fences()
		pockets = _find_pockets()
	pockets_left = pockets.size()
	fenced_tiles = _fenced.size()
	for pocket in pockets:
		var box: Rect2i = pocket["box"]
		_warn("a drop leads into %d tiles with no way back to an opening (tiles x %d-%d, y %d-%d)" % [
				(pocket["nodes"] as Dictionary).size(), box.position.x, box.end.x - 1, box.position.y, box.end.y - 1])


## Raises a small pocket (at most MAX_LEVELLED_CELLS cells, on one level, off the border band, not
## levelled before, whose cells hold nothing else walkable on its level, and at least half of the
## cells around it higher) to the level most of the higher cells around it have. True when it did.
func _level_pocket(pocket: Dictionary) -> bool:
	var pocket_cells: Dictionary = pocket["cells"]
	if pocket_cells.is_empty() or pocket_cells.size() > MAX_LEVELLED_CELLS or int(pocket["level"]) == NO_POCKET_LEVEL:
		return false
	var low := int(pocket["level"])
	var nodes: Dictionary = pocket["nodes"]
	for cell: Vector2i in pocket_cells:
		var cell_index := _cell_index(cell)
		if corridor[cell_index] == 1 or ring[cell_index] == 1 or _levelled.has(cell) or flight_cells.has(cell):
			return false
		# Another walkable tile of the cell on the pocket's level: the cell is more than the pocket.
		for dy in per_cell:
			for dx in per_cell:
				var index := _tile_index(cell * per_cell + Vector2i(dx, dy))
				if not nodes.has(index) and level[index] == low and _walkable_tile(index) and not flags[index] & TREE:
					return false
	var counts := {}
	var around := {}
	for cell: Vector2i in pocket_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var near := cell + Vector2i(dx, dy)
				if _is_own(near) and not pocket_cells.has(near) and not around.has(near):
					around[near] = true
					if _level(near) > low:
						counts[_level(near)] = int(counts.get(_level(near), 0)) + 1
	var higher := 0
	for candidate: int in counts:
		higher += int(counts[candidate])
	if higher * 2 < around.size():
		return false
	var best := low
	var best_count := 0
	for candidate: int in counts:
		if int(counts[candidate]) > best_count or (int(counts[candidate]) == best_count and candidate < best):
			best = candidate
			best_count = int(counts[candidate])
	if best == low:
		return false
	for cell: Vector2i in pocket_cells:
		_levelled[cell] = best
	levelled_cells += pocket_cells.size()
	return true


## Adds a road to the pocket (its cells a road may take) for the next plan, unless one was tried for
## any of its cells already. True when it did.
func _pocket_road(pocket: Dictionary) -> bool:
	var target: Array[Vector2i] = []
	for cell: Vector2i in pocket["cells"]:
		if _pocket_tried.has(cell):
			return false
		if _road_cell(cell):
			target.append(cell)
	if target.is_empty():
		return false
	for cell: Vector2i in pocket["cells"]:
		_pocket_tried[cell] = true
	_pocket_targets.append(target)
	return true


## Fences every rim a drop into the pocket goes over (its tile, on the higher side).
func _fence_pocket(pocket: Dictionary) -> void:
	for from: int in pocket["sources"]:
		_fenced[from] = true


## The pockets: walks the tiles from the openings' corridors as the game moves the slime
## (`_walk_steps`, `_drops`) and gathers the tiles reached that cannot get back to a corridor, by
## the tiles they touch. Each: {nodes (node -> true), cells (the region's own block cells they
## lie in), sources (the tiles the drops into it leave from), level (theirs when they share one,
## else NO_POCKET_LEVEL), box (Rect2i, tiles), open (how many of them are the region's tiles
## without a tree, off a strip)}. A node is a tile index, plus the tile count for the upper level
## of a flight's steps, plus twice the tile count for the strip behind a back rim.
func _find_pockets() -> Array[Dictionary]:
	var count := size.x * size.y
	var starts: Array[int] = []
	var exit_tiles := {}
	for opening in plan.openings_of(key):
		var order := 0
		for global_cell in plan.corridor_cells(opening, key):
			var cell: Vector2i = global_cell - block.position
			for dy in per_cell:
				for dx in per_cell:
					var index := _tile_index(cell * per_cell + Vector2i(dx, dy))
					if not _walkable_tile(index):
						continue
					starts.append(index)
					# The cells on the border hold the exit: the way out.
					if order < RegionPlan.OPENING_CELLS:
						exit_tiles[index] = true
			order += 1
	if starts.is_empty():
		return []
	var drops_from := {}
	var drops_to := {}
	for index in count:
		if not _walkable_tile(index) or flags[index] & TREE or not flags[index] & OWN or stairs[index] >= 0 \
				or fences[index] == 1:
			continue
		for target in _drops(index):
			if not drops_from.has(index):
				drops_from[index] = []
			(drops_from[index] as Array).append(target)
			if not drops_to.has(target):
				drops_to[target] = []
			(drops_to[target] as Array).append(index)
	var ahead := _reach(starts, drops_from, exit_tiles, false)
	var back := _reach(starts, drops_to, {}, true)
	var stuck := {}
	for node: int in ahead:
		if not back.has(node):
			stuck[node] = true
	var pockets: Array[Dictionary] = []
	var seen := {}
	for first: int in stuck:
		if seen.has(first):
			continue
		var pocket := {"nodes": {}, "cells": {}, "sources": {}, "level": _node_level(first), "box": Rect2i(), "open": 0}
		var queue: Array[int] = [first]
		seen[first] = true
		var head := 0
		while head < queue.size():
			var node := queue[head]
			head += 1
			pocket["nodes"][node] = true
			var index := node % count
			var tile := Vector2i(index % size.x, index / size.x)
			pocket["box"] = Rect2i(tile, Vector2i.ONE) if head == 1 else (pocket["box"] as Rect2i).expand(tile).expand(tile + Vector2i.ONE)
			if _node_level(node) != int(pocket["level"]):
				pocket["level"] = NO_POCKET_LEVEL
			var cell := Vector2i(tile.x / per_cell, tile.y / per_cell)
			# A strip lies on the higher tile: its cell is not the pocket's.
			if _is_own(cell) and node < 2 * count:
				pocket["cells"][cell] = true
				if not flags[index] & TREE:
					pocket["open"] = int(pocket["open"]) + 1
			for from: int in drops_to.get(node, []):
				pocket["sources"][from] = true
			var touching := _walk_steps(node)
			touching.append_array(_walk_steps(node, true))
			for next in touching:
				if stuck.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)
				elif not stuck.has(next) and ahead.has(next):
					# A tree a drop lands on, that the slime may leave into the pocket: its drops too.
					for from: int in drops_to.get(next, []):
						pocket["sources"][from] = true
		pockets.append(pocket)
	return pockets


## The nodes reachable from `starts` on foot and on stairs and by the drops in `drops` (node ->
## nodes), not going on from the nodes in `stop`; `backward`: the nodes `starts` are reachable from
## (`drops` then the drops into each node).
func _reach(starts: Array[int], drops: Dictionary, stop: Dictionary, backward: bool) -> Dictionary:
	var seen := {}
	var queue: Array[int] = []
	for node in starts:
		if not seen.has(node):
			seen[node] = true
			queue.append(node)
	var head := 0
	while head < queue.size():
		var node := queue[head]
		head += 1
		if stop.has(node):
			continue
		var next_nodes := _walk_steps(node, backward)
		next_nodes.append_array(drops.get(node, []))
		for next: int in next_nodes:
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


## A tile the slime can stand on at its level: not under a wall (a flight's steps excepted) and not
## deep water. Trees stand on such tiles (they block walking onto them, not landing). The region's
## own tiles and the rest of the block alike (the rest is never walked: a drop there is lost).
func _walkable_tile(index: int) -> bool:
	if stairs[index] >= 0:
		return true
	if flags[index] & WALL:
		return false
	if flags[index] & OWN:
		return ground[index] != DEEP_WATER
	var tile := Vector2i(index % size.x, index / size.x)
	return plan.kind_at(block.position + Vector2i(tile.x / per_cell, tile.y / per_cell)) != "w"


## The level of a node: its tile's; the upper level of a flight's steps for the second node of a
## tile; the lower ground's behind a back rim for the third (`_strip_level`).
func _node_level(node: int) -> int:
	var count := size.x * size.y
	var index := node % count
	if node >= 2 * count:
		return _strip_level(index)
	return level[index] + (1 if node >= count else 0)


## The level of the strip behind higher ground on tile `index` (Elevation: the lower ground north
## of a back rim reaches half a tile into the top, walkable by its level), NO_POCKET_LEVEL when
## the tile has none: a top (no wall, stairs or tree on it) whose north neighbour is lower and no
## wall.
func _strip_level(index: int) -> int:
	if index < size.x or flags[index] & (WALL | TREE) or stairs[index] >= 0:
		return NO_POCKET_LEVEL
	var north := index - size.x
	if flags[north] & WALL or stairs[north] >= 0 or level[north] >= level[index]:
		return NO_POCKET_LEVEL
	return level[north]


## The nodes a body at `node` walks to (`backward`: walks from): the 4 neighbours on its level, the
## region's own and walkable, never onto a tree (a body that landed on one walks off it), a flight's
## steps on both its levels, the other level of the same steps, and the strips behind higher ground
## on its level (into one from the north, along one east and west).
func _walk_steps(node: int, backward: bool = false) -> Array[int]:
	var count := size.x * size.y
	var index := node % count
	var out: Array[int] = []
	if not flags[index] & OWN or (backward and flags[index] & TREE):
		return out
	var tile := Vector2i(index % size.x, index / size.x)
	var here := _node_level(node)
	var strip := node >= 2 * count
	if stairs[index] >= 0:
		out.append(index + count if node < count else index)
	for step in RegionPlan.NEIGHBOURS:
		var near := tile + step
		if not _has_tile(near):
			continue
		var near_index := _tile_index(near)
		if not flags[near_index] & OWN:
			continue
		# The strip behind the neighbour's rim, entered from the north or along it.
		if step != Vector2i.UP and not (strip and step == Vector2i.DOWN) and _strip_level(near_index) == here:
			out.append(near_index + 2 * count)
			continue
		if strip and step == Vector2i.DOWN:
			continue
		if not _walkable_tile(near_index) or (not backward and flags[near_index] & TREE):
			continue
		if level[near_index] == here:
			out.append(near_index)
		elif stairs[near_index] >= 0 and level[near_index] + 1 == here:
			out.append(near_index + count)
	return out


## Where the slime lands going over a rim from tile `index` (not on stairs, unfenced), along the 8
## ways, as Elevation.ledge_below and drop_target judge it: a rim when what lies past it is lower
## ground (a lower top, or a wall that hangs from this level or lower: over it to its foot), and
## nothing beside it on the way is higher ground, stairs or the map's border; the landing out past
## the rim and one tile lower on screen per level dropped (a wall's foot already is), else the
## nearest spot up towards the rim, else one tile further out (`_landing`: a strip behind a back
## rim too). The landing's node for each way.
func _drops(index: int) -> Array[int]:
	var out: Array[int] = []
	var tile := Vector2i(index % size.x, index / size.x)
	var here := level[index]
	var ways: Array[Vector2i] = []
	ways.append_array(RegionPlan.NEIGHBOURS)
	ways.append_array(DIAGONALS)
	for way in ways:
		if way.x != 0 and way.y != 0 and (not _probe_passes(tile + Vector2i(way.x, 0), here) or not _probe_passes(tile + Vector2i(0, way.y), here)):
			continue
		var past := tile + way
		var below := _ground_past(past, here)
		if below.x < 0:
			continue
		var lower := level[_tile_index(below)]
		if lower >= here:
			continue
		var shift := 0 if below != past else here - lower
		var landing := -1
		for base: Vector2i in [below, below + way]:
			for rise in range(shift + 2):
				landing = _landing(base + Vector2i(0, shift - rise), lower)
				if landing >= 0:
					break
			if landing >= 0:
				break
		if landing >= 0 and not out.has(landing):
			out.append(landing)
	return out


## The ground a probe past a rim at `tile` finds for a body on `here`: the tile itself, or the foot
## of the wall there when the wall hangs from `here` or lower; (-1, -1) for higher ground (a wall
## going up), stairs or the map's border.
func _ground_past(tile: Vector2i, here: int) -> Vector2i:
	var none := Vector2i(-1, -1)
	if not _has_tile(tile) or stairs[_tile_index(tile)] >= 0:
		return none
	if not flags[_tile_index(tile)] & WALL:
		return tile
	var top := tile
	while top.y > 0 and flags[_tile_index(top)] & WALL:
		top.y -= 1
	if level[_tile_index(top)] > here:
		return none
	var foot := tile
	while _has_tile(foot) and flags[_tile_index(foot)] & WALL and stairs[_tile_index(foot)] < 0:
		foot.y += 1
	return foot if _has_tile(foot) else none


## True when a probe at `tile` lets a ledge be a ledge for a body on `here`: ground it walks on, or
## lower ground.
func _probe_passes(tile: Vector2i, here: int) -> bool:
	var below := _ground_past(tile, here)
	return below.x >= 0 and level[_tile_index(below)] <= here


## The node the slime lands on at `tile` on `lower`: the tile, when it is of that level and the
## slime can stand on it, else the strip behind its back rim on that level (off a back rim, the
## landing is that strip), else -1.
func _landing(tile: Vector2i, lower: int) -> int:
	if not _has_tile(tile):
		return -1
	var index := _tile_index(tile)
	if level[index] == lower and stairs[index] < 0 and _walkable_tile(index):
		return index
	if _strip_level(index) == lower:
		return index + 2 * size.x * size.y
	return -1


# --- props ----------------------------------------------------------------------------------

## True when the tiles of `rect` are own, free (NOT_FREE) and on one level, and the row below them
## is no higher (a prop never stands in the strip behind a hill).
func _free(rect: Rect2i) -> bool:
	var first := -100
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			var tile := Vector2i(tx, ty)
			if not _has_tile(tile):
				return false
			var index := _tile_index(tile)
			if not flags[index] & OWN or flags[index] & NOT_FREE or fences[index] == 1:
				return false
			if first == -100:
				first = level[index]
			elif level[index] != first:
				return false
	for tx in range(rect.position.x, rect.end.x):
		var below := Vector2i(tx, rect.end.y)
		if _has_tile(below) and level[_tile_index(below)] > first:
			return false
	return true


func _take(rect: Rect2i) -> void:
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			flags[_tile_index(Vector2i(tx, ty))] |= PROP


func _add_prop(scene: String, position: Vector2, prop_name: String) -> void:
	props.append({"scene": scene, "position": position, "name": "%s-%03d" % [prop_name, props.size() + 1]})


## The footbridge over every east-west bridge: one deck over up to FOOTBRIDGE_CELLS of water, two
## overlapping decks (a pier in the middle) over more.
func _place_bridges() -> void:
	for bridge in bridges:
		var crossed: Array = bridge["cells"]
		var step: Vector2i = bridge["step"]
		if step.y != 0:
			continue
		var first: Vector2i = crossed[0]
		var last: Vector2i = crossed[crossed.size() - 1]
		var middle := (Vector2(first + last) + Vector2.ONE) * 0.5 * per_cell * tile_size + Vector2(0.0, DECK_RISE)
		if crossed.size() <= FOOTBRIDGE_CELLS:
			_add_prop(FOOTBRIDGE, middle, "footbridge")
			continue
		var half := (crossed.size() * per_cell * tile_size - DECK_LENGTH) * 0.5
		_add_prop(FOOTBRIDGE, middle - Vector2(half, 0.0), "footbridge")
		_add_prop(FOOTBRIDGE, middle + Vector2(half, 0.0), "footbridge")


## A field rock tile by tile of rock (more around mountains), a crystal cluster on crystal ground.
func _place_rocks_and_crystals() -> void:
	for cy in cells.y:
		for cx in cells.x:
			var cell := Vector2i(cx, cy)
			if not _is_own(cell):
				continue
			var terrain_kind := _kind(cell)
			var chance := 0.0
			var crystal := false
			if terrain_kind == "r":
				chance = ROCK_CHANCE
			elif plan.lowered_rock.has(block.position + cell):
				chance = LOWERED_ROCK_CHANCE
			elif terrain_kind == "k":
				chance = CRYSTAL_CHANCE
				crystal = true
			elif terrain_kind == "i":
				chance = ICE_CRYSTAL_CHANCE
				crystal = true
			if not crystal and terrain_kind != "m":
				for step in RegionPlan.NEIGHBOURS:
					if _kind(cell + step) == "m":
						chance = MOUNTAIN_ROCK_CHANCE
			if chance <= 0.0 or _rng.randf() >= chance:
				continue
			var tile := cell * per_cell + Vector2i(_rng.randi_range(0, per_cell - 1), _rng.randi_range(0, per_cell - 1))
			var foot := (Vector2(tile) + Vector2(0.5, 1.0)) * tile_size - Vector2(0.0, 8.0)
			if crystal:
				if _free(Rect2i(tile, Vector2i.ONE)):
					_take(Rect2i(tile, Vector2i.ONE))
					_add_prop(CRYSTAL_SCENE % _rng.randi_range(1, CRYSTAL_VARIANTS), foot, "crystal")
			elif _rng.randf() < LARGE_ROCK_SHARE and _free(Rect2i(tile, Vector2i(2, 1))):
				_take(Rect2i(tile, Vector2i(2, 1)))
				_add_prop(LARGE_ROCK_SCENES[_rng.randi_range(0, LARGE_ROCK_SCENES.size() - 1)], foot + Vector2(tile_size * 0.5, 0.0), "boulder")
			elif _free(Rect2i(tile, Vector2i.ONE)):
				_take(Rect2i(tile, Vector2i.ONE))
				_add_prop(ROCK_SCENE % ROCK_VARIANTS[_rng.randi_range(0, ROCK_VARIANTS.size() - 1)], foot, "rock")


## The first marker of the region of one of `types`, as its tile (block tiles), or (-1, -1).
func _marker_tile(types: PackedStringArray) -> Vector2i:
	for wanted in types:
		for marker: Dictionary in plan.map.markers():
			var cell := Vector2i(int(marker.get("x", 0)), int(marker.get("y", 0))) - block.position
			if str(marker.get("type", "")) == wanted and _is_own(cell):
				return cell * per_cell + Vector2i(per_cell / 2, per_cell / 2)
	return Vector2i(-1, -1)


## Broken stone walls in rings (`rings`: their distances from it, tiles) around `centre` (block
## tiles; none when x < 0), with gaps where roads cross, and rubble around.
func _place_ruins(centre: Vector2i, rings: Array[int]) -> void:
	if centre.x < 0:
		return
	for radius in rings:
		for i in range(-radius, radius + 1):
			for side: Array in [[Vector2i(i, -radius), "h"], [Vector2i(i, radius), "h"], [Vector2i(-radius, i), "v"], [Vector2i(radius, i), "v"]]:
				var tile: Vector2i = centre + side[0]
				if _rng.randf() < RUIN_WALL_CHANCE:
					_place_wall_piece(tile, side[1])
	var reach: int = rings.max() + RUIN_RUBBLE_BEYOND
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if _rng.randf() < RUIN_RUBBLE_CHANCE:
				_place_wall_piece(centre + Vector2i(dx, dy), "h" if _rng.randf() < 0.5 else "v")


## A ring of broken walls around every marker of the region whose label speaks of a ruin (outside
## the ruins, which have their own).
func _place_marked_ruins() -> void:
	if theme == "ruins":
		return
	for marker: Dictionary in plan.map.markers():
		var cell := Vector2i(int(marker.get("x", 0)), int(marker.get("y", 0))) - block.position
		if _is_own(cell) and str(marker.get("label", "")).to_lower().contains("ruin"):
			_place_ruins(cell * per_cell + Vector2i(per_cell / 2, per_cell / 2), MARKED_RUIN_RINGS)


func _place_wall_piece(tile: Vector2i, along: String) -> void:
	if not _free(Rect2i(tile, Vector2i.ONE)):
		return
	_take(Rect2i(tile, Vector2i.ONE))
	var variants: Array = WALL_VARIANTS[along]
	var scene := str(WALL_SCENES[along]) % _rng.randi_range(int(variants[0]), int(variants[1]))
	_add_prop(scene, (Vector2(tile) + Vector2(0.5, 1.0)) * tile_size, "ruin-wall")


## Houses around the village's town (or its note), each with its front on a road or the paving.
func _place_houses() -> void:
	var centre := _marker_tile(["town", "note", "landmark"])
	if centre.x < 0:
		return
	var candidates: Array[Array] = []
	for dy in range(-HOUSE_REACH, HOUSE_REACH + 1):
		for dx in range(-HOUSE_REACH, HOUSE_REACH + 1):
			var corner := centre + Vector2i(dx, dy)
			var rect := Rect2i(corner, HOUSE_TILES)
			var front := 0
			for tx in range(rect.position.x, rect.end.x):
				var below := Vector2i(tx, rect.end.y)
				if _has_tile(below) and (flags[_tile_index(below)] & ROAD or ground[_tile_index(below)] == TOWN_COBBLE):
					front += 1
			if front >= 2:
				candidates.append([Vector2(rect.get_center()).distance_to(Vector2(centre)), corner])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and (a[1] as Vector2i) < (b[1] as Vector2i)))
	var placed := 0
	for candidate in candidates:
		if placed >= MAX_HOUSES:
			break
		var rect := Rect2i(candidate[1], HOUSE_TILES)
		if not _free(rect) or _near_flag(rect.get_center(), PROP, maxi(HOUSE_TILES.x, HOUSE_TILES.y)):
			continue
		_take(rect)
		var foot := Vector2((rect.position.x + HOUSE_TILES.x * 0.5) * tile_size, rect.end.y * tile_size - HOUSE_LIFT)
		_add_prop(HOUSE_SCENES[placed % HOUSE_SCENES.size()], foot, "house")
		placed += 1


# --- travel and notes -----------------------------------------------------------------------

func _place_travel() -> void:
	var openings := plan.openings_of(key)
	for opening in openings:
		var other: String = opening["b"] if opening["a"] == key else opening["a"]
		var target := str(plan.map.region(other).get("world", ""))
		var place := opening_place(plan, opening, key)
		var edge: String = place["edge"]
		var arrive: Vector2 = place["arrive"]
		arrivals.append({"name": "arrive-from-%s-%d" % [target, int(opening["index"])], "position": arrive})
		if not entries.has(edge):
			entries[edge] = arrive
		if spawn == Vector2.ZERO:
			spawn = arrive
		# Into the neighbour's marker for this opening: a placeholder has it; a hand-made world gets
		# it with its side of the opening (until then the travel falls back to its edge's entry).
		exits.append({
			"name": "exit-to-%s-%d" % [target, int(opening["index"])],
			"exit_id": "%s-to-%s-%d" % [world, target, int(opening["index"])],
			"rect": place["exit"], "target": target, "entry": OPPOSITE_EDGES[edge],
			"entry_marker": "arrive-from-%s-%d" % [world, int(opening["index"])],
		})
	if spawn == Vector2.ZERO:
		spawn = _open_centre()


## Where `opening` lies in region `key`'s world (its block of chunks; units and tiles from the
## block's corner): {edge (the world's edge it leads out of), tiles (Rect2i: the opening's tiles in
## the cells on the border), arrive (Vector2: ARRIVAL_TILES inside the border, in the middle of the
## opening: the `arrive-from-<neighbour world>-<n>` marker), exit (Rect2: a strip EXIT_DEPTH deep
## just past the border, the last strip inside the world on its edge, as wide as the opening)}.
static func opening_place(source: RegionPlan, opening: Dictionary, region_key: String) -> Dictionary:
	var map := source.map
	var per := map.tiles_per_cell
	var unit := float(map.tile_size)
	var origin := map.chunk_rect_cells(map.region_chunk_rect(region_key))
	var tiles_size := origin.size * per
	var step := source.direction(opening, region_key)
	var horizontal := step.x != 0
	var outward := step.x + step.y > 0
	# The opening's first cell on the border, the border line and the span along it (tiles).
	var first: Vector2i = source.corridor_cells(opening, region_key, 1)[0] - origin.position
	var border := ((first.x if horizontal else first.y) + (1 if outward else 0)) * per
	var span_start := (first.y if horizontal else first.x) * per
	var span := RegionPlan.OPENING_CELLS * per
	var limit := tiles_size.x if horizontal else tiles_size.y
	var arrive_across := (border - ARRIVAL_TILES if outward else border + ARRIVAL_TILES - 1) * unit + unit * 0.5
	var arrive_along := (span_start + span * 0.5) * unit
	var arrive := Vector2(arrive_across, arrive_along) if horizontal else Vector2(arrive_along, arrive_across)
	var at_edge := border >= limit if outward else border <= 0
	var strip := border * unit
	if outward == at_edge:
		strip -= EXIT_DEPTH
	var exit := Rect2(strip, span_start * unit, EXIT_DEPTH, span * unit) if horizontal \
			else Rect2(span_start * unit, strip, span * unit, EXIT_DEPTH)
	var tiles := Rect2i(first * per, Vector2i(per, span) if horizontal else Vector2i(span, per))
	return {"edge": EDGE_NAMES[step], "tiles": tiles, "arrive": arrive, "exit": exit}


## The open tile nearest the region's middle (no opening to arrive at).
func _open_centre() -> Vector2:
	var middle := Vector2(size) * 0.5
	var best := middle
	var best_distance := INF
	for ty in size.y:
		for tx in size.x:
			var index := ty * size.x + tx
			if flags[index] & OWN and not flags[index] & (BLOCKED | WALL | TREE | PROP | WET):
				var distance := Vector2(tx + 0.5, ty + 0.5).distance_squared_to(middle)
				if distance < best_distance:
					best_distance = distance
					best = Vector2(tx + 0.5, ty + 0.5)
	return best * tile_size


func _place_notes() -> void:
	for marker: Dictionary in plan.map.markers():
		var cell := Vector2i(int(marker.get("x", 0)), int(marker.get("y", 0))) - block.position
		if not _is_own(cell):
			continue
		var text := PackedStringArray()
		for field in ["notes", "needs", "to", "map"]:
			if str(marker.get(field, "")) != "":
				text.append("%s: %s" % [field, marker[field]] if field != "notes" else str(marker[field]))
		notes.append({
			"kind": str(marker.get("type", "note")), "label": str(marker.get("label", "")),
			"notes": "\n".join(text), "position": (Vector2(cell * per_cell) + Vector2.ONE * per_cell * 0.5) * tile_size,
		})
