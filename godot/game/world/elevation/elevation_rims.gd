extends RefCounted
## The border of every cliff top (docs/godot/ELEVATION.md): its boundary edges, where a top tri meets
## lower ground or a wall at or below its level, directed with the top on the left. LIP where the
## top hangs over the wall right below it (a south face), RIM elsewhere (north, east, west, the back
## diagonals, a hole's near rim). The walls (sides/elevation_sides.gd) are built along them;
## fences are painted on their own layer and do not follow rims (game/world/fences/fences.gd).
##
## It also adds, past every rim, a thin core of the top's depth to the occlusion map (`add_cores`: a
## body behind the hill is hidden behind the top's edge too).
##
## Owner: world (elevation).

const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")

const LIP := 0
const RIM := 1
## Width of a rim's depth core past the edge (world units).
const CORE := 6.0

var grid: ElevationGrid
var cell := 64.0


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
		# A side beside the lower courses of a higher wall (a terrace against a cliff, the wall going on
		# down past it): the terrace's edge runs on up to that wall (2026-11-06, the owner: "the low
		# level should reach the top wall and blend nicely with it"), drawn without a foot
		# (ElevationSides._edge_drop: the wall is behind it, no ground).
		return RIM if kind == ElevationGrid.VERTICAL and int(band["bottom"]) < level else -1
	if kind != ElevationGrid.VERTICAL and upper_is_north and int(band["top"]) == level \
			and across == grid.column_tri(int(band["column"]), int(band["start"])):
		return LIP
	return RIM


## A thin core just past every rim of `edges` (boundary edges, cells) with its top's depth
## (`encode_depth`: Callable(level, dy) -> Color, elevation_occlusion.gd), so the top's edge hides a
## body behind it too.
func add_cores(depth: MeshData, edges: Array[Dictionary], encode_depth: Callable) -> void:
	for edge in edges:
		if int(edge["mode"]) != RIM:
			continue
		var from: Vector2 = (edge["from"] as Vector2) * cell
		var to: Vector2 = (edge["to"] as Vector2) * cell
		var dir := (to - from).normalized()
		var d := Vector2(-dir.y, dir.x)
		var level := int(edge["level"])
		var edge_color: Color = encode_depth.call(level, 0.0)
		var core_color: Color = encode_depth.call(level, d.y * CORE)
		for point_color: Array in [[from, edge_color], [to, edge_color], [to + d * CORE, core_color],
				[from, edge_color], [to + d * CORE, core_color], [from + d * CORE, core_color]]:
			depth.add(point_color[0], Vector2.ZERO, point_color[1])
