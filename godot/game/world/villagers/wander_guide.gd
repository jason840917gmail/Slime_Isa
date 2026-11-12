@tool
extends Node2D
## The editor's picture of where a villager or an animal goes (docs/godot/VILLAGERS.md): the circle
## of its `wander_radius` around where it stands, and a line to the node it follows. `source` is
## the node with those properties (a villager's NpcScript, an animal's root). Editor only: in the
## game it frees itself.
##
## Owner: world (villagers).

const CIRCLE_COLOR := Color(0.45, 0.85, 1.0, 0.8)
const FOLLOW_COLOR := Color(1.0, 0.75, 0.35, 0.8)
const LINE_WIDTH := 2.0
const SEGMENTS := 48

## The node holding `wander_radius` and `follow`.
@export var source: Node


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or source == null:
		return
	var radius: Variant = source.get(&"wander_radius")
	if radius != null and float(radius) > 0.0:
		draw_arc(Vector2.ZERO, float(radius) / maxf(0.001, global_scale.x), 0.0, TAU, SEGMENTS, CIRCLE_COLOR, LINE_WIDTH)
	var follow: Variant = source.get(&"follow")
	if follow is NodePath and not (follow as NodePath).is_empty():
		var leader := source.get_node_or_null(follow) as Node2D
		if leader != null:
			draw_line(Vector2.ZERO, to_local(leader.global_position), FOLLOW_COLOR, LINE_WIDTH)
