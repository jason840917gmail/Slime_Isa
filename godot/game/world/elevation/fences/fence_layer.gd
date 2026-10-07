@tool
extends TileMapLayer
## The painted fences of a world (docs/godot/FENCES.md): a TileMapLayer named `fences` beside the
## ground and `elevation` layers, on the same grid, using fence_tileset.tres. Paint a style on the
## cells of a hill's (or a hole's surroundings') top: a fence of that style stands inside every rim
## of those cells where a body could drop ("auto": the style of the ground on top).
##
## In the editor the fences follow the paint at once (the elevation drawing is rebuilt with them);
## its own squares are only a painting aid: hide the layer (eye icon) to see the result. The game
## hides it and WorldService mounts the elevation, fences included, with their collision.
##
## Owner: world (elevation fences).

const Elevation := preload("res://game/world/elevation/elevation.gd")

var _queued := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		return
	changed.connect(_queue_rebuild)
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	Elevation.mount(Elevation.find_ground(self), false)
