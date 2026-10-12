@tool
extends TileMapLayer
## A world's ground layer (docs/godot/TERRAIN_LAB.md): every world scene's `ground` TileMapLayer
## carries this script so the editor shows the world as the game draws it. In the editor it mounts
## the 128 px ground, the animated water and the hand-made terrain edges on itself, as
## `WorldService.register_world` does in the game, and painting the ground rebuilds them. The mounted nodes have no owner, so they are never
## saved with the scene. In the game it does nothing: WorldService mounts them.
##
## Owner: world.

const WaterSurface := preload("res://game/world/water_surface.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")
const GroundSurface := preload("res://game/world/ground_surface.gd")

var _queued := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	refresh()
	changed.connect(_queue_refresh)


## The 128 px ground first, then the water (the edges copy its mask) and the edges right after it,
## so the cliffs an `elevation` layer mounts on this ground stay on top.
func refresh() -> void:
	_queued = false
	var surface := GroundSurface.mount(self)
	var water := get_node_or_null(^"WaterSurface") as WaterSurface
	if water != null:
		water.build(self)
	else:
		water = WaterSurface.mount(self)
	var edges := TerrainEdges.mount(self)
	var index := 0
	for node: Node in [surface, water, edges]:
		if node != null:
			move_child(node, index)
			index += 1


func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	refresh.call_deferred()
