extends RefCounted
## Lined-up aim: the two kinds of enemy ranged attack (owner, 2026-10-16). Four-way shooters (the
## archers and the spiders) shoot only straight up, down, left or right, like the archers in Zelda;
## eight-way shooters (the skeletons) also shoot along the diagonals. A shooter lines up with the
## slime on one of its lines first, then shoots along it; a slime that steps off the line during
## the wind-up is missed. Pass `eight = true` for the eight-way kind.
##
## Owner: enemy builder.

## Right, down, left, up.
const DIRECTIONS: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
## The four above and the four diagonals between them, clockwise from right.
const EIGHT_DIRECTIONS: Array[Vector2] = [
	Vector2.RIGHT, Vector2(0.70710678, 0.70710678), Vector2.DOWN, Vector2(-0.70710678, 0.70710678),
	Vector2.LEFT, Vector2(-0.70710678, -0.70710678), Vector2.UP, Vector2(0.70710678, -0.70710678),
]


## The four (or eight) directions.
static func directions(eight: bool = false) -> Array[Vector2]:
	return EIGHT_DIRECTIONS if eight else DIRECTIONS


## The direction nearest to `vector` (ties go to the earlier one: horizontal first); zero stays zero.
static func snap(vector: Vector2, eight: bool = false) -> Vector2:
	if vector.is_zero_approx():
		return Vector2.ZERO
	var best := Vector2.ZERO
	var best_dot := -INF
	var unit := vector.normalized()
	for direction in directions(eight):
		var dot := unit.dot(direction)
		if dot > best_dot + 0.000001:
			best_dot = dot
			best = direction
	return best


## True when `target` lies on one of `from`'s lines, within `tolerance` px of it.
static func is_lined_up(from: Vector2, target: Vector2, tolerance: float, eight: bool = false) -> bool:
	return not line_direction(from, target, tolerance, eight).is_zero_approx()


## The direction from `from` along the line it shares with `target` (its row or column, or a
## diagonal for the eight-way kind), `target` within `tolerance` px of that line; the closest line
## when several fit; zero when none does.
static func line_direction(from: Vector2, target: Vector2, tolerance: float, eight: bool = false) -> Vector2:
	var delta := target - from
	var best := Vector2.ZERO
	var best_off := INF
	for direction in directions(eight):
		if delta.dot(direction) <= 0.0:
			continue
		var off := absf(delta.cross(direction))
		if off <= tolerance and off < best_off:
			best_off = off
			best = direction
	return best


## The spots `distance` px from `target` along each of its lines (four, or eight), nearest to `from`
## first: where a shooter at `from` stands to shoot along a line. A shooter whose way to the first
## is blocked tries the next.
static func line_up_points(from: Vector2, target: Vector2, distance: float, eight: bool = false) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for direction in directions(eight):
		points.append(target + direction * distance)
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return from.distance_squared_to(a) < from.distance_squared_to(b))
	return points
