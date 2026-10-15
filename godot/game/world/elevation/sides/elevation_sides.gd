extends RefCounted
## Cliffs that read as raised blocks from all four sides (docs/godot/ELEVATION.md "Side walls",
## 2026-10-13): besides the front (south) wall, the east and west sides show a narrow strip of the
## same wall seen from the side, and the back (north) edge no wall at all; front corners are round, the
## wall turning from the front onto the side, while at a back corner the side wall starts with a
## slanted end, so the back edge visibly runs on behind it (the ground behind the hill can be walked).
## Tops and feet wobble instead of running ruler-straight. A world picks this look with its ground
## layer's metadata `cliff_look` = "sides" (Elevation `_sides_look`); the model, collision, stairs
## and ramps stay the elevation system's.
##
## How it is drawn. Every top's border (ElevationRims.boundary_edges, the top on the left) is
## chained per level into loops and lines, its corners rounded (RADIUS_OUTER, RADIUS_INNER;
## RADIUS_BACK at a back corner, RADIUS_FOLD where a side meets an edge at an inner corner) and
## resampled every STEP units. Each point hangs a "fibre": from the top edge (wobbled, TOP_WOBBLE) to
## the foot, the way its outward normal points, as long as the reach of a shape K for its drop
## (`reach`): FRONT per level down on a front face, SIDE out on a side, nothing on a back edge
## (BACK_FADE), a superellipse (SHAPE) between them, so a front corner's wall turns smoothly onto the
## side. Next to a back corner a side's fibres are cut to CAP_SLOPE of their distance from it
## (`_caps`); at an inner corner of a front wall and a side wall the two fold into one wall, its
## courses running on round the corner (`_fold_corners`). The wall art runs along the border (u,
## scaled so a loop closes on a whole number of the art's periods) and down the fibre (v, one stone
## course per level); a side shows one course across, its stones shorter (`_side_ramps`, `side_of`).
## Faces are lit by the way they look (west lit, east dark).
##
## The edges are drawn, not painted (the owner, 2026-10-13: "simpler borders ... like the initial
## reference"): along the top edge the top's own ground, darkening towards the edge and hanging a
## little over the wall in clumps with a dark outline along them (on a back edge, with no wall, a
## dark green one); along the foot a dark line over a few clumps of the lower ground and a soft
## shadow on it (a back edge only the shadow) (elevation_sides.gdshader).
##
## Painter's order: one mesh per level, wall style and grounds (`build` returns them lowest level
## first). Its pieces are drawn by the depth of the top edge they hang from (the screen y of the
## smooth border): where faces overlap, at an inner corner, the nearer (more southern) face is drawn
## over the farther one. A top edge follows its wall a little (EDGE_LEAD), a foot a stretch more
## (FOOT_LEAD), so they stay over the walls they belong to.
##
## Owner: world (elevation).

const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const ElevationRims := preload("res://game/world/elevation/elevation_rims.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")

## A wall's reach (world units): down a front face FRONT per level of drop (one stone course), out
## from a side SIDE for one level, growing as the drop to the power THIN_GROWTH for more (a tall
## side stays a strip); between them a superellipse of exponent SHAPE (2 an ellipse, higher
## squarer). A back edge shows no wall (the owner, 2026-10-13: "in the top not black wall hint"):
## the side's reach fades out as the normal turns north (`BACK_FADE`).
const FRONT := 64.0
const SIDE := 24.0
const THIN_GROWTH := 0.7
const BACK_FADE := Vector2(0.2, 0.6)
const SHAPE := 2.5
## The wall art's u runs along the curve this far down the fibres (0 the top edge, 1 the foot): at a
## front corner the fibres fan out, and the stones keep their width there.
const U_DEPTH := 0.6
## Along a side wall the stones are this many times shorter than along a front wall, and the wall
## shows one course across its width whatever its height (the concept's side faces: a single column
## of short rounded stones); both turn with the fibres round a corner (`side_of`).
const SIDE_U_RATE := 2.6
const SIDE_RAMP := 56.0
## Corner radii of a top's border (world units): outer (convex) and inner (concave) corners, and
## RADIUS_BACK at an outer corner of a back edge and a side (the side wall starts with a slanted end
## past it; the owner, 2026-10-13: the top's corners "a little more rounded").
const RADIUS_OUTER := 40.0
const RADIUS_INNER := 20.0
const RADIUS_BACK := 34.0
const RADIUS_WATER := 3.0
## TerrainMaterials.WATER, the ground whose feet are foam.
const WATER := "water"
## Next to a back corner a side's wall is this wide per unit along the side from the corner (until
## its full width): its end is slanted, as the owner's reference draws it.
const CAP_SLOPE := 0.65
## Point spacing along straight runs (world units). Around a corner the fibres swing fast (a side
## strip's turns into a front wall's within a few degrees), so its arc is sampled every ARC_FINE
## radians and a point kept wherever its top edge or its foot has moved STEP from the last one.
const STEP := 6.0
const ARC_FINE := 0.005
## Wobble of the top edge and of the foot (world units, along the normal) and its wavelengths.
const TOP_WOBBLE := 3.5
const FOOT_WOBBLE := 4.0
const WOBBLE_LONG := 56.0
const WOBBLE_SHORT := 21.0
## Light of a face by the way it looks (the light comes from the upper left).
const SHADE_FRONT := 0.86
const SHADE_EAST := 0.6
const SHADE_WEST := 1.04
const SHADE_BACK := 0.5
## The edges' reaches (world units): the top edge EDGE_IN over the top (its darkening band) and
## EDGE_OUT past the edge (the hanging clumps); the foot FOOT_UP up the wall (clumps and line) and
## FOOT_OUT over the lower ground (the shadow). elevation_sides.gdshader draws within them.
const EDGE_IN := 12.0
const EDGE_OUT := 9.0
const FOOT_UP := 7.0
const FOOT_OUT := 20.0
## The shadow past a foot: its strength on a front face, more where the foot faces the lower right,
## and its length: FOOT_OUT, plus SHADOW_PER_LEVEL per level of drop as the foot faces east
## (SHADOW_EAST) or south (SHADOW_SOUTH) — the light comes from the upper left, so a hill casts
## its shadow to the lower right, longer for a taller one. It replaces the model's cast shadows
## (Elevation leaves them out in the sides look: they follow the square cells).
const SHADOW_PER_LEVEL := 22.0
const SHADOW_EAST := 1.0
const SHADOW_SOUTH := 0.3
const FOOT_SHADOW := 0.32
## The foot line's way at a point is taken between neighbours this far apart (world units).
const FOOT_SPAN := 8.0
const FOOT_SHADOW_EAST := 0.25
const SHADOW_FROM := Vector2(0.7071, 0.7071)
## Painter's order leads (world units of depth): a top edge and a foot are drawn after the walls this
## far nearer than the edge they hang from.
const EDGE_LEAD := 8.0
const FOOT_LEAD := 24.0
## Vertex colour r of each kind of piece (elevation_sides.gdshader).
## Collision follows the borders and the walls' feet simplified to this many world units.
const SHAPE_TOLERANCE := 0.5
const KIND_WALL := 0.0
## A wall's colour r runs from KIND_WALL to KIND_WALL + KIND_SIDE as it is a side's (the shader
## blends the style's side strip art in by it).
const KIND_SIDE := 0.2
const KIND_CORNER := 0.3
const KIND_FOOT := 0.5
## A foot standing in water: foam.
const KIND_FOOT_WATER := 0.54
## The ground between a corner's arc and the model's square corner: the lower ground outside an
## outer corner, the top's inside an inner one (`_add_corner_fills`).
const KIND_FILL_LOW := 0.6
const KIND_FILL_TOP := 0.7
const KIND_EDGE := 1.0
## Over every outer corner of a front wall and a side wall lies one big rounded corner stone per
## course (the style's `-corners.png`: CORNER_STONES of them side by side, picked by place),
## CORNER_LENGTH units long along the course.
const CORNER_STONES := 4
const CORNER_LENGTH := 72.0
## An inner corner of a front wall and a side wall is one wall folding round (the owner, 2026-10-13:
## "a continuous seamless curve"): from where the second wall's foot meets the first wall's, back
## FOLD_RUN units along the first wall's foot, and as far on along the second's, the fibres turn
## from straight down to straight out (`_fold_corners`), so every stone course runs on round the
## corner, the foot turning a corner of radius FOLD_FOOT_RADIUS there. The top edge turns with
## radius RADIUS_FOLD.
const FOLD_RUN := 56.0
const FOLD_FOOT_RADIUS := 28.0
const RADIUS_FOLD := 14.0

var grid: ElevationGrid
var cell := 64.0
## Every chain's shape for collision (`_add_shape`; `build` fills it): {level, points, belows (the
## level under each point's wall), below (the commonest), lowest, mixed, walls (polygons of the drawn
## walls), wall_bounds,
## zones (between each round outer corner and the model's square corner), edges ([from, to] of the
## border and the walls' outlines), bounds}.
## Elevation traces each lower level's collision along them (`_with_sides`, `_sides_walkable`): the
## drawn walls are solid, the model's square corners outside a round border are ground.
var shapes: Array[Dictionary] = []
## Callable(point) -> bool: true where a ramp's slope lies (a foot's shadow fades out before it).
var _under_ramp: Callable


## A top's border, its corners rounded and resampled (`_border`): per point the smooth point, its
## outward normal, the drop and visible depth (levels), whether a foot grows there (0/1), the rim
## factor (0 a front … 1 a side or back) and the corner it lies on (-1 on a straight run); the
## corners {vertex, e_a, e_b, n_a, n_b, convex, back, radius, tangent, turn, first, last}.
class Border:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var drop := PackedFloat32Array()
	var shown := PackedFloat32Array()
	var foot := PackedFloat32Array()
	var rim := PackedFloat32Array()
	var water := PackedFloat32Array()
	var corner := PackedInt32Array()
	var corners: Array[Dictionary] = []


## The meshes of every top's sides: [{key, level, style, top_ground, low_ground, arrays}] lowest
## level first. `edges`: the tops' boundary edges to draw (ElevationRims.boundary_edges, cells, those
## left out removed). `style_of` (Callable(edge) -> String): the wall style of an edge.
## `grounds_of` (Callable(edge) -> PackedStringArray: the top's ground, the lower ground): the
## grounds its edges are drawn with. `wall_width_of` (Callable(style) -> float): the wall art's
## width in px, so loops close on whole periods. `under_ramp` (Callable(point) -> bool, Elevation
## space): where a ramp's slope lies, drawn over the feet; their shadows fade out before it.
func build(the_grid: ElevationGrid, cell_size: float, edges: Array[Dictionary], style_of: Callable,
		grounds_of: Callable, wall_width_of: Callable, under_ramp: Callable = Callable()) -> Array[Dictionary]:
	grid = the_grid
	cell = cell_size
	shapes.clear()
	_under_ramp = under_ramp
	var by_key := {}
	for chain in _chains(edges):
		var level := int(chain[0]["level"])
		var styles := {}
		var tops := {}
		var lows := {}
		for edge in chain:
			var style := str(style_of.call(edge))
			styles[style] = int(styles.get(style, 0)) + 1
			var grounds: PackedStringArray = grounds_of.call(edge)
			tops[grounds[0]] = int(tops.get(grounds[0], 0)) + 1
			lows[grounds[1]] = int(lows.get(grounds[1], 0)) + 1
		var style := _most(styles)
		var top_ground := _most(tops)
		var low_ground := _most(lows)
		var key := "%d|%s|%s|%s" % [level, style, top_ground, low_ground]
		if not by_key.has(key):
			by_key[key] = {"key": key, "level": level, "style": style, "top_ground": top_ground,
					"low_ground": low_ground, "pieces": []}
		_add_chain(by_key[key]["pieces"], chain, float(wall_width_of.call(style)))
	var out: Array[Dictionary] = []
	for key: String in by_key:
		var entry: Dictionary = by_key[key]
		var pieces: Array = entry["pieces"]
		# Painter's order: pieces filed by their key to a quarter unit (a bucket sort; pieces in one
		# bucket keep the order they were made in), then whole packed arrays appended.
		var buckets := {}
		for piece: Array in pieces:
			var bucket := floori(float(piece[0]) * 4.0)
			if not buckets.has(bucket):
				buckets[bucket] = []
			(buckets[bucket] as Array).append(piece)
		var keys := buckets.keys()
		keys.sort()
		var vertices := PackedVector2Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		for bucket: int in keys:
			for piece: Array in buckets[bucket]:
				vertices.append_array(piece[1])
				uvs.append_array(piece[2])
				colors.append_array(piece[3])
		var arrays := MeshData.new()
		arrays.vertices = vertices
		arrays.uvs = uvs
		arrays.colors = colors
		entry.erase("pieces")
		entry["arrays"] = arrays
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) < int(b["level"]))
	return out


## The reach of a wall `drop` levels high for outward normal `n` (world units): the point of the
## shape K (FRONT · drop down, SIDE · drop^THIN_GROWTH out, a superellipse of exponent SHAPE)
## furthest along `n`; facing north, the side's reach fading to nothing (BACK_FADE).
static func reach(n: Vector2, drop: float) -> Vector2:
	if drop <= 0.0:
		return Vector2.ZERO
	var side := SIDE * pow(drop, THIN_GROWTH)
	if n.y < 0.0:
		return Vector2(side * signf(n.x) * (1.0 - smoothstep(BACK_FADE.x, BACK_FADE.y, -n.y)), 0.0)
	var down := FRONT * drop
	var a := side * n.x
	var c := down * n.y
	var q := SHAPE / (SHAPE - 1.0)
	var h := pow(pow(absf(a), q) + pow(absf(c), q), 1.0 / q)
	if h < 1e-6:
		return Vector2.ZERO
	var k := q - 1.0
	return Vector2(side * signf(a) * pow(absf(a) / h, k), down * signf(c) * pow(absf(c) / h, k))


## How much the border at normal `n` is a back edge (0 … 1): it has no wall, so its edge has no
## outline and its foot only a shadow (elevation_sides.gdshader).
static func backness(n: Vector2) -> float:
	return smoothstep(0.3, 0.7, -n.y)


## The light of a face whose outward normal is `n`.
static func shade(n: Vector2) -> float:
	var light := SHADE_FRONT
	light += (SHADE_EAST - SHADE_FRONT) * smoothstep(0.2, 1.0, n.x)
	light += (SHADE_WEST - SHADE_FRONT) * smoothstep(0.2, 1.0, -n.x)
	return lerpf(light, SHADE_BACK, smoothstep(0.0, 0.8, -n.y))


# --- chains -------------------------------------------------------------------------------

## Edges joined end to start into chains of one level: lines first, then loops. At a point with
## several ways on, the sharpest left turn keeps to the same top (as ElevationRims).
func _chains(edges: Array[Dictionary]) -> Array:
	var outgoing := {}
	var incoming := {}
	for i in edges.size():
		for pair: Array in [[outgoing, edges[i]["from"]], [incoming, edges[i]["to"]]]:
			var key := _point_key(pair[1])
			var table: Dictionary = pair[0]
			if not table.has(key):
				table[key] = []
			(table[key] as Array).append(i)
	var used := PackedByteArray()
	used.resize(edges.size())
	var chains := []
	for pass_index in 2:
		for i in edges.size():
			if used[i]:
				continue
			if pass_index == 0 and _has_predecessor(edges, incoming, used, i):
				continue
			var chain: Array[Dictionary] = [edges[i]]
			used[i] = 1
			var current := i
			while true:
				var next := _next_edge(edges, outgoing, used, current)
				if next < 0:
					break
				chain.append(edges[next])
				used[next] = 1
				current = next
			chains.append(chain)
	return chains


func _has_predecessor(edges: Array[Dictionary], incoming: Dictionary, used: PackedByteArray, i: int) -> bool:
	for j: int in incoming.get(_point_key(edges[i]["from"]), []):
		if j != i and not used[j] and int(edges[j]["level"]) == int(edges[i]["level"]):
			return true
	return false


func _next_edge(edges: Array[Dictionary], outgoing: Dictionary, used: PackedByteArray, current: int) -> int:
	var best := -1
	var best_turn := INF
	var dir := _dir(edges[current])
	for j: int in outgoing.get(_point_key(edges[current]["to"]), []):
		if used[j] or int(edges[j]["level"]) != int(edges[current]["level"]):
			continue
		var next_dir := _dir(edges[j])
		var turn := atan2(dir.x * next_dir.y - dir.y * next_dir.x, dir.dot(next_dir))
		if turn < best_turn:
			best_turn = turn
			best = j
	return best


static func _point_key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x * 2.0), roundi(point.y * 2.0))


static func _dir(edge: Dictionary) -> Vector2:
	return ((edge["to"] as Vector2) - (edge["from"] as Vector2)).normalized()


static func _most(counts: Dictionary) -> String:
	var best := ""
	var best_count := -1
	for key: String in counts:
		if int(counts[key]) > best_count:
			best = key
			best_count = int(counts[key])
	return best


# --- the drop of an edge ------------------------------------------------------------------

## [drop (levels), visible depth (levels: a wall something stands in front of ends early), has a
## foot] of a top's boundary edge.
func _edge_drop(edge: Dictionary) -> Array:
	var level := int(edge["level"])
	var across := int(edge["x"])
	var band_index := grid.tri_band[across]
	if band_index < 0:
		return [float(level - grid.tri_level[across]), float(level - grid.tri_level[across]), true]
	var band: Dictionary = grid.bands[band_index]
	if int(edge["mode"]) == ElevationRims.LIP:
		var drop := float(band["drop"])
		var shown := float(int(band["end"]) - int(band["start"]) + 1) / 4.0
		return [drop, minf(drop, shown), bool(band["natural"])]
	return [float(level - int(band["bottom"])), float(level - int(band["bottom"])), true]


# --- one chain ----------------------------------------------------------------------------

## Straight runs of a chain (world units): {from, to, dir, normal, drop, shown, foot, rim, water (the
## ground below is water)}, edges running the same way with the same drop merged.
func _runs(chain: Array[Dictionary]) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for edge in chain:
		var from: Vector2 = (edge["from"] as Vector2) * cell
		var to: Vector2 = (edge["to"] as Vector2) * cell
		var dir := (to - from).normalized()
		var drop := _edge_drop(edge)
		var rim := 1.0 if int(edge["mode"]) == ElevationRims.RIM else 0.0
		var water := _ground_below(edge) == WATER
		if not runs.is_empty():
			var last: Dictionary = runs[runs.size() - 1]
			if (last["dir"] as Vector2).dot(dir) > 0.9999 and float(last["drop"]) == float(drop[0]) \
					and float(last["shown"]) == float(drop[1]) and bool(last["foot"]) == bool(drop[2]) \
					and float(last["rim"]) == rim and bool(last["water"]) == water:
				last["to"] = to
				continue
		runs.append({
			"from": from, "to": to, "dir": dir, "normal": Vector2(-dir.y, dir.x),
			"drop": float(drop[0]), "shown": float(drop[1]), "foot": bool(drop[2]), "rim": rim, "water": water,
		})
	return runs


## The ground at the foot of `edge`'s wall: the tri across it, or (a wall) the tri below the wall's
## foot.
func _ground_below(edge: Dictionary) -> String:
	var across := int(edge["x"])
	var band_index := grid.tri_band[across]
	if band_index < 0:
		return grid.tri_ground[across]
	var band: Dictionary = grid.bands[band_index]
	var below := int(band["end"]) + 1
	if below >= grid.rows * 4:
		return grid.tri_ground[across]
	return grid.tri_ground[grid.column_tri(int(band["column"]), below)]


## True when an outer corner joins a back edge (its normal points north) and a side (east or west):
## its side wall starts with a slanted end there (`_caps`).
static func _is_back_corner(n_a: Vector2, n_b: Vector2, convex: bool) -> bool:
	if not convex:
		return false
	return (n_a.y < -0.5 and n_b.y > -0.5 and absf(n_b.x) > 0.5) or (n_b.y < -0.5 and n_a.y > -0.5 and absf(n_a.x) > 0.5)


## True when an inner corner joins a side (east or west) and a front or back edge.
static func _is_side_inner_corner(n_a: Vector2, n_b: Vector2, convex: bool) -> bool:
	if convex:
		return false
	return (absf(n_a.x) > 0.7 and absf(n_b.y) > 0.7) or (absf(n_b.x) > 0.7 and absf(n_a.y) > 0.7)


## The chain's border (Border), its corners rounded, resampled.
func _border(runs: Array[Dictionary], loop: bool) -> Border:
	var count := runs.size()
	# Per run: how far its start and end are cut back for the corners there.
	var cut_start := PackedFloat32Array()
	var cut_end := PackedFloat32Array()
	cut_start.resize(count)
	cut_end.resize(count)
	var corner_of := {}
	var joins := count if loop else count - 1
	for i in joins:
		var j := (i + 1) % count
		var e_a: Vector2 = runs[i]["dir"]
		var e_b: Vector2 = runs[j]["dir"]
		var cross := e_a.x * e_b.y - e_a.y * e_b.x
		var turn := atan2(cross, e_a.dot(e_b))
		if absf(turn) < 0.01:
			continue
		var convex := cross < 0.0
		var back := _is_back_corner(runs[i]["normal"], runs[j]["normal"], convex)
		var len_a := (runs[i]["from"] as Vector2).distance_to(runs[i]["to"])
		var len_b := (runs[j]["from"] as Vector2).distance_to(runs[j]["to"])
		var fold := _is_side_inner_corner(runs[i]["normal"], runs[j]["normal"], convex)
		var radius := RADIUS_BACK if back else (RADIUS_FOLD if fold else (RADIUS_OUTER if convex else RADIUS_INNER))
		# Over water a round corner would need the water surface itself between it and the model's
		# square one: such corners stay nearly square.
		if convex and (bool(runs[i]["water"]) or bool(runs[j]["water"])):
			radius = RADIUS_WATER
		var tangent := radius * tan(absf(turn) * 0.5)
		tangent = minf(tangent, 0.5 * minf(len_a, len_b))
		radius = tangent / tan(absf(turn) * 0.5)
		cut_end[i] = tangent
		cut_start[j] = tangent
		corner_of[i] = {"vertex": runs[i]["to"], "e_a": e_a, "e_b": e_b, "n_a": runs[i]["normal"],
				"n_b": runs[j]["normal"], "convex": convex, "back": back, "radius": radius, "tangent": tangent,
				"turn": turn, "fold": fold,
				"drop_a": float(runs[i]["shown"]), "drop_b": float(runs[j]["shown"])}
	var border := Border.new()
	for i in count:
		var run: Dictionary = runs[i]
		var from: Vector2 = run["from"]
		var to: Vector2 = run["to"]
		var dir: Vector2 = run["dir"]
		var start := from + dir * cut_start[i]
		var finish := to - dir * cut_end[i]
		var length := start.distance_to(finish)
		var steps := maxi(1, ceili(length / STEP))
		# A run's last point is the next corner's (or run's) first: only a line's last run keeps it.
		var last_index := steps if not loop and i == count - 1 else steps - 1
		for k in range(0, last_index + 1):
			_add_point(border, start.lerp(finish, float(k) / steps), run["normal"], run, run, 0.0, -1)
		if corner_of.has(i):
			_add_corner(border, corner_of[i], run, runs[(i + 1) % count])
	return border


func _add_point(border: Border, point: Vector2, normal: Vector2, a: Dictionary, b: Dictionary, t: float, corner: int) -> void:
	border.points.append(point)
	border.normals.append(normal)
	border.drop.append(lerpf(float(a["drop"]), float(b["drop"]), t))
	border.shown.append(lerpf(float(a["shown"]), float(b["shown"]), t))
	border.foot.append(1.0 if bool(a["foot"]) and bool(b["foot"]) else 0.0)
	border.rim.append(lerpf(float(a["rim"]), float(b["rim"]), t))
	border.water.append(1.0 if bool(a["water"]) or bool(b["water"]) else 0.0)
	border.corner.append(corner)


## A rounded corner's arc, from the end of run `a` to the start of run `b`.
func _add_corner(border: Border, corner: Dictionary, a: Dictionary, b: Dictionary) -> void:
	var index := border.corners.size()
	var vertex: Vector2 = corner["vertex"]
	var e_a: Vector2 = corner["e_a"]
	var e_b: Vector2 = corner["e_b"]
	var n_a: Vector2 = corner["n_a"]
	var radius := float(corner["radius"])
	var tangent := float(corner["tangent"])
	var convex := bool(corner["convex"])
	var start := vertex - e_a * tangent
	var centre := start - n_a * radius if convex else start + n_a * radius
	var angle_a := (start - centre).angle()
	var finish := vertex + e_b * tangent
	var delta := wrapf((finish - centre).angle() - angle_a, -PI, PI)
	var steps := maxi(1, ceili(absf(delta) / ARC_FINE))
	corner["first"] = border.points.size()
	var kept_top := Vector2.INF
	var kept_foot := Vector2.INF
	for k in steps:
		var t := float(k) / steps
		var point := centre + Vector2.from_angle(angle_a + delta * t) * radius
		var normal := (point - centre).normalized() if convex else (centre - point).normalized()
		if radius < 0.01:
			normal = (n_a as Vector2).slerp(corner["n_b"], t)
		var foot := point + reach(normal, lerpf(float(a["shown"]), float(b["shown"]), t))
		if k > 0 and point.distance_to(kept_top) < STEP and foot.distance_to(kept_foot) < STEP:
			continue
		kept_top = point
		kept_foot = foot
		_add_point(border, point, normal, a, b, t, index)
	corner["last"] = border.points.size() - 1
	border.corners.append(corner)


## Per point of the border, the share of its fibre that is drawn: 1, but at a back corner the side's
## wall starts where the round of the top begins (the back edge's end) and widens CAP_SLOPE per unit
## along the border, round the corner and on down the side, to its full width: a slanted end that
## hugs the round (the owner, 2026-10-13: "now that the top border is round the wall should get a
## little higher").
func _caps(border: Border, loop: bool) -> PackedFloat32Array:
	var points := border.points
	var count := points.size()
	var caps := PackedFloat32Array()
	caps.resize(count)
	caps.fill(1.0)
	for corner: Dictionary in border.corners:
		if not bool(corner["back"]):
			continue
		var first := int(corner["first"])
		var last := int(corner["last"])
		# The side runs on after the corner when the back edge comes first, else before it: start at
		# the arc's back-edge end and go round it.
		var forward := (corner["n_a"] as Vector2).y < -0.5
		var k := first if forward else last
		var previous := points[k]
		var widest := SIDE * pow(maxf(float(corner["drop_a"]), float(corner["drop_b"])), THIN_GROWTH)
		var distance := 0.0
		var steps := 0
		while steps < count and CAP_SLOPE * distance < widest:
			if k < 0 or k >= count:
				if not loop:
					break
				k = posmod(k, count)
			distance += previous.distance_to(points[k])
			previous = points[k]
			var full := reach(border.normals[k], border.shown[k]).length()
			if full > 0.0:
				caps[k] = minf(caps[k], minf(1.0, CAP_SLOPE * distance / full))
			k += 1 if forward else -1
			steps += 1
	return caps


func _add_chain(pieces: Array, chain: Array[Dictionary], wall_width: float) -> void:
	var loop := chain.size() > 2 and _point_key(chain[0]["from"]) == _point_key(chain[chain.size() - 1]["to"])
	var runs := _runs(chain)
	if runs.is_empty():
		return
	# A loop starts wherever its first edge lies, often partway along a straight run: join the run's
	# two pieces, or the short one would leave no room to round the corner after it.
	if loop and runs.size() > 2:
		var last: Dictionary = runs[runs.size() - 1]
		var first: Dictionary = runs[0]
		if (last["dir"] as Vector2).dot(first["dir"]) > 0.9999 and float(last["drop"]) == float(first["drop"]) 				and float(last["shown"]) == float(first["shown"]) and bool(last["foot"]) == bool(first["foot"]) 				and float(last["rim"]) == float(first["rim"]):
			first["from"] = last["from"]
			runs.remove_at(runs.size() - 1)
	var level := float(chain[0]["level"])
	var border := _border(runs, loop)
	var points := border.points
	var normals := border.normals
	var count := points.size()
	if count < 2:
		return
	var caps := _caps(border, loop)
	# How deep each fibre reaches (levels), cut next to back corners.
	var depths := PackedFloat32Array()
	for i in count:
		depths.append(border.shown[i] * caps[i])
	# Each point's fibre (from the top edge to the foot) and the light of its face; inner corners of a
	# front and a side wall fold round (`_fold_corners`).
	var fibres := PackedVector2Array()
	var lights := PackedFloat32Array()
	var folded := PackedFloat32Array()
	folded.resize(count)
	for i in count:
		fibres.append(reach(normals[i], border.shown[i]) * caps[i])
		lights.append(shade(normals[i]))
	_fold_corners(border, fibres, lights, folded, loop)
	# The top edge (wobbled), the foot (its own wobble), the arc length along the curve U_DEPTH down
	# the fibres.
	var tops := PackedVector2Array()
	var foots := PackedVector2Array()
	var wall_along := PackedFloat32Array()
	var wall_length := 0.0
	var previous := Vector2.ZERO
	var sides := _side_ramps(border, fibres, loop)
	var rates := PackedFloat32Array()
	for i in count:
		rates.append(lerpf(1.0, SIDE_U_RATE, sides[i]))
	for i in count:
		var p := points[i]
		var n := normals[i]
		var fibre := fibres[i]
		var middle := p + fibre * U_DEPTH
		if i > 0:
			wall_length += previous.distance_to(middle) * (rates[i - 1] + rates[i]) * 0.5
		wall_along.append(wall_length)
		previous = middle
		# Outward only: an edge pulled in would leave a sliver of the top's square cells past it.
		var top := p + n * TOP_WOBBLE * (0.5 + 0.5 * _wobble(p))
		tops.append(top)
		# The foot wobbles on its own, along its fibre, as much as there is wall to wobble (none on a
		# back edge); in a fold it lies on the fold's foot line (the wobbles there would push it back
		# and forth along that line).
		var foot_wobble := FOOT_WOBBLE * minf(1.0, fibre.length() / FOOT_WOBBLE)
		var way := fibre.normalized() if fibre.length() > 0.01 else n
		var shift := (top - p) + way * foot_wobble * _wobble(p + Vector2(311.0, 97.0))
		foots.append(p + fibre + shift * (1.0 - folded[i]))
	if loop:
		wall_length += previous.distance_to(points[0] + fibres[0] * U_DEPTH) * (rates[count - 1] + rates[0]) * 0.5
	var segments := count if loop else count - 1
	# u: 2 px of art per unit along the border, a loop stretched to close on whole periods.
	var wall_scale := _period_scale(wall_length, wall_width, loop)
	var course := float(posmod(int(level), 2)) * 128.0
	for i in segments:
		var j := (i + 1) % count
		if (depths[i] <= 0.0 and depths[j] <= 0.0) or (tops[i].distance_to(foots[i]) < 0.5 and tops[j].distance_to(foots[j]) < 0.5):
			continue
		var u_i := wall_along[i] * 2.0 * wall_scale
		var u_j := (wall_along[j] if j > 0 else wall_length) * 2.0 * wall_scale
		var key := (points[i].y + points[j].y) * 0.5
		_add_wall(pieces, key, tops[i], tops[j], foots[i], foots[j], u_i, u_j, depths[i], depths[j], course, level,
				lights[i], lights[j], sides[i], sides[j])
	_add_corner_stones(pieces, border, tops, foots, depths, lights, loop, level)
	_add_shape(border, foots, depths, loop, level)
	_add_corner_fills(pieces, border, level)
	_add_top_edge(pieces, border, tops, loop, level)
	_add_foot(pieces, border, foots, depths, loop, level)


## Per point, how much its wall is drawn as a side's (one course across, short stones: `side_of`),
## reaching it only SIDE_RAMP units along the border past the last fibre hanging more down than
## sideways: round a front corner the courses keep wrapping as the front's and merge into the
## side's single column over that stretch, instead of all at once inside the corner.
func _side_ramps(border: Border, fibres: PackedVector2Array, loop: bool) -> PackedFloat32Array:
	var points := border.points
	var count := points.size()
	var out := PackedFloat32Array()
	out.resize(count)
	# Distance along the border to the nearest fibre that hangs more down than sideways, both ways.
	var distance := PackedFloat32Array()
	distance.resize(count)
	distance.fill(INF)
	for way: int in [1, -1]:
		var running := INF
		for pass_index in (2 if loop else 1):
			for step in count:
				var i := step if way > 0 else count - 1 - step
				var previous := i - way
				if previous >= 0 and previous < count:
					running += points[previous].distance_to(points[i])
				elif loop:
					running += points[posmod(previous, count)].distance_to(points[i])
				else:
					running = INF
				if side_of(fibres[i]) < 0.5:
					running = 0.0
				distance[i] = minf(distance[i], running)
	for i in count:
		out[i] = side_of(fibres[i]) * smoothstep(0.0, SIDE_RAMP, distance[i])
	return out


## How much a fibre is a side wall's (0 a front … 1 a side): by the way it hangs.
static func side_of(fibre: Vector2) -> float:
	var way := fibre.normalized() if fibre.length() > 0.01 else Vector2.DOWN
	return smoothstep(0.55, 0.97, absf(way.x))


## A run of wall between two fibres (top edge t → foot f), cut into pieces down the fibre where the
## fibres fan out (at a corner), so the art bends smoothly there; one piece where they run alike.
## Down a front fibre the art shows a course per level, across a side one a single course (`side0`,
## `side1`: how much each is a side's).
func _add_wall(pieces: Array, key: float, t0: Vector2, t1: Vector2, f0: Vector2, f1: Vector2, u0: float, u1: float,
		d0: float, d1: float, course: float, level: float, light0: float, light1: float, side0: float = 0.0,
		side1: float = 0.0) -> void:
	var alike := (f0 - t0).normalized().dot((f1 - t1).normalized()) > 0.999 and absf((f0 - t0).length() - (f1 - t1).length()) < 2.0
	var cuts := 1 if alike else maxi(1, ceili(maxf(d0, d1) * 2.0))
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for c in cuts:
		var s0 := float(c) / cuts
		var s1 := float(c + 1) / cuts
		var corners := [
			[t0.lerp(f0, s0), u0, s0 * d0, light0, lerpf(s0 * d0, s0, side0), side0],
			[t1.lerp(f1, s0), u1, s0 * d1, light1, lerpf(s0 * d1, s0, side1), side1],
			[t1.lerp(f1, s1), u1, s1 * d1, light1, lerpf(s1 * d1, s1, side1), side1],
			[t0.lerp(f0, s1), u0, s1 * d0, light0, lerpf(s1 * d0, s1, side0), side0],
		]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var corner: Array = corners[index]
			var depth := float(corner[2])
			verts.append(corner[0])
			uvs.append(Vector2(float(corner[1]), course + float(corner[4]) * 128.0))
			colors.append(Color(KIND_WALL + KIND_SIDE * float(corner[5]), float(corner[3]), depth * 128.0 / 512.0,
					_level_channel(level - depth)))
	pieces.append([key, verts, uvs, colors])


## Over every outer corner of a front wall and a side wall (as the concept paints it): one big
## rounded stone per course, CORNER_LENGTH units long along that course's middle line and centred
## on the corner, so the courses turn the corner on a stone of their own, of the same proportions at
## every height, instead of the wall's art fanned round it. UV = (u in the corner sheet: the stone's
## cell + how far along it, 0 … 1 down its course); drawn just after the wall there.
func _add_corner_stones(pieces: Array, border: Border, tops: PackedVector2Array, foots: PackedVector2Array,
		depths: PackedFloat32Array, lights: PackedFloat32Array, loop: bool, level: float) -> void:
	var count := tops.size()
	for corner: Dictionary in border.corners:
		if not bool(corner["convex"]) or bool(corner["back"]) or not _is_front_side(corner["n_a"], corner["n_b"]):
			continue
		var first := int(corner["first"])
		var last := int(corner["last"])
		var middle := (first + last) / 2
		var vertex: Vector2 = corner["vertex"]
		var front_drop := float(corner["drop_a"] if (corner["n_a"] as Vector2).y > 0.9 else corner["drop_b"])
		var courses := maxi(1, ceili(front_drop - 0.01))
		# The points round the corner, far enough either way for the stone.
		var span := int(ceil(CORNER_LENGTH / STEP)) * 4 + (last - first)
		var indices: Array[int] = []
		for step in range(-span, span + 1):
			var i := middle + step
			if i < 0 or i >= count:
				if not loop:
					continue
				i = posmod(i, count)
			if indices.has(i):
				continue
			indices.append(i)
		if indices.size() < 3:
			continue
		for course_index in courses:
			# The course's middle line, its arc length, and where the stone starts and ends on it.
			var lines := PackedVector2Array()
			var along := PackedFloat32Array()
			var at_middle := 0.0
			for n in indices.size():
				var i := indices[n]
				var d := maxf(depths[i], 1e-3)
				lines.append(tops[i].lerp(foots[i], clampf((course_index + 0.5) / d, 0.0, 1.0)))
				along.append(0.0 if n == 0 else along[n - 1] + lines[n - 1].distance_to(lines[n]))
				if i == middle:
					at_middle = along[n]
			var from := at_middle - CORNER_LENGTH * 0.5
			var to := at_middle + CORNER_LENGTH * 0.5
			if from < 0.0 or to > along[along.size() - 1]:
				continue
			var cell := posmod(int(floor(vertex.x / 64.0)) * 7 + int(floor(vertex.y / 64.0)) * 3 + course_index, CORNER_STONES)
			# Resampled along the stone: [top of the course band, foot of it, light, depth there].
			var samples := []
			var steps := 12
			for k in steps + 1:
				var t := lerpf(from, to, float(k) / steps)
				var n := 0
				while n < along.size() - 2 and along[n + 1] < t:
					n += 1
				var f := clampf((t - along[n]) / maxf(along[n + 1] - along[n], 1e-6), 0.0, 1.0)
				var i0 := indices[n]
				var i1 := indices[n + 1]
				var top := tops[i0].lerp(tops[i1], f)
				var foot := foots[i0].lerp(foots[i1], f)
				var d := lerpf(depths[i0], depths[i1], f)
				var s0 := clampf(course_index / maxf(d, 1e-3), 0.0, 1.0)
				var s1 := clampf((course_index + 1) / maxf(d, 1e-3), 0.0, 1.0)
				samples.append([top.lerp(foot, s0), top.lerp(foot, s1), lerpf(lights[i0], lights[i1], f), s0 * d, s1 * d, float(k) / steps])
			var verts := PackedVector2Array()
			var uvs := PackedVector2Array()
			var colors := PackedColorArray()
			for k in steps:
				var a: Array = samples[k]
				var b: Array = samples[k + 1]
				var quad := [[a[0], a[5], 0.0, a[2], a[3]], [b[0], b[5], 0.0, b[2], b[3]],
						[b[1], b[5], 1.0, b[2], b[4]], [a[1], a[5], 1.0, a[2], a[4]]]
				for index: int in [0, 1, 2, 0, 2, 3]:
					var c: Array = quad[index]
					var depth := float(c[4])
					verts.append(c[0])
					uvs.append(Vector2((float(cell) + float(c[1])) / CORNER_STONES, float(c[2])))
					colors.append(Color(KIND_CORNER, float(c[3]), depth * 128.0 / 512.0, _level_channel(level - depth)))
			pieces.append([vertex.y + 1.0, verts, uvs, colors])


## True when two normals are a front's (south) and a side's (east or west).
static func _is_front_side(n_a: Vector2, n_b: Vector2) -> bool:
	return (n_a.y > 0.9 and absf(n_b.x) > 0.9) or (n_b.y > 0.9 and absf(n_a.x) > 0.9)


## Folds every inner corner of a front wall and a side wall into one wall (FOLD_RUN): over the
## stretch of border round the corner (the second wall's reach plus FOLD_RUN before it, the first
## wall's reach plus FOLD_RUN after it), each fibre runs from its top point to the point as far along
## the foot's path (FOLD_RUN along the first wall's foot, round a corner of FOLD_FOOT_RADIUS where it
## meets the second wall's, FOLD_RUN along that), so the fibres turn from straight down to straight
## out without crossing and every course line folds round the corner. The light turns with them;
## `folded` says per point how much of a fold holds there (its feet keep to the fold's foot line).
## Where the runs are too short for it the corner stays as it is.
func _fold_corners(border: Border, fibres: PackedVector2Array, lights: PackedFloat32Array, folded: PackedFloat32Array,
		loop: bool) -> void:
	var points := border.points
	var count := points.size()
	# Arc length along the border.
	var along := PackedFloat32Array()
	var length := 0.0
	for i in count:
		if i > 0:
			length += points[i - 1].distance_to(points[i])
		along.append(length)
	if loop:
		length += points[count - 1].distance_to(points[0])
	for corner: Dictionary in border.corners:
		if not bool(corner.get("fold", false)):
			continue
		var n_a: Vector2 = corner["n_a"]
		var n_b: Vector2 = corner["n_b"]
		var front_first := n_a.y > 0.7
		var front_normal := n_a if front_first else n_b
		var side_normal := n_b if front_first else n_a
		var front := reach(front_normal, float(corner["drop_a"] if front_first else corner["drop_b"]))
		var side := reach(side_normal, float(corner["drop_b"] if front_first else corner["drop_a"]))
		if front.length() < 1.0 or side.length() < 1.0:
			continue
		# The fibre at each end of the stretch: the first run's, then the second's.
		var fibre_a := front if front_first else side
		var fibre_b := side if front_first else front
		var middle := (int(corner["first"]) + int(corner["last"])) / 2
		var at := along[middle]
		# How far the stretch may reach each way: up to half of each run's free length.
		var room_a := _room(border, middle, -1, loop, along, length)
		var room_b := _room(border, middle, 1, loop, along, length)
		# Each side's run of foot: FOLD_RUN, or what room the run leaves.
		var run_a := minf(FOLD_RUN, room_a - fibre_b.length())
		var run_b := minf(FOLD_RUN, room_b - fibre_a.length())
		if run_a < 8.0 or run_b < 8.0:
			continue
		var reach_a := fibre_b.length() + run_a
		var reach_b := fibre_a.length() + run_b
		var vertex: Vector2 = corner["vertex"]
		var e_a: Vector2 = corner["e_a"]
		var e_b: Vector2 = corner["e_b"]
		# The foot's path: along the first wall's foot to where the two feet meet, round, then along the
		# second's.
		var start := vertex - e_a * reach_a + fibre_a
		var meet := vertex + fibre_a + fibre_b
		var finish := vertex + e_b * reach_b + fibre_b
		var path := _rounded_path(start, meet, finish, FOLD_FOOT_RADIUS)
		var path_length := _path_length(path)
		var light_a := shade(n_a)
		var light_b := shade(n_b)
		for step in range(-count, count):
			var i := middle + step
			if i < 0 or i >= count:
				if not loop:
					continue
				i = posmod(i, count)
			var d := along[i] - at
			if loop:
				d = wrapf(d, -length * 0.5, length * 0.5)
			if d < -reach_a or d > reach_b:
				continue
			var t := (d + reach_a) / (reach_a + reach_b)
			fibres[i] = _path_point(path, t * path_length) - points[i]
			# The light turns from one face's to the other's across the fold.
			lights[i] = lerpf(light_a, light_b, smoothstep(0.3, 0.7, t))
			# How much of the fold holds here: the feet's own wobble fades out into it.
			folded[i] = maxf(folded[i], smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.75, 1.0, t)))


## How far the border runs from point `from` going `way` (1 on, -1 back) before the next corner's
## arc, units; half of it when that corner folds too (the two share the run).
func _room(border: Border, from: int, way: int, loop: bool, along: PackedFloat32Array, length: float) -> float:
	var count := border.points.size()
	var own := border.corner[from]
	var i := from
	for step in count:
		i += way
		if i < 0 or i >= count:
			if not loop:
				return absf(along[clampi(i, 0, count - 1)] - along[from])
			i = posmod(i, count)
		var corner := border.corner[i]
		if corner >= 0 and corner != own:
			var d := absf(along[i] - along[from])
			if loop:
				d = minf(d, length - d)
			return d * 0.5 if bool(border.corners[corner].get("fold", false)) else d
	return length * 0.5


## The polyline start → meet → finish with the corner at `meet` rounded by `radius` (less along a
## short leg: the curve then leans to the longer one), as points.
static func _rounded_path(start: Vector2, meet: Vector2, finish: Vector2, radius: float) -> PackedVector2Array:
	var path := PackedVector2Array([start])
	var in_dir := (meet - start).normalized()
	var out_dir := (finish - meet).normalized()
	var from := meet - in_dir * minf(radius, 0.9 * start.distance_to(meet))
	var to := meet + out_dir * minf(radius, 0.9 * meet.distance_to(finish))
	for k in 9:
		var t := float(k) / 8.0
		# A quadratic curve through the corner: tangent to both legs.
		path.append(from.lerp(meet, t).lerp(meet.lerp(to, t), t))
	path.append(finish)
	return path


static func _path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## The point `distance` along `path`.
static func _path_point(path: PackedVector2Array, distance: float) -> Vector2:
	var left := distance
	for i in range(1, path.size()):
		var piece := path[i - 1].distance_to(path[i])
		if left <= piece or i == path.size() - 1:
			return path[i - 1].lerp(path[i], clampf(left / maxf(piece, 1e-6), 0.0, 1.0))
		left -= piece
	return path[path.size() - 1]


## At every corner, the ground between its arc and the model's square corner (the vertex): past an
## outer corner the lower ground (else the top's square cell would poke out past the round edge),
## inside an inner one the top's. Drawn first in the level's mesh, under its walls and edges.
func _add_corner_fills(pieces: Array, border: Border, level: float) -> void:
	for corner: Dictionary in border.corners:
		var first := int(corner["first"])
		var last := int(corner["last"])
		if last <= first:
			continue
		var vertex: Vector2 = corner["vertex"]
		var convex := bool(corner["convex"])
		var kind := KIND_FILL_LOW if convex else KIND_FILL_TOP
		var fill_level := level - (float(corner["drop_a"]) if convex else 0.0)
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var colour := Color(kind, 0.0, 0.0, _level_channel(fill_level))
		# The arc's ends meet the straight runs, which carry on to the vertex: fan from it.
		for i in range(first, last):
			for point: Vector2 in [vertex, border.points[i], border.points[i + 1]]:
				verts.append(point)
				uvs.append(Vector2.ZERO)
				colors.append(colour)
		pieces.append([-1e9, verts, uvs, colors])


## A chain's shape for collision (`shapes`): its drawn walls as polygons (each run of points with a
## wall, from the smooth border to the foot; the foot simplified to SHAPE_TOLERANCE), the zones
## between each round outer corner and the model's square corner (the vertex and the arc), the level
## below each point, and every edge of the border and the walls, for Elevation to trace. Each test
## and its edges come from the same points, so a piece's two sides are judged by the line drawn.
func _add_shape(border: Border, foots: PackedVector2Array, depths: PackedFloat32Array, loop: bool, level: float) -> void:
	var points := border.points
	var count := points.size()
	var walled := PackedByteArray()
	walled.resize(count)
	for k in count:
		walled[k] = 1 if depths[k] > 0.0 and points[k].distance_to(foots[k]) > 0.75 else 0
	# Runs of walled points; a loop starts after an unwalled point so no run wraps.
	var start := 0
	if loop:
		start = -1
		for k in count:
			if walled[k] == 0:
				start = k
				break
	# The border simplified once (SHAPE_TOLERANCE), keeping every corner's ends and every point where a
	# wall starts or ends: walls, zones and edges all take its points, so each test agrees with the
	# line its pieces are cut along.
	var forced := {}
	for corner: Dictionary in border.corners:
		forced[int(corner["first"])] = true
		forced[int(corner["last"])] = true
		forced[(int(corner["last"]) + 1) % count] = true
	for k in count:
		var next := (k + 1) % count
		if walled[k] != walled[next]:
			forced[k] = true
			forced[next] = true
	var keep := _kept(points, loop, forced, SHAPE_TOLERANCE)
	var walls: Array[PackedVector2Array] = []
	if loop and start < 0:
		# Walled all round (no back edge): two halves.
		walls.append(_wall_polygon(points, foots, range(0, count / 2 + 1), keep))
		walls.append(_wall_polygon(points, foots, range(count / 2, count) + [0], keep))
	else:
		var run: Array = []
		var steps := count + (1 if loop else 0)
		for i in steps:
			var k := (start + i) % count
			if walled[k] == 1:
				run.append(k)
			if walled[k] == 0 or i == steps - 1:
				if run.size() >= 2:
					walls.append(_wall_polygon(points, foots, run, keep))
				run = []
	var zones: Array[PackedVector2Array] = []
	for corner: Dictionary in border.corners:
		if not bool(corner["convex"]):
			continue
		var zone := PackedVector2Array([corner["vertex"]])
		for k in range(int(corner["first"]), int(corner["last"]) + 1):
			if keep[k] == 1:
				zone.append(points[k])
		# The arc's last point is the next run's first.
		var after := int(corner["last"]) + 1
		if after < count or loop:
			zone.append(points[after % count])
		if zone.size() >= 3:
			zones.append(zone)
	var edges: Array = []
	var line := PackedVector2Array()
	for k in count:
		if keep[k] == 1:
			line.append(points[k])
	if loop and line.size() > 0:
		line.append(line[0])
	for i in line.size() - 1:
		edges.append([line[i], line[i + 1]])
	for wall in walls:
		for i in wall.size():
			edges.append([wall[i], wall[(i + 1) % wall.size()]])
	var bounds := Rect2(points[0], Vector2.ZERO)
	for k in count:
		bounds = bounds.expand(points[k]).expand(foots[k])
	for corner: Dictionary in border.corners:
		bounds = bounds.expand(corner["vertex"])
	# The level below each point's wall, and the commonest.
	var belows := PackedInt32Array()
	var counts := {}
	for k in count:
		var below := roundi(level - border.drop[k])
		belows.append(below)
		counts[below] = int(counts.get(below, 0)) + 1
	var common := 0
	var most := -1
	for below: int in counts:
		if int(counts[below]) > most:
			most = int(counts[below])
			common = below
	var wall_bounds: Array[Rect2] = []
	for wall in walls:
		var box := Rect2(wall[0], Vector2.ZERO)
		for point in wall:
			box = box.expand(point)
		wall_bounds.append(box.grow(0.5))
	var lowest := common
	for below: int in counts:
		lowest = mini(lowest, below)
	shapes.append({
		"level": int(level), "points": points, "belows": belows, "below": common, "lowest": lowest,
		"mixed": counts.size() > 1, "walls": walls, "wall_bounds": wall_bounds, "zones": zones,
		"edges": edges, "bounds": bounds.grow(2.0),
	})


## The polygon of the wall over `run` (point indices): along the smooth border (its points `keep`
## marks, and the run's ends), back along the foot (simplified to SHAPE_TOLERANCE).
static func _wall_polygon(points: PackedVector2Array, foots: PackedVector2Array, run: Array, keep: PackedByteArray) -> PackedVector2Array:
	var top := PackedVector2Array()
	var foot := PackedVector2Array()
	for n in run.size():
		var k: int = run[n]
		if keep[k] == 1 or n == 0 or n == run.size() - 1:
			top.append(points[k])
		foot.append(foots[k])
	foot.reverse()
	return top + _simplify(foot, SHAPE_TOLERANCE)


## Which points of `points` (a loop or a line) a simplified border keeps (1): every `forced` index,
## the ends of a line, and between them what Ramer-Douglas-Peucker keeps within `tolerance`.
static func _kept(points: PackedVector2Array, loop: bool, forced: Dictionary, tolerance: float) -> PackedByteArray:
	var count := points.size()
	var keep := PackedByteArray()
	keep.resize(count)
	var anchors: Array[int] = []
	for k: int in forced:
		anchors.append(k)
	if not loop:
		anchors.append_array([0, count - 1])
	elif anchors.size() < 2:
		anchors.append_array([0, count / 2])
	anchors.sort()
	var unique: Array[int] = []
	for k in anchors:
		if unique.is_empty() or unique[unique.size() - 1] != k:
			unique.append(k)
	for k in unique:
		keep[k] = 1
	var spans := unique.size() if loop else unique.size() - 1
	for n in spans:
		var a := unique[n]
		var b := unique[(n + 1) % unique.size()]
		if b <= a:
			b += count
		var stack: Array[Vector2i] = [Vector2i(a, b)]
		while not stack.is_empty():
			var span: Vector2i = stack.pop_back()
			var from := points[span.x % count]
			var to := points[span.y % count]
			var worst := -1
			var worst_distance := tolerance
			for i in range(span.x + 1, span.y):
				var d := Geometry2D.get_closest_point_to_segment(points[i % count], from, to).distance_to(points[i % count])
				if d > worst_distance:
					worst_distance = d
					worst = i
			if worst >= 0:
				keep[worst % count] = 1
				stack.append(Vector2i(span.x, worst))
				stack.append(Vector2i(worst, span.y))
	return keep


## `line` with the points that lie within `tolerance` of the line through their neighbours left out
## (Ramer-Douglas-Peucker).
static func _simplify(line: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if line.size() <= 2:
		return line
	var keep := PackedByteArray()
	keep.resize(line.size())
	keep[0] = 1
	keep[line.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, line.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var worst := -1
		var worst_distance := tolerance
		for i in range(span.x + 1, span.y):
			var d := Geometry2D.get_closest_point_to_segment(line[i], line[span.x], line[span.y]).distance_to(line[i])
			if d > worst_distance:
				worst_distance = d
				worst = i
		if worst >= 0:
			keep[worst] = 1
			stack.append(Vector2i(span.x, worst))
			stack.append(Vector2i(worst, span.y))
	var out := PackedVector2Array()
	for i in line.size():
		if keep[i] == 1:
			out.append(line[i])
	return out


## The top edge along the border: from EDGE_IN over the top (from the smooth border; at an outer
## corner tighter than that the inner side meets in a mitre) to EDGE_OUT past the (wobbled) edge.
## UV = (world units along the border, world units past the edge); colour g = the rim factor.
func _add_top_edge(pieces: Array, border: Border, tops: PackedVector2Array, loop: bool, level: float) -> void:
	var points := border.points
	var normals := border.normals
	var rims := border.rim
	var count := points.size()
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var along := PackedFloat32Array()
	var length := 0.0
	for i in count:
		inner.append(points[i] - normals[i] * EDGE_IN)
		outer.append(tops[i] + normals[i] * EDGE_OUT)
		if i > 0:
			length += points[i - 1].distance_to(points[i])
		along.append(length)
	if loop:
		length += points[count - 1].distance_to(points[0])
	for corner: Dictionary in border.corners:
		_mitre(inner, corner, -EDGE_IN, loop)
		_mitre(outer, corner, EDGE_OUT, loop)
	var segments := count if loop else count - 1
	for i in segments:
		var j := (i + 1) % count
		var u_i := along[i]
		var u_j := along[j] if j > 0 else length
		# Where the wobble moved the edge, the band over the top starts that much further in.
		var in_i := -EDGE_IN - (tops[i] - points[i]).dot(normals[i])
		var in_j := -EDGE_IN - (tops[j] - points[j]).dot(normals[j])
		var key := (points[i].y + points[j].y) * 0.5 + EDGE_LEAD
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var back_i := backness(normals[i])
		var back_j := backness(normals[j])
		var ring := [
			[inner[i], u_i, in_i, rims[i], back_i], [inner[j], u_j, in_j, rims[j], back_j],
			[tops[j], u_j, 0.0, rims[j], back_j], [tops[i], u_i, 0.0, rims[i], back_i],
			[outer[j], u_j, EDGE_OUT, rims[j], back_j], [outer[i], u_i, EDGE_OUT, rims[i], back_i],
		]
		for index: int in [0, 1, 2, 0, 2, 3, 3, 2, 4, 3, 4, 5]:
			var corner: Array = ring[index]
			verts.append(corner[0])
			uvs.append(Vector2(float(corner[1]), float(corner[2])))
			colors.append(Color(KIND_EDGE, float(corner[3]), float(corner[4]), _level_channel(level)))
		pieces.append([key, verts, uvs, colors])


## The foot along the wall's foot line: FOOT_UP up the wall and FOOT_OUT over the lower ground, its
## sweep perpendicular to the foot line. UV = (world units along the foot, world units past it);
## colour g = the shadow's strength (stronger facing the lower right).
func _add_foot(pieces: Array, border: Border, foots: PackedVector2Array, depths: PackedFloat32Array, loop: bool, level: float) -> void:
	var points := border.points
	var normals := border.normals
	var has_foot := border.foot
	var count := points.size()
	var foot_normals := PackedVector2Array()
	var foot_along := PackedFloat32Array()
	var length := 0.0
	for i in count:
		# The foot line's way here, from neighbours at least FOOT_SPAN apart (points bunch up where a
		# fold's fibres crowd its foot corner, and close neighbours would make the strip's sweep jitter).
		var before := i
		var after := i
		for step in count:
			var b := before - 1
			if b < 0:
				if not loop:
					break
				b += count
			before = b
			if foots[before].distance_to(foots[i]) >= FOOT_SPAN:
				break
		for step in count:
			var a := after + 1
			if a >= count:
				if not loop:
					break
				a -= count
			after = a
			if foots[after].distance_to(foots[i]) >= FOOT_SPAN:
				break
		var tangent := (foots[after] - foots[before]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		# A foot line folded back on itself (fibres crossing at an inner corner): keep the border's.
		if normal.dot(normals[i]) < 0.2:
			normal = normals[i]
		foot_normals.append(normal)
		if i > 0:
			length += foots[i - 1].distance_to(foots[i])
		foot_along.append(length)
	if loop:
		length += foots[count - 1].distance_to(foots[0])
	var segments := count if loop else count - 1
	# How far each point's strip reaches up the wall and out over the ground: where the foot turns
	# tighter than that (a fold's foot corner, the inside of a round corner) the offsets of two
	# neighbours would cross and fold the strip over itself, so both shrink until they do not.
	# Where a foot's shadow would run under a ramp's slope (drawn over it, so it would end on the
	# slope's edge) it fades out: none at a point whose shadow reaches the slope, half at its
	# neighbours.
	var shadow_scale := PackedFloat32Array()
	shadow_scale.resize(count)
	shadow_scale.fill(1.0)
	var reaches := PackedVector2Array()
	var shadow_lengths := PackedFloat32Array()
	for k in count:
		var facing := SHADOW_EAST * maxf(0.0, foot_normals[k].x) + SHADOW_SOUTH * maxf(0.0, foot_normals[k].y)
		# As long as the wall there is tall: none beyond a back corner's slanted end.
		shadow_lengths.append(FOOT_OUT + SHADOW_PER_LEVEL * depths[k] * facing)
		reaches.append(Vector2(FOOT_UP, shadow_lengths[k]))
	if _under_ramp.is_valid():
		var blocked := PackedByteArray()
		blocked.resize(count)
		for k in count:
			var reach_out := shadow_lengths[k]
			for along: float in [0.0, 0.5, 1.0]:
				if bool(_under_ramp.call(foots[k] + foot_normals[k] * reach_out * along)):
					blocked[k] = 1
					break
		for k in count:
			if blocked[k] == 1:
				shadow_scale[k] = 0.0
			elif blocked[(k + 1) % count] == 1 or blocked[(k - 1 + count) % count] == 1:
				shadow_scale[k] = 0.5
	for side_index in 2:
		var sign := -1.0 if side_index == 0 else 1.0
		for pass_index in 8:
			var changed := false
			for i in segments:
				var j := (i + 1) % count
				var base := foots[j] - foots[i]
				var o_i := foots[i] + foot_normals[i] * sign * reaches[i][side_index]
				var o_j := foots[j] + foot_normals[j] * sign * reaches[j][side_index]
				if base.length() > 0.5 and (o_j - o_i).dot(base) < 0.0:
					reaches[i][side_index] *= 0.6
					reaches[j][side_index] *= 0.6
					changed = true
			if not changed:
				break
	for i in segments:
		var j := (i + 1) % count
		if foots[i].distance_to(foots[j]) < 0.25:
			continue
		# A back edge has no wall but keeps its foot's shadow on the ground behind.
		var back_edge := backness(normals[i]) > 0.5 and backness(normals[j]) > 0.5
		if has_foot[i] < 0.5 or has_foot[j] < 0.5 or (depths[i] <= 0.0 and depths[j] <= 0.0 and not back_edge):
			continue
		var u_of := [foot_along[i], foot_along[j] if j > 0 else length]
		var key := (points[i].y + points[j].y) * 0.5 + FOOT_LEAD
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		# ring: i-up 0, i-edge 1, i-out 2, j-up 3, j-edge 4, j-out 5 ([index, offset along its normal]).
		var ring := []
		for e in 2:
			var k: int = [i, j][e]
			for offset: float in [-reaches[k].x, 0.0, reaches[k].y]:
				ring.append([k, offset, float(u_of[e])])
		for index: int in [0, 3, 4, 0, 4, 1, 1, 4, 5, 1, 5, 2]:
			var corner: Array = ring[index]
			var k := int(corner[0])
			var offset := float(corner[1])
			var shadow := (FOOT_SHADOW + FOOT_SHADOW_EAST * maxf(0.0, foot_normals[k].dot(SHADOW_FROM))) * shadow_scale[k]
			verts.append(foots[k] + foot_normals[k] * offset)
			# Past the foot the art's rows run over the shadow's whole length (FOOT_OUT of them).
			uvs.append(Vector2(float(corner[2]), offset * FOOT_OUT / shadow_lengths[k] if offset > 0.0 else offset))
			var kind := KIND_FOOT_WATER if border.water[k] > 0.5 else KIND_FOOT
			colors.append(Color(kind, shadow, backness(normals[k]), _level_channel(level - border.drop[k])))
		pieces.append([key, verts, uvs, colors])


## Where an offset of the border by `distance` (along the outward normal; negative inwards) would
## fold over itself around `corner` (an outer corner offset inwards, an inner one outwards, further
## than its radius), its points meet in the mitre of the two runs' offsets instead.
func _mitre(offsets: PackedVector2Array, corner: Dictionary, distance: float, loop: bool) -> void:
	var convex := bool(corner["convex"])
	if (convex and distance >= 0.0) or (not convex and distance <= 0.0):
		return
	if absf(distance) <= float(corner["radius"]):
		return
	var n_a: Vector2 = corner["n_a"]
	var n_b: Vector2 = corner["n_b"]
	var e_a: Vector2 = corner["e_a"]
	var e_b: Vector2 = corner["e_b"]
	var mitre: Vector2 = (corner["vertex"] as Vector2) + (n_a + n_b) * distance / (1.0 + n_a.dot(n_b))
	var first := int(corner["first"])
	var last := int(corner["last"])
	var count := offsets.size()
	for i in range(first, last + 1):
		offsets[i] = mitre
	# The runs on either side, as far as their offsets pass the mitre.
	var k := first - 1
	var steps := 0
	while steps < count:
		if k < 0:
			if not loop:
				break
			k += count
		if (offsets[k] - mitre).dot(e_a) <= 0.0:
			break
		offsets[k] = mitre
		k -= 1
		steps += 1
	k = last + 1
	steps = 0
	while steps < count:
		if k >= count:
			if not loop:
				break
			k -= count
		if (offsets[k] - mitre).dot(e_b) >= 0.0:
			break
		offsets[k] = mitre
		k += 1
		steps += 1


## The stretch of u along a loop `length` units long so it closes on whole periods of art `width`
## px wide (2 px per unit); 1 along a line or without art.
static func _period_scale(length: float, width: float, loop: bool) -> float:
	if not loop or width <= 0.0 or length <= 0.0:
		return 1.0
	var periods := maxf(1.0, roundf(length * 2.0 / width))
	return periods * width / (length * 2.0)


## A smooth wobble in −1 … 1 at `point` (world units), the same wherever the border is built from.
static func _wobble(point: Vector2) -> float:
	return 0.65 * _value_noise(point / WOBBLE_LONG) + 0.35 * _value_noise(point / WOBBLE_SHORT + Vector2(17.3, 5.1))


static func _value_noise(p: Vector2) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var f := p - Vector2(ix, iy)
	var s := f * f * (Vector2(3.0, 3.0) - f * 2.0)
	var top := lerpf(_hash(ix, iy), _hash(ix + 1, iy), s.x)
	var bottom := lerpf(_hash(ix, iy + 1), _hash(ix + 1, iy + 1), s.x)
	return lerpf(top, bottom, s.y)


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 32767.5 - 1.0


## A level (or a height between levels) in a vertex colour channel (elevation_light.gdshaderinc).
static func _level_channel(level: float) -> float:
	return (level + 4.0) / 8.0
