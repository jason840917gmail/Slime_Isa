@tool
extends TileMapLayer
## The one painted fence layer of a world (docs/godot/FENCES.md): each tile is a fence post whose
## picture chooses its style and the neighbour it joins (an arrow, or every neighbour); the
## fences (fences.gd) draw the posts and rails and give them shadows and collision. They do not
## paint or alter elevation rims.
##
## In the editor the fences follow the paint at once: a stroke rebuilds only the fences (on the
## Elevation's grid and depth map when the world has one, else on flat ground). The layer's own
## squares are only a painting aid: hide the layer (eye icon) to see the result. The game hides it
## and the Elevation (or, in a flat world, Elevation.mount) mounts the fences with their collision.
##
## Owner: world (fences).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const Fences := preload("res://game/world/fences/fences.gd")

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
	var ground := Elevation.find_ground(self)
	if ground == null:
		return
	var elevation := ground.get_node_or_null(NodePath(Elevation.NODE_NAME)) as Elevation
	if elevation == null or elevation.grid == null:
		# No elevation drawing yet (or a flat world): the full mount builds what there is.
		Elevation.mount(ground, false)
		return
	elevation.fences = Fences.mount(ground, elevation, elevation.grid, elevation.occlusion, false)
