extends RefCounted
## Where the tracked quest wants the player next (Phaser `features/quests/QuestWaypoint.ts` with
## the world queries of `WorldScene.questWaypointWorld` and `UniversalSceneWorldController`
## `bossCampPosition`, `exitToArea`, `nearestSource`, `nearestStation`, `restorationSite`; quests
## spec 4.6 and 10.7). Static; positions are old Phaser positions (NPCs: sprite bottom).
##
## `resolve(quest_view, from)` returns {"position": Vector2, "label": String}, or {} when there is
## nowhere to go on this map:
## - an available NPC quest: the nearest giver ("Talk to <name>");
## - ready to turn in: the nearest turn-in NPC ("Return to <name>");
## - active: the first unfinished objective of the current stage that resolves: kill -> the
##   nearest enemy-spawn area holding one of its kinds (its stay rect centre); defeat-boss -> the
##   camp of the first boss on this map; discover-area -> the nearest exit or door into the area;
##   collect -> the nearest pile with some left or standing resource node that drops the item;
##   craft-item -> the nearest station serving the recipe (portable recipes: nothing);
##   activate-object -> the nearest restoration site; talk-to-npc -> the nearest NPC.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const WorldExitScript := preload("res://game/scripts/world_exit.gd")

## The Workshop also crafts workbench recipes (STATION_INCLUDES, RecipeCatalog.ts:93-99).
const STATION_INCLUDES := {"workshop": ["workbench"]}

## World exits of the current world (no group): cached per world root.
static var _exit_world_id: int = 0
static var _exits: Array[Node] = []


static func resolve(quest: Dictionary, from: Vector2) -> Dictionary:
	if quest.is_empty():
		return {}
	var definition: Dictionary = quest["definition"]
	var status := str(quest.get("status", ""))
	if status == "available":
		var acquisition: Dictionary = definition.get("acquisition", {})
		if str(acquisition.get("kind", "")) != "npc":
			return {}
		return _npc_target(QuestCatalog.ids(acquisition, "npcIds"), from, "Talk to %s")
	if status != "active":
		return {}
	if bool(quest.get("ready_to_turn_in", false)):
		var completion: Dictionary = definition.get("completion", {})
		if str(completion.get("kind", "")) != "npc-turn-in":
			return {}
		return _npc_target(QuestCatalog.ids(completion, "npcIds"), from, "Return to %s")
	var stage_definition := QuestCatalog.stage(definition, str(quest.get("active_stage_id", "")))
	var progress: Dictionary = quest.get("progress", {})
	for objective: Dictionary in QuestCatalog.objectives(stage_definition):
		if int(progress.get(str(objective["id"]), 0)) >= int(objective["target"]):
			continue
		var target := _objective_target(objective, from)
		if not target.is_empty():
			return target
	return {}


static func _objective_target(objective: Dictionary, from: Vector2) -> Dictionary:
	var label := str(objective.get("label", ""))
	var point: Variant = null
	match str(objective.get("kind", "")):
		"talk-to-npc":
			return _npc_target(QuestCatalog.ids(objective, "npcIds"), from, "Talk to %s")
		"kill":
			var kinds := QuestCatalog.ids(objective, "enemyKinds")
			point = _spawn_area_for(kinds, from) if not kinds.is_empty() else null
		"defeat-boss":
			for boss_id: String in QuestCatalog.ids(objective, "bossIds"):
				point = _boss_camp_position(boss_id)
				if point != null:
					break
		"discover-area":
			for area_id: String in QuestCatalog.ids(objective, "areaIds"):
				point = _exit_to_area(area_id, from)
				if point != null:
					break
		"collect":
			point = _nearest_source(QuestCatalog.ids(objective, "itemIds"), from)
		"craft-item":
			var item_ids := QuestCatalog.ids(objective, "itemIds")
			var station := ""
			for recipe: Dictionary in QuestCatalog.recipes():
				if str((recipe.get("output", {}) as Dictionary).get("itemId", "")) in item_ids:
					station = str(recipe.get("station", ""))
					break
			if not station.is_empty() and station != "portable":
				point = _nearest_station(station, from)
		"activate-object":
			var object_ids := QuestCatalog.ids(objective, "objectIds")
			point = _restoration_site(object_ids, from) if not object_ids.is_empty() else null
	return {"position": point, "label": label} if point is Vector2 else {}


## The first in-tree NPC of each id, the nearest of them: "<format % name>".
static func _npc_target(npc_ids: Array[String], from: Vector2, label_format: String) -> Dictionary:
	var best: Dictionary = {}
	for npc_id in npc_ids:
		var point: Variant = _npc_position(npc_id)
		if point == null:
			continue
		if best.is_empty() or from.distance_to(point) < from.distance_to(best["position"]):
			best = {"position": point, "label": label_format % QuestCatalog.npc_name(npc_id)}
	return best


static func _npc_position(npc_id: String) -> Variant:
	for node: Node in _tree().get_nodes_in_group(&"npc"):
		if str(node.get(&"npc_definition_id")) == npc_id and node.has_method(&"get_phaser_position"):
			return node.call(&"get_phaser_position")
	return null


static func _boss_camp_position(boss_id: String) -> Variant:
	for camp: Node in _tree().get_nodes_in_group(&"boss_camp"):
		if str(camp.get(&"boss_id")) == boss_id and camp.get_parent() is Node2D:
			return FeetAnchor.phaser_position(camp.get_parent() as Node2D)
	return null


## The nearest enemy-spawn area holding one of `kinds`: its stay rectangle's centre.
static func _spawn_area_for(kinds: Array[String], from: Vector2) -> Variant:
	var world := Services.world()
	if world == null:
		return null
	var best: Variant = null
	for area: Dictionary in world.areas(world.AREA_ENEMY_SPAWN):
		var data: Dictionary = area.get("data", {})
		var holds := false
		for entry: Variant in data.get("enemies", []):
			if entry is Dictionary and str((entry as Dictionary).get("type", "")) in kinds:
				holds = true
		var stay: Dictionary = area.get("stay_perimeter", {}) if area.get("stay_perimeter") is Dictionary else {}
		if not holds or str(stay.get("shape", "")) != "rectangle":
			continue
		var centre := Vector2(float(stay["x"]) + float(stay["w"]) / 2.0, float(stay["y"]) + float(stay["h"]) / 2.0)
		if best == null or from.distance_to(centre) < from.distance_to(best):
			best = centre
	return best


## The nearest world exit (its parent) or in-tree door (its parent) leading to `area_id`.
static func _exit_to_area(area_id: String, from: Vector2) -> Variant:
	var best: Variant = null
	var candidates: Array[Node] = []
	for exit_node: Node in _world_exits():
		if is_instance_valid(exit_node) and exit_node.is_inside_tree() and str(exit_node.get(&"target_area_id")) == area_id:
			candidates.append(exit_node.get_parent())
	for door: Node in _tree().get_nodes_in_group(&"door"):
		if str(door.get(&"target_area_id")) == area_id:
			candidates.append(door.get_parent())
	for parent: Node in candidates:
		var root := parent as Node2D
		if root == null:
			continue
		var point := FeetAnchor.phaser_position(root)
		if best == null or from.distance_to(point) < from.distance_to(best):
			best = point
	return best


## The nearest pile with something left, or standing resource node whose piles give the item.
static func _nearest_source(item_ids: Array[String], from: Vector2) -> Variant:
	var best: Variant = null
	for pile: Node in _tree().get_nodes_in_group(&"collectible"):
		if not str(pile.get(&"item_id")) in item_ids or int(pile.call(&"remaining")) <= 0 or not pile.get_parent() is Node2D:
			continue
		var point := FeetAnchor.phaser_position(pile.get_parent() as Node2D)
		if best == null or from.distance_to(point) < from.distance_to(best):
			best = point
	for node: Node in _tree().get_nodes_in_group(&"resource_node"):
		if bool(node.call(&"is_destroyed")):
			continue
		var drop: Variant = node.get(&"drop")
		var object_id := str((drop as Dictionary).get("objectId", "")) if drop is Dictionary else ""
		if object_id.is_empty() or not _item_for_world_drop(object_id) in item_ids:
			continue
		var at: Vector2 = node.call(&"world_position")
		if best == null or from.distance_to(at) < from.distance_to(best):
			best = at
	return best


## The nearest in-tree station that crafts `station` recipes (its parent).
static func _nearest_station(station: String, from: Vector2) -> Variant:
	var best: Variant = null
	for bench: Node in _tree().get_nodes_in_group(&"crafting_station"):
		var kind := str(bench.get(&"recipe_context"))
		if kind != station and not station in (STATION_INCLUDES.get(kind, []) as Array):
			continue
		if not bench.get_parent() is Node2D:
			continue
		var point := FeetAnchor.phaser_position(bench.get_parent() as Node2D)
		if best == null or from.distance_to(point) < from.distance_to(best):
			best = point
	return best


## The nearest in-tree restoration site of one of `object_ids` (its parent).
static func _restoration_site(object_ids: Array[String], from: Vector2) -> Variant:
	var best: Variant = null
	for site: Node in _tree().get_nodes_in_group(&"restoration_site"):
		if not str(site.get(&"object_id")) in object_ids or not site.get_parent() is Node2D:
			continue
		var point := FeetAnchor.phaser_position(site.get_parent() as Node2D)
		if best == null or from.distance_to(point) < from.distance_to(best):
			best = point
	return best


## `itemIdForWorldDrop`: the item whose `worldDrop.objectId` is `object_id` ("" when none).
static func _item_for_world_drop(object_id: String) -> String:
	var constants := Services.constants()
	var items: Variant = constants.data_file(ItemCatalog.ITEMS_FILE) if constants != null else null
	if not items is Dictionary:
		return ""
	for item_id: Variant in items:
		var look: Variant = (items[item_id] as Dictionary).get("worldDrop") if items[item_id] is Dictionary else null
		if look is Dictionary and str((look as Dictionary).get("objectId", "")) == object_id:
			return str(item_id)
	return ""


## The current world's exit scripts (searched once per world).
static func _world_exits() -> Array[Node]:
	var world := Services.world()
	var root: Node2D = world.world_root if world != null else null
	if root == null or not is_instance_valid(root):
		return []
	if root.get_instance_id() != _exit_world_id:
		_exit_world_id = root.get_instance_id()
		_exits = []
		for node: Node in root.find_children("*", "Node", true, false):
			if node.get_script() == WorldExitScript:
				_exits.append(node)
	return _exits


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
