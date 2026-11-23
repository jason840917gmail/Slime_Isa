@tool
extends Node2D
## A beaver dam (Gloop Forest's River Roads, 2026-11-21; docs/design/2026-11-21-gloop-river-roads.md):
## sticks and mud holding a pond. A Goo Bomb blast that reaches it (group `blast_targets`,
## `receive_blast`, as cracked walls) blows it apart: the story flag `flag_id` is set, and the pond
## drains for good. Its cells (`pond`, the chunk's ground cells) turn to `drained_source` ground,
## which has no water collision, so the slime walks the pond bed, and `sunk` (a chest lying on the
## bed) shows. With the flag set the pond is dry when the world is built.
##
## Owner: world (water).

const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const SHEET := 19
const BREAK_TEXT := "The dam gives way!"
const DEBRIS_TINT := Color(0.52, 0.37, 0.22)

@export var flag_id: String = "gloop-forest.beaver-dam"
## The pond's cells on the world's `ground` layer.
@export var pond: Rect2i = Rect2i(0, 0, 1, 1)
## The ground the pond bed shows once drained (terrain_tileset.tres: 4 forest floor).
@export var drained_source: int = 4
## The dam's picture, gone once blown.
@export var visual: CanvasItem
## What lies on the pond bed (hidden until it drains).
@export var sunk: CanvasItem

var _drained := false


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(BlastBarrier.GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var run := Services.run()
	if run != null and not flag_id.is_empty() and run.has_flag(flag_id):
		_drain.call_deferred(false)
	elif sunk != null:
		sunk.visible = false


func blast_point() -> Vector2:
	return global_position + Vector2(0.0, -40.0)


## A Goo Bomb blast reached it: it gives way and the pond drains for good.
func receive_blast(_hit: Dictionary) -> bool:
	if _drained:
		return false
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	_drain(true)
	return true


func _drain(show_effect: bool) -> void:
	_drained = true
	var ground := owner.get_node_or_null(^"ground") as TileMapLayer if owner != null else null
	if ground != null:
		for y in range(pond.position.y, pond.end.y):
			for x in range(pond.position.x, pond.end.x):
				ground.set_cell(Vector2i(x, y), drained_source, Vector2i(posmod(x, SHEET), posmod(y, SHEET)))
		if ground.has_method(&"refresh"):
			ground.call(&"refresh")
	if visual != null:
		visual.visible = false
	if sunk != null:
		sunk.visible = true
	if show_effect:
		BlastBarrier.give_way(global_position - Vector2(0.0, 40.0), BREAK_TEXT, DEBRIS_TINT, 24, 14)
