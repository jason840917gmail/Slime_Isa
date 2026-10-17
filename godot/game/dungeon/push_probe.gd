extends RefCounted
class_name PushProbe
## "Walk into it to use it" (docs/godot/CONVENTIONS.md "Doors": no keys for doors and gates; the
## dungeon designs' "W"): the slime pushes a kit object (a locked door, a bolt, a winch) by walking
## into its box. Shared by game/dungeon/dungeon_door.gd and winch.gd, as gate.gd does for gates:
## the player's collision rect within `worldNavigation.gatePushReachPx` of the box while its
## movement input points at it (within `doorPushAlignment`).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const Door := preload("res://game/scripts/door.gd")


## The way the slime pushes into `box` (global), as a unit cardinal vector, or ZERO when it does not
## push it. `reach` < 0 uses `worldNavigation.gatePushReachPx`.
static func push_direction(box: Rect2, reach: float = -1.0) -> Vector2:
	var world := Services.world()
	if world == null or world.player_body == null or world.player == null or box.size == Vector2.ZERO:
		return Vector2.ZERO
	var player: Node = world.player
	if not player.has_method(&"get_move_intent") or bool(player.call(&"is_dead")):
		return Vector2.ZERO
	var intent: Vector2 = player.call(&"get_move_intent")
	if intent == Vector2.ZERO:
		return Vector2.ZERO
	var body := Door._body_rect(world.player_body)
	var grow := reach if reach >= 0.0 else navigation("gatePushReachPx", 6.0)
	if not box.grow(grow).intersects(body):
		return Vector2.ZERO
	var centre := body.get_center()
	var nearest := Vector2(clampf(centre.x, box.position.x, box.end.x), clampf(centre.y, box.position.y, box.end.y))
	var to_box := nearest - centre
	if to_box.length() < 0.5:
		to_box = box.get_center() - centre
	var toward := Vector2(signf(to_box.x), 0.0) if absf(to_box.x) > absf(to_box.y) else Vector2(0.0, signf(to_box.y))
	if intent.normalized().dot(toward) < navigation("doorPushAlignment", 0.7):
		return Vector2.ZERO
	return toward


## How long a push must last (ms): `worldNavigation.doorPushMs`.
static func push_ms() -> float:
	return navigation("doorPushMs", 200.0)


## `worldNavigation.<key>`, else `fallback` (no constants: the editor).
static func navigation(key: String, fallback: float) -> float:
	var constants := Services.constants()
	return constants.number("worldNavigation." + key) if constants != null else fallback


## The bounding box (global) of `node`'s rectangle collision shapes; Rect2() without one.
static func shapes_box(node: Node) -> Rect2:
	var box := Rect2()
	var found := false
	if node == null:
		return box
	for child: Node in node.find_children("*", "CollisionShape2D", true, false):
		var shape_node := child as CollisionShape2D
		var rectangle := shape_node.shape as RectangleShape2D
		if rectangle == null:
			continue
		var half := rectangle.size * 0.5
		var xform := shape_node.global_transform
		var corners := [xform * Vector2(-half.x, -half.y), xform * Vector2(half.x, -half.y),
			xform * Vector2(half.x, half.y), xform * Vector2(-half.x, half.y)]
		var rect := Rect2(corners[0], Vector2.ZERO)
		for corner: Vector2 in corners:
			rect = rect.expand(corner)
		box = rect if not found else box.merge(rect)
		found = true
	return box
