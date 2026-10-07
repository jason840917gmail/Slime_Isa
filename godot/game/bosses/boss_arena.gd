extends RefCounted
class_name BossArena
## Boss camp geometry and spawn rules (Phaser `features/bosses/BossCampBehavior.ts`). Boss spec
## 4.1 and 4.3. Perimeters use the world-area Dictionary shape of `shared/perimeter.gd`:
##   {"shape": "circle", "x", "y" (centre), "radius"} or {"shape": "rectangle", "x", "y" (top-left), "w", "h"}
## but are not rounded (BossCampBehavior reads the shape as it is). Coordinates are world space
## (camp areas have no depth anchor) and points are old Phaser positions (centres).
##
## Owner: boss port.

const SHAPE_CIRCLE := "circle"
const SHAPE_RECTANGLE := "rectangle"


## `bossPerimeterFromSensorShape` (:5-9) for a CollisionShape2D in the tree: circle -> centre and
## radius (times the global x scale); rectangle -> top-left and size (times the global scale);
## any other shape -> {}.
static func perimeter_from_shape(shape_node: CollisionShape2D) -> Dictionary:
	if shape_node == null or shape_node.shape == null:
		return {}
	var origin := shape_node.global_position
	var scale := shape_node.global_scale.abs()
	if shape_node.shape is CircleShape2D:
		return {"shape": SHAPE_CIRCLE, "x": origin.x, "y": origin.y,
			"radius": (shape_node.shape as CircleShape2D).radius * scale.x}
	if shape_node.shape is RectangleShape2D:
		var size := (shape_node.shape as RectangleShape2D).size * scale
		return {"shape": SHAPE_RECTANGLE, "x": origin.x - size.x / 2.0, "y": origin.y - size.y / 2.0,
			"w": size.x, "h": size.y}
	return {}


## The first CollisionShape2D child of `area` that converts (BossCampScript.ts:98-104), {} when none.
static func first_perimeter(area: Area2D) -> Dictionary:
	if area == null:
		return {}
	for child: Node in area.get_children():
		if child is CollisionShape2D:
			var perimeter := perimeter_from_shape(child as CollisionShape2D)
			if not perimeter.is_empty():
				return perimeter
	return {}


## `bossArenaCenter` (:11-15): circle centre or rectangle centre.
static func centre(perimeter: Dictionary) -> Vector2:
	if perimeter.get("shape", "") == SHAPE_CIRCLE:
		return Vector2(float(perimeter["x"]), float(perimeter["y"]))
	return Vector2(float(perimeter["x"]) + float(perimeter["w"]) / 2.0, float(perimeter["y"]) + float(perimeter["h"]) / 2.0)


## `clampToBossArena` (:17-32): rectangle -> each axis clamped to the edges; circle -> the point
## when within the radius, else projected onto the circle.
static func clamp_point(perimeter: Dictionary, point: Vector2) -> Vector2:
	if perimeter.is_empty():
		return point
	if perimeter.get("shape", "") == SHAPE_RECTANGLE:
		var x := float(perimeter["x"])
		var y := float(perimeter["y"])
		return Vector2(minf(x + float(perimeter["w"]), maxf(x, point.x)), minf(y + float(perimeter["h"]), maxf(y, point.y)))
	var center := Vector2(float(perimeter["x"]), float(perimeter["y"]))
	var radius := float(perimeter["radius"])
	var offset := point - center
	var length := offset.length()
	if length <= radius:
		return point
	return center + offset / length * radius


## `bossPerimeterContains` (:34-43): non-finite -> false; rectangle inclusive; circle
## `dx² + dy² <= r²`.
static func contains(perimeter: Dictionary, point: Vector2) -> bool:
	if perimeter.is_empty() or not point.is_finite():
		return false
	var x := float(perimeter.get("x", NAN))
	var y := float(perimeter.get("y", NAN))
	if not is_finite(x) or not is_finite(y):
		return false
	if perimeter.get("shape", "") == SHAPE_RECTANGLE:
		return point.x >= x and point.x <= x + float(perimeter["w"]) and point.y >= y and point.y <= y + float(perimeter["h"])
	var dx := point.x - x
	var dy := point.y - y
	var radius := float(perimeter.get("radius", 0.0))
	return dx * dx + dy * dy <= radius * radius


## `bossCampSpawnEligible` (:45-55). `respawn_ready_at < 0` means no respawn timer.
static func spawn_eligible(has_live_boss: bool, inside_activation: bool, respawn_ready_at: float,
		observed_outside_after_defeat: bool, epoch_now: float) -> bool:
	if has_live_boss or not inside_activation:
		return false
	if respawn_ready_at < 0.0:
		return true
	return observed_outside_after_defeat and epoch_now >= respawn_ready_at


## `resolveBossCampSpawnSuppression` (:62-73): {"suppress_spawn_until_outside", "blocks_spawn_this_update"}.
static func spawn_suppression(suppress_spawn_until_outside: bool, inside_activation: bool) -> Dictionary:
	if not suppress_spawn_until_outside:
		return {"suppress_spawn_until_outside": false, "blocks_spawn_this_update": false}
	return {"suppress_spawn_until_outside": inside_activation, "blocks_spawn_this_update": true}
