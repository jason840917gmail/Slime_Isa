extends RefCounted
class_name Perimeter
## World-area perimeters (enemy spawn/safe zones, NPC wander areas) as Dictionaries:
##   rectangle: {"shape": "rectangle", "x": float, "y": float, "w": float, "h": float}  (x, y = top-left)
##   circle:    {"shape": "circle", "x": float, "y": float, "radius": float}            (x, y = centre)
## Coordinates are world space; world areas have no depthAnchor, so they are unchanged from Phaser.
## Ports `content/scenes/worldAreaGeometry.ts` and `content/maps/agentAreaGeometry.ts`.
##
## Owner: world builder. Architect wrote it complete.

const SHAPE_RECTANGLE := "rectangle"
const SHAPE_CIRCLE := "circle"
const ANGLE_EPSILON := 0.000001


## JS `Math.round` (half rounds toward +infinity).
static func js_round(value: float) -> float:
	return floorf(value + 0.5)


## `perimeterFromCollisionShape` (worldAreaGeometry.ts:32-52) using the shape node's global
## position / rotation / scale. Circle needs a uniform scale; rectangle must be unrotated.
## Returns {} and push_error()s for an unsupported or invalid shape.
static func from_shape(shape_node: CollisionShape2D) -> Dictionary:
	if shape_node == null or shape_node.shape == null:
		push_error("Perimeter.from_shape: missing CollisionShape2D or shape resource")
		return {}
	var origin := shape_node.global_position
	var scale_x := absf(shape_node.global_scale.x)
	var scale_y := absf(shape_node.global_scale.y)
	if shape_node.shape is CircleShape2D:
		if absf(scale_x - scale_y) > ANGLE_EPSILON:
			push_error("Perimeter.from_shape: circle areas need a uniform scale (%s)" % shape_node.get_path())
			return {}
		var radius := (shape_node.shape as CircleShape2D).radius
		return {"shape": SHAPE_CIRCLE, "x": js_round(origin.x), "y": js_round(origin.y),
			"radius": maxf(1.0, js_round(radius * scale_x))}
	if shape_node.shape is RectangleShape2D:
		if absf(sin(shape_node.global_rotation)) >= ANGLE_EPSILON:
			push_error("Perimeter.from_shape: rectangle areas cannot be rotated (%s)" % shape_node.get_path())
			return {}
		var size := (shape_node.shape as RectangleShape2D).size
		var w := size.x * scale_x
		var h := size.y * scale_y
		var left := js_round(origin.x - w / 2.0)
		var top := js_round(origin.y - h / 2.0)
		var right := maxf(left + 1.0, js_round(origin.x + w / 2.0))
		var bottom := maxf(top + 1.0, js_round(origin.y + h / 2.0))
		return {"shape": SHAPE_RECTANGLE, "x": left, "y": top, "w": right - left, "h": bottom - top}
	push_error("Perimeter.from_shape: only rectangle and circle shapes are supported (%s)" % shape_node.get_path())
	return {}


## `perimeterContains`: inclusive edges; circle uses `hypot <= radius`.
static func contains(perimeter: Dictionary, point: Vector2) -> bool:
	if perimeter.is_empty():
		return false
	if perimeter["shape"] == SHAPE_CIRCLE:
		return point.distance_to(Vector2(perimeter["x"], perimeter["y"])) <= float(perimeter["radius"])
	var x: float = perimeter["x"]
	var y: float = perimeter["y"]
	return point.x >= x and point.x <= x + float(perimeter["w"]) and point.y >= y and point.y <= y + float(perimeter["h"])


## `randomPointInPerimeter`: circle `angle = randf()*TAU, d = sqrt(randf())*r`;
## rectangle `(x + randf()*w, y + randf()*h)`. Exactly two randf() calls, in that order.
static func random_point(perimeter: Dictionary) -> Vector2:
	if perimeter["shape"] == SHAPE_CIRCLE:
		var angle := randf() * TAU
		var distance := sqrt(randf()) * float(perimeter["radius"])
		return Vector2(float(perimeter["x"]) + cos(angle) * distance, float(perimeter["y"]) + sin(angle) * distance)
	var px := float(perimeter["x"]) + randf() * float(perimeter["w"])
	var py := float(perimeter["y"]) + randf() * float(perimeter["h"])
	return Vector2(px, py)


## Circle centre, or rectangle centre `(x + w/2, y + h/2)` (Territory.ts home centre).
static func centre(perimeter: Dictionary) -> Vector2:
	if perimeter["shape"] == SHAPE_CIRCLE:
		return Vector2(perimeter["x"], perimeter["y"])
	return Vector2(float(perimeter["x"]) + float(perimeter["w"]) / 2.0, float(perimeter["y"]) + float(perimeter["h"]) / 2.0)


## Distance from `point` to the perimeter, 0 inside (Territory.ts home distance):
## circle `max(0, |p - c| - r)`; rectangle `hypot(max(x - p.x, 0, p.x - (x + w)), max(y - p.y, 0, p.y - (y + h)))`.
static func distance_outside(perimeter: Dictionary, point: Vector2) -> float:
	if perimeter["shape"] == SHAPE_CIRCLE:
		return maxf(0.0, point.distance_to(Vector2(perimeter["x"], perimeter["y"])) - float(perimeter["radius"]))
	var x: float = perimeter["x"]
	var y: float = perimeter["y"]
	var dx := maxf(maxf(x - point.x, 0.0), point.x - (x + float(perimeter["w"])))
	var dy := maxf(maxf(y - point.y, 0.0), point.y - (y + float(perimeter["h"])))
	return Vector2(dx, dy).length()


## `enemySpawnPerimeterIssues`: same shape kind and `inner` fully inside `outer`.
static func fits_inside(inner: Dictionary, outer: Dictionary) -> bool:
	if inner.is_empty() or outer.is_empty() or inner["shape"] != outer["shape"]:
		return false
	if inner["shape"] == SHAPE_CIRCLE:
		var gap := Vector2(inner["x"], inner["y"]).distance_to(Vector2(outer["x"], outer["y"]))
		return gap + float(inner["radius"]) <= float(outer["radius"]) + ANGLE_EPSILON
	return float(inner["x"]) >= float(outer["x"]) and float(inner["y"]) >= float(outer["y"]) \
		and float(inner["x"]) + float(inner["w"]) <= float(outer["x"]) + float(outer["w"]) \
		and float(inner["y"]) + float(inner["h"]) <= float(outer["y"]) + float(outer["h"])
