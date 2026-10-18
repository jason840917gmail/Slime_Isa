@tool
extends TileMapLayer
## The one painted fence layer of a world (docs/godot/FENCES.md): connected fence tiles choose a
## style and direction, join neighboring cells, and add their own shadows and collision. They do
## not paint or alter elevation rims. The painted material always controls the fence style.
##
## In the editor the fences follow the paint at once (the elevation drawing is rebuilt with them);
## its own squares are only a painting aid: hide the layer (eye icon) to see the result. The game
## hides it and WorldService mounts the fence geometry, shadows and level-matched collision.
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
