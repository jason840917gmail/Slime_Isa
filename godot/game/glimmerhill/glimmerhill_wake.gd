extends RefCounted
## Glimmerhill asleep and waking (docs/godot/VILLAGERS.md "Asleep until its Pearl comes home"; owner,
## 2026-11-17 and 2026-11-19, question 159): the wake table `story.glimmerhill` in game-constants.json
## read in one place. The town's four parts (Market Hill B4, West Hill A4, the south gate's quarter B5,
## the farms and the lake A5) each list their chunk worlds (with the town's rectangle in that chunk,
## world units: B4's leaves out the Wellspring and the prologue glade in its south) and their room
## worlds, and name the story flag that wakes them. A part sleeps until its flag is set: its villagers
## frozen with their eyes shut (villager_script.gd), its animals away (critter.gd), its fountain dry
## (goo_fountain.gd) and the town greyed and darkened (town_sleep.gd). The Pearls' list says which
## part each Pearl wakes when it comes home to the Wellspring (wellspring_homecoming.gd), what else it
## sets (`alsoFlags`: Pearl 2 raises Slimeshire's Workshop, `workshop.restored`; Pearl 3 lights its
## Forge, `forge.restored`; owner, 2026-11-20) and its card's texts.
##
## Static helpers; nothing here holds state (the flags live in RunState).
##
## Owner: world (Glimmerhill).

const Services := preload("res://game/shared/services.gd")

const TABLE_PATH := "story.glimmerhill"
const PEARL_FLAG_PREFIX := "pearl."
const HOME_SUFFIX := ".home"
const WORLD_DEFINITION_NODE := "world-definition"


## The whole table ({} without one).
static func table() -> Dictionary:
	var constants := Services.constants()
	var found: Variant = constants.value(TABLE_PATH, {}) if constants != null else {}
	return found if found is Dictionary else {}


## A tunable of the table's `section` ("sleep", "villagers", "animals", "fountain"), or `fallback`.
static func tunable(section: String, key: String, fallback: Variant) -> Variant:
	var part: Variant = table().get(section, {})
	return (part as Dictionary).get(key, fallback) if part is Dictionary else fallback


static func tunable_number(section: String, key: String, fallback: float) -> float:
	var found: Variant = tunable(section, key, fallback)
	return float(found) if typeof(found) == TYPE_FLOAT or typeof(found) == TYPE_INT else fallback


## The part id whose chunk or room `map_id` is ("" when it is no part of the town).
static func part_of_world(map_id: String) -> String:
	var parts: Variant = table().get("parts", {})
	if not parts is Dictionary:
		return ""
	for part_id: Variant in (parts as Dictionary).keys():
		var part: Dictionary = (parts as Dictionary)[part_id]
		var chunks: Variant = part.get("chunks", {})
		if chunks is Dictionary and (chunks as Dictionary).has(map_id):
			return str(part_id)
		var rooms: Variant = part.get("rooms", [])
		if rooms is Array and map_id in (rooms as Array):
			return str(part_id)
	return ""


static func part(part_id: String) -> Dictionary:
	var parts: Variant = table().get("parts", {})
	var found: Variant = (parts as Dictionary).get(part_id, {}) if parts is Dictionary else {}
	return found if found is Dictionary else {}


static func part_name(part_id: String) -> String:
	return str(part(part_id).get("name", part_id))


static func wake_flag(part_id: String) -> String:
	return str(part(part_id).get("wakeFlag", ""))


## True once `part_id`'s wake flag is set (a part with no flag, or no part, is always awake).
static func is_awake(part_id: String) -> bool:
	var flag := wake_flag(part_id)
	if part_id.is_empty() or flag.is_empty():
		return true
	var run := Services.run()
	return run != null and run.has_flag(flag)


## The town's rectangle in the chunk `map_id` (world units); Rect2() for a room or no part (a room is
## the town whole).
static func town_rect(map_id: String) -> Rect2:
	var chunks: Variant = part(part_of_world(map_id)).get("chunks", {})
	var raw: Variant = (chunks as Dictionary).get(map_id, []) if chunks is Dictionary else []
	if not raw is Array or (raw as Array).size() < 4:
		return Rect2()
	var r: Array = raw
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## True when `map_id` is a room of the town (not a chunk).
static func is_room(map_id: String) -> bool:
	var rooms: Variant = part(part_of_world(map_id)).get("rooms", [])
	return rooms is Array and map_id in (rooms as Array)


## The part asleep at `point` (world units) of the world `map_id`, "" when none is: the world's part
## while its flag is unset, in a room anywhere and in a chunk only inside the town's rectangle.
static func asleep_part_at(map_id: String, point: Vector2) -> String:
	var part_id := part_at(map_id, point)
	return "" if part_id.is_empty() or is_awake(part_id) else part_id


## The part of the town at `point` of the world `map_id`, asleep or awake ("" when none): a room's
## part anywhere in it, a chunk's only inside the town's rectangle.
static func part_at(map_id: String, point: Vector2) -> String:
	var part_id := part_of_world(map_id)
	if part_id.is_empty() or is_room(map_id):
		return part_id
	var rect := town_rect(map_id)
	return part_id if not rect.has_area() or rect.has_point(point) else ""


## The part asleep where `node` stands in its world ("" when none). Asked from a node's `_ready`, when
## the world is not registered yet (main adds the world to the tree first), so the world's id is read
## from the world scene's own definition (`world_id_of`).
static func asleep_part_of(node: Node2D) -> String:
	if node == null:
		return ""
	return asleep_part_at(world_id_of(node), node.global_position)


## The id of the world `node` stands in: the `map_id` of the world definition (the `world-definition`
## node) of the nearest ancestor that has one, else the registered world's.
static func world_id_of(node: Node) -> String:
	var at := node
	while at != null:
		var definition := at.get_node_or_null(NodePath(WORLD_DEFINITION_NODE))
		if definition != null and definition.get(&"map_id") != null:
			return str(definition.get(&"map_id"))
		at = at.get_parent()
	var world := Services.world()
	return world.map_id() if world != null else ""


## The Pearls in their order: [{pearlId, number, part, alsoFlags, cardName, cardLine}].
static func pearls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = table().get("pearls", [])
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				out.append(entry as Dictionary)
	return out


static func pearl_flag(pearl_id: String) -> String:
	return PEARL_FLAG_PREFIX + pearl_id


static func home_flag(pearl_id: String) -> String:
	return PEARL_FLAG_PREFIX + pearl_id + HOME_SUFFIX


## The Pearls taken and not yet home, in their order.
static func pearls_waiting() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var run := Services.run()
	if run == null:
		return out
	for entry: Dictionary in pearls():
		var pearl_id := str(entry.get("pearlId", ""))
		if not pearl_id.is_empty() and run.has_flag(pearl_flag(pearl_id)) and not run.has_flag(home_flag(pearl_id)):
			out.append(entry)
	return out


## How many of the table's Pearls are home.
static func pearls_home() -> int:
	var run := Services.run()
	if run == null:
		return 0
	var count := 0
	for entry: Dictionary in pearls():
		if run.has_flag(home_flag(str(entry.get("pearlId", "")))):
			count += 1
	return count


## Wakes the part a Pearl wakes: its wake flag and the Pearl's `alsoFlags` (the homecoming, and a
## load whose Pearl was home before the town slept: none yet).
static func wake_for_pearl(entry: Dictionary) -> void:
	var run := Services.run()
	if run == null:
		return
	var flag := wake_flag(str(entry.get("part", "")))
	if not flag.is_empty():
		run.set_flag(flag)
	var also: Variant = entry.get("alsoFlags", [])
	if also is Array:
		for extra: Variant in also:
			run.set_flag(str(extra))


## Connects `method` (a method of a node: Godot drops the connection when the node is freed) to
## RunState.story_flag_changed; the method checks its payload with `wakes`.
static func listen(method: Callable) -> void:
	var run := Services.run()
	if run != null and not run.story_flag_changed.is_connected(method):
		run.story_flag_changed.connect(method)


static func unlisten(method: Callable) -> void:
	var run := Services.run()
	if run != null and run.story_flag_changed.is_connected(method):
		run.story_flag_changed.disconnect(method)


## True when a RunState.story_flag_changed payload is `part_id`'s wake flag being set.
static func wakes(payload: Dictionary, part_id: String) -> bool:
	var flag := wake_flag(part_id)
	return not flag.is_empty() and str(payload.get("flag", "")) == flag and bool(payload.get("set", true))
