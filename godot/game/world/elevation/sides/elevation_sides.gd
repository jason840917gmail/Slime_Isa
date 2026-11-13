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
const LevelCode := preload("res://game/world/elevation/level_code.gd")
const ElevationRims := preload("res://game/world/elevation/elevation_rims.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const LedgeDressing := preload("res://game/world/elevation/sides/ledge_dressing.gd")

## A wall's reach (world units): down a front face FRONT per level of drop (one stone course), out
## from a side SIDE for one level, growing as the drop to the power THIN_GROWTH for more (a tall
## side stays a strip) up to SIDE_FULL_DROP levels and no wider beyond (`side_width`: on the walls
## over ten levels, 2026-11-13, a side grown on was 140 units wide and buried the ledges and
## balconies beside it; no outdoor wall was over three levels before); between them a superellipse of exponent SHAPE (2 an ellipse, higher
## squarer). A back edge shows no wall (the owner, 2026-10-13: "in the top not black wall hint"):
## the side's reach fades out as the normal turns north (`BACK_FADE`).
const FRONT := 64.0
const SIDE := 24.0
const THIN_GROWTH := 0.7
const SIDE_FULL_DROP := 3.0
const TALL_TURN := 0.12
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
## A terrace joint (`_with_terrace_joints`): where a terrace's side runs up against a higher wall that
## goes on down past it, that wall's courses below the terrace's level are hung from the terrace's
## chain for a stretch along the wall: half of what the wall runs on straight past the terrace (the
## other half is left to fold round the wall's own next corner), JOINT_CELLS cells at most, and none
## where it runs on less than JOINT_MIN cells. So the terrace's side and those courses fold round as
## one wall, as a hole's inner corner does; the fold ends JOINT_STRAIGHT units before the stretch
## does, so the stretch ends on fibres hanging straight, as the wall's own beside it. The higher
## wall's own courses end JOINT_TUCK levels below the terrace's level along that stretch, under the
## top of the ones hung there.
const JOINT_CELLS := 2
const JOINT_MIN := 2
const JOINT_STRAIGHT := 12.0
const JOINT_LEDGE := 28.0
const JOINT_TUCK := 0.15
const RADIUS_JOINT := 2.0
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
const SHADOW_LEAD := 8.0
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
## A foot's shadow: its length and strength averaged along the foot over SHADOW_SMOOTH units either
## way (`_smooth_shadow`); runs of foot whose ends lie within SHADOW_JOIN units of each other cast one
## shadow (`_shadow_runs`); each of its fibres ends where another foot is as near as its own
## (`_lay_shadows`), counting only feet that lie at least SHADOW_CUT_MIN of their distance ahead of
## the fibre (those beside it, along a straight stretch, never meet it) and SHADOW_CUT_NEAR units or
## more from its foot, and shows that foot's shadow from where it is the darker one (`_shadow_turn`:
## tried every SHADOW_CUT_STEP units along it); feet within SHADOW_BUNCH of each other cast one fibre.
## The shadow fades out over SHADOW_FADE of its length (elevation_sides.gdshader `foot_shadow_width`
## of FOOT_OUT rows).
const SHADOW_SMOOTH := 24.0
const SHADOW_JOIN := 16.0
const SHADOW_CUT_MIN := 0.02
const SHADOW_CUT_NEAR := 6.0
const SHADOW_CUT_STEP := 3.0
const SHADOW_BUNCH := 1.5
const SHADOW_SPAN := 3.0
const SHADOW_FADE := 0.9
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
## Where a top's border runs up against another level's wall, and how it is drawn there (`build`
## fills it, for tools/check_cliff_joints.gd): {at (where, world units), level (the lower top's),
## against (the other top's), kind, run (cells: see the kinds)}. Kinds: "fold"
## a terrace joint, drawn as one folding wall (`_with_terrace_joints`); "short" a terrace's side
## against a wall that runs on less than JOINT_MIN cells past it; "no-front" a terrace's side against
## a wall that is no straight south face there (a 45° face, or it turns); "diagonal" a wall that ends
## against the other level's wall with a 45° edge within JOINT_MIN cells of its end ("run": how far).
## All but "fold" keep the plain join (`_taper_against_walls`).
var joints: Array[Dictionary] = []
## Callable(point) -> bool: true where a ramp's slope lies (a foot's shadow fades out before it).
var _under_ramp: Callable
## Callable(point) -> bool: true by a flight of stairs (no ledge dressing there).
var _near_stairs: Callable
## The ledge dressing (sides/ledge_dressing.gd): pieces along each chain's foot, one mesh per level
## after that level's walls. Its `density` 0 places none.
var dressing_density := 1.0
var _dressing: LedgeDressing
## Every chain's foot shadows, waiting for `_lay_shadows` (`build`): {border, by_material, points,
## foots, bases, ways, lengths, fulls, fars, floors, runs, colours, along, length}.
var _shadows: Array[Dictionary] = []
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
	## A terrace joint (`_with_terrace_joints`). `virtual`: 1 where the border is the line across the
	## higher wall's face at the terrace's level (no top there: no lip); `lift`: how many levels of
	## that wall hang above the point; `pin_u`: the higher wall's own u there (NAN elsewhere), so its
	## art runs on; `cut`: 1 along the higher wall's stretch whose lower courses the terrace's chain
	## hangs; `taper`: 1 where a terrace's side meets a higher wall with no joint (`_taper_against_walls`).
	var virtual := PackedByteArray()
	var lift := PackedFloat32Array()
	## How many levels the point's top stands above its chain's level: along a joint's stretch of a
	## higher wall's side, which hangs from that wall's own top (`_with_front_joints`).
	var raise := PackedFloat32Array()
	## The share of a wall's reach the point's fibre takes (1; less along such a stretch: the strip's
	## lower part), and where its art starts across a side's course (0 … 1).
	var narrow := PackedFloat32Array()
	var art_from := PackedFloat32Array()
	## How far such a stretch lies out from the higher wall's border (units; 0 elsewhere).
	var inset := PackedFloat32Array()
	var pin_u := PackedFloat32Array()
	var cut := PackedByteArray()
	var taper := PackedByteArray()
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
	_shadows.clear()
	joints.clear()
	var filed: Array = []
	var chains := _chains(_with_front_joints(_with_terrace_joints(edges)))
	_note_diagonal_ends(chains)
	# Higher tops first (a stable sort: each level's chains keep their order, and no mesh holds two
	# levels' pieces): a terrace joint's chain takes the higher wall's style and u, set when that
	# wall's chain is built.
	var order: Array[int] = []
	for index in chains.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		var level_a := int(chains[a][0]["level"])
		var level_b := int(chains[b][0]["level"])
		return level_a > level_b if level_a != level_b else a < b)
	for index: int in order:
		var chain: Array[Dictionary] = chains[index]
		var level := int(chain[0]["level"])
		var styles := {}
		var painted := PackedStringArray()
		for edge in chain:
			# The stretch of a higher wall a joint hangs from this chain keeps that wall's style.
			if edge.has("twin"):
				painted.append(str((edge["twin"] as Dictionary).get("style", "")))
				continue
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
		filed.append([level, by_material])
	# The feet's shadows, now that every chain's feet are known: each is cut by the others' too.
	_lay_shadows()
	for entry: Array in filed:
		var level := int(entry[0])
		var by_material: Dictionary = entry[1]
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


## How wide a side wall `drop` levels high is (world units): SIDE for one level, growing as the
## drop to the power THIN_GROWTH, no wider than at SIDE_FULL_DROP levels.
static func side_width(drop: float) -> float:
	return SIDE * pow(minf(drop, SIDE_FULL_DROP), THIN_GROWTH)


## The reach of a wall `drop` levels high for outward normal `n` (world units): the point of the
## shape K (FRONT · drop down, `side_width` out, a superellipse of exponent SHAPE)
## furthest along `n`; facing north, the side's reach fading to nothing (BACK_FADE).
## A wall over SIDE_FULL_DROP levels is that shape for SIDE_FULL_DROP levels under a straight
## stretch for the levels above them (TALL_TURN: how soon past a side's normal it comes in): its
## side stays a strip all the way down and its corner rounds off over its last courses only, as a
## three-level hill's does (stretched to its height, the round became a long taper to the foot).
static func reach(n: Vector2, drop: float) -> Vector2:
	if drop <= 0.0:
		return Vector2.ZERO
	var side := side_width(drop)
	if n.y < 0.0:
		return Vector2(side * signf(n.x) * (1.0 - smoothstep(BACK_FADE.x, BACK_FADE.y, -n.y)), 0.0)
	if drop > SIDE_FULL_DROP:
		return reach(n, SIDE_FULL_DROP) + Vector2(0.0, FRONT * (drop - SIDE_FULL_DROP) * smoothstep(0.0, TALL_TURN, n.y))
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


# --- terrace joints -----------------------------------------------------------------------

## `edges` with the terrace joints worked in (the owner, 2026-11-06: "a join ... like an interior
## joint only seen on holes"; 2026-11-11: the wedge laid over the wall there did "not look too good").
## Where a terrace's side runs up against a higher wall that goes on down past it (ElevationRims:
## the terrace's vertical edges beside that wall's lower courses), the wall's courses below the
## terrace's level are the terrace's from there on: for a stretch along the wall (JOINT_CELLS), a line
## across its face at the terrace's level joins the terrace's chain ("twin": the wall's edge there;
## drawn as a front wall down to the wall's own foot, with no top), so the terrace's side and those
## courses fold round the corner as one wall (`_fold_corners`), as at a hole's inner corner. The
## wall's edges along that stretch are marked "cut" (its courses end at the terrace's level there)
## and the terrace's edges beside the wall "joined" (a side wall with its foot). The stretch takes
## the wall's style, u and courses (`build`, `_join_u`, `_add_chain`), so past its end the wall's own
## lower courses run on from it without a seam. Where the wall runs on less than JOINT_MIN cells
## past the terrace nothing changes: the terrace's side tapers against it (`_taper_against_walls`).
## The edges changed are copies; `edges` itself is left as it is.
func _with_terrace_joints(edges: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = edges.duplicate()
	# The front edges of every level by where they start, and the terraces' edges beside a wall.
	var fronts := {}
	var beside: Array[int] = []
	var beside_from := {}
	var beside_to := {}
	for i in out.size():
		var edge := out[i]
		var dir := _dir(edge)
		var level := int(edge["level"])
		if dir.x > 0.9999:
			fronts[Vector3i(level, _point_key(edge["from"]).x, _point_key(edge["from"]).y)] = i
		elif absf(dir.y) > 0.9999 and _over_level(edge) != NO_OVER:
			beside.append(i)
			beside_from[Vector3i(level, _point_key(edge["from"]).x, _point_key(edge["from"]).y)] = i
			beside_to[Vector3i(level, _point_key(edge["to"]).x, _point_key(edge["to"]).y)] = i
	for i: int in beside:
		var edge := out[i]
		var level := int(edge["level"])
		var heading_north := _dir(edge).y < 0.0
		# The topmost of its stack: the one that ends (an east side, heading north) or starts (a west
		# side, heading south) at the terrace's top corner under the wall.
		var corner: Vector2 = edge["to"] if heading_north else edge["from"]
		var corner_key := Vector3i(level, _point_key(corner).x, _point_key(corner).y)
		if (beside_from if heading_north else beside_to).has(corner_key):
			continue
		var top := _over_level(edge)
		var lift := top - level
		var floor_level := int(grid.bands[grid.tri_band[int(edge["x"])]]["bottom"])
		# The wall's edges that run on from the corner (east of an east side, west of a west one), as
		# long as they are the same wall down to the same floor.
		# (the grid's edges are half a cell long)
		var twins: Array[int] = []
		for step in JOINT_CELLS * 4:
			var from := Vector2(corner.x + 0.5 * (step if heading_north else -step - 1), corner.y - lift)
			var index := int(fronts.get(Vector3i(top, _point_key(from).x, _point_key(from).y), -1))
			if index < 0 or out[index].has("cut") or grid.tri_band[int(out[index]["x"])] < 0:
				break
			var band: Dictionary = grid.bands[grid.tri_band[int(out[index]["x"])]]
			if int(band["top"]) != top or int(band["bottom"]) != floor_level:
				break
			twins.append(index)
		if twins.size() < JOINT_MIN * 2:
			joints.append({"at": corner * cell, "level": level, "against": top,
					"kind": "short" if not twins.is_empty() else "no-front", "run": twins.size() * 0.5})
			continue
		joints.append({"at": corner * cell, "level": level, "against": top, "kind": "fold"})
		twins.resize(clampi(twins.size() / 2, 2, JOINT_CELLS * 2))
		for step in twins.size():
			var twin := out[twins[step]].duplicate()
			twin["cut"] = lift
			twin["whole"] = float(top - floor_level)
			out[twins[step]] = twin
			var from: Vector2 = (twin["from"] as Vector2) + Vector2(0.0, lift)
			var to: Vector2 = (twin["to"] as Vector2) + Vector2(0.0, lift)
			out.append({
				"from": from, "to": to, "mode": ElevationRims.RIM, "level": level, "ground": edge["ground"],
				"x": twin["x"], "twin": twin, "drop": float(level - floor_level), "lift": float(lift),
			})
		# The terrace's stack of edges beside the wall: a side wall with its foot from now on.
		var at := i
		for step in 64:
			var joined := out[at].duplicate()
			joined["joined"] = true
			out[at] = joined
			var next: Vector2 = joined["from"] if heading_north else joined["to"]
			var next_key := Vector3i(level, _point_key(next).x, _point_key(next).y)
			at = int((beside_to if heading_north else beside_from).get(next_key, -1))
			if at < 0:
				break
	return out


## `edges` with the second kind of terrace joint worked in (the owner, 2026-11-11, on a ledge's wall
## between two taller walls in desert-b7: "the join does not look like the same wall, you can see
## the 2 walls clashing"): where a lower top's south-facing wall ends against a higher wall's side,
## and that side runs on down past it to the same floor. Until then the ledge's wall just stopped at
## the side's strip, the strip's straight edge and foot laid across its courses. Below the ledge's
## level that corner too is a hole's inner corner: for a stretch south of it (half of what the side
## runs on straight, as much as the fold takes at most, none where it runs on less than JOINT_MIN
## cells) the higher wall's side hangs from the ledge's chain ("twin": the wall's edge there, with its
## lower part: the strip down to the ledge's level stays the wall's own, running on unbroken past the
## ledge's edge, and the made edges lie along its foot line, `inset` from the wall's border, hanging
## the rest of the strip's width, `narrow`; "raise": how far the wall's top stands above the ledge's),
## so the side's strip and the ledge's
## wall fold round the corner as one wall, with one foot and one shadow. The higher wall's edges
## along the stretch are marked "cut" (no wall of its own there; it keeps its top edge), and the
## stretch takes its style, u and course, so the wall's own strip runs on from it without a seam.
func _with_front_joints(edges: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = edges.duplicate()
	# Each level's edges by where they start and end, and every edge heading north or south by its
	# ends (a side's edge: east-facing heading north, west-facing heading south).
	var starts := {}
	var ends := {}
	var north_to := {}
	var south_from := {}
	for i in out.size():
		var edge := out[i]
		var dir := _dir(edge)
		var level := int(edge["level"])
		var from_key := _point_key(edge["from"])
		var to_key := _point_key(edge["to"])
		starts[Vector3i(level, from_key.x, from_key.y)] = i
		ends[Vector3i(level, to_key.x, to_key.y)] = i
		if absf(dir.x) < 0.0001 and not edge.has("twin"):
			if dir.y < 0.0:
				north_to[to_key] = i
			else:
				south_from[from_key] = i
	for i in edges.size():
		var edge := out[i]
		if _dir(edge).x < 0.9999 or edge.has("twin") or edge.has("cut"):
			continue
		var level := int(edge["level"])
		var drop: Array = _edge_drop(edge)
		var floor_level := level - roundi(float(drop[0]))
		# The fold's stretch down the side: the ledge's wall's height and FOLD_RUN, and what stays straight.
		# (in the grid's edges, half a cell each; `needed`: the least a fold can do with)
		var wanted := ceili((FRONT * float(drop[0]) + FOLD_RUN + JOINT_STRAIGHT) / cell * 2.0)
		var needed := ceili((FRONT * float(drop[0]) + JOINT_STRAIGHT + 8.0) / cell * 2.0)
		for at_start: bool in [true, false]:
			var corner: Vector2 = edge["from"] if at_start else edge["to"]
			var corner_key := _point_key(corner)
			# The end of the ledge's border: no edge of its level leads on from there.
			if (ends if at_start else starts).has(Vector3i(level, corner_key.x, corner_key.y)):
				continue
			# The side's edges south of the corner: heading north up to it (an east-facing side, at the
			# wall's west end) or south from it (a west-facing one, at its east end).
			var twins: Array[int] = []
			var at := corner_key
			var top := NO_OVER
			for step in maxi(JOINT_CELLS * 4, wanted * 2):
				var index := int((north_to if at_start else south_from).get(at, -1))
				if index < 0 or out[index].has("cut") or out[index].has("joined"):
					break
				var side := out[index]
				if top == NO_OVER:
					top = int(side["level"])
				# Down to the ledge's own floor: beside open ground there, or beside the ledge's wall
				# itself (the first rows south of the corner lie under it).
				var across := int(side["x"])
				var below := grid.tri_level[across]
				if grid.tri_band[across] >= 0:
					var band: Dictionary = grid.bands[grid.tri_band[across]]
					below = int(band["bottom"]) if int(band["top"]) <= level else NO_OVER
				if int(side["level"]) != top or top <= level or below != floor_level:
					break
				twins.append(index)
				at = _point_key(side["from"] if at_start else side["to"])
			if top == NO_OVER or top <= level:
				continue
			var whole := false
			var trim := 0.0
			if twins.size() < maxi(JOINT_MIN * 2, needed) and twins.size() >= needed:
				# Too short to share, long enough for the fold: the side's whole run hangs from the ledge's
				# chain where the wall goes on from it round an outer corner of 45° at most (that corner,
				# drawn whole by the wall's own chain, laps over the stretch's end: `_border`).
				var beyond := int((ends if at_start else starts).get(Vector3i(top, at.x, at.y), -1))
				if beyond >= 0 and not out[beyond].has("cut") and not out[beyond].has("twin"):
					var side_way := Vector2(0.0, -1.0 if at_start else 1.0)
					var first_way := _dir(out[beyond]) if at_start else side_way
					var second_way := side_way if at_start else _dir(out[beyond])
					whole = first_way.cross(second_way) < 0.0 and first_way.dot(second_way) > 0.69
					# (how far before its end that corner's round begins)
					trim = minf(RADIUS_OUTER * tan(acos(clampf(first_way.dot(second_way), -1.0, 1.0)) * 0.5),
							twins.size() * 0.25 * cell)
			if twins.size() < maxi(JOINT_MIN * 2, needed) and not whole:
				joints.append({"at": corner * cell, "level": level, "against": top, "kind": "front-short",
						"run": twins.size() * 0.5, "needed": maxi(JOINT_MIN * 2, needed) * 0.5})
				continue
			if not whole:
				twins.resize(clampi(maxi(twins.size() / 2, needed), 2, mini(wanted, twins.size())))
			# The side's strip down to the ledge's level stays the wall's own (`inset` wide: its foot line
			# is where the ledge's border starts on the screen); what hangs from the ledge's chain is the
			# rest of its width (`narrow` of a side wall as tall as the ledge's).
			var raise := float(top - level)
			var low := float(level - floor_level)
			var inset := side_width(raise)
			var narrow := (side_width(raise + low) - inset) / side_width(low)
			# The ledge's wall must run on straight past the strip's width: the fold starts beyond it.
			var straight := 0.0
			var walk := i
			for step in 64:
				straight += 0.5
				var onward := _point_key(out[walk]["to"] if at_start else out[walk]["from"])
				var onward_index := int((starts if at_start else ends).get(Vector3i(level, onward.x, onward.y), -1))
				if onward_index < 0 or _dir(out[onward_index]).x < 0.9999 or out[onward_index].has("twin"):
					break
				walk = onward_index
			if straight * cell < inset + JOINT_LEDGE:
				joints.append({"at": corner * cell, "level": level, "against": top, "kind": "ledge-short",
						"run": straight, "needed": ceilf((inset + JOINT_LEDGE) / cell * 2.0) * 0.5})
				continue
			var made: Array[Dictionary] = []
			for index: int in twins:
				var twin := out[index].duplicate()
				twin["cut"] = raise
				twin["whole"] = raise + low
				out[index] = twin
				made.append({
					"from": twin["from"], "to": twin["to"], "mode": ElevationRims.RIM, "level": level, "ground": edge["ground"],
					"x": twin["x"], "twin": twin, "drop": low, "lift": 0.0, "raise": raise, "inset": inset, "narrow": narrow,
					"trim": trim if whole else 0.0,
					"art_from": inset / (inset + narrow * side_width(low)),
				})
			out.append_array(made)
			joints.append({"at": corner * cell, "level": level, "against": top, "kind": "fold"})
	return out


## Notes (`joints`, "diagonal") every wall that ends against another level's wall with a 45° edge at
## its end or within JOINT_MIN cells of it ("run": how many): the end of a line of border (`chains`)
## with higher ground or a higher top's wall beside it. No joint folds there, and a wall that turns
## that close to its end shows it.
func _note_diagonal_ends(chains: Array) -> void:
	for chain: Array[Dictionary] in chains:
		if chain.size() > 2 and _point_key(chain[0]["from"]) == _point_key(chain[chain.size() - 1]["to"]):
			continue
		for at_start: bool in [true, false]:
			var count := chain.size()
			var walked := 0.0
			var found := -1.0
			for step in count:
				var edge := chain[step if at_start else count - 1 - step]
				var dir := _dir(edge)
				if absf(dir.x) > 0.1 and absf(dir.y) > 0.1:
					found = walked
					break
				walked += (edge["from"] as Vector2).distance_to(edge["to"])
				if walked >= float(JOINT_MIN):
					break
			if found < 0.0:
				continue
			var last := chain[0] if at_start else chain[count - 1]
			var end: Vector2 = last["from"] if at_start else last["to"]
			var level := int(last["level"])
			var against := NO_OVER
			for offset: Vector2 in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
				var tri := grid.tri_at(end + offset)
				if tri < 0 or not grid.is_higher(tri, level):
					continue
				var top := int(grid.bands[grid.tri_band[tri]]["top"]) if grid.tri_band[tri] >= 0 else grid.tri_level[tri]
				against = maxi(against, top)
			if against != NO_OVER:
				joints.append({"at": end * cell, "level": level, "against": against, "kind": "diagonal", "run": found})


## A chain's u (`us`: at each point, then at a loop's whole length) with its terrace joints worked in:
## along a joint's stretch of the higher wall that wall's own u (`border.pin_u`), and the rest of
## the chain shifted to run on from it. A chain with a joint at both ends (a terrace between two
## walls) cannot run on from both: its u jumps where the jump shows least, at a point with no wall
## (a back edge), else under an outer corner's stones, else as a crease down the second joint's
## corner (the returned Vector2: the point past it and that point's u for the piece before it; x -1
## where there is none).
func _join_u(border: Border, us: PackedFloat32Array, fibres: PackedVector2Array) -> Vector2:
	var count := border.points.size()
	var crease := Vector2(-1.0, 0.0)
	var head := -1
	for i in count:
		if is_nan(border.pin_u[i]):
			break
		head = i
	var tail := count
	for step in count:
		var i := count - 1 - step
		if is_nan(border.pin_u[i]) or i <= head:
			break
		tail = i
	if head < 0 and tail >= count:
		return crease
	var shift_head := border.pin_u[head] - us[head] if head >= 0 else 0.0
	var shift_tail := border.pin_u[tail] - us[tail] if tail < count else 0.0
	# Where the chain turns from running on from its start to running back from its end.
	var turn := count
	var best := INF
	if head >= 0 and tail < count:
		var middle := (head + tail) / 2
		turn = middle
		for i in range(head + 1, tail):
			var hidden := fibres[i].length() < WALL_MIN
			var under_stones := false
			if border.corner[i] >= 0:
				var corner: Dictionary = border.corners[border.corner[i]]
				under_stones = bool(corner["convex"]) and _is_front_side(corner["n_a"], corner["n_b"]) \
						and i == (int(corner["first"]) + int(corner["last"])) / 2
			if not hidden and not under_stones:
				continue
			var cost := absf(float(i - middle)) + (0.0 if hidden else float(count))
			if cost < best:
				best = cost
				turn = i
	# With nowhere to hide the jump it lies at the second joint's corner, as a crease down that corner's
	# edge: the wall piece there runs on with the first joint's u to its far fibre (`crease`: that
	# fibre's point and its u seen from before), and the stretch past it starts with its own.
	if head >= 0 and tail < count and is_inf(best):
		turn = tail - 1
		crease = Vector2(float(tail), us[tail] + shift_head)
	for i in count:
		if i <= head or i >= tail:
			us[i] = border.pin_u[i]
		elif head >= 0 and i <= turn:
			us[i] += shift_head
		else:
			us[i] += shift_tail
	us[count] = us[count - 1]
	return crease


## u at `at` (a point on the border) from the u of its points (`us`).
static func _u_at(points: PackedVector2Array, us: PackedFloat32Array, at: Vector2) -> float:
	var best := INF
	var out := us[0]
	for i in points.size() - 1:
		var along := points[i + 1] - points[i]
		var t := clampf((at - points[i]).dot(along) / maxf(along.length_squared(), 1e-6), 0.0, 1.0)
		var distance := at.distance_squared_to(points[i] + along * t)
		if distance < best:
			best = distance
			out = lerpf(us[i], us[i + 1], t)
	return out


## A chain's shape for collision (`_add_shape`), terrace joints or not: the walls collide as they did
## before the joints were drawn (2026-11-11). A higher wall's stretch cut for a joint counts down to
## its own foot (what hangs below is still its wall), and the terrace's chain counts without the
## stretch of that wall it draws: it ends at the wall, its side straight up to it.
func _add_chain_shape(border: Border, foots: PackedVector2Array, depths: PackedFloat32Array, fibres: PackedVector2Array,
		loop: bool, level: float) -> void:
	var count := border.points.size()
	var cut := false
	var virtual := false
	for i in count:
		cut = cut or border.cut[i] == 1
		virtual = virtual or border.virtual[i] == 1
	if not cut and not virtual:
		_add_shape(border, foots, depths, fibres, loop, level)
		return
	var shape_foots := foots.duplicate()
	var shape_depths := depths.duplicate()
	var shape_fibres := fibres.duplicate()
	for i in count:
		if border.cut[i] == 1 and border.corner[i] < 0:
			var whole := reach(border.normals[i], border.drop[i])
			shape_foots[i] = foots[i] + whole - fibres[i]
			shape_fibres[i] = whole
			shape_depths[i] = border.drop[i]
	if not virtual:
		_add_shape(border, shape_foots, shape_depths, shape_fibres, loop, level)
		return
	# The joints' corners: the one the chain starts with (a west side), the one it ends with.
	var from := 0
	var to := count
	var head := Vector2.INF
	var tail := Vector2.INF
	for corner: Dictionary in border.corners:
		if not bool(corner.get("joint", false)):
			continue
		var first := int(corner["first"])
		var last := int(corner["last"])
		if border.virtual[0] == 1 and head == Vector2.INF and last + 1 < count and border.virtual[last + 1] == 0:
			from = last + 1
			head = corner["vertex"]
		elif border.virtual[count - 1] == 1 and first > 0 and border.virtual[first - 1] == 0:
			to = first
			tail = corner["vertex"]
	if to - from < 2:
		return
	var part := Border.new()
	var part_foots := PackedVector2Array()
	var part_depths := PackedFloat32Array()
	var part_fibres := PackedVector2Array()
	# Each kept point (`slot`: its index, placed at `point`) as a plain side's near a joint: the fold
	# there slants its fibres to the corner.
	var slots: Array = []
	if head != Vector2.INF:
		slots.append([from, head])
	for i in range(from, to):
		slots.append([i, border.points[i]])
	if tail != Vector2.INF:
		slots.append([to - 1, tail])
	for slot: Array in slots:
		var i := int(slot[0])
		var point: Vector2 = slot[1]
		var span := FRONT * border.shown[i] + FOLD_RUN + 1.0
		var near := (head != Vector2.INF and point.distance_to(head) < span) or (tail != Vector2.INF and point.distance_to(tail) < span)
		var fibre := reach(border.normals[i], border.shown[i]) if near else shape_fibres[i]
		part.points.append(point)
		part.drop.append(border.drop[i])
		part_foots.append(point + fibre if near else shape_foots[i])
		part_depths.append(border.shown[i] if near else shape_depths[i])
		part_fibres.append(fibre)
	var offset := (1 if head != Vector2.INF else 0) - from
	for corner: Dictionary in border.corners:
		if bool(corner.get("joint", false)) or int(corner["first"]) < from or int(corner["last"]) >= to:
			continue
		var moved := corner.duplicate()
		moved["first"] = int(corner["first"]) + offset
		moved["last"] = int(corner["last"]) + offset
		part.corners.append(moved)
	_add_shape(part, part_foots, part_depths, part_fibres, false, level)


# --- the drop of an edge ------------------------------------------------------------------

## [drop (levels), visible depth (levels: a wall something stands in front of ends early), has a
## foot] of a top's boundary edge.
func _edge_drop(edge: Dictionary) -> Array:
	var level := int(edge["level"])
	var across := int(edge["x"])
	# A terrace joint (`_with_terrace_joints`): the higher wall's lower courses hung from the terrace's
	# level, and that wall's own stretch above them (no foot: it ends on their top).
	if edge.has("twin"):
		return [float(edge["drop"]), float(edge["drop"]), true]
	if edge.has("cut"):
		var whole := float(edge["whole"])
		return [whole, minf(whole, float(edge["cut"]) + JOINT_TUCK), false]
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
	var against_wall := int(band["top"]) > level and not edge.has("joined")
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
		# A terrace joint (`_with_terrace_joints`).
		var virtual := edge.has("twin")
		var lift := float(edge.get("lift", 0.0))
		var raise := float(edge.get("raise", 0.0))
		var inset := float(edge.get("inset", 0.0))
		var narrow := float(edge.get("narrow", 1.0))
		var art_from := float(edge.get("art_from", 0.0))
		var trim := float(edge.get("trim", 0.0))
		var cut := edge.has("cut")
		var taper := over != NO_OVER and not virtual and not edge.has("joined")
		var u_from := NAN
		var u_to := NAN
		if virtual:
			u_from = float((edge["twin"] as Dictionary).get("u_from", NAN))
			u_to = float((edge["twin"] as Dictionary).get("u_to", NAN))
		if not runs.is_empty():
			var last: Dictionary = runs[runs.size() - 1]
			if (last["dir"] as Vector2).dot(dir) > 0.9999 and float(last["drop"]) == float(drop[0]) \
					and float(last["shown"]) == float(drop[1]) and bool(last["foot"]) == bool(drop[2]) \
					and float(last["rim"]) == rim and bool(last["water"]) == water and str(last["style"]) == style \
					and str(last["top_ground"]) == top_ground and str(last["low_ground"]) == low_ground \
					and int(last["over"]) == over and bool(last["virtual"]) == virtual and bool(last["cut"]) == cut \
					and bool(last["taper"]) == taper and float(last["lift"]) == lift and float(last["raise"]) == raise:
				last["to"] = to
				last["u_to"] = u_to
				continue
		runs.append({
			"from": from, "to": to, "dir": dir, "normal": Vector2(-dir.y, dir.x),
			"drop": float(drop[0]), "shown": float(drop[1]), "foot": bool(drop[2]), "rim": rim, "water": water,
			"style": style, "top_ground": top_ground, "low_ground": low_ground, "over": over,
			"virtual": virtual, "lift": lift, "raise": raise, "cut": cut, "taper": taper, "u_from": u_from, "u_to": u_to,
			"inset": inset, "narrow": narrow, "art_from": art_from, "trim": trim,
		})
	# A joint's stretch of a higher wall's side (`_with_front_joints`) lies `inset` out from that wall's
	# border, along its strip's foot line at the ledge's level, and the ledge's border starts there.
	for k in runs.size():
		var run: Dictionary = runs[k]
		if float(run["inset"]) <= 0.0:
			continue
		var shift := (run["normal"] as Vector2) * float(run["inset"])
		var joint_from: Vector2 = run["from"]
		var joint_to: Vector2 = run["to"]
		run["from"] = joint_from + shift
		run["to"] = joint_to + shift
		# (its u is the wall's along the whole of it, whatever becomes of the run)
		run["span_from"] = joint_from + shift
		run["span_to"] = joint_to + shift
		var ledge_after := k + 1 < runs.size() and float(runs[k + 1]["inset"]) <= 0.0 and (runs[k + 1]["from"] as Vector2).distance_to(joint_to) < 0.01
		if ledge_after:
			runs[k + 1]["from"] = joint_to + shift
		if k > 0 and float(runs[k - 1]["inset"]) <= 0.0 and (runs[k - 1]["to"] as Vector2).distance_to(joint_from) < 0.01:
			runs[k - 1]["to"] = joint_from + shift
		run["ledge_after"] = ledge_after
	# Where the wall turns right after such a stretch (`trim`: how far before the stretch's end that
	# corner's round begins), the wall's own chain draws the corner whole, with its foot: the stretch has
	# no foot over that last part (a run of its own, so a point lies where the foot ends).
	var out: Array[Dictionary] = []
	for run in runs:
		var trim := float(run.get("trim", 0.0))
		var length := (run["from"] as Vector2).distance_to(run["to"])
		if float(run["inset"]) <= 0.0 or trim <= 0.0 or trim >= length - 1.0:
			out.append(run)
			continue
		var footless := run.duplicate()
		footless["foot"] = false
		if bool(run["ledge_after"]):
			var at: Vector2 = (run["from"] as Vector2) + (run["dir"] as Vector2) * trim
			footless["to"] = at
			run["from"] = at
			out.append(footless)
			out.append(run)
		else:
			var at: Vector2 = (run["to"] as Vector2) - (run["dir"] as Vector2) * trim
			footless["from"] = at
			run["to"] = at
			out.append(run)
			out.append(footless)
	return out


## A terrace's foot shadow fades out over the last WALL_SHADOW_FADE units before its side runs up
## against a higher wall (`border.over`): it fell across that wall's own foot there (the owner,
## 2026-11-06: "mitigate this shadow and artifacts going to the other wall").
func _fade_shadow_near_walls(border: Border, shadow_scale: PackedFloat32Array) -> void:
	var count := border.points.size()
	var walls := PackedInt32Array()
	for i in count:
		if border.taper[i] == 1:
			walls.append(i)
	if walls.is_empty():
		return
	for k in count:
		if border.taper[k] == 1:
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
			if border.taper[i] == 0:
				break
			last = i
		if last < 0:
			continue
		var span := absf(along[last] - along[0 if at_start else count - 1])
		if span < 1.0:
			continue
		for step in count:
			var i := step if at_start else count - 1 - step
			if border.taper[i] == 0:
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
		# A terrace joint's corner (the terrace's edge meeting the higher wall's face) stays square.
		if bool(runs[i]["virtual"]) != bool(runs[j]["virtual"]):
			radius = RADIUS_JOINT
		var tangent := radius * tan(absf(turn) * 0.5)
		tangent = minf(tangent, 0.5 * minf(len_a, len_b))
		radius = tangent / tan(absf(turn) * 0.5)
		cut_end[i] = tangent
		cut_start[j] = tangent
		corner_of[i] = {"vertex": runs[i]["to"], "e_a": e_a, "e_b": e_b, "n_a": runs[i]["normal"],
				"n_b": runs[j]["normal"], "convex": convex, "back": back, "radius": radius, "tangent": tangent,
				"turn": turn, "fold": fold, "joint": bool(runs[i]["virtual"]) != bool(runs[j]["virtual"]),
				"narrow_a": float(runs[i]["narrow"]), "narrow_b": float(runs[j]["narrow"]),
				"drop_a": float(runs[j if bool(runs[i]["cut"]) and not bool(runs[j]["cut"]) else i]["shown"]),
				"drop_b": float(runs[i if bool(runs[j]["cut"]) and not bool(runs[i]["cut"]) else j]["shown"])}
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
		var span_from: Vector2 = run.get("span_from", from)
		var whole := span_from.distance_to(run.get("span_to", to))
		for k in range(0, last_index + 1):
			var point := start.lerp(finish, float(k) / steps)
			_add_point(border, point, run["normal"], run, run, 0.0, -1)
			# Along a terrace joint's stretch of the higher wall: that wall's u here.
			if bool(run["virtual"]) and not is_nan(float(run["u_from"])) and not is_nan(float(run["u_to"])) and whole > 0.0:
				border.pin_u[border.pin_u.size() - 1] = lerpf(float(run["u_from"]), float(run["u_to"]), span_from.distance_to(point) / whole)
		if corner_of.has(i):
			# A corner between a stretch whose wall a terrace joint hangs (`cut`) and the wall's own next
			# face is that face's all the way round: its wall laps over the joint's stretch there.
			var next_run: Dictionary = runs[(i + 1) % count]
			var from_run := run
			if bool(run["cut"]) != bool(next_run["cut"]) and float(run["raise"]) == 0.0 and float(next_run["raise"]) == 0.0:
				from_run = next_run if bool(run["cut"]) else run
				next_run = from_run
			_add_corner(border, corner_of[i], from_run, next_run)
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
	var nearer := a if t < 0.5 else b
	border.virtual.append(1 if bool(nearer["virtual"]) else 0)
	border.cut.append(1 if bool(nearer["cut"]) else 0)
	border.taper.append(1 if bool(nearer["taper"]) else 0)
	border.lift.append(lerpf(float(a["lift"]), float(b["lift"]), t))
	border.raise.append(lerpf(float(a["raise"]), float(b["raise"]), t))
	border.narrow.append(lerpf(float(a["narrow"]), float(b["narrow"]), t))
	border.inset.append(float(a["inset"]) if t < 0.5 else float(b["inset"]))
	border.art_from.append(lerpf(float(a["art_from"]), float(b["art_from"]), t))
	border.pin_u.append(NAN)
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
		var widest := side_width(maxf(float(corner["drop_a"]), float(corner["drop_b"])))
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
		fibres.append(fibre * border.narrow[i])
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
	# The most levels of a higher wall above any point of the chain (a terrace joint), at least 1.
	var joint_lift := 1.0
	for i in count:
		joint_lift = maxf(joint_lift, border.lift[i])
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
			# So too where a straight wall's height steps (a terrace below part of it): the taller wall's
			# measuring point lies far below the shorter one's, and by the distance between the two the
			# art jumped sideways at the step (a seam down the wall, until 2026-11-11).
			var stepped := border.corner[i] < 0 and border.corner[i - 1] < 0 and absf(border.shown[i] - border.shown[i - 1]) >= 0.5
			if stepped or (_on_back_corner(border, i, true) and _on_back_corner(border, i - 1, true)):
				var way := fibres[i] + fibres[i - 1]
				if way.length() > 0.01:
					var delta := middle - previous
					step = (delta - way.normalized() * delta.dot(way.normalized())).length()
			wall_length += step * (rates[i - 1] + rates[i]) * 0.5
		wall_along.append(wall_length)
		previous = middle
		# Outward only: an edge pulled in would leave a sliver of the top's square cells past it.
		# Along a terrace joint's line across a higher wall the wobbles are that wall's own border's
		# (`lift` levels up the screen), so its foot there is the foot the wall has beside it; and the
		# line itself stays straight, under the end of the courses above it.
		# (a joint's stretch of a higher wall's side lies `inset` out from that wall's border: its foot
		# is the foot that wall's own strip has beside it, and its line stays straight too)
		var wobble_at := p - Vector2(0.0, border.lift[i] * FRONT) - n * border.inset[i] + origin
		var top_shift := n * TOP_WOBBLE * (0.5 + 0.5 * _wobble(wobble_at))
		var top := p + top_shift * (1.0 - clampf(border.lift[i] / joint_lift, 0.0, 1.0)) * (0.0 if border.inset[i] > 0.0 else 1.0)
		tops.append(top)
		# The foot wobbles on its own, along its fibre, as much as there is wall to wobble (none on a
		# back edge); in a fold it lies on the fold's foot line (the wobbles there would push it back
		# and forth along that line).
		# None along a stretch whose lower part a joint hangs (`cut`): that part's line is straight, and
		# the wall's end must reach under it everywhere.
		var foot_wobble := FOOT_WOBBLE * minf(1.0, fibre.length() / FOOT_WOBBLE) * (0.0 if border.cut[i] == 1 else 1.0)
		var way := fibre.normalized() if fibre.length() > 0.01 else n
		var shift := top_shift + way * foot_wobble * _wobble(wobble_at + Vector2(311.0, 97.0))
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
	var us := PackedFloat32Array()
	for i in count + 1:
		if not pinned.is_empty():
			us.append(pinned[i])
		else:
			us.append(u_start + (wall_along[i] if i < count else wall_length) * 2.0 * wall_scale)
	# A terrace joint: along the higher wall's stretch its own u, the rest of the chain running on
	# from it; and that wall's chain notes its u along the stretches cut for a joint.
	var crease := _join_u(border, us, fibres)
	for edge in chain:
		if edge.has("cut"):
			edge["u_from"] = _u_at(points, us, (edge["from"] as Vector2) * cell)
			edge["u_to"] = _u_at(points, us, (edge["to"] as Vector2) * cell)
	# The art's courses alternate by level; a chain that hangs a higher wall's lower courses (a
	# terrace joint) counts them from that wall's top, so its art there is that wall's own.
	var course := float(posmod(int(level), 2)) * 128.0
	for i in count:
		if border.virtual[i] == 1:
			course = float(posmod(roundi(level + border.lift[i]), 2) + roundi(border.lift[i])) * 128.0
			break
	# How many pieces each fibre is cut into down its length: a course per half level beside a wall
	# that fans out (a corner), so the art bends smoothly there; else one. Both walls beside a fibre cut
	# it at the same points: one cut where the other is not leaves hairline cracks between them.
	var cuts := PackedInt32Array()
	cuts.resize(count)
	cuts.fill(1)
	# How much of a side's course each point's strip shows across its width: all of it, but along a
	# stretch whose lower part a joint hangs (`cut`) the share its width is of the whole strip's by the
	# stretch's end beside the wall's whole strip, growing from all of it at the other end (the strip
	# above the ledge, a whole course wide), so the stones run on at both ends.
	var spans := PackedFloat32Array()
	spans.resize(count)
	spans.fill(1.0)
	var at := 0
	while at < count:
		if border.cut[at] == 0 or border.corner[at] >= 0:
			at += 1
			continue
		var last := at
		while last + 1 < count and border.cut[last + 1] == 1 and border.corner[last + 1] < 0:
			last += 1
		var whole := reach(normals[at], border.drop[at]).length()
		var share := reach(normals[at], border.shown[at]).length() / whole if whole > 1e-3 else 1.0
		var full_before := at > 0 and border.shown[at - 1] > border.shown[at] + 0.5
		var full_after := last + 1 < count and border.shown[last + 1] > border.shown[last] + 0.5
		for k in range(at, last + 1):
			var t := float(k - at) / maxf(1.0, float(last - at))
			if full_before and not full_after:
				t = 1.0 - t
			elif full_before == full_after:
				t = 1.0
			spans[k] = lerpf(1.0, share, t)
		at = last + 1
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
		var u_i := us[i]
		var u_j := us[j] if j > 0 else us[count]
		if j == int(crease.x):
			u_j = crease.y
		var key := (points[i].y + points[j].y) * 0.5
		var foot_i := foots[i]
		var depth_i := depths[i]
		var foot_j := foots[j]
		var depth_j := depths[j]
		# Where a straight wall's height steps (a terrace below part of it), the piece across the step
		# hangs as deep as its first point at both ends: the taller wall starts or ends on a straight
		# edge at the step. Hung between the two depths it was a sheared sliver, a seam down the wall
		# (until 2026-11-11).
		if border.corner[i] < 0 and border.corner[j] < 0 and absf(border.shown[i] - border.shown[j]) >= 0.5 \
				and normals[i].dot(normals[j]) > 0.999 and depths[i] > 0.0 and depths[j] > 0.0:
			# (at the end of a stretch whose lower courses a terrace joint hangs, as deep as the deeper
			# one: the wall laps one piece over the joint's own, with the same art, so no hairline shows
			# between the two)
			# (the other point's own fibre, moved over: a side's reach does not grow evenly with its depth)
			if border.cut[i] != border.cut[j] and depths[j] > depths[i] and depths[i] > 0.5:
				foot_i = tops[i] + foots[j] - tops[j]
				depth_i = depths[j]
			else:
				foot_j = tops[j] + foots[i] - tops[i]
				depth_j = depths[i]
		_add_wall(pieces, key, tops[i], tops[j], foot_i, foot_j, u_i, u_j, depth_i, depth_j, course, level,
				lights[i], lights[j], sides[i], sides[j], cuts[i], cuts[j], border.lift[i], border.lift[j],
				border.raise[i], border.raise[j], Vector2(border.art_from[i], spans[i]), Vector2(border.art_from[j], spans[j]))
		(pieces[pieces.size() - 1] as Array).append(i)
	_add_corner_stones(pieces, border, tops, foots, depths, lights, loop, level)
	_add_chain_shape(border, foots, depths, fibres, loop, level)
	_add_corner_fills(pieces, border, level)
	_add_top_edge(pieces, border, tops, loop, level)
	# The feet without their wobble: the shadows are cut and laid by them (`_lay_shadows`).
	var bases := PackedVector2Array()
	for i in count:
		bases.append(points[i] + fibres[i])
	_add_foot(pieces, border, foots, depths, loop, level, foot_ns, tops, bases)
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
	_file_pieces(by_material, pieces, border)
	if not _shadows.is_empty() and _shadows[_shadows.size() - 1]["border"] == border:
		_shadows[_shadows.size() - 1]["by_material"] = by_material


## Files a chain's `pieces` by the material of the point each hangs from (its index: piece[4]).
static func _file_pieces(by_material: Dictionary, pieces: Array, border: Border) -> void:
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


## True when point `i` lies on the arc of a terrace joint's corner (`_with_terrace_joints`).
static func _on_joint_corner(border: Border, i: int) -> bool:
	var index := border.corner[i]
	return index >= 0 and bool(border.corners[index].get("joint", false))


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
## a side one a single course (`side0`, `side1`: how much each is a side's). `lift0`, `lift1`: the levels
## of wall above the fibres' tops (a terrace joint's line across a higher wall), `raise0`, `raise1`
## likewise along a joint's stretch of a higher wall's side; `across0`, `across1`: where the fibres' art
## starts across a side's course and how much of the rest it covers.
func _add_wall(pieces: Array, key: float, t0: Vector2, t1: Vector2, f0: Vector2, f1: Vector2, u0: float, u1: float,
		d0: float, d1: float, course: float, level: float, light0: float, light1: float, side0: float = 0.0,
		side1: float = 0.0, cuts0: int = 1, cuts1: int = 1, lift0: float = 0.0, lift1: float = 0.0,
		raise0: float = 0.0, raise1: float = 0.0, across0: Vector2 = Vector2(0.0, 1.0), across1: Vector2 = Vector2(0.0, 1.0)) -> void:
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
			# Across a side's course: from `across`.x of it, over `across`.y of what is left.
			var across := across1 if second else across0
			var over_side := (across.x + s * (1.0 - across.x)) * across.y
			verts.append(t1.lerp(f1, s) if second else t0.lerp(f0, s))
			uvs.append(Vector2(u1 if second else u0, course + lerpf(depth, over_side, side) * 128.0))
			# b: how far below the wall's top (the top edge's shadow): with what hangs above a joint's line.
			colors.append(Color(KIND_WALL + KIND_SIDE * side, light1 if second else light0,
					(depth + (lift1 if second else lift0) + (raise1 if second else raise0)) * 128.0 / 512.0,
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
		var front := reach(front_normal, float(corner["drop_a"] if front_first else corner["drop_b"])) \
				* float(corner.get("narrow_a" if front_first else "narrow_b", 1.0))
		var side := reach(side_normal, float(corner["drop_b"] if front_first else corner["drop_a"])) \
				* float(corner.get("narrow_b" if front_first else "narrow_a", 1.0))
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
		# (measured along the border from the arc's middle point: as distances from the corner's vertex
		# along the runs' straight lines, which is how the stretch itself is measured below)
		room_a += float(corner["tangent"]) - absf(along[middle] - along[int(corner["first"])])
		room_b += float(corner["tangent"]) - absf(along[int(corner["last"])] - along[middle])
		# A terrace joint's stretch of the higher wall ends on straight fibres (JOINT_STRAIGHT).
		if bool(corner.get("joint", false)):
			# (less where the stretch is short: the fold comes first)
			if int(corner["first"]) > 0 and border.virtual[int(corner["first"]) - 1] == 1:
				room_a -= clampf(room_a - fibre_b.length() - 8.0, 0.0, JOINT_STRAIGHT)
			if int(corner["last"]) + 1 < count and border.virtual[int(corner["last"]) + 1] == 1:
				room_b -= clampf(room_b - fibre_a.length() - 8.0, 0.0, JOINT_STRAIGHT)
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
			if d < -reach_a - FOLD_RUN or d > reach_b + FOLD_RUN:
				continue
			# How far along the two runs' straight lines the point lies from the corner's vertex (back
			# along the first run negative), not along the border's rounded arc: the fold's foot path is
			# measured along those lines, and by the arc's length the stretch ended a few units past the
			# next plain point's foot, so the foot line stepped back there and its shadow was drawn three
			# times over (a dark hairline, until 2026-11-11).
			if border.corner[i] >= 0 and border.corners[border.corner[i]] == corner:
				var tangent := float(corner["tangent"])
				var span := maxi(1, int(corner["last"]) - int(corner["first"]))
				d = lerpf(-tangent, tangent, float(i - int(corner["first"])) / span)
			elif d < 0.0:
				d = -(vertex - points[i]).dot(e_a)
			else:
				d = (points[i] - vertex).dot(e_b)
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
		# Nor into a stretch whose lower courses a terrace joint hangs, nor out of one: up to the last
		# point before it.
		if border.cut[i] != border.cut[from] and corner < 0:
			var d := absf(along[posmod(i - way, count)] - along[from])
			if loop:
				d = minf(d, length - d)
			return d
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
		outer.append(tops[i] + normals[i] * (EDGE_OUT if border.taper[i] == 0 else 0.0))
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
		# No top along a terrace joint's line across the higher wall's face, nor round its corner.
		if border.virtual[i] == 1 or border.virtual[j] == 1 or _on_joint_corner(border, i) or _on_joint_corner(border, j):
			continue
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
		foot_ns: PackedVector2Array = PackedVector2Array(), tops: PackedVector2Array = PackedVector2Array(),
		bases: PackedVector2Array = PackedVector2Array()) -> void:
	var points := border.points
	# The border's normals, or the feet's own (`_open_corners`): a back edge's or a side's foot.
	var normals := foot_ns if foot_ns.size() == border.normals.size() else border.normals
	var has_foot := border.foot.duplicate()
	var count := points.size()
	var segments := count if loop else count - 1
	if bases.size() != count:
		bases = foots
	# Where a wall meets a stretch with no foot of its own (a terrace joint: what is below hangs from
	# the terrace's chain from there on), the wall's foot runs on to the stretch's first point; else it
	# ended one point short of it, a gap in the foot and its shadow (a bare square of ground where a
	# strip standing on a ledge reaches the ledge's edge).
	foots = foots.duplicate()
	bases = bases.duplicate()
	depths = depths.duplicate()
	if tops.size() == count:
		# (`near`: the point with a foot, `far`: the stretch's first point, taking that foot on; found
		# first and set after, so the foot runs on one point only)
		var onward: Array[Vector2i] = []
		for i in segments:
			var j := (i + 1) % count
			var joint_step := border.cut[i] != border.cut[j] or (border.virtual[i] == 1 and border.virtual[j] == 1)
			if border.corner[i] >= 0 or border.corner[j] >= 0 or not joint_step or (has_foot[i] > 0.5) == (has_foot[j] > 0.5):
				continue
			onward.append(Vector2i(i, j) if has_foot[i] > 0.5 else Vector2i(j, i))
		for pair: Vector2i in onward:
			foots[pair.y] = tops[pair.y] + foots[pair.x] - tops[pair.x]
			bases[pair.y] = points[pair.y] + bases[pair.x] - points[pair.x]
			depths[pair.y] = depths[pair.x]
			has_foot[pair.y] = 1.0
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
		drawn[i] = 0 if hidden else 1
	var foot_normals := _line_normals(foots, normals, loop, drawn)
	var foot_along := PackedFloat32Array()
	var length := 0.0
	for i in count:
		if i > 0:
			length += foots[i - 1].distance_to(foots[i])
		foot_along.append(length)
	if loop:
		length += foots[count - 1].distance_to(foots[0])
	foot_along = _seed_along(points, foot_along, length, loop)
	length = foot_along[count]
	foot_along.resize(count)
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
		# (with what hangs above a terrace joint's line: the wall is that tall there)
		shadow_lengths.append(FOOT_OUT + SHADOW_PER_LEVEL * (depths[k] + border.lift[k] + border.raise[k]) * facing)
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
	# The shadows run out from the feet without their wobble (`bases`): by the wobbled line every dent
	# of it would notch them where they are cut (`_lay_shadows`).
	# Their ways are the line's own normals over a short span (SHADOW_SPAN): over FOOT_SPAN the ways
	# turned over four or five feet at a sharp turn of the foot line, so those fibres crossed their own
	# wall's short of where the two walls' fibres meet and left a pocket of bare ground behind them.
	var shadow_ns := _line_normals(bases, PackedVector2Array(), loop, drawn, SHADOW_SPAN)
	var runs := _shadow_runs(drawn, foots, loop)
	for run: Dictionary in runs:
		_smooth_shadow(run, bases, shadow_lengths, strengths)
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
	# The strip up the wall, per stretch of foot. Stretches a hair long (a corner's finely cut arc lays
	# many points that close) are joined into one from the first of them, while the strip leans the
	# same way: left out one by one, as until 2026-11-11, they added up to a gap across the strip (a
	# light wedge at a fold's corner). Where it does not (two walls' feet meeting in one point:
	# `_meet_feet`) they are left out.
	var from := -1
	for segment in segments:
		var j := (segment + 1) % count
		if drawn[segment] == 0:
			from = -1
			continue
		if from < 0:
			from = segment
		var i := from
		if foots[i].distance_to(foots[j]) < 0.25:
			if foot_normals[i].dot(foot_normals[j]) < 0.9 or segment + 1 >= segments or drawn[segment + 1] == 0:
				from = -1
			continue
		from = j
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
	# The shadows themselves are laid once every chain's feet are known (`_lay_shadows`).
	var floors := PackedInt32Array()
	var darks := PackedFloat32Array()
	for k in count:
		floors.append(roundi(level - border.drop[k]))
		darks.append(strengths[k] * shadow_scale[k])
	_shadows.append({
		"border": border, "by_material": {}, "points": points, "foots": foots, "bases": bases, "ways": shadow_ns,
		"fulls": shadow_lengths, "darks": darks, "floors": floors, "runs": runs,
		"colours": shadow_colours, "along": foot_along, "length": length,
	})


## Lays every chain's foot shadows (`_shadows`, from `_add_foot`), now that all the feet are known, so
## that each is drawn once everywhere (translucent, a shadow drawn twice darkens) and shadows that
## meet are as dark on both sides of the line between them. A shadow runs out from its foot along
## the foot's normal (a "fibre") as far as the wall is tall, fading.
## - Each fibre ends where another foot on the same floor is as near as its own: another stretch of
##   its own chain's foot (round an inner corner, where the foot turns in tighter than the shadow is
##   long) or another chain's (two hills across a narrow way, a terrace's side beside the wall it
##   stands against). So the fibres tile the ground between the feet: every spot is drawn by the fibre
##   of its nearest foot, with no overlap and no gap. A fibre shorter than the way to that line runs on
##   to it where the other foot's shadow still reaches there.
## - Along a fibre the shadow is its own foot's up to where another wall's would be darker
##   (`_darkest`: of every other foot whose shadow reaches there, by the distance from it), and that
##   wall's from there to the fibre's end. So every spot shows the darkest of all the shadows that
##   reach it, whichever fibre draws it: a tall wall's long shadow runs on under a low wall's short
##   one, across the line between them and across a third wall's ground too.
## - A fibre that would meet another foot from behind (that foot's wall stands between: a wall that
##   ends against this one, a lower hill seen from its back) has no ground of that foot's to share:
##   its shadow fades out over what is left of it, so it lies soft over the end of that wall.
## - Feet bunched within SHADOW_BUNCH of each other (a corner's finely cut arc, folded onto one spot
##   of the foot) cast one fibre, the first one's, and two neighbouring fibres that still cross are
##   both ended where they do.
## One ring per run: from the foot to where the shadow turns, and on to its far edge.
## Until 2026-11-11 each chain shaped its own shadows, turning crossing fibres towards each other in
## up to 400 passes: round a deep corner that left fans of overlapping slivers (black hairlines,
## desert-b7), and two chains' shadows lay over each other.
func _lay_shadows() -> void:
	var longest := 1.0
	for record in _shadows:
		for run: Dictionary in record["runs"]:
			for k: int in run["points"]:
				longest = maxf(longest, (record["fulls"] as PackedFloat32Array)[k])
	# Every shadowed foot (where it lies, its way, its shadow's reach and strength), and their numbers
	# by floor and square.
	var feet := PackedVector2Array()
	var feet_way := PackedVector2Array()
	var feet_reach := PackedFloat32Array()
	var feet_dark := PackedFloat32Array()
	var squares := {}
	for index in _shadows.size():
		var record := _shadows[index]
		var bases: PackedVector2Array = record["bases"]
		var floors: PackedInt32Array = record["floors"]
		var numbers := PackedInt32Array()
		numbers.resize(bases.size())
		numbers.fill(-1)
		for run: Dictionary in record["runs"]:
			for k: int in run["points"]:
				if numbers[k] >= 0:
					continue
				numbers[k] = feet.size()
				var square := Vector3i(floors[k], floori(bases[k].x / longest), floori(bases[k].y / longest))
				if not squares.has(square):
					squares[square] = []
				(squares[square] as Array).append(feet.size())
				feet.append(bases[k])
				feet_way.append((record["ways"] as PackedVector2Array)[k])
				feet_reach.append((record["fulls"] as PackedFloat32Array)[k])
				feet_dark.append((record["darks"] as PackedFloat32Array)[k])
		record["numbers"] = numbers
	# How far each fibre runs.
	for index in _shadows.size():
		var record := _shadows[index]
		var bases: PackedVector2Array = record["bases"]
		var ways: PackedVector2Array = record["ways"]
		var fulls: PackedFloat32Array = record["fulls"]
		var floors: PackedInt32Array = record["floors"]
		var numbers: PackedInt32Array = record["numbers"]
		var lengths := fulls.duplicate()
		for run: Dictionary in record["runs"]:
			var run_points: Array[int] = run["points"]
			var n := run_points.size()
			var firsts := PackedInt32Array()
			for m in n:
				var first := run_points[m]
				if m > 0 and bases[run_points[m]].distance_to(bases[firsts[m - 1]]) < SHADOW_BUNCH:
					first = firsts[m - 1]
				firsts.append(first)
			run["firsts"] = firsts
			for m in n:
				var k := run_points[m]
				if firsts[m] != k:
					continue
				# (no further than any shadow reaches)
				var best := longest
				var behind := INF
				var base := bases[k]
				var way := ways[k]
				var found := false
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						var square := Vector3i(floors[k], floori(base.x / longest) + dx, floori(base.y / longest) + dy)
						for other: int in squares.get(square, []):
							var gap := feet[other] - base
							var ahead := gap.dot(way)
							if ahead <= 0.0:
								continue
							var apart_squared := gap.length_squared()
							# Not by a foot beside the fibre's own (a straight stretch: the two never meet),
							# nor by its nearest neighbours (the foot line is a polyline: their cut swings
							# with every kink of it).
							if apart_squared < SHADOW_CUT_NEAR * SHADOW_CUT_NEAR or ahead * ahead <= SHADOW_CUT_MIN * SHADOW_CUT_MIN * apart_squared:
								continue
							var met := apart_squared / (2.0 * ahead)
							if (way * met - gap).dot(feet_way[other]) <= 0.0:
								# The two meet behind that foot (its wall stands between): no ground of that
								# foot's to share, but the fibre's shadow fades out by there (`behind`).
								if met < fulls[k]:
									behind = minf(behind, met)
							elif met < best and (met < fulls[k] or met < SHADOW_FADE * feet_reach[other]):
								# Only a foot whose line the fibre's own shadow reaches, or that foot's: the
								# fibre ends there, running on to it where it is the shorter one.
								best = met
								found = true
				if found:
					lengths[k] = best
				# Ended behind another foot before any line: squeezed, the whole fade over what is left.
				if behind < lengths[k]:
					lengths[k] = behind
					fulls[k] = minf(fulls[k], behind)
					feet_reach[numbers[k]] = fulls[k]
			var pairs := n if bool(run["closed"]) else n - 1
			for pass_index in 8:
				var changed := false
				for m in pairs:
					var i := firsts[m]
					var j := firsts[(m + 1) % n]
					if i == j:
						continue
					var gap := bases[j] - bases[i]
					var det := ways[i].cross(ways[j])
					if absf(det) < 1e-5:
						continue
					var s_i := gap.cross(ways[j]) / det
					var s_j := gap.cross(ways[i]) / det
					if s_i > 0.0 and s_j > 0.0 and s_i < lengths[i] - 0.5 and s_j < lengths[j] - 0.5:
						lengths[i] = s_i
						lengths[j] = s_j
						changed = true
				if not changed:
					break
		record["lengths"] = lengths
	# What each fibre shows, and the rings.
	for index in _shadows.size():
		var record := _shadows[index]
		var border: Border = record["border"]
		var points: PackedVector2Array = record["points"]
		var foots: PackedVector2Array = record["foots"]
		var bases: PackedVector2Array = record["bases"]
		var ways: PackedVector2Array = record["ways"]
		var fulls: PackedFloat32Array = record["fulls"]
		var darks: PackedFloat32Array = record["darks"]
		var floors: PackedInt32Array = record["floors"]
		var colours: PackedColorArray = record["colours"]
		var along: PackedFloat32Array = record["along"]
		var lengths: PackedFloat32Array = record["lengths"]
		var numbers: PackedInt32Array = record["numbers"]
		var count := points.size()
		# Per point: where its shadow turns to another wall's, and that shadow's v and strength at the
		# turn and at the far end (its own where it does not turn).
		var turns := lengths.duplicate()
		var turn_vs := PackedFloat32Array()
		var turn_darks := darks.duplicate()
		var far_vs := PackedFloat32Array()
		var far_darks := darks.duplicate()
		turn_vs.resize(count)
		far_vs.resize(count)
		var pieces: Array = []
		for run: Dictionary in record["runs"]:
			var run_points: Array[int] = run["points"]
			var n := run_points.size()
			var firsts: PackedInt32Array = run["firsts"]
			for m in n:
				var k := run_points[m]
				if firsts[m] != k:
					continue
				turn_vs[k] = FOOT_OUT * lengths[k] / maxf(fulls[k], 1e-3)
				far_vs[k] = turn_vs[k]
				if lengths[k] < 0.5 or darks[k] < 0.001:
					continue
				# The other feet whose shadows reach the fibre.
				var base := bases[k]
				var way := ways[k]
				var near := PackedInt32Array()
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						var square := Vector3i(floors[k], floori(base.x / longest) + dx, floori(base.y / longest) + dy)
						for other: int in squares.get(square, []):
							var apart_squared := (feet[other] - base).length_squared()
							var within := lengths[k] + feet_reach[other]
							if other != numbers[k] and apart_squared >= SHADOW_CUT_NEAR * SHADOW_CUT_NEAR and apart_squared < within * within:
								near.append(other)
				if near.is_empty():
					continue
				# Where another wall's shadow is darker than its own at the fibre's end, the fibre shows
				# that shadow from where the two are as dark (the other gains on it along the fibre).
				var end := _darkest(base + way * lengths[k], near, feet, feet_way, feet_reach, feet_dark)
				if end.x <= _shadow_at(lengths[k], fulls[k], darks[k]) + 0.002:
					continue
				var from := 0.0
				var to := lengths[k]
				if _darkest(base, near, feet, feet_way, feet_reach, feet_dark).x > darks[k] + 0.002:
					to = 0.0
				else:
					for pass_index in 7:
						var middle := (from + to) * 0.5
						if _darkest(base + way * middle, near, feet, feet_way, feet_reach, feet_dark).x \
								> _shadow_at(middle, fulls[k], darks[k]) + 0.002:
							to = middle
						else:
							from = middle
				var turn := _darkest(base + way * to, near, feet, feet_way, feet_reach, feet_dark)
				if turn.y < 0.0:
					continue
				turns[k] = to
				var turn_foot := int(turn.y)
				turn_vs[k] = FOOT_OUT * (base + way * to).distance_to(feet[turn_foot]) / maxf(feet_reach[turn_foot], 1e-3)
				turn_darks[k] = feet_dark[turn_foot]
				var end_foot := int(end.y)
				far_vs[k] = FOOT_OUT * (base + way * lengths[k]).distance_to(feet[end_foot]) / maxf(feet_reach[end_foot], 1e-3)
				far_darks[k] = feet_dark[end_foot]
			var pairs := n if bool(run["closed"]) else n - 1
			# (stretches a hair long, between feet that cast one fibre, are joined into one from the first
			# of them: left out one by one they added up to a gap, a light wedge at a fold's corner)
			var from_m := 0
			for m in pairs:
				var to_m := (m + 1) % n
				var i := run_points[from_m]
				var j := run_points[to_m]
				var cast_i := firsts[from_m]
				var cast_j := firsts[to_m]
				var turn_i := bases[cast_i] + ways[cast_i] * turns[cast_i]
				var turn_j := bases[cast_j] + ways[cast_j] * turns[cast_j]
				var far_i := bases[cast_i] + ways[cast_i] * lengths[cast_i]
				var far_j := bases[cast_j] + ways[cast_j] * lengths[cast_j]
				if m < pairs - 1 and cast_i == cast_j and foots[i].distance_to(foots[j]) < 0.25:
					continue
				from_m = to_m
				var u_i := along[i]
				var u_j := along[j] if j > 0 else float(record["length"])
				# Over the foot's strip (`_add_foot`), its neighbours' too: a strip leans with its foot line,
				# and where the next stretch's strip leaned over this one's shadow it was drawn after it, a
				# light sliver across the shadowed strip at every point (streaks where a fold starts and
				# wherever the foot wobbles, until 2026-11-11).
				var key := (points[i].y + points[j].y) * 0.5 + FOOT_LEAD + SHADOW_LEAD
				# Its own shadow, from the foot to the turn: past the foot the art's rows run over the
				# shadow's whole length (FOOT_OUT of them), a fibre cut short ending on the row it reached.
				var own_i := FOOT_OUT * turns[cast_i] / maxf(fulls[cast_i], 1e-3)
				var own_j := FOOT_OUT * turns[cast_j] / maxf(fulls[cast_j], 1e-3)
				if foots[i].distance_to(foots[j]) >= 0.25 or turn_i.distance_to(turn_j) >= 0.25:
					var verts := PackedVector2Array()
					var uvs := PackedVector2Array()
					var colors := PackedColorArray()
					var ring := [[i, foots[i], Vector2(u_i, 0.0)], [j, foots[j], Vector2(u_j, 0.0)],
							[j, turn_j, Vector2(u_j, own_j)], [i, turn_i, Vector2(u_i, own_i)]]
					for corner_index: int in [0, 1, 2, 0, 2, 3]:
						var corner: Array = ring[corner_index]
						verts.append(corner[1])
						uvs.append(corner[2])
						colors.append(colours[int(corner[0])])
					pieces.append([key, verts, uvs, colors, i])
				# Another wall's shadow, from the turn to the far edge.
				if turn_i.distance_to(far_i) >= 0.25 or turn_j.distance_to(far_j) >= 0.25:
					var verts := PackedVector2Array()
					var uvs := PackedVector2Array()
					var colors := PackedColorArray()
					# (a fibre that does not turn goes on as its own shadow did)
					var turned_i := turns[cast_i] < lengths[cast_i]
					var turned_j := turns[cast_j] < lengths[cast_j]
					var near_i := colours[i]
					var near_j := colours[j]
					var end_i := colours[i]
					var end_j := colours[j]
					near_i.g = turn_darks[cast_i] if turned_i else colours[cast_i].g
					near_j.g = turn_darks[cast_j] if turned_j else colours[cast_j].g
					end_i.g = far_darks[cast_i] if turned_i else colours[cast_i].g
					end_j.g = far_darks[cast_j] if turned_j else colours[cast_j].g
					var ring := [[near_i, turn_i, Vector2(u_i, turn_vs[cast_i] if turned_i else own_i)],
							[near_j, turn_j, Vector2(u_j, turn_vs[cast_j] if turned_j else own_j)],
							[end_j, far_j, Vector2(u_j, far_vs[cast_j] if turned_j else own_j)],
							[end_i, far_i, Vector2(u_i, far_vs[cast_i] if turned_i else own_i)]]
					for corner_index: int in [0, 1, 2, 0, 2, 3]:
						var corner: Array = ring[corner_index]
						verts.append(corner[1])
						uvs.append(corner[2])
						colors.append(corner[0])
					pieces.append([key, verts, uvs, colors, i])
		_file_pieces(record["by_material"], pieces, border)
	_shadows.clear()


## The darkest shadow the feet `near` (numbers into `feet`, their ways, reaches and strengths) cast at
## `point`: Vector2(how dark, the foot's number; 0 and -1 where none reaches it). A foot's shadow falls
## on its own side only (ahead of its way), as dark as the distance from the foot makes it.
static func _darkest(point: Vector2, near: PackedInt32Array, feet: PackedVector2Array, feet_way: PackedVector2Array,
		feet_reach: PackedFloat32Array, feet_dark: PackedFloat32Array) -> Vector2:
	var best := 0.0
	var by := -1
	for other: int in near:
		var out := point - feet[other]
		if out.dot(feet_way[other]) <= 0.0:
			continue
		var dark := _shadow_at(out.length(), feet_reach[other], feet_dark[other])
		if dark > best:
			best = dark
			by = other
	return Vector2(best, float(by))


## How dark a shadow `reach` long and `dark` strong at its foot is `distance` from the foot (as the
## shader fades it: elevation_sides.gdshader).
static func _shadow_at(distance: float, reach: float, dark: float) -> float:
	return dark * (1.0 - smoothstep(0.0, SHADOW_FADE * reach, distance))


## One run's shadow (`_shadow_runs`): its lengths and strengths averaged along the foot (`foots`: the
## feet without their wobble) over SHADOW_SMOOTH either way, so two walls that meet at a corner cast
## shadows that turn from one's length and strength to the other's round it.
static func _smooth_shadow(run: Dictionary, foots: PackedVector2Array, lengths: PackedFloat32Array,
		strengths: PackedFloat32Array) -> void:
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


## The outward normal of `line` (a foot line) at each of its points, from neighbours at least `span`
## apart (points bunch up where a fold's fibres crowd its foot corner, and close neighbours would make
## a strip's sweep jitter), never looking past a stretch that is not drawn (`drawn`, per stretch
## between two points; all when empty): past a step in the wall's height the foot lies elsewhere. The
## border's normal (`normals`, when given) where the line folds back on itself (fibres crossing at an
## inner corner).
static func _line_normals(line: PackedVector2Array, normals: PackedVector2Array, loop: bool,
		drawn: PackedByteArray = PackedByteArray(), span: float = FOOT_SPAN) -> PackedVector2Array:
	var count := line.size()
	var out := PackedVector2Array()
	for i in count:
		var before := i
		var after := i
		for step in count:
			var b := before - 1
			if b < 0:
				if not loop:
					break
				b += count
			if not drawn.is_empty() and b < drawn.size() and drawn[b] == 0:
				break
			before = b
			if line[before].distance_to(line[i]) >= span:
				break
		for step in count:
			var a := after + 1
			if a >= count:
				if not loop:
					break
				a -= count
			if not drawn.is_empty() and after < drawn.size() and drawn[after] == 0:
				break
			after = a
			if line[after].distance_to(line[i]) >= span:
				break
		var tangent := line[after] - line[before]
		# Alone between two stretches that are not drawn: as its neighbours along the whole line lie.
		if tangent.length() < 0.01:
			tangent = line[mini(i + 1, count - 1)] - line[maxi(i - 1, 0)]
		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		if not normals.is_empty() and normal.dot(normals[i]) < 0.2:
			normal = normals[i]
		out.append(normal)
	return out


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
	return LevelCode.of(level)
