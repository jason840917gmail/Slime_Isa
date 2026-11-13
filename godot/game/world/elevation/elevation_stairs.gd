@tool
extends RefCounted
## One flight of stairs (docs/godot/ELEVATION.md "Stairs"), in one simple style after the stairs of
## A Link to the Past (owner, 2026-10-11): stone steps between two side posts of stone blocks, all
## of it in the colour of the road or ground the flight leads to (Elevation picks it: `ground_name`).
## A flight leaves a rim in one of 8 directions:
##   front flights (S, SW, SE) are set into the cliff's face, from its top edge down to its foot and
##     no further: the steps and their posts lie flat on the face (in 3D a vertical surface, as the
##     wall is), the steps drawn on it as bands of risers and treads (elevation_stairs.gdshader);
##   side and back flights (E, W, N, NE, NW), whose faces the camera does not see, run out over the
##     lower ground from the rim (a cell per level; north 1.5 cells, foreshortened), from the top
##     level at the rim (no landing) down onto the lower ground, 4 steps per level, between two low
##     side walls of blocks.
##
## Built in 3D in the flight's frame: s along its direction D (down the stairs, 0 on the rim), t
## across it (T = D turned 90°), h up from the lower ground. A point at ground (x, y) and absolute
## height H (64 per level) is drawn at (x, y − H), and its depth is its ground y
## (elevation_occlusion.gdshaderinc). Elevation uses:
##   `walk`        the walkable surface on screen (the face between the posts; the steps' nosing line
##                 between the side walls), walkable by every level from `bottom` to `top`; a body
##                 there takes the level of the height it stands at (`level_at`) and its depth
##                 (`depth_at`);
##   `blockers`    what of the structure stands at a level's height, drawn at that height (a body of
##                 that level is blocked there: `blocks`): the posts beside the steps, the side walls
##                 along them; what is drawn above it only hides it (the depth map);
##   `silhouette`  the whole structure as drawn, and `approach` the top's ground just behind the rim
##                 (`occupies`; Elevation draws the top's own ground over its edge there,
##                 `add_approach`, so the edge breaks for the way down);
##   faces         drawn (`add_mesh`) and written to the depth map (`add_depth`) back to front.
## Godot draws in order, without a depth test, so what of a flight lies behind the ground it leaves
## (`occlude`: a back flight's foot and the first steps behind the rim, under the hill's top) is cut
## out of its faces, its depth and its silhouette; and what of a side flight lies behind the cliff's
## side wall it comes out of (`cut_into`: the rock beside its near side, where the hill runs on past
## it) is cut out of its faces and its depth, so the wall drawn under it shows there (owner,
## 2026-11-06: the stairs should come "from inside the wall", not be painted on top of it).
## Coordinates are Elevation's (world units from the ground layer's origin).
##
## Owner: world (elevation).

const Self := preload("res://game/world/elevation/elevation_stairs.gd")
const LevelCode := preload("res://game/world/elevation/level_code.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const ElevationOcclusion := preload("res://game/world/elevation/elevation_occlusion.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")

const LEVEL := 64.0
const STEPS_PER_LEVEL := 4
const RISE := LEVEL / STEPS_PER_LEVEL
## Half the walkable width of a one-cell flight; a flight is `cells` cells wide.
const HALF_CELL := 32.0
## The posts (front flights) and side walls (the others) outside the walkable width: how wide, and
## how far a side wall stands above the steps.
const POST := 14.0
const POST_UP := 8.0
## The stone blocks the posts and side walls are laid in (world units, both ways).
const BLOCK := 16.0
## The top's ground just behind the rim (`approach`): how deep into the top, and how far it fades
## out beside the flight.
const APPROACH := 52.0
const APPROACH_FADE := 14.0
## How far into the top (s) and, for a side or back flight, past its bottom end its way stays
## walkable by every level it joins (`overhang`): a body's feet are on the steps, but its body may
## reach over their ends before it takes the next level (over a 45° rim, over the short end of a
## foreshortened back flight).
const REACH := 32.0
const BEYOND := 48.0
const SQRT2 := 1.4142135623730951
## Direction -> [D on the ground, run per level (world units)]. Front flights (D.y > 0) are set into
## the face and have no run. Back flights are foreshortened: a 45° one runs one diagonal cell per
## level, a north one 1.5 cells (at one it would be seen edge-on).
const DIRECTIONS := {
	"s": [Vector2(0, 1), 64.0], "n": [Vector2(0, -1), 96.0],
	"e": [Vector2(1, 0), 64.0], "w": [Vector2(-1, 0), 64.0],
	"se": [Vector2(1, 1), 64.0 * SQRT2], "sw": [Vector2(-1, 1), 64.0 * SQRT2],
	"ne": [Vector2(1, -1), 64.0 * SQRT2], "nw": [Vector2(-1, -1), 64.0 * SQRT2],
}
## Face kinds: the stairs shader picks the texture from UV.y (KIND_OFFSET per kind).
const KIND_STEPS := 0
const KIND_TREAD := 1
const KIND_RISER := 2
const KIND_BLOCK := 3
const KIND_POST := 4
const KIND_CAP := 5
const KIND_PIECE := 7
const KIND_OFFSET := 4096.0
## A front flight is painted whole (owner 2026-11-06: "paint the whole stair at once", after
## Front A): its steps, the notch they are set into and the rock framing it, one piece per height
## (FRONT_PIECES: levels -> the kit part, its aspect, where its steps run across it, from its left;
## a flight of more levels takes the tallest), drawn over the wall in the face's plane in three
## slices (`_piece_quads`): the two frames at the piece's own proportions, the steps between them
## stretched across the flight, PIECE_INTO inside its walkable edges; from where its steps begin
## ("top") at the top edge to PIECE_SINK below the foot, the whole piece lifted by what lies above
## that row (world units).
const FRONT_PIECES := {
	1: {"part": "front_1", "aspect": 3.314, "steps": Vector2(0.2241, 0.7759)},
	2: {"part": "front_2", "aspect": 1.731, "steps": Vector2(0.2241, 0.7759)},
}
## A 45° front flight (south-west, south-east) takes its own piece, painted on its slanted face for
## the south-west (a south-east flight draws it mirrored, PIECE_AWAY_LIGHT as dark: that face turns
## from the light).
const DIAG_PIECES := {
	1: {"part": "diag_1", "aspect": 2.132, "steps": Vector2(0.3484, 0.6516)},
	2: {"part": "diag_2", "aspect": 1.114, "steps": Vector2(0.3484, 0.6516)},
}
const PIECE_AWAY_LIGHT := 0.74
const PIECE_INTO := 0.0
## The top's ground drawn down the face to a front flight's top step reaches this far under it, so no
## hairline of the ledge shows between them (world units).
const LEDGE_COVER := 2.0
const PIECE_SINK := 6.0
## A side flight (east or west) is painted whole too (owner 2026-11-06, after West C): (levels, cells)
## -> the kit part, painted westward (an eastward flight draws it mirrored), over the flight's box
## (`_side_piece`); a size without one keeps the kit's faces.
const SIDE_PIECES := {Vector2i(1, 1): "side_1_1", Vector2i(1, 2): "side_1_2", Vector2i(2, 1): "side_2_1"}
## The painted pieces' order (vertex colour b = (index + 0.5) / 8; the shader picks the texture).
const PIECE_ORDER: PackedStringArray = ["front_1", "front_2", "side_2_1", "side_1_1", "side_1_2", "diag_1", "diag_2"]
## Texture px per world unit (the stairs kit).
const PX := 3.0
## Block rows count down from this height (world units), so every flight's rows line up.
const BLOCK_ROWS_FROM := LEVEL * 8.0
## Face light: tops 1, faces by the way they look, S 0.86 ± 0.20.
const SHADE_SOUTH := 0.86
const SHADE_SPREAD := 0.20
## Contact shadows and highlights of a side or back flight's steps: a tread darkens towards the
## riser above it and lights up on its nosing, every face darkens a little along the side walls, a
## riser under its nosing, a side wall's inner face where it meets the steps.
const TREAD_AO := 0.78
const TREAD_AO_REACH := 0.35
const NOSING_LIGHT := 1.08
const NOSING := 3.0
const TREAD_EDGE := 0.62
const TREAD_EDGE_REACH := 9.0
const RISER_AO := 0.62
const RISER_AO_REACH := 0.4
const RISER_EDGE := 0.75
const RISER_EDGE_REACH := 7.0
const WALL_CONTACT := 0.7
const WALL_CONTACT_REACH := 10.0
## A part of the flight this much below its top level is hidden by higher ground drawn over it.
const OCCLUDE_MARGIN := 2.0
## The hill's side past a side flight's near side (`cut_into`): probed this far either side of the
## rim, every ROCK_STEP down it; where it ends, the side wall turns round the top's rounded corner
## (ElevationSides RADIUS_OUTER) about ROCK_ROUND before, and a shorter run than ROCK_MIN hides
## nothing (a hole's side ending at its back edge narrows there) (world units).
const ROCK_PROBE := 6.0
const ROCK_STEP := 4.0
const ROCK_ROUND := 20.0
const ROCK_MIN := 16.0
## The painted kit (scripts/art/build-stairs-kit.py; owner 2026-11-06, the concepts Front A and
## West C): uniform -> texture, and each texture's mean colour (the script prints them).
const SHADER := preload("res://game/world/elevation/elevation_stairs.gdshader")
## The kit of back flights and of sizes without a piece (one for every set, recoloured), and its
## textures' mean colours; the painted pieces come from the art sets (SETS: elevation_stairs_sets.gd,
## generated by build-stairs-kit.py; owner 2026-11-06: stairs art to match the other grounds), a
## flight taking the set of the wall style it is cut into (`art_set`).
const KIT := {
	"tread": "res://asset/MAPS/elevation/stairs-tread.png",
	"block": "res://asset/MAPS/elevation/stairs-blocks.png",
}
const KIT_MEANS := {
	"tread": Color(0.761, 0.452, 0.221),
	"block": Color(0.726, 0.399, 0.197),
}
const Sets := preload("res://game/world/elevation/elevation_stairs_sets.gd")
const DEFAULT_SET := "desert"
## A flight is cut from the rock of the wall it leaves (`stone`, set by Elevation): each wall
## style's mean colour (its <style>-wall.png, build-stairs-kit.py prints them), made the colour of
## worn slabs: saturation times STONE_SATURATION, value times STONE_VALUE.x, at least STONE_VALUE.y.
const STONE_COLOURS := {
	"autumn-face": Color(0.558, 0.280, 0.082),
	"castle-face": Color(0.687, 0.576, 0.378),
	"cave-face": Color(0.188, 0.238, 0.276),
	"cave-rock": Color(0.313, 0.272, 0.236),
	"crystal-face": Color(0.083, 0.145, 0.305),
	"crystal-rock": Color(0.297, 0.264, 0.348),
	"desert-dirt": Color(0.743, 0.405, 0.178),
	"desert-face": Color(0.688, 0.375, 0.110),
	"desert-strata": Color(0.768, 0.434, 0.155),
	"dungeon-face": Color(0.212, 0.222, 0.195),
	"forest-face": Color(0.275, 0.222, 0.059),
	"ice-dirt": Color(0.447, 0.356, 0.306),
	"masonry": Color(0.685, 0.567, 0.412),
	"meadow-face": Color(0.537, 0.338, 0.072),
	"meadow-rock": Color(0.530, 0.439, 0.304),
	"mossy-rock": Color(0.485, 0.433, 0.169),
	"mountain-dirt": Color(0.354, 0.194, 0.082),
	"red-rock": Color(0.626, 0.266, 0.146),
	"root-rock": Color(0.416, 0.278, 0.138),
	"sandstone": Color(0.737, 0.480, 0.248),
	"snow-face": Color(0.438, 0.716, 0.782),
	"snow-rock": Color(0.558, 0.531, 0.543),
	"storybook-rock": Color(0.440, 0.328, 0.207),
	"town-face": Color(0.557, 0.446, 0.152),
	"volcanic-face": Color(0.243, 0.187, 0.147),
}
const STONE_SATURATION := 0.95
const STONE_VALUE := Vector2(1.08, 0.42)

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
## A front flight: set into the face, no run.
var in_face := false
## The ground at its ends (set by Elevation: its colour when the flight has no `stone`), and the
## top's ground behind its rim.
var ground_name := ""
var top_ground := ""
## The wall style of the cliff it is cut into (set by Elevation; STONE_COLOURS), "" for none.
var stone := ""
var steps := 4
## Depth of a step, s where the nosing reaches the lower ground, where the flight ends (0 for a
## front flight).
var run := LEVEL / STEPS_PER_LEVEL
var ramp := LEVEL
var end := LEVEL
var walk := PackedVector2Array()
var approach := PackedVector2Array()
## The way past its ends (`overhang`): into the top, past the bottom end (side and back flights).
var reach := PackedVector2Array()
var beyond := PackedVector2Array()
var silhouette: Array[PackedVector2Array] = []
var bounds := Rect2()
## Faces back to front: {kind, quad: [p00, p10, p11, p01] (s, t, h), normal (x, y, h), shade,
## and per kind the texture mapping}.
var faces: Array[Dictionary] = []
## Screen polygons of the higher ground in front of the flight (`occlude`), and their rects.
var occluders: Array[PackedVector2Array] = []
var _occluder_rects: Array[Rect2] = []
## Screen polygons of the cliff's rock in front of the flight (`cut_into`), and their rects.
var rock_cuts: Array[PackedVector2Array] = []
var _rock_rects: Array[Rect2] = []
## The structure's convex pieces on screen: [polygon, may hide behind the ground (not on the top)].
var _hulls: Array = []
## The structure's solids in the flight's frame: [s from, s to, t from, t to, floor at s from, floor at
## s to, top at s from, top at s to] (h above the lower ground, linear along s).
var _solids: Array = []
## Per level: the blockers, and the collision's edges cut where they cross.
var _blockers: Dictionary = {}
var _pieces: Dictionary = {}
var _seed := 0


## A flight leaving the rim at `rim_point` (screen, top level) towards `direction_key` (DIRECTIONS)
## from level `top_level` down to `bottom_level`, `cells` cells wide.
static func create(direction_key: String, rim_point: Vector2, top_level: int, bottom_level: int, cells: int) -> Self:
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
	flight.in_face = flight.dir.y > 0.1
	var levels := maxi(1, top_level - bottom_level)
	flight.steps = levels * STEPS_PER_LEVEL
	flight.run = 0.0 if flight.in_face else float(entry[1]) * levels / flight.steps
	flight.ramp = flight.steps * flight.run
	flight.end = flight.ramp
	flight._seed = int(rim_point.x * 7.0 + rim_point.y * 13.0)
	flight._build()
	return flight


## The flights' material (the stairs shader with the painted kit) in `tint`; null without the kit.
static func make_material(tint: Color, style: String = "") -> ShaderMaterial:
	var material_of := ShaderMaterial.new()
	material_of.shader = SHADER
	var art: Dictionary = Sets.SETS[art_set(style)]
	var parts := {}
	for part: String in KIT:
		parts[part] = [KIT[part], KIT_MEANS[part]]
	parts.merge(art["parts"] as Dictionary)
	for part: String in parts:
		var path := str(parts[part][0])
		if not ResourceLoader.exists(path):
			push_warning("ElevationStairs: no stairs art '%s'" % path)
			return null
		var texture := load(path) as Texture2D
		material_of.set_shader_parameter(StringName(part + "_texture"), texture)
		material_of.set_shader_parameter(StringName(part + "_size"), Vector2(texture.get_size()))
		var mean: Color = parts[part][1]
		material_of.set_shader_parameter(StringName(part + "_mean"), Vector3(mean.r, mean.g, mean.b))
	material_of.set_shader_parameter(&"px_per_unit", PX)
	material_of.set_shader_parameter(&"block_units", BLOCK)
	material_of.set_shader_parameter(&"tint", tint)
	# The style a set is painted for draws its pieces as painted; the set's other styles recolour them.
	material_of.set_shader_parameter(&"as_painted", 1.0 if style != "" and str(art["home"]) == style else 0.0)
	return material_of


## The art set of flights cut into walls of `style` (any other: DEFAULT_SET).
static func art_set(style: String) -> String:
	var name := str(Sets.STYLE_SETS.get(style, DEFAULT_SET))
	return name if Sets.SETS.has(name) else DEFAULT_SET


## The colour of the flights cut into walls of `style` (STONE_COLOURS), transparent for a style
## without one.
static func stone_tint(style: String) -> Color:
	if not STONE_COLOURS.has(style):
		return Color(0.0, 0.0, 0.0, 0.0)
	var wall: Color = STONE_COLOURS[style]
	return Color.from_hsv(wall.h, wall.s * STONE_SATURATION, clampf(maxf(wall.v * STONE_VALUE.x, STONE_VALUE.y), 0.0, 1.0))


## Levels of the flight's two ends.
func joins(level: int) -> bool:
	return level >= bottom and level <= top


## Height of the steps' nosing line above the lower ground at `s` (a front flight: the top).
func nosing(s: float) -> float:
	var height := LEVEL * (top - bottom)
	if ramp <= 0.0:
		return height
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


## True when a body of `level` can stand at `point` (screen): on the steps of a flight that joins
## its level.
func walks_level(point: Vector2, level: int) -> bool:
	return joins(level) and walks(point)


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


## A side flight (east or west) comes out of the side wall of the hill it leaves: a slanted face from
## the rim at the top level down to its foot `wall` out along the flight (ElevationSides.reach: the
## side strip's width, 39 units for two levels), the hill's rock behind it. That rock stands between
## the camera and every part of the flight seen through the triangle the face cuts out of the near
## side's plane: from the rim's top down the face to its foot, back up the rim (the camera looks down
## at 45° from the south: a ray from any part of the flight drawn there rises through the rock before
## it leaves it). The faces and the depth are drawn without it (`rock_cuts`, `_emit`), so the side
## wall drawn under the flight shows through: only as far down the screen as the hill's straight
## side runs on past the flight's near side (`on_top`: true for a screen point on a top of the
## flight's level or higher; less ROCK_ROUND, where the wall turns round the top's corner), since the
## side wall is drawn only along it. Front flights (set into the face) and back flights (behind the
## top: `occlude`) are left as they are.
func cut_into(wall: Vector2, on_top: Callable) -> void:
	rock_cuts.clear()
	_rock_rects.clear()
	var out := minf(absf(wall.x), end)
	if in_face or absf(dir.y) > 1e-6 or out < 1.0:
		return
	var height := LEVEL * (top - bottom)
	var near_side := 1.0 if across.y > 0.0 else -1.0
	var t_near := near_side * (half + POST)
	# How far the straight side runs on past the near side (screen units at the top level).
	var run_on := -1.0
	var k := 0.0
	while k <= height:
		var along := across * (t_near + near_side * k)
		if not bool(on_top.call(rim - dir * ROCK_PROBE + along)) or bool(on_top.call(rim + dir * ROCK_PROBE + along)):
			break
		run_on = k
		k += ROCK_STEP
	run_on = minf(run_on, height) - (ROCK_ROUND if run_on < height else 0.0)
	if run_on < ROCK_MIN:
		return
	var triangle := PackedVector2Array([screen_of(Vector3(0.0, t_near, height)), screen_of(Vector3(out, t_near, 0.0)),
			screen_of(Vector3(0.0, t_near, 0.0))])
	var reach_y := triangle[0].y + run_on
	var far := 1.0e5
	for cover: PackedVector2Array in Geometry2D.intersect_polygons(triangle, PackedVector2Array([Vector2(-far, -far),
			Vector2(far, -far), Vector2(far, reach_y), Vector2(-far, reach_y)])):
		if cover.size() < 3 or absf(_area(cover)) < 1.0:
			continue
		rock_cuts.append(cover)
		var rect := Rect2(cover[0], Vector2.ZERO)
		for point in cover:
			rect = rect.expand(point)
		_rock_rects.append(rect)


## Every edge `level`'s collision may run along: the walkable surface's border, the blockers', and
## for a level it joins the way past its ends.
func outline_edges(level: int) -> Array:
	var edges: Array = []
	var polygons: Array[PackedVector2Array] = [walk]
	polygons.append_array(blockers(level))
	if joins(level):
		for polygon: PackedVector2Array in [reach, beyond]:
			if polygon.size() >= 3:
				polygons.append(polygon)
	for polygon in polygons:
		for i in polygon.size():
			edges.append([polygon[i], polygon[(i + 1) % polygon.size()]])
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


## What of the structure stands at `level`'s height, drawn at that height (screen quads): a front
## flight's posts (for every level it joins: a body on the steps stands beside them), else each
## solid's cross-section there and the side walls along the nosing line. A body of that level
## walking on its ground meets these; the parts above it only hide it.
func blockers(level: int) -> Array[PackedVector2Array]:
	if _blockers.has(level):
		return _blockers[level]
	var quads: Array[PackedVector2Array] = []
	if in_face:
		if joins(level):
			for side: float in [-1.0, 1.0]:
				quads.append(_post_quad(side))
		_blockers[level] = quads
		return quads
	var h := LEVEL * (level - bottom)
	for solid: Array in _solids:
		var span := _span_at(solid, h)
		if span.y - span.x < 0.01:
			continue
		var t0 := float(solid[2])
		var t1 := float(solid[3])
		quads.append(PackedVector2Array([screen_of(Vector3(span.x, t0, h)), screen_of(Vector3(span.y, t0, h)),
				screen_of(Vector3(span.y, t1, h)), screen_of(Vector3(span.x, t1, h))]))
	# A body on the steps stands at their height, not its level's: the side walls along the nosing
	# line hold it there, at every level the flight joins.
	if joins(level):
		for side: float in [-1.0, 1.0]:
			quads.append(PackedVector2Array([screen_of(Vector3(0.0, side * half, nosing(0.0))), screen_of(Vector3(end, side * half, nosing(end))),
					screen_of(Vector3(end, side * (half + POST), nosing(end))), screen_of(Vector3(0.0, side * (half + POST), nosing(0.0)))]))
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


## Where `point` (screen) lies on the way past the flight's ends, which a body of a level it joins
## may stand on (where the ground there is walkable: Elevation `_stairs_rule`) without taking that
## end's level: 1 into the top (REACH), 2 past the bottom end (BEYOND), 0 neither.
func overhang(point: Vector2) -> int:
	if not bounds.has_point(point):
		return 0
	if reach.size() >= 3 and Geometry2D.is_point_in_polygon(point, reach):
		return 1
	if beyond.size() >= 3 and Geometry2D.is_point_in_polygon(point, beyond):
		return 2
	return 0


## True when `point` (screen) lies on the structure (walkable or not) or on the top's ground just
## behind its rim.
func occupies(point: Vector2) -> bool:
	if not bounds.has_point(point):
		return false
	if Geometry2D.is_point_in_polygon(point, walk):
		return true
	if approach.size() >= 3 and Geometry2D.is_point_in_polygon(point, approach):
		return true
	for shape in silhouette:
		if Geometry2D.is_point_in_polygon(point, shape):
			return true
	return false


## s along the flight of the walkable surface's point drawn at `point`, NAN off it (a front flight:
## 0 on it).
func s_at(point: Vector2) -> float:
	if in_face:
		return 0.0 if walks(point) else NAN
	var height := LEVEL * (top - bottom)
	# The ramp of nosings, affine on screen: screen = A + s · Ds + t · Ts with H(s) = height − slope · s.
	var slope := -height / ramp
	var a := screen_of(Vector3(0.0, 0.0, height))
	var ds := Vector2(dir.x, dir.y - slope)
	var ts := across
	var det := ds.x * ts.y - ds.y * ts.x
	if absf(det) < 1e-6:
		return NAN
	var q := point - a
	var s := (q.x * ts.y - q.y * ts.x) / det
	var t := (ds.x * q.y - ds.y * q.x) / det
	if s >= -0.01 and s <= end + 0.01 and absf(t) <= half + 0.01:
		return clampf(s, 0.0, end)
	return NAN


## The flight's frame at `point` (screen): Vector2(s, t) of the walkable surface drawn there (a front
## flight: s 0), NAN in both off it. The stairs walk (stairs_sequence.gd) carries a body along its t.
func st_at(point: Vector2) -> Vector2:
	if not walks(point):
		return Vector2(NAN, NAN)
	if in_face:
		return Vector2(0.0, clampf((point.x - rim.x) / across.x, -half, half) if absf(across.x) > 1e-6 else 0.0)
	var height := LEVEL * (top - bottom)
	var slope := -height / ramp
	var ds := Vector2(dir.x, dir.y - slope)
	var det := ds.x * across.y - ds.y * across.x
	if absf(det) < 1e-6:
		return Vector2(NAN, NAN)
	var q := point - screen_of(Vector3(0.0, 0.0, height))
	var s := (q.x * across.y - q.y * across.x) / det
	var t := (ds.x * q.y - ds.y * q.x) / det
	return Vector2(clampf(s, 0.0, end), clampf(t, -half, half))


## The height above the lower ground of the walkable surface at `point` (screen), NAN off it: on a
## front flight how far up the face it lies, else the nosing line's there.
func height_at(point: Vector2) -> float:
	if in_face:
		if not walks(point):
			return NAN
		# point = rim + T · t + (0, down the face).
		var t := (point.x - rim.x) / across.x
		var down := point.y - (rim.y + across.y * t)
		var height := LEVEL * (top - bottom)
		return clampf(height - down, 0.0, height)
	var s := s_at(point)
	return NAN if is_nan(s) else nosing(s)


## The level of the stretch of the flight at `point` (the upper half of a level's stretch takes the
## level above it), `fallback` off the walkable surface.
func level_at(point: Vector2, fallback: int) -> int:
	var h := height_at(point)
	if is_nan(h):
		return fallback
	return clampi(bottom + roundi(h / LEVEL), bottom, top)


## The depth (ground y) of a body standing at `point` (screen) on the flight.
func depth_at(point: Vector2) -> float:
	var h := height_at(point)
	return point.y + LEVEL * bottom + (h if not is_nan(h) else 0.0)


# --- building ------------------------------------------------------------------------------

func _build() -> void:
	var height := LEVEL * (top - bottom)
	_hulls.clear()
	_solids.clear()
	_blockers.clear()
	_pieces.clear()
	var outer := half + POST
	approach = PackedVector2Array([screen_of(Vector3(-APPROACH, -outer, height)), screen_of(Vector3(0.0, -outer, height)),
			screen_of(Vector3(0.0, outer, height)), screen_of(Vector3(-APPROACH, outer, height))])
	reach = PackedVector2Array([screen_of(Vector3(-REACH, -half, height)), screen_of(Vector3(0.0, -half, height)),
			screen_of(Vector3(0.0, half, height)), screen_of(Vector3(-REACH, half, height))])
	beyond = PackedVector2Array() if in_face else PackedVector2Array([screen_of(Vector3(end, -half, 0.0)),
			screen_of(Vector3(end + BEYOND, -half, 0.0)), screen_of(Vector3(end + BEYOND, half, 0.0)), screen_of(Vector3(end, half, 0.0))])
	if in_face:
		# The face between the posts, from the top edge to the foot.
		walk = PackedVector2Array([screen_of(Vector3(0.0, -half, height)), screen_of(Vector3(0.0, half, height)),
				screen_of(Vector3(0.0, half, 0.0)), screen_of(Vector3(0.0, -half, 0.0))])
		_hulls.append([walk, false])
		for side: float in [-1.0, 1.0]:
			_hulls.append([_post_quad(side), false])
	else:
		# The steps' nosing line between the side walls.
		walk = PackedVector2Array()
		for s: float in [0.0, end]:
			walk.append(screen_of(Vector3(s, -half, nosing(s))))
		for s: float in [end, 0.0]:
			walk.append(screen_of(Vector3(s, half, nosing(s))))
		for k in steps:
			var s0 := k * run
			var s1 := (k + 1) * run
			_solids.append([s0, s1, -half, half, 0.0, 0.0, height - (k + 1) * RISE, height - (k + 1) * RISE])
			_hulls.append([_box_hull(s0, s1, -half, half, 0.0, height - (k + 1) * RISE), true])
			_hulls.append([_hull([Vector3(s0, -half, height - k * RISE), Vector3(s0, half, height - k * RISE), Vector3(s0, half, height - (k + 1) * RISE), Vector3(s0, -half, height - (k + 1) * RISE)]), true])
		for side: float in [-1.0, 1.0]:
			var inner := side * half
			var out := side * outer
			_solids.append([0.0, end, minf(inner, out), maxf(inner, out), 0.0, 0.0, height + POST_UP, POST_UP])
			_hulls.append([_hull([Vector3(0.0, inner, 0.0), Vector3(end, inner, 0.0), Vector3(0.0, out, 0.0), Vector3(end, out, 0.0),
					Vector3(0.0, inner, height + POST_UP), Vector3(end, inner, POST_UP), Vector3(0.0, out, height + POST_UP), Vector3(end, out, POST_UP)]), true])
	var pieces: Array[PackedVector2Array] = []
	for hull: Array in _hulls:
		pieces.append(hull[0])
	silhouette = _union(pieces)
	bounds = Rect2(walk[0], Vector2.ZERO)
	for point in walk:
		bounds = bounds.expand(point)
	for point in approach:
		bounds = bounds.expand(point)
	for point in beyond:
		bounds = bounds.expand(point)
	for shape in silhouette:
		for point in shape:
			bounds = bounds.expand(point)
	# A front flight's painted piece reaches over the wall beside it: the ledge dressing keeps clear of
	# it too.
	for slice: Array in _piece_quads():
		for point: Vector2 in slice[0]:
			bounds = bounds.expand(point)
	bounds = bounds.grow(1.0)
	_build_faces()


## A front flight's painted piece (none for the others) in three slices, screen-left first, in the
## face's plane (a 45° flight its own piece, DIAG_PIECES, painted on the slanted face): [quad (top left, top
## right, bottom right, bottom left), the slice's span across the piece (UV.x from, to), the piece
## (PIECE_ORDER), absolute height of its middle]. Widths are measured on screen (along t
## they are longer on a 45° face).
func _piece_quads() -> Array:
	var slices: Array = []
	if not in_face:
		return slices
	var height := LEVEL * (top - bottom)
	var diagonal := absf(dir.x) > 0.1
	var pieces: Dictionary = DIAG_PIECES if diagonal else FRONT_PIECES
	var levels := mini(top - bottom, pieces.size())
	var piece: Dictionary = pieces[levels]
	var steps_at: Vector2 = piece["steps"]
	# From the top edge (owner 2026-11-06: the piece is never lifted or cut; the strip above its top
	# step is the top's own ground, `add_approach`).
	var h_top := height
	var natural := float(piece["aspect"]) * (h_top + PIECE_SINK)
	var per_t := maxf(absf(across.x), 0.5)
	# The end of the steps on screen left (+1 or -1 across).
	var left := 1.0 if screen_of(Vector3(0.0, half, height)).x < screen_of(Vector3(0.0, -half, height)).x else -1.0
	var inner := half - PIECE_INTO / per_t
	var ts := [left * (inner + steps_at.x * natural / per_t), left * inner, -left * inner,
			-left * (inner + (1.0 - steps_at.y) * natural / per_t)]
	var us := [0.0, steps_at.x, steps_at.y, 1.0]
	# A diagonal piece is painted for the south-west face: mirrored on the south-east one.
	if diagonal and dir.x > 0.0:
		us = [1.0, steps_at.y, steps_at.x, 0.0]
	var middle := LEVEL * bottom + (height - PIECE_SINK) * 0.5
	for i in 3:
		slices.append([PackedVector2Array([screen_of(Vector3(0.0, ts[i], h_top)), screen_of(Vector3(0.0, ts[i + 1], h_top)),
				screen_of(Vector3(0.0, ts[i + 1], -PIECE_SINK)), screen_of(Vector3(0.0, ts[i], -PIECE_SINK))]),
				Vector2(us[i], us[i + 1]), PIECE_ORDER.find(str(piece["part"])), middle])
	return slices


## A side flight's painted piece, [] for any other flight or a size without one: [its box on screen
## (top left, top right, bottom right, bottom left: from the end of the run to the rim, from the top
## of the far side wall at the rim to the near side's foot), UV.x at its left and right (the piece
## is painted westward, its rim on the right: mirrored for an eastward flight), the piece
## (PIECE_ORDER), absolute height of its middle, absolute heights at its top and bottom].
func _side_piece() -> Array:
	if in_face or absf(dir.y) > 1e-6:
		return []
	var key := Vector2i(top - bottom, roundi(half / HALF_CELL))
	if not SIDE_PIECES.has(key):
		return []
	var height := LEVEL * (top - bottom)
	var near := 1.0 if across.y > 0.0 else -1.0
	var outer := half + POST
	var top_left := screen_of(Vector3(0.0, -near * outer, height + POST_UP))
	var foot := screen_of(Vector3(0.0, near * outer, 0.0))
	var end_x := screen_of(Vector3(end, 0.0, 0.0)).x
	var x0 := minf(top_left.x, end_x)
	var x1 := maxf(top_left.x, end_x)
	var westward := dir.x < 0.0
	return [PackedVector2Array([Vector2(x0, top_left.y), Vector2(x1, top_left.y), Vector2(x1, foot.y), Vector2(x0, foot.y)]),
			Vector2(0.0, 1.0) if westward else Vector2(1.0, 0.0), PIECE_ORDER.find(str(SIDE_PIECES[key])),
			LEVEL * bottom + height * 0.5, Vector2(LEVEL * top + POST_UP, LEVEL * bottom)]


## A front flight's post on `side` (−1 or 1 across), on screen: from the top edge to the foot.
func _post_quad(side: float) -> PackedVector2Array:
	var height := LEVEL * (top - bottom)
	var inner := side * half
	var out := side * (half + POST)
	return PackedVector2Array([screen_of(Vector3(0.0, inner, height)), screen_of(Vector3(0.0, out, height)),
			screen_of(Vector3(0.0, out, 0.0)), screen_of(Vector3(0.0, inner, 0.0))])


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

## The faces in the order they are drawn. A front flight: its steps, flat on the face, for the depth
## map only (since 2026-11-06 it is drawn as its painted piece, `_piece_quads`; its posts are still
## `blockers`, the piece's rock frame stands there). Else the far side wall's inner face, the steps
## from the far end, then each side wall (far first). Faces turned away are left out.
func _build_faces() -> void:
	faces.clear()
	var height := LEVEL * (top - bottom)
	var normal := Vector3(dir.x, dir.y, 0)
	if in_face:
		var steps_face := _face(KIND_STEPS, [Vector3(0.0, -half, height), Vector3(0.0, half, height), Vector3(0.0, half, 0.0), Vector3(0.0, -half, 0.0)], normal)
		if not steps_face.is_empty():
			faces.append(steps_face)
		return
	# Which side is nearer the camera (+ground y), and which end.
	var near_side := 1.0 if across.y > 1e-6 else (-1.0 if across.y < -1e-6 else 0.0)
	var toward_end := signf(dir.y) if absf(dir.y) > 1e-6 else 0.0
	var sides: Array[float] = [-1.0, 1.0]
	if near_side != 0.0:
		sides = [-near_side, near_side]
		_wall_side_face(-near_side, true)
	# The steps, from the far end.
	var parts: Array = []
	for k in steps:
		var s0 := k * run
		var s1 := (k + 1) * run
		parts.append(_riser(s0, height - k * RISE, height - (k + 1) * RISE, k))
		parts.append(_tread(s0, s1, height - (k + 1) * RISE, k + 1))
	if toward_end < 0.0:
		parts.reverse()
	for part: Dictionary in parts:
		if not part.is_empty():
			faces.append(part)
	for side in sides:
		_wall_faces(side, near_side == 0.0 or side == near_side)


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


## A tread from s0 to s1 at height h.
func _tread(s0: float, s1: float, h: float, index: int) -> Dictionary:
	return _face(KIND_TREAD, [Vector3(s0, -half, h), Vector3(s1, -half, h), Vector3(s1, half, h), Vector3(s0, half, h)],
			Vector3(0, 0, 1), {"s0": s0, "depth": s1 - s0, "off": _offset(index)})


## A riser at s from h_top down to h_bottom, facing down the flight.
func _riser(s: float, h_top: float, h_bottom: float, index: int) -> Dictionary:
	return _face(KIND_RISER, [Vector3(s, -half, h_top), Vector3(s, half, h_top), Vector3(s, half, h_bottom), Vector3(s, -half, h_bottom)],
			Vector3(dir.x, dir.y, 0), {"off": _offset(index + 1) * 0.7})


## One side face of a side wall (inner or outer), from the ground up to its top; the inner one in
## bands for its contact shadow with the steps.
func _wall_side_face(side: float, inner: bool) -> void:
	var height := LEVEL * (top - bottom)
	var t_face := side * (half if inner else half + POST)
	var normal_sign := -side if inner else side
	var normal := Vector3(across.x * normal_sign, across.y * normal_sign, 0)
	if shade_for(normal) <= 0.0:
		return
	var floors := Vector2.ZERO
	var tops := Vector2(height + POST_UP, POST_UP)
	var bands: Array = [[floors, tops]]
	if inner:
		var n := Vector2(nosing(0.0), nosing(end))
		var contact := n + Vector2.ONE * WALL_CONTACT_REACH
		bands = [[floors, n], [n, contact], [contact, tops]]
	for band: Array in bands:
		var lo: Vector2 = band[0]
		var hi: Vector2 = band[1]
		if hi.x - lo.x <= 0.01 and hi.y - lo.y <= 0.01:
			continue
		faces.append({"kind": KIND_BLOCK, "quad": [Vector3(0.0, t_face, lo.x), Vector3(end, t_face, lo.y), Vector3(end, t_face, hi.y), Vector3(0.0, t_face, hi.x)],
				"normal": normal, "shade": shade_for(normal), "contact": inner})


## A side wall's faces but the far wall's inner face (drawn before the steps): the outer face, the
## inner one (the near wall's), its top and its two ends.
func _wall_faces(side: float, with_inner: bool) -> void:
	var height := LEVEL * (top - bottom)
	var inner := side * half
	var out := side * (half + POST)
	_wall_side_face(side, false)
	if with_inner:
		_wall_side_face(side, true)
	var slope := -height / maxf(1e-6, end)
	var cap := _face(KIND_CAP, [Vector3(0.0, inner, height + POST_UP), Vector3(end, inner, POST_UP), Vector3(end, out, POST_UP), Vector3(0.0, out, height + POST_UP)],
			Vector3(-dir.x * slope, -dir.y * slope, 1.0))
	if not cap.is_empty():
		faces.append(cap)
	for end_face: Dictionary in [
			_face(KIND_BLOCK, [Vector3(end, inner, 0), Vector3(end, out, 0), Vector3(end, out, POST_UP), Vector3(end, inner, POST_UP)], Vector3(dir.x, dir.y, 0)),
			_face(KIND_BLOCK, [Vector3(0.0, out, 0.0), Vector3(0.0, inner, 0.0), Vector3(0.0, inner, height + POST_UP), Vector3(0.0, out, height + POST_UP)], Vector3(-dir.x, -dir.y, 0))]:
		if not end_face.is_empty():
			faces.append(end_face)


# --- output --------------------------------------------------------------------------------

## The faces into `mesh` (the stairs shader): UV.x texture px (blocks: block units), UV.y the
## kind's texture coordinate + kind · KIND_OFFSET; colour r = light / 2, g = height in levels
## ((L + 4) / 32), b and a = where on the face (0 … 1 across both ways). A front flight draws its
## painted piece instead (its steps face stays for the depth map): UV over the piece, colour b which
## piece (/ 4).
func add_mesh(mesh: MeshData) -> void:
	var side_piece := _side_piece()
	for face in (faces if not in_face and side_piece.is_empty() else []):
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
	for slice: Array in _piece_quads():
		var quad: PackedVector2Array = slice[0]
		var span: Vector2 = slice[1]
		var h := float(slice[3])
		var away := PIECE_AWAY_LIGHT if absf(dir.x) > 0.1 and dir.x > 0.0 else 1.0
		var colour := Color(0.5 * away, LevelCode.of(h / LEVEL), (float(slice[2]) + 0.5) / 8.0, 1.0)
		var corners: Array = []
		for k in 4:
			var uv := Vector2(span.y if k == 1 or k == 2 else span.x, 1.0 if k >= 2 else 0.0)
			corners.append([quad[k], Vector2(uv.x, uv.y + KIND_PIECE * KIND_OFFSET), colour, h])
		_emit(mesh, [corners[0], corners[1], corners[2]])
		_emit(mesh, [corners[0], corners[2], corners[3]])
	if not side_piece.is_empty():
		var quad: PackedVector2Array = side_piece[0]
		var us: Vector2 = side_piece[1]
		var colour := Color(0.5, LevelCode.of(float(side_piece[3]) / LEVEL), (float(side_piece[2]) + 0.5) / 8.0, 1.0)
		var heights: Vector2 = side_piece[4]
		var corners: Array = []
		for k in 4:
			var uv := Vector2(us.y if k == 1 or k == 2 else us.x, 1.0 if k >= 2 else 0.0)
			corners.append([quad[k], Vector2(uv.x, uv.y + KIND_PIECE * KIND_OFFSET), colour, heights.x if k < 2 else heights.y])
		_emit(mesh, [corners[0], corners[1], corners[2]])
		_emit(mesh, [corners[0], corners[2], corners[3]])


## The faces into the depth map: depth = ground y, written as level `top` and dy = 64 · top − H. A
## side or back flight is marked as a structure (the cast shadows read its height, not its level);
## a front flight is the wall it is set into.
func add_depth(depth: MeshData) -> void:
	for face in faces:
		var corners: Array = []
		for p: Vector3 in face["quad"]:
			var w := world(p)
			corners.append([screen(w), Vector2.ZERO, ElevationOcclusion.encode(top, LEVEL * top - w.z, not in_face), w.z])
		_emit(depth, [corners[0], corners[1], corners[2]])
		_emit(depth, [corners[0], corners[2], corners[3]])


## The top's ground just behind the rim into `mesh` (elevation_ramp.gdshader, with `top_ground`'s
## sheet): over the top's edge there, its sides fading out over APPROACH_FADE, so the edge breaks
## where the flight leaves the top.
func add_approach(mesh: MeshData) -> void:
	var height := LEVEL * (top - bottom)
	var level_of := LevelCode.of(top)
	var solid := Color(1.0, level_of, 0.0, 1.0)
	var clear := Color(1.0, level_of, 0.0, 0.0)
	var outer := half + POST
	var fade := APPROACH_FADE
	var patch := approach
	if in_face:
		# Only over the steps: the top's lip runs on over the rock either side (the piece's frames).
		outer = half - PIECE_INTO
		fade = APPROACH_FADE * 0.5
		patch = PackedVector2Array([screen_of(Vector3(-APPROACH, -outer, height)), screen_of(Vector3(0.0, -outer, height)),
				screen_of(Vector3(0.0, outer, height)), screen_of(Vector3(-APPROACH, outer, height))])
		# And down the face to the top step (the piece's steps begin "top" down it): the top's ground
		# there instead of the wall's ledge (owner 2026-11-06: no ledge painted over the stairs).
		var steps_down := _steps_top() * (height + PIECE_SINK) + LEDGE_COVER
		if steps_down > LEDGE_COVER:
			_add_quad(mesh, PackedVector2Array([screen_of(Vector3(0.0, -outer, height)), screen_of(Vector3(0.0, outer, height)),
					screen_of(Vector3(0.0, outer, height - steps_down)), screen_of(Vector3(0.0, -outer, height - steps_down))]), [solid, solid, solid, solid])
	var wide := outer + fade
	var faded := PackedVector2Array([screen_of(Vector3(-APPROACH, -wide, height)), screen_of(Vector3(0.0, -wide, height)),
			screen_of(Vector3(0.0, wide, height)), screen_of(Vector3(-APPROACH, wide, height))])
	_add_quad(mesh, patch, [solid, solid, solid, solid])
	# The sides: [inner back, inner rim] against [outer back, outer rim].
	for pair: Array in [[0, 1], [3, 2]]:
		_add_quad(mesh, PackedVector2Array([patch[pair[0]], patch[pair[1]], faded[pair[1]], faded[pair[0]]]), [solid, solid, clear, clear])


## Where a front flight's painted piece has its first full step, as a share of its height down from
## the top edge (its set's "tops"; 0 for any other flight, a 45° one's steps start at the top).
func _steps_top() -> float:
	if not in_face:
		return 0.0
	if absf(dir.x) > 0.1:
		return 0.0
	var tops: Dictionary = Sets.SETS[art_set(stone)]["tops"]
	return float(tops.get(mini(top - bottom, FRONT_PIECES.size()), 0.0))


static func _add_quad(mesh: MeshData, quad: PackedVector2Array, colors: Array) -> void:
	for index: int in [0, 1, 2, 0, 2, 3]:
		mesh.add(quad[index], Vector2.ZERO, colors[index])


## Where a face is cut for its light: fractions along its two sides.
func _cuts(face: Dictionary) -> Array:
	var kind := int(face["kind"])
	var fu := PackedFloat32Array([0.0, 1.0])
	var fv := PackedFloat32Array([0.0, 1.0])
	var width := 2.0 * half
	if kind == KIND_TREAD:
		var depth := float(face["depth"])
		fu = PackedFloat32Array([0.0, TREAD_AO_REACH, 1.0 - NOSING / depth, 1.0])
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
		light *= TREAD_AO + (1.0 - TREAD_AO) * clampf(f.x / TREAD_AO_REACH, 0.0, 1.0)
		if f.x > 1.0 - NOSING / float(face["depth"]):
			light *= NOSING_LIGHT
	elif kind == KIND_RISER:
		var edge := clampf(minf(f.x, 1.0 - f.x) * width / RISER_EDGE_REACH, 0.0, 1.0)
		light *= (RISER_AO + (1.0 - RISER_AO) * clampf(f.y / RISER_AO_REACH, 0.0, 1.0)) * (RISER_EDGE + (1.0 - RISER_EDGE) * edge)
	return light


## A vertex of a face at (fu, fv): [screen point, UV, colour, absolute height].
func _vertex(face: Dictionary, f: Vector2, inside: Vector2) -> Array:
	var quad: Array = face["quad"]
	var p: Vector3 = (quad[0] as Vector3).lerp(quad[1], f.x).lerp((quad[3] as Vector3).lerp(quad[2], f.x), f.y)
	var w := world(p)
	var kind := int(face["kind"])
	# Light is taken just inside the cell, so steps in it (the nosing) stay sharp.
	var light := _light(face, f.lerp(inside, 0.001))
	if bool(face.get("contact", false)):
		light *= _contact(p)
	var uv := Vector2.ZERO
	var height := LEVEL * (top - bottom)
	match kind:
		KIND_STEPS:
			# Along the face in texture px; down it in steps from the top edge.
			uv = Vector2(screen(w).x * PX + float(posmod(_seed, 997)), (LEVEL * top - w.z) / RISE)
		KIND_TREAD:
			uv = Vector2(p.y * PX + float(face["off"]), clampf((p.x - float(face["s0"])) / float(face["depth"]), 0.0, 1.0))
		KIND_RISER:
			uv = Vector2(p.y * PX + float(face["off"]), (height - p.z) / RISE)
		KIND_POST:
			uv = Vector2((p.y - float(face["left"])) / float(face["span"]), (BLOCK_ROWS_FROM - w.z) / BLOCK)
		KIND_CAP:
			uv = Vector2(p.x * PX * 1.6 + 220.0, clampf((absf(p.y) - half) / POST, 0.0, 1.0))
		_:
			uv = Vector2(w.x / BLOCK, (BLOCK_ROWS_FROM - w.z) / BLOCK)
	var lines := f
	if bool(face.get("contact", false)):
		# A side wall's inner face, cut in bands: its joint lines only along the whole face's ends.
		lines = Vector2(f.x, 0.5)
	return [screen(w), Vector2(uv.x, uv.y + kind * KIND_OFFSET),
			Color(clampf(light * 0.5, 0.0, 1.0), LevelCode.of(w.z / LEVEL), lines.x, lines.y), w.z]


## One triangle of vertices [screen point, UV, colour, height] into `mesh`, without what of it lies
## below the top level behind the higher ground in front (`occluders`) and what lies behind the
## cliff's rock (`rock_cuts`).
func _emit(mesh: MeshData, triangle: Array) -> void:
	var points := PackedVector2Array([triangle[0][0], triangle[1][0], triangle[2][0]])
	var below_top := PackedFloat32Array()
	var lowest := INF
	for vertex: Array in triangle:
		below_top.append(float(vertex[3]) - (LEVEL * top - OCCLUDE_MARGIN))
		lowest = minf(lowest, below_top[below_top.size() - 1])
	var covered := _touches(points, _rock_rects)
	if (occluders.is_empty() or lowest >= 0.0) and not covered:
		for vertex: Array in triangle:
			mesh.add(vertex[0], vertex[1], vertex[2])
		return
	var parts: Array[PackedVector2Array] = [points]
	if not occluders.is_empty() and lowest < 0.0:
		var halves := _split(points, below_top)
		parts = []
		if (halves[1] as PackedVector2Array).size() >= 3:
			parts.append(halves[1])
		if (halves[0] as PackedVector2Array).size() >= 3:
			parts.append_array(_cut([halves[0]]))
	if covered:
		parts = _cut_by(parts, rock_cuts, _rock_rects)
	for part in parts:
		_add_polygon(mesh, triangle, part)


## True when the box around `points` meets one of `rects`.
static func _touches(points: PackedVector2Array, rects: Array[Rect2]) -> bool:
	if rects.is_empty():
		return false
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	for rect in rects:
		if box.intersects(rect):
			return true
	return false


## `parts` without the occluders.
func _cut(parts: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	return _cut_by(parts, occluders, _occluder_rects)


## `parts` without `polygons` (whose rects are `rects`).
static func _cut_by(parts: Array[PackedVector2Array], polygons: Array[PackedVector2Array], rects: Array[Rect2]) -> Array[PackedVector2Array]:
	for index in polygons.size():
		var next: Array[PackedVector2Array] = []
		for part in parts:
			var box := Rect2(part[0], Vector2.ZERO)
			for point in part:
				box = box.expand(point)
			if not box.intersects(rects[index]):
				next.append(part)
				continue
			next.append_array(_difference(part, polygons[index], rects[index], 2))
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
		for half_plane: PackedVector2Array in [PackedVector2Array([Vector2(-far, -far), Vector2(far, -far), Vector2(far, middle), Vector2(-far, middle)]),
				PackedVector2Array([Vector2(-far, middle), Vector2(far, middle), Vector2(far, far), Vector2(-far, far)])]:
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(part, half_plane):
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


## The contact shadow on a side wall's inner face where it meets the steps.
func _contact(p: Vector3) -> float:
	var above := p.z - nosing(p.x)
	return WALL_CONTACT + (1.0 - WALL_CONTACT) * clampf(above / WALL_CONTACT_REACH, 0.0, 1.0)
