extends RefCounted
class_name DungeonMapDraw
## Draws a dungeon's rooms (docs/godot/DUNGEONS.md "The dungeon map"), shared by the minimap overlay
## (dungeon_minimap.gd) and the map screen's page (dungeon_map_page.gd). The rooms are the Dungeon
## node's CameraRooms in this world:
## - a room the slime has stood in: filled in parchment, edged;
## - with the map: every other room, a dim fill with a dashed-looking thin edge (fog lifted);
## - without the map, a room never visited is not drawn (fog);
## - the room the slime is in: a gold ring;
## - with the compass: a red mark in the boss's room (a RoomFight with a `boss_id`, or a node in the
##   group `dungeon_map_mark` with `mark` = "boss") and a gold dot on each chest not opened yet.
## `to_view` maps a global point to the canvas.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const VISITED_FILL := Color("#d9c491")
const VISITED_EDGE := Color("#6b4a26")
const MAPPED_FILL := Color("#5d6f86")
const MAPPED_EDGE := Color("#9fb2c8")
const CURRENT_RING := Color("#ffd277")
const BOSS_MARK := Color("#d6403a")
const CHEST_MARK := Color("#f5c542")
const MARK_GROUP := &"dungeon_map_mark"
const CHEST_GROUP := &"chest"
const FIGHT_GROUP := &"room_fight"
## Rooms are drawn this share of a room inset, so neighbours show a gap.
const INSET_SHARE := 0.06


## The bounding rect (global) of the dungeon's rooms in this world.
static func bounds(dungeon: Node) -> Rect2:
	var out := Rect2()
	var first := true
	for room: Dictionary in dungeon.call(&"rooms"):
		var rect: Rect2 = room["rect"]
		out = rect if first else out.merge(rect)
		first = false
	return out


## Draws the rooms on `canvas`; `to_view` (Callable: Vector2 -> Vector2) maps global points.
## `player_point` (global, or Vector2.INF) gets the slime's dot when `with_dot`.
static func draw(canvas: CanvasItem, dungeon: Node, to_view: Callable, player_point: Vector2, with_dot: bool) -> void:
	var run := Services.run()
	if dungeon == null or run == null:
		return
	var id := str(dungeon.get(&"dungeon_id"))
	var has_map := DungeonState.has_item(run, id, DungeonState.MAP)
	var has_compass := DungeonState.has_item(run, id, DungeonState.COMPASS)
	var current := str(dungeon.call(&"current_room_key"))
	var rooms: Array = dungeon.call(&"rooms")
	for room: Dictionary in rooms:
		var visited := DungeonState.is_visited(run, id, str(room["key"]))
		if not visited and not has_map:
			continue
		var box := _view_rect(room["rect"], to_view)
		var inset := minf(box.size.x, box.size.y) * INSET_SHARE
		box = box.grow(-inset)
		if visited:
			canvas.draw_rect(box, VISITED_FILL)
			canvas.draw_rect(box, VISITED_EDGE, false, maxf(1.0, inset * 0.35))
		else:
			canvas.draw_rect(box, Color(MAPPED_FILL, 0.55))
			canvas.draw_rect(box, Color(MAPPED_EDGE, 0.7), false, 1.0)
		if str(room["key"]) == current:
			canvas.draw_rect(box.grow(inset * 0.5), CURRENT_RING, false, maxf(1.5, inset * 0.6))
	if has_compass:
		for point: Vector2 in boss_points(dungeon):
			var at: Vector2 = to_view.call(point)
			_draw_skull(canvas, at, 6.0)
		for point: Vector2 in chest_points(dungeon):
			var at: Vector2 = to_view.call(point)
			canvas.draw_circle(at, 3.6, Color(0, 0, 0, 0.55))
			canvas.draw_circle(at, 2.6, CHEST_MARK)
	if with_dot and player_point.is_finite():
		var at: Vector2 = to_view.call(player_point)
		canvas.draw_circle(at, 5.25, Color("#0b1020"))
		canvas.draw_circle(at, 4.0, Color("#72d8ff"))


## The boss's spots: the middle of every RoomFight with a boss not beaten yet, and every
## `dungeon_map_mark` node marked "boss".
static func boss_points(dungeon: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var tree := dungeon.get_tree()
	var run := Services.run()
	var id := str(dungeon.get(&"dungeon_id"))
	for node: Node in tree.get_nodes_in_group(FIGHT_GROUP):
		var boss := str(node.get(&"boss_id"))
		if not boss.is_empty() and not DungeonState.is_boss_beaten(run, id, boss) and node.has_method(&"rect"):
			out.append((node.call(&"rect") as Rect2).get_center())
	for node: Node in tree.get_nodes_in_group(MARK_GROUP):
		if node is Node2D and str(node.get(&"mark")) == "boss":
			out.append((node as Node2D).global_position)
	return out


## The chests not opened yet (in a room of the dungeon, shown: a hidden chest that has not risen yet
## counts too).
static func chest_points(dungeon: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for node: Node in dungeon.get_tree().get_nodes_in_group(CHEST_GROUP):
		if not node.has_method(&"is_empty") or bool(node.call(&"is_empty")):
			continue
		var root := node.get_parent() as Node2D
		if root != null and dungeon.call(&"room_at", root.global_position) != null:
			out.append(root.global_position)
	return out


static func _view_rect(rect: Rect2, to_view: Callable) -> Rect2:
	var a: Vector2 = to_view.call(rect.position)
	var b: Vector2 = to_view.call(rect.end)
	return Rect2(a, b - a).abs()


## A tiny red skull-ish mark: a round head with two eye holes.
static func _draw_skull(canvas: CanvasItem, at: Vector2, r: float) -> void:
	canvas.draw_circle(at, r + 1.2, Color(0, 0, 0, 0.6))
	canvas.draw_circle(at, r, BOSS_MARK)
	canvas.draw_circle(at + Vector2(-r * 0.38, -r * 0.1), r * 0.24, Color("#2a0d0d"))
	canvas.draw_circle(at + Vector2(r * 0.38, -r * 0.1), r * 0.24, Color("#2a0d0d"))
