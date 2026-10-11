@tool
extends TileMapLayer
## A world's ground layer (docs/godot/TERRAIN_LAB.md): every world scene's `ground` TileMapLayer
## carries this script so the editor shows the world as the game draws it. In the editor it mounts
## the 128 px ground, the animated water, the hand-made terrain edges and the light by height of
## hand-painted cliffs on itself, as `WorldService.register_world` does in the game, and painting
## (the ground or a cliff layer) rebuilds them. The mounted nodes have no owner, so they are never
## saved with the scene. In the game it does nothing: WorldService mounts them.
##
## Owner: world.

const WaterSurface := preload("res://game/world/water_surface.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")
const GroundSurface := preload("res://game/world/ground_surface.gd")
const GroundShade := preload("res://game/world/ground_shade.gd")

var _queued := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	refresh()
	changed.connect(_queue_refresh)
	for layer in GroundShade.cliff_layers(self):
		layer.changed.connect(_queue_refresh)


## The 128 px ground first, then the water (the edges copy its mask), the edges right after it
## and the light by height last, so the cliffs an `elevation` layer mounts on this ground stay on
## top.
func refresh() -> void:
	_queued = false
	var surface := GroundSurface.mount(self)
	var water := get_node_or_null(^"WaterSurface") as WaterSurface
	if water != null:
		water.build(self)
	else:
		water = WaterSurface.mount(self)
	var edges := TerrainEdges.mount(self)
	var shade := GroundShade.mount(self)
	var index := 0
	for node: Node in [surface, water, edges, shade]:
		if node != null:
			move_child(node, index)
			index += 1


func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	refresh.call_deferred()
