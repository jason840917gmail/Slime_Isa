extends RefCounted
class_name DungeonMapDraw
## Draws a dungeon's rooms (docs/godot/DUNGEONS.md "The dungeon map"), shared by the minimap overlay
## (dungeon_minimap.gd) and the map screen's page (dungeon_map_page.gd). The rooms are the Dungeon
## node's CameraRooms in this world:
## - a room the slime has stood in: filled in parchment, edged;
## - with the map: every other room, a dim fill with a dashed-looking thin edge (fog lifted);
## - without the map, a room never visited is not drawn (fog);
## - the room the slime is in: a gold ring;
## - with the map: a red mark in the boss's room (a RoomFight with a `boss_id`, or a node in the
##   group `dungeon_map_mark` with `mark` = "boss"; owner, 2026-10-26: it moved from the compass);
## - with the compass: a gold dot on each chest not opened yet;
## - a seal shut (dungeon_seal.gd, `mark` = "seal"): a red bar across its doorway, with or without
##   the compass, while the dungeon is sealed (docs/godot/DUNGEONS.md "The seal");
## - in a room drawn, its doors, shutters and stairs, read from its scene (`scene_features`).
## `to_view` maps a global point to the canvas. The minimap draws `only_current`: the slime's room
## alone with the marks inside it (owner, 2026-10-19: the rooms around it, at the minimap's scale,
## covered the play area); the map screen (M) draws every room.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const RoomDoorScript := preload("res://game/dungeon/room_door.gd")

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
const CHEST_ROOT_SCRIPT := "res://game/scripts/chest_root.gd"
const WORLD_DEFINITION_NODE := "world-definition"
const GooHeart := preload("res://game/scripts/goo_heart.gd")
const FIGHT_GROUP := &"room_fight"
## Rooms are drawn this share of a room inset, so neighbours show a gap.
const INSET_SHARE := 0.06

## Room scene path -> its chests (`scene_chests`) and its features (`scene_features`), read once a
## session; script path -> {property: its default} (`_default_of`).
static var _scene_chests: Dictionary = {}
static var _scene_features: Dictionary = {}
static var _defaults: Dictionary = {}
const DOOR_MARK := Color("#c9a25a")
const LOCKED_MARK := Color("#7f8ea3")
const STAIR_MARK := Color("#ffc866")
## The scripts the map draws a feature for (a script that extends one is that feature too): a room
## door (the way through), a dungeon door (key, boss and bolted doors), a shutter (not the seal, which
## has its own bar), a plank barricade, a stair door and a door out to another world with a side.
const ROOM_DOOR_SCRIPT := "res://game/dungeon/room_door.gd"
const WORLD_DOOR_SCRIPT := "res://game/scripts/door.gd"
const DUNGEON_DOOR_SCRIPT := "res://game/dungeon/dungeon_door.gd"
const KEY_DOOR_SCRIPT := "res://game/dungeon/key_door.gd"
const BOLTED_DOOR_SCRIPT := "res://game/dungeon/bolted_door.gd"
const SHUTTER_SCRIPT := "res://game/dungeon/shutter.gd"
const SEAL_SCRIPT := "res://game/dungeon/dungeon_seal.gd"
const BARRICADE_SCRIPT := "res://game/scripts/plank_barricade.gd"
const STAIR_SCRIPT := "res://game/scripts/stair_hatch.gd"
## A feature on a room's edge (a room door) still belongs to it this close outside (room units).
const EDGE_SLACK := 8.0
## One doorway (`_doorways`, room units): its two sides' ways through lie this close along and across
## its wall; a door leaf, shutter or barricade in it stands up to this deep in the wall (two cells and
## a margin).
const DOORWAY_MERGE := 72.0
const DOORWAY_DEPTH := 160.0
## A doorway's mark (canvas units, on a north or south wall; turned on an east or west one).
const DOORWAY_BAR := Vector2(14.0, 6.0)
## What a doorway shows, the first its pieces have (`_doorway_look`): the boss door, a small-key door,
## a barricade, a bolted door, a door locked by a record elsewhere, a fight's shutter (open until its
## fight starts: a lock in the same doorway says more); else open.
const DOORWAY_LOOKS: PackedStringArray = ["big", "small", "barricade", "bolt", "locked", "shutter"]
const DOORWAY_COLOURS := {"open": DOOR_MARK, "shutter": Color("#e0503a"), "barricade": Color("#8a5a2b"),
	"big": Color("#7a1d1a"), "small": LOCKED_MARK, "bolt": LOCKED_MARK, "locked": LOCKED_MARK}


## The floors the dungeon's rooms lie on, the highest first ([0] alone for a one-floor dungeon).
static func floors(dungeon: Node) -> Array[int]:
	var out: Array[int] = []
	for room: Dictionary in dungeon.call(&"rooms"):
		var floor_level := int(room.get("floor", 0))
		if not out.has(floor_level):
			out.append(floor_level)
	out.sort()
	out.reverse()
	return out


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
## slime's room alone, and only the seals and the marks inside it (the minimap).
## `floor_level`: the floor shown (the map's floor tabs; the minimap ignores it and shows the slime's room).
static func draw(canvas: CanvasItem, dungeon: Node, to_view: Callable, player_point: Vector2, with_dot: bool, only_current: bool = false, floor_level: int = 0) -> void:
	var run := Services.run()
	if dungeon == null or run == null or not dungeon.is_inside_tree():
		return
	var id := str(dungeon.get(&"dungeon_id"))
	var has_map := DungeonState.has_item(run, id, DungeonState.MAP)
	var has_compass := DungeonState.has_item(run, id, DungeonState.COMPASS)
	var current := str(dungeon.call(&"current_room_key"))
	var rooms: Array = dungeon.call(&"rooms")
	# where the marks may be drawn: the slime's room (the minimap), else the rooms of this floor
	var here := Rect2()
	var floor_rects: Array[Rect2] = []
	for room: Dictionary in rooms:
		if str(room["key"]) == current:
			here = room["rect"]
		if int(room.get("floor", 0)) == floor_level:
			floor_rects.append(room["rect"])
	var shown := func(point: Vector2) -> bool:
		if only_current:
			return here.has_area() and here.has_point(point)
		for rect: Rect2 in floor_rects:
			if rect.has_point(point):
				return true
		return false
	for room: Dictionary in rooms:
		if only_current and str(room["key"]) != current:
			continue
		if not only_current and int(room.get("floor", 0)) != floor_level:
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
	# A world of several rooms (R5) is one scene: each of its features is drawn once.
	var drawn := {}
	# The doors, shutters and barricades of every room drawn, merged into doorways after.
	var walls: Array[Dictionary] = []
	for room: Dictionary in rooms:
		if only_current and str(room["key"]) != current:
			continue
		if not only_current and int(room.get("floor", 0)) != floor_level:
			continue
		if not DungeonState.is_visited(run, id, str(room["key"])) and not has_map:
			continue
		_collect_features(canvas, dungeon, room, to_view, shown, drawn, walls)
	for doorway: Dictionary in _doorways(walls):
		_draw_doorway(canvas, to_view.call(doorway["at"]), str(doorway["axis"]), _doorway_look(doorway["states"]))
	for seal: Node2D in seal_nodes(dungeon):
		if bool(shown.call(seal.global_position)):
			_draw_seal(canvas, seal, to_view)
	# The layout's seal marks (the seals of the other room worlds) while the dungeon is sealed.
	if DungeonState.is_sealed(run, id) and dungeon.has_method(&"layout_marks"):
		for mark: Dictionary in dungeon.call(&"layout_marks"):
			if str(mark["mark"]) == "seal" and not _seal_drawn_near(dungeon, mark["at"]) and bool(shown.call(mark["at"])):
				_draw_seal_at(canvas, mark["at"], float(mark["rotation"]), to_view)
	# The boss shows once the map is held (owner, 2026-10-26: there is no compass in the lair).
	if has_map:
		for point: Vector2 in boss_points(dungeon):
			if not bool(shown.call(point)):
				continue
			var at: Vector2 = to_view.call(point)
			_draw_skull(canvas, at, 6.0)
	if has_compass:
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
	# A world of several rooms (R5) is one scene, named by each of its rooms: read once.
	var read := {}
	for room: Dictionary in dungeon.call(&"layout_rooms_elsewhere"):
		var path := str(room["scene"])
		if read.has(path):
			continue
		read[path] = true
		for chest: Dictionary in scene_chests(path):
			if _chest_full(run, chest):
				out.append(_scene_origin(room) + (chest["at"] as Vector2))
	return out


## Where the origin of a room's scene lies in this world: its CameraRoom's place on the layout less
## where that CameraRoom lies in its scene (`camera_offset`: R5's lower hall and key alcove are not
## at their scene's origin); this world's own room: the world root.
static func _scene_origin(room: Dictionary) -> Vector2:
	if room.get("node") != null:
		var world := Services.world()
		return world.world_root.global_position if world != null and world.world_root != null else Vector2.ZERO
	return (room["rect"] as Rect2).position - (room.get("camera_offset", Vector2.ZERO) as Vector2)


## The doors, shutters and stairs of a room, read from its scene (`scene`, or the layout's scene for
## the room this world holds), if they lie in this room (a world of several rooms holds the features
## of all of them; `drawn` keeps each scene's feature to one). Stairs are drawn at once; the wall
## pieces (doors, shutters, barricades) go into `walls` as {"at" (this world), "axis" ("h" on a north
## or south wall, "v" on an east or west one), "anchor" (a room door or a door out: the way through,
## on the wall's line), "state" (what it shows: `_doorway_look`)} for `_doorways` to merge.
static func _collect_features(canvas: CanvasItem, dungeon: Node, room: Dictionary, to_view: Callable, shown: Callable,
		drawn: Dictionary, walls: Array[Dictionary]) -> void:
	var path := str(room.get("scene", ""))
	if path.is_empty() and room.get("node") != null:
		path = str(dungeon.call(&"layout_scene_of", str(room["name"])))
	if path.is_empty():
		return
	var origin := _scene_origin(room)
	var records := _records_of(dungeon, room)
	var run := Services.run()
	var features := scene_features(path)
	for index: int in features.size():
		var feature: Dictionary = features[index]
		var point: Vector2 = origin + (feature["at"] as Vector2)
		var key := "%s#%d" % [path, index]
		if drawn.has(key) or not _room_holds(room, point) or not bool(shown.call(point)):
			continue
		drawn[key] = true
		var kind := str(feature["kind"])
		if kind == "stair":
			_draw_stair(canvas, to_view.call(point), str(feature["direction"]))
			continue
		var side := str(feature["side"])
		var state := "open"
		match kind:
			"door":
				if _is_locked(dungeon, feature, records):
					state = str(feature.get("lock", "locked"))
			"barricade":
				if run == null or not bool(run.call(&"has_flag", str(feature["flag"]))):
					state = "barricade"
			"shutter":
				state = "shutter"
		walls.append({"at": point, "axis": "h" if side == "north" or side == "south" else "v",
			"anchor": kind == "door" and str(feature.get("via", "")) != "dungeon", "state": state})


## The doorways the wall pieces `walls` (`_collect_features`) make, one each: the ways through
## (room doors, doors out) on one wall line within DOORWAY_MERGE of each other are one doorway (the
## two rooms' sides of it), drawn where they are; a door leaf, shutter or barricade standing in the
## wall's depth (DOORWAY_DEPTH across it, DOORWAY_MERGE along it) belongs to that doorway; one with
## no doorway near is a doorway of its own. [{"at", "axis", "states"}].
static func _doorways(walls: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for anchors: bool in [true, false]:
		for piece: Dictionary in walls:
			if bool(piece["anchor"]) != anchors:
				continue
			var at: Vector2 = piece["at"]
			var axis := str(piece["axis"])
			var best: Dictionary = {}
			var best_distance := INF
			for doorway: Dictionary in out:
				if str(doorway["axis"]) != axis:
					continue
				var d := at - (doorway["at"] as Vector2)
				var across := absf(d.y) if axis == "h" else absf(d.x)
				var along := absf(d.x) if axis == "h" else absf(d.y)
				var reach := DOORWAY_MERGE if anchors else DOORWAY_DEPTH
				if across <= reach and along <= DOORWAY_MERGE and across + along < best_distance:
					best = doorway
					best_distance = across + along
			if best.is_empty():
				out.append({"at": at, "axis": axis, "states": [piece["state"]], "count": 1})
				continue
			(best["states"] as Array).append(piece["state"])
			if anchors:
				# the doorway's two sides: drawn between them, on the wall the rooms share
				var count := int(best["count"])
				best["at"] = ((best["at"] as Vector2) * count + at) / (count + 1)
				best["count"] = count + 1
	return out


## What a doorway shows (`states`: its pieces'): the first of DOORWAY_LOOKS any piece has, else open.
static func _doorway_look(states: Array) -> String:
	for look: String in DOORWAY_LOOKS:
		if states.has(look):
			return look
	return "open"


## A doorway's mark on its wall: a bar across the opening (horizontal on a north or south wall,
## upright on an east or west one), gold while open; a bolted or barred one grey with a dark bolt, a
## key door grey with a gold keyhole, the boss door dark crimson with a gold keyhole, a shutter red, a
## barricade brown and slatted.
static func _draw_doorway(canvas: CanvasItem, at: Vector2, axis: String, look: String) -> void:
	var size := DOORWAY_BAR if axis == "h" else Vector2(DOORWAY_BAR.y, DOORWAY_BAR.x)
	var bar := Rect2(at - size * 0.5, size)
	canvas.draw_rect(bar.grow(0.8), Color(0, 0, 0, 0.55))
	canvas.draw_rect(bar, DOORWAY_COLOURS.get(look, DOOR_MARK))
	match look:
		"locked", "bolt":
			canvas.draw_rect(Rect2(at - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), Color("#2a2f3a"))
		"small", "big":
			canvas.draw_circle(at, 1.8, CHEST_MARK)
		"barricade":
			for k in [-0.25, 0.25]:
				var middle := at + (Vector2(size.x * k, 0.0) if axis == "h" else Vector2(0.0, size.y * k))
				var half := size.y * 0.5 if axis == "h" else size.x * 0.5
				canvas.draw_line(middle + Vector2(-half, half), middle + Vector2(half, -half), Color("#2a1a0a"), 1.0)


## True while a door of the map is locked: a room door until the record its `requires` names is set
## (RoomDoor.requirement_met), a dungeon door (key, boss, bolted) until it is opened for good (its
## record: DungeonState.mark_done under its link). `records`: the id its world keeps them under.
static func _is_locked(dungeon: Node, feature: Dictionary, records: String) -> bool:
	if feature.has("requires"):
		return not RoomDoorScript.requirement_met(dungeon.get_tree(), records, str(feature["requires"]))
	if feature.has("link"):
		return not DungeonState.is_done(dungeon.get_tree(), "%s:%s" % [records, feature["link"]] if not records.is_empty() else str(feature["link"]))
	return false


## The id a room's world keeps its kit records under (DungeonState.record_map_id): the dungeon's
## `record_map_id` (Fatty's Lair: every room's under "fatty-lair"), else the room's world.
static func _records_of(dungeon: Node, room: Dictionary) -> String:
	var shared := str(dungeon.get(&"record_map_id")) if &"record_map_id" in dungeon else ""
	if not shared.is_empty():
		return shared
	if room.has("world"):
		return str(room["world"])
	var world := Services.world()
	return world.map_id() if world != null else ""


## True when `point` (this world) lies in `room`: in its outline (its rectangle without one), or
## within EDGE_SLACK of its edge.
static func _room_holds(room: Dictionary, point: Vector2) -> bool:
	if not (room["rect"] as Rect2).grow(EDGE_SLACK).has_point(point):
		return false
	var outline := room.get("outline", PackedVector2Array()) as PackedVector2Array
	if outline.size() < 3 or Geometry2D.is_point_in_polygon(point, outline):
		return true
	for i: int in outline.size():
		var edge := Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % outline.size()])
		if edge.distance_to(point) <= EDGE_SLACK:
			return true
	return false


## A stair's arrow: up or down, gold.
static func _draw_stair(canvas: CanvasItem, at: Vector2, direction: String) -> void:
	var tip := -6.0 if direction == "up" else 6.0
	var base := 5.0 if direction == "up" else -5.0
	var points := PackedVector2Array([at + Vector2(0.0, tip), at + Vector2(-5.0, base), at + Vector2(5.0, base)])
	canvas.draw_colored_polygon(points, STAIR_MARK)
	canvas.draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.6), 1.0)


## The features of the room scene at `path`, read from its state once a session: [{"at" (in the scene),
## "kind" ("door", "barricade", "shutter" or "stair"), "side" (its wall; not stairs), "direction"
## (stairs), and what says whether a door is locked: "requires" (a room door's), "link" (a dungeon
## door's record id), "flag" (a barricade's)}]. Each is known by its script (`_script_of`; the
## scripts above), its values read as the game builds them (`_value_of`: a value the scene leaves at
## its default is not saved in it).
static func scene_features(path: String) -> Array[Dictionary]:
	if _scene_features.has(path):
		return _scene_features[path]
	var out: Array[Dictionary] = []
	_scene_features[path] = out
	for node: Dictionary in _scene_nodes(path):
		var state: SceneState = node["state"]
		var index: int = node["index"]
		var script := _script_of(state, index)
		if script == null:
			continue
		var feature := {}
		if _extends(script, ROOM_DOOR_SCRIPT):
			feature = {"kind": "door", "via": "room", "side": str(_value_of(state, index, script, &"side")),
				"requires": str(_value_of(state, index, script, &"requires")), "lock": "locked"}
		elif _extends(script, DUNGEON_DOOR_SCRIPT):
			# Its record: its link, else its door id, else its node's name (DungeonDoor `_link`).
			var link := str(_value_of(state, index, script, &"link_id"))
			if link.is_empty():
				link = str(_value_of(state, index, script, &"door_id"))
			# what holds it shut: a key door's lock ("small", "big": the boss door), a bolt
			var lock := "locked"
			if _extends(script, KEY_DOOR_SCRIPT):
				lock = str(_value_of(state, index, script, &"lock"))
			elif _extends(script, BOLTED_DOOR_SCRIPT):
				lock = "bolt"
			feature = {"kind": "door", "via": "dungeon", "side": str(_value_of(state, index, script, &"wall")),
				"link": link if not link.is_empty() else String(state.get_node_name(index)), "lock": lock}
		elif _extends(script, SEAL_SCRIPT):
			continue
		elif _extends(script, SHUTTER_SCRIPT):
			feature = {"kind": "shutter", "side": str(_value_of(state, index, script, &"wall"))}
		elif _extends(script, BARRICADE_SCRIPT):
			feature = {"kind": "barricade", "side": str(_value_of(state, index, script, &"wall")),
				"flag": str(_value_of(state, index, script, &"flag_id"))}
		elif _extends(script, STAIR_SCRIPT):
			var direction: Variant = _value_of(state, index, script, &"direction")
			feature = {"kind": "stair", "direction": str(direction) if direction != null else "down"}
		elif _extends(script, WORLD_DOOR_SCRIPT):
			# A door out of the dungeon (R1's way in); one without a side is a hole or a ladder.
			var side := str(_value_of(state, index, script, &"side"))
			if side != "none":
				feature = {"kind": "door", "via": "world", "side": side}
		if feature.is_empty():
			continue
		feature["at"] = node["at"]
		out.append(feature)
	return out


## The chests of the room scene at `path`, read from its state once a session: [{"at" (in the
## scene), "map_id", "instance_id", "contents" (as built), "heart" (its goo heart's id)}]. A chest
## is read from its root (chest_root.gd: `contents`, `heart_id`, `chest_id`, `map_id`) and from an
## older override on its ChestScript child; the root's values win where set, and an empty record
## is the game's: the chest's name and the scene's map (chest.gd).
static func scene_chests(path: String) -> Array[Dictionary]:
	if _scene_chests.has(path):
		return _scene_chests[path]
	var out: Array[Dictionary] = []
	_scene_chests[path] = out
	var scene_map := ""
	var by_root := {}
	for node: Dictionary in _scene_nodes(path):
		var state: SceneState = node["state"]
		var index: int = node["index"]
		var node_name := String(state.get_node_name(index))
		if node_name == WORLD_DEFINITION_NODE:
			scene_map = str(_value_or(state, index, &"map_id", ""))
			continue
		if node_name == CHEST_SCRIPT_NODE:
			var root_path := str(state.get_node_path(index, true)).trim_prefix("./")
			var chest := _chest_entry(by_root, root_path, root_path.get_file(), node["parent_at"])
			for p: int in state.get_node_property_count(index):
				var value: Variant = state.get_node_property_value(index, p)
				match str(state.get_node_property_name(index, p)):
					"map_id":
						chest["script_map"] = str(value)
					"instance_id":
						chest["script_id"] = str(value)
					"initial_contents":
						chest["script_contents"] = value
					"goo_heart_id":
						chest["script_heart"] = str(value)
			continue
		var script := _script_of(state, index)
		if script == null or script.resource_path != CHEST_ROOT_SCRIPT:
			continue
		var root_chest := _chest_entry(by_root, str(state.get_node_path(index)).trim_prefix("./"), node_name, node["at"])
		root_chest["at"] = node["at"]
		root_chest["root_map"] = str(_value_or(state, index, &"map_id", ""))
		root_chest["root_id"] = str(_value_or(state, index, &"chest_id", ""))
		root_chest["root_contents"] = _value_or(state, index, &"contents", {})
		root_chest["root_heart"] = str(_value_or(state, index, &"heart_id", ""))
	for entry: Dictionary in by_root.values():
		var contents: Variant = entry.get("root_contents", {})
		if not contents is Dictionary or (contents as Dictionary).is_empty():
			contents = entry.get("script_contents", {})
		var chest := {
			"at": entry["at"],
			"map_id": _first_set([entry.get("root_map", ""), entry.get("script_map", ""), scene_map]),
			"instance_id": _first_set([entry.get("root_id", ""), entry.get("script_id", ""), entry["name"]]),
			"contents": contents if contents is Dictionary else {},
			"heart": _first_set([entry.get("root_heart", ""), entry.get("script_heart", "")]),
		}
		out.append(chest)
	return out


## The entry of the chest whose root is at `root_path` (made the first time: its name and place).
static func _chest_entry(by_root: Dictionary, root_path: String, chest_name: String, at: Vector2) -> Dictionary:
	if not by_root.has(root_path):
		by_root[root_path] = {"name": chest_name, "at": at}
	return by_root[root_path]


## `property` as stored for a node of a scene state (`_stored`), else `fallback`.
static func _value_or(state: SceneState, index: int, property: StringName, fallback: Variant) -> Variant:
	var stored: Array = _stored(state, index, property)
	return stored[0] if not stored.is_empty() and stored[0] != null else fallback


## The first value of `values` that is not empty, "" when none is.
static func _first_set(values: Array) -> String:
	for value: Variant in values:
		if not str(value).is_empty():
			return str(value)
	return ""


## The nodes of the scene at `path`, read from its state (nothing is built): [{"state", "index",
## "at" (where the node stands in the scene: its position and its ancestors'), "parent_at" (its
## parent's)}]; [] when there is no such scene.
static func _scene_nodes(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if path.is_empty() or not ResourceLoader.exists(path):
		return out
	var state := (load(path) as PackedScene).get_state()
	var positions := {}
	for index: int in state.get_node_count():
		var own: Array = _stored(state, index, &"position")
		if not own.is_empty():
			positions[str(state.get_node_path(index))] = own[0]
	for index: int in state.get_node_count():
		var parent_at := _place(positions, str(state.get_node_path(index, true)))
		var own := positions.get(str(state.get_node_path(index)), Vector2.ZERO) as Vector2
		out.append({"state": state, "index": index, "at": parent_at + own, "parent_at": parent_at})
	return out


## Where the node at `node_path` stands in its scene: its position and its ancestors' (the root's
## left out: the scene's origin).
static func _place(positions: Dictionary, node_path: String) -> Vector2:
	var at := Vector2.ZERO
	while node_path != "." and not node_path.is_empty():
		at += positions.get(node_path, Vector2.ZERO) as Vector2
		node_path = node_path.get_base_dir()
	return at


## `property` as a node of a scene state holds it: [its value] from the state, else from the root
## of the scene it instances (and so on: an instance's own values are in its scene); [] when none
## of them stores it (it is at its script's default).
static func _stored(state: SceneState, index: int, property: StringName) -> Array:
	var at := state
	var node := index
	while at != null:
		for p: int in at.get_node_property_count(node):
			if at.get_node_property_name(node, p) == property:
				return [at.get_node_property_value(node, p)]
		var instance := at.get_node_instance(node)
		at = instance.get_state() if instance != null else null
		node = 0
	return []


## The script of a node of a scene state (its own, else its instanced scene's root's); null without.
static func _script_of(state: SceneState, index: int) -> Script:
	var script: Array = _stored(state, index, &"script")
	return script[0] as Script if not script.is_empty() else null


## True when `script` is the script at `path` or extends it.
static func _extends(script: Script, path: String) -> bool:
	var at := script
	while at != null:
		if at.resource_path == path:
			return true
		at = at.get_base_script()
	return false


## `property` of a node of a scene state as the game builds it: stored (`_stored`), else its
## script's default (`_default_of`).
static func _value_of(state: SceneState, index: int, script: Script, property: StringName) -> Variant:
	var stored: Array = _stored(state, index, property)
	return stored[0] if not stored.is_empty() else _default_of(script, property)


## The default of `script`'s `property` (Script.get_property_default_value; an exported game keeps
## none on its scripts, so then a bare instance of the script tells it, once a session).
static func _default_of(script: Script, property: StringName) -> Variant:
	var value: Variant = script.get_property_default_value(property)
	if value != null:
		return value
	var known: Dictionary = _defaults.get_or_add(script.resource_path, {})
	if not known.has(property):
		var probe: Object = script.new() if script.can_instantiate() else null
		known[property] = probe.get(property) if probe != null else null
		if probe != null and not probe is RefCounted:
			probe.free()
	return known[property]


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
