extends RefCounted
## Fire and light: the two small contracts the Lantern's flame, candles, burnables, dark rooms and
## the Goo Bomb share (docs/godot/DARKNESS.md; bomb-lantern-and-secrets design section 2).
##
## - **Fire targets**: nodes in group `fire_targets` with `receive_fire(hit: Dictionary) -> bool`
##   (true: the flame is used up and stops there; false: it flies on, e.g. a candle already lit).
##   Where a flame touches one (`touches`): its `fire_rect() -> Rect2` (global) when it has one, else
##   its global position within its `fire_radius` property (DEFAULT_FIRE_RADIUS without one), each
##   grown by the flame's own radius.
## - **Light sources**: nodes in group `light_sources` with `light_circle() -> Vector3` (global x,
##   global y, radius; a radius <= 0 is off). Dark rooms cut a soft hole around each one.
##
## Owner: world (fire and darkness).

const Services := preload("res://game/shared/services.gd")

const FIRE_GROUP := &"fire_targets"
const LIGHT_GROUP := &"light_sources"
## The fire radius of a target that names none.
const DEFAULT_FIRE_RADIUS := 24.0
## A light's flicker (presentation only, real time): the radius breathes this share around its size.
const FLICKER_SHARE := 0.05


## True when a flame of `radius` at the global `point` touches the fire target `node`.
static func touches(node: Node, point: Vector2, radius: float) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if node.has_method(&"fire_rect"):
		var rect: Variant = node.call(&"fire_rect")
		if rect is Rect2:
			return (rect as Rect2).grow(radius).has_point(point)
	var at: Vector2
	if node is Node2D:
		at = (node as Node2D).global_position
	elif node.get_parent() is Node2D:
		at = (node.get_parent() as Node2D).global_position
	else:
		return false
	var own: Variant = node.get(&"fire_radius")
	var reach := float(own) if (own is float or own is int) else DEFAULT_FIRE_RADIUS
	return at.distance_to(point) <= reach + radius


## The first fire target (in the group, not `skip`) a flame of `radius` at `point` touches, or null.
static func first_touched(tree: SceneTree, point: Vector2, radius: float, skip: Array = []) -> Node:
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(FIRE_GROUP):
		if node in skip:
			continue
		if touches(node, point, radius):
			return node
	return null


## A light's radius `radius` with a slight flicker (real time, presentation; `share` of the radius,
## FLICKER_SHARE by default, more for a guttering candle), `phase` keeping
## neighbouring lights out of step.
static func flicker(radius: float, phase: float, share: float = FLICKER_SHARE) -> float:
	var t := float(Time.get_ticks_msec()) / 1000.0
	var wave := sin(t * 9.1 + phase) * 0.55 + sin(t * 23.7 + phase * 2.3) * 0.3 + sin(t * 4.3 + phase * 0.7) * 0.15
	return radius * (1.0 + share * wave)


## `abilities.lantern.<path>` as a number, or `fallback`.
static func lantern_number(path: String, fallback: float) -> float:
	var constants := Services.constants()
	var raw: Variant = constants.value("abilities.lantern." + path) if constants != null else null
	return float(raw) if (raw is float or raw is int) else fallback
