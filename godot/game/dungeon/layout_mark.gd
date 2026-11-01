@tool
extends Node2D
class_name LayoutMark
## A mark on a dungeon's map layout (game/dungeon/dungeon_layout.gd), dragged where it shows:
## - "boss": the skull over the boss's room once the map is held, until the Dungeon node's `boss_id` is beaten;
## - "seal": a red bar across a seal's doorway while the dungeon is sealed (turn the node with the
##   doorway: 0 for a north or south doorway, 90 degrees for an east or west one).
##
## Owner: dungeon kit.

@export_enum("boss", "seal") var mark: String = "boss":
	set(value):
		mark = value
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if mark == "seal":
		draw_rect(Rect2(-75, -27, 150, 54), Color("#ff3b2e"))
	else:
		draw_circle(Vector2.ZERO, 60.0, Color("#d6403a"))
		draw_circle(Vector2(-22, -6), 14.0, Color("#2a0d0d"))
		draw_circle(Vector2(22, -6), 14.0, Color("#2a0d0d"))
