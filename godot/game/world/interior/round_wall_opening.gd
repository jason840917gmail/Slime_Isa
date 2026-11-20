@tool
class_name RoundWallOpening
extends Node2D
## An opening in a round room's walls (game/world/interior/round_interior_walls.gd; docs/godot/
## INTERIOR_WALLS.md "Round rooms"): a child of the RoundInteriorWalls, dragged onto the ring where the
## opening goes (the ring takes the point of the wall nearest to it; a house door goes to the nearest
## of the ring's top, bottom, left and right, where its leaf stands square). It is cut into the wall
## as on the square rooms, two cells along: a **doorway**, a **cracked** stretch (solid until a Goo
## Bomb blows it: a `cracked-wall` stands on the floor in front of it with `frame_drawn_by_wall` on),
## a **blown** hole, or a closed house **door** (its leaf swings open as the slime goes through).
## With a `target_area_id` a doorway, a door or a blown hole is a way to that world's door
## `target_door_id` (the ring makes the door in the game).
##
## Owner: world (interior walls).

const KINDS: PackedStringArray = ["doorway", "cracked", "blown", "door"]

@export_enum("doorway", "cracked", "blown", "door") var kind: String = "doorway":
	set(value):
		kind = value
		_changed()
@export_group("Door")
## This end's id (the world's other doors and crossings name it).
@export var door_id: String = ""
@export var target_area_id: String = ""
@export var target_door_id: String = ""
@export_group("")


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()


func _changed() -> void:
	queue_redraw()
	var ring := get_parent()
	if ring != null and ring.has_method(&"queue_rebuild"):
		ring.call(&"queue_rebuild")


## Set by the ring when a Goo Bomb blows a cracked opening (`RoundInteriorWalls.change_opening_at`).
func blow() -> void:
	if kind == "cracked":
		kind = "blown"


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# a handle to drag: where the opening is asked for (the ring draws it on the wall)
	draw_circle(Vector2.ZERO, 9.0, Color(1.0, 0.85, 0.3, 0.85))
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 20, Color(0.1, 0.08, 0.05, 0.9), 2.0)
