@tool
extends Node2D
class_name DungeonLayout
## A dungeon's map layout (docs/godot/DUNGEON_ROOMS.md "The map layout"): the scene the dungeon map
## is drawn from when the dungeon is one world per room (Fatty's Lair:
## `game/scenes/worlds/rooms/fatty-lair/layout.tscn`). Its children are the rooms (LayoutRoom,
## game/dungeon/layout_room.gd), dragged where they lie on the map, and the marks (LayoutMark,
## game/dungeon/layout_mark.gd): the boss's skull, the seals' bars. Edit it in the editor: open the
## scene, drag the rooms (they snap to the 64-unit grid), pick a room scene in a room's Inspector.
## The Dungeon node of every room world names this scene (`layout`).
##
## In the editor it draws the map's grid of `cell` cells behind the rooms.
##
## Owner: dungeon kit.

const GRID := Color(0.5, 0.5, 0.55, 0.35)

## One map cell (a room of the Lair: 18 x 16 cells of 64 units).
@export var cell: Vector2 = Vector2(1152, 1024):
	set(value):
		cell = value
		queue_redraw()
## The grid's size in cells (drawn in the editor only).
@export var grid: Vector2i = Vector2i(5, 5):
	set(value):
		grid = value
		queue_redraw()


## Every LayoutRoom of the layout.
func layout_rooms() -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in get_children():
		if child.has_method(&"outline_points"):
			out.append(child)
	return out


## The room whose world is `world_id`, or null.
func room_of_world(world_id: String) -> Node:
	for room: Node in layout_rooms():
		if str(room.get(&"world_id")) == world_id:
			return room
	return null


## The room named `room_name` (its CameraRoom's name), or null.
func room_named(room_name: String) -> Node:
	for room: Node in layout_rooms():
		if str(room.get(&"room_name")) == room_name:
			return room
	return null


## Every LayoutMark of the layout.
func marks() -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in get_children():
		if &"mark" in child and child is Node2D and not child.has_method(&"outline_points"):
			out.append(child)
	return out


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	for x in grid.x + 1:
		draw_line(Vector2(x * cell.x, 0), Vector2(x * cell.x, grid.y * cell.y), GRID, 4.0)
	for y in grid.y + 1:
		draw_line(Vector2(0, y * cell.y), Vector2(grid.x * cell.x, y * cell.y), GRID, 4.0)
