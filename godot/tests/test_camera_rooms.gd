extends RefCounted
## Camera rooms (game/world/camera_room.gd; docs/godot/DUNGEON_ROOMS.md "Camera rooms in the
## editor"): a turned and scaled room's bounds, its point test and its outline agree, and an upright
## room's bounds are its position and size. The editor's handles (addons/camera_room_handles/plugin.gd,
## its static drag maths only: nothing here needs the editor) snap a dropped point on the world's grid
## in a room under a parent placed off the grid, and moving the top-left corner of a turned, unevenly
## scaled room keeps its opposite corner put.

const TestContext := preload("res://tests/lib/test_context.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
## The handles' drag maths (static: the plugin itself needs the editor).
const Handles := preload("res://addons/camera_room_handles/plugin.gd")

## Away from the world (north-west of its origin) and on the 64-unit grid (-100 cells), so the camera
## never keeps to these rooms.
const FAR := Vector2(-6400.0, -6400.0)


func test_a_turned_room_agrees_with_itself(t: TestContext) -> void:
	var holder := _holder(t, FAR + Vector2(10.0, 6.0))
	var room := CameraRoom.new()
	room.size = Vector2(512.0, 256.0)
	room.rotation = deg_to_rad(30.0)
	room.scale = Vector2(2.0, 1.0)
	holder.add_child(room)
	var corners := room.outline_global()
	var bounds := room.rect()
	var expected := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		expected = expected.expand(corner)
	t.near_vec(bounds.position, expected.position, 0.01, "the turned room's bounds' corner")
	t.near_vec(bounds.size, expected.size, 0.01, "the turned room's bounds' size")
	t.check(room.contains(room.to_global(room.size * 0.5)), "the turned room's middle is not in it")
	t.check(not room.contains(bounds.position + Vector2(2.0, 2.0)), "a corner of its bounds outside the turned room is in it")
	var upright := CameraRoom.new()
	upright.position = Vector2(64.0, 128.0)
	upright.size = Vector2(448.0, 448.0)
	holder.add_child(upright)
	t.near_vec(upright.rect().position, holder.global_position + Vector2(64.0, 128.0), 0.001, "the upright room's position")
	t.near_vec(upright.rect().size, Vector2(448.0, 448.0), 0.001, "the upright room's size")
	t.check(upright.contains(holder.global_position + Vector2(65.0, 129.0)), "the upright room's top-left cell is not in it")
	holder.free()


func test_the_handles_snap_on_the_world_grid_and_keep_the_far_corner(t: TestContext) -> void:
	var holder := _holder(t, FAR + Vector2(10.0, 6.0))
	var room := CameraRoom.new()
	room.position = Vector2(20.0, 4.0)
	room.size = Vector2(512.0, 384.0)
	holder.add_child(room)
	# A point dropped at FAR + (200, 130) lands on the world's grid, FAR + (192, 128), though the room
	# and its parent are off the grid.
	var local := Handles.snapped_local(FAR + Vector2(200.0, 130.0), room.get_global_transform(), false)
	t.near_vec(room.to_global(local), FAR + Vector2(192.0, 128.0), 0.01, "the snapped point")
	t.near_vec(Handles.snapped_local(FAR + Vector2(200.4, 130.6), Transform2D.IDENTITY, true), FAR + Vector2(200.0, 131.0), 0.001,
		"a free point (Alt)")
	# The bottom-right corner dragged there: it lands there, the room does not move.
	var moved := Handles.corner_drag(room.transform, room.size, 2, local)
	room.position = moved.position
	room.size = moved.size
	t.near_vec(room.to_global(room.size), FAR + Vector2(192.0, 128.0), 0.01, "the dragged corner")
	t.near_vec(room.position, Vector2(20.0, 4.0), 0.001, "the room moved for its bottom-right corner")
	# A turned, unevenly scaled room: its top-left corner moves, the bottom-right one stays.
	room.rotation = deg_to_rad(30.0)
	room.scale = Vector2(2.0, 0.5)
	room.size = Vector2(512.0, 384.0)
	var far_corner := room.to_global(room.size)
	moved = Handles.corner_drag(room.transform, room.size, 0, Vector2(128.0, 64.0))
	room.position = moved.position
	room.size = moved.size
	t.near_vec(room.size, Vector2(384.0, 320.0), 0.001, "the turned room's size")
	t.near_vec(room.to_global(room.size), far_corner, 0.01, "the turned room's far corner")
	# Never smaller than one cell.
	t.near_vec(Handles.corner_drag(room.transform, room.size, 2, Vector2(8.0, 8.0)).size, Vector2(64.0, 64.0), 0.001,
		"the smallest room")
	holder.free()


## A plain node at `at` under the tree's root, to hold the test's rooms.
func _holder(t: TestContext, at: Vector2) -> Node2D:
	var holder := Node2D.new()
	holder.position = at
	t.tree.root.add_child(holder)
	return holder
