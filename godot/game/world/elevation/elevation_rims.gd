extends RefCounted
## The border of every cliff top as one continuous strip of its ground's fringe art
## (docs/godot/ELEVATION.md, art/<ground>-lip.png, elevation_fringe.gdshader).
##
## The top's boundary edges (where a top tri meets lower ground or a wall at or below its level)
## are chained into loops and lines, the top on the left. Along a south face the strip is the lip:
## tufts, soil and roots hanging over the wall, swept straight down (also on diagonal faces). Along
## every other edge (north, east, west, the back diagonals, a hole's near rim) it is the rim: the
## same tufts swept perpendicular to the edge, the soil and roots cut away (vertex colour b = 1).
## The art's u runs along the chain without restarting, convex corners turn in a round fan and
## concave ones meet in a mitre, so lip and rim flow into each other around every corner.
##
## It also adds, per rim, the light the top edge catches when it faces the upper-left light
## (Rims/glow) and a thin core of the top's depth just past the edge to the occlusion map (a body
## behind the hill is hidden behind the rim's tufts too).
##
## Owner: world (elevation).

const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")

const LIP := 0
const RIM := 1
## Art rows (px, 2 per world unit) and reaches (world units): the edge line runs on EDGE_ROW; the
## strip reaches IN units over the top and LIP_OUT / RIM_OUT past the edge.
const EDGE_ROW := 96.0
const IN := 48.0
const LIP_OUT := 32.0
const RIM_OUT := 8.0
## Fan triangles per radian at a convex corner.
const FAN_STEPS_PER_RADIAN := 4.0
## A concave mitre longer than this many reaches becomes a bevel.
const MITRE_LIMIT := 3.0
## The light from the upper left (rims facing it catch light) and the glow's reach (world units).
const LIGHT_FROM := Vector2(-0.7071, -0.7071)
const GLOW := Color(0.12, 0.11, 0.07, 1.0)
const GLOW_REACH := 7.0
## Width of the rim's depth core past the edge (world units).
const CORE := 6.0

var grid: ElevationGrid
var cell := 64.0


## Builds the strips of every top whose ground `has_lip` (Callable(ground) -> bool) into
## `lips[<ground> + key_suffix]`, the glow into `glow` and the depth cores into `depth` (vertex
## colours as elevation_occlusion.gd encodes them). `lip_shadow`: the shadow a lip casts on its
## wall. Returns the boundary edges of tops without lip art ({from, to, mode, level, ground, x} in
## cells) for the caller's fallback strips.
func build(the_grid: ElevationGrid, cell_size: float, has_lip: Callable, lips: Dictionary, key_suffix: String,
		glow: MeshData, depth: MeshData, lip_shadow: float, encode_depth: Callable) -> Array[Dictionary]:
	grid = the_grid
	cell = cell_size
	var edges := boundary_edges()
	var leftover: Array[Dictionary] = []
	var with_art: Array[Dictionary] = []
	for edge in edges:
		if has_lip.call(str(edge["ground"])):
			with_art.append(edge)
		else:
			leftover.append(edge)
	for chain in _chains(with_art):
		var segments := _segments(chain)
		var key := str(segments[0]["ground"]) + key_suffix
		if not lips.has(key):
			lips[key] = MeshData.new()
		_add_chain(lips[key], segments, _is_loop(chain), lip_shadow)
		for segment in segments:
			if int(segment["mode"]) == RIM:
				_add_glow(glow, segment)
				_add_core(depth, segment, encode_depth)
	return leftover


## Every boundary edge of every top, directed with the top on its left: {from, to (cells), mode
## (LIP or RIM), level, ground, x (the tri across the edge)}.
func boundary_edges() -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for edge: Array in grid.tri_edges():
		var a := int(edge[0])
		var b := int(edge[1])
		var kind := int(edge[2])
		for upper_is_a: bool in [true, false]:
			var upper := a if upper_is_a else b
			var across := b if upper_is_a else a
			var mode := _boundary_mode(upper, across, kind, upper_is_a)
			if mode < 0:
				continue
			# tri_edges runs non-vertical edges with `a` on the left, vertical ones with `b`.
			var forward := upper_is_a if kind != ElevationGrid.VERTICAL else not upper_is_a
			var p0: Vector2 = edge[3]
			var p1: Vector2 = edge[4]
			edges.append({
				"from": p0 if forward else p1, "to": p1 if forward else p0, "mode": mode,
				"level": grid.tri_level[upper], "ground": grid.tri_ground[upper], "x": across,
			})
	return edges


## LIP where `upper` hangs over the wall right below it, RIM where it meets lower ground or a wall
## at or below its level elsewhere, -1 when the edge is no border of `upper`.
func _boundary_mode(upper: int, across: int, kind: int, upper_is_north: bool) -> int:
	if grid.tri_band[upper] >= 0:
		return -1
	var level := grid.tri_level[upper]
	if grid.tri_band[across] < 0:
		return RIM if grid.tri_level[across] < level else -1
	var band: Dictionary = grid.bands[grid.tri_band[across]]
	if int(band["top"]) > level:
		return -1
	if kind != ElevationGrid.VERTICAL and upper_is_north and int(band["top"]) == level \
			and across == grid.column_tri(int(band["column"]), int(band["start"])):
		return LIP
	return RIM


## Edges joined end to start into chains of one level and ground: lines first (their first edge
## has no edge ending at its start), then loops. At a point with several ways on, the sharpest
## left turn keeps to the same top.
func _chains(edges: Array[Dictionary]) -> Array:
	var outgoing := {}
	var incoming := {}
	for i in edges.size():
		var from_key := _key(edges[i]["from"])
		var to_key := _key(edges[i]["to"])
		if not outgoing.has(from_key):
			outgoing[from_key] = []
		(outgoing[from_key] as Array).append(i)
		if not incoming.has(to_key):
			incoming[to_key] = []
		(incoming[to_key] as Array).append(i)
	var used := PackedByteArray()
	used.resize(edges.size())
	var chains := []
	for pass_index in 2:
		for i in edges.size():
			if used[i]:
				continue
			if pass_index == 0 and _has_predecessor(edges, incoming, used, i):
				continue
			var chain: Array[int] = [i]
			used[i] = 1
			var current := i
			while true:
				var next := _next_edge(edges, outgoing, used, current)
				if next < 0:
					break
				chain.append(next)
				used[next] = 1
				current = next
			chains.append(_with_edges(edges, chain))
	return chains


func _has_predecessor(edges: Array[Dictionary], incoming: Dictionary, used: PackedByteArray, i: int) -> bool:
	for j: int in incoming.get(_key(edges[i]["from"]), []):
		if j != i and not used[j] and _same_strip(edges[i], edges[j]):
			return true
	return false


func _next_edge(edges: Array[Dictionary], outgoing: Dictionary, used: PackedByteArray, current: int) -> int:
	var best := -1
	var best_turn := INF
	var dir := _dir(edges[current])
	for j: int in outgoing.get(_key(edges[current]["to"]), []):
		if used[j] or not _same_strip(edges[current], edges[j]):
			continue
		var next_dir := _dir(edges[j])
		var turn := atan2(dir.x * next_dir.y - dir.y * next_dir.x, dir.dot(next_dir))
		if turn < best_turn:
			best_turn = turn
			best = j
	return best


func _with_edges(edges: Array[Dictionary], chain: Array[int]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in chain:
		out.append(edges[i])
	return out


static func _same_strip(a: Dictionary, b: Dictionary) -> bool:
	return int(a["level"]) == int(b["level"]) and str(a["ground"]) == str(b["ground"])


static func _key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x * 2.0), roundi(point.y * 2.0))


static func _dir(edge: Dictionary) -> Vector2:
	return ((edge["to"] as Vector2) - (edge["from"] as Vector2)).normalized()


func _is_loop(chain: Array[Dictionary]) -> bool:
	return chain.size() > 2 and _key(chain[0]["from"]) == _key(chain[chain.size() - 1]["to"])


## Consecutive edges of one mode running the same way, merged: {from, to (world units), mode, dir,
## offset (the sweep: straight down for a lip, the outward normal for a rim), out, ground, level}.
func _segments(chain: Array[Dictionary]) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for edge in chain:
		var from: Vector2 = (edge["from"] as Vector2) * cell
		var to: Vector2 = (edge["to"] as Vector2) * cell
		var dir := (to - from).normalized()
		var mode := int(edge["mode"])
		if not segments.is_empty():
			var last: Dictionary = segments[segments.size() - 1]
			if int(last["mode"]) == mode and (last["dir"] as Vector2).dot(dir) > 0.9999:
				last["to"] = to
				continue
		segments.append({
			"from": from, "to": to, "mode": mode, "dir": dir,
			"offset": Vector2(0.0, 1.0) if mode == LIP else Vector2(-dir.y, dir.x),
			"out": LIP_OUT if mode == LIP else RIM_OUT,
			"ground": edge["ground"], "level": int(edge["level"]),
		})
	return segments


## The strip of one chain: per segment a quad from the inner reach to the outer one, with mitred
## inner corners; round fans on the outside of convex corners, mitres on concave ones.
func _add_chain(arrays: MeshData, segments: Array[Dictionary], loop: bool, lip_shadow: float) -> void:
	var count := segments.size()
	# Per segment: [inner start, outer start, inner end, outer end].
	var corners: Array = []
	for segment in segments:
		var d: Vector2 = segment["offset"]
		var out := float(segment["out"])
		corners.append([
			(segment["from"] as Vector2) - d * IN, (segment["from"] as Vector2) + d * out,
			(segment["to"] as Vector2) - d * IN, (segment["to"] as Vector2) + d * out,
		])
	# Joins: [segment index, convex, fan points] after each segment that has a successor.
	var joins := {}
	var join_count := count if loop else count - 1
	for i in join_count:
		var j := (i + 1) % count
		var a: Dictionary = segments[i]
		var b: Dictionary = segments[j]
		var v: Vector2 = a["to"]
		var e_a: Vector2 = a["dir"]
		var e_b: Vector2 = b["dir"]
		var d_a: Vector2 = a["offset"]
		var d_b: Vector2 = b["offset"]
		var cross := e_a.x * e_b.y - e_a.y * e_b.x
		var straight := absf(cross) < 1e-4 and e_a.dot(e_b) > 0.0
		if straight and d_a.is_equal_approx(d_b):
			continue
		var convex := cross < 0.0 or straight
		if convex:
			var mitre := _intersect(v - d_a * IN, e_a, v - d_b * IN, e_b, v - d_a * IN)
			corners[i][2] = mitre
			corners[j][0] = mitre
			joins[i] = true
		else:
			var outer := _intersect(v + d_a * float(a["out"]), e_a, v + d_b * float(b["out"]), e_b, Vector2.INF)
			var limit := MITRE_LIMIT * maxf(float(a["out"]), float(b["out"]))
			if outer != Vector2.INF and outer.distance_to(v) <= limit:
				corners[i][3] = outer
				corners[j][1] = outer
			joins[i] = false
	var u := 0.0
	for i in count:
		var segment: Dictionary = segments[i]
		var length := (segment["from"] as Vector2).distance_to(segment["to"])
		var u_end := u + length * 2.0
		var level := float(segment["level"])
		var rim := 1.0 if int(segment["mode"]) == RIM else 0.0
		var shadow := lip_shadow if rim == 0.0 else 0.0
		var out := float(segment["out"])
		var c: Array = corners[i]
		var edge_from: Vector2 = segment["from"]
		var edge_to: Vector2 = segment["to"]
		# Inner half and outer half, so the edge line keeps its own row.
		_quad(arrays, c[0], c[2], edge_to, edge_from, [u, u_end, u_end, u], [0.0, 0.0, EDGE_ROW, EDGE_ROW],
				[-IN, -IN, 0.0, 0.0], shadow, rim, level)
		_quad(arrays, edge_from, edge_to, c[3], c[1], [u, u_end, u_end, u], [EDGE_ROW, EDGE_ROW, EDGE_ROW + out * 2.0, EDGE_ROW + out * 2.0],
				[0.0, 0.0, out, out], shadow, rim, level)
		u = u_end
		if joins.has(i):
			var j := (i + 1) % count
			var next: Dictionary = segments[j]
			if bool(joins[i]):
				u = _add_fan(arrays, segment, next, u, lip_shadow)
			else:
				_add_bevel(arrays, segment, next, corners[i][2], corners[j][0], u)


## Round outer corner from `a`'s sweep to `b`'s around their shared point; returns the u after it.
func _add_fan(arrays: MeshData, a: Dictionary, b: Dictionary, u: float, lip_shadow: float) -> float:
	var v: Vector2 = a["to"]
	var d_a: Vector2 = a["offset"]
	var d_b: Vector2 = b["offset"]
	var angle_a := d_a.angle()
	var delta := wrapf(d_b.angle() - angle_a, -PI, PI)
	var steps := maxi(1, ceili(absf(delta) * FAN_STEPS_PER_RADIAN))
	var out_a := float(a["out"])
	var out_b := float(b["out"])
	var rim_a := 1.0 if int(a["mode"]) == RIM else 0.0
	var rim_b := 1.0 if int(b["mode"]) == RIM else 0.0
	var level := float(a["level"])
	var arc := absf(delta) * (out_a + out_b) * 0.5 * 2.0
	var previous := v + d_a * out_a
	var previous_t := 0.0
	for step in range(1, steps + 1):
		var t := float(step) / steps
		var out := lerpf(out_a, out_b, t)
		var point := v + Vector2.from_angle(angle_a + delta * t) * out
		var rim_prev := lerpf(rim_a, rim_b, previous_t)
		var rim_now := lerpf(rim_a, rim_b, t)
		var out_prev := lerpf(out_a, out_b, previous_t)
		var u_mid := u + arc * (previous_t + t) * 0.5
		arrays.add(v, Vector2(u_mid, EDGE_ROW), _color(lip_shadow * (1.0 - rim_prev), 0.0, rim_prev, level))
		arrays.add(previous, Vector2(u + arc * previous_t, EDGE_ROW + out_prev * 2.0), _color(lip_shadow * (1.0 - rim_prev), out_prev, rim_prev, level))
		arrays.add(point, Vector2(u + arc * t, EDGE_ROW + out * 2.0), _color(lip_shadow * (1.0 - rim_now), out, rim_now, level))
		previous = point
		previous_t = t
	return u + arc


## Inner gap of a concave corner: one triangle from the shared point to both inner reaches.
func _add_bevel(arrays: MeshData, a: Dictionary, b: Dictionary, inner_a: Vector2, inner_b: Vector2, u: float) -> void:
	var v: Vector2 = a["to"]
	var rim := 1.0 if int(a["mode"]) == RIM or int(b["mode"]) == RIM else 0.0
	var level := float(a["level"])
	arrays.add(v, Vector2(u, EDGE_ROW), _color(0.0, 0.0, rim, level))
	arrays.add(inner_a, Vector2(u, 0.0), _color(0.0, -IN, rim, level))
	arrays.add(inner_b, Vector2(u, 0.0), _color(0.0, -IN, rim, level))


## A quad p0 p1 p2 p3 (in order around it) as two triangles.
func _quad(arrays: MeshData, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, us: Array, vs: Array,
		outs: Array, shadow: float, rim: float, level: float) -> void:
	var points := [p0, p1, p2, p3]
	for index: int in [0, 1, 2, 0, 2, 3]:
		arrays.add(points[index], Vector2(float(us[index]), float(vs[index])), _color(shadow, float(outs[index]), rim, level))


## Fringe vertex data (elevation_fringe.gdshader): r = shadow strength, g = outward distance
## ((d + 64) / 128), b = rim (the soil and roots cut away), a = the ground's level.
static func _color(shadow: float, outward: float, rim: float, level: float) -> Color:
	return Color(shadow, (outward + 64.0) / 128.0, rim, (level + 4.0) / 8.0)


## Where line (p, dir_p) meets line (q, dir_q); `fallback` when they run parallel.
static func _intersect(p: Vector2, dir_p: Vector2, q: Vector2, dir_q: Vector2, fallback: Vector2) -> Vector2:
	var denominator := dir_p.x * dir_q.y - dir_p.y * dir_q.x
	if absf(denominator) < 1e-6:
		return fallback
	var t := ((q.x - p.x) * dir_q.y - (q.y - p.y) * dir_q.x) / denominator
	return p + dir_p * t


## The light a rim facing the upper left catches, fading from its edge over the top.
func _add_glow(glow: MeshData, segment: Dictionary) -> void:
	var lit := maxf(0.0, (segment["offset"] as Vector2).dot(LIGHT_FROM))
	if lit <= 0.05:
		return
	var color := Color(GLOW.r * lit, GLOW.g * lit, GLOW.b * lit, 1.0)
	var clear := Color(color, 0.0)
	var from: Vector2 = segment["from"]
	var to: Vector2 = segment["to"]
	var inward := -(segment["offset"] as Vector2) * GLOW_REACH
	for point_color: Array in [[from, color], [to, color], [to + inward, clear], [from, color], [to + inward, clear], [from + inward, clear]]:
		glow.add(point_color[0], Vector2.ZERO, point_color[1])


## A thin core just past a rim with the top's depth (elevation_occlusion.gd), so the rim's tufts
## hide a body behind them too.
func _add_core(depth: MeshData, segment: Dictionary, encode_depth: Callable) -> void:
	var from: Vector2 = segment["from"]
	var to: Vector2 = segment["to"]
	var d: Vector2 = segment["offset"]
	var level := int(segment["level"])
	var edge_color: Color = encode_depth.call(level, 0.0)
	var core_color: Color = encode_depth.call(level, d.y * CORE)
	for point_color: Array in [[from, edge_color], [to, edge_color], [to + d * CORE, core_color],
			[from, edge_color], [to + d * CORE, core_color], [from + d * CORE, core_color]]:
		depth.add(point_color[0], Vector2.ZERO, point_color[1])
