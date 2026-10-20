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
##   group `dungeon_map_mark` with `mark` = "boss") and a gold dot on each chest not opened yet;
## - a seal shut (dungeon_seal.gd, `mark` = "seal"): a red bar across its doorway, with or without
##   the compass, while the dungeon is sealed (docs/godot/DUNGEONS.md "The seal").
## `to_view` maps a global point to the canvas. The minimap draws `only_current`: the slime's room
## alone with the marks inside it (owner, 2026-10-19: the rooms around it, at the minimap's scale,
## covered the play area); the map screen (M) draws every room.
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
const SEAL_MARK := Color("#ff3b2e")
## A seal's bar on the map, in room units (a doorway is two cells, 128 wide).
const SEAL_BAR := Vector2(150.0, 54.0)
const MARK_GROUP := &"dungeon_map_mark"
const CHEST_GROUP := &"chest"
## The chest scenes' script node (game/scripts/chest.gd), whose overrides a room scene saves.
const CHEST_SCRIPT_NODE := &"ChestScript"
const GooHeart := preload("res://game/scripts/goo_heart.gd")
const FIGHT_GROUP := &"room_fight"
## Rooms are drawn this share of a room inset, so neighbours show a gap.
const INSET_SHARE := 0.06

## Room scene path -> its chests (`scene_chests`), read once a session.
static var _scene_chests: Dictionary = {}


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
## `player_point` (global, or Vector2.INF) gets the slime's dot when `with_dot`. `only_current`: the
## slime's room alone, and only the seals and compass marks inside it (the minimap).
static func draw(canvas: CanvasItem, dungeon: Node, to_view: Callable, player_point: Vector2, with_dot: bool, only_current: bool = false) -> void:
	var run := Services.run()
	if dungeon == null or run == null:
		return
	var id := str(dungeon.get(&"dungeon_id"))
	var has_map := DungeonState.has_item(run, id, DungeonState.MAP)
	var has_compass := DungeonState.has_item(run, id, DungeonState.COMPASS)
	var current := str(dungeon.call(&"current_room_key"))
	var rooms: Array = dungeon.call(&"rooms")
	# where the marks may be drawn: anywhere, or the slime's room only
	var shown := func(_point: Vector2) -> bool: return true
	if only_current:
		var here := Rect2()
		for room: Dictionary in rooms:
			if str(room["key"]) == current:
				here = room["rect"]
		shown = func(point: Vector2) -> bool: return here.has_area() and here.has_point(point)
	for room: Dictionary in rooms:
		if only_current and str(room["key"]) != current:
			continue
		var visited := DungeonState.is_visited(run, id, str(room["key"]))
		if not visited and not has_map:
			continue
		var room_node := room.get("node") as Node
		var outline: Variant = room_node.get(&"outline") if room_node != null else null
		# A room of another world (a dungeon's layout, dungeon_layout.gd): its own outline points.
		if room_node == null and (room.get("outline", PackedVector2Array()) as PackedVector2Array).size() >= 3:
			outline = room["outline"]
		if outline is PackedVector2Array and outline.size() >= 3:
			var polygon := PackedVector2Array()
			for point: Vector2 in room["outline"]:
				polygon.append(to_view.call(point))
			canvas.draw_colored_polygon(polygon, VISITED_FILL if visited else Color(MAPPED_FILL, 0.55))
			polygon.append(polygon[0])
			canvas.draw_polyline(polygon, CURRENT_RING if str(room["key"]) == current else (VISITED_EDGE if visited else MAPPED_EDGE), 1.5)
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
	for seal: Node2D in seal_nodes(dungeon):
		if bool(shown.call(seal.global_position)):
			_draw_seal(canvas, seal, to_view)
	# The layout's seal marks (the seals of the other room worlds) while the dungeon is sealed.
	if DungeonState.is_sealed(run, id) and dungeon.has_method(&"layout_marks"):
		for mark: Dictionary in dungeon.call(&"layout_marks"):
			if str(mark["mark"]) == "seal" and not _seal_drawn_near(dungeon, mark["at"]) and bool(shown.call(mark["at"])):
				_draw_seal_at(canvas, mark["at"], float(mark["rotation"]), to_view)
	if has_compass:
		for point: Vector2 in boss_points(dungeon):
			if not bool(shown.call(point)):
				continue
			var at: Vector2 = to_view.call(point)
			_draw_skull(canvas, at, 6.0)
		for point: Vector2 in chest_points(dungeon):
			if not bool(shown.call(point)):
				continue
			var at: Vector2 = to_view.call(point)
			canvas.draw_circle(at, 3.6, Color(0, 0, 0, 0.55))
			canvas.draw_circle(at, 2.6, CHEST_MARK)
	if with_dot and player_point.is_finite():
		var at: Vector2 = to_view.call(player_point)
		canvas.draw_circle(at, 5.25, Color("#0b1020"))
		canvas.draw_circle(at, 4.0, Color("#72d8ff"))


## The boss's spots: the middle of every RoomFight with a boss not beaten yet (only the dungeon's
## boss when its Dungeon node names one: a mini-boss, the Pearl's guard, is not marked), and every
## `dungeon_map_mark` node marked "boss".
static func boss_points(dungeon: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var tree := dungeon.get_tree()
	var run := Services.run()
	var id := str(dungeon.get(&"dungeon_id"))
	var dungeon_boss := str(dungeon.get(&"boss_id")) if &"boss_id" in dungeon else ""
	for node: Node in tree.get_nodes_in_group(FIGHT_GROUP):
		var boss := str(node.get(&"boss_id"))
		if not dungeon_boss.is_empty() and boss != dungeon_boss:
			continue
		if not boss.is_empty() and not DungeonState.is_boss_beaten(run, id, boss) and node.has_method(&"rect"):
			out.append((node.call(&"rect") as Rect2).get_center())
	for node: Node in tree.get_nodes_in_group(MARK_GROUP):
		if node is Node2D and str(node.get(&"mark")) == "boss":
			out.append((node as Node2D).global_position)
	# The layout's boss mark (the boss's room in another world) until he is beaten.
	if not dungeon_boss.is_empty() and not DungeonState.is_boss_beaten(run, id, dungeon_boss) and dungeon.has_method(&"layout_marks"):
		for mark: Dictionary in dungeon.call(&"layout_marks"):
			if str(mark["mark"]) == "boss" and out.is_empty():
				out.append(mark["at"])
	return out


## True when a seal of this world is drawn near `at` already (the layout marks its seal too).
static func _seal_drawn_near(dungeon: Node, at: Vector2) -> bool:
	for seal: Node2D in seal_nodes(dungeon):
		if seal.global_position.distance_to(at) < 256.0:
			return true
	return false


## The seals shut in this world (group `dungeon_map_mark`, `mark` "seal").
static func seal_nodes(dungeon: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not dungeon.is_inside_tree():
		return out
	for node: Node in dungeon.get_tree().get_nodes_in_group(MARK_GROUP):
		if node is Node2D and str(node.get(&"mark")) == "seal":
			out.append(node as Node2D)
	return out


## A red bar across a shut seal's doorway (along its wall), outlined dark.
static func _draw_seal(canvas: CanvasItem, seal: Node2D, to_view: Callable) -> void:
	_draw_seal_at(canvas, seal.global_position - Vector2.DOWN.rotated(seal.global_rotation) * SEAL_BAR.y * 0.5,
		seal.global_rotation, to_view)


## A red bar centred on `middle` (global), turned by `rotation`.
static func _draw_seal_at(canvas: CanvasItem, middle: Vector2, rotation: float, to_view: Callable) -> void:
	var along := Vector2.RIGHT.rotated(rotation) * SEAL_BAR.x * 0.5
	var across := Vector2.DOWN.rotated(rotation) * SEAL_BAR.y * 0.5
	var corners := PackedVector2Array()
	for point: Vector2 in [middle - along - across, middle + along - across, middle + along + across, middle - along + across]:
		corners.append(to_view.call(point))
	var outline := corners.duplicate()
	outline.append(corners[0])
	canvas.draw_colored_polygon(corners, SEAL_MARK)
	canvas.draw_polyline(outline, Color("#2a0d0d"), 1.0)


## The chests not opened yet (in a room of the dungeon, shown: a hidden chest that has not risen yet
## counts too): this world's, and in a dungeon of one world per room the other rooms' too, read from
## their scenes (`Dungeon.layout_rooms_elsewhere`; their records say which are opened).
static func chest_points(dungeon: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for node: Node in dungeon.get_tree().get_nodes_in_group(CHEST_GROUP):
		if not node.has_method(&"is_empty") or bool(node.call(&"is_empty")):
			continue
		var root := node.get_parent() as Node2D
		if root != null and dungeon.call(&"room_at", root.global_position) != null:
			out.append(root.global_position)
	if not dungeon.has_method(&"layout_rooms_elsewhere"):
		return out
	var run := Services.run()
	for room: Dictionary in dungeon.call(&"layout_rooms_elsewhere"):
		for chest: Dictionary in scene_chests(str(room["scene"])):
			if _chest_full(run, chest):
				out.append((room["rect"] as Rect2).position + (chest["at"] as Vector2))
	return out


## The chests of the room scene at `path`, read from its state once a session: [{"at" (in the
## scene), "map_id", "instance_id", "contents" (as built), "heart" (its goo heart's id)}].
static func scene_chests(path: String) -> Array[Dictionary]:
	if _scene_chests.has(path):
		return _scene_chests[path]
	var out: Array[Dictionary] = []
	_scene_chests[path] = out
	if path.is_empty() or not ResourceLoader.exists(path):
		return out
	var state := (load(path) as PackedScene).get_state()
	var positions := {}
	for index: int in state.get_node_count():
		for p: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, p) == &"position":
				positions[str(state.get_node_path(index))] = state.get_node_property_value(index, p)
	for index: int in state.get_node_count():
		if state.get_node_name(index) != CHEST_SCRIPT_NODE:
			continue
		var chest := {"map_id": "", "instance_id": "", "contents": {}, "heart": ""}
		for p: int in state.get_node_property_count(index):
			match str(state.get_node_property_name(index, p)):
				"map_id":
					chest["map_id"] = str(state.get_node_property_value(index, p))
				"instance_id":
					chest["instance_id"] = str(state.get_node_property_value(index, p))
				"initial_contents":
					chest["contents"] = state.get_node_property_value(index, p)
				"goo_heart_id":
					chest["heart"] = str(state.get_node_property_value(index, p))
		if str(chest["instance_id"]).is_empty():
			continue
		# The chest stands at its root (the script's parent), placed by its ancestors' positions.
		var at := Vector2.ZERO
		var node_path := str(state.get_node_path(index, true))
		while node_path != "." and not node_path.is_empty():
			at += positions.get(node_path, Vector2.ZERO) as Vector2
			node_path = node_path.get_base_dir()
		chest["at"] = at
		out.append(chest)
	return out


## True when a chest of another room's scene (`scene_chests`) is not opened yet: its heart not taken,
## or its record holding something (a chest never built yet: its contents as built).
static func _chest_full(run: Object, chest: Dictionary) -> bool:
	if not str(chest["heart"]).is_empty() and not GooHeart.is_heart_taken(str(chest["heart"])):
		return true
	if run == null:
		return false
	var chests: Dictionary = (run.call(&"map_record", str(chest["map_id"])) as Dictionary).get("chests", {})
	var record: Variant = chests.get(str(chest["instance_id"]))
	if record is Dictionary:
		return not ((record as Dictionary).get("remaining", {}) as Dictionary).is_empty()
	return not (chest["contents"] as Dictionary).is_empty()


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
