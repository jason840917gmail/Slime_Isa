extends Node
## Autoload `RunState`: everything about the current run that outlives one world, shaped like
## Phaser's `GameSaveData` (infrastructure/persistence/SaveSchema.ts, schema v10) so the save
## phase can write it to user:// as is. Phaser keeps this state in GameState, the inventory, the
## world-progress and story stores, and hands it to the next area through a session-storage save
## (RunNavigationStore.ts); here it simply stays in this autoload while main.gd swaps worlds.
##
## Sections (snake_case keys; Phaser's camelCase names in brackets):
## - `player` [GameStateData]: coins, boost_bonus, hp, energy, goo_hearts, attributes, equipment
##   {weapon_id, weapon_slots}. The player script owns live HP; main.gd copies it in and out at
##   world boundaries (`capture_player` / spawn).
## - `inventory` [InventorySaveData]: max_slots, slots [{item_id, count}].
## - `world` [WorldProgressData]: discovered_areas, defeated_boss_ids, completed_dungeon_ids,
##   maps {map_id: map record}, respawn_point.
## - `story` [StorySaveData]: world_flags, learned_recipe_ids, learned_ability_ids, talked_npc_ids.
## - `location` [GameLocationData], play time (`current_play_time_ms()`).
## - `quests` [QuestState[]]: one record per quest, written by the quest service.
##
## A map record [MapRuntimeStateData] has: resources, collectibles, inventory_drops,
## next_inventory_drop_sequence, placed_furniture, next_placed_furniture_sequence, boss_camps,
## chests, completed_encounter_ids, opened_reward_ids, unlocked_gate_ids, object_states.
## World-object scripts read and write their own entry through `map_record(map_id)`.
##
## Access from scripts: `Services.run()` (res://game/shared/services.gd).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const SaveSlotsMenu := preload("res://game/saves/save_slots_menu.gd")

## InitialRun.ts:16 (a literal there too).
const NEW_RUN_COINS := 50
## InitialRun.ts: the run starts in level-1.
const INITIAL_MAP_ID := "level-1"
## WEAPON_HOTBAR_SLOT_COUNT (core/types.ts:17).
const WEAPON_SLOT_COUNT := 4

## A story flag was set (or cleared). Payload: {"flag": String, "set": bool}.
signal story_flag_changed(payload: Dictionary)
## An ability was learned. Payload: {"ability_id": String}.
signal ability_learned(payload: Dictionary)
## The bag changed (Phaser `inventory.changed`). Payload: {}.
signal inventory_changed(payload: Dictionary)
## A world-object record changed (Phaser `world.progress.changed`). Payload: {"map_id": String}.
signal world_progress_changed(payload: Dictionary)
## Coins changed (GameState.addCoins / spendCoins). Payload: {"coins": int, "delta": int}.
signal coins_changed(payload: Dictionary)
## The weapon belt changed (Phaser `weapon.loadout.changed`). Payload: {"slots": Array}.
signal weapon_loadout_changed(payload: Dictionary)
## The weapon in hand changed (Phaser `weapon.equipped`). Payload: {"weapon_id": String or null}.
signal weapon_equipped(payload: Dictionary)
## Recipes were learned. Payload: {"recipe_ids": Array[String]} (the new ids only).
signal recipes_learned(payload: Dictionary)
## A craft succeeded (Phaser `craft.completed`). Payload: {"recipeId", "itemId", "quantity"}.
signal recipe_crafted(payload: Dictionary)
## The Craft button was refused (Phaser `craft.failed`). Payload: {"recipeId", "reason"}.
signal craft_failed(payload: Dictionary)
## A quest record changed (the quest service calls `notify_quests_changed`). Payload: {"quest_id"}.
signal quests_changed(payload: Dictionary)

var player: Dictionary = {}
var inventory: Dictionary = {}
var world: Dictionary = {}
var story: Dictionary = {}
var location: Dictionary = {}
var quests: Array = []
## True after `new_run()` or a load; main.gd starts a new run on its first boot otherwise.
var started: bool = false

## Saves (section "saves" below).
const SAVE_SCHEMA_VERSION := 1
const AUTOSAVE_SLOT := 0
const AUTOSAVE_DELAY_MS := 250.0
const SLOT_PREFIX := "slot-"
## Where saves live; the test runner points it at a scratch folder.
var save_root: String = "user://saves"
## The recovery autosave runs only while a world is being played (main.gd turns it on).
var autosave_enabled: bool = false
## main.gd: returns the live player's {"map_id", "hp", "energy", "x", "y", "facing"} for saves.
var location_provider: Callable = Callable()
var _autosave_timer: Timer
var _play_time_base_ms: float = 0.0
var _play_started_ms: float = 0.0

## A save was written. Payload: {"slot": int}.
signal saved(payload: Dictionary)
## A save was installed. Payload: {"slot": int}.
signal loaded(payload: Dictionary)

## Dev and tests: quest ids that count as active whatever their record says (a restoration site
## with a quest id stays locked unless its quest is active).
var debug_active_quests: Array[String] = []
## Dev stand-in until quests teach recipes (crafting spec C2, launch option `recipes`): every
## recipe counts as known. `new_run()` clears it.
var debug_all_recipes_known: bool = false
## Trial (crafting spec C3): true from `new_run()` until main.gd hands out the trial weapon (bag,
## belt slot 1, hand) at the run's first world build. A loaded run never has it.
var trial_weapon_pending: bool = false

## The pending area handoff [RunNavigationHandoff]: {"kind": "area"|"load"|"reset", "map_id",
## "entry_edge"?, "entry_door"?, "respawn_home"?}. Empty when none.
var _navigation: Dictionary = {}


## Phaser `createInitialRunState()` (content/initial-state/InitialRun.ts).
func new_run() -> void:
	var constants := Services.constants()
	var full_hp := _constant_int(constants, "character.player.stats.maxHp")
	var max_energy := _constant_int(constants, "character.player.stats.maxEnergy")
	var attributes: Dictionary = constants.dictionary("character.player.initialAttributes").duplicate(true) if constants != null else {}
	var weapon_slots: Array = []
	weapon_slots.resize(WEAPON_SLOT_COUNT)
	player = {
		"coins": NEW_RUN_COINS,
		"boost_bonus": 0,
		"hp": full_hp,
		"energy": max_energy,
		"goo_hearts": 0,
		"attributes": attributes,
		"equipment": {"weapon_id": null, "weapon_slots": weapon_slots},
	}
	inventory = {"max_slots": _constant_int(constants, "inventory.initialMaxSlots"), "slots": []}
	world = {
		"discovered_areas": [INITIAL_MAP_ID],
		"defeated_boss_ids": [],
		"completed_dungeon_ids": [],
		"maps": {},
		"respawn_point": {},
	}
	story = {"world_flags": [], "learned_recipe_ids": [], "learned_ability_ids": [], "talked_npc_ids": []}
	location = {"area_id": INITIAL_MAP_ID, "map_id": INITIAL_MAP_ID, "x": 0.0, "y": 0.0, "facing": "down"}
	quests = []
	_play_time_base_ms = 0.0
	_play_started_ms = Time.get_ticks_msec()
	debug_active_quests = []
	debug_all_recipes_known = false
	trial_weapon_pending = true
	_navigation = {}
	started = true


## Starts a new run if none is in progress (first boot, or a test that cleared it).
func ensure_started() -> void:
	if not started:
		new_run()


# --- player -----------------------------------------------------------------------------------

## GameState.maxHp: `stats.maxHp + goo_hearts * gooHeart.maxHpBonus`.
func max_hp() -> int:
	var constants := Services.constants()
	return _constant_int(constants, "character.player.stats.maxHp") \
			+ int(player.get("goo_hearts", 0)) * _constant_int(constants, "character.player.gooHeart.maxHpBonus")


## Copies the live player's state into `player` and `location` (before a world is left).
## `state` = {"hp": int, "energy": float, "facing": "up"|"down"|"left"|"right", "x": float,
## "y": float} with x/y the old Phaser (centre) position.
func capture_player(map_id: String, state: Dictionary) -> void:
	if state.has("hp"):
		player["hp"] = clampi(int(state["hp"]), 0, max_hp())
	if state.has("energy"):
		player["energy"] = float(state["energy"])
	location = {
		"area_id": map_id,
		"map_id": map_id,
		"x": float(state.get("x", 0.0)),
		"y": float(state.get("y", 0.0)),
		"facing": str(state.get("facing", "down")),
	}


# --- coins ------------------------------------------------------------------------------------

func coins() -> int:
	return int(player.get("coins", 0))


## GameState.addCoins: `max(0, coins + amount)`; nothing for 0.
func add_coins(amount: int) -> void:
	if amount == 0:
		return
	player["coins"] = maxi(0, coins() + amount)
	coins_changed.emit({"coins": coins(), "delta": amount})


## GameState.spendCoins: false (and nothing spent) when there are too few.
func spend_coins(amount: int) -> bool:
	if coins() < amount:
		return false
	player["coins"] = coins() - amount
	coins_changed.emit({"coins": coins(), "delta": -amount})
	return true


# --- inventory (systems/Inventory.ts; world-objects spec 8) -----------------------------------
## Slots are an ordered list with no holes: emptied slots are removed, new stacks are appended.

## How many of `item_id` the bag holds (PlayerInventory.count).
func item_count(item_id: String) -> int:
	var total := 0
	for slot: Dictionary in inventory.get("slots", []):
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


## How many more of `item_id` fit (world-objects spec 8.3): room left in its stacks below the
## max stack plus a full stack per free slot; 0 for unknown items.
func item_capacity(item_id: String) -> int:
	var max_stack := ItemCatalog.max_stack(item_id)
	if max_stack <= 0:
		return 0
	var slots: Array = inventory.get("slots", [])
	var room := 0
	for slot: Dictionary in slots:
		if str(slot.get("item_id", "")) == item_id and int(slot.get("count", 0)) < max_stack:
			room += max_stack - int(slot["count"])
	return room + maxi(0, int(inventory.get("max_slots", 0)) - slots.size()) * max_stack


## Inventory.add, all or nothing: fills the item's stacks in slot order up to the max stack, then
## appends new stacks while slots are free. Returns `count`, or 0 when it does not all fit.
func add_item(item_id: String, count: int) -> int:
	if count <= 0 or item_capacity(item_id) < count:
		return 0
	_insert(item_id, count)
	inventory_changed.emit({})
	return count


## Takes `count` of `item_id` from the first matching slot onward (Inventory.remove); false (and
## nothing taken) when the bag holds fewer.
func remove_item(item_id: String, count: int) -> bool:
	if count <= 0:
		return true
	if item_count(item_id) < count:
		return false
	var slots: Array = inventory.get("slots", [])
	var left := count
	var index := 0
	while index < slots.size() and left > 0:
		var slot: Dictionary = slots[index]
		if str(slot.get("item_id", "")) != item_id:
			index += 1
			continue
		var taken := mini(left, int(slot["count"]))
		slot["count"] = int(slot["count"]) - taken
		left -= taken
		if int(slot["count"]) <= 0:
			slots.remove_at(index)
		else:
			index += 1
	inventory_changed.emit({})
	return true


## `InventoryWorldTransaction.collectWorldItem` (world-objects spec 8.3): moves as much of a world
## pile as fits, writes its collectible record and returns the amount moved (0 = nothing fits).
## The record's `remaining` wins over `remaining`; source ids already saved win over the given ones.
func collect_world_item(map_id: String, instance_id: String, item_id: String, remaining: int,
		requested: int = -1, source_resource_instance_id: String = "", source_inventory_drop_id: String = "") -> int:
	var saved := collectible_record(map_id, instance_id)
	var left := int(saved.get("remaining", remaining))
	var asked := requested if requested >= 0 else left
	if left <= 0 or asked <= 0:
		return 0
	var moved := mini(mini(left, asked), item_capacity(item_id))
	if moved <= 0:
		return 0
	_insert(item_id, moved)
	var record := {"remaining": left - moved}
	var resource_source := str(saved.get("source_resource_instance_id", source_resource_instance_id))
	var drop_source := str(saved.get("source_inventory_drop_id", source_inventory_drop_id))
	if not resource_source.is_empty():
		record["source_resource_instance_id"] = resource_source
	if not drop_source.is_empty():
		record["source_inventory_drop_id"] = drop_source
	_collectibles(map_id)[instance_id] = record
	inventory_changed.emit({})
	world_progress_changed.emit({"map_id": map_id})
	return moved


func _insert(item_id: String, count: int) -> void:
	var max_stack := ItemCatalog.max_stack(item_id)
	var slots: Array = inventory.get_or_add("slots", [])
	var left := count
	for slot: Dictionary in slots:
		if left <= 0:
			break
		if str(slot.get("item_id", "")) != item_id or int(slot.get("count", 0)) >= max_stack:
			continue
		var added := mini(left, max_stack - int(slot["count"]))
		slot["count"] = int(slot["count"]) + added
		left -= added
	while left > 0 and slots.size() < int(inventory.get("max_slots", 0)):
		var stack := mini(max_stack, left)
		slots.append({"item_id": item_id, "count": stack})
		left -= stack


## `Inventory.transact` (crafting spec 2.5): all or nothing, one `inventory_changed`. Removals
## (summed per item, first-seen order) come out of the first matching slot onward; emptied slots
## are dropped; then additions (summed) fill that item's stacks below the max stack in slot order
## and append new stacks while slots are free. `removals` / `additions`: [{"item_id", "count"}]
## with counts > 0. False (nothing changed) when anything is missing, unknown or does not fit.
## `preview` (Inventory.previewTransact) only answers.
func transact_items(removals: Array, additions: Array, preview: bool = false) -> bool:
	var taken := _summed(removals)
	var given := _summed(additions)
	if taken.is_empty() and given.is_empty() and (not removals.is_empty() or not additions.is_empty()):
		return false
	var draft: Array = (inventory.get("slots", []) as Array).duplicate(true)
	for item_id: String in taken:
		var left: int = taken[item_id]
		for slot: Dictionary in draft:
			if left <= 0:
				break
			if str(slot.get("item_id", "")) != item_id:
				continue
			var take := mini(left, int(slot.get("count", 0)))
			slot["count"] = int(slot.get("count", 0)) - take
			left -= take
		if left > 0:
			return false
	var compact: Array = []
	for slot: Dictionary in draft:
		if int(slot.get("count", 0)) > 0:
			compact.append(slot)
	var max_slots := int(inventory.get("max_slots", 0))
	for item_id: String in given:
		var max_stack := ItemCatalog.max_stack(item_id)
		if max_stack <= 0:
			return false
		var left: int = given[item_id]
		for slot: Dictionary in compact:
			if left <= 0:
				break
			if str(slot.get("item_id", "")) != item_id or int(slot.get("count", 0)) >= max_stack:
				continue
			var added := mini(left, max_stack - int(slot["count"]))
			slot["count"] = int(slot["count"]) + added
			left -= added
		while left > 0 and compact.size() < max_slots:
			var stack := mini(max_stack, left)
			compact.append({"item_id": item_id, "count": stack})
			left -= stack
		if left > 0:
			return false
	if preview:
		return true
	inventory["slots"] = compact
	inventory_changed.emit({})
	return true


## `Inventory.removeFromSlot`: takes min(count, slot count) from slot `index` (the slot goes at 0).
## Returns the amount taken (0 for a bad index or count).
func remove_from_slot(index: int, count: int) -> int:
	var slots: Array = inventory.get("slots", [])
	if index < 0 or index >= slots.size() or count <= 0:
		return 0
	var slot: Dictionary = slots[index]
	var taken := mini(count, int(slot.get("count", 0)))
	slot["count"] = int(slot.get("count", 0)) - taken
	if int(slot["count"]) <= 0:
		slots.remove_at(index)
	inventory_changed.emit({})
	return taken


## A copy of the bag slots ([{item_id, count}], slot order) for windows and tests.
func slots() -> Array:
	return (inventory.get("slots", []) as Array).duplicate(true)


## {item_id: total count} for [{"item_id", "count"}] entries, first-seen order; {} when any entry
## is malformed (blank id or count <= 0).
static func _summed(entries: Array) -> Dictionary:
	var totals := {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			return {}
		var item_id := str(entry.get("item_id", ""))
		var count := int(entry.get("count", 0))
		if item_id.is_empty() or count <= 0:
			return {}
		totals[item_id] = int(totals.get(item_id, 0)) + count
	return totals


# --- weapon belt (GameState equipment; crafting spec 8.1) --------------------------------------
## The belt names weapons that live in the bag (it never holds them); `weapon_id` is the weapon in
## hand. The rules (owned checks, swaps, cycling) are in res://game/player/weapon_loadout.gd.

## A copy of the 4 belt entries (String, or null when empty).
func weapon_slots() -> Array:
	var equipment: Dictionary = player.get_or_add("equipment", {})
	return _normalised_slots(equipment.get("weapon_slots", []))


## `GameState.setWeaponSlots`: blank or non-string entries become null, size 4; signals only on
## a change.
func set_weapon_slots(slots: Array) -> void:
	var next := _normalised_slots(slots)
	var equipment: Dictionary = player.get_or_add("equipment", {})
	if equipment.get("weapon_slots") is Array and next == equipment["weapon_slots"]:
		return
	equipment["weapon_slots"] = next
	weapon_loadout_changed.emit({"slots": next.duplicate()})


## The weapon in hand (String), or null.
func equipped_weapon_id() -> Variant:
	var id: Variant = (player.get_or_add("equipment", {}) as Dictionary).get("weapon_id")
	return id if id is String and not (id as String).strip_edges().is_empty() else null


## `GameState.equipWeapon`: trims, "" -> null; false when unchanged, else stores and signals.
func set_equipped_weapon(weapon_id: Variant) -> bool:
	var next: Variant = null
	if weapon_id is String and not (weapon_id as String).strip_edges().is_empty():
		next = (weapon_id as String).strip_edges()
	if next == equipped_weapon_id():
		return false
	(player.get_or_add("equipment", {}) as Dictionary)["weapon_id"] = next
	weapon_equipped.emit({"weapon_id": next})
	return true


static func _normalised_slots(slots: Variant) -> Array:
	var out: Array = []
	out.resize(WEAPON_SLOT_COUNT)
	if slots is Array:
		for index in mini(WEAPON_SLOT_COUNT, (slots as Array).size()):
			var entry: Variant = slots[index]
			if entry is String and not (entry as String).strip_edges().is_empty():
				out[index] = (entry as String).strip_edges()
	return out


## `playerInventoryWorldTransaction.unlockGate`: true when the gate is (or already was) unlocked;
## the key is taken when `consume`. False without the key.
func unlock_gate(map_id: String, gate_id: String, required_item_id: String, consume: bool) -> bool:
	if is_gate_unlocked(map_id, gate_id):
		return true
	if item_count(required_item_id) < 1:
		return false
	if consume and not remove_item(required_item_id, 1):
		return false
	mark_gate_unlocked(map_id, gate_id)
	return true


# --- story ------------------------------------------------------------------------------------

func has_flag(flag: String) -> bool:
	return flag in _flags()


## Sets a story flag for good (StoryFlags.set). Returns false when it was already set.
func set_flag(flag: String) -> bool:
	if flag.is_empty() or has_flag(flag):
		return false
	_flags().append(flag)
	story_flag_changed.emit({"flag": flag, "set": true})
	return true


## `storyProgress.recordTalk`: remembers that the player talked to `npc_id`.
func record_talk(npc_id: String) -> void:
	var talked := _story_list("talked_npc_ids")
	if not npc_id.is_empty() and not npc_id in talked:
		talked.append(npc_id)


func has_talked_to(npc_id: String) -> bool:
	return npc_id in _story_list("talked_npc_ids")


## `StoryProgress.knowsRecipe` (or every recipe under `debug_all_recipes_known`).
func knows_recipe(recipe_id: String) -> bool:
	return debug_all_recipes_known or recipe_id in _story_list("learned_recipe_ids")


## `StoryProgress.learnRecipes`: appends the ids not known yet and returns them; signals when any.
func learn_recipes(recipe_ids: Array) -> Array[String]:
	var learned := _story_list("learned_recipe_ids")
	var added: Array[String] = []
	for recipe_id: Variant in recipe_ids:
		var id := str(recipe_id)
		if not id.is_empty() and not id in learned and not id in added:
			learned.append(id)
			added.append(id)
	if not added.is_empty():
		recipes_learned.emit({"recipe_ids": added.duplicate()})
	return added


func has_learned_ability(ability_id: String) -> bool:
	return ability_id in _story_list("learned_ability_ids")


## Returns false when it was already learned.
func learn_ability(ability_id: String) -> bool:
	if ability_id.is_empty() or has_learned_ability(ability_id):
		return false
	_story_list("learned_ability_ids").append(ability_id)
	ability_learned.emit({"ability_id": ability_id})
	return true


# --- quests --------------------------------------------------------------------------------------
## `quests` holds one record per quest in catalog order (res://game/quests/quest_service.gd owns
## the rules): {"quest_id", "definition_version", "status", "active_stage_id", "progress",
## "consumed_fact_ids", "rewards_granted", "accepted_at"?, "completed_at"?, ...}.

## The record's status ("locked" when the quest has no record).
func quest_status(quest_id: String) -> String:
	for record: Variant in quests:
		if record is Dictionary and str(record.get("quest_id", "")) == quest_id:
			return str(record.get("status", "locked"))
	return "locked"


func is_quest_active(quest_id: String) -> bool:
	return quest_id in debug_active_quests or quest_status(quest_id) == "active"


## The quest service calls this after every change to a record (autosave, HUD).
func notify_quests_changed(quest_id: String) -> void:
	quests_changed.emit({"quest_id": quest_id})


## One more Goo Heart (GameState.addGooHeart): max HP grows; the player fills its HP.
func add_goo_heart() -> void:
	player["goo_hearts"] = int(player.get("goo_hearts", 0)) + 1
	player["hp"] = max_hp()


# --- world progress ---------------------------------------------------------------------------
## Resource record (WorldProgress / SaveSchema ResourceProgressStateData, snake_case):
## {"stage": "node"|"destroyed"|"depleted", "value": float >= 0, "piles"?: [{"id", "cell_x",
## "cell_y", "amount", "offset_x"?, "offset_y"?, "object_id"?, "visual_id"?}],
## "respawn_ready_at_epoch_ms"?}. Collectible record: {"remaining": int >= 0,
## "source_resource_instance_id"?, "source_inventory_drop_id"?}. World-objects spec 9.

## A copy of the resource record of `instance_id`; {} when none.
func resource_record(map_id: String, instance_id: String) -> Dictionary:
	var record: Variant = (map_record(map_id)["resources"] as Dictionary).get(instance_id)
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


## `setResourceState` (WorldProgress.ts:392-404): keeps the previous regrow timer when the new
## stage is not "node" and the new record has none; clamps value and pile amounts at 0; omits an
## empty pile list. No change, no signal.
func set_resource_record(map_id: String, instance_id: String, record: Dictionary) -> void:
	var resources: Dictionary = map_record(map_id)["resources"]
	var previous: Dictionary = resources.get(instance_id, {})
	var next := {"stage": str(record.get("stage", "node")), "value": maxf(0.0, float(record.get("value", 0.0)))}
	var piles: Array = []
	for pile: Dictionary in record.get("piles", []):
		var copy := pile.duplicate()
		copy["amount"] = maxi(0, int(copy.get("amount", 0)))
		piles.append(copy)
	if not piles.is_empty():
		next["piles"] = piles
	if record.has("respawn_ready_at_epoch_ms"):
		next["respawn_ready_at_epoch_ms"] = float(record["respawn_ready_at_epoch_ms"])
	elif next["stage"] != "node" and previous.has("respawn_ready_at_epoch_ms"):
		next["respawn_ready_at_epoch_ms"] = previous["respawn_ready_at_epoch_ms"]
	if previous == next:
		return
	resources[instance_id] = next
	world_progress_changed.emit({"map_id": map_id})


## `clearResourceState` (WorldProgress.ts:407-419): forgets the node and every collectible record
## of its piles (sourced from it, or keyed "<node>-drop-..."), so a regrown node's piles start full.
func clear_resource_record(map_id: String, instance_id: String) -> void:
	var record := map_record(map_id)
	(record["resources"] as Dictionary).erase(instance_id)
	var collectibles: Dictionary = record["collectibles"]
	var prefix := instance_id + "-drop-"
	for key: String in collectibles.keys():
		var entry: Dictionary = collectibles[key]
		if str(entry.get("source_resource_instance_id", "")) == instance_id or key.begins_with(prefix):
			collectibles.erase(key)
	world_progress_changed.emit({"map_id": map_id})


## A copy of the collectible record of `instance_id`; {} when none.
func collectible_record(map_id: String, instance_id: String) -> Dictionary:
	var record: Variant = _collectibles(map_id).get(instance_id)
	return (record as Dictionary).duplicate() if record is Dictionary else {}


## `setCollectibleState`: `remaining = max(0, floor(remaining))`.
func set_collectible_record(map_id: String, instance_id: String, record: Dictionary) -> void:
	var next := record.duplicate()
	next["remaining"] = maxi(0, floori(float(record.get("remaining", 0))))
	_collectibles(map_id)[instance_id] = next
	world_progress_changed.emit({"map_id": map_id})


func _collectibles(map_id: String) -> Dictionary:
	return map_record(map_id)["collectibles"]


## A copy of what is left in a chest ({item_id: count}); {} when empty or unknown.
func chest_remaining(map_id: String, instance_id: String) -> Dictionary:
	var record: Variant = (map_record(map_id)["chests"] as Dictionary).get(instance_id)
	if not record is Dictionary:
		return {}
	return ((record as Dictionary).get("remaining", {}) as Dictionary).duplicate()


## `WorldProgress.ensureChestInitialized`: creates the record from `contents` only when none
## exists (counts > 0 kept).
func ensure_chest(map_id: String, instance_id: String, contents: Dictionary) -> void:
	var chests: Dictionary = map_record(map_id)["chests"]
	if chests.has(instance_id):
		return
	chests[instance_id] = {"remaining": _positive(contents)}
	world_progress_changed.emit({"map_id": map_id})


## Replaces a chest's contents (counts <= 0 dropped).
func set_chest_remaining(map_id: String, instance_id: String, contents: Dictionary) -> void:
	(map_record(map_id)["chests"] as Dictionary)[instance_id] = {"remaining": _positive(contents)}
	world_progress_changed.emit({"map_id": map_id})


## `InventoryWorldTransaction.transferChestStack`: moves as much of the chest's `item_id` as fits
## into the bag; returns the count moved (0 when nothing fits or the chest has none).
func transfer_chest_stack(map_id: String, instance_id: String, item_id: String) -> int:
	var contents := chest_remaining(map_id, instance_id)
	var moved := mini(int(contents.get(item_id, 0)), item_capacity(item_id))
	if moved <= 0:
		return 0
	_insert(item_id, moved)
	contents[item_id] = int(contents[item_id]) - moved
	(map_record(map_id)["chests"] as Dictionary)[instance_id] = {"remaining": _positive(contents)}
	inventory_changed.emit({})
	world_progress_changed.emit({"map_id": map_id})
	return moved


static func _positive(contents: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in contents:
		if int(contents[key]) > 0:
			out[str(key)] = int(contents[key])
	return out


## The persistent record of `map_id`, created empty on first use (MapRuntimeStateData).
func map_record(map_id: String) -> Dictionary:
	var maps: Dictionary = world.get_or_add("maps", {})
	if not maps.has(map_id):
		maps[map_id] = {
			"resources": {},
			"collectibles": {},
			"inventory_drops": {},
			"next_inventory_drop_sequence": 1,
			"placed_furniture": {},
			"next_placed_furniture_sequence": 1,
			"boss_camps": {},
			"chests": {},
			"completed_encounter_ids": [],
			"opened_reward_ids": [],
			"unlocked_gate_ids": [],
			"object_states": {},
		}
	return maps[map_id]


func is_gate_unlocked(map_id: String, gate_id: String) -> bool:
	return gate_id in (map_record(map_id)["unlocked_gate_ids"] as Array)


## Returns false when it was already unlocked.
func mark_gate_unlocked(map_id: String, gate_id: String) -> bool:
	var unlocked: Array = map_record(map_id)["unlocked_gate_ids"]
	if gate_id.is_empty() or gate_id in unlocked:
		return false
	unlocked.append(gate_id)
	return true


## `objectStates[key]` of a map (webs torn, hearts taken, sites restored, ...); `fallback` when unset.
func object_state(map_id: String, key: String, fallback: Variant = null) -> Variant:
	return (map_record(map_id)["object_states"] as Dictionary).get(key, fallback)


func set_object_state(map_id: String, key: String, value: Variant) -> void:
	(map_record(map_id)["object_states"] as Dictionary)[key] = value


func is_area_discovered(area_id: String) -> bool:
	return area_id in (world.get("discovered_areas", []) as Array)


func is_boss_defeated(boss_id: String) -> bool:
	return boss_id in (world.get("defeated_boss_ids", []) as Array)


## The map's bag and loot drops still on the ground: copies of {"id", "item_id", "amount",
## "object_id", "visual_id", "x", "y", "origin"?} (WorldProgress.ts:444-479), sequence order.
func inventory_drops(map_id: String) -> Array:
	var out: Array = []
	for record: Variant in (map_record(map_id)["inventory_drops"] as Dictionary).values():
		if record is Dictionary and int(record.get("amount", 0)) > 0:
			out.append((record as Dictionary).duplicate())
	return out


## `WorldProgress.createInventoryDrop`: records `drop` as "inventory-drop-<sequence>" (the
## sequence then grows) and returns the record.
func create_inventory_drop(map_id: String, drop: Dictionary) -> Dictionary:
	var record_map := map_record(map_id)
	var sequence := int(record_map.get("next_inventory_drop_sequence", 1))
	var record := drop.duplicate()
	record["id"] = "inventory-drop-%d" % sequence
	(record_map["inventory_drops"] as Dictionary)[record["id"]] = record
	record_map["next_inventory_drop_sequence"] = sequence + 1
	world_progress_changed.emit({"map_id": map_id})
	return record.duplicate()


## `WorldProgress.setInventoryDropAmount`: floor, at least 0; the record goes at 0.
func set_inventory_drop_amount(map_id: String, drop_id: String, amount: int) -> void:
	var drops: Dictionary = map_record(map_id)["inventory_drops"]
	if not drops.has(drop_id):
		return
	if amount <= 0:
		drops.erase(drop_id)
	else:
		drops[drop_id]["amount"] = amount
	world_progress_changed.emit({"map_id": map_id})


func mark_area_discovered(area_id: String) -> void:
	var discovered: Array = world.get_or_add("discovered_areas", [])
	if not area_id.is_empty() and not area_id in discovered:
		discovered.append(area_id)


## Where the player wakes after defeat (the last bed slept in); {} when none.
func respawn_point() -> Dictionary:
	return world.get("respawn_point", {})


## `point` = {"area_id", "map_id", "x", "y", "bed_id"?} (old Phaser coordinates).
func set_respawn_point(point: Dictionary) -> void:
	world["respawn_point"] = point.duplicate()


# --- navigation handoff -----------------------------------------------------------------------

## Queues the next world for main.gd (RunNavigationStore.writeRunNavigation). `entry_edge` is
## "north"|"east"|"south"|"west" or "", `entry_door` a door id in the target world or "".
func request_navigation(kind: String, map_id: String, entry_edge: String = "", entry_door: String = "", respawn_home: bool = false) -> void:
	_navigation = {"kind": kind, "map_id": map_id}
	if not entry_edge.is_empty():
		_navigation["entry_edge"] = entry_edge
	if not entry_door.is_empty():
		_navigation["entry_door"] = entry_door
	if respawn_home:
		_navigation["respawn_home"] = true


## The pending handoff, removed (consumeRunNavigation); {} when none.
func consume_navigation() -> Dictionary:
	var pending := _navigation
	_navigation = {}
	return pending


func peek_navigation() -> Dictionary:
	return _navigation


# --- helpers ----------------------------------------------------------------------------------

func _flags() -> Array:
	return _story_list("world_flags")


func _story_list(key: String) -> Array:
	return story.get_or_add(key, [])


static func _constant_int(constants: Services.GameConstantsType, path: String) -> int:
	return constants.integer(path) if constants != null else 0


# --- saves (Phaser SaveSystem.ts + SaveRepository.ts) ------------------------------------------
## Files under `save_root`: slot 0 is the recovery autosave (written 250 ms after the run changes,
## never while the slime is dead, and when the window closes); slots 1+ are named saves. Each file
## is {"schema_version", "saved_at" (unix ms), "data": `serialize()`}. Loading installs the run
## and queues a "load" navigation, so main.tscn boots in the saved world at the saved spot.

## The run as Phaser's GameSaveData (snake_case keys), ready for JSON.
func serialize() -> Dictionary:
	_capture_live_player()
	return {
		"player": player.duplicate(true),
		"inventory": inventory.duplicate(true),
		"quests": quests.duplicate(true),
		"location": location.duplicate(true),
		"world": world.duplicate(true),
		"story": story.duplicate(true),
		"play_time_ms": current_play_time_ms(),
	}


## Replaces the run with `data` (a `serialize()` result); false (and nothing changed) when it is
## not one. A run saved at the moment of defeat wakes with full health.
func install(data: Dictionary) -> bool:
	for key: String in ["player", "inventory", "location", "world", "story"]:
		if not data.get(key) is Dictionary:
			return false
	var fresh := data.duplicate(true)
	player = fresh["player"]
	inventory = fresh["inventory"]
	location = fresh["location"]
	world = fresh["world"]
	story = fresh["story"]
	quests = fresh.get("quests", []) if fresh.get("quests") is Array else []
	if int(player.get("hp", 0)) <= 0:
		player["hp"] = max_hp()
	world.get_or_add("maps", {})
	world.get_or_add("discovered_areas", [])
	_play_time_base_ms = float(fresh.get("play_time_ms", 0.0))
	_play_started_ms = Time.get_ticks_msec()
	_navigation = {}
	trial_weapon_pending = false
	started = true
	return true


func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Writes the run to `slot` (0 = the autosave). False when it could not be written.
func save_slot(slot: int = 0) -> bool:
	if not started:
		return false
	DirAccess.make_dir_recursive_absolute(save_root)
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_warning("RunState: cannot write %s (%s)" % [_slot_path(slot), error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({"schema_version": SAVE_SCHEMA_VERSION,
		"saved_at": Time.get_unix_time_from_system() * 1000.0, "data": serialize()}, "\t"))
	file.close()
	saved.emit({"slot": slot})
	return true


## Installs the run in `slot` and queues a "load" navigation into its world; false when the file
## is missing, unreadable, from a newer schema, or names a world that does not exist.
func load_slot(slot: int = 0) -> bool:
	var record := read_slot(slot)
	if record.is_empty():
		return false
	var data: Dictionary = record["data"]
	var map_id := str((data["location"] as Dictionary).get("map_id", ""))
	var world_service := Services.world()
	if map_id.is_empty() or (world_service != null and world_service.scene_path("world." + map_id).is_empty()):
		return false
	if not install(data):
		return false
	request_navigation("load", map_id)
	loaded.emit({"slot": slot})
	return true


## {"schema_version", "saved_at", "data"} of `slot`, or {} when missing or unreadable (with a
## warning for an unreadable file).
func read_slot(slot: int) -> Dictionary:
	var inspected := inspect_slot(slot)
	if not str(inspected["problem"]).is_empty():
		push_warning("RunState: cannot load %s: %s" % [_slot_path(slot), inspected["problem"]])
	return inspected["record"]


## What is in `slot`, quietly: {"exists": bool, "record": the read_slot record or {}, "problem":
## "" or why an existing file cannot be loaded ("not a save file", "made by a newer version")}.
func inspect_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false, "record": {}, "problem": ""}
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not parsed is Dictionary:
		return {"exists": true, "record": {}, "problem": "not a save file"}
	var record: Dictionary = _integers(parsed)
	if int(record.get("schema_version", 0)) > SAVE_SCHEMA_VERSION or not record.get("data") is Dictionary:
		return {"exists": true, "record": {}, "problem": "made by a newer version"}
	return {"exists": true, "record": record, "problem": ""}


func delete_slot(slot: int) -> bool:
	return has_save(slot) and DirAccess.remove_absolute(_slot_path(slot)) == OK


## Every readable save: [{"slot", "saved_at", "map_id", "play_time_ms"}], slot order.
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(save_root)
	if dir == null:
		return out
	var slots: Array[int] = []
	for file_name in dir.get_files():
		if file_name.begins_with(SLOT_PREFIX) and file_name.ends_with(".json"):
			var number := file_name.trim_prefix(SLOT_PREFIX).trim_suffix(".json")
			if number.is_valid_int():
				slots.append(int(number))
	slots.sort()
	for slot in slots:
		var record := read_slot(slot)
		if record.is_empty():
			continue
		var data: Dictionary = record["data"]
		out.append({"slot": slot, "saved_at": float(record.get("saved_at", 0.0)),
			"map_id": str((data["location"] as Dictionary).get("map_id", "")),
			"play_time_ms": float(data.get("play_time_ms", 0.0))})
	return out


## Asks for the recovery autosave 250 ms from now (later changes push it back).
func schedule_autosave() -> void:
	if not autosave_enabled or not started or _autosave_timer == null:
		return
	_autosave_timer.start(AUTOSAVE_DELAY_MS / 1000.0)


## Writes the recovery autosave now, unless the slime is dead (`SaveSystem.writeRecovery`).
func write_recovery() -> bool:
	if _autosave_timer != null:
		_autosave_timer.stop()
	if not autosave_enabled or not started:
		return false
	_capture_live_player()
	if int(player.get("hp", 0)) <= 0:
		return false
	return save_slot(AUTOSAVE_SLOT)


func current_play_time_ms() -> float:
	return _play_time_base_ms + maxf(0.0, Time.get_ticks_msec() - _play_started_ms)


func _capture_live_player() -> void:
	if location_provider.is_valid():
		var state: Variant = location_provider.call()
		if state is Dictionary and not (state as Dictionary).is_empty():
			capture_player(str(state.get("map_id", location.get("map_id", ""))), state)


func _slot_path(slot: int) -> String:
	return save_root.path_join("%s%d.json" % [SLOT_PREFIX, slot])


## JSON numbers come back as floats: whole ones become ints again (counts, coins, HP, cells).
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.one_shot = true
	_autosave_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_autosave_timer.timeout.connect(write_recovery)
	add_child(_autosave_timer)
	for changed: Signal in [inventory_changed, world_progress_changed, coins_changed, story_flag_changed, ability_learned,
			weapon_loadout_changed, weapon_equipped, recipes_learned, quests_changed]:
		changed.connect(func(_payload: Dictionary) -> void: schedule_autosave())
	_install_save_slots.call_deferred()


## The save slots window joins the Shell (once every autoload is ready) and takes over its "save"
## and "load" actions (game/saves/save_slots_menu.gd).
func _install_save_slots() -> void:
	SaveSlotsMenu.install(Services.shell())


## Window close (Phaser `pagehide`): the autosave is written at once.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		write_recovery()
