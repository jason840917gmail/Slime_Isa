@tool
extends "res://game/world/elevation/elevation_stairs.gd"
## A ramp (docs/godot/ELEVATION.md "Ramps"): sloped ground that joins a higher top to the ground
## below it with no steps, as A Link to the Past joins its levels: beside a ramp the cliff wall
## shows only the height left between the top and the slope, so it tapers to nothing where the
## ramp reaches the top, on a straight face or a 45° one.
##
## A flight of stairs without its stone (elevation_stairs.gd, the same frame: s along its direction
## D down the slope from its top end, t across, h up from the lower ground; drawn at (x, y − H), depth
## = ground y): a smooth surface, `nosing` its height, from the top level at s = 0 to the bottom
## level at s = `ramp` (its length, from the painted cells). Elevation finds a ramp's top end and
## level (`_make_ramp`): the rim of the top right behind its top cells (a ramp leaving a rim, like
## stairs), else the face of a top beside them (a ramp running along a wall): then its `near` side
## lies on that wall's foot, its top end where the wall begins (a tip), its bottom end where the
## face turns into another face of the top (a 45° arm meeting the main wall), and the wall's
## visible part is the top's height minus the slope's (`face_from` … `face_to`).
##
## An open end (`opens`, the owner's rule of 2026-10-11): a free top end where the face begins and
## the top ends (a ridge's or an arm's tip, a face's end) is where the cliff opens, the wall coming
## down to meet the ground instead of turning a corner and closing the shape. There the wall tapers
## to nothing with no corner stones (Elevation leaves them out under any ramp), the top's rim does
## not turn around the end (`closes`: Elevation leaves those edges out of the strip), the cap covers
## the ends of the lip and the rim with ground and fades out, and no shadow falls beyond the end
## (`shadow_take`). At a plateau's corner (its side runs on past the top end) the rim and the
## shadow stay. A one-row open cliff (Elevation `_open_tops`) has no back rim and casts no shadow,
## and its ramps take none (`no_shadow`).
##
## What it changes:
##   `walk`     the surface on screen, walkable by every level it joins, except its high end (s <
##              `high_end`), which only the top level walks; a body there takes the level of its
##              height (`level_at`) and its depth (`depth_at`). Along the near side, where the face
##              left between the slope and the top is lower than JOIN_HEIGHT (at least JOIN_MIN
##              along the slope), the walk reaches over it to the top's edge: the ramp and the top
##              are one there. A free top end (one not against a rim) is the top's rim carried on:
##              the top level is held there and drops over it, lower levels meet it as a wall. A
##              straight front ramp's sides are cut at 45° where they meet the foot of the wall it
##              cuts through (FOOT_EAR), so a body overhanging a side slides onto the slope.
##   `sides`    the long open sides that face no camera (both sides of a front or back ramp): strips
##              SOFT_MARGIN wide past the slope's edge, their start cut at 45° from its top corner.
##              There is no railing or face (the illusion of one ground): a body of a level above
##              the bottom may step off onto ground of a level from the bottom up to its own
##              (`lets_off`, Elevation decides with the terrain), and takes that ground's level once
##              its feet leave the slope. They never open the top's own rims. A rimmed ramp's top
##              corners also reach EAR over the rim (`walk`): a body overhanging the slope slides
##              onto it there.
##   `skirt`    the sides facing the camera, from the slope's edge down to the ground: ground of the
##              bottom level (`skirts`; a body there takes that level). From `high_end` down
##              (`soft_skirt`) a body on the slope steps off onto it (its open side); above, the
##              levels over the bottom meet it as a rim.
##   `face_zone` the tapered face's visible part: no ledge drop over it (it is a wall, as in Zelda).
##   drawing    the surface and the skirt with the lower ground's own sheet (elevation_ramp.gdshader,
##              with the cast shadows at its height), after the walls, feet and lips, so they cover
##              the wall below the slope, the lip's hanging part and the wall's old foot: the courses
##              of what shows are the wall's own. Along a face the slope's edge fades out over
##              EDGE_FADE, so the lip's hanging tufts and the stone end softly on it; at an open end
##              the cap (`_cap_triangles`, `add_cap_top`) covers the lip's and the rim's ends; a
##              rimmed ramp's landing (`add_landing`) covers the top's lip where the ramp leaves the
##              rim (it fades out at its sides), so the way down reads. Elevation lays a foot along
##              the slope's edge (`face_from` … `face_to`) and corner stones where a front ramp cuts a
##              wall. Into the depth map they go as ground of the bottom level marked as a ramp: they
##              hide nothing (the slope reads as flat ground) and cast no shadow, except over the
##              wall they cover, where they keep the slope's height there (`add_ramp_depth`): the
##              shadow beside them is as long as the slope is high, and the slope takes the shadows
##              of the face and the top beside it at its own height, so they grow with the face's
##              height from nothing at an open end. A body on the slope still takes its true depth
##              (`depth_at`), so the walls and tops around it hide it as they should.
## JOIN_HEIGHT, SOFT_MARGIN, END_BAND, the ears and the drawing's reaches are the ramp's geometry
## (what reads as one ground, how far a body overhangs an edge), like the stairs' steps, not tuning
## values.
## Coordinates are Elevation's (world units from the ground layer's origin).
##
## Owner: world (elevation).

const RampSelf := preload("res://game/world/elevation/elevation_ramp.gd")

## Where the face left between the slope and the top it runs beside is lower than this (world
## units), a body steps between them: the ramp joins that top there. The join reaches at least
## JOIN_MIN along the slope (s): a body (Elevation.BODY_HALF) crossing a 45° top edge needs about
## 36 units of it, and a steep ramp (one diagonal cell per level) has its face that low for less.
const JOIN_HEIGHT := 20.0
const JOIN_MIN := 44.0
## How far past the slope's open sides the levels it joins may walk (world units): a body leaving it
## crosses its side before its level changes to the ground's there. Also how far (on screen) the
## strips keep from the rim a rimmed ramp leaves.
const SOFT_MARGIN := 32.0
## The high end only the top level walks (s, world units): lower levels meet a free top end as a
## wall, and never step onto the slope's highest part from its side. It ends HIGH_END_MARGIN
## before the body's reach up the slope from where a body takes the top level (`level_at`), never
## shorter than HIGH_END_MIN: a body climbing a steep ramp is of the top level when it gets there.
const END_BAND := 32.0
const HIGH_END_MARGIN := 8.0
const HIGH_END_MIN := 8.0
## A rimmed ramp's top corners are cut off this far (on screen) over the rim beside them, so a
## body that overhangs the slope's side slides onto it instead of catching on the rim's corner.
const EAR := 16.0
## Where a straight front ramp cuts through the wall it leaves, the corner of that wall's foot and
## the slope's side is cut off this far (on screen, at 45°): a body walking up with its side over
## the ground beside the slope slides onto the slope instead of stopping at the wall's foot.
const FOOT_EAR := 18.0
## At an open end (`opens`), around the top end's corner on the face: the top's rim is left out
## where it would turn around the end (`closes`, edges whose middle lies within OPEN_REACH), and
## the cap covers the ends of the lip and the rim there with ground (world units): out to
## CAP_RADIUS from the corner, fading out over CAP_FADE further; from CAP_BEYOND beyond the top end
## (s at the top's height), fading out up to CAP_INTO along the slope. Where edges of the rim were
## left out (`cuts_rim`: a ridge's or an arm's tip) the strips end right at the top end: the cap is
## opaque up to CAP_SOLID along the slope, just past their ends, and fades out up to CAP_INTO_CUT,
## so they fade in from nothing instead of ending on a line. Drawn as a grid of CAP_CELL squares
## (the fade is per vertex).
const OPEN_REACH := 40.0
const CAP_RADIUS := 56.0
const CAP_FADE := 16.0
const CAP_BEYOND := 8.0
const CAP_INTO := 16.0
const CAP_SOLID := 4.0
const CAP_INTO_CUT := 40.0
const CAP_CELL := 12.0
## At an open end the cliff comes down to the ground: no shadow falls on the ground beyond the top
## end within OPEN_NEAR of its corner, all of it again OPEN_FADE down the slope and OPEN_FAR from
## the corner (world units; `shadow_take`). Beside the slope the shadows fade with the face's
## height by themselves (the slope takes them at its own height).
const OPEN_FADE := 48.0
const OPEN_NEAR := 64.0
const OPEN_FAR := 160.0
## Along a face, the slope's edge fades out over this (world units across it).
const EDGE_FADE := 10.0
## A rimmed ramp's landing: how far it reaches over the top (the lip's inner reach,
## elevation_rims.gd IN) and how far its sides fade out (world units).
const LANDING_DEPTH := 48.0
const LANDING_FADE := 14.0

## The side along a face: −1 or 1 (the sign of t), 0 without.
var near := 0.0
## The stretch of s along which the near side runs at a face (its foot follows the slope there).
var face_from := 0.0
var face_to := 0.0
## The s down to which only the top level walks the slope, and from which the open sides let a
## body off (`sides`).
var high_end := END_BAND
## The surface as drawn (screen), the strips past its open sides, and the tapered face's visible
## part.
var surface := PackedVector2Array()
var sides: Array[PackedVector2Array] = []
var face_zone := PackedVector2Array()
## The sides of the slope that face the camera (screen), from its edge down to the ground: drawn as
## ground too and walked as the bottom level's ground, so the slope seems to meet the ground in front
## (a ramp rising higher than it is wide covers the lower courses of the wall there). Its part from
## `high_end` down (`soft_skirt`) is where a body on the slope steps off onto it; higher up the
## levels above the bottom meet it as a rim.
var skirt: Array[PackedVector2Array] = []
var soft_skirt: Array[PackedVector2Array] = []
## `ground_name` (ElevationStairs) is the lower ground the ramp is made of (its sheet draws the
## surface; its foot runs along the face), `top_ground` the top's (a rimmed ramp's landing, an open
## end's cap over the top).
## True when the top it leads to lies right behind its top end (a rim): that end stands against it.
var rimmed := false
## True when the top it joins is a one-row open cliff (Elevation `_open_tops`): its slope and cap
## take no cast shadow.
var no_shadow := false
## True when its top end lies where the face beside it begins (a tip or a corner of the top), and
## when the top ends there too (no top beyond its top end around that corner: a ridge's or an arm's
## tip, not a plateau's corner; Elevation `_top_ends_at`): the cliff opens there (`opens`).
var at_face_end := false
var top_ends := false
## Where a straight front ramp cuts through a wall: the slope's s level with that wall's foot
## (`FOOT_EAR`), 0 otherwise.
var foot_cut := 0.0
## True when Elevation left edges of the top's rim out at this open end (`closes`): the strips end
## at the top end, and the cap fades them in over a longer stretch (CAP_INTO_CUT).
var cuts_rim := false
## An open end's cap (screen): the square around the top end's corner its grid covers (empty
## without one). Drawn as ground over the lip's and the rim's ends there (`_cap_alpha`), the top's
## own ground where it covers the top (`add_cap_top`).
var cap_rect := Rect2()


## A ramp whose top end's middle lies at `base_point` (ground, world units: y + 64 · level) going
## down towards `direction_key` (DIRECTIONS) for `length` units, from `top_level` to
## `bottom_level`, `half_width` units each side of its middle; `near_side` (−1, 0, 1) runs along a
## face from s = `from_s` to `to_s`; `against_rim`: the top lies right behind its top end;
## `face_ends`: the face begins at the top end; `top_ends_there`: the top ends there too.
static func create_ramp(direction_key: String, base_point: Vector2, top_level: int, bottom_level: int, half_width: float,
		length: float, near_side: float, from_s: float, to_s: float, against_rim: bool = false, face_ends: bool = false,
		top_ends_there: bool = false) -> RampSelf:
	var ramp_of := RampSelf.new()
	var entry: Array = DIRECTIONS[direction_key]
	ramp_of.direction_name = direction_key
	ramp_of.dir = (entry[0] as Vector2).normalized()
	ramp_of.across = Vector2(-ramp_of.dir.y, ramp_of.dir.x)
	ramp_of.base = base_point
	ramp_of.rim = base_point - Vector2(0.0, LEVEL * top_level)
	ramp_of.top = top_level
	ramp_of.bottom = bottom_level
	ramp_of.half = half_width
	ramp_of.steps = 0
	ramp_of.ramp = maxf(length, 1.0)
	ramp_of.run = ramp_of.ramp
	ramp_of.end = ramp_of.ramp
	ramp_of.near = signf(near_side)
	ramp_of.face_from = clampf(from_s, 0.0, ramp_of.ramp)
	ramp_of.face_to = clampf(to_s, 0.0, ramp_of.ramp)
	ramp_of.rimmed = against_rim
	ramp_of.at_face_end = face_ends and near_side != 0.0
	ramp_of.top_ends = top_ends_there
	ramp_of._build()
	return ramp_of


## The s up to which the near side joins the top beside it (0 when it runs along no face there).
func join_length() -> float:
	if near == 0.0 or face_from > 0.5 or face_to <= face_from:
		return 0.0
	return minf(face_to, maxf(JOIN_HEIGHT / maxf(1.0, LEVEL * (top - bottom)) * ramp, JOIN_MIN))


## True when its top end is an open end of the cliff (docs/godot/ELEVATION.md "Ramps"): a free top
## end where the face beside it begins and the top ends (a tip), so the wall comes down to meet the
## ground there instead of turning a corner and closing the shape. The top's rim does not turn
## around the end (`closes`), the cap covers the strips' ends, and no shadow falls beyond the end
## (`shadow_take`). (No corner stones end a tapered wall anywhere: Elevation `_end_under_ramp`.) At a
## plateau's corner the top's side runs on past the top end: its rim and shadow stay.
func opens() -> bool:
	return near != 0.0 and at_face_end and top_ends and not rimmed


## The top end's corner on the face (screen, at the top's height): where an open end's wall begins.
func open_corner() -> Vector2:
	return screen_of(Vector3(0.0, near * half, LEVEL * (top - bottom)))


## True when the boundary edge `from` → `to` (screen) of a top of `level` is part of the rim that
## would turn around this open end and close the shape: beyond the top end (s ≤ 0 at the top's
## height, not along it: a straight face's top end runs along the top's side) and its middle within
## OPEN_REACH of the end's corner. Elevation leaves it out of the top's rim (no strip, glow or
## depth core), so the lip runs on to the end and stops there.
func closes(from: Vector2, to: Vector2, level: int) -> bool:
	if not opens() or level != top or ((from + to) * 0.5).distance_to(open_corner()) > OPEN_REACH:
		return false
	var s_from := _s_on_top(from)
	var s_to := _s_on_top(to)
	return maxf(s_from, s_to) <= 1.0 and minf(s_from, s_to) < -1.0


## How much of the cast shadows the ground drawn at `point` (screen) takes, 0 … 1: none on a
## one-row open cliff (`no_shadow`); else none beyond an open end (s ≤ 0 at the top's height)
## within OPEN_NEAR of its corner, where the cliff comes down to the ground and nothing stands high
## enough to cast one; all of it OPEN_FADE down the slope and OPEN_FAR from the corner. 1 where it
## is not an open end. (The shadows on the slope beside the face fade with the face's height by
## themselves: the slope takes them at its own height.)
func shadow_take(point: Vector2) -> float:
	if no_shadow:
		return 0.0
	if not opens():
		return 1.0
	var beyond := 1.0 - smoothstep(0.0, OPEN_FADE, _s_on_top(point))
	return 1.0 - beyond * (1.0 - smoothstep(OPEN_NEAR, OPEN_FAR, point.distance_to(open_corner())))


## s of `point` (screen) taken at the top's height (the ground under it: y + 64 · top).
func _s_on_top(point: Vector2) -> float:
	return (point + Vector2(0.0, LEVEL * top) - base).dot(dir)


## How far a body (Elevation.BODY_HALF around its feet, its rect BODY_HALF.y high above them)
## reaches up the slope (towards s = 0) from its feet, in s: the slope's s grows on screen along
## its gradient, the rect's corner furthest against it leads.
func _body_reach() -> float:
	var ds := _screen_step()
	var det := ds.x * across.y - ds.y * across.x
	if absf(det) < 1e-6:
		return 0.0
	var gradient := Vector2(across.y, -across.x) / det
	return Elevation.BODY_HALF.x * absf(gradient.x) + 2.0 * Elevation.BODY_HALF.y * maxf(0.0, gradient.y)


## Every level it joins walks it, but its high end is the top level's alone: a ramp has no landing
## of its own, and nothing climbs onto its highest part from below.
func walks_level(point: Vector2, level: int) -> bool:
	if not joins(level) or not walks(point):
		return false
	return level == top or s_at(point) >= high_end


## Nothing of a ramp stands up: no railings, no posts.
func blockers(_level: int) -> Array[PackedVector2Array]:
	var none: Array[PackedVector2Array] = []
	return none


## The edges a level's collision may run along: the borders of the walk, the open sides' strips
## and the skirt, and the line where the high end begins (Elevation keeps a piece where it parts
## walkable from blocked ground).
func outline_edges(_level: int) -> Array:
	var edges: Array = []
	for polygon: PackedVector2Array in [walk] + sides + skirt + soft_skirt:
		for i in polygon.size():
			edges.append([polygon[i], polygon[(i + 1) % polygon.size()]])
	# The line s = high_end across the walk (on the slope's plane, as `s_at` measures it: on past
	# the near side over a joined face, out to a rimmed ramp's corners).
	var h := nosing(high_end)
	var far := half + LEVEL * (top - bottom + 1)
	var line := PackedVector2Array([screen_of(Vector3(high_end, -far, h)), screen_of(Vector3(high_end, far, h))])
	for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, walk):
		edges.append([piece[0], piece[piece.size() - 1]])
	return edges


## True when `point` (screen) lies past one of the slope's open sides (`sides`) and a body of `level`
## on the slope could step off there: a level above the bottom it joins (Elevation then asks the
## terrain for ground of a level from the bottom up to `level`).
func lets_off(point: Vector2, level: int) -> bool:
	if level <= bottom or level > top or not bounds.has_point(point) or Geometry2D.is_point_in_polygon(point, walk):
		return false
	return _in_sides(point)


## True when `point` (screen) lies on the slope or past one of its open sides.
func reaches(point: Vector2) -> bool:
	return bounds.has_point(point) and (Geometry2D.is_point_in_polygon(point, walk) or _in_sides(point))


func _in_sides(point: Vector2) -> bool:
	for strip in sides:
		if Geometry2D.is_point_in_polygon(point, strip):
			return true
	return false


## True when the ramp is drawn at `point` (screen): its surface or its skirt.
func covers(point: Vector2) -> bool:
	if not bounds.has_point(point):
		return false
	if Geometry2D.is_point_in_polygon(point, surface):
		return true
	for side in skirt:
		if Geometry2D.is_point_in_polygon(point, side):
			return true
	return false


## True when `point` (screen) lies on a side of the slope facing the camera (not on the slope):
## ground of the bottom level.
func skirts(point: Vector2) -> bool:
	if skirt.is_empty() or not bounds.has_point(point) or Geometry2D.is_point_in_polygon(point, walk):
		return false
	for side in skirt:
		if Geometry2D.is_point_in_polygon(point, side):
			return true
	return false


## True when a body of `level` may stand on the skirt at `point` (screen, on it: `skirts`): the
## bottom level anywhere, the levels above it from `high_end` down (they step off the slope there).
func skirt_walks(point: Vector2, level: int) -> bool:
	if not joins(level):
		return false
	if level == bottom:
		return true
	for side in soft_skirt:
		if Geometry2D.is_point_in_polygon(point, side):
			return true
	return false


## True when `point` (screen) lies on the visible part of the tapered face beside the slope.
func on_face(point: Vector2) -> bool:
	return face_zone.size() >= 3 and bounds.has_point(point) and Geometry2D.is_point_in_polygon(point, face_zone)


## s along the slope of the walk's point drawn at `point`, NAN off it (the joined stretch over the
## face counts as the slope beside it).
func s_at(point: Vector2) -> float:
	if not walks(point):
		return NAN
	var height := LEVEL * (top - bottom)
	# screen = a + s · ds + t · across, the slope's height falling by height / ramp per unit of s.
	var a := screen_of(Vector3(0.0, 0.0, height))
	var ds := _screen_step()
	var det := ds.x * across.y - ds.y * across.x
	if absf(det) < 1e-6:
		return NAN
	var q := point - a
	return clampf((q.x * across.y - q.y * across.x) / det, 0.0, ramp)


## How far the slope's points move on screen per unit of s.
func _screen_step() -> Vector2:
	return Vector2(dir.x, dir.y + LEVEL * (top - bottom) / ramp)


# --- building ------------------------------------------------------------------------------

func _build() -> void:
	var height := LEVEL * (top - bottom)
	var a := screen_of(Vector3(0.0, -half, height))
	var b := screen_of(Vector3(ramp, -half, 0.0))
	var c := screen_of(Vector3(ramp, half, 0.0))
	var d := screen_of(Vector3(0.0, half, height))
	surface = PackedVector2Array([a, b, c, d])
	walk = surface.duplicate()
	var ear := EAR / maxf(0.1, _screen_step().length())
	if rimmed and ear < ramp * 0.5:
		# The top corners reach over the rim beside them (`EAR`).
		walk = PackedVector2Array([screen_of(Vector3(0.0, -half - EAR, height)), screen_of(Vector3(ear, -half, nosing(ear))), b, c,
				screen_of(Vector3(ear, half, nosing(ear))), screen_of(Vector3(0.0, half + EAR, height))])
		# A straight front ramp cuts through the wall it leaves: that wall's foot meets the slope's
		# sides where the slope has come down one wall course per level on screen. The corner there
		# is cut at 45° (`FOOT_EAR`), so a body overhanging a side slides onto the slope.
		foot_cut = 0.0
		if is_zero_approx(dir.x) and dir.y > 0.0:
			var step_y := _screen_step().y
			foot_cut = height / step_y
			var up := FOOT_EAR / step_y
			if foot_cut - up > ear and foot_cut < ramp:
				# Down the side t = −half, then up the side t = half.
				var cuts: Array = []
				for t: float in [-half, half]:
					var foot := screen_of(Vector3(foot_cut, t, nosing(foot_cut)))
					var cut := [screen_of(Vector3(foot_cut - up, t, nosing(foot_cut - up))), foot + across * signf(t) * FOOT_EAR, foot]
					if t > 0.0:
						cut.reverse()
					cuts.append(cut)
				walk = PackedVector2Array([walk[0], walk[1]] + cuts[0] + [b, c] + cuts[1] + [walk[4], walk[5]])
			else:
				foot_cut = 0.0
	var joined := join_length()
	if joined > 0.5:
		var t := near * half
		var on_edge := screen_of(Vector3(joined, t, nosing(joined)))
		var on_top := screen_of(Vector3(joined, t, height))
		# The near side is a → b (t = −half) or c → d (t = half); the walk takes in the face beside
		# the slope's top end up to the top's edge.
		walk = PackedVector2Array([a, on_top, on_edge, b, c, d]) if near < 0.0 else PackedVector2Array([a, b, c, on_edge, on_top, d])
	face_zone = PackedVector2Array()
	if near != 0.0 and face_to - face_from > 0.5:
		var t := near * half
		face_zone = PackedVector2Array([screen_of(Vector3(face_from, t, height)), screen_of(Vector3(face_to, t, height)),
				screen_of(Vector3(face_to, t, nosing(face_to))), screen_of(Vector3(face_from, t, nosing(face_from)))])
	# The high end: SOFT_MARGIN on screen down from the top end, at least END_BAND, and ending before
	# a climbing body's front reaches it below the top level's stretch (`level_at`: the top level
	# from s = ramp · 32 / height up).
	var chamfer := minf(SOFT_MARGIN / maxf(0.1, _screen_step().length()), ramp * 0.5)
	high_end = minf(maxf(END_BAND, chamfer), ramp * 0.5)
	var takes_top := ramp * LEVEL * 0.5 / maxf(1.0, height)
	high_end = minf(high_end, maxf(HIGH_END_MIN, takes_top - _body_reach() - HIGH_END_MARGIN))
	# The open sides that face no camera (a side facing it has its skirt instead), from the top end
	# down, their start cut at about 45° on screen: a body overhanging the slope slides along it, and
	# none steps off the top's own rim into them.
	sides.clear()
	for side: float in ([-near] if near != 0.0 else [-1.0, 1.0]):
		if (across * side).y > 1e-6:
			continue
		var t0 := side * half
		var t1 := side * (half + SOFT_MARGIN)
		sides.append(PackedVector2Array([screen_of(Vector3(0.0, t0, height)), screen_of(Vector3(ramp, t0, 0.0)),
				screen_of(Vector3(ramp, t1, 0.0)), screen_of(Vector3(chamfer, t1, nosing(chamfer)))]))
	cap_rect = Rect2()
	if opens():
		cap_rect = Rect2(open_corner(), Vector2.ZERO).grow(CAP_RADIUS + CAP_FADE)
	skirt.clear()
	soft_skirt.clear()
	for side_quad: Array in _skirt_faces():
		var shape := PackedVector2Array()
		for p: Vector3 in side_quad:
			shape.append(screen_of(p))
		if absf(_area(shape)) > 1.0:
			skirt.append(shape)
		if side_quad.size() == 3:
			# A long side: its part from the high end down.
			var t := float((side_quad[0] as Vector3).y)
			soft_skirt.append(PackedVector2Array([screen_of(Vector3(high_end, t, nosing(high_end))), screen_of(Vector3(ramp, t, 0.0)),
					screen_of(Vector3(high_end, t, 0.0))]))
	_hulls.clear()
	_hulls.append([surface, true])
	for side in skirt:
		_hulls.append([side, true])
	_solids.clear()
	_blockers.clear()
	_pieces.clear()
	faces.clear()
	feet.clear()
	var pieces: Array[PackedVector2Array] = [surface]
	pieces.append_array(skirt)
	silhouette = _union(pieces)
	bounds = Rect2(walk[0], Vector2.ZERO)
	for polygon: PackedVector2Array in [walk, surface, face_zone, _landing_quad(LANDING_FADE)] + sides + skirt:
		for point in polygon:
			bounds = bounds.expand(point)
	if opens():
		bounds = bounds.merge(cap_rect)
	bounds = bounds.grow(1.0)


## The sides of the slope facing the camera (their outward normal points down the screen), as
## polygons in the frame from the slope's edge down to the ground: a long side is a triangle (the
## slope reaches the ground at the bottom end), a free top end a rectangle (one against a rim stands
## against the top behind it).
func _skirt_faces() -> Array:
	var height := LEVEL * (top - bottom)
	var faces_of := []
	for side: float in [-1.0, 1.0]:
		if (across * side).y > 1e-6:
			var t := side * half
			faces_of.append([Vector3(0.0, t, height), Vector3(ramp, t, 0.0), Vector3(0.0, t, 0.0)])
	if -dir.y > 1e-6 and not rimmed:
		faces_of.append([Vector3(0.0, -half, height), Vector3(0.0, half, height), Vector3(0.0, half, 0.0), Vector3(0.0, -half, 0.0)])
	return faces_of


## A rimmed ramp's landing on the top behind its top end (screen), its sides grown by `grow`: empty
## for a free top end.
func _landing_quad(grow: float) -> PackedVector2Array:
	if not rimmed:
		return PackedVector2Array()
	var height := LEVEL * (top - bottom)
	return PackedVector2Array([screen_of(Vector3(-LANDING_DEPTH, -half - grow, height)), screen_of(Vector3(0.0, -half - grow, height)),
			screen_of(Vector3(0.0, half + grow, height)), screen_of(Vector3(-LANDING_DEPTH, half + grow, height))])


## Higher ground drawn over the ramp hides it (elevation_stairs.gd `occlude`): what of the skirt lies
## under it is no skirt.
func occlude(polygons: Array[PackedVector2Array]) -> void:
	super.occlude(polygons)
	if not occluders.is_empty():
		skirt = _cut(skirt)
		soft_skirt = _cut(soft_skirt)


# --- output --------------------------------------------------------------------------------

## The surface and the skirt into `mesh` (elevation_ramp.gdshader): colour g = the height in levels
## ((L + 4) / 8, the light of a ramp in a hole; the skirt from its edge's down to the bottom's), a =
## its opacity (the edge along a face fades out). What of them lies below the top level where higher
## ground is drawn over it (a ramp leaving a back rim) is cut out.
func add_mesh(mesh: MeshData) -> void:
	var height := LEVEL * (top - bottom)
	# r = the cast shadows it takes: none on a one-row open cliff (`no_shadow`).
	var take := 0.0 if no_shadow else 1.0
	var shown := func(_p: Vector3, w: Vector3) -> Color: return Color(take, (w.z / LEVEL + 4.0) / 8.0, 0.0, 1.0)
	var faded := func(_p: Vector3, w: Vector3) -> Color: return Color(take, (w.z / LEVEL + 4.0) / 8.0, 0.0, 0.0)
	if near == 0.0:
		_emit_fan(mesh, [Vector3(0.0, -half, height), Vector3(ramp, -half, 0.0), Vector3(ramp, half, 0.0), Vector3(0.0, half, height)], shown)
	else:
		# The edge along the face fades out over EDGE_FADE: the lip's tufts and the stone above the
		# slope end softly on it instead of along a ruled line.
		var t_near := near * half
		var t_in := near * (half - minf(EDGE_FADE, half))
		_emit_fan(mesh, [Vector3(0.0, -t_near, height), Vector3(ramp, -t_near, 0.0), Vector3(ramp, t_in, 0.0), Vector3(0.0, t_in, height)], shown)
		var band: Array = [[Vector3(0.0, t_in, height), shown], [Vector3(ramp, t_in, 0.0), shown], [Vector3(ramp, t_near, 0.0), faded], [Vector3(0.0, t_near, height), faded]]
		var corners: Array = []
		for corner: Array in band:
			var w := world(corner[0])
			corners.append([screen(w), Vector2.ZERO, (corner[1] as Callable).call(corner[0], w), w.z])
		_emit(mesh, [corners[0], corners[1], corners[2]])
		_emit(mesh, [corners[0], corners[2], corners[3]])
	for polygon: Array in _skirt_faces():
		_emit_fan(mesh, polygon, shown)
	# An open end's cap: ground of the bottom level; what of it lies on the top (the tops around,
	# `occluders`) is cut out by `_emit` and drawn with the top's ground (`add_cap_top`).
	for triangle: Array in _cap_triangles(bottom):
		_emit(mesh, triangle)


## An open end's cap over the top beside it into `mesh`, with the top's ground (`top_ground`'s
## sheet): the cap on `tops` (the tris of the top level and higher around it, screen triangles), so
## the ends of the top's lip and rim fade out under it.
func add_cap_top(mesh: MeshData, tops: Array[PackedVector2Array]) -> void:
	var boxes: Array[Rect2] = []
	for tri in tops:
		boxes.append(Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2]))
	for triangle: Array in _cap_triangles(top):
		var points := PackedVector2Array([triangle[0][0], triangle[1][0], triangle[2][0]])
		var box := Rect2(points[0], Vector2.ZERO).expand(points[1]).expand(points[2])
		for index in tops.size():
			if not box.intersects(boxes[index]):
				continue
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(points, tops[index]):
				if absf(_area(piece)) > 0.25:
					_add_polygon(mesh, triangle, piece)


## The cap's triangles of vertices [screen, uv, colour, height] as ground of `level`: a grid of
## CAP_CELL squares over `cap_rect`, colour a = `_cap_alpha` (squares it leaves clear are left out),
## r = the shadows it takes (`shadow_take`).
func _cap_triangles(level: int) -> Array:
	var triangles: Array = []
	if not opens():
		return triangles
	var vertex := func(point: Vector2) -> Array:
		return [point, Vector2.ZERO, Color(shadow_take(point), (float(level) + 4.0) / 8.0, 0.0, _cap_alpha(point)), LEVEL * level]
	var count := ceili(cap_rect.size.x / CAP_CELL)
	for iy in count:
		for ix in count:
			var o := cap_rect.position + Vector2(ix, iy) * CAP_CELL
			var square: Array = [vertex.call(o), vertex.call(o + Vector2(CAP_CELL, 0.0)), vertex.call(o + Vector2(CAP_CELL, CAP_CELL)), vertex.call(o + Vector2(0.0, CAP_CELL))]
			var clear := true
			for corner: Array in square:
				clear = clear and (corner[2] as Color).a <= 0.001
			if clear:
				continue
			triangles.append([square[0], square[1], square[2]])
			triangles.append([square[0], square[2], square[3]])
	return triangles


## The cap's opacity at `point` (screen): opaque within CAP_RADIUS of the open end's corner and
## CAP_BEYOND beyond the top end (up to CAP_SOLID past it where the rim was cut), clear CAP_FADE
## further out and CAP_INTO (CAP_INTO_CUT) along the slope.
func _cap_alpha(point: Vector2) -> float:
	var radial := 1.0 - smoothstep(CAP_RADIUS, CAP_RADIUS + CAP_FADE, point.distance_to(open_corner()))
	var along := smoothstep(CAP_SOLID, CAP_INTO_CUT, _s_on_top(point)) if cuts_rim else smoothstep(-CAP_BEYOND, CAP_INTO, _s_on_top(point))
	return radial * (1.0 - along)


## A rimmed ramp's landing into `mesh` (the top's ground, elevation_ramp.gdshader): the top's own
## ground over its lip where the ramp leaves the rim, from LANDING_DEPTH over the top to the rim,
## its sides fading out over LANDING_FADE, so the lip breaks for the way down.
func add_landing(mesh: MeshData) -> void:
	if not rimmed:
		return
	var level_of := (float(top) + 4.0) / 8.0
	var solid := Color(1.0, level_of, 0.0, 1.0)
	var clear := Color(1.0, level_of, 0.0, 0.0)
	var inner := _landing_quad(0.0)
	var outer := _landing_quad(LANDING_FADE)
	_add_quad(mesh, inner, [solid, solid, solid, solid])
	# The sides: [inner back, inner rim] against [outer back, outer rim].
	for pair: Array in [[0, 1], [3, 2]]:
		_add_quad(mesh, PackedVector2Array([inner[pair[0]], inner[pair[1]], outer[pair[1]], outer[pair[0]]]), [solid, solid, clear, clear])


static func _add_quad(mesh: MeshData, quad: PackedVector2Array, colors: Array) -> void:
	for index: int in [0, 1, 2, 0, 2, 3]:
		mesh.add(quad[index], Vector2.ZERO, colors[index])


## The surface and the skirt into the depth map as ground of the bottom level marked as a ramp
## (elevation_occlusion.gd `encode_ramp`): over the wall they cover nothing hides a body any more.
## For the cast shadows they are the ground below, except over that wall (`walls`, screen
## triangles), where they keep the height they stand at: the shadow beside the slope is as long as
## the slope is high there (none beyond an open end: `shadow_take`), and the slope's free edges
## (drawn as ground) cast none.
func add_ramp_depth(depth: MeshData, walls: Array[PackedVector2Array]) -> void:
	var flat := func(_p: Vector3, _w: Vector3) -> Color: return ElevationOcclusion.encode_ramp(bottom, 0.0)
	for polygon: Array in _polygons():
		_emit_fan(depth, polygon, flat)
	if walls.is_empty():
		return
	for polygon: Array in _polygons():
		var corners: Array = []
		for p: Vector3 in polygon:
			var w := world(p)
			corners.append([screen(w), Vector2.ZERO, ElevationOcclusion.encode_ramp(bottom, p.z / LEVEL), w.z])
		for i in range(1, corners.size() - 1):
			var triangle: Array = [corners[0], corners[i], corners[i + 1]]
			var points := PackedVector2Array([triangle[0][0], triangle[1][0], triangle[2][0]])
			for wall in walls:
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(points, wall):
					var parts: Array[PackedVector2Array] = [piece]
					for part in (_cut(parts) if not occluders.is_empty() else parts):
						_add_polygon(depth, triangle, part)


## A ramp goes into the depth map by `add_ramp_depth`.
func add_depth(depth: MeshData) -> void:
	add_ramp_depth(depth, [])


## The surface and the skirt's faces, as polygons in the frame.
func _polygons() -> Array:
	var height := LEVEL * (top - bottom)
	var polygons: Array = [[Vector3(0.0, -half, height), Vector3(ramp, -half, 0.0), Vector3(ramp, half, 0.0), Vector3(0.0, half, height)]]
	polygons.append_array(_skirt_faces())
	return polygons


## A convex polygon of the frame into `mesh` as a fan of `_emit` triangles, `color_of(p, world)`
## giving each corner's colour.
func _emit_fan(mesh: MeshData, polygon: Array, color_of: Callable) -> void:
	var corners: Array = []
	for p: Vector3 in polygon:
		var w := world(p)
		corners.append([screen(w), Vector2.ZERO, color_of.call(p, w), w.z])
	for i in range(1, corners.size() - 1):
		_emit(mesh, [corners[0], corners[i], corners[i + 1]])
