extends RefCounted
## The door area handles (addons/door_area_handles/; docs/godot/CONVENTIONS.md "A door's area in the
## editor"), the part that needs no editor (door_area.gd): a door's area is its `trigger_rect` around
## the door node, as door.gd's own `trigger_global` has it; selecting the door's Node2D finds its
## script node; a dragged corner keeps the opposite one and snaps the numbers, the grip moves the
## area, and no drag turns it inside out.

const TestContext := preload("res://tests/lib/test_context.gd")
const DoorArea := preload("res://addons/door_area_handles/door_area.gd")
const Door := preload("res://game/scripts/door.gd")

## Away from the world, so nothing there meets these doors.
const FAR := Vector2(-6400.0, -6400.0)
## The mushroom home's yard door (level-1-c4).
const YARD := Rect2(-24.0, -32.0, 32.0, 64.0)


func test_the_area_is_the_trigger_rect_around_the_door_node(t: TestContext) -> void:
	var node := Node2D.new()
	node.position = FAR + Vector2(704.0, 204.0)
	var door := Door.new()
	door.door_id = "yard"
	door.side = "north"
	door.trigger_rect = YARD
	node.add_child(door)
	t.tree.root.add_child(node)
	t.check(DoorArea.door_of(node) == door, "the door's Node2D does not lead to its script node")
	t.check(DoorArea.door_of(door) == door, "the script node is not its own door")
	t.check(DoorArea.door_of(t.tree.root) == null, "a node that is no door has a door area")
	t.check(DoorArea.uses_rect(door), "a door without shapes is not set off by its rect")
	var world := DoorArea.world_rect(door)
	t.near_vec(world.position, door.trigger_global().position, 0.001, "the area's corner (door.gd's own trigger)")
	t.near_vec(world.position, FAR + Vector2(680.0, 172.0), 0.001, "the area's corner in the world")
	t.near_vec(world.size, YARD.size, 0.001, "the area's size")
	t.near_vec(DoorArea.push_direction(door), Vector2.UP, 0.001, "a north door is pushed up into")
	t.check(not DoorArea.travels(door), "a door without a target travels")
	node.free()


func test_drags_snap_and_never_turn_the_area_inside_out(t: TestContext) -> void:
	# The bottom-right corner: it lands on the 4-unit grid, the top-left one stays.
	var grown := DoorArea.drag(YARD, 2, Vector2(41.0, 23.0), 4.0)
	t.near_vec(grown.position, YARD.position, 0.001, "the top-left corner moved for the bottom-right one")
	t.near_vec(grown.size, Vector2(72.0, 88.0), 0.001, "the grown area")
	# The top-left corner: the bottom-right one stays.
	var cut := DoorArea.drag(YARD, 0, Vector2(11.0, 9.0), 4.0)
	t.near_vec(cut.position, Vector2(-12.0, -24.0), 0.001, "the dragged top-left corner")
	t.near_vec(cut.end, YARD.end, 0.001, "the bottom-right corner moved for the top-left one")
	# Single units (Alt).
	t.near_vec(DoorArea.drag(YARD, 2, Vector2(5.4, 0.0), 1.0).size, Vector2(37.0, 64.0), 0.001, "a fine drag")
	# Dragged past the opposite corner: the smallest area, not one inside out.
	var crushed := DoorArea.drag(YARD, 2, Vector2(-400.0, -400.0), 4.0)
	t.near_vec(crushed.position, YARD.position, 0.001, "the crushed area's corner")
	t.near_vec(crushed.size, Vector2(4.0, 4.0), 0.001, "the smallest area")
	# The grip moves it whole.
	var moved := DoorArea.drag(YARD, DoorArea.HANDLE_MOVE, Vector2(-20.0, 12.0), 4.0)
	t.near_vec(moved.position, Vector2(-44.0, -20.0), 0.001, "the moved area's corner")
	t.near_vec(moved.size, YARD.size, 0.001, "the moved area's size")
