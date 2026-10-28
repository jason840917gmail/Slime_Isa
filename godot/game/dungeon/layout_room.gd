@tool
extends Node2D
class_name LayoutRoom
## One room of a dungeon's map layout (a DungeonLayout scene, game/dungeon/dungeon_layout.gd;
## docs/godot/DUNGEON_ROOMS.md "The map layout"). Fatty's Lair is one world per room: the map draws
## every room from its layout, where each room is one of these nodes, placed by dragging it in the
## editor.
##
## - `room_scene`: the room's world scene. Picking it fills in the rest from the scene (the editor
##   reads it, nothing is typed): `world_id` (its world-definition's map id), `room_name` (its
##   CameraRoom's name, the room's key on the map and in the record), `size` and `outline` (the
##   CameraRoom's), `camera_offset` (where that CameraRoom lies in its scene).
## - `camera_room`: which CameraRoom of the scene this map room is ("" = its first). A world may hold
##   several rooms parted by low dividers (R5: the eye hall, the lower hall and the key alcove): each
##   has its own map room, all naming the one scene.
## - Its position is where the room lies on the map (dungeon units: 64 a cell; a room of the Lair is
##   1152 x 1024). Dragged in the editor it snaps to the 64-unit grid.
## The editor draws it as the map shows it: its outline filled, its name; neighbours with a gap.
##
## Owner: dungeon kit.

const FILL := Color(0.85, 0.77, 0.57, 0.55)
const EDGE := Color(0.42, 0.29, 0.15, 1.0)
const TEXT := Color(0.15, 0.1, 0.05, 1.0)
const SNAP := 64.0

## The room's world scene (a room scene with a `world-definition`).
@export_file("*.tscn") var room_scene: String = "":
	set(value):
		room_scene = value
		# picked in the Inspector (not while the layout loads: what it read is saved)
		if Engine.is_editor_hint() and is_inside_tree():
			_read_scene()
		queue_redraw()
## The CameraRoom of `room_scene` this map room is ("" = its first; see the notes).
@export var camera_room: String = "":
	set(value):
		camera_room = value
		if Engine.is_editor_hint() and is_inside_tree():
			_read_scene()
		queue_redraw()
## Read from `room_scene`: its world's map id.
@export var world_id: String = ""
## Read from `room_scene`: its CameraRoom's name.
@export var room_name: String = ""
## Read from `room_scene`: its CameraRoom's size.
@export var size: Vector2 = Vector2(1152, 1024):
	set(value):
		size = value
		queue_redraw()
## Read from `room_scene`: its CameraRoom's outline (local), empty for a rectangle.
@export var outline: PackedVector2Array = PackedVector2Array():
	set(value):
		outline = value
		queue_redraw()
## Read from `room_scene`: where its CameraRoom lies in its scene (zero for a world of one room). The
## world's own place on the map is this node's position less it (Dungeon `_read_layout`).
@export var camera_offset: Vector2 = Vector2.ZERO
## Its floor: 0 the ground, 1 above it, -1 below (the map's floor tabs; a stair joins the floors it
## links). Only the map reads it.
@export var floor_level: int = 0
## Press in the Inspector to read the room scene again (after its CameraRoom changed).
@export var read_again: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_read_scene()


func _ready() -> void:
	set_notify_transform(true)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var snapped := position.snapped(Vector2(SNAP, SNAP))
		if snapped != position:
			position = snapped


## The room's rectangle in dungeon units.
func rect() -> Rect2:
	return Rect2(position, size)


## The room's outline in dungeon units (its rectangle's corners when it has none).
func outline_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	if outline.size() >= 3:
		for point: Vector2 in outline:
			points.append(position + point)
		return points
	for point: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		points.append(position + point)
	return points


## Reads `world_id`, `room_name`, `size`, `outline` and `camera_offset` from the room scene (its
## state: nothing is built), the CameraRoom named `camera_room` (else the first).
func _read_scene() -> void:
	if room_scene.is_empty() or not ResourceLoader.exists(room_scene):
		return
	var packed := load(room_scene) as PackedScene
	var state := packed.get_state() if packed != null else null
	if state == null:
		return
	var found := false
	for index: int in state.get_node_count():
		var path := str(state.get_node_path(index))
		var parent := str(state.get_node_path(index, true))
		if path.ends_with("world-definition"):
			for p: int in state.get_node_property_count(index):
				if state.get_node_property_name(index, p) == &"map_id":
					world_id = str(state.get_node_property_value(index, p))
		elif (parent == "./CameraRooms" or parent == "CameraRooms") and not found \
				and (camera_room.is_empty() or String(state.get_node_name(index)) == camera_room):
			found = true
			room_name = String(state.get_node_name(index))
			outline = PackedVector2Array()
			camera_offset = Vector2.ZERO
			for p: int in state.get_node_property_count(index):
				var property_name := state.get_node_property_name(index, p)
				if property_name == &"size":
					size = state.get_node_property_value(index, p)
				elif property_name == &"outline":
					outline = state.get_node_property_value(index, p)
				elif property_name == &"position":
					camera_offset = state.get_node_property_value(index, p)
	if not room_name.is_empty():
		name = room_name
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var inset := 24.0
	var local := PackedVector2Array()
	for point: Vector2 in outline_points():
		local.append(point - position)
	if local.size() >= 3:
		var centre := Vector2.ZERO
		for point: Vector2 in local:
			centre += point
		centre /= float(local.size())
		var shrunk := PackedVector2Array()
		for point: Vector2 in local:
			shrunk.append(point + (centre - point).normalized() * inset)
		draw_colored_polygon(shrunk, FILL)
		var ring := shrunk.duplicate()
		ring.append(shrunk[0])
		draw_polyline(ring, EDGE, 6.0)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := room_name if not room_name.is_empty() else "(pick a room scene)"
		draw_string(font, Vector2(48, 96), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, TEXT)
		if not world_id.is_empty():
			draw_string(font, Vector2(48, 160), world_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, TEXT)
