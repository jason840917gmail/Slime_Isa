@tool
extends Sprite2D
## One built wall piece placed as a scene (docs/godot/WALLS.md): the `Visual` of the kept
## wall-stone-solid scenes, which the test worlds still place one by one. It shows `style`'s piece of
## `shape` (a WallLayer shape: a bit per joined side, north 1, east 2, south 4, west 8) with the
## stretch of the pattern the cell it stands in takes on a WallLayer, so pieces placed on the
## 64-unit grid join as seamlessly as painted ones. New walls are painted on a WallLayer instead.
##
## Owner: world (walls).

const Walls := preload("res://game/world/walls/wall_layer.gd")

@export var style: String = "stone":
	set(value):
		style = value
		_apply()
@export_range(0, 15) var shape: int = 10:
	set(value):
		shape = value
		_apply()


func _ready() -> void:
	set_notify_transform(Engine.is_editor_hint())
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var rect := Walls.region(style, shape, Vector2i(((global_position - Walls.FOOT) / Walls.CELL).round()))
	if rect.has_area():
		region_rect = rect
