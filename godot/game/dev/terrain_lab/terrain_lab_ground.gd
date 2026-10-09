@tool
extends "res://game/world/world_ground.gd"
## The terrain lab's ground (docs/godot/TERRAIN_LAB.md): a world ground (`world_ground.gd`) that
## also mounts the water surface and the terrain edges in the game, since the lab has no
## WorldService to do it. Painting it in the editor rebuilds both.


func _ready() -> void:
	if Engine.is_editor_hint():
		super()
	else:
		refresh()
