extends StaticBody2D
## Scene script of `object.rubble-heap` (game/scenes/objects/rubble-heap.tscn; bomb-lantern-and-
## secrets design section 3, the Goo Bomb's lock; BODY_SHAPES.md "Goo Bomb"). A heap of loose rocks
## choking a path (asset/abilities/goo-bomb/rubble-2x1.webp: heap | scatter, 224 x 160 each, drawn
## at half size). Only a blast moves it: weapons, throws and the Slam clink off (`refusal_text`).
## A Goo Bomb blast whose ellipse holds its root (`receive_blast`; group `blast_targets`) leaves a
## pebble scatter on the ground that no longer collides and sets the story flag `flag_id` (read at
## load: gone for good; a story variant on the same flag can show a prize).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")

const BREAK_TEXT := "The rocks fly apart!"
const ROCK_TINT := Color("#8f7a5c")
const FRAME_HEAP := 0
const FRAME_SCATTER := 1
## The scatter lies flat under the bodies.
const SCATTER_Z := -1

## Story flag set when it is blown.
@export var flag_id: String = ""
@export var refusal_text: String = "Too many rocks to move. It needs a blast."

var _broken: bool = false


func _enter_tree() -> void:
	add_to_group(BlastBarrier.GROUP)
	var run := Services.run()
	_broken = not flag_id.is_empty() and run != null and run.has_flag(flag_id)


func _ready() -> void:
	if _broken:
		_scatter(false)
	else:
		BlastBarrier.register(get_node_or_null(^"DamageArea") as Area2D, self)


func _exit_tree() -> void:
	BlastBarrier.unregister(get_node_or_null(^"DamageArea") as Area2D)


func is_broken() -> bool:
	return _broken


func blast_point() -> Vector2:
	return global_position


func receive_blast(_hit: Dictionary) -> bool:
	if _broken:
		return false
	_broken = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	_scatter(true)
	BlastBarrier.give_way(global_position - Vector2(0.0, 10.0), BREAK_TEXT, ROCK_TINT, 18, 10)
	return true


func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _broken}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	return BlastBarrier.refuse(global_position - Vector2(0.0, 30.0), refusal_text)


## The pebble scatter: no collision, no hurtbox.
func _scatter(_now: bool) -> void:
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		visual.frame = FRAME_SCATTER
		visual.z_as_relative = false
		visual.z_index = SCATTER_Z
	set_deferred(&"collision_layer", 0)
	var shape := get_node_or_null(^"BodyShape") as CollisionShape2D
	if shape != null:
		shape.set_deferred(&"disabled", true)
	var area := get_node_or_null(^"DamageArea") as Area2D
	if area != null:
		BlastBarrier.unregister(area)
		area.queue_free()
