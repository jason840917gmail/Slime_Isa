extends RefCounted
class_name WorldBounds
## World bounds walls (Phaser `physics.world.setBounds` + every body's `collideWorldBounds`,
## dropped by the converter). World spec 2.3.
##
## Owner: world builder.

## Wall thickness: thick enough that a 380 px/s dodge never tunnels through.
const THICKNESS := 256.0
## Physics layer "world" (bit 1).
const WORLD_LAYER := 1


## Adds a StaticBody2D "WorldBounds" under `parent` with four CollisionShape2D rectangles placed
## just outside `world_rect` (left Rect(-T,-T,T,H+2T), right Rect(W,-T,T,H+2T), top
## Rect(0,-T,W,T), bottom Rect(0,H,W,T)); collision_layer = 1 (world), collision_mask = 0.
## Returns the body (null when the rect is empty or there is no parent).
static func build(parent: Node, world_rect: Rect2) -> StaticBody2D:
	if parent == null or world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		push_error("WorldBounds.build: no parent or empty world rect %s" % world_rect)
		return null
	var t := THICKNESS
	var x := world_rect.position.x
	var y := world_rect.position.y
	var w := world_rect.size.x
	var h := world_rect.size.y
	var body := StaticBody2D.new()
	body.name = "WorldBounds"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var walls: Array[Rect2] = [
		Rect2(x - t, y - t, t, h + 2.0 * t),
		Rect2(x + w, y - t, t, h + 2.0 * t),
		Rect2(x, y - t, w, t),
		Rect2(x, y + h, w, t),
	]
	var names: Array[String] = ["Left", "Right", "Top", "Bottom"]
	for i: int in walls.size():
		var rect := walls[i]
		var rectangle := RectangleShape2D.new()
		rectangle.size = rect.size
		var shape_node := CollisionShape2D.new()
		shape_node.name = names[i]
		shape_node.shape = rectangle
		shape_node.position = rect.get_center()
		body.add_child(shape_node)
	parent.add_child(body)
	return body
