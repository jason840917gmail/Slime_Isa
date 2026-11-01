extends RefCounted
class_name DungeonState
## A dungeon's saved state (docs/godot/DUNGEONS.md "Dungeon state"; decisions archive question 109):
## what the slime did inside a dungeon, kept per dungeon in RunState `world["dungeons"][<id>]`, so a
## faint, a quit or a load keeps it and the slime resumes at the dungeon's entrance.
##
## A record: {"small_keys": int (held, unspent), "keys_found": int, "items": [the big key, the map,
## the compass held], "keyholes": {door key: keyholes opened}, "done": [object keys solved for good:
## bolts slid, winches turned, bridges lowered, fights cleared, keys picked up, ...], "bosses": [boss
## ids beaten], "visited": [room keys], "entrance": {"map_id", "x", "y"} (an old centre), "seal":
## {"boss_id", "by"} while the dungeon is sealed (empty otherwise)}.
##
## **The seal** (docs/godot/DUNGEONS.md "The seal"; decisions archive, 2026-10-17 "the Pearl inside
## the dungeon"): taking the dungeon's Pearl seals it (`seal`) until its boss falls. While
## `is_sealed`, every door out of the dungeon refuses: the seal shutters (`object.dungeon-seal`,
## game/dungeon/dungeon_seal.gd) stand in its outside doorways, and a travel to a world that is
## not one of the dungeon's refuses with the seal's line (`exit_refusal`: main.gd `request_exit`,
## climbable walls with an exit). A faint or a quit still resumes at the entrance, inside, with the
## seal on. The boss's fall (`mark_boss_beaten`, or his id in `defeated_boss_ids`) breaks it.
##
## Inside a dungeon (a `Dungeon` node, game/dungeon/dungeon.gd, in the current world: `is_inside`)
## RunState refuses every save and the autosave waits (`saving_blocked_reason` is NO_SAVE_REASON);
## a quit or a closed window writes the resume save instead (`resume_data`: the run with its
## location moved to the entrance).
##
## Kit objects keep what they did with `is_done` / `mark_done`: in a dungeon its record, elsewhere
## the world's map record (`object_states`), so a winch or a drawbridge works outside dungeons too.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")

## Every Dungeon node joins this group.
const GROUP := &"dungeon"
## RunState.saving_blocked_reason inside a dungeon.
const NO_SAVE_REASON := "dungeon"
## RunState.world key of the records.
const RECORD_KEY := "dungeons"
## The dungeon items (chest contents, floor pickups, `give_item`).
const SMALL_KEY := "small-key"
const BIG_KEY := "big-key"
const MAP := "map"
const COMPASS := "compass"
const ITEMS: PackedStringArray = [SMALL_KEY, BIG_KEY, MAP, COMPASS]
## A chest's contents may name a dungeon item with this prefix ("dungeon-small-key": 1).
const ITEM_PREFIX := "dungeon-"
## Outside a dungeon, kit objects keep their state in the map record under this prefix.
const OBJECT_STATE_PREFIX := "kit:"
## Every seal shutter (dungeon_seal.gd) joins this group.
const SEAL_GROUP := &"dungeon_seal"
## The Dungeon node's scene and script: a world holding one with a dungeon's id is that dungeon's.
const DUNGEON_SCENE := "res://game/scenes/objects/dungeon/dungeon.tscn"
const DUNGEON_SCRIPT := "res://game/dungeon/dungeon.gd"
const WORLD_SCENE_PREFIX := "world."

## World id -> the dungeon id its Dungeon node has ("" for a world outside every dungeon), read
## from the world's scene once a session (`world_dungeon_id`).
static var _world_dungeons: Dictionary = {}
## World id -> its Dungeon node's `record_map_id` ("" when none), read once a session
## (`world_record_id`).
static var _world_records: Dictionary = {}


# --- the record ---------------------------------------------------------------------------------

## The record of `dungeon_id` (created empty on first use). {} without a run or an id.
static func record(run: Object, dungeon_id: String) -> Dictionary:
	if run == null or dungeon_id.is_empty():
		return {}
	var world: Dictionary = run.get(&"world")
	var all: Dictionary = world.get_or_add(RECORD_KEY, {})
	if not all.has(dungeon_id):
		all[dungeon_id] = {"small_keys": 0, "keys_found": 0, "items": [], "keyholes": {}, "done": [],
			"bosses": [], "visited": [], "entrance": {}, "seal": {}}
	var found: Dictionary = all[dungeon_id]
	# Records from an older kit: the keys that are missing.
	for key: String in ["items", "done", "bosses", "visited"]:
		found.get_or_add(key, [])
	found.get_or_add("keyholes", {})
	found.get_or_add("entrance", {})
	found.get_or_add("seal", {})
	return found


## Tells the views (the HUD's key chip, the map) and the autosave that the record changed.
static func notify(run: Object, dungeon_id: String) -> void:
	if run != null and run.has_signal(&"world_progress_changed"):
		run.emit_signal(&"world_progress_changed", {"map_id": "", "dungeon_id": dungeon_id})


# --- keys and items -----------------------------------------------------------------------------

## Small keys held and not spent yet.
static func small_keys(run: Object, dungeon_id: String) -> int:
	return int(record(run, dungeon_id).get("small_keys", 0))


## One more small key (found in a chest, picked up, given by a dev option).
static func add_small_key(run: Object, dungeon_id: String, count: int = 1) -> void:
	var found := record(run, dungeon_id)
	if found.is_empty() or count <= 0:
		return
	found["small_keys"] = int(found.get("small_keys", 0)) + count
	found["keys_found"] = int(found.get("keys_found", 0)) + count
	notify(run, dungeon_id)


## Spends one small key: false (nothing spent) when none is held.
static func spend_small_key(run: Object, dungeon_id: String) -> bool:
	var found := record(run, dungeon_id)
	if int(found.get("small_keys", 0)) <= 0:
		return false
	found["small_keys"] = int(found["small_keys"]) - 1
	notify(run, dungeon_id)
	return true


## True when the dungeon's big key, map or compass is held (a small key: one held).
static func has_item(run: Object, dungeon_id: String, item: String) -> bool:
	if item == SMALL_KEY:
		return small_keys(run, dungeon_id) > 0
	return item in (record(run, dungeon_id).get("items", []) as Array)


## Gives a dungeon item: a small key adds one; the others are held once. True when something was
## new (always for a small key).
static func give_item(run: Object, dungeon_id: String, item: String) -> bool:
	if item == SMALL_KEY:
		add_small_key(run, dungeon_id)
		return true
	var found := record(run, dungeon_id)
	if found.is_empty() or not item in ITEMS:
		return false
	var items: Array = found["items"]
	if item in items:
		return false
	items.append(item)
	notify(run, dungeon_id)
	return true


## The dungeon item a chest's content id names ("dungeon-small-key" -> "small-key"), "" when none.
static func item_of(content_id: String) -> String:
	if not content_id.begins_with(ITEM_PREFIX):
		return ""
	var item := content_id.trim_prefix(ITEM_PREFIX)
	return item if item in ITEMS else ""


# --- doors, objects, bosses, rooms --------------------------------------------------------------

## Keyholes of door `door_key` opened so far.
static func keyholes_open(run: Object, dungeon_id: String, door_key: String) -> int:
	return int((record(run, dungeon_id).get("keyholes", {}) as Dictionary).get(door_key, 0))


## One more keyhole of `door_key` opened; returns how many are open now.
static func open_keyhole(run: Object, dungeon_id: String, door_key: String) -> int:
	var found := record(run, dungeon_id)
	if found.is_empty():
		return 0
	var holes: Dictionary = found["keyholes"]
	holes[door_key] = int(holes.get(door_key, 0)) + 1
	notify(run, dungeon_id)
	return int(holes[door_key])


static func is_boss_beaten(run: Object, dungeon_id: String, boss_id: String) -> bool:
	if boss_id.is_empty():
		return false
	if boss_id in (record(run, dungeon_id).get("bosses", []) as Array):
		return true
	return run != null and run.has_method(&"is_boss_defeated") and bool(run.call(&"is_boss_defeated", boss_id))


## A boss fell: kept in the dungeon's record and the run's `defeated_boss_ids`.
static func mark_boss_beaten(run: Object, dungeon_id: String, boss_id: String) -> void:
	if boss_id.is_empty():
		return
	var found := record(run, dungeon_id)
	if not found.is_empty() and not boss_id in (found["bosses"] as Array):
		(found["bosses"] as Array).append(boss_id)
	if run != null:
		var world: Dictionary = run.get(&"world")
		var defeated: Array = world.get_or_add("defeated_boss_ids", [])
		if not boss_id in defeated:
			defeated.append(boss_id)
	# His fall breaks the seal he held (the Dungeon node sinks the seal shutters).
	if not found.is_empty() and str((found["seal"] as Dictionary).get("boss_id", "")) == boss_id:
		found["seal"] = {}
	notify(run, dungeon_id)


# --- the seal -----------------------------------------------------------------------------------

## Seals `dungeon_id` until its boss `boss_id` falls (the Pearl's take; `by` names what sealed it, a
## Pearl's id). False, and nothing sealed, without a boss, when that boss is already beaten (an old
## save that beat him before the rework takes the Pearl after) or when it is sealed already.
static func seal(run: Object, dungeon_id: String, boss_id: String, by: String = "") -> bool:
	var found := record(run, dungeon_id)
	if found.is_empty() or boss_id.is_empty() or is_boss_beaten(run, dungeon_id, boss_id):
		return false
	if is_sealed(run, dungeon_id):
		return false
	found["seal"] = {"boss_id": boss_id, "by": by}
	notify(run, dungeon_id)
	return true


## True while `dungeon_id` is sealed: sealed, and the boss who holds it not beaten.
static func is_sealed(run: Object, dungeon_id: String) -> bool:
	var held: Dictionary = record(run, dungeon_id).get("seal", {})
	if held.is_empty():
		return false
	return not is_boss_beaten(run, dungeon_id, str(held.get("boss_id", "")))


## The boss whose fall breaks the seal ("" when not sealed).
static func sealed_by(run: Object, dungeon_id: String) -> String:
	return str((record(run, dungeon_id).get("seal", {}) as Dictionary).get("boss_id", "")) if is_sealed(run, dungeon_id) else ""


## Breaks the seal (his fall does it by itself: `mark_boss_beaten`; this is for a dev option or a
## test). True when it was sealed.
static func unseal(run: Object, dungeon_id: String) -> bool:
	var found := record(run, dungeon_id)
	if found.is_empty() or (found["seal"] as Dictionary).is_empty():
		return false
	var was := is_sealed(run, dungeon_id)
	found["seal"] = {}
	notify(run, dungeon_id)
	return was


## The line a travel from the current dungeon to world `target_map_id` is refused with while the
## dungeon is sealed: its Dungeon node's `seal_text`. "" when it may go: not in a dungeon, not
## sealed, or the target is one of the dungeon's worlds (a floor of the Weaver Hollow).
static func exit_refusal(tree: SceneTree, target_map_id: String) -> String:
	var dungeon := current(tree)
	if dungeon == null:
		return ""
	var dungeon_id := str(dungeon.get(&"dungeon_id"))
	if not is_sealed(Services.run(), dungeon_id) or world_dungeon_id(target_map_id) == dungeon_id:
		return ""
	return str(dungeon.call(&"seal_text")) if dungeon.has_method(&"seal_text") else "Sealed."


## The dungeon id of world `map_id`'s Dungeon node ("" for a world outside every dungeon or an
## unknown one): the current world's own node, else read from the world's scene (its SceneState,
## without building it) once a session.
static func world_dungeon_id(map_id: String) -> String:
	if map_id.is_empty():
		return ""
	var world := Services.world()
	if world != null and world.map_id() == map_id and world.is_inside_tree():
		var here := current(world.get_tree())
		if here != null:
			return str(here.get(&"dungeon_id"))
	if _world_dungeons.has(map_id):
		return str(_world_dungeons[map_id])
	var found := _dungeon_value_in(_world_state(map_id), &"dungeon_id")
	_world_dungeons[map_id] = found
	return found


## The `record_map_id` of world `map_id`'s Dungeon node: the id the worlds of a dungeon of one world
## per room share (Fatty's Lair: "fatty-lair"); "" for a world without one. The current world's own
## node, else read from the world's scene once a session.
static func world_record_id(map_id: String) -> String:
	if map_id.is_empty():
		return ""
	var world := Services.world()
	if world != null and world.map_id() == map_id and world.is_inside_tree():
		var here := current(world.get_tree())
		if here != null:
			return str(here.get(&"record_map_id"))
	if not _world_records.has(map_id):
		_world_records[map_id] = _dungeon_value_in(_world_state(map_id), &"record_map_id")
	return str(_world_records[map_id])


## The scene state of world `map_id` (its scene not built), or null.
static func _world_state(map_id: String) -> SceneState:
	var world := Services.world()
	var path := world.scene_path(WORLD_SCENE_PREFIX + map_id) if world != null else ""
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	return packed.get_state() if packed != null else null


## The value of `property` (`dungeon_id`, `record_map_id`) on the Dungeon node in a world scene's
## state ("" when it has none or does not set it).
static func _dungeon_value_in(state: SceneState, property: StringName) -> String:
	if state == null:
		return ""
	for index: int in state.get_node_count():
		var instance := state.get_node_instance(index)
		var is_dungeon := instance != null and instance.resource_path == DUNGEON_SCENE
		var found := ""
		for index_property: int in state.get_node_property_count(index):
			var property_name := state.get_node_property_name(index, index_property)
			var value: Variant = state.get_node_property_value(index, index_property)
			if property_name == property:
				found = str(value)
			elif property_name == &"script" and value is Script and (value as Script).resource_path == DUNGEON_SCRIPT:
				is_dungeon = true
		if is_dungeon and not found.is_empty():
			return found
		# A scene instanced under the root that holds the Dungeon node with its settings (Fatty's
		# Lair's `fatty-lair-dungeon.tscn`, in every room world): this world's own value for it, else
		# the held scene's.
		if instance != null and not is_dungeon and str(state.get_node_path(index, true)) == "." \
				and _holds_dungeon(instance.get_state()):
			if not found.is_empty():
				return found
			var inner := _dungeon_value_in(instance.get_state(), property)
			if not inner.is_empty():
				return inner
	return ""


## True when a scene's state has a Dungeon node (an instance of its scene, or its script).
static func _holds_dungeon(state: SceneState) -> bool:
	if state == null:
		return false
	for index: int in state.get_node_count():
		var instance := state.get_node_instance(index)
		if instance != null and instance.resource_path == DUNGEON_SCENE:
			return true
		for index_property: int in state.get_node_property_count(index):
			var value: Variant = state.get_node_property_value(index, index_property)
			if state.get_node_property_name(index, index_property) == &"script" and value is Script \
					and (value as Script).resource_path == DUNGEON_SCRIPT:
				return true
	return false


## Remembers that the slime stood in room `room_key`; true when it is new.
static func visit_room(run: Object, dungeon_id: String, room_key: String) -> bool:
	var found := record(run, dungeon_id)
	if found.is_empty() or room_key.is_empty() or room_key in (found["visited"] as Array):
		return false
	(found["visited"] as Array).append(room_key)
	notify(run, dungeon_id)
	return true


static func is_visited(run: Object, dungeon_id: String, room_key: String) -> bool:
	return room_key in (record(run, dungeon_id).get("visited", []) as Array)


## Where a faint or a quit resumes: {"map_id", "x", "y"} (an old centre), {} until known.
static func entrance(run: Object, dungeon_id: String) -> Dictionary:
	return (record(run, dungeon_id).get("entrance", {}) as Dictionary).duplicate()


static func set_entrance(run: Object, dungeon_id: String, map_id: String, centre: Vector2) -> void:
	var found := record(run, dungeon_id)
	if found.is_empty() or map_id.is_empty():
		return
	found["entrance"] = {"map_id": map_id, "x": centre.x, "y": centre.y}


# --- the session: facts kept while the run plays, never saved ------------------------------------

## A session fact of the run (RunState `dungeon_session`: forgotten by a new run and a load), or
## `fallback`. Fatty's Lair keeps here what one room tells another without a record for good: a
## plate held down when the slime left its room (heavy_plate.gd `hold_record`, read by gate.gd
## `open_while_record` in the next room) and the next far-off roar.
static func session_value(run: Object, key: String, fallback: Variant = null) -> Variant:
	if run == null or key.is_empty() or not &"dungeon_session" in run:
		return fallback
	return (run.get(&"dungeon_session") as Dictionary).get(key, fallback)


static func set_session_value(run: Object, key: String, value: Variant) -> void:
	if run == null or key.is_empty() or not &"dungeon_session" in run:
		return
	var session: Dictionary = run.get(&"dungeon_session")
	if value == null:
		session.erase(key)
	else:
		session[key] = value


# --- objects solved for good (in a dungeon or anywhere) ------------------------------------------

## The key a kit object keeps its state under: its world's record id and its own id
## ("fatty-lair:door-3"). The record id is the world's map id, or its Dungeon node's
## `record_map_id` when it has one: every room world of Fatty's Lair keeps its records under
## "fatty-lair" (docs/godot/DUNGEON_ROOMS.md), so a room's records do not depend on its world.
static func object_key(node: Node, id: String) -> String:
	var map_id := record_map_id(node)
	return "%s:%s" % [map_id, id] if not map_id.is_empty() else id


## The id `node`'s world keeps its kit records under: its Dungeon node's `record_map_id`, else the
## world's map id (`world_map_id`).
static func record_map_id(node: Node) -> String:
	var at := node.get_parent() if node != null else null
	while at != null:
		var definition := at.get_node_or_null(^"world-definition")
		if definition != null:
			for child: Node in at.get_children():
				if &"record_map_id" in child and not str(child.get(&"record_map_id")).is_empty():
					return str(child.get(&"record_map_id"))
			return str(definition.get(&"map_id"))
		at = at.get_parent()
	var dungeon := current(node.get_tree()) if node != null and node.is_inside_tree() else null
	if dungeon != null and not str(dungeon.get(&"record_map_id")).is_empty():
		return str(dungeon.get(&"record_map_id"))
	return world_map_id(node)


## The map id of the world scene `node` stands in (its `world-definition` node), known before the
## world is registered; else the registered world's.
static func world_map_id(node: Node) -> String:
	var at := node.get_parent() if node != null else null
	while at != null:
		var definition := at.get_node_or_null(^"world-definition")
		if definition != null:
			return str(definition.get(&"map_id"))
		at = at.get_parent()
	var world := Services.world()
	return world.map_id() if world != null else ""


## True when the kit object `key` (an `object_key`) did its thing for good.
static func is_done(tree: SceneTree, key: String) -> bool:
	var run := Services.run()
	if run == null or key.is_empty():
		return false
	var dungeon_id := current_id(tree)
	if not dungeon_id.is_empty():
		return key in (record(run, dungeon_id).get("done", []) as Array)
	return bool(run.object_state(_key_map(key), OBJECT_STATE_PREFIX + key, false))


static func mark_done(tree: SceneTree, key: String) -> void:
	var run := Services.run()
	if run == null or key.is_empty():
		return
	var dungeon_id := current_id(tree)
	if not dungeon_id.is_empty():
		var done: Array = record(run, dungeon_id)["done"]
		if not key in done:
			done.append(key)
		notify(run, dungeon_id)
		return
	var map_id := _key_map(key)
	run.set_object_state(map_id, OBJECT_STATE_PREFIX + key, true)
	run.world_progress_changed.emit({"map_id": map_id})


## Forgets that the kit object `key` did its thing (a held chest that sank away again).
static func clear_done(tree: SceneTree, key: String) -> void:
	var run := Services.run()
	if run == null or key.is_empty():
		return
	var dungeon_id := current_id(tree)
	if not dungeon_id.is_empty():
		var done: Array = record(run, dungeon_id)["done"]
		if key in done:
			done.erase(key)
			notify(run, dungeon_id)
		return
	var map_id := _key_map(key)
	run.set_object_state(map_id, OBJECT_STATE_PREFIX + key, false)
	run.world_progress_changed.emit({"map_id": map_id})


## The map id an `object_key` starts with ("" for a key without one).
static func _key_map(key: String) -> String:
	var colon := key.find(":")
	return key.left(colon) if colon > 0 else ""


# --- inside ----------------------------------------------------------------------------------

## The current world's Dungeon node, or null.
static func current(tree: SceneTree) -> Node:
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node.is_inside_tree() and not node.is_queued_for_deletion():
			return node
	return null


## The current dungeon's id, "" outside.
static func current_id(tree: SceneTree) -> String:
	var dungeon := current(tree)
	return str(dungeon.get(&"dungeon_id")) if dungeon != null else ""


## True while the current world is (part of) a dungeon.
static func is_inside(run: Node) -> bool:
	return run != null and run.is_inside_tree() and not current_id(run.get_tree()).is_empty()


## True when a quit or a closed window in the current dungeon writes its resume save (the dev lab
## does not, as the playground writes no autosave: docs/godot/DUNGEONS.md).
static func writes_resume(run: Node) -> bool:
	var dungeon := current(run.get_tree()) if run != null and run.is_inside_tree() else null
	return dungeon != null and bool(dungeon.get(&"resume_saves"))


## `data` (RunState.serialize) with the location moved to the current dungeon's entrance, so the
## save resumes there; `data` unchanged when the entrance is not known.
static func resume_data(run: Node, data: Dictionary) -> Dictionary:
	var dungeon_id := current_id(run.get_tree()) if run != null and run.is_inside_tree() else ""
	var at := entrance(run, dungeon_id)
	if at.is_empty():
		return data
	data["location"] = {"area_id": str(at["map_id"]), "map_id": str(at["map_id"]), "x": float(at["x"]),
		"y": float(at["y"]), "facing": "up"}
	return data


## The kit's generic hookup: sets `target` off (a winch's targets, a room fight's reward): its
## `trigger(payload)`, else `appear`, `open_for_good`, `lower` or `open`; a node with none of them
## (a chest's root) passes it to its first child that has one. True when something was called.
static func fire(target: Node, payload: Variant = null) -> bool:
	if target == null:
		return false
	for method: StringName in [&"trigger", &"appear", &"open_for_good", &"lower", &"open"]:
		if target.has_method(method):
			target.call(method, payload)
			return true
	for child: Node in target.get_children():
		for method: StringName in [&"trigger", &"appear", &"open_for_good", &"lower", &"open"]:
			if child.has_method(method):
				child.call(method, payload)
				return true
	return false


## Takes back what `fire` did, on a target that can go back (`vanish`, on it or a child: a hidden
## chest sinking away again), for a plate that holds its targets only while it is pressed
## (heavy_plate.gd `hold_targets`). False when the target has no way back.
static func take_back(target: Node, payload: Variant = null) -> bool:
	if target == null:
		return false
	for node: Node in [target] + target.get_children():
		if node.has_method(&"vanish"):
			node.call(&"vanish", payload)
			return true
	return false


## Levels, as the open world has them (docs/godot/DUNGEONS.md "Levels"): the level a kit object
## stands on: its `level` property when it has one set (not -99); on a deck that holds there (a slab,
## a landing, a lowered drawbridge over a pit: hazard_deck.gd), the deck's level, so it is reached
## from the deck, not from the pit under it; else the level a body put there walks on
## (Elevation.walkable_level_at).
static func level_of_node(node: Node2D) -> int:
	if node == null:
		return 0
	var own: Variant = node.get(&"level")
	if own is int and int(own) != -99:
		return int(own)
	var world := Services.world()
	if world == null or world.elevation == null or not is_instance_valid(world.elevation):
		return 0
	if node.is_inside_tree():
		# the decks' group (hazard_deck.gd GROUP; not preloaded: it preloads this script)
		for deck: Node in node.get_tree().get_nodes_in_group(&"hazard_deck"):
			if deck != node and deck.has_method(&"holds_at") and bool(deck.call(&"holds_at", node.global_position)):
				return int(deck.call(&"deck_level"))
	return int(world.elevation.walkable_level_at(node.global_position))


## True when the slime's body stands on the level of `node` (or no elevation tells them apart): only
## then does it reach the object (a key, a flower, a plate, a slab); a slime in a pit under a bridge
## touches nothing on the bridge.
static func on_level_of(node: Node2D) -> bool:
	var world := Services.world()
	if world == null or world.player_body == null or world.elevation == null or not is_instance_valid(world.elevation):
		return true
	return int(world.elevation.level_of(world.player_body)) == level_of_node(node)


## The dungeon numbers: `dungeon.<path>` in game-constants.json (a missing one is an error);
## `fallback` only where there are no constants (the editor).
static func number(path: String, fallback: float) -> float:
	var constants := Services.constants()
	return constants.number("dungeon." + path) if constants != null else fallback
