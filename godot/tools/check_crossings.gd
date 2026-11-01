extends SceneTree
## Checks every crossing between worlds (docs/design/2026-10-31-crossings-and-arrivals.md D6): loads
## every world of res://game/scenes/scene_index.json, lists its crossing ends (doors, holes and blown
## walls, stair doors, landings, world exits) and says what is wrong with each link, so a broken
## pair is found before a playtest lands the slime on a fallback spot.
##
##   "<Godot console exe>" --headless --path godot -s res://tools/check_crossings.gd [-- --world=<text>]
##
## `--world=<text>` keeps only the worlds whose id holds the text; `--all` also lists the border
## crossings that work ("by coordinates"). What it reports, by world:
## - **broken** (the crossing does not work as meant): a door, hole or stair door whose target world
##   is unknown or has no end of that id; two sided doors not on opposite sides;
## - **one way** (to look at): a door or stair whose far end does not lead back (falls into a landing
##   are one way by design and not reported);
## - **spawn** (to pair): a stair door with no `target_door` (it leads nowhere);
## - **border** (open world): an exit into a neighbouring region crosses by coordinates
##   (BorderCrossing), or comes out of the far side's opening back elsewhere along the border
##   ("apart"); reported when no exit leads back along that border (it lands at the region's spawn).
## A world exit with a `target_door_id` (the mine's mouth and its way out) is checked as a door.
## Dungeon room doors (room_door.gd) check themselves in the editor and are only counted.
##
## Owner: world objects.

const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")
const BorderCrossing := preload("res://game/world/crossings/border_crossing.gd")
const Landing := preload("res://game/scripts/landing.gd")
const WorldExit := preload("res://game/scripts/world_exit.gd")

const INDEX_PATH := "res://game/scenes/scene_index.json"
const WORLD_PREFIX := "world."
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
## How far from the arrival point an exit back may lie and still count as the way back (world units).
const BORDER_SLACK := 96.0

## world id -> {"ends": {id: end}, "exits": [exit], "rect": Rect2, "room_doors": int}.
var _worlds: Dictionary = {}
## world id -> its scene's path.
var _paths: Dictionary = {}
var _problems: Dictionary = {}
var _counts: Dictionary = {}
var _all := false


func _init() -> void:
	var filter := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--world="):
			filter = arg.substr(8)
		elif arg == "--all":
			_all = true
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	for key: String in index:
		if key.begins_with(WORLD_PREFIX):
			_paths[key.substr(WORLD_PREFIX.length())] = str(index[key])
			_read_world(key.substr(WORLD_PREFIX.length()), str(index[key]))
	for world_id: String in _worlds:
		_check_world(world_id)
	_report(filter)
	quit(0)


# --- reading ------------------------------------------------------------------------------------

func _read_world(world_id: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate()
	var info := {"ends": {}, "exits": [], "rect": Rect2(), "room_doors": 0}
	for node: Node in [root] + root.find_children("*", "", true, false):
		if node is WorldDefinitionScript:
			var definition := node as WorldDefinitionScript
			info["rect"] = Rect2(0.0, 0.0, definition.columns * definition.tile_size, definition.rows * definition.tile_size)
		elif node is RoomDoor:
			info["room_doors"] = int(info["room_doors"]) + 1
		elif node is StairHatchScript:
			var stair := node as StairHatchScript
			info["ends"][stair.hatch_id] = {"type": "stair", "side": "", "kind": "stair",
				"target_world": stair.target_world if not stair.target_world.is_empty() else world_id,
				"target_door": stair.target_door}
		elif node is Landing:
			info["ends"][str(node.get(&"door_id"))] = {"type": "landing", "side": "", "kind": "landing",
				"target_world": "", "target_door": ""}
		elif node is WorldExitScript:
			info["exits"].append(_exit_of(node as WorldExitScript))
		elif not (node is DoorScript) and &"door_id" in node and &"target_area_id" in node:
			# A cracked floor or wall: its own door (built in its _ready) carries these.
			_add_door(info, node, "hole")
		elif node is DoorScript:
			_add_door(info, node, "door")
	_worlds[world_id] = info
	root.free()


func _add_door(info: Dictionary, node: Node, type: String) -> void:
	var door_id := str(node.get(&"door_id"))
	var target := str(node.get(&"target_area_id"))
	if door_id.is_empty() and target.is_empty():
		return
	info["ends"][door_id] = {"type": type, "side": str(node.get(&"side")) if &"side" in node else "none",
		"kind": str(node.get(&"kind")) if &"kind" in node else "", "target_world": target,
		"target_door": str(node.get(&"target_door_id"))}


func _exit_of(exit_node: WorldExitScript) -> Dictionary:
	var rect := Rect2()
	if exit_node.area != null:
		for child: Node in exit_node.area.get_children():
			var shape := child as CollisionShape2D
			if shape != null and shape.shape is RectangleShape2D:
				var size := (shape.shape as RectangleShape2D).size * shape.global_scale.abs()
				var at := _global(shape)
				rect = Rect2(at - size * 0.5, size)
				break
	return {"id": exit_node.exit_id, "target": exit_node.target_area_id, "entry": exit_node.entry,
		"target_door": exit_node.target_door_id, "keep_along": exit_node.keep_along, "rect": rect}


## A node's position in its scene (the scene is not in a tree, so global_position is not kept).
static func _global(node: Node) -> Vector2:
	var at := Vector2.ZERO
	var walk := node
	while walk != null:
		if walk is Node2D:
			at = (walk as Node2D).transform * at
		walk = walk.get_parent()
	return at


# --- checking -----------------------------------------------------------------------------------

func _check_world(world_id: String) -> void:
	var info: Dictionary = _worlds[world_id]
	_count("room doors (checked in the editor)", int(info["room_doors"]))
	for end_id: String in info["ends"]:
		var end: Dictionary = info["ends"][end_id]
		_count(str(end["type"]) + " ends", 1)
		if str(end["type"]) == "landing":
			continue
		var label := "%s %s" % [end["type"], end_id]
		var target_door := str(end["target_door"])
		if target_door.is_empty():
			# A door with no target door lands at the target's spawn (the dev labs' ways back); a stair
			# without its pair leads nowhere.
			if str(end["type"]) == "stair":
				_flag(world_id, "spawn", "%s has no target_door: it leads nowhere" % label)
			continue
		var far_world := _world_holding(str(end["target_world"]), target_door)
		if far_world.is_empty():
			_flag(world_id, "broken", "%s leads to %s / %s, which does not exist" % [label, end["target_world"], target_door])
			continue
		var far: Dictionary = _worlds[far_world]["ends"][target_door]
		var side := str(end["side"])
		if side in OPPOSITE and str(far["side"]) in OPPOSITE and str(far["side"]) != OPPOSITE[side]:
			_flag(world_id, "broken", "%s is a %s door but %s / %s is in the %s wall" % [label, side, far_world, target_door, far["side"]])
		if str(far["type"]) == "landing":
			continue
		var back_world := _world_holding(str(far["target_world"]), str(far["target_door"]))
		if str(far["target_door"]) != end_id or back_world != world_id:
			_flag(world_id, "one way", "%s leads to %s / %s, which leads to %s / %s" % [label, far_world, target_door,
				far["target_world"], far["target_door"]])
	for exit: Dictionary in info["exits"]:
		_count("world exits", 1)
		_check_exit(world_id, info, exit)


func _check_exit(world_id: String, info: Dictionary, exit: Dictionary) -> void:
	var target := str(exit["target"])
	if bool(exit["keep_along"]) or target.is_empty():
		return
	var door := str(exit["target_door"])
	if not door.is_empty():
		if _world_holding(target, door).is_empty():
			_flag(world_id, "broken", "exit %s leads to %s / %s, which does not exist" % [exit["id"], target, door])
		return
	var rect: Rect2 = exit["rect"]
	var bounds: Rect2 = info["rect"]
	var crossing := {}
	if rect.has_area() and bounds.has_area():
		crossing = BorderCrossing.across(world_id, target, WorldExit.edge_of(rect, bounds), rect.get_center())
	if not crossing.is_empty():
		var back := BorderCrossing.opening_back(crossing, PackedStringArray([world_id, WorldChunks.world_of(world_id)]), BORDER_SLACK)
		if back.is_empty():
			_flag(world_id, "border", "%s would cross into %s at its %s edge, %d along, but no exit leads back along that border: it lands at the region's spawn (draw the opening's other side)" % [
				exit["id"], crossing["world"], crossing["edge"], int(crossing["along"])])
			return
		var along := float(back["along"])
		if back["world"] == crossing["world"] and is_equal_approx(along, float(crossing["along"])):
			_count("border crossings by coordinates", 1)
			if _all:
				_flag(world_id, "by coordinates", "%s crosses into %s at its %s edge, %d along" % [exit["id"],
					crossing["world"], crossing["edge"], int(crossing["along"])])
		else:
			_count("border crossings into the opening back elsewhere", 1)
			_flag(world_id, "apart", "%s comes out of %s's opening back, %d along its %s edge (it left at %d along %s: the two sides are drawn apart)" % [
				exit["id"], back["world"], int(along), back["edge"], int(crossing["along"]), crossing["world"]])
		return


## The world (`world_id`, or a chunk of the region `world_id`) that holds the end `end_id`; "" if none.
func _world_holding(world_id: String, end_id: String) -> String:
	for candidate: String in _candidates(world_id):
		if _worlds.has(candidate) and (_worlds[candidate]["ends"] as Dictionary).has(end_id):
			return candidate
	return ""


func _candidates(world_id: String) -> Array:
	var out := [world_id]
	out.append_array(WorldChunks.chunks(world_id).keys())
	return out


func _flag(world_id: String, kind: String, text: String) -> void:
	if not _problems.has(world_id):
		_problems[world_id] = []
	_problems[world_id].append([kind, text])
	_count(kind, 1)


func _count(what: String, n: int) -> void:
	_counts[what] = int(_counts.get(what, 0)) + n


func _report(filter: String) -> void:
	var ids := _problems.keys()
	ids.sort()
	for world_id: String in ids:
		if not filter.is_empty() and not world_id.contains(filter):
			continue
		print("%s:" % world_id)
		for problem: Array in _problems[world_id]:
			print("  [%s] %s" % problem)
	print("")
	var keys := _counts.keys()
	keys.sort()
	for what: String in keys:
		print("%-36s %d" % [what, _counts[what]])
