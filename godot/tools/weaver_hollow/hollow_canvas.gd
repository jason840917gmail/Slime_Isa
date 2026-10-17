extends RefCounted
## One floor of the Weaver Hollow (docs/design/2026-10-16-dungeon-weaver-hollow.md) painted cell by
## cell before tools/build_weaver_hollow.gd turns it into a world scene: the ground, the elevation
## levels, the stairs, the wall styles (`cliffs`) and the floor webs.
##
## A floor is a mass of rock (level ROCK_LEVEL, its top the oak's dark soil, its walls root rock unless
## a room paints another style; voids are deep holes floored with dark cavern stone)
## with the rooms carved out of it at level 0: every camera room (16 x 14 cells) keeps a one-cell
## rim of rock on each side, so two rooms side by side are parted by a two-cell band, its north
## face a wall of two stone courses, its sides narrow side walls (ELEVATION.md "Side walls").
## Doors are gaps carved through those bands.
##
## Owner: world (dungeons).

## Cells per camera room (one screen).
const ROOM_COLS := 16
const ROOM_ROWS := 14
## The rock's level: a wall of two courses (128 units) under its south edges.
const ROCK_LEVEL := 2
## Terrain sources (game/world/terrain_tileset.tres).
const AMBERLEAF := 0
const CAVERN_FLOOR := 1
const CRYSTAL_FLOOR := 2
const DEEP_WATER := 3
const FOREST_FLOOR := 4
const FOREST_MOSS := 5
const TOWN_COBBLE := 19
## The interiors' wooden boards (one tile, not a 19 x 19 sheet).
const WOOD_FLOOR := 12
## Sources of one tile (atlas (0, 0) on every cell).
const SINGLE_TILE_SOURCES: Array[int] = [12, 13, 14, 15, 16, 17, 18]
## The 19 x 19 ground sheets wrap every 19 cells.
const SHEET_TILES := 19
## cliff_tileset.tres: the wall style tiles of row 0.
const CLIFF_STYLES := {
	"meadow-rock": 0, "snow-rock": 1, "sandstone": 2, "cave-rock": 3, "crystal-rock": 4,
	"mossy-rock": 5, "masonry": 6, "root-rock": 7, "red-rock": 8,
}
## elevation_tileset.tres row 2: a flight of stairs per direction (the arrow points down them).
const STAIRS_ROW := 2
const STAIRS_COLUMNS := {"s": 0, "sw": 1, "w": 2, "nw": 3, "n": 4, "ne": 5, "e": 6, "se": 7}

var world: String
var cols: int
var rows: int
## Per cell: a terrain source (-1 none), a level, a stairs column (-1 none), a wall style (-1 the
## ground's), a floor web (0 / 1).
var ground: PackedInt32Array
var level: PackedInt32Array
var stairs: PackedInt32Array
var cliffs: PackedInt32Array
var webs: PackedInt32Array
## The ground on top of the rock (the oak's dark soil).
var rock_ground: int


func _init(world_id: String, room_cols: int, room_rows: int, rock_ground_source: int = FOREST_FLOOR,
		rock_style: String = "root-rock") -> void:
	world = world_id
	rock_ground = rock_ground_source
	cols = room_cols * ROOM_COLS
	rows = room_rows * ROOM_ROWS
	var count := cols * rows
	ground = PackedInt32Array()
	ground.resize(count)
	ground.fill(rock_ground_source)
	level = PackedInt32Array()
	level.resize(count)
	level.fill(ROCK_LEVEL)
	stairs = PackedInt32Array()
	stairs.resize(count)
	stairs.fill(-1)
	cliffs = PackedInt32Array()
	cliffs.resize(count)
	cliffs.fill(CLIFF_STYLES[rock_style])
	webs = PackedInt32Array()
	webs.resize(count)
	webs.fill(0)


## The cells of the camera room at room cell (x, y), w x h rooms.
static func room_rect(x: int, y: int, w: int = 1, h: int = 1) -> Rect2i:
	return Rect2i(x * ROOM_COLS, y * ROOM_ROWS, w * ROOM_COLS, h * ROOM_ROWS)


## The room's camera rect in world units.
static func room_world_rect(x: int, y: int, w: int = 1, h: int = 1, cell: int = 64) -> Rect2:
	var r := room_rect(x, y, w, h)
	return Rect2(Vector2(r.position * cell), Vector2(r.size * cell))


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows


func index(x: int, y: int) -> int:
	return y * cols + x


## Carves a room's floor: everything but its one-cell rock rim, at level `floor_level`, painted
## `floor_ground`. Returns the floor's cells.
func carve_room(x: int, y: int, w: int, h: int, floor_ground: int, floor_level: int = 0) -> Rect2i:
	var floor := room_rect(x, y, w, h).grow(-1)
	fill(floor, floor_level, floor_ground)
	return floor


## Sets the level (and the ground, when >= 0) of every cell in `rect`.
func fill(rect: Rect2i, value: int, ground_source: int = -1) -> void:
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if not inside(cx, cy):
				continue
			level[index(cx, cy)] = value
			if ground_source >= 0:
				ground[index(cx, cy)] = ground_source


## Rock again over `rect` (a band, a block, a tongue between rooms): the wall level with the rock's
## own top.
func rock(rect: Rect2i) -> void:
	fill(rect, ROCK_LEVEL, rock_ground)


func paint_ground(rect: Rect2i, ground_source: int) -> void:
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if inside(cx, cy):
				ground[index(cx, cy)] = ground_source


## Paints a wall style on the cells of `rect` (their walls take it).
func paint_style(rect: Rect2i, style: String) -> void:
	var tile: int = CLIFF_STYLES[style]
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if inside(cx, cy):
				cliffs[index(cx, cy)] = tile


## Floor webs over the floor cells of `rect` (cells up to `max_level`: the rock's top is never
## webbed; 1 webs a level-1 ledge or gallery too).
func paint_webs(rect: Rect2i, max_level: int = 0) -> void:
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if inside(cx, cy) and level[index(cx, cy)] <= max_level:
				webs[index(cx, cy)] = 1


func clear_webs(rect: Rect2i) -> void:
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			if inside(cx, cy):
				webs[index(cx, cy)] = 0


## A front flight of stairs down a south face, `width` cells wide, its first cell (`x`, `y`) being
## the face's first row (the cell right below the top's edge).
func paint_stairs(x: int, y: int, direction: String, width: int = 2) -> void:
	for i in width:
		var cx := x + i if direction in ["s", "n"] else x
		var cy := y if direction in ["s", "n"] else y + i
		if inside(cx, cy):
			stairs[index(cx, cy)] = STAIRS_COLUMNS[direction]


## A door between two rooms one above the other: the two cells `x`, `x + 1` carved through the band
## whose rows are `band_top` and `band_top + 1`, at `floor_level`, painted `floor_ground`. The rock
## left either side of the gap shows its side walls.
func door_north_south(x: int, band_top: int, floor_ground: int, floor_level: int = 0) -> void:
	fill(Rect2i(x, band_top, 2, 2), floor_level, floor_ground)


## A door between two rooms side by side: the band's two columns `band_left`, `band_left + 1`, cut
## from two rows above `y` (the rows the band's north face then covers) to `y + 1`, so the gap's two
## open rows are `y` and `y + 1`.
func door_east_west(band_left: int, y: int, floor_ground: int, floor_level: int = 0) -> void:
	fill(Rect2i(band_left, y - ROCK_LEVEL, 2, 2 + ROCK_LEVEL), floor_level, floor_ground)
