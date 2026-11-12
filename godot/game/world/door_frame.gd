@tool
class_name DoorFrame
extends Node2D
## The door painted on a house's picture (owner, 2026-11-12; docs/godot/CONVENTIONS.md "Door
## frames"): a child of the house scene, standing on the painted door's sill (the middle of its
## bottom edge), `size` wide and high. A house door placed in a world (game/scripts/door.gd, kind
## `door` or `opening`, with a side and no `door_rect` of its own) takes the nearest frame within
## `worldNavigation.doorFrameReachPx`: its leaf swings in that frame, cut from the house's picture,
## and the slime's picture walks up to the sill before it fades into the doorway (and comes down
## from it on the way out). So a house placed or painted anywhere opens by itself, and a house
## with two or three doors has a frame for each.
##
## A house without a door in its art (a stall) has no frame, and so no door to walk into: it gets
## no door node and no room. `swings` off is an entrance with nothing to swing (a curtain, an open
## arch): the slime walks up to it, no leaf moves.
##
## In the editor the frame draws its outline over the house, to place and size it on the painted
## door. Owner: world objects.

const GROUP := &"door_frame"
const OUTLINE := Color(1.0, 0.85, 0.2, 0.9)
const OUTLINE_STILL := Color(0.4, 0.9, 1.0, 0.9)
const ARCH_STEPS := 10

## The painted door's width and height (the house scene's units), up from this node.
@export var size: Vector2 = Vector2(32.0, 48.0):
	set(value):
		size = value
		queue_redraw()
## The arch at the door's top (0 = square).
@export var arch: float = 0.0:
	set(value):
		arch = value
		queue_redraw()
@export_enum("left", "right") var hinge: String = "left"
## Two leaves meeting in the middle, hinged on the outer edges.
@export var double_leaf: bool = false:
	set(value):
		double_leaf = value
		queue_redraw()
## Off: an entrance with no leaf (a curtain, an arch): nothing swings.
@export var swings: bool = true:
	set(value):
		swings = value
		queue_redraw()
## The picture the door is painted on; empty = the sibling named "Visual".
@export var art: Sprite2D


func _enter_tree() -> void:
	add_to_group(GROUP)


## The house's picture (`art`, else the sibling "Visual"); null without one.
func house_art() -> Sprite2D:
	if art != null and is_instance_valid(art):
		return art
	var parent := get_parent()
	return parent.get_node_or_null(^"Visual") as Sprite2D if parent != null else null


## The sill in world space: where the slime's feet stand in the doorway.
func sill() -> Vector2:
	return global_position


## The painted door in world space.
func world_rect() -> Rect2:
	var scaled := size * global_scale.abs()
	return Rect2(global_position - Vector2(scaled.x * 0.5, scaled.y), scaled)


## The arch's height in world space.
func world_arch() -> float:
	return arch * absf(global_scale.y)


## The frame nearest to `at` (world space) within `reach`, null when there is none.
static func nearest(tree: SceneTree, at: Vector2, reach: float) -> DoorFrame:
	var found: DoorFrame = null
	var best := reach * reach
	for node: Node in tree.get_nodes_in_group(GROUP):
		var frame := node as DoorFrame
		if frame == null or not frame.is_visible_in_tree():
			continue
		var distance := frame.global_position.distance_squared_to(at)
		if distance <= best:
			best = distance
			found = frame
	return found


func _draw() -> void:
	if not Engine.is_editor_hint() or size.x <= 0.0 or size.y <= 0.0:
		return
	var colour := OUTLINE if swings else OUTLINE_STILL
	var left := -size.x * 0.5
	var right := size.x * 0.5
	var top := -size.y
	var rise := clampf(arch, 0.0, size.y)
	var points := PackedVector2Array([Vector2(left, 0.0)])
	for i in ARCH_STEPS + 1:
		var t := float(i) / float(ARCH_STEPS)
		points.append(Vector2(lerpf(left, right, t), top + rise * (1.0 - sin(PI * t))))
	points.append(Vector2(right, 0.0))
	points.append(Vector2(left, 0.0))
	draw_polyline(points, colour, 1.0)
	if double_leaf:
		draw_line(Vector2(0.0, top), Vector2.ZERO, colour, 1.0)
	# The sill mark: where the slime's feet stand.
	draw_line(Vector2(-3.0, 0.0), Vector2(3.0, 0.0), colour, 2.0)
