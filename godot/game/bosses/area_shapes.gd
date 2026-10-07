extends RefCounted
class_name AreaShapes
## World-space shapes of an Area2D and their overlap tests (Phaser `EnemyScript.referencedAreaShapes`,
## `targetOverlapsShapes`, `FattyScript.translateShape`, `runtime/scene/physics/SensorGeometry.ts`).
## Boss spec 3.5.
##
## A shape entry is {"shape": Shape2D, "transform": Transform2D (global)}. Every CollisionShape2D
## child counts, disabled or not: an authored attack area is geometry, its physics monitoring is
## irrelevant (EnemyScript.ts:621-632). Ellipses are the converter's 32-point convex polygons.
##
## Owner: boss port.


## Every CollisionShape2D child of `area` with a shape, in world space (child order).
static func of_area(area: Area2D) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	if area == null or not is_instance_valid(area) or not area.is_inside_tree():
		return shapes
	for child: Node in area.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		shapes.append({"shape": shape_node.shape, "transform": shape_node.global_transform})
	return shapes


## The shapes moved by `offset` (`translateShape`).
static func translated(shapes: Array[Dictionary], offset: Vector2) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	for entry: Dictionary in shapes:
		var xform: Transform2D = entry["transform"]
		moved.append({"shape": entry["shape"], "transform": xform.translated(offset)})
	return moved


## `targetOverlapsShapes`: any of `shapes` intersects any shape of `hurtbox`; when the hurtbox has
## no shapes, `fallback_point` (the target centre) inside any of `shapes`.
static func overlaps_area(shapes: Array[Dictionary], hurtbox: Area2D, fallback_point: Vector2) -> bool:
	var targets := of_area(hurtbox)
	if targets.is_empty():
		return contains_point(shapes, fallback_point)
	for entry: Dictionary in shapes:
		var shape: Shape2D = entry["shape"]
		for other: Dictionary in targets:
			if shape.collide(entry["transform"], other["shape"], other["transform"]):
				return true
	return false


## True when `point` (world space) is inside any of `shapes` (circles, rectangles, convex polygons).
static func contains_point(shapes: Array[Dictionary], point: Vector2) -> bool:
	for entry: Dictionary in shapes:
		var xform: Transform2D = entry["transform"]
		var local := xform.affine_inverse() * point
		var shape: Shape2D = entry["shape"]
		if shape is CircleShape2D:
			if local.length() <= (shape as CircleShape2D).radius:
				return true
		elif shape is RectangleShape2D:
			var half := (shape as RectangleShape2D).size / 2.0
			if absf(local.x) <= half.x and absf(local.y) <= half.y:
				return true
		elif shape is ConvexPolygonShape2D:
			if Geometry2D.is_point_in_polygon(local, (shape as ConvexPolygonShape2D).points):
				return true
	return false


## Outline of a shape entry in world space (for drawing): circle -> 48 points, rectangle -> 4,
## convex polygon -> its points. Empty for other shape types.
static func outline(entry: Dictionary) -> PackedVector2Array:
	var xform: Transform2D = entry["transform"]
	var shape: Shape2D = entry["shape"]
	var points := PackedVector2Array()
	if shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		for i in 48:
			points.append(xform * (Vector2.from_angle(TAU * i / 48.0) * radius))
	elif shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size / 2.0
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			points.append(xform * corner)
	elif shape is ConvexPolygonShape2D:
		for point: Vector2 in (shape as ConvexPolygonShape2D).points:
			points.append(xform * point)
	return points


## The centre of a shape entry in world space (its transform origin).
static func centre(entry: Dictionary) -> Vector2:
	var xform: Transform2D = entry["transform"]
	return xform.origin
