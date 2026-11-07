extends RefCounted
## Cliffs that read as raised blocks from all four sides (docs/godot/ELEVATION.md "Side walls",
## 2026-10-13): besides the front (south) wall, the east and west sides show a narrow strip of the
## same wall seen from the side, and the back (north) edge no wall at all; front corners are round, the
## wall turning from the front onto the side, while at a back corner the side wall starts with a
## slanted end, so the back edge visibly runs on behind it (the ground behind the hill can be walked).
## Tops and feet wobble instead of running ruler-straight. Every world's cliffs are drawn this way
## (the owner, 2026-10-14: "I think it is the way to go"); the model, collision, stairs and ramps
## stay the elevation system's.
##
## How it is drawn. Every top's border (ElevationRims.boundary_edges, the top on the left) is
## chained per level into loops and lines, its corners rounded (RADIUS_OUTER, RADIUS_INNER;
## RADIUS_BACK at a back corner, RADIUS_FOLD where a side meets an edge at an inner corner) and
## resampled every STEP units. Each point hangs a "fibre": from the top edge (wobbled, TOP_WOBBLE) to
## the foot, the way its outward normal points, as long as the reach of a shape K for its drop
## (`reach`): FRONT per level down on a front face, SIDE out on a side, nothing on a back edge
## (BACK_FADE), a superellipse (SHAPE) between them, so a front corner's wall turns smoothly onto the
## side. Next to a back corner a side's sideways reach is cut to CAP_SLOPE of its distance from it
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
## first; a chain's walls take its commonest style, or the style painted on the `cliffs` layer
## where there is one, a chain's stretches of painted style going into meshes of their own). Its pieces are drawn by the depth of the top edge they hang from (the screen y of the
## smooth border): where faces overlap, at an inner corner, the nearer (more southern) face is drawn
## over the farther one. A top edge follows its wall a little (EDGE_LEAD), a foot a stretch more
## (FOOT_LEAD), so they stay over the walls they belong to.
##
## Owner: world (elevation).

const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const ElevationRims := preload("res://game/world/elevation/elevation_rims.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const LedgeDressing := preload("res://game/world/elevation/sides/ledge_dressing.gd")

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
## A chain's art starts 0 … START_PERIODS − 1 whole periods in (`_add_chain`), so the wall variation
## picks another run of variants on each chain; few enough that u stays small (a float, read by the
## shader: the web's GPUs too).
const START_PERIODS := 64
## Between two chunk lines a chain's art stretches this much at most to meet both (`_anchored_u`);
## beyond that it runs on from the first line.
const STRETCH_MIN := 0.75
const STRETCH_MAX := 1.33
## The overworld's size (world units) at most: a chunk line's u is kept positive by it.
const REGION_SPAN := 16384.0
## No higher wall behind an edge (`_over_level`).
const NO_OVER := -100
## A terrace's foot shadow fades out over this many units before its side meets a higher wall
## (`_fade_shadow_near_walls`).
const WALL_SHADOW_FADE := 72.0
## Marks the mesh key of a terrace side drawn after a higher level's walls (`build`): kept off that
## level's own mesh of the same style and grounds, so it can come after it.
const OVER_KEY := "~over"
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
## TerrainMaterials.WATER, the ground whose feet stand in water.
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
## EDGE_OUT past the edge (the hanging clumps, a shaggy lip's tufts, rim stones); the foot FOOT_UP up
## the wall (clumps and line, tall grass, fallen stones) and FOOT_OUT over the lower ground (the
## shadow), and a dry foot's art FOOT_DOWN over the ground too (a foot strip's ferns in front of the
## wall). elevation_sides.gdshader draws within them: the top's ground only `grass_reach_in` (12) over
## the top, a lip strip's art the rest (its ledge variety; EDGE_IN 12, EDGE_OUT 9, FOOT_UP 7 and no
## FOOT_DOWN before 2026-11-05).
const EDGE_IN := 36.0
## A point belongs to a corner's run while its normal stays this close to the run's (`_mitre`).
const MITRE_RUN_DOT := 0.9
const EDGE_OUT := 24.0
const FOOT_UP := 30.0
const FOOT_DOWN := 16.0
const FOOT_OUT := 20.0
## Each chain's top edge and foot measure u from their own start (`_edge_seed`: 0 … EDGE_SEEDS − 1 times
## EDGE_SEED_STEP world units, by where the chain lies), so the shader's ledge variety and clumps run
## another sequence on every hill instead of the same one from each chain's start.
const EDGE_SEEDS := 512
const EDGE_SEED_STEP := 97.0
## The shadow past a foot: its strength on a front face, more where the foot faces the lower right,
## and its length: FOOT_OUT, plus SHADOW_PER_LEVEL per level of drop as the foot faces east
## (SHADOW_EAST) or south (SHADOW_SOUTH) — the light comes from the upper left, so a hill casts
## its shadow to the lower right, longer for a taller one. (The model's own cast shadows, which
## followed its square cells, were the front-only look's and went with it on 2026-10-17.)
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
## A point of a border has a wall for collision where its fibre reaches out further than this (world
## units): a back edge has none (its foot lies a little out only by the top edge's wobble), so the
## strip behind a hill stays open.
const WALL_MIN := 0.75
const KIND_WALL := 0.0
## A wall's colour r runs from KIND_WALL to KIND_WALL + KIND_SIDE as it is a side's (the shader
## blends the style's side strip art in by it).
const KIND_SIDE := 0.2
const KIND_CORNER := 0.3
const KIND_FOOT := 0.5
## A dry foot of the side walls is two pieces: its art (KIND_FOOT_ART: from FOOT_UP up the wall to
## FOOT_DOWN over the ground, in world units, so a foot strip's ferns are not stretched) and its shadow
## ring (KIND_FOOT_SHADOW: the shadow only, its rows stretched over the shadow's length). KIND_FOOT
## draws both in one piece (a ramp's foot, elevation.gd `_add_ramp_foot`).
const KIND_FOOT_ART := 0.46
const KIND_FOOT_SHADOW := 0.48
## A foot standing in water: the water lapping up the wall's base (or, with no water surface, foam).
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
## A foot's shadow (`_shape_shadow`): its length and strength averaged along the foot over
## SHADOW_SMOOTH units either way; runs of foot whose ends lie within SHADOW_JOIN units of each other
## cast one shadow (`_shadow_runs`); at most SHADOW_RELAX passes turn its crossing fibres apart.
const SHADOW_SMOOTH := 24.0
const SHADOW_JOIN := 16.0
const SHADOW_RELAX := 400
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
## Callable(point) -> bool: true by a flight of stairs (no ledge dressing there).
var _near_stairs: Callable
## The ledge dressing (sides/ledge_dressing.gd): pieces along each chain's foot, one mesh per level
## after that level's walls. Its `density` 0 places none.
var dressing_density := 1.0
var _dressing: LedgeDressing
## A chunk world's place on the overworld (docs/godot/ELEVATION.md "Across chunk lines"; zero for any
## other world): the overworld position of this builder's (0, 0). The edges' wobble, the corner
## stones' picks and each chain's start follow the overworld, so they match across a chunk line.
var origin := Vector2.ZERO
## The lines this chunk world shares with a neighbouring one (builder space): Vector2(axis: 0 a
## vertical line x = value, 1 a horizontal one y = value, value); empty in any other world. Where a
## chain crosses one, its art is pinned to the line's place (`_anchored_u`), so walls, lips and feet
## run on across it.
var chunk_lines: Array[Vector2] = []
## The chunk's own cells (builder space): what is drawn outside them (its neighbours' edges) is never
## shown in the game.
var own_rect := Rect2()


## A top's border, its corners rounded and resampled (`_border`): per point the smooth point, its
## outward normal, the drop and visible depth (levels), whether a foot grows there (0/1), the rim
## factor (0 a front … 1 a side or back), water status, top/lower ground and wall style, and the
## corner it lies on (-1 on a straight run); the corners {vertex, e_a, e_b, n_a, n_b, convex, back,
## radius, tangent, turn, first, last}.
class Border:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var drop := PackedFloat32Array()
	var shown := PackedFloat32Array()
	var foot := PackedFloat32Array()
	var rim := PackedFloat32Array()
	var water := PackedFloat32Array()
	var top_ground := PackedStringArray()
	var low_ground := PackedStringArray()
	var corner := PackedInt32Array()
	var style := PackedStringArray()
	## The top level of the higher wall the point's edge runs up against (`_over_level`), NO_OVER none.
	var over := PackedInt32Array()
	var corners: Array[Dictionary] = []


## A mesh's place among its level's (`build`): walls 0, a lower terrace's side in front of them 1,
## dressing 2.
static func _draw_rank(entry: Dictionary) -> int:
	if bool(entry.get("dressing", false)):
		return 2
	return 1 if bool(entry.get("over", false)) else 0


## The meshes of every top's sides: [{key, level, style, top_ground, low_ground, arrays}] lowest
## level first. Ground pairs stay per edge; pieces share a mesh only when their pair matches.
## `edges`: the tops' boundary edges to draw (ElevationRims.boundary_edges, cells, those left out
## removed). `style_of` (Callable(edge) -> String): the wall style an edge's ground gives it; a
## chain's walls take the commonest. `painted_of` (Callable(edge) -> String, optional): the style
## painted over an edge's top ("" where none), which its stretch of wall takes instead.
## `grounds_of` (Callable(edge) -> PackedStringArray: the top's ground, the lower ground): the
## grounds its edges are drawn with. `wall_width_of` (Callable(style) -> float): the wall art's
## width in px, so loops close on whole periods. `under_ramp` (Callable(point) -> bool, Elevation
## space): where a ramp's slope lies, drawn over the feet; their shadows fade out before it.
## `near_stairs` (Callable(point) -> bool, Elevation space): by a flight of stairs, where the ledge
## dressing places nothing. The dressing's meshes ("<level>|dressing") come after each level's.
func build(the_grid: ElevationGrid, cell_size: float, edges: Array[Dictionary], style_of: Callable,
		grounds_of: Callable, wall_width_of: Callable, under_ramp: Callable = Callable(),
		painted_of: Callable = Callable(), near_stairs: Callable = Callable()) -> Array[Dictionary]:
	grid = the_grid
	cell = cell_size
	shapes.clear()
	_under_ramp = under_ramp
	_near_stairs = near_stairs
	_dressing = LedgeDressing.new()
	_dressing.density = dressing_density
	_dressing.origin = origin
	var by_key := {}
	for chain in _chains(edges):
		var level := int(chain[0]["level"])
		var styles := {}
		var painted := PackedStringArray()
		for edge in chain:
			painted.append(str(painted_of.call(edge)) if painted_of.is_valid() else "")
			if painted[painted.size() - 1] == "":
				var edge_style := str(style_of.call(edge))
				styles[edge_style] = int(styles.get(edge_style, 0)) + 1
		var style := _most(styles) if not styles.is_empty() else painted[0]
		# Each edge's wall style: what is painted over its top, else the chain's.
		for k in chain.size():
			chain[k]["style"] = painted[k] if painted[k] != "" else style
		var by_material := {}
		_add_chain(by_material, chain, float(wall_width_of.call(style)), grounds_of)
		for material_key: String in by_material:
			var material_group: Dictionary = by_material[material_key]
			var piece_style := str(material_group["style"])
			var top_ground := str(material_group["top_ground"])
			var low_ground := str(material_group["low_ground"])
			# A terrace's side against a higher wall goes with that wall's level, after its walls.
			var over := int(material_group.get("over", NO_OVER))
			var draw_level := over if over != NO_OVER else level
			var key := "%d|%s|%s|%s" % [draw_level, piece_style, top_ground, low_ground]
			if over != NO_OVER:
				key = "%d|%s|%s|%s" % [draw_level, piece_style, top_ground, low_ground + OVER_KEY]
			if not by_key.has(key):
				by_key[key] = {"key": key, "level": draw_level, "style": piece_style, "top_ground": top_ground,
						"low_ground": low_ground, "over": over != NO_OVER, "pieces": []}
			(by_key[key]["pieces"] as Array).append_array(material_group["pieces"])
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
	if _dressing.is_ready():
		out.append_array(_dressing.entries())
	# Lowest level first; within a level its walls, then the sides of lower terraces standing in front of
	# them (`over`), then its dressing.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return _draw_rank(a) < _draw_rank(b))
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
	# Beside a higher wall's lower courses (ElevationRims: a terrace's side run on up to the wall) the
	# wall stands behind it: no foot there.
	var against_wall := int(band["top"]) > level
	return [float(level - int(band["bottom"])), float(level - int(band["bottom"])), not against_wall]


# --- one chain ----------------------------------------------------------------------------

## Straight runs of a chain (world units): {from, to, dir, normal, drop, shown, foot, rim, water (the
## ground below is water), style, top_ground, low_ground}. Adjacent edges merge only when all those
## properties match, so ground treatment stays tile by tile without breaking the wall's geometry.
func _runs(chain: Array[Dictionary], grounds_of: Callable) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for edge in chain:
		var from: Vector2 = (edge["from"] as Vector2) * cell
		var to: Vector2 = (edge["to"] as Vector2) * cell
		var dir := (to - from).normalized()
		var drop := _edge_drop(edge)
		var rim := 1.0 if int(edge["mode"]) == ElevationRims.RIM else 0.0
		# Foam is per edge; shallow water stays visually wet even though it is walkable.
		var water := _ground_below(edge) == WATER
		var style := str(edge.get("style", ""))
		var grounds: PackedStringArray = grounds_of.call(edge)
		var top_ground := str(grounds[0])
		var low_ground := str(grounds[1])
		var over := _over_level(edge)
		if not runs.is_empty():
			var last: Dictionary = runs[runs.size() - 1]
			if (last["dir"] as Vector2).dot(dir) > 0.9999 and float(last["drop"]) == float(drop[0]) \
					and float(last["shown"]) == float(drop[1]) and bool(last["foot"]) == bool(drop[2]) \
					and float(last["rim"]) == rim and bool(last["water"]) == water and str(last["style"]) == style \
					and str(last["top_ground"]) == top_ground and str(last["low_ground"]) == low_ground \
					and int(last["over"]) == over:
				last["to"] = to
				continue
		runs.append({
			"from": from, "to": to, "dir": dir, "normal": Vector2(-dir.y, dir.x),
			"drop": float(drop[0]), "shown": float(drop[1]), "foot": bool(drop[2]), "rim": rim, "water": water,
			"style": style, "top_ground": top_ground, "low_ground": low_ground, "over": over,
		})
	return runs


## A terrace's foot shadow fades out over the last WALL_SHADOW_FADE units before its side runs up
## against a higher wall (`border.over`): it fell across that wall's own foot there (the owner,
## 2026-11-06: "mitigate this shadow and artifacts going to the other wall").
func _fade_shadow_near_walls(border: Border, shadow_scale: PackedFloat32Array) -> void:
	var count := border.points.size()
	var walls := PackedInt32Array()
	for i in count:
		if border.over[i] != NO_OVER:
			walls.append(i)
	if walls.is_empty():
		return
	for k in count:
		if border.over[k] != NO_OVER:
			continue
		var nearest := INF
		for i: int in walls:
			nearest = minf(nearest, border.points[k].distance_to(border.points[i]))
		shadow_scale[k] *= smoothstep(0.0, WALL_SHADOW_FADE, nearest)


## A terrace's side strip where it runs up against a higher wall (`border.over`, at a line chain's
## start or end) starts from nothing at that wall and widens to its full width where its own foot
## begins, as a hole's side strip meets its far wall (the owner, 2026-11-06: "a join ... like an
## interior joint only seen on holes"); its depth with it.
func _taper_against_walls(border: Border, fibres: PackedVector2Array, depths: PackedFloat32Array, loop: bool) -> void:
	var count := border.points.size()
	if loop or count < 2:
		return
	var along := PackedFloat32Array()
	var length := 0.0
	for i in count:
		if i > 0:
			length += border.points[i - 1].distance_to(border.points[i])
		along.append(length)
	# The run of points against a wall at the chain's start, then at its end.
	for at_start: bool in [true, false]:
		var last := -1
		for step in count:
			var i := step if at_start else count - 1 - step
			if border.over[i] == NO_OVER:
				break
			last = i
		if last < 0:
			continue
		var span := absf(along[last] - along[0 if at_start else count - 1])
		if span < 1.0:
			continue
		for step in count:
			var i := step if at_start else count - 1 - step
			if border.over[i] == NO_OVER:
				break
			var t := absf(along[i] - along[0 if at_start else count - 1]) / span
			fibres[i] *= t
			depths[i] *= t


## The top level of the higher wall a top's side edge runs up against (ElevationRims: a terrace's side
## beside that wall's lower courses, 2026-11-06), else NO_OVER. Its pieces are drawn after that level's
## walls (`build`): in front of the wall's lower courses, as the terrace stands.
func _over_level(edge: Dictionary) -> int:
	var band_index := grid.tri_band[int(edge["x"])]
	if band_index < 0:
		return NO_OVER
	var top := int(grid.bands[band_index]["top"])
	return top if top > int(edge["level"]) else NO_OVER


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


## True when an inner corner joins a true side (east or west: |x| over 0.9) and a front or back edge
## (a 45° one too). A straight front meeting a 45° face (|x| 0.707) is no such corner: each keeps its
## own courses and their feet meet (`_meet_feet`); until 2026-11-06 the 45° face counted as a side
## and the two folded, the front's stones turning into a side's single tall course for some three cells.
static func _is_side_inner_corner(n_a: Vector2, n_b: Vector2, convex: bool) -> bool:
	if convex:
		return false
	return (absf(n_a.x) > 0.9 and absf(n_b.y) > 0.7) or (absf(n_b.x) > 0.9 and absf(n_a.y) > 0.7)


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
	# At a ground change, water foam turns around only the water side of the rounded corner.
	var water_a := 1.0 if bool(a["water"]) else 0.0
	var water_b := 1.0 if bool(b["water"]) else 0.0
	border.water.append(lerpf(water_a, water_b, t))
	border.style.append(str(a["style"]) if t < 0.5 else str(b["style"]))
	border.over.append(int(a["over"]) if t < 0.5 else int(b["over"]))
	border.top_ground.append(str(a["top_ground"]) if t < 0.5 else str(b["top_ground"]))
	border.low_ground.append(str(a["low_ground"]) if t < 0.5 else str(b["low_ground"]))
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


## Per point of the border, the share of its fibre's sideways reach that is drawn: 1, but at a back
## corner the side's wall starts where the round of the top begins (the back edge's end) and widens
## CAP_SLOPE per unit along the border, round the corner and on down the side, to its full width: a
## slanted end that hugs the round (the owner, 2026-10-13: "now that the top border is round the wall
## should get a little higher"). Only the sideways reach: where a back face meets a 45° front face at
## one corner (an octagon's east and west points) the front wall hangs its full height from the corner
## (until 2026-11-03 its fibres were cut too, so its foot slanted up to the corner and then jumped).
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
			var sideways := absf(reach(border.normals[k], border.shown[k]).x)
			if sideways > 0.0:
				caps[k] = minf(caps[k], minf(1.0, CAP_SLOPE * distance / sideways))
			k += 1 if forward else -1
			steps += 1
	return caps


## One chain's pieces into `by_style` (style -> pieces), each by the wall style of the border point
## it hangs from. `wall_width`: the chain's own style's wall art width (px).
func _add_chain(by_material: Dictionary, chain: Array[Dictionary], wall_width: float, grounds_of: Callable) -> void:
	var pieces: Array = []
	var loop := chain.size() > 2 and _point_key(chain[0]["from"]) == _point_key(chain[chain.size() - 1]["to"])
	var runs := _runs(chain, grounds_of)
	if runs.is_empty():
		return
	# A loop starts wherever its first edge lies, often partway along a straight run: join the run's
	# two pieces, or the short one would leave no room to round the corner after it.
	if loop and runs.size() > 2:
		var last: Dictionary = runs[runs.size() - 1]
		var first: Dictionary = runs[0]
		if (last["dir"] as Vector2).dot(first["dir"]) > 0.9999 and float(last["drop"]) == float(first["drop"]) \
				and float(last["shown"]) == float(first["shown"]) and bool(last["foot"]) == bool(first["foot"]) \
				and float(last["rim"]) == float(first["rim"]) and bool(last["water"]) == bool(first["water"]) \
				and str(last["style"]) == str(first["style"]) \
				and str(last["top_ground"]) == str(first["top_ground"]) \
				and str(last["low_ground"]) == str(first["low_ground"]):
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
	# Each point's fibre (from the top edge to the foot), its sideways reach cut next to back corners,
	# how deep it reaches (levels: as much less as it is shorter) and the light of its face; inner
	# corners of a front and a side wall fold round (`_fold_corners`).
	var depths := PackedFloat32Array()
	var fibres := PackedVector2Array()
	var lights := PackedFloat32Array()
	var folded := PackedFloat32Array()
	folded.resize(count)
	for i in count:
		# Round a back corner, the arc's half that faces the front (an octagon's east or west point,
		# between a back face and a 45° front face) hangs that front wall as it is: it ends there.
		var n := normals[i]
		if n.y > 0.0 and _on_back_corner(border, i, true):
			var corner: Dictionary = border.corners[border.corner[i]]
			n = corner["n_b"] if (corner["n_a"] as Vector2).y < -0.5 else corner["n_a"]
		var full := reach(n, border.shown[i])
		var fibre := Vector2(full.x * caps[i], full.y)
		fibres.append(fibre)
		depths.append(border.shown[i] * (fibre.length() / full.length() if full.length() > 1e-6 else caps[i]))
		lights.append(shade(n))
	_taper_against_walls(border, fibres, depths, loop)
	_fold_corners(border, fibres, lights, folded, loop)
	# The feet's normals (a side's where a strip runs on past a back edge's corner: `_open_corners`).
	var foot_ns := border.normals.duplicate()
	_open_corners(border, fibres, depths, lights, folded, foot_ns, loop)
	_meet_feet(border, fibres, folded, loop)
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
			var step := previous.distance_to(middle)
			# Round a back corner beside a front face the fibres swing from the back edge's (none) to
			# that wall's: the art runs on only across them, not down them, or the wall's end (an
			# octagon's east and west points) would show a crowd of thin stones.
			if _on_back_corner(border, i, true) and _on_back_corner(border, i - 1, true):
				var way := fibres[i] + fibres[i - 1]
				if way.length() > 0.01:
					var delta := middle - previous
					step = (delta - way.normalized() * delta.dot(way.normalized())).length()
			wall_length += step * (rates[i - 1] + rates[i]) * 0.5
		wall_along.append(wall_length)
		previous = middle
		# Outward only: an edge pulled in would leave a sliver of the top's square cells past it.
		var top := p + n * TOP_WOBBLE * (0.5 + 0.5 * _wobble(p + origin))
		tops.append(top)
		# The foot wobbles on its own, along its fibre, as much as there is wall to wobble (none on a
		# back edge); in a fold it lies on the fold's foot line (the wobbles there would push it back
		# and forth along that line).
		var foot_wobble := FOOT_WOBBLE * minf(1.0, fibre.length() / FOOT_WOBBLE)
		var way := fibre.normalized() if fibre.length() > 0.01 else n
		var shift := (top - p) + way * foot_wobble * _wobble(p + origin + Vector2(311.0, 97.0))
		foots.append(p + fibre + shift * (1.0 - folded[i]))
	if loop:
		wall_length += previous.distance_to(points[0] + fibres[0] * U_DEPTH) * (rates[count - 1] + rates[0]) * 0.5
	var segments := count if loop else count - 1
	# u: 2 px of art per unit along the border, a loop stretched to close on whole periods.
	var wall_scale := _period_scale(wall_length, wall_width, loop)
	# Each chain's art starts a whole number of periods in, picked by where the chain lies: the plain
	# art looks the same, and the wall variation (the shader picks a variant per period) runs another
	# sequence of variants on every chain instead of the same one from each chain's start.
	var start := points[0] + origin
	var u_start := float(posmod(int(floor(start.x / 8.0)) * 7919 + int(floor(start.y / 8.0)) * 104729, START_PERIODS)) * wall_width
	# Across a chunk line u is the line's own (`_anchored_u`; empty where the chain crosses none).
	var pinned := _anchored_u(points, wall_along, wall_length, loop, 2.0, 2.0)
	var course := float(posmod(int(level), 2)) * 128.0
	# How many pieces each fibre is cut into down its length: a course per half level beside a wall
	# that fans out (a corner), so the art bends smoothly there; else one. Both walls beside a fibre cut
	# it at the same points: one cut where the other is not leaves hairline cracks between them.
	var cuts := PackedInt32Array()
	cuts.resize(count)
	cuts.fill(1)
	for i in segments:
		var j := (i + 1) % count
		if not _alike(tops[i], tops[j], foots[i], foots[j]):
			var want := maxi(1, ceili(maxf(depths[i], depths[j]) * 2.0))
			cuts[i] = maxi(cuts[i], want)
			cuts[j] = maxi(cuts[j], want)
	for i in segments:
		var j := (i + 1) % count
		if (depths[i] <= 0.0 and depths[j] <= 0.0) or (tops[i].distance_to(foots[i]) < 0.5 and tops[j].distance_to(foots[j]) < 0.5):
			continue
		var u_i := u_start + wall_along[i] * 2.0 * wall_scale
		var u_j := u_start + (wall_along[j] if j > 0 else wall_length) * 2.0 * wall_scale
		if not pinned.is_empty():
			u_i = pinned[i]
			u_j = pinned[j] if j > 0 else pinned[count]
		var key := (points[i].y + points[j].y) * 0.5
		_add_wall(pieces, key, tops[i], tops[j], foots[i], foots[j], u_i, u_j, depths[i], depths[j], course, level,
				lights[i], lights[j], sides[i], sides[j], cuts[i], cuts[j])
		(pieces[pieces.size() - 1] as Array).append(i)
	_add_corner_stones(pieces, border, tops, foots, depths, lights, loop, level)
	_add_shape(border, foots, depths, fibres, loop, level)
	_add_corner_fills(pieces, border, level)
	_add_top_edge(pieces, border, tops, loop, level)
	_add_foot(pieces, border, foots, depths, loop, level, foot_ns, tops)
	if _dressing != null and _dressing.is_ready():
		# Its slots by the top edge's u (`_seed_along`, as `_add_top_edge` measures it): pinned at chunk lines.
		var edge_along := PackedFloat32Array()
		var edge_length := 0.0
		for k in count:
			if k > 0:
				edge_length += points[k - 1].distance_to(points[k])
			edge_along.append(edge_length)
		if loop:
			edge_length += points[count - 1].distance_to(points[0])
		_dressing.add_chain(border, foots, depths, fibres, loop, level, _under_ramp, _near_stairs,
				_seed_along(points, edge_along, edge_length, loop))
	for piece: Array in pieces:
		var piece_style := border.style[int(piece[4])]
		var point_index := int(piece[4])
		var top_ground := border.top_ground[point_index]
		var low_ground := border.low_ground[point_index]
		var over := border.over[point_index]
		var material_key := "%s|%s|%s|%d" % [piece_style, top_ground, low_ground, over]
		if not by_material.has(material_key):
			by_material[material_key] = {"style": piece_style, "top_ground": top_ground,
					"low_ground": low_ground, "over": over, "pieces": []}
		(by_material[material_key]["pieces"] as Array).append(piece)


## True when point `i` lies on the arc of a back corner (`_is_back_corner`); with `front`, only one
## whose other face looks to the front (a 45° front face: an octagon's east or west point).
static func _on_back_corner(border: Border, i: int, front := false) -> bool:
	var index := border.corner[i]
	if index < 0 or not bool(border.corners[index]["back"]):
		return false
	var corner: Dictionary = border.corners[index]
	var other: Vector2 = corner["n_b"] if (corner["n_a"] as Vector2).y < -0.5 else corner["n_a"]
	return not front or other.y > 0.0


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


## True when two fibres (top edge t → foot f) run alike: the wall between them needs no cuts.
static func _alike(t0: Vector2, t1: Vector2, f0: Vector2, f1: Vector2) -> bool:
	return (f0 - t0).normalized().dot((f1 - t1).normalized()) > 0.999 and absf((f0 - t0).length() - (f1 - t1).length()) < 2.0


## A run of wall between two fibres (top edge t → foot f), each cut into `cuts0` / `cuts1` pieces down
## its length (more where the fibres fan out, at a corner, so the art bends smoothly there), the cut
## points of the two zipped into triangles. Down a front fibre the art shows a course per level, across
## a side one a single course (`side0`, `side1`: how much each is a side's).
func _add_wall(pieces: Array, key: float, t0: Vector2, t1: Vector2, f0: Vector2, f1: Vector2, u0: float, u1: float,
		d0: float, d1: float, course: float, level: float, light0: float, light1: float, side0: float = 0.0,
		side1: float = 0.0, cuts0: int = 1, cuts1: int = 1) -> void:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	# [fibre (0 or 1), share down it] of each triangle's corners: whichever fibre's next cut is nearer
	# the top goes first, the second fibre's on a tie (so two alike fibres split as they always did).
	var a := 0
	var b := 0
	while a < cuts0 or b < cuts1:
		var next_a := float(a + 1) / cuts0
		var next_b := float(b + 1) / cuts1
		var triangle: Array
		if b >= cuts1 or (a < cuts0 and next_a < next_b):
			triangle = [[0, float(a) / cuts0], [1, float(b) / cuts1], [0, next_a]]
			a += 1
		else:
			triangle = [[0, float(a) / cuts0], [1, float(b) / cuts1], [1, next_b]]
			b += 1
		for corner: Array in triangle:
			var second := int(corner[0]) == 1
			var s := float(corner[1])
			var side := side1 if second else side0
			var depth := s * (d1 if second else d0)
			verts.append(t1.lerp(f1, s) if second else t0.lerp(f0, s))
			uvs.append(Vector2(u1 if second else u0, course + lerpf(depth, s, side) * 128.0))
			colors.append(Color(KIND_WALL + KIND_SIDE * side, light1 if second else light0, depth * 128.0 / 512.0,
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
			var at := vertex + origin
			var cell := posmod(int(floor(at.x / 64.0)) * 7 + int(floor(at.y / 64.0)) * 3 + course_index, CORNER_STONES)
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
			pieces.append([vertex.y + 1.0, verts, uvs, colors, middle])


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
## Where the runs are too short for it `_open_corners` meets the two walls along the corner's edge.
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
		corner["folded"] = true
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


## The inner corners of a side wall and a front wall that `_fold_corners` left open (a short side
## under a tall wall: the octagon hole in the park, 3 levels deep, 2026-11-03), and those of a side
## wall and a back edge. Seen from the camera the side wall (its strip, `reach`) is nearer than the
## wall beside it, and the two meet along the corner's edge, from the top's corner down to where
## their feet meet:
## - a front wall: the strip starts from nothing at the corner and widens along that edge to its full
##   width where the two feet meet, with no foot along the edge (it is wall against wall); the front
##   wall's foot starts there too (its stretch before lies behind the strip);
## - a back edge (no wall): the strip runs on past the corner, its fibres out to its own foot line,
##   until the back edge's top hides it, with a side's foot there.
## Before, the strip stopped flat at both ends, as a slab laid on the front wall: its foot's shadow ran
## over that wall with a flat top, and at the back edge the two feet folded into dark wedges.
## Beside a front wall the corner's arc hangs that wall on to the corner on its half (the strip, drawn
## after it, covers its end), so no sliver of the top shows between the two; the two shadows meet
## where the feet do (`_shadow_runs`). The strip's feet past a back edge's corner lie on its foot line,
## unwobbled (`folded`), so they never cross.
func _open_corners(border: Border, fibres: PackedVector2Array, depths: PackedFloat32Array,
		lights: PackedFloat32Array, folded: PackedFloat32Array, foot_ns: PackedVector2Array, loop: bool) -> void:
	var points := border.points
	var count := points.size()
	for corner: Dictionary in border.corners:
		if not bool(corner.get("fold", false)) or bool(corner.get("folded", false)):
			continue
		var n_a: Vector2 = corner["n_a"]
		var n_b: Vector2 = corner["n_b"]
		var side_first := absf(n_a.x) > absf(n_b.x)
		var n_side := n_a if side_first else n_b
		var n_other := n_b if side_first else n_a
		var drop_side := float(corner["drop_a"] if side_first else corner["drop_b"])
		var side := reach(n_side, drop_side)
		# a true side (east or west) beside a front or back edge, not a 45° face beside a front one
		if side.length() < 1.0 or absf(n_side.y) > 0.3 or absf(n_other.y) < 0.7:
			continue
		var vertex: Vector2 = corner["vertex"]
		var e_a: Vector2 = corner["e_a"]
		var e_b: Vector2 = corner["e_b"]
		# Each run away from the corner (run a backwards, run b on), and its points in that order.
		var side_away := -e_a if side_first else e_b
		var other_away := e_b if side_first else -e_a
		var arc := _arc_points(corner, count)
		var side_run := _run_away(border, corner, side_first, loop)
		var other_run := _run_away(border, corner, not side_first, loop)
		var light := shade(n_side)
		if n_other.y > 0.0:
			var drop_other := float(corner["drop_b"] if side_first else corner["drop_a"])
			var other := reach(n_other, drop_other)
			if other.length() < 1.0:
				continue
			# Where the two feet meet: vertex + side + side_away * along = vertex + other + other_away * on.
			var gap := other - side
			var det := side_away.y * other_away.x - side_away.x * other_away.y
			if absf(det) < 0.01:
				continue
			var along := (gap.y * other_away.x - gap.x * other_away.y) / det
			var on := (side_away.x * gap.y - side_away.y * gap.x) / det
			if along <= STEP or on < 0.0:
				continue
			corner["open"] = true
			for k: int in arc + side_run:
				var at := (points[k] - vertex).dot(side_away)
				if at >= along:
					break
				border.foot[k] = 0.0
				if at <= 0.0:
					# the arc's half on the front wall's side: that wall hangs on to the corner
					fibres[k] = other
					depths[k] = drop_other
					lights[k] = shade(n_other)
					continue
				var share := at / along
				fibres[k] = side * share
				depths[k] = drop_side * share
				lights[k] = light
			for k: int in other_run:
				if (points[k] - vertex).dot(other_away) >= on:
					break
				border.foot[k] = 0.0
		else:
			corner["open"] = true
			# The strip's foot line, and how far out to it from a point (along the side's fibre).
			var out := side.normalized()
			var line := vertex + side
			for k: int in arc + other_run:
				var length := (line - points[k]).dot(out)
				if length <= WALL_MIN:
					break
				fibres[k] = out * length
				depths[k] = drop_side
				lights[k] = light
				folded[k] = 1.0
				foot_ns[k] = n_side


## At every other inner corner of two walls (two fronts at a 45° turn, a front and a side whose
## fold did not fit and is not a side's), the walls hang into the lower ground's wedge and their feet
## would cross, drawing a small loop of wall and shadow under the corner (a dark spike, the owner's
## octagon hole, 2026-11-03): the arc's fibres, and those of each run whose foot would pass where the
## two walls' foot lines meet, end there instead, unwobbled (`folded`).
func _meet_feet(border: Border, fibres: PackedVector2Array, folded: PackedFloat32Array, loop: bool) -> void:
	var points := border.points
	for corner: Dictionary in border.corners:
		if bool(corner["convex"]) or bool(corner.get("folded", false)) or bool(corner.get("open", false)):
			continue
		var fibre_a := reach(corner["n_a"], float(corner["drop_a"]))
		var fibre_b := reach(corner["n_b"], float(corner["drop_b"]))
		if fibre_a.length() < 1.0 or fibre_b.length() < 1.0:
			continue
		var vertex: Vector2 = corner["vertex"]
		var e_a: Vector2 = corner["e_a"]
		var e_b: Vector2 = corner["e_b"]
		# vertex + fibre_a + e_a * u = vertex + fibre_b + e_b * v
		var gap := fibre_b - fibre_a
		var det := e_b.x * e_a.y - e_a.x * e_b.y
		if absf(det) < 0.01:
			continue
		var meet := vertex + fibre_a + e_a * ((e_b.x * gap.y - e_b.y * gap.x) / det)
		for k: int in _arc_points(corner, points.size()):
			fibres[k] = meet - points[k]
			folded[k] = 1.0
		for k: int in _run_away(border, corner, true, loop):
			if (points[k] + fibres[k] - meet).dot(e_a) <= 0.0:
				break
			fibres[k] = meet - points[k]
			folded[k] = 1.0
		for k: int in _run_away(border, corner, false, loop):
			if (points[k] + fibres[k] - meet).dot(e_b) >= 0.0:
				break
			fibres[k] = meet - points[k]
			folded[k] = 1.0


## The points of `corner`'s arc, from run a's end to run b's start.
static func _arc_points(corner: Dictionary, count: int) -> Array[int]:
	var out: Array[int] = []
	var first := int(corner["first"])
	var last := int(corner["last"])
	var k := first
	for step in count:
		out.append(k)
		if k == last:
			break
		k = (k + 1) % count
	return out


## The points of the run before `corner` (`first_run`: walking back from its arc) or after it (on from
## its arc), up to the next corner's arc.
static func _run_away(border: Border, corner: Dictionary, first_run: bool, loop: bool) -> Array[int]:
	var count := border.points.size()
	var out: Array[int] = []
	var k := int(corner["first"]) - 1 if first_run else int(corner["last"]) + 1
	for step in count:
		if k < 0 or k >= count:
			if not loop:
				break
			k = posmod(k, count)
		if border.corner[k] >= 0:
			break
		out.append(k)
		k += -1 if first_run else 1
	return out


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
			verts.clear()
			uvs.clear()
			colors.clear()
			for point: Vector2 in [vertex, border.points[i], border.points[i + 1]]:
				verts.append(point)
				uvs.append(Vector2.ZERO)
				colors.append(colour)
			pieces.append([-1e9, verts.duplicate(), uvs.duplicate(), colors.duplicate(), i])


## A chain's shape for collision (`shapes`): its drawn walls as polygons (each run of points with a
## wall, from the smooth border to the foot; the foot simplified to SHAPE_TOLERANCE), the zones
## between each round outer corner and the model's square corner (the vertex and the arc), the level
## below each point, and every edge of the border and the walls, for Elevation to trace. Each test
## and its edges come from the same points, so a piece's two sides are judged by the line drawn.
## A point has a wall where its fibre (`fibres`) reaches out more than WALL_MIN: a back edge has
## none, though its foot lies a little out with the top edge's wobble, so the strip behind a hill
## stays open.
func _add_shape(border: Border, foots: PackedVector2Array, depths: PackedFloat32Array, fibres: PackedVector2Array,
		loop: bool, level: float) -> void:
	var points := border.points
	var count := points.size()
	var walled := PackedByteArray()
	walled.resize(count)
	for k in count:
		walled[k] = 1 if depths[k] > 0.0 and fibres[k].length() > WALL_MIN and points[k].distance_to(foots[k]) > 0.75 else 0
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
		# Not past a terrace's edge where it runs up against a higher wall (`border.over`): the lip there
		# lay over that wall's stones (2026-11-06).
		outer.append(tops[i] + normals[i] * (EDGE_OUT if border.over[i] == NO_OVER else 0.0))
		if i > 0:
			length += points[i - 1].distance_to(points[i])
		along.append(length)
	if loop:
		length += points[count - 1].distance_to(points[0])
	along = _seed_along(points, along, length, loop)
	length = along[count]
	along.resize(count)
	for corner: Dictionary in border.corners:
		_mitre(inner, corner, -EDGE_IN, loop, normals)
		_mitre(outer, corner, EDGE_OUT, loop, normals)
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
		pieces.append([key, verts, uvs, colors, i])


## The foot along the wall's foot line: FOOT_UP up the wall (clumps of the lower ground and a dark line
## over them, its sweep perpendicular to the foot line) and the shadow over the lower ground (`_shadows`).
## UV = (world units along the foot, world units past it: up the wall negative, over the shadow
## 0 … FOOT_OUT at its far edge); colour g = the shadow's strength (stronger facing the lower right).
func _add_foot(pieces: Array, border: Border, foots: PackedVector2Array, depths: PackedFloat32Array, loop: bool, level: float,
		foot_ns: PackedVector2Array = PackedVector2Array(), tops: PackedVector2Array = PackedVector2Array()) -> void:
	var points := border.points
	# The border's normals, or the feet's own (`_open_corners`): a back edge's or a side's foot.
	var normals := foot_ns if foot_ns.size() == border.normals.size() else border.normals
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
	foot_along = _seed_along(points, foot_along, length, loop)
	length = foot_along[count]
	foot_along.resize(count)
	var segments := count if loop else count - 1
	# Each point's shadow: as long as the wall there is tall (none beyond a back corner's slanted end)
	# and longer facing the lower right, stronger facing it. Where it would run under a ramp's slope
	# (drawn over it, so it would end on the slope's edge) it fades out: none at a point whose shadow
	# reaches the slope, half at its neighbours.
	var shadow_scale := PackedFloat32Array()
	shadow_scale.resize(count)
	shadow_scale.fill(1.0)
	_fade_shadow_near_walls(border, shadow_scale)
	var shadow_lengths := PackedFloat32Array()
	var strengths := PackedFloat32Array()
	for k in count:
		var facing := SHADOW_EAST * maxf(0.0, foot_normals[k].x) + SHADOW_SOUTH * maxf(0.0, foot_normals[k].y)
		shadow_lengths.append(FOOT_OUT + SHADOW_PER_LEVEL * depths[k] * facing)
		strengths.append(FOOT_SHADOW + FOOT_SHADOW_EAST * maxf(0.0, foot_normals[k].dot(SHADOW_FROM)))
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
	# Which stretches of the foot are drawn: a back edge has no wall but keeps its foot's shadow on the
	# ground behind.
	var drawn := PackedByteArray()
	drawn.resize(segments)
	for i in segments:
		var j := (i + 1) % count
		var back_edge := backness(normals[i]) > 0.5 and backness(normals[j]) > 0.5
		# Nor where the foot steps between two drops along a wall (a terrace below part of it): that
		# step's shadow fell on the terrace as a dark wedge (2026-11-06).
		var stepped := absf(depths[i] - depths[j]) >= 0.5
		var hidden := has_foot[i] < 0.5 or has_foot[j] < 0.5 or stepped or (depths[i] <= 0.0 and depths[j] <= 0.0 and not back_edge)
		drawn[i] = 0 if hidden else 1
	var shadow_ns := foot_normals.duplicate()
	var runs := _shadow_runs(drawn, foots, loop)
	for run: Dictionary in runs:
		_shape_shadow(run, foots, shadow_ns, shadow_lengths, strengths)
	# How far each point's strip reaches up the wall: where the foot turns tighter than that (a fold's
	# foot corner) the offsets of two neighbours would cross and fold the strip over itself, so both
	# shrink until they do not.
	var ups := PackedFloat32Array()
	ups.resize(count)
	ups.fill(FOOT_UP)
	# None where the foot runs down the wall's own fibres (`tops` to `foots`): that is the wall's end,
	# not its base (a front wall hanging from an octagon's east or west point, whose end edge runs
	# straight down from it), and clumps there would grow sideways into the wall.
	if tops.size() == count:
		for k in count:
			var way := foots[k] - tops[k]
			if way.length() > 0.5:
				var along := absf(Vector2(foot_normals[k].y, -foot_normals[k].x).dot(way.normalized()))
				ups[k] *= 1.0 - smoothstep(0.75, 0.95, along)
	for pass_index in 8:
		var changed := false
		for i in segments:
			var j := (i + 1) % count
			var base := foots[j] - foots[i]
			var o_i := foots[i] - foot_normals[i] * ups[i]
			var o_j := foots[j] - foot_normals[j] * ups[j]
			if base.length() > 0.5 and (o_j - o_i).dot(base) < 0.0:
				ups[i] *= 0.6
				ups[j] *= 0.6
				changed = true
		if not changed:
			break
	var colours := PackedColorArray()
	var shadow_colours := PackedColorArray()
	for k in count:
		var water := border.water[k] > 0.5
		var colour := Color(KIND_FOOT_WATER if water else KIND_FOOT_ART, strengths[k] * shadow_scale[k], backness(normals[k]),
				_level_channel(level - border.drop[k]))
		colours.append(colour)
		colour.r = KIND_FOOT_WATER if water else KIND_FOOT_SHADOW
		shadow_colours.append(colour)
	# The strip up the wall, per stretch of foot.
	for i in segments:
		var j := (i + 1) % count
		if drawn[i] == 0 or foots[i].distance_to(foots[j]) < 0.25:
			continue
		var u_j := foot_along[j] if j > 0 else length
		var verts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		# A dry foot's art reaches FOOT_DOWN over the ground too; in water the water is the foot's.
		var down_i := 0.0 if border.water[i] > 0.5 else FOOT_DOWN
		var down_j := 0.0 if border.water[j] > 0.5 else FOOT_DOWN
		var ring := [[i, foots[i] - foot_normals[i] * ups[i], -ups[i], foot_along[i]], [i, foots[i], 0.0, foot_along[i]],
				[j, foots[j] - foot_normals[j] * ups[j], -ups[j], u_j], [j, foots[j], 0.0, u_j],
				[i, foots[i] + foot_normals[i] * down_i, down_i, foot_along[i]], [j, foots[j] + foot_normals[j] * down_j, down_j, u_j]]
		for index: int in [0, 2, 3, 0, 3, 1, 1, 3, 5, 1, 5, 4]:
			var corner: Array = ring[index]
			verts.append(corner[1])
			uvs.append(Vector2(float(corner[3]), float(corner[2])))
			colors.append(colours[int(corner[0])])
		pieces.append([(points[i].y + points[j].y) * 0.5 + FOOT_LEAD, verts, uvs, colors, i])
	# The shadow: one ring per run, from the foot to its far edge.
	for run: Dictionary in runs:
		var run_points: Array[int] = run["points"]
		var n := run_points.size()
		for m in (n if bool(run["closed"]) else n - 1):
			var i := run_points[m]
			var j := run_points[(m + 1) % n]
			var far_i := foots[i] + shadow_ns[i] * shadow_lengths[i]
			var far_j := foots[j] + shadow_ns[j] * shadow_lengths[j]
			if foots[i].distance_to(foots[j]) < 0.25 and far_i.distance_to(far_j) < 0.25:
				continue
			var u_i := foot_along[i]
			var u_j := foot_along[j] if j > 0 else length
			var verts := PackedVector2Array()
			var uvs := PackedVector2Array()
			var colors := PackedColorArray()
			# Past the foot the art's rows run over the shadow's whole length (FOOT_OUT of them).
			var ring := [[i, foots[i], Vector2(u_i, 0.0)], [j, foots[j], Vector2(u_j, 0.0)],
					[j, far_j, Vector2(u_j, FOOT_OUT)], [i, far_i, Vector2(u_i, FOOT_OUT)]]
			for index: int in [0, 1, 2, 0, 2, 3]:
				var corner: Array = ring[index]
				verts.append(corner[1])
				uvs.append(corner[2])
				colors.append(shadow_colours[int(corner[0])])
			pieces.append([(points[i].y + points[j].y) * 0.5 + FOOT_LEAD, verts, uvs, colors, i])


## The runs of the foot whose shadow is drawn (`drawn`, per stretch between two points): {points (their
## indices along the foot), closed (round a whole loop)}. Two runs whose ends lie within SHADOW_JOIN
## of each other are one: at a corner `_open_corners` meets, the strip's foot and the front wall's
## start where the two feet meet, the stretch between them hidden behind the strip.
static func _shadow_runs(drawn: PackedByteArray, foots: PackedVector2Array, loop: bool) -> Array[Dictionary]:
	var segments := drawn.size()
	var count := foots.size()
	var runs: Array[Dictionary] = []
	# A loop is walked from after a stretch that is not drawn (if any), so no run wraps round.
	var start := 0
	if loop:
		start = -1
		for i in segments:
			if drawn[i] == 0:
				start = (i + 1) % segments
				break
		if start < 0:
			var every: Array[int] = []
			for k in count:
				every.append(k)
			runs.append({"points": every, "closed": true})
			return runs
	var current: Array[int] = []
	for step in segments:
		var i := (start + step) % segments
		if drawn[i] == 1:
			if current.is_empty():
				current.append(i)
			current.append((i + 1) % count)
		elif not current.is_empty():
			runs.append({"points": current, "closed": false})
			current = []
	if not current.is_empty():
		runs.append({"points": current, "closed": false})
	var joined: Array[Dictionary] = []
	for run in runs:
		if not joined.is_empty():
			var last: Array[int] = joined[joined.size() - 1]["points"]
			var next: Array[int] = run["points"]
			if foots[last[last.size() - 1]].distance_to(foots[next[0]]) < SHADOW_JOIN:
				last.append_array(next)
				continue
		joined.append(run)
	if loop and not joined.is_empty():
		var first: Array[int] = joined[0]["points"]
		var last: Array[int] = joined[joined.size() - 1]["points"]
		if foots[last[last.size() - 1]].distance_to(foots[first[0]]) < SHADOW_JOIN:
			if joined.size() == 1:
				# one run round the whole loop, its ends meeting (a hole's last open corner)
				joined[0]["closed"] = true
			else:
				last.append_array(first)
				joined.remove_at(0)
	return joined


## One run's shadow (`_shadow_runs`), shaped so it is drawn once everywhere: its lengths and strengths
## averaged along the foot over SHADOW_SMOOTH either way (two walls meeting at an inner corner cast
## shadows of one length and strength there, so they join without a seam), then, wherever two
## neighbouring fibres of it (foot → far edge) would cross (round an inner corner, where the foot turns
## in tighter than the shadow is long), their ways turned towards each other, and on, until none do
## (at most SHADOW_RELAX passes). Translucent, a shadow drawn twice would darken; until 2026-11-03 the
## two walls' shadows overlapped there and were cut on hard lines.
static func _shape_shadow(run: Dictionary, foots: PackedVector2Array, ways: PackedVector2Array,
		lengths: PackedFloat32Array, strengths: PackedFloat32Array) -> void:
	var run_points: Array[int] = run["points"]
	var closed := bool(run["closed"])
	var n := run_points.size()
	if n < 2:
		return
	var at := PackedFloat32Array()
	var total := 0.0
	for m in n:
		if m > 0:
			total += foots[run_points[m - 1]].distance_to(foots[run_points[m]])
		at.append(total)
	if closed:
		total += foots[run_points[n - 1]].distance_to(foots[run_points[0]])
	var smooth_lengths := PackedFloat32Array()
	var smooth_strengths := PackedFloat32Array()
	for m in n:
		var weight_sum := 0.0
		var length_sum := 0.0
		var strength_sum := 0.0
		for way: int in [-1, 1]:
			for step in n:
				if way > 0 and step == 0:
					continue
				var o := m + way * step
				if not closed and (o < 0 or o >= n):
					break
				var gap := absf(at[posmod(o, n)] - at[m] + (total if o >= n else (-total if o < 0 else 0.0)))
				if gap >= SHADOW_SMOOTH or step >= n - 1:
					break
				var weight := 1.0 - gap / SHADOW_SMOOTH
				weight_sum += weight
				length_sum += lengths[run_points[posmod(o, n)]] * weight
				strength_sum += strengths[run_points[posmod(o, n)]] * weight
		smooth_lengths.append(length_sum / weight_sum)
		smooth_strengths.append(strength_sum / weight_sum)
	for m in n:
		lengths[run_points[m]] = smooth_lengths[m]
		strengths[run_points[m]] = smooth_strengths[m]
	var pairs := n if closed else n - 1
	var active: Array[int] = []
	for m in pairs:
		active.append(m)
	for pass_index in SHADOW_RELAX:
		if active.is_empty():
			break
		var next := {}
		for m: int in active:
			var a := run_points[m]
			var b := run_points[(m + 1) % n]
			var step := foots[b] - foots[a]
			var far_a := foots[a] + ways[a] * lengths[a] - foots[a]
			var far_b := foots[b] + ways[b] * lengths[b] - foots[a]
			# The two triangles of the piece between the fibres both turn the shadow's way.
			if step.cross(far_b) >= -0.01 and far_b.cross(far_a) >= -0.01:
				continue
			var target := ways[a] + ways[b]
			if step.length() > 0.01 and step.cross(far_b) < -0.01:
				# the foot steps against the shadow's way (a sharp inner corner): turn to its side
				target += Vector2(-step.y, step.x).normalized() * 2.0
			if target.length() < 1e-4:
				continue
			target = target.normalized()
			ways[a] = ways[a].lerp(target, 0.5).normalized()
			ways[b] = ways[b].lerp(target, 0.5).normalized()
			for near: int in [m - 1, m, m + 1]:
				if near >= 0 and near < pairs:
					next[near] = true
				elif closed:
					next[posmod(near, pairs)] = true
		active.clear()
		for m: int in next:
			active.append(m)


## Where an offset of the border by `distance` (along the outward normal; negative inwards) would
## fold over itself around `corner` (an outer corner offset inwards, an inner one outwards, further
## than its radius), its points meet in the mitre of the two runs' offsets instead. Only the two runs
## that meet there are pulled in (`normals`: a point whose normal is no longer its run's ends the
## walk): past them the test of passing the mitre held again round a narrow U and pulled a far
## edge's whole band onto this corner's mitre, a fan of the top edge across the U (desert-b8,
## 2026-11-07, since the band over the top grew to EDGE_IN 36).
func _mitre(offsets: PackedVector2Array, corner: Dictionary, distance: float, loop: bool,
		normals: PackedVector2Array = PackedVector2Array()) -> void:
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
		if (offsets[k] - mitre).dot(e_a) <= 0.0 or not _on_run(normals, k, n_a):
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
		if (offsets[k] - mitre).dot(e_b) >= 0.0 or not _on_run(normals, k, n_b):
			break
		offsets[k] = mitre
		k += 1
		steps += 1


## True when point `k` still lies on the straight run of normal `n` (`_mitre`; always without normals).
static func _on_run(normals: PackedVector2Array, k: int, n: Vector2) -> bool:
	return normals.is_empty() or normals[k].dot(n) > MITRE_RUN_DOT


## The stretch of u along a loop `length` units long so it closes on whole periods of art `width`
## px wide (2 px per unit); 1 along a line or without art.
static func _period_scale(length: float, width: float, loop: bool) -> float:
	if not loop or width <= 0.0 or length <= 0.0:
		return 1.0
	var periods := maxf(1.0, roundf(length * 2.0 / width))
	return periods * width / (length * 2.0)


## Where a chain's top edge and foot start measuring u (world units, EDGE_SEEDS steps), by where the
## chain's first point lies.
static func _edge_seed(point: Vector2) -> float:
	return float(posmod(int(floor(point.x / 8.0)) * 7919 + int(floor(point.y / 8.0)) * 104729, EDGE_SEEDS)) * EDGE_SEED_STEP


## A top edge's or a foot's u (world units) at each of a chain's points (`along`: the edge's length
## there; `total`: a loop's whole length), then at `total`: pinned to the chunk lines it crosses
## (`_anchored_u`), else `along` from the chain's own start (`_edge_seed`).
func _seed_along(points: PackedVector2Array, along: PackedFloat32Array, total: float, loop: bool) -> PackedFloat32Array:
	var pinned := _anchored_u(points, along, total, loop, 1.0, 1.0)
	if not pinned.is_empty():
		return pinned
	var seed := _edge_seed(points[0] + origin)
	var out := PackedFloat32Array()
	for value in along:
		out.append(value + seed)
	out.append(total + seed)
	return out


## u at each point of a chain (`along`: its length there in the measure the caller's art runs by;
## `total`: a loop's whole length), then at `total`, where its border (`points`) crosses a chunk line
## (`chunk_lines`); empty where it crosses none, so the caller keeps its own u. u grows `rate` a unit
## of `along`. At a crossing it is the line's own value: `unit` times its overworld coordinate, signed
## by the way the chain crosses it, plus REGION_SPAN to stay positive. The chunks on both sides work
## out the same value there, so the art meets across the line. Between a crossing into the chunk's
## own cells and the next one out the art stretches to meet both when that keeps it within
## STRETCH_MIN … STRETCH_MAX, else it runs on from the first (its art then jumps at the second line,
## seen only while the screen scrolls across). Outside the chunk's own cells it runs back from the
## next crossing, so the jump there lies on the side of the line the game never shows.
func _anchored_u(points: PackedVector2Array, along: PackedFloat32Array, total: float, loop: bool, rate: float,
		unit: float) -> PackedFloat32Array:
	if chunk_lines.is_empty():
		return PackedFloat32Array()
	var count := points.size()
	var segments := count if loop else count - 1
	# (length along the chain, the line's value, 1 when the chain goes into the chunk's own cells there)
	var crossings: Array[Vector3] = []
	for i in segments:
		var j := (i + 1) % count
		var p := points[i]
		var q := points[j]
		var a_i := along[i]
		var a_j := along[j] if j > 0 else total
		var found: Array[Vector3] = []
		for line: Vector2 in chunk_lines:
			var axis := int(line.x)
			var a := p[axis] - line.y
			var b := q[axis] - line.y
			if (a < 0.0) == (b < 0.0):
				continue
			var t := a / (a - b)
			var heading := 1.0 if b > a else -1.0
			var past := p.lerp(q, t) + (q - p).normalized() * 0.5
			var value := unit * (heading * (origin[axis] + line.y) + REGION_SPAN)
			found.append(Vector3(lerpf(a_i, a_j, t), value, 1.0 if own_rect.has_point(past) else 0.0))
		found.sort_custom(func(first: Vector3, second: Vector3) -> bool: return first.x < second.x)
		crossings.append_array(found)
	if crossings.is_empty():
		return PackedFloat32Array()
	var n := crossings.size()
	# Per stretch from crossing k to the next (round a loop, the last one on to the first): [u at k,
	# u a unit of `along`].
	var spans: Array[Vector2] = []
	for k in n:
		var here := crossings[k]
		if k + 1 >= n and not loop:
			spans.append(Vector2(here.y, rate))
			break
		var next := crossings[(k + 1) % n]
		var length := next.x - here.x + (total if k + 1 >= n else 0.0)
		if here.z < 0.5:
			# Outside the chunk's own cells: run back from the next line.
			spans.append(Vector2(next.y - rate * length, rate))
			continue
		var stretch := (next.y - here.y) / (rate * length) if length > 1e-3 else 0.0
		if stretch >= STRETCH_MIN and stretch <= STRETCH_MAX:
			spans.append(Vector2(here.y, rate * stretch))
		else:
			spans.append(Vector2(here.y, rate))
	var out := PackedFloat32Array()
	for k in count + 1:
		var at := along[k] if k < count else total
		# The stretch `at` lies in: before the first crossing, a loop's last one (a lap on) or a line's
		# run back from the first.
		var index := -1
		for m in n:
			if crossings[m].x <= at:
				index = m
		if index < 0:
			if loop:
				index = n - 1
				at += total
			else:
				out.append(crossings[0].y - rate * (crossings[0].x - at))
				continue
		out.append(spans[index].x + spans[index].y * (at - crossings[index].x))
	return out


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
