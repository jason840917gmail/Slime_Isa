@tool
extends TileMapLayer
## The terrain lab's ground (docs/godot/TERRAIN_LAB.md): a ground layer on the converted terrain
## tile set that mounts the water surface and the terrain edges on itself, in the editor too, as
## WorldService.register_world does for a world. Painting it in the editor rebuilds both.

const WaterSurface := preload("res://game/world/water_surface.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")

var _queued := false


func _ready() -> void:
	WaterSurface.mount(self)
	TerrainEdges.mount(self)
	if Engine.is_editor_hint():
		changed.connect(_queue_refresh)


## Water first (the edges copy its mask), then the edges.
func refresh() -> void:
	_queued = false
	var water := get_node_or_null(^"WaterSurface") as WaterSurface
	if water != null:
		water.build(self)
	elif WaterSurface.mount(self) != null:
		move_child(get_node(^"WaterSurface"), 0)
	TerrainEdges.mount(self)


func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	refresh.call_deferred()
