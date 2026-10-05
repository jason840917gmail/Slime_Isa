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
## - `location` [GameLocationData], `play_time_ms`; quests stay empty until the quest phase.
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

var player: Dictionary = {}
var inventory: Dictionary = {}
var world: Dictionary = {}
var story: Dictionary = {}
var location: Dictionary = {}
var quests: Array = []
var play_time_ms: float = 0.0
## True after `new_run()` or a load; main.gd starts a new run on its first boot otherwise.
var started: bool = false

## The pending area handoff [RunNavigationHandoff]: {"kind": "area"|"load"|"reset", "map_id",
## "entry_edge"?, "entry_door"?, "respawn_home"?}. Empty when none.
var _navigation: Dictionary = {}


## Phaser `createInitialRunState()` (content/initial-state/InitialRun.ts).
func new_run() -> void:
	var constants := Services.constants()
	var max_hp := _constant_int(constants, "character.player.stats.maxHp")
	var max_energy := _constant_int(constants, "character.player.stats.maxEnergy")
	var attributes: Dictionary = constants.dictionary("character.player.initialAttributes").duplicate(true) if constants != null else {}
	var weapon_slots: Array = []
	weapon_slots.resize(WEAPON_SLOT_COUNT)
	player = {
		"coins": NEW_RUN_COINS,
		"boost_bonus": 0,
		"hp": max_hp,
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
	play_time_ms = 0.0
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
## `state` = {"hp": int, "facing": "up"|"down"|"left"|"right", "x": float, "y": float} with x/y
## the old Phaser (centre) position.
func capture_player(map_id: String, state: Dictionary) -> void:
	if state.has("hp"):
		player["hp"] = clampi(int(state["hp"]), 0, max_hp())
	location = {
		"area_id": map_id,
		"map_id": map_id,
		"x": float(state.get("x", 0.0)),
		"y": float(state.get("y", 0.0)),
		"facing": str(state.get("facing", "down")),
	}


# --- inventory --------------------------------------------------------------------------------

## How many of `item_id` the bag holds (PlayerInventory.count).
func item_count(item_id: String) -> int:
	var total := 0
	for slot: Dictionary in inventory.get("slots", []):
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


## Takes `count` of `item_id` out of the bag, emptiest slots last; false (and nothing taken)
## when the bag holds fewer.
func remove_item(item_id: String, count: int) -> bool:
	if count <= 0:
		return true
	if item_count(item_id) < count:
		return false
	var slots: Array = inventory.get("slots", [])
	var left := count
	for index in range(slots.size() - 1, -1, -1):
		var slot: Dictionary = slots[index]
		if str(slot.get("item_id", "")) != item_id:
			continue
		var taken := mini(left, int(slot["count"]))
		slot["count"] = int(slot["count"]) - taken
		left -= taken
		if int(slot["count"]) <= 0:
			slots.remove_at(index)
		if left == 0:
			break
	return true


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


func has_learned_ability(ability_id: String) -> bool:
	return ability_id in _story_list("learned_ability_ids")


## Returns false when it was already learned.
func learn_ability(ability_id: String) -> bool:
	if ability_id.is_empty() or has_learned_ability(ability_id):
		return false
	_story_list("learned_ability_ids").append(ability_id)
	ability_learned.emit({"ability_id": ability_id})
	return true


# --- world progress ---------------------------------------------------------------------------

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
