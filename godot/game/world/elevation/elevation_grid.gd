extends RefCounted
## The elevation model of a world (docs/godot/ELEVATION.md): which ground lies at which level,
## where cliff walls hang, where their tops and feet are, and what each level can walk on.
##
## The map is authored as the camera sees it. Every cell has a painted level (0 when unpainted).
## A higher area is drawn where it is painted; the cliff wall below its south-facing edges hangs
## over the lower cells, one cell (64 units) per level of drop, and only the front faces show:
## a square block shows its south face, a diamond its south-west and south-east faces, an octagon
## all three. North, east and west edges are rims without a wall. A hole is the same thing upside
## down: its north rim drops into it and the wall shows on the hole's far side.
##
## Shapes come from the painted cells: a staircase of single-cell steps becomes a straight 45°
## edge (chamfer), a step of two or more cells keeps a square corner. To place 45° edges exactly,
## every cell is split into 8 triangles ("tris"): the 4 corner triangles and the 4 quarters of the
## centre diamond (the corner triangles meet the diamond on the 45° lines). A chamfer gives a
## corner triangle the level across the corner.
##
## Walls are swept per half-cell column, top to bottom: below an edge where the north tri is
## higher (level a) than the south one (level b) the wall covers the next 4·(a − b) tris (one
## cell of depth per level) unless a tri in front of the wall plane hides it first (a tri of level
## l at depth d cells hides the wall when d ≥ a − l: the near rim of a hole, a lower platform
## standing in front). A covered tri is wall, walkable at no level.
##
## What a level can walk on: its own visible tops (not walls) and the strip behind higher ground
## in front of it. As in 3D, a hill hides the ground right behind it and a
## hole's near rim hides the floor under it; a body may walk into that hidden strip `behind` cells
## deep (a cap: the camera's 3D answer would be a cell per level, which buries the slime). The strip
## lies below every "back rim": an edge where walkable ground (north) meets higher ground (south),
## so the north and diagonal back rims of a hill and the near rim of a hole, and runs into whatever
## higher ground is there: the top, and at a hill's tip the top corner of its wall, so the strip's
## edge goes straight on to the tip and turns down the wall's end (no notch to get caught in).
## It never reaches the hill's real footprint (a cell per level below its back rims). East and west
## sides stay plain rims, the rest of a wall stays solid. `is_walkable_point` answers for a point, `collision_segments`
## traces the outline of the same ground on a finer grid (16 parts per cell, closed at every
## corner by construction). `behind` is a whole number of half cells.
##
## Stairs are no part of the model: elevation.gd builds the terrain with a stairs cell as the ground
## it leads down to and stands the flight (elevation_stairs.gd) on it.
##
## Pure data: elevation.gd draws and collides from it. Coordinates are in cells unless named
## `world`; tri ids are (cell index · 4 + quadrant) · 2 + part.
##
## Owner: world (elevation).

const Self := preload("res://game/world/elevation/elevation_grid.gd")

## Painted levels stay in this range (physics layers exist for each, elevation.gd).
const MIN_LEVEL := -3
const MAX_LEVEL := 3
## Quadrants of a cell.
const TL := 0
const TR := 1
const BL := 2
const BR := 3
## Parts of a quadrant: the cell's corner triangle, or a quarter of its centre diamond.
const OUTER := 0
const INNER := 1
## Quadrant -> direction from the cell centre (TL = up-left).
const QUADRANT_DIR: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
## Edge kinds.
const HORIZONTAL := 0
const VERTICAL := 1
## Falling to the right ("\"): y grows with x.
const DIAGONAL_DOWN := 2
## Rising to the right ("/"): y shrinks as x grows.
const DIAGONAL_UP := 3
## Squares per cell side of the fine grid the collision is traced on (`collision_segments`): each
## square is a cell quadrant, cut by its diagonals into the parts N, E, S, W.
const FINE := 2
const FINE_N := 0
const FINE_E := 1
const FINE_S := 2
const FINE_W := 3
## Per quadrant (TL, TR, BL, BR), which parts (N, E, S, W) lie in its corner tri.
const FINE_CORNER: Array = [[true, false, false, true], [true, true, false, false], [false, false, true, true], [false, true, true, false]]
## The wall sweep order of the tris in one half-cell column of a cell, top to bottom.
const COLUMN_ORDER: Array = [
	[[TL, OUTER], [TL, INNER], [BL, INNER], [BL, OUTER]],
	[[TR, OUTER], [TR, INNER], [BR, INNER], [BR, OUTER]],
]

var columns := 0
var rows := 0
## Painted level per cell (row-major).
var cell_level := PackedInt32Array()
## Ground name per cell ("" = none, or a ground without edge art).
var cell_ground := PackedStringArray()
## Level per tri after the chamfers.
var tri_level := PackedInt32Array()
## Ground per tri: the cell's, or the ground across the corner for a chamfered corner triangle.
var tri_ground := PackedStringArray()
## Index into `bands` of the wall covering each tri, -1 when uncovered.
var tri_band := PackedInt32Array()
## Cliff walls, one per covered half-column stretch: {column (half-column index), start, end (sequence
## indices of the first and last covered tri), top (level a), bottom (level b), drop (a − b),
## y_left, slope (the top edge: y = y_left + slope·(x − column/2), cells), natural (true when the
## wall reached its foot, false when something in front hid its lower part)}.
var bands: Array[Dictionary] = []
## Corner triangles re-levelled by a chamfer whose ground differs from their cell's: {tri, ground}.
var patches: Array[Dictionary] = []
## How deep (cells) a body may walk into the ground hidden behind higher ground.
var behind := 0.5
var _edges: Array = []
var _fine_parent := PackedInt32Array()


## Builds the model. `levels`: Vector2i cell -> int (unlisted cells are level 0); `grounds`:
## Vector2i cell -> String; `behind_cells`: how deep a body may walk behind higher ground.
static func build(cell_columns: int, cell_rows: int, levels: Dictionary, grounds: Dictionary, behind_cells: float = 0.5) -> Self:
	var grid := Self.new()
	grid.behind = clampf(roundf(behind_cells * FINE) / FINE, 0.0, 1.0)
	grid.columns = maxi(cell_columns, 0)
	grid.rows = maxi(cell_rows, 0)
	var count := grid.columns * grid.rows
	grid.cell_level.resize(count)
	grid.cell_ground.resize(count)
	for cell: Vector2i in levels:
		if not grid.has_cell(cell):
			continue
		grid.cell_level[grid.cell_index(cell)] = clampi(int(levels[cell]), MIN_LEVEL, MAX_LEVEL)
	for cell: Vector2i in grounds:
		if grid.has_cell(cell):
			grid.cell_ground[grid.cell_index(cell)] = str(grounds[cell])
	grid._build_tris()
	grid._build_bands()
	return grid


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows


func cell_index(cell: Vector2i) -> int:
	return cell.y * columns + cell.x


## Painted level of `cell`; outside the map, the nearest cell's (no walls at the border).
func level_of_cell(cell: Vector2i) -> int:
	if columns == 0 or rows == 0:
		return 0
	return cell_level[cell_index(Vector2i(clampi(cell.x, 0, columns - 1), clampi(cell.y, 0, rows - 1)))]


static func tri_id(cell_idx: int, quadrant: int, part: int) -> int:
	return (cell_idx * 4 + quadrant) * 2 + part


func tri_cell(tri: int) -> Vector2i:
	var cell_idx := tri / 8
	return Vector2i(cell_idx % columns, cell_idx / columns)


## True when any cell has a level other than 0.
func is_flat() -> bool:
	for level in cell_level:
		if level != 0:
			return false
	return true


## The 3 corners of a tri, in cells.
func tri_points(tri: int) -> PackedVector2Array:
	var cell := Vector2(tri_cell(tri))
	var quadrant := (tri / 2) % 4
	var part := tri % 2
	var o := cell + Vector2(0.5 if quadrant == TR or quadrant == BR else 0.0, 0.5 if quadrant >= BL else 0.0)
	var a := o
	var b := o + Vector2(0.5, 0.0)
	var c := o + Vector2(0.5, 0.5)
	var d := o + Vector2(0.0, 0.5)
	match quadrant:
		TL:
			return PackedVector2Array([a, b, d]) if part == OUTER else PackedVector2Array([b, c, d])
		TR:
			return PackedVector2Array([a, b, c]) if part == OUTER else PackedVector2Array([a, c, d])
		BL:
			return PackedVector2Array([a, c, d]) if part == OUTER else PackedVector2Array([a, b, c])
		_:
			return PackedVector2Array([b, c, d]) if part == OUTER else PackedVector2Array([a, b, d])


## The tri containing `point` (cells), -1 outside the map.
func tri_at(point: Vector2) -> int:
	var cell := Vector2i(floori(point.x), floori(point.y))
	if not has_cell(cell):
		return -1
	var local := point - Vector2(cell)
	var right := local.x >= 0.5
	var lower := local.y >= 0.5
	var quadrant := (BR if right else BL) if lower else (TR if right else TL)
	var q := local - Vector2(0.5 if right else 0.0, 0.5 if lower else 0.0)
	var outer := false
	match quadrant:
		TL:
			outer = q.x + q.y < 0.5
		TR:
			outer = q.y < q.x
		BL:
			outer = q.y > q.x
		_:
			outer = q.x + q.y > 0.5
	return tri_id(cell_index(cell), quadrant, OUTER if outer else INNER)


## Every pair of touching tris: [tri_a, tri_b, kind, p0, p1] with tri_a north of the edge (west of
## it for vertical edges) and p0.x <= p1.x (p0.y <= p1.y for vertical edges), in cells. Built once.
func tri_edges() -> Array:
	if not _edges.is_empty():
		return _edges
	var edges := _edges
	for cy in rows:
		for cx in columns:
			var o := Vector2(cx, cy)
			var c := cell_index(Vector2i(cx, cy))
			edges.append([tri_id(c, TL, OUTER), tri_id(c, TL, INNER), DIAGONAL_UP, o + Vector2(0.0, 0.5), o + Vector2(0.5, 0.0)])
			edges.append([tri_id(c, TR, OUTER), tri_id(c, TR, INNER), DIAGONAL_DOWN, o + Vector2(0.5, 0.0), o + Vector2(1.0, 0.5)])
			edges.append([tri_id(c, BL, INNER), tri_id(c, BL, OUTER), DIAGONAL_DOWN, o + Vector2(0.0, 0.5), o + Vector2(0.5, 1.0)])
			edges.append([tri_id(c, BR, INNER), tri_id(c, BR, OUTER), DIAGONAL_UP, o + Vector2(0.5, 1.0), o + Vector2(1.0, 0.5)])
			edges.append([tri_id(c, TL, INNER), tri_id(c, TR, INNER), VERTICAL, o + Vector2(0.5, 0.0), o + Vector2(0.5, 0.5)])
			edges.append([tri_id(c, BL, INNER), tri_id(c, BR, INNER), VERTICAL, o + Vector2(0.5, 0.5), o + Vector2(0.5, 1.0)])
			if cy + 1 < rows:
				var below := cell_index(Vector2i(cx, cy + 1))
				edges.append([tri_id(c, BL, OUTER), tri_id(below, TL, OUTER), HORIZONTAL, o + Vector2(0.0, 1.0), o + Vector2(0.5, 1.0)])
				edges.append([tri_id(c, BR, OUTER), tri_id(below, TR, OUTER), HORIZONTAL, o + Vector2(0.5, 1.0), o + Vector2(1.0, 1.0)])
			if cx + 1 < columns:
				var right := cell_index(Vector2i(cx + 1, cy))
				edges.append([tri_id(c, TR, OUTER), tri_id(right, TL, OUTER), VERTICAL, o + Vector2(1.0, 0.0), o + Vector2(1.0, 0.5)])
				edges.append([tri_id(c, BR, OUTER), tri_id(right, BL, OUTER), VERTICAL, o + Vector2(1.0, 0.5), o + Vector2(1.0, 1.0)])
	return edges


## The tri at sequence index `s` of half-column `column` (4 per cell row, COLUMN_ORDER).
func column_tri(column: int, s: int) -> int:
	var pick: Array = COLUMN_ORDER[column % 2][s % 4]
	return tri_id(cell_index(Vector2i(column / 2, s / 4)), int(pick[0]), int(pick[1]))


## The edge under sequence index `s` of a half-column (between tri s and s + 1) as
## [y_left, slope]: y = y_left + slope·(x − column/2), cells.
static func column_edge(column: int, s: int) -> Vector2:
	var row := float(s / 4)
	var right := column % 2 == 1
	match s % 4:
		0:
			return Vector2(row, 1.0) if right else Vector2(row + 0.5, -1.0)
		1:
			return Vector2(row + 0.5, 0.0)
		2:
			return Vector2(row + 1.0, -1.0) if right else Vector2(row + 0.5, 1.0)
		_:
			return Vector2(row + 1.0, 0.0)


## True when the tri is walkable at `level`: a visible top of that level (not wall). The strip
## behind higher ground is `is_walkable_point`'s.
func is_walkable(tri: int, level: int) -> bool:
	return tri >= 0 and tri_level[tri] == level and tri_band[tri] < 0


## Ground higher than `level` in front of it: a top above it, or a wall whose top is. The strip
## behind a back rim runs into either: at a hill's tip the wall's end comes within `behind` of the
## ground behind the hill.
func is_higher(tri: int, level: int) -> bool:
	if tri < 0:
		return false
	if tri_band[tri] >= 0:
		return int(bands[tri_band[tri]]["top"]) > level
	return tri_level[tri] > level


## True when a body of `level` can stand at `point` (cells): its walkable tris, and the strip
## `behind` cells deep below a back rim (the class notes).
func is_walkable_point(point: Vector2, level: int) -> bool:
	var tri := tri_at(point)
	if is_walkable(tri, level):
		return true
	if not is_higher(tri, level):
		return false
	return is_walkable(tri_at(point - Vector2(0.0, behind)), level)


## The level a body standing at `point` (cells) walks on: `preferred` when it can walk there, else
## the level seen there, else the nearest walkable level to 0; `preferred` when none is.
func walkable_level(point: Vector2, preferred: int = 0) -> int:
	var tri := tri_at(point)
	if tri < 0 or is_walkable_point(point, preferred):
		return preferred
	if is_walkable_point(point, tri_level[tri]):
		return tri_level[tri]
	for distance in range(1, MAX_LEVEL - MIN_LEVEL + 1):
		for level: int in [-distance, distance]:
			if is_walkable_point(point, level):
				return level
	return preferred


## Level of the ground seen at `point` (cells); `fallback` on a wall or outside the map.
func level_at(point: Vector2, fallback: int = 0) -> int:
	var tri := tri_at(point)
	if tri < 0:
		return fallback
	if tri_band[tri] >= 0:
		return fallback
	return tri_level[tri]


## Blocking segments for bodies at `level`, in cells: [p0, p1, p0, p1, ...], merged along their
## lines. They trace the outline of exactly what `is_walkable_point` allows, on the fine grid: every
## cell quadrant cut by its two diagonals into 4 parts (16 per cell). Each tri is 2 of those parts,
## and a shift of half a cell maps the grid onto itself, so a part is walkable when its tri is, or
## when its tri is higher ground (`is_higher`) and the part `behind` north of it is walkable (the strip behind a
## back rim). The outline is the border between walkable and blocked parts, so it closes around
## every corner by construction (map borders excepted, as before).
func collision_segments(level: int) -> PackedVector2Array:
	var parents := _fine_parents()
	var tri_count := tri_level.size()
	var walk := PackedByteArray()
	walk.resize(tri_count)
	# `is_higher`, inlined.
	var higher := PackedByteArray()
	higher.resize(tri_count)
	for tri in tri_count:
		if tri_band[tri] < 0:
			if tri_level[tri] == level:
				walk[tri] = 1
			elif tri_level[tri] > level:
				higher[tri] = 1
		elif int(bands[tri_band[tri]]["top"]) > level:
			higher[tri] = 1
	var fine_columns := columns * FINE
	var fine_rows := rows * FINE
	var row_stride := fine_columns * 4
	var shift := roundi(behind * FINE) * row_stride
	var state := PackedByteArray()
	state.resize(parents.size())
	for f in parents.size():
		var parent := parents[f]
		if walk[parent] == 1 or (higher[parent] == 1 and shift > 0 and f >= shift and walk[parents[f - shift]] == 1):
			state[f] = 1
	var lines := {}
	var size := 1.0 / FINE
	for fy in fine_rows:
		for fx in fine_columns:
			var base := (fy * fine_columns + fx) * 4
			var north := state[base + FINE_N]
			var east := state[base + FINE_E]
			var south := state[base + FINE_S]
			var west := state[base + FINE_W]
			var cut_above := fy > 0 and north != state[base - row_stride + FINE_S]
			var cut_left := fx > 0 and west != state[base - 4 + FINE_E]
			if north == east and east == south and south == west and not cut_above and not cut_left:
				continue
			var o := Vector2(fx, fy) * size
			var middle := o + Vector2(size, size) * 0.5
			if north != east:
				_add_line(lines, o + Vector2(size, 0.0), middle)
			if east != south:
				_add_line(lines, o + Vector2(size, size), middle)
			if south != west:
				_add_line(lines, o + Vector2(0.0, size), middle)
			if west != north:
				_add_line(lines, o, middle)
			if cut_above:
				_add_line(lines, o, o + Vector2(size, 0.0))
			if cut_left:
				_add_line(lines, o, o + Vector2(0.0, size))
	var segments := PackedVector2Array()
	for key: Vector2 in lines:
		var kind := int(key.x)
		var constant := key.y
		var spans: Array = lines[key]
		spans.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
		var current: Vector2 = spans[0]
		for i in range(1, spans.size() + 1):
			var next: Vector2 = spans[i] if i < spans.size() else Vector2(INF, INF)
			if i < spans.size() and is_equal_approx(next.x, current.y):
				current.y = next.y
				continue
			match kind:
				HORIZONTAL:
					segments.append(Vector2(current.x, constant))
					segments.append(Vector2(current.y, constant))
				VERTICAL:
					segments.append(Vector2(constant, current.x))
					segments.append(Vector2(constant, current.y))
				DIAGONAL_DOWN:
					segments.append(Vector2(current.x, current.x + constant))
					segments.append(Vector2(current.y, current.y + constant))
				_:
					segments.append(Vector2(current.x, constant - current.x))
					segments.append(Vector2(current.y, constant - current.y))
			current = next
	return segments


## Files the edge p–q under its line: lines[Vector2(kind, constant)] gets its span along the line
## (x, or y for a vertical line), smallest first.
static func _add_line(lines: Dictionary, p: Vector2, q: Vector2) -> void:
	var kind := DIAGONAL_UP
	var constant := p.y + p.x
	var along := Vector2(minf(p.x, q.x), maxf(p.x, q.x))
	if is_equal_approx(p.y, q.y):
		kind = HORIZONTAL
		constant = p.y
	elif is_equal_approx(p.x, q.x):
		kind = VERTICAL
		constant = p.x
		along = Vector2(minf(p.y, q.y), maxf(p.y, q.y))
	elif (q.x - p.x) * (q.y - p.y) > 0.0:
		kind = DIAGONAL_DOWN
		constant = p.y - p.x
	var key := Vector2(kind, constant)
	if not lines.has(key):
		lines[key] = []
	(lines[key] as Array).append(along)


## For every part of the fine grid (row-major squares, FINE per cell side, 4 parts each), the tri
## it belongs to. With FINE 2 a square is a quadrant of a cell; FINE_CORNER says which of its parts
## make the quadrant's corner tri. Built once.
func _fine_parents() -> PackedInt32Array:
	if not _fine_parent.is_empty():
		return _fine_parent
	var fine_columns := columns * FINE
	_fine_parent.resize(fine_columns * rows * FINE * 4)
	for fy in rows * FINE:
		for fx in fine_columns:
			var cell_idx := (fy / FINE) * columns + fx / FINE
			var quadrant := (fx % FINE) + 2 * (fy % FINE)
			var corner: Array = FINE_CORNER[quadrant]
			var base := (fy * fine_columns + fx) * 4
			for part in 4:
				_fine_parent[base + part] = tri_id(cell_idx, quadrant, OUTER if bool(corner[part]) else INNER)
	return _fine_parent


# --- build ---------------------------------------------------------------------------------

func _build_tris() -> void:
	var count := columns * rows
	tri_level.resize(count * 8)
	tri_ground.resize(count * 8)
	tri_band.resize(count * 8)
	tri_band.fill(-1)
	for c in count:
		for t in 8:
			tri_level[c * 8 + t] = cell_level[c]
			tri_ground[c * 8 + t] = cell_ground[c]
	patches.clear()
	for cy in range(1, rows):
		for cx in range(1, columns):
			_chamfer_corner(Vector2i(cx, cy))


## The four cells around the corner point `corner` (top-left of cell `corner`), in QUADRANT order.
func _corner_cells(corner: Vector2i) -> Array[Vector2i]:
	return [corner + Vector2i(-1, -1), corner + Vector2i(0, -1), corner + Vector2i(-1, 0), corner]


## At threshold `t`: [kind, quadrant] of the corner (kind 1 = convex: only `quadrant`'s cell
## reaches t; 3 = concave: only `quadrant`'s cell is below t; 0 = neither). Corners on the map
## border are neither.
func _corner_shape(corner: Vector2i, t: int) -> Vector2i:
	if corner.x < 1 or corner.y < 1 or corner.x >= columns or corner.y >= rows:
		return Vector2i.ZERO
	var cells := _corner_cells(corner)
	var inside := 0
	var last_in := -1
	var last_out := -1
	for q in 4:
		if cell_level[cell_index(cells[q])] >= t:
			inside += 1
			last_in = q
		else:
			last_out = q
	if inside == 1:
		return Vector2i(1, last_in)
	if inside == 3:
		return Vector2i(3, last_out)
	return Vector2i.ZERO


## A convex corner pairs with a concave one beside it along the 45° line (and back): together
## they are one step of a staircase, which becomes a straight diagonal edge.
func _is_chamfered(corner: Vector2i, t: int, shape: Vector2i) -> bool:
	var dir := QUADRANT_DIR[shape.y]
	var opposite := 3 - shape.y
	if shape.x == 1:
		# Convex, in-cell at quadrant q: concave partners at corner + (qx, 0) and corner + (0, qy)
		# with their out-cell at the opposite quadrant.
		return _corner_shape(corner + Vector2i(dir.x, 0), t) == Vector2i(3, opposite) \
				or _corner_shape(corner + Vector2i(0, dir.y), t) == Vector2i(3, opposite)
	# Concave, out-cell at quadrant o: convex partners at corner + (ox, 0) and corner + (0, oy).
	return _corner_shape(corner + Vector2i(dir.x, 0), t) == Vector2i(1, opposite) \
			or _corner_shape(corner + Vector2i(0, dir.y), t) == Vector2i(1, opposite)


func _chamfer_corner(corner: Vector2i) -> void:
	var cells := _corner_cells(corner)
	var levels: Array[int] = []
	for cell in cells:
		levels.append(cell_level[cell_index(cell)])
	var thresholds: Array[int] = []
	for level in levels:
		if not thresholds.has(level):
			thresholds.append(level)
	if thresholds.size() < 2:
		return
	thresholds.sort()
	# Final level of each cell's corner triangle at this corner: the highest threshold it reaches.
	var final: Array[int] = [thresholds[0], thresholds[0], thresholds[0], thresholds[0]]
	for i in range(1, thresholds.size()):
		var t := thresholds[i]
		var shape := _corner_shape(corner, t)
		var flip := -1
		if shape.x != 0 and _is_chamfered(corner, t, shape):
			flip = shape.y
		for q in 4:
			var inside := levels[q] >= t
			if q == flip:
				inside = not inside
			if inside:
				final[q] = t
	for q in 4:
		if final[q] == levels[q]:
			continue
		var cell := cells[q]
		# The cell at quadrant q of the corner touches it with its own opposite quadrant.
		var tri := tri_id(cell_index(cell), 3 - q, OUTER)
		tri_level[tri] = final[q]
		var ground := _ground_across(corner, q, final[q])
		if ground != tri_ground[tri]:
			tri_ground[tri] = ground
			patches.append({"tri": tri, "ground": ground})


## The ground of the corner's cell at `level` nearest to quadrant `q` (sides first, then across).
func _ground_across(corner: Vector2i, q: int, level: int) -> String:
	var cells := _corner_cells(corner)
	for other in [q ^ 1, q ^ 2, 3 - q]:
		if cell_level[cell_index(cells[other])] == level:
			return cell_ground[cell_index(cells[other])]
	return cell_ground[cell_index(cells[q])]


func _build_bands() -> void:
	bands.clear()
	var length := rows * 4
	for column in columns * 2:
		var band := -1
		var band_start := 0
		var band_end := -1
		var band_top := 0
		for s in length:
			var tri := column_tri(column, s)
			if band >= 0 and s <= band_end:
				var depth := (s - band_start) / 4
				if depth >= band_top - tri_level[tri]:
					# Something in front of the wall plane: the rest of this wall is hidden.
					bands[band]["end"] = s - 1
					bands[band]["natural"] = false
					band = -1
					band_end = -1
				else:
					tri_band[tri] = band
			if band >= 0 and s == band_end:
				band = -1
			if s + 1 >= length or band_end >= s + 1:
				continue
			var a := tri_level[tri]
			var below := column_tri(column, s + 1)
			var b := tri_level[below]
			if a <= b:
				continue
			var edge := column_edge(column, s)
			band = bands.size()
			band_start = s + 1
			band_end = mini(s + 4 * (a - b), length - 1)
			band_top = a
			bands.append({
				"column": column, "start": s + 1, "end": band_end, "top": a, "bottom": b,
				"drop": a - b, "y_left": edge.x, "slope": edge.y,
				"natural": s + 4 * (a - b) < length - 1,
			})
