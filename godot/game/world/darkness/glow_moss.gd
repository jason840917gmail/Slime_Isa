@tool
extends Node2D
## A tuft of glow-moss (Gloop Forest's glow grove, 2026-11-21; docs/godot/DARKNESS.md): a light
## source (group `light_sources`, fire_targets.gd's contract) that opens a small soft hole in a dark
## room's darkness, and a few faint glowing specks drawn over the dark, so a dim grove shows its way.
## It never goes out and burns nothing.
##
## Owner: world (fire and darkness).

## Its light's radius (px).
@export var radius: float = 44.0:
	set(value):
		radius = value
		queue_redraw()
## The specks' colour.
@export var color: Color = Color(0.5, 1.0, 0.8, 0.9):
	set(value):
		color = value
		queue_redraw()

## Over a dark room's darkness (dark_room.gd's OVERLAY_Z is 45).
const SPECKS_Z := 46
const SPECKS: Array[Vector2] = [Vector2(-10, 2), Vector2(4, -3), Vector2(13, 4), Vector2(-3, 8), Vector2(8, 11)]


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"light_sources")


func _ready() -> void:
	z_index = SPECKS_Z
	z_as_relative = false


## The light: global x, global y and radius.
func light_circle() -> Vector3:
	return Vector3(global_position.x, global_position.y, radius)


func _draw() -> void:
	for speck: Vector2 in SPECKS:
		draw_circle(speck, 3.5, Color(color, color.a * 0.35))
		draw_circle(speck, 1.8, color)
