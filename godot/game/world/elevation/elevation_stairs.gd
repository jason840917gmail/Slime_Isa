@tool
extends RefCounted
## One flight of stairs (docs/godot/ELEVATION.md "Stairs"): a stone structure that leaves a rim in
## one of 8 directions, from a landing on the higher ground, down 3 steps per level onto the lower
## ground, between two railings with a newel post at each end. The approved design and its numbers:
## asset/Originals/elevation/stairs-mockups/README.md (its renderer, stairs_mockup.py `Flight`,
## holds the same geometry).
##
## Built in 3D in the flight's frame: s along its direction D (down the stairs, 0 on the rim), t
## across it (T = D turned 90°), h up from the lower ground. A point at ground (x, y) and absolute
## height H (64 per level) is drawn at (x, y − H), and its depth is its ground y
## (elevation_occlusion.gdshaderinc). Elevation uses:
##   `walk`        the walkable surface on screen: the landing and the steps' nosing line between
##                 the railings, walkable by every level from `bottom` to `top` (the landing by the
##                 top level only: `walks_level`); a body there
##                 takes the level of the stretch it stands on (`level_at`) and its depth
##                 (`depth_at`);
##   `blockers`    what of the structure stands at a level's height, drawn at that height (its
##                 footprint there: the landing's railings and posts for the top level, the bases of
##                 the railings, posts and steps for the bottom one): a body of that level is
##                 blocked there (`blocks`); what is drawn above it only hides it (the depth map);
##   `silhouette`  the whole structure as drawn (`occupies`: fences leave a gap there);
##   faces         drawn (`add_mesh`) and written to the depth map (`add_depth`) back to front;
##   `feet`        where the railings and posts stand on the lower ground in sight (foot strips).
## Godot draws in order, without a depth test, so what of a flight lies behind the ground it leaves
## (`occlude`: a back flight's foot and the first steps behind the rim, under the hill's top) is cut
## out of its faces, its depth and its silhouette.
## Coordinates are Elevation's (world units from the ground layer's origin).
##
## Owner: world (elevation).

const Self := preload("res://game/world/elevation/elevation_stairs.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const ElevationOcclusion := preload("res://game/world/elevation/elevation_occlusion.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")

const LEVEL := 64.0
const STEPS_PER_LEVEL := 3
const RISE := LEVEL / STEPS_PER_LEVEL
## Half the walkable width of a one-cell flight; a flight is `cells` cells wide.
const HALF_CELL := 32.0
## The flat top step, reaching into the higher ground.
const LANDING := 32.0
## The last step (on the lower ground) is this much deeper than the others.
const BOTTOM := 11.0
## Railings: thickness (outside the walkable width) and height above the nosing line.
const RAIL := 18.0
const RAIL_UP := 24.0
## Newel posts: length along the flight, how far they stand proud of the railing on its outside
## (flush with its inner face: they never narrow the walkway) and above it.
const POST := 20.0
const POST_OUT := 6.0
const POST_UP := 10.0
const SQRT2 := 1.4142135623730951
## Direction -> [D on the ground, run per level (world units)]. Back flights are foreshortened:
## a 45° one runs one diagonal cell per level like a front one, a north one 1.5 cells (at one it
## would be seen edge-on).
const DIRECTIONS := {
	"s": [Vector2(0, 1), 64.0], "n": [Vector2(0, -1), 96.0],
	"e": [Vector2(1, 0), 64.0], "w": [Vector2(-1, 0), 64.0],
	"se": [Vector2(1, 1), 64.0 * SQRT2], "sw": [Vector2(-1, 1), 64.0 * SQRT2],
	"ne": [Vector2(1, -1), 64.0 * SQRT2], "nw": [Vector2(-1, -1), 64.0 * SQRT2],
}
## Face kinds: the stairs shader picks the texture from UV.y (KIND_OFFSET per kind).
const KIND_TREAD := 0
const KIND_RISER := 1
const KIND_COPING := 2
const KIND_WALL := 3
const KIND_OFFSET := 4096.0
## Texture px per world unit (the stairs kit and the wall).
const PX := 2.0
## Face light (elevation_wall.gdshader): tops 1, faces by the way they look, S 0.86 ± 0.20.
const SHADE_SOUTH := 0.86
const SHADE_SPREAD := 0.20
## Contact shadows and highlights (the mockup's): a tread darkens towards the riser above it and
## lights up on its nosing, every face darkens a little along the railings, a riser under its
## nosing, a railing's inner face where it meets the steps.
const TREAD_AO := 0.78
const TREAD_AO_REACH := 0.35
const NOSING_LIGHT := 1.22
const NOSING := 3.0
const TREAD_EDGE := 0.62
const TREAD_EDGE_REACH := 9.0
const RISER_AO := 0.62
const RISER_AO_REACH := 0.4
const RISER_EDGE := 0.75
const RISER_EDGE_REACH := 7.0
const RAIL_CONTACT := 0.7
const RAIL_CONTACT_REACH := 10.0
## A part of the flight this much below its top level is hidden by higher ground drawn over it.
const OCCLUDE_MARGIN := 2.0

var direction_name := "s"
## D and T on the ground (unit).
var dir := Vector2.DOWN
var across := Vector2.LEFT
## The rim's midpoint on screen at the top level, and the same point on the ground (y + 64 · top).
var rim := Vector2.ZERO
var base := Vector2.ZERO
var top := 1
var bottom := 0
var half := HALF_CELL
var open_landing := false
var steps := 3
## Depth of a step, s where the nosing reaches the lower ground, where the flight ends.
var run := LEVEL / STEPS_PER_LEVEL
var ramp := LEVEL
var end := LEVEL + BOTTOM
## Where the railings start: the landing's start (railed landing) or the rim (open landing).
var rail_start := -LANDING
var walk := PackedVector2Array()
var silhouette: Array[PackedVector2Array] = []
var bounds := Rect2()
## [from, to] on screen and the ground level, where a railing or post stands in sight.
var feet: Array = []
## Faces back to front: {kind, quad: [p00, p10, p11, p01] (s, t, h), normal (x, y, h), shade,
## and per kind the texture mapping}.
var faces: Array[Dictionary] = []
## Screen polygons of the higher ground in front of the flight (`occlude`), and their rects.
var occluders: Array[PackedVector2Array] = []
var _occluder_rects: Array[Rect2] = []
## The structure's convex pieces on screen: [polygon, may hide behind the ground (not on the top)].
var _hulls: Array = []
## The structure's solids in the flight's frame: [s from, s to, t from, t to, floor at s from, floor at
## s to, top at s from, top at s to] (h above the lower ground, linear along s).
var _solids: Array = []
## Per level: the blockers, and the collision's edges cut where they cross.
var _blockers: Dictionary = {}
var _pieces: Dictionary = {}
var _seed := 0


## A flight leaving the rim at `rim_point` (screen, top level) towards `direction_name` (DIRECTIONS)
## from level `top_level` down to `bottom_level`, `cells` cells wide, its landing railed or open.
static func create(direction_key: String, rim_point: Vector2, top_level: int, bottom_level: int, cells: int, open: bool) -> Self:
	var flight := Self.new()
	var entry: Array = DIRECTIONS[direction_key]
	flight.direction_name = direction_key
	flight.dir = (entry[0] as Vector2).normalized()
	flight.across = Vector2(-flight.dir.y, flight.dir.x)
	flight.rim = rim_point
	flight.top = top_level
	flight.bottom = bottom_level
	flight.base = rim_point + Vector2(0.0, LEVEL * top_level)
	flight.half = HALF_CELL * maxi(1, cells)
	flight.open_landing = open
	flight.rail_start = 0.0 if open else -LANDING
	var levels := maxi(1, top_level - bottom_level)
	flight.steps = levels * STEPS_PER_LEVEL
	flight.run = float(entry[1]) * levels / flight.steps
	flight.ramp = flight.steps * flight.run
	flight.end = flight.ramp + BOTTOM
	flight._seed = int(rim_point.x * 7.0 + rim_point.y * 13.0)
	flight._build()
	return flight


## Levels of the flight's two ends.
func joins(level: int) -> bool:
	return level >= bottom and level <= top


## Height of the steps' nosing line above the lower ground at `s` (the landing at the top).
func nosing(s: float) -> float:
	var height := LEVEL * (top - bottom)
	return clampf(height * (1.0 - s / ramp), 0.0, height)


## The point of the flight's frame (s, t, h above the lower ground) on the ground and its absolute
## height: Vector3(x, ground y, H).
func world(p: Vector3) -> Vector3:
	var ground := base + dir * p.x + across * p.y
	return Vector3(ground.x, ground.y, LEVEL * bottom + p.z)


static func screen(w: Vector3) -> Vector2:
	return Vector2(w.x, w.y - w.z)


func screen_of(p: Vector3) -> Vector2:
	return screen(world(p))


## True when `point` (screen) lies on the walkable surface.
func walks(point: Vector2) -> bool:
	return bounds.has_point(point) and Geometry2D.is_point_in_polygon(point, walk)


## True when a body of `level` can stand at `point` (screen): on the steps when the flight joins
## its level, on the landing only at the top level (a body changes level on the way up, so it never
## meets that; nothing steps onto the landing from beside it, as from the hidden strip behind a
## hill).
func walks_level(point: Vector2, level: int) -> bool:
	if not joins(level) or not walks(point):
		return false
	var s := s_at(point)
	if not is_nan(s) and s < 0.0:
		return level == top
	return true


## The higher ground in front of the flight (screen polygons: the tops of its top level or higher
## around it): the parts of the flight below its top level drawn over them are hidden behind them.
func occlude(polygons: Array[PackedVector2Array]) -> void:
	occluders = polygons
	_occluder_rects.clear()
	for polygon in occluders:
		var rect := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			rect = rect.expand(point)
		_occluder_rects.append(rect)
	var pieces: Array[PackedVector2Array] = []
	for hull: Array in _hulls:
		var parts: Array[PackedVector2Array] = [hull[0]]
		if bool(hull[1]):
			parts = _cut(parts)
		pieces.append_array(parts)
	silhouette = _union(pieces)
	# A foot strip behind the hill's top is hidden with what stands there.
	var visible_feet: Array = []
	for foot: Array in feet:
		var lines: Array = [PackedVector2Array([foot[0], foot[1]])]
		for occluder in occluders:
			var next: Array = []
			for line: PackedVector2Array in lines:
				next.append_array(Geometry2D.clip_polyline_with_polygon(line, occluder))
			lines = next
		for line: PackedVector2Array in lines:
			if line.size() >= 2 and line[0].distance_to(line[line.size() - 1]) > 1.0:
				visible_feet.append([line[0], line[line.size() - 1], foot[2]])
	feet = visible_feet


## Every edge `level`'s collision may run along: the walkable surface's border, the line where its
## landing begins, the blockers' borders.
func outline_edges(level: int) -> Array:
	var edges: Array = []
	for polygon: PackedVector2Array in [walk] + blockers(level):
		for i in polygon.size():
			edges.append([polygon[i], polygon[(i + 1) % polygon.size()]])
	edges.append([screen_of(Vector3(0.0, -half, nosing(0.0))), screen_of(Vector3(0.0, half, nosing(0.0)))])
	return edges


## `outline_edges(level)` cut where they cross each other (built once per level).
func outline_pieces(level: int) -> Array:
	if not _pieces.has(level):
		var pieces: Array = []
		var edges := outline_edges(level)
		for edge: Array in edges:
			pieces.append_array(Elevation.split_edge(edge, edges))
		_pieces[level] = pieces
	return _pieces[level]


## What of the structure stands at `level`'s height, drawn at that height (screen quads): each solid's
## cross-section there. A body of that level walking on its ground meets these; the parts above it
## only hide it.
func blockers(level: int) -> Array[PackedVector2Array]:
	if _blockers.has(level):
		return _blockers[level]
	var h := LEVEL * (level - bottom)
	var quads: Array[PackedVector2Array] = []
	for solid: Array in _solids:
		var span := _span_at(solid, h)
		if span.y - span.x < 0.01:
			continue
		var t0 := float(solid[2])
		var t1 := float(solid[3])
		quads.append(PackedVector2Array([screen_of(Vector3(span.x, t0, h)), screen_of(Vector3(span.y, t0, h)),
				screen_of(Vector3(span.y, t1, h)), screen_of(Vector3(span.x, t1, h))]))
	# A body on the steps stands at their height, not its level's: the railings along the nosing line
	# hold it there, at every level the flight joins.
	if joins(level):
		var from := maxf(rail_start, -LANDING)
		for side: float in [-1.0, 1.0]:
			for piece: Vector2 in [Vector2(from, 0.0), Vector2(0.0, ramp), Vector2(ramp, end)]:
				if piece.y - piece.x < 0.01:
					continue
				quads.append(PackedVector2Array([screen_of(Vector3(piece.x, side * half, nosing(piece.x))), screen_of(Vector3(piece.y, side * half, nosing(piece.y))),
						screen_of(Vector3(piece.y, side * (half + RAIL), nosing(piece.y))), screen_of(Vector3(piece.x, side * (half + RAIL), nosing(piece.x)))]))
	_blockers[level] = quads
	return quads


## True when a body of `level` standing at `point` (screen) meets the structure.
func blocks(point: Vector2, level: int) -> bool:
	if not bounds.has_point(point):
		return false
	for quad in blockers(level):
		if Geometry2D.is_point_in_polygon(point, quad):
			return true
	return false


## The stretch along s where `solid` reaches through height `h` (from its floor to above it):
## Vector2(s from, s to), empty (y <= x) where it does not.
static func _span_at(solid: Array, h: float) -> Vector2:
	var lo := 0.0
	var hi := 1.0
	# floor(u) <= h + 0.5 and top(u) >= h + 0.5, both linear in u along the solid.
	for bound: Array in [[float(solid[4]), float(solid[5]), true], [float(solid[6]), float(solid[7]), false]]:
		var a := float(bound[0]) - (h + 0.5)
		var b := float(bound[1]) - (h + 0.5)
		var below := bool(bound[2])
		if is_equal_approx(a, b):
			if (a > 0.0) if below else (a < 0.0):
				return Vector2(1.0, 0.0)
			continue
		var u := a / (a - b)
		var rising := b > a
		# below: keep where value <= 0; above: keep where value >= 0.
		if below == rising:
			hi = minf(hi, u)
		else:
			lo = maxf(lo, u)
	if hi <= lo:
		return Vector2(1.0, 0.0)
	var s0 := float(solid[0])
	var s1 := float(solid[1])
	return Vector2(lerpf(s0, s1, lo), lerpf(s0, s1, hi))


## True when `point` (screen) lies on the structure (walkable or not). Fences use it too: a fence
## leaves a gap where a flight stands on its line (elevation_fences.gd `_crosses_stairs`).
func occupies(point: Vector2) -> bool:
	if not bounds.has_point(point):
		return false
	if Geometry2D.is_point_in_polygon(point, walk):
		return true
	for shape in silhouette:
		if Geometry2D.is_point_in_polygon(point, shape):
			return true
	return false


## s along the flight of the walkable surface's point drawn at `point`, NAN off it.
func s_at(point: Vector2) -> float:
	var height := LEVEL * (top - bottom)
	# Three pieces, each affine on screen: the landing, the ramp of nosings, the last step.
	for piece: Array in [[-LANDING, 0.0, height, 0.0], [0.0, ramp, height, -height / ramp], [ramp, end, 0.0, 0.0]]:
		var s0 := float(piece[0])
		var s1 := float(piece[1])
		var h0 := float(piece[2])
		var slope := float(piece[3])
		# screen = A + s · Ds + t · Ts with H(s) = h0 + slope · (s − s0).
		var a := screen_of(Vector3(s0, 0.0, h0)) - (dir * s0 + Vector2(0.0, -slope * s0))
		var ds := Vector2(dir.x, dir.y - slope)
		var ts := across
		var det := ds.x * ts.y - ds.y * ts.x
		if absf(det) < 1e-6:
			continue
		var q := point - a
		var s := (q.x * ts.y - q.y * ts.x) / det
		var t := (ds.x * q.y - ds.y * q.x) / det
		if s >= s0 - 0.01 and s <= s1 + 0.01 and absf(t) <= half + 0.01:
			return s
	return NAN


## The level of the stretch of the flight at `point` (the upper half of a level's stretch takes the
## level above it), `fallback` off the walkable surface.
func level_at(point: Vector2, fallback: int) -> int:
	var s := s_at(point)
	if is_nan(s):
		return fallback
	return clampi(bottom + roundi(nosing(s) / LEVEL), bottom, top)


## The depth (ground y) of a body standing at `point` (screen) on the flight.
func depth_at(point: Vector2) -> float:
	var s := s_at(point)
	return point.y + LEVEL * bottom + (nosing(s) if not is_nan(s) else 0.0)


# --- building ------------------------------------------------------------------------------

func _build() -> void:
	var height := LEVEL * (top - bottom)
	# The walkable surface: both sides of it, along the nosing line.
	walk = PackedVector2Array()
	for s: float in [-LANDING, 0.0, ramp, end]:
		walk.append(screen_of(Vector3(s, -half, nosing(s))))
	for s: float in [end, ramp, 0.0, -LANDING]:
		walk.append(screen_of(Vector3(s, half, nosing(s))))
	_hulls.clear()
	_hulls.append([_hull([Vector3(-LANDING, -half, height), Vector3(0.0, -half, height), Vector3(0.0, half, height), Vector3(-LANDING, half, height)]), false])
	_solids.clear()
	_blockers.clear()
	_pieces.clear()
	for k in steps:
		var s0 := k * run
		var s1 := (k + 1) * run if k < steps - 1 else end
		_solids.append([s0, s1, -half, half, 0.0, 0.0, height - (k + 1) * RISE, height - (k + 1) * RISE])
		_hulls.append([_box_hull(s0, s1, -half, half, 0.0, height - (k + 1) * RISE), true])
		_hulls.append([_hull([Vector3(s0, -half, height - k * RISE), Vector3(s0, half, height - k * RISE), Vector3(s0, half, height - (k + 1) * RISE), Vector3(s0, -half, height - (k + 1) * RISE)]), true])
	for side: float in [-1.0, 1.0]:
		var inner := side * half
		var outer := side * (half + RAIL)
		for piece: Array in _rail_pieces():
			var sa := float(piece[0])
			var sb := float(piece[1])
			_solids.append([sa, sb, minf(inner, outer), maxf(inner, outer), float(piece[2]), float(piece[3]), float(piece[4]), float(piece[5])])
			_hulls.append([_hull([Vector3(sa, inner, float(piece[2])), Vector3(sb, inner, float(piece[3])), Vector3(sa, outer, float(piece[2])), Vector3(sb, outer, float(piece[3])),
					Vector3(sa, inner, float(piece[4])), Vector3(sb, inner, float(piece[5])), Vector3(sa, outer, float(piece[4])), Vector3(sb, outer, float(piece[5]))]), float(piece[2]) < height])
		var p_in := side * half
		var p_out := side * (half + RAIL + POST_OUT)
		for post: Array in _posts():
			_solids.append([float(post[0]), float(post[1]), minf(p_in, p_out), maxf(p_in, p_out), float(post[2]), float(post[2]), float(post[3]), float(post[3])])
			_hulls.append([_box_hull(float(post[0]), float(post[1]), minf(p_in, p_out), maxf(p_in, p_out), float(post[2]), float(post[3])), float(post[2]) < height])
	var pieces: Array[PackedVector2Array] = []
	for hull: Array in _hulls:
		pieces.append(hull[0])
	silhouette = _union(pieces)
	bounds = Rect2(walk[0], Vector2.ZERO)
	for point in walk:
		bounds = bounds.expand(point)
	for shape in silhouette:
		for point in shape:
			bounds = bounds.expand(point)
	bounds = bounds.grow(1.0)
	_build_faces()


## The railing's three stretches: [s from, s to, floor from, floor to, top from, top to] (h above
## the lower ground): over the landing (railed landing only), down the steps, over the last step.
func _rail_pieces() -> Array:
	var height := LEVEL * (top - bottom)
	var pieces := []
	if rail_start < 0.0:
		pieces.append([rail_start, 0.0, height, height, height + RAIL_UP, height + RAIL_UP])
	pieces.append([0.0, ramp, 0.0, 0.0, height + RAIL_UP, RAIL_UP])
	pieces.append([ramp, end, 0.0, 0.0, RAIL_UP, RAIL_UP])
	return pieces


## The newel posts of a railing: [s from, s to, floor, top] at its two ends.
func _posts() -> Array:
	var height := LEVEL * (top - bottom)
	var floor_top := height if rail_start < 0.0 else 0.0
	return [[rail_start, rail_start + POST, floor_top, height + RAIL_UP + POST_UP], [end - POST, end, 0.0, RAIL_UP + POST_UP]]


func _hull(points: Array) -> PackedVector2Array:
	var flat := PackedVector2Array()
	for p: Vector3 in points:
		flat.append(screen_of(p))
	var hull := Geometry2D.convex_hull(flat)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull


func _box_hull(s0: float, s1: float, t0: float, t1: float, h0: float, h1: float) -> PackedVector2Array:
	var corners := []
	for s: float in [s0, s1]:
		for t: float in [t0, t1]:
			for h: float in [h0, h1]:
				corners.append(Vector3(s, t, h))
	return _hull(corners)


## The union of convex screen shapes, merged where they overlap (touching ones stay apart: their
## shared edge has the structure on both sides, so no collision runs along it); holes are filled.
static func _union(hulls: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var shapes: Array[PackedVector2Array] = []
	for hull in hulls:
		if hull.size() < 3 or absf(_area(hull)) < 0.01:
			continue
		var current := hull
		var rest: Array[PackedVector2Array] = []
		for shape in shapes:
			if Geometry2D.intersect_polygons(shape, current).is_empty():
				rest.append(shape)
				continue
			var biggest := PackedVector2Array()
			for merged: PackedVector2Array in Geometry2D.merge_polygons(shape, current):
				if absf(_area(merged)) > absf(_area(biggest)):
					biggest = merged
			current = biggest
		rest.append(current)
		shapes = rest
	return shapes


static func _area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


# --- faces ---------------------------------------------------------------------------------

## The faces in the order they are drawn: the far railing's inner face, the landing and the steps
## from the far end, then each railing (far first) between its posts: the post at the far end of
## the flight before it, the one at the near end after it. Faces turned away are left out.
func _build_faces() -> void:
	faces.clear()
	var height := LEVEL * (top - bottom)
	# Which side is nearer the camera (+ground y), and which end.
	var near_side := 1.0 if across.y > 1e-6 else (-1.0 if across.y < -1e-6 else 0.0)
	var toward_end := signf(dir.y) if absf(dir.y) > 1e-6 else 0.0
	var sides: Array[float] = [-1.0, 1.0]
	if near_side != 0.0:
		sides = [-near_side, near_side]
	if near_side != 0.0:
		_rail_side_face(-near_side, true)
	# The landing and the steps, from the far end.
	var parts: Array = []
	parts.append([-LANDING * 0.5, _tread(-LANDING, 0.0, height, false, 0)])
	for k in steps:
		var s0 := k * run
		var s1 := (k + 1) * run if k < steps - 1 else end
		parts.append([s0, _riser(s0, height - k * RISE, height - (k + 1) * RISE, k)])
		parts.append([(s0 + s1) * 0.5, _tread(s0, s1, height - (k + 1) * RISE, true, k + 1)])
	if toward_end < 0.0:
		parts.reverse()
	for part: Array in parts:
		if not (part[1] as Dictionary).is_empty():
			faces.append(part[1])
	var posts := _posts()
	for side in sides:
		if toward_end == 0.0:
			_rail_faces(side, near_side == 0.0 or side == near_side)
			_post_faces(side, posts[0])
			_post_faces(side, posts[1])
			continue
		_post_faces(side, posts[0] if toward_end > 0.0 else posts[1])
		_rail_faces(side, near_side == 0.0 or side == near_side)
		_post_faces(side, posts[1] if toward_end > 0.0 else posts[0])


## Light of a face by the way it looks (0 when turned away from the camera).
static func shade_for(normal: Vector3) -> float:
	if normal.z > 0.3:
		return 1.0
	if normal.y <= 1e-6:
		return 0.0
	var nx := normal.x / sqrt(0.5)
	return SHADE_SOUTH - SHADE_SPREAD * clampf(nx, -1.0, 1.0)


func _face(kind: int, quad: Array, normal: Vector3, extra: Dictionary = {}) -> Dictionary:
	var shade := shade_for(normal.normalized())
	if shade <= 0.0:
		return {}
	var face := {"kind": kind, "quad": quad, "normal": normal, "shade": shade}
	face.merge(extra)
	return face


func _offset(index: int) -> float:
	return float(posmod(_seed * 31 + index * 977, 2000))


## A tread (or the landing) from s0 to s1 at height h; `front`: it has a nosing.
func _tread(s0: float, s1: float, h: float, front: bool, index: int) -> Dictionary:
	return _face(KIND_TREAD, [Vector3(s0, -half, h), Vector3(s1, -half, h), Vector3(s1, half, h), Vector3(s0, half, h)],
			Vector3(0, 0, 1), {"s0": s0, "depth": s1 - s0, "front": front, "off": _offset(index)})


## A riser at s from h_top down to h_bottom, facing down the flight.
func _riser(s: float, h_top: float, h_bottom: float, index: int) -> Dictionary:
	return _face(KIND_RISER, [Vector3(s, -half, h_top), Vector3(s, half, h_top), Vector3(s, half, h_bottom), Vector3(s, -half, h_bottom)],
			Vector3(dir.x, dir.y, 0), {"off": _offset(index + 1) * 0.7})


## One side face of a railing (inner or outer) as quads per stretch; the inner one in bands for
## its contact shadow with the steps.
func _rail_side_face(side: float, inner: bool) -> void:
	var t_face := side * (half if inner else half + RAIL)
	var normal_sign := -side if inner else side
	var normal := Vector3(across.x * normal_sign, across.y * normal_sign, 0)
	if shade_for(normal) <= 0.0:
		return
	var span := end - rail_start
	for piece: Array in _rail_pieces():
		var sa := float(piece[0])
		var sb := float(piece[1])
		var floors := Vector2(float(piece[2]), float(piece[3]))
		var tops := Vector2(float(piece[4]), float(piece[5]))
		var bands: Array = [[floors, tops]]
		if inner:
			var n := Vector2(nosing(sa), nosing(sb))
			var contact := n + Vector2.ONE * RAIL_CONTACT_REACH
			bands = [[floors, n], [n, contact], [contact, tops]]
		for band: Array in bands:
			var lo: Vector2 = band[0]
			var hi: Vector2 = band[1]
			if hi.x - lo.x <= 0.01 and hi.y - lo.y <= 0.01:
				continue
			faces.append({"kind": KIND_WALL, "quad": [Vector3(sa, t_face, lo.x), Vector3(sb, t_face, lo.y), Vector3(sb, t_face, hi.y), Vector3(sa, t_face, hi.x)],
					"normal": normal, "shade": shade_for(normal), "along": "s", "contact": inner,
					"lines": [(sa - rail_start) / span, (sb - rail_start) / span]})


## A railing's faces but the far railing's inner face (drawn before the steps): the outer face,
## the coping along its top, its two ends.
func _rail_faces(side: float, with_inner: bool) -> void:
	var inner := side * half
	var outer := side * (half + RAIL)
	_rail_side_face(side, false)
	if shade_for(Vector3(across.x * side, across.y * side, 0)) > 0.0:
		feet.append([screen_of(Vector3(0.0, outer, 0.0)), screen_of(Vector3(end, outer, 0.0)), bottom])
	if with_inner:
		_rail_side_face(side, true)
	for piece: Array in _rail_pieces():
		var sa := float(piece[0])
		var sb := float(piece[1])
		var ha := float(piece[4])
		var hb := float(piece[5])
		var slope := (hb - ha) / maxf(1e-6, sb - sa)
		var up := Vector3(-dir.x * slope, -dir.y * slope, 1.0)
		var cap := _face(KIND_COPING, [Vector3(sa, inner, ha), Vector3(sb, inner, hb), Vector3(sb, outer, hb), Vector3(sa, outer, ha)], up)
		if not cap.is_empty():
			faces.append(cap)
	var floor_start := LEVEL * (top - bottom) if rail_start < 0.0 else 0.0
	var high := LEVEL * (top - bottom) + RAIL_UP
	for end_face: Dictionary in [
			_face(KIND_WALL, [Vector3(end, inner, 0), Vector3(end, outer, 0), Vector3(end, outer, RAIL_UP), Vector3(end, inner, RAIL_UP)], Vector3(dir.x, dir.y, 0), {"along": "t"}),
			_face(KIND_WALL, [Vector3(rail_start, outer, floor_start), Vector3(rail_start, inner, floor_start), Vector3(rail_start, inner, high), Vector3(rail_start, outer, high)], Vector3(-dir.x, -dir.y, 0), {"along": "t"})]:
		if not end_face.is_empty():
			faces.append(end_face)


## A newel post's faces: [s from, s to, floor, top].
func _post_faces(side: float, post: Array) -> void:
	var s0 := float(post[0])
	var s1 := float(post[1])
	var h0 := float(post[2])
	var h1 := float(post[3])
	var t0 := minf(side * half, side * (half + RAIL + POST_OUT))
	var t1 := maxf(side * half, side * (half + RAIL + POST_OUT))
	var d := Vector3(dir.x, dir.y, 0)
	var t := Vector3(across.x, across.y, 0)
	for face: Dictionary in [
			_face(KIND_WALL, [Vector3(s1, t0, h0), Vector3(s1, t1, h0), Vector3(s1, t1, h1), Vector3(s1, t0, h1)], d, {"along": "t"}),
			_face(KIND_WALL, [Vector3(s0, t1, h0), Vector3(s0, t0, h0), Vector3(s0, t0, h1), Vector3(s0, t1, h1)], -d, {"along": "t"}),
			_face(KIND_WALL, [Vector3(s0, t1, h0), Vector3(s1, t1, h0), Vector3(s1, t1, h1), Vector3(s0, t1, h1)], t, {"along": "s"}),
			_face(KIND_WALL, [Vector3(s1, t0, h0), Vector3(s0, t0, h0), Vector3(s0, t0, h1), Vector3(s1, t0, h1)], -t, {"along": "s"}),
			_face(KIND_COPING, [Vector3(s0, t0, h1), Vector3(s1, t0, h1), Vector3(s1, t1, h1), Vector3(s0, t1, h1)], Vector3(0, 0, 1))]:
		if not face.is_empty():
			faces.append(face)
	# The foot of a post standing on the lower ground in sight: its front faces the camera, and it is
	# not the far post, behind the steps.
	if is_zero_approx(h0) and dir.y > 1e-6 and side * across.y >= -1e-6:
		feet.append([screen_of(Vector3(s1, t0, 0.0)), screen_of(Vector3(s1, t1, 0.0)), bottom])


# --- output --------------------------------------------------------------------------------

## The faces into `mesh` (the stairs shader): UV.x texture px, UV.y the kind's texture coordinate
## + kind · KIND_OFFSET; colour r = light / 2, g = height in levels ((L + 4) / 8), b and a = where
## on the face (0 … 1 across both ways: the shader's joint lines). `course` = the cliff's course at
## the top level (posmod(top, 2) · 64), so railings show the wall's joints level with the cliff's.
func add_mesh(mesh: MeshData) -> void:
	for face in faces:
		var cuts := _cuts(face)
		var fu: PackedFloat32Array = cuts[0]
		var fv: PackedFloat32Array = cuts[1]
		for i in fu.size() - 1:
			for j in fv.size() - 1:
				var inside := Vector2((fu[i] + fu[i + 1]) * 0.5, (fv[j] + fv[j + 1]) * 0.5)
				var corners: Array = []
				for f: Vector2 in [Vector2(fu[i], fv[j]), Vector2(fu[i + 1], fv[j]), Vector2(fu[i + 1], fv[j + 1]), Vector2(fu[i], fv[j + 1])]:
					corners.append(_vertex(face, f, inside))
				_emit(mesh, [corners[0], corners[1], corners[2]])
				_emit(mesh, [corners[0], corners[2], corners[3]])


## The faces into the depth map: depth = ground y, written as level `top` and dy = 64 · top − H
## (marked as a structure: the cast shadows read its height, not its level).
func add_depth(depth: MeshData) -> void:
	for face in faces:
		var corners: Array = []
		for p: Vector3 in face["quad"]:
			var w := world(p)
			corners.append([screen(w), Vector2.ZERO, ElevationOcclusion.encode(top, LEVEL * top - w.z, true), w.z])
		_emit(depth, [corners[0], corners[1], corners[2]])
		_emit(depth, [corners[0], corners[2], corners[3]])


## Where a face is cut for its light: fractions along its two sides.
func _cuts(face: Dictionary) -> Array:
	var kind := int(face["kind"])
	var fu := PackedFloat32Array([0.0, 1.0])
	var fv := PackedFloat32Array([0.0, 1.0])
	var width := 2.0 * half
	if kind == KIND_TREAD:
		var depth := float(face["depth"])
		fu = PackedFloat32Array([0.0, TREAD_AO_REACH, 1.0 - NOSING / depth, 1.0]) if bool(face["front"]) else PackedFloat32Array([0.0, 1.0])
		fv = PackedFloat32Array([0.0, TREAD_EDGE_REACH / width, 1.0 - TREAD_EDGE_REACH / width, 1.0])
	elif kind == KIND_RISER:
		fu = PackedFloat32Array([0.0, RISER_EDGE_REACH / width, 1.0 - RISER_EDGE_REACH / width, 1.0])
		fv = PackedFloat32Array([0.0, RISER_AO_REACH, 1.0])
	return [fu, fv]


## Light of a face at (fu, fv), taken inside the cell around `inside` (so a step in it stays sharp).
func _light(face: Dictionary, f: Vector2) -> float:
	var kind := int(face["kind"])
	var light := float(face["shade"])
	var width := 2.0 * half
	if kind == KIND_TREAD:
		var edge := clampf(minf(f.y, 1.0 - f.y) * width / TREAD_EDGE_REACH, 0.0, 1.0)
		light *= TREAD_EDGE + (1.0 - TREAD_EDGE) * edge
		if bool(face["front"]):
			light *= TREAD_AO + (1.0 - TREAD_AO) * clampf(f.x / TREAD_AO_REACH, 0.0, 1.0)
			if f.x > 1.0 - NOSING / float(face["depth"]):
				light *= NOSING_LIGHT
	elif kind == KIND_RISER:
		var edge := clampf(minf(f.x, 1.0 - f.x) * width / RISER_EDGE_REACH, 0.0, 1.0)
		light *= (RISER_AO + (1.0 - RISER_AO) * clampf(f.y / RISER_AO_REACH, 0.0, 1.0)) * (RISER_EDGE + (1.0 - RISER_EDGE) * edge)
	elif kind == KIND_WALL and bool(face.get("contact", false)):
		pass
	return light


## A vertex of a face at (fu, fv): [screen point, UV, colour, absolute height].
func _vertex(face: Dictionary, f: Vector2, inside: Vector2) -> Array:
	var quad: Array = face["quad"]
	var p: Vector3 = (quad[0] as Vector3).lerp(quad[1], f.x).lerp((quad[3] as Vector3).lerp(quad[2], f.x), f.y)
	var w := world(p)
	var kind := int(face["kind"])
	# Light is taken just inside the cell, so steps in it (the nosing) stay sharp.
	var light := _light(face, f.lerp(inside, 0.001))
	if kind == KIND_WALL and bool(face.get("contact", false)):
		light *= _contact(p)
	var uv := Vector2.ZERO
	var height := LEVEL * (top - bottom)
	match kind:
		KIND_TREAD:
			uv = Vector2(p.y * PX + float(face["off"]), clampf((p.x - float(face["s0"])) / float(face["depth"]), 0.0, 1.0))
		KIND_RISER:
			uv = Vector2(p.y * PX + float(face["off"]), (height - p.z) / RISE)
		KIND_COPING:
			uv = Vector2(p.x * PX * 1.6 + 220.0, clampf((absf(p.y) - half) / (RAIL + POST_OUT), 0.0, 1.0))
		_:
			var along := p.x if str(face.get("along", "s")) == "s" else p.y
			var course := float(posmod(top, 2)) * LEVEL
			uv = Vector2(along * PX + 300.0, (height - p.z + course) * PX)
	var lines := f
	if face.has("lines"):
		# A railing's side, cut in stretches: its joint lines only along the whole face's border.
		var span: Array = face["lines"]
		lines = Vector2(lerpf(float(span[0]), float(span[1]), f.x), f.y if not bool(face.get("contact", false)) else 0.5)
	return [screen(w), Vector2(uv.x, uv.y + kind * KIND_OFFSET),
			Color(clampf(light * 0.5, 0.0, 1.0), (w.z / LEVEL + 4.0) / 8.0, lines.x, lines.y), w.z]


## One triangle of vertices [screen point, UV, colour, height] into `mesh`, without what of it lies
## below the top level behind the higher ground in front (`occluders`).
func _emit(mesh: MeshData, triangle: Array) -> void:
	var points := PackedVector2Array([triangle[0][0], triangle[1][0], triangle[2][0]])
	var below_top := PackedFloat32Array()
	var lowest := INF
	for vertex: Array in triangle:
		below_top.append(float(vertex[3]) - (LEVEL * top - OCCLUDE_MARGIN))
		lowest = minf(lowest, below_top[below_top.size() - 1])
	if occluders.is_empty() or lowest >= 0.0:
		for vertex: Array in triangle:
			mesh.add(vertex[0], vertex[1], vertex[2])
		return
	var halves := _split(points, below_top)
	if (halves[1] as PackedVector2Array).size() >= 3:
		_add_polygon(mesh, triangle, halves[1])
	if (halves[0] as PackedVector2Array).size() >= 3:
		for part in _cut([halves[0]]):
			_add_polygon(mesh, triangle, part)


## `parts` without the occluders.
func _cut(parts: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	for index in occluders.size():
		var next: Array[PackedVector2Array] = []
		for part in parts:
			var box := Rect2(part[0], Vector2.ZERO)
			for point in part:
				box = box.expand(point)
			if not box.intersects(_occluder_rects[index]):
				next.append(part)
				continue
			next.append_array(_difference(part, occluders[index], _occluder_rects[index], 2))
		parts = next
	return parts


## `part` without `occluder`. Where the occluder lies inside the part, the difference would have a
## hole (which the drawing cannot fill around): the part is cut in two through the occluder first.
static func _difference(part: PackedVector2Array, occluder: PackedVector2Array, rect: Rect2, depth: int) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var clipped := Geometry2D.clip_polygons(part, occluder)
	var holed := false
	for a: PackedVector2Array in clipped:
		for b: PackedVector2Array in clipped:
			if a != b and Geometry2D.is_point_in_polygon(b[0], a):
				holed = true
	if holed and depth > 0:
		var middle := rect.get_center().y
		var far := 1.0e6
		for half: PackedVector2Array in [PackedVector2Array([Vector2(-far, -far), Vector2(far, -far), Vector2(far, middle), Vector2(-far, middle)]),
				PackedVector2Array([Vector2(-far, middle), Vector2(far, middle), Vector2(far, far), Vector2(-far, far)])]:
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(part, half):
				result.append_array(_difference(piece, occluder, rect, depth - 1))
		return result
	for polygon: PackedVector2Array in clipped:
		if polygon.size() >= 3 and absf(_area(polygon)) > 0.01:
			result.append(polygon)
	return result


## A triangle's points split where `values` (affine over it) crosses 0: [below, above].
static func _split(points: PackedVector2Array, values: PackedFloat32Array) -> Array:
	var below := PackedVector2Array()
	var above := PackedVector2Array()
	for i in 3:
		var a := values[i]
		var b := values[(i + 1) % 3]
		if a < 0.0:
			below.append(points[i])
		else:
			above.append(points[i])
		if (a < 0.0) != (b < 0.0):
			var crossing := points[i].lerp(points[(i + 1) % 3], a / (a - b))
			below.append(crossing)
			above.append(crossing)
	return [below, above]


## A polygon inside `triangle` into `mesh`, its UV and colours interpolated from the triangle's.
static func _add_polygon(mesh: MeshData, triangle: Array, polygon: PackedVector2Array) -> void:
	var points := _clean(polygon)
	if points.size() < 3:
		return
	var corners := PackedVector2Array()
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		# Triangulation can fail on a sliver: fan out its convex pieces instead.
		for convex: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(points):
			for i in range(1, convex.size() - 1):
				corners.append_array([convex[0], convex[i], convex[i + 1]])
	else:
		for index in indices:
			corners.append(points[index])
	var a: Vector2 = triangle[0][0]
	var b: Vector2 = triangle[1][0]
	var c: Vector2 = triangle[2][0]
	for q in corners:
		var weights := _barycentric(q, a, b, c)
		var uv: Vector2 = (triangle[0][1] as Vector2) * weights.x + (triangle[1][1] as Vector2) * weights.y + (triangle[2][1] as Vector2) * weights.z
		var color: Color = (triangle[0][2] as Color) * weights.x + (triangle[1][2] as Color) * weights.y + (triangle[2][2] as Color) * weights.z
		mesh.add(q, uv, color)


## `polygon` without points repeating their neighbour (a cut through a corner leaves them).
static func _clean(polygon: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in polygon:
		if points.is_empty() or points[points.size() - 1].distance_to(point) > 0.001:
			points.append(point)
	while points.size() > 1 and points[0].distance_to(points[points.size() - 1]) <= 0.001:
		points.remove_at(points.size() - 1)
	return points


static func _barycentric(q: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := q - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	if absf(denom) < 1e-9:
		return Vector3(1.0, 0.0, 0.0)
	var v := (d11 * d20 - d01 * d21) / denom
	var w := (d00 * d21 - d01 * d20) / denom
	return Vector3(1.0 - v - w, v, w)


## The contact shadow on a railing's inner face where it meets the steps.
func _contact(p: Vector3) -> float:
	var above := p.z - nosing(p.x)
	return RAIL_CONTACT + (1.0 - RAIL_CONTACT) * clampf(above / RAIL_CONTACT_REACH, 0.0, 1.0)
