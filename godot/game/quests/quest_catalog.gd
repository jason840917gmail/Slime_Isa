extends RefCounted
## The quest catalogue (Phaser `content/quests/QuestCatalog.ts` with the chapter files
## `quests/chapterOne.ts` and `chapterTwo.ts`), plus the recipe and NPC lookups the quest UI needs
## (`content/recipes/RecipeCatalog.ts`, `content/npcs/NpcDefinitions.ts`) and the player-facing
## reward and objective texts (`features/quests/QuestRewardText.ts`,
## `QuestTrackerSurfacePort.objectiveLabel`). Quests spec 1, 4.2, 4.4 and 8.
##
## Data: `game/data/quests-chapter-1.json` then `quests-chapter-2.json` (the catalogue order),
## `recipes.json` and `npc-definitions.json`, read once through `GameConstants.data_file`. The
## definitions keep Phaser's camelCase keys; JSON numbers are turned back into ints on a private
## copy (the parsed files are shared and never mutated). Validation stays on the TS side
## (`pnpm quests:check`); this file only checks the shape and push_errors.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

## QUEST_DEFINITIONS order (QuestCatalog.ts:5-8): chapter 1, then chapter 2.
const CHAPTER_FILES: Array[String] = ["quests-chapter-1.json", "quests-chapter-2.json"]
const RECIPES_FILE := "recipes.json"
const NPC_FILE := "npc-definitions.json"
## RETIRED_QUEST_IDS (QuestCatalog.ts:17-20): dropped from saves without a complaint.
const RETIRED_IDS: Array[String] = ["gather-building-materials"]
## The six quest statuses (types.ts).
const STATUSES: Array[String] = ["locked", "available", "active", "completed", "failed", "abandoned"]
## `Reward: the elder's gratitude` when a quest gives nothing (QuestRewardText.ts).
const NO_REWARD_SUMMARY := "Reward: the elder's gratitude"
## A tutorial objective's key (QuestTrackerSurfacePort.controlKey): control id -> [action, format].
const CONTROL_KEYS := {
	"menu:inventory": [&"menu", "%s"],
	"menu:crafting": [&"menu", "%s, then its tab"],
	"menu:journal": [&"menu", "%s, then its tab"],
	"menu:map": [&"map", "%s"],
	"sprint": [&"sprint", "hold %s"],
	"weapon-switch": [&"weapon_next", "%s"],
	"pause": [&"pause", "%s"],
}

static var _definitions: Array = []
static var _index: Dictionary = {}
static var _recipes: Array = []
static var _npcs: Dictionary = {}
static var _loaded: bool = false


# --- quests -------------------------------------------------------------------------------------

## Every quest definition in catalogue order (camelCase keys, ints normalised). Do not mutate.
static func definitions() -> Array:
	_ensure_loaded()
	return _definitions


## The definition of `quest_id`, {} when unknown.
static func definition(quest_id: String) -> Dictionary:
	_ensure_loaded()
	var index: int = _index.get(quest_id, -1)
	return _definitions[index] if index >= 0 else {}


static func has(quest_id: String) -> bool:
	_ensure_loaded()
	return _index.has(quest_id)


## Catalogue position of `quest_id` (-1 when unknown).
static func index_of(quest_id: String) -> int:
	_ensure_loaded()
	return int(_index.get(quest_id, -1))


## The definition's title, else the id (QuestNotificationPresenter.title).
static func title(quest_id: String) -> String:
	var found := definition(quest_id)
	return str(found.get("title", quest_id)) if not found.is_empty() else quest_id


static func stages(quest: Dictionary) -> Array:
	return quest.get("stages", []) if quest.get("stages") is Array else []


static func first_stage(quest: Dictionary) -> Dictionary:
	var list := stages(quest)
	return list[0] if not list.is_empty() else {}


## The stage `stage_id` of `quest`, {} when none.
static func stage(quest: Dictionary, stage_id: String) -> Dictionary:
	var index := stage_index(quest, stage_id)
	return stages(quest)[index] if index >= 0 else {}


static func stage_index(quest: Dictionary, stage_id: String) -> int:
	if stage_id.is_empty():
		return -1
	var list := stages(quest)
	for index in list.size():
		if str((list[index] as Dictionary).get("id", "")) == stage_id:
			return index
	return -1


static func objectives(stage_definition: Dictionary) -> Array:
	return stage_definition.get("objectives", []) if stage_definition.get("objectives") is Array else []


## The objective `objective_id` of any stage of `quest` (progress is keyed by objective id across
## the whole quest), {} when none.
static func objective(quest: Dictionary, objective_id: String) -> Dictionary:
	for stage_definition: Dictionary in stages(quest):
		for entry: Dictionary in objectives(stage_definition):
			if str(entry.get("id", "")) == objective_id:
				return entry
	return {}


## Ids listed under `key` of `source` (e.g. `acquisition.npcIds`), as Strings.
static func ids(source: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	var values: Variant = source.get(key)
	if values is Array:
		for value: Variant in values:
			out.append(str(value))
	return out


# --- recipes ------------------------------------------------------------------------------------

## RECIPE_CATALOG entries (camelCase: id, name, station, tier, ingredients, output).
static func recipes() -> Array:
	_ensure_loaded()
	return _recipes


static func recipe(recipe_id: String) -> Dictionary:
	for entry: Dictionary in recipes():
		if str(entry.get("id", "")) == recipe_id:
			return entry
	return {}


static func recipe_name(recipe_id: String) -> String:
	var entry := recipe(recipe_id)
	return str(entry.get("name", recipe_id)) if not entry.is_empty() else recipe_id


# --- NPCs ---------------------------------------------------------------------------------------

static func has_npc(npc_id: String) -> bool:
	_ensure_loaded()
	return _npcs.has(npc_id)


## `displayName`, else the id.
static func npc_name(npc_id: String) -> String:
	_ensure_loaded()
	var entry: Dictionary = _npcs.get(npc_id, {})
	return str(entry.get("displayName", npc_id)) if not entry.is_empty() else npc_id


## Plain talk without a quest (QuestNpcController.ts:194-196): `dialogue ?? [description ?? "Hello!"]`.
static func npc_default_pages(npc_id: String) -> Array:
	_ensure_loaded()
	var entry: Dictionary = _npcs.get(npc_id, {})
	if entry.get("dialogue") is Array and not (entry["dialogue"] as Array).is_empty():
		return (entry["dialogue"] as Array).duplicate()
	if entry.has("description"):
		return [str(entry["description"])]
	return ["Hello!"]


# --- texts --------------------------------------------------------------------------------------

## `questRewardLines`: coins, items ("<n>× " when more than one), recipes, abilities; flags are
## not listed.
static func reward_lines(rewards: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var coins := int(rewards.get("coins", 0))
	if coins != 0:
		lines.append("%d coins" % coins)
	for item: Variant in rewards.get("items", []):
		if not item is Dictionary:
			continue
		var count := int(item.get("count", 1))
		var prefix := "%d× " % count if count > 1 else ""
		lines.append(prefix + ItemCatalog.item_name(str(item.get("itemId", ""))))
	for recipe_id: String in ids(rewards, "recipeIds"):
		lines.append("New recipe: " + recipe_name(recipe_id))
	for ability_id: String in ids(rewards, "abilityIds"):
		lines.append("New ability: " + AbilityDefinitions.title(StringName(ability_id)))
	return lines


## `questRewardSummary`: "Reward: a · b · c", or the elder's gratitude when there is nothing.
static func reward_summary(rewards: Dictionary) -> String:
	var lines := reward_lines(rewards)
	return "Reward: " + " · ".join(lines) if not lines.is_empty() else NO_REWARD_SUMMARY


## `objectiveLabel`: a `use-control` objective names its key, e.g. "Open your bag (E)".
static func objective_label(entry: Dictionary) -> String:
	var label := str(entry.get("label", ""))
	if str(entry.get("kind", "")) != "use-control":
		return label
	var controls := ids(entry, "controlIds")
	if controls.is_empty() or not CONTROL_KEYS.has(controls[0]):
		return label
	var key: Array = CONTROL_KEYS[controls[0]]
	return "%s (%s)" % [label, str(key[1]) % ControlLabels.control_label(key[0])]


# --- loading ------------------------------------------------------------------------------------

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var constants := Services.constants()
	if constants == null:
		return
	_loaded = true
	_definitions = []
	_index = {}
	for file_name: String in CHAPTER_FILES:
		var parsed: Variant = constants.data_file(file_name)
		if not parsed is Array:
			push_error("QuestCatalog: %s is not a list of quests" % file_name)
			continue
		for entry: Variant in parsed:
			if not _valid_shape(entry):
				push_error("QuestCatalog: %s holds a malformed quest: %s" % [file_name, str(entry).left(120)])
				continue
			var quest: Dictionary = _integers(entry)
			var id := str(quest["id"])
			if _index.has(id):
				push_error("QuestCatalog: duplicate quest id '%s'" % id)
				continue
			_index[id] = _definitions.size()
			_definitions.append(quest)
	var recipe_data: Variant = constants.data_file(RECIPES_FILE)
	_recipes = _integers(recipe_data) if recipe_data is Array else []
	_npcs = {}
	var npc_data: Variant = constants.data_file(NPC_FILE)
	if npc_data is Array:
		for entry: Variant in npc_data:
			if entry is Dictionary and (entry as Dictionary).get("id") is String:
				_npcs[str(entry["id"])] = (entry as Dictionary).duplicate(true)


## id, title, category, acquisition, completion and at least one stage, each with at least one
## objective that has an id, a kind and a target.
static func _valid_shape(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	var quest: Dictionary = entry
	if not (quest.get("id") is String and quest.get("acquisition") is Dictionary and quest.get("completion") is Dictionary):
		return false
	var stage_list: Variant = quest.get("stages")
	if not stage_list is Array or (stage_list as Array).is_empty():
		return false
	for stage_entry: Variant in stage_list:
		if not stage_entry is Dictionary or not (stage_entry as Dictionary).get("id") is String:
			return false
		var objective_list: Variant = (stage_entry as Dictionary).get("objectives")
		if not objective_list is Array or (objective_list as Array).is_empty():
			return false
		for objective_entry: Variant in objective_list:
			if not objective_entry is Dictionary:
				return false
			var item: Dictionary = objective_entry
			if not (item.get("id") is String and item.get("kind") is String and (item.get("target") is float or item.get("target") is int)):
				return false
	return true


## A deep copy whose whole JSON numbers are ints again (targets, counts, coins, versions).
static func _integers(value: Variant) -> Variant:
	if value is float:
		var number: float = value
		return int(number) if is_finite(number) and number == floorf(number) and absf(number) < 9.0e15 else number
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _integers(value[key])
		return out
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_integers(item))
		return items
	return value
