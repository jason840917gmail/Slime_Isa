@tool
extends Node2D
## A prop the slime walks through, as a hollow log lying along a road (Gloop Forest's River Roads,
## 2026-11-21): its picture stands on this node (its foot, the y-sort line), and while the slime's
## feet are inside `inside` (this node's coordinates) the picture fades to `fade_alpha`, so the
## slime shows inside it (real time, presentation only). It has no collision of its own: the wood
## or walls beside the road hold the slime in. The editor draws `inside`.
##
## Owner: world.

const Services := preload("res://game/shared/services.gd")

## Where the slime counts as inside (this node's coordinates).
@export var inside: Rect2 = Rect2(-60, -290, 120, 290):
	set(value):
		inside = value
		queue_redraw()
## How faint the picture gets with the slime inside, and how fast it follows (per second).
@export_range(0.0, 1.0) var fade_alpha: float = 0.3
@export var fade_speed: float = 8.0
## The picture that fades.
@export var visual: CanvasItem


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or visual == null:
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var body := player.get(&"body") as Node2D if player != null and is_instance_valid(player) else null
	var target := 1.0
	if body != null and inside.has_point(to_local(body.global_position)):
		target = fade_alpha
	visual.modulate.a = lerpf(visual.modulate.a, target, clampf(delta * fade_speed, 0.0, 1.0))


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(inside, Color(0.9, 0.7, 0.3, 0.8), false, 2.0)
