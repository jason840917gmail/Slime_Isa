@tool
extends TileMapLayer
## The painted ground levels of a world (docs/godot/ELEVATION.md): a TileMapLayer named
## `elevation` beside the ground layer, on the same grid, using elevation_tileset.tres. Paint a
## level (−3 … 3; unpainted cells are level 0) on the cells whose top you walk on; the cliff wall
## hangs below the painted area's south edges by itself. Single-cell steps make 45° edges.
##
## In the editor the cliffs follow the paint (and the ground's paint) at once: this layer mounts
## the Elevation drawing under the ground layer. Its own squares are only a painting aid: hide the
## layer (eye icon) to see the result; the game hides it and WorldService mounts the elevation
## with its collision.
##
## Owner: world (elevation).

const Elevation := preload("res://game/world/elevation/elevation.gd")

var _queued := false
var _ground: TileMapLayer


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		return
	changed.connect(_queue_rebuild)
	_ground = Elevation.find_ground(self)
	if _ground != null and not _ground.changed.is_connected(_queue_rebuild):
		_ground.changed.connect(_queue_rebuild)
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
