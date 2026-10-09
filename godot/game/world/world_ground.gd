@tool
extends TileMapLayer
## A world's ground layer (docs/godot/TERRAIN_LAB.md): every world scene's `ground` TileMapLayer
## carries this script so the editor shows the world as the game draws it. In the editor it mounts
## the animated water and the hand-made terrain edges on itself, as `WorldService.register_world`
## does in the game, and painting rebuilds both. The mounted nodes have no owner, so they are never
## saved with the scene. In the game it does nothing: WorldService mounts them.
##
## Owner: world.

const WaterSurface := preload("res://game/world/water_surface.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")

var _queued := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	refresh()
	changed.connect(_queue_refresh)


## Water first (the edges copy its mask), then the edges right after it, so the cliffs an
## `elevation` layer mounts on this ground stay on top.
func refresh() -> void:
	_queued = false
	var water := get_node_or_null(^"WaterSurface") as WaterSurface
	if water != null:
		water.build(self)
	else:
		water = WaterSurface.mount(self)
		if water != null:
			move_child(water, 0)
	var edges := TerrainEdges.mount(self)
	if edges != null:
		move_child(edges, water.get_index() + 1 if water != null else 0)


func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	refresh.call_deferred()
