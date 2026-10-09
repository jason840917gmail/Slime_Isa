@tool
extends TileMapLayer
## The painted wall styles of a world (docs/godot/ELEVATION.md "Wall styles"): a TileMapLayer named
## `cliffs` beside the ground and `elevation` layers, on the same grid, using cliff_tileset.tres.
## Paint a style on the cells of a top: the cliff walls hanging from that top, their corner stones
## and the railings of the flights of stairs leaving it take that style. Unpainted tops take the
## style of their ground (Elevation.GROUND_WALL_STYLES); a hole's far wall hangs from the ground
## around the hole, so paint those cells for it.
##
## In the editor the walls follow the paint at once (the elevation drawing is rebuilt); its own
## squares are only a painting aid: hide the layer (eye icon) to see the result. The game hides it.
##
## Owner: world (elevation).

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
