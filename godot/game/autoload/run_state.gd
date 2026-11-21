extends Node
## Autoload `RunState`: everything about the current run that outlives one world, shaped like
## Phaser's `GameSaveData` (infrastructure/persistence/SaveSchema.ts, schema v10) so the save
## phase can write it to user:// as is. Phaser keeps this state in GameState, the inventory, the
## world-progress and story stores, and hands it to the next area through a session-storage save
## (RunNavigationStore.ts); here it simply stays in this autoload while main.gd swaps worlds.
##
## Sections (snake_case keys; Phaser's camelCase names in brackets):
## - `player` [GameStateData]: coins, boost_bonus, hp, energy, heart_quarters, full_hearts, attributes, equipment
##   {weapon_id, weapon_slots}; and (Godot, 2026-11-20) belt {open, kinds}: the potion belt (the
##   slots found and the potion kind each is set to; see "potion belt" below). The player script
##   owns live HP; main.gd copies it in and out at world boundaries (`capture_player` / spawn).
## - `inventory` [InventorySaveData]: max_slots, slots [{item_id, count}].
## - `world` [WorldProgressData]: discovered_areas, defeated_boss_ids, completed_dungeon_ids,
##   maps {map_id: map record}, respawn_point.
## - `story` [StorySaveData]: world_flags, learned_recipe_ids, learned_ability_ids, talked_npc_ids;
##   and (Godot) celebrated_item_ids: the permanent items whose ceremony has played; skin_ids and
##   skin_look: the skins won from the Pearls and the everyday look (docs/godot/SKINS.md); tips: the
##   ids of the tips NPCs gave, in the order heard (quests spec 14.4; a save from before 2026-11-19
##   has none and loads with none heard); war_pages: the war-journal pages found (their item ids, in
##   the order found; a save from before 2026-11-20 has none: see "finds" below).
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
## The prologue cannot be saved (question 113): `saving_blocked_reason` asks it.
const PrologueState := preload("res://game/prologue/prologue_state.gd")
## Nor can a dungeon (question 109): the slime resumes at its entrance (docs/godot/DUNGEONS.md).
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

## InitialRun.ts:16 (a literal there too).
const NEW_RUN_COINS := 50
## InitialRun.ts: the run starts in level-1.
const INITIAL_MAP_ID := "level-1"
## WEAPON_HOTBAR_SLOT_COUNT (core/types.ts:17).
const WEAPON_SLOT_COUNT := 4
## Placed-furniture record ids: "placed-furniture-<n>" (WorldProgress.ts:481-509).
const PLACED_FURNITURE_PREFIX := "placed-furniture-"

## A story flag was set (or cleared). Payload: {"flag": String, "set": bool}.
signal story_flag_changed(payload: Dictionary)
## An ability was learned. Payload: {"ability_id": String}.
signal ability_learned(payload: Dictionary)
## An NPC's tip was heard for the first time (`hear_tip`). Payload: {"tip_id": String}.
signal tip_heard(payload: Dictionary)
## A skin was won or lent, or the everyday look changed (docs/godot/SKINS.md). Payload:
## {"skin_id": String, "reason": "won" | "lent" | "look"}.
signal skins_changed(payload: Dictionary)
## A permanent item (a weapon or tool, a key: PERMANENT_ITEM_CATEGORIES) came into the bag for the
## first time in the run, outside a quiet grant: its ceremony plays (game/ui/ceremony/). Payload:
## {"item_id": String}.
signal permanent_item_gained(payload: Dictionary)
## The bag changed (Phaser `inventory.changed`). Payload: {}.
signal inventory_changed(payload: Dictionary)
## A world-object record changed (Phaser `world.progress.changed`). Payload: {"map_id": String}.
signal world_progress_changed(payload: Dictionary)
## Coins changed (GameState.addCoins / spendCoins). Payload: {"coins": int, "delta": int}.
signal coins_changed(payload: Dictionary)
## The weapon belt changed (Phaser `weapon.loadout.changed`). Payload: {"slots": Array}.
signal weapon_loadout_changed(payload: Dictionary)
## The potion belt changed: a slot opened (a `belt-slot` found or bought) or a slot's potion kind was
## set. Payload: {"open": int, "kinds": Array[String] (one per slot, "" for none), "opened": int (the
## index of the slot that just opened, -1 for a kind change or a load), "quiet": bool (a quiet grant
## or a load: no ceremony)}.
signal potion_belt_changed(payload: Dictionary)
## A page came in (a war-journal page or a recipe page: section "finds"); its reading panel opens
## unless `quiet` (game/ui/screens/page_window.gd). Payload: {"item_id": String, "quiet": bool}.
signal page_found(payload: Dictionary)
## A fragment came in (section "finds": the Roll fragments, owner 2026-11-20). Payload: {"item_id": String,
## "count": int (found so far, this one included), "total": int, "quiet": bool}; the last one teaches its
## ability (`ability_learned` and its card).
signal fragment_found(payload: Dictionary)
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
## Where the player's saves live.
const PLAYER_SAVE_ROOT := "user://saves"
## Where saves live; the test runner points it at a scratch folder.
var save_root: String = PLAYER_SAVE_ROOT
## Where a headless or windowed tool run from `res://tools/` (renders, bakes, labs) saves, so its
## autosave never overwrites the player's real slots (2026-11-20: render runs had overwritten slot 0).
const TOOL_SAVE_ROOT := "user://tool-saves"
const TOOLS_DIR := "res://tools/"
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
## True from `new_run()` until main.gd's first world build of the run hands out the start kit
## (nothing in Phaser; `start_weapon_id` or the `weapon` launch option). A loaded run never has it.
var start_kit_pending: bool = false
## Dev and tests: a weapon put in the bag, on belt slot 1 and in hand at a new run's first world
## build ("" = none, Phaser: a run starts empty-handed). The test runner sets "basic-sword".
var start_weapon_id: String = ""
## Grants that are no news (a dev or test start weapon, the playground's kit, `?arsenal`) set this
## around their adds: a permanent item they give counts as celebrated without a ceremony.
var quiet_items: bool = false
## Abilities lent for this session only (the body-shapes rework mode's quiet grants, main.gd
## `start_rework` through `learn_session_ability`): learned while the run plays, but `serialize`
## leaves them out, so no save (the autosave or a save made by hand) carries them into a classic
## game. A real lesson of one (`learn_ability` without `quiet`) keeps it for good. `new_run` and
## `install` forget the list. Empty outside the rework mode.
var session_ability_ids: Array[String] = []
## Skins lent for this session only (the F6 dev powers, the playground's Skins corner:
## `lend_skin`): on while the run plays, but `serialize` leaves them out. Winning one for real
## (`win_skin`) keeps it. `new_run` and `install` forget the list.
var session_skin_ids: Array[String] = []
## Dungeon facts that last while the run plays but are never saved (game/dungeon/dungeon_state.gd
## `session`: a plate held down in a room the slime left, the next far-off roar). `new_run` and
## `install` forget them.
var dungeon_session: Dictionary = {}

## Item categories that are permanent things, celebrated once when first gained (roadmap 4.13).
const PERMANENT_ITEM_CATEGORIES: Array[String] = ["weapon", "key"]
const CELEBRATED_ITEMS := "celebrated_item_ids"
## game-constants.json: boss id -> the story flag his fall sets (`record_boss_defeated`).
const BOSS_FLAGS_PATH := "story.bossFlags"
## [map id, gate id] of the Lair's outer gate, which the removed gatehouse winch held up for good:
## a loaded save forgets it (`install`).
const OBSOLETE_HELD_GATE: Array[String] = ["level-1-d5", "fatty-lair-gate"]
## The Roll (ability `dodge`): young Burr teaches it since 2026-11-19 (until then it was free from
## birth). A save already past Burr's cell in Fatty's Lair, or holding any Pearl flag (`pearl.<id>`,
## `pearl.<id>.home`), learns it quietly on load (`install`).
const ROLL_ID := "dodge"
const ROLL_KNOWN_FLAG := "fatty-lair.burr-freed"
## Burr's Roll fragment, given as he is freed in Fatty's Lair (game/fattys_lair/lair_director.gd
## FLAG_FRAGMENT, owner 2026-11-20); a run freed him before that gets it quietly on load (`install`).
const BURR_FRAGMENT_FLAG := "fatty-lair.burr-fragment"
## Pearl 2 home raises Slimeshire's Workshop since 2026-11-20 (it lit the Forge before): `install`.
const MATRON_PEARL_HOME_FLAG := "pearl.orb-weaver-matron.home"
const WORKSHOP_FLAG := "workshop.restored"
const ROLL_FRAGMENT_ID := "roll-fragment"
const ROLL_CHARGE_ID := "roll-charge"
const PEARL_FLAG_PREFIX := "pearl."
## The Verdant Gate (its gate id, in any map's `unlocked_gate_ids`) gave way to a fallen tree that a
## Heavy Roll smashes (2026-11-19, question 163): a save that had the gate open has the tree smashed
## (`install`).
const VERDANT_GATE_ID := "level-1-east-verdant-gate"
const VERDANT_TREE_FLAG := "level-1.verdant-tree-smashed"

## The pending area handoff [RunNavigationHandoff]: {"kind": "area"|"load"|"reset", "map_id",
## "entry_edge"?, "entry_door"?, "entry_marker"?, "respawn_home"?}. Empty when none. Never saved:
## a loaded save queues a fresh "load" handoff.
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
		"heart_quarters": 0,
		"attributes": attributes,
		"equipment": {"weapon_id": null, "weapon_slots": weapon_slots},
		BELT_KEY: _empty_belt(),
	}
	inventory = {"max_slots": _constant_int(constants, "inventory.initialMaxSlots"), "slots": []}
	world = {
		"discovered_areas": [INITIAL_MAP_ID],
		"defeated_boss_ids": [],
		"completed_dungeon_ids": [],
		"maps": {},
		"respawn_point": {},
	}
	story = {"world_flags": [], "learned_recipe_ids": [], "learned_ability_ids": [], "talked_npc_ids": [], TIPS_KEY: [], WAR_PAGES_KEY: []}
	location = {"area_id": INITIAL_MAP_ID, "map_id": INITIAL_MAP_ID, "x": 0.0, "y": 0.0, "facing": "down"}
	quests = []
	_play_time_base_ms = 0.0
	_play_started_ms = Time.get_ticks_msec()
	debug_active_quests = []
	debug_all_recipes_known = false
	session_ability_ids = []
	session_skin_ids = []
	dungeon_session = {}
	start_kit_pending = true
	_navigation = {}
	started = true


## Starts a new run if none is in progress (first boot, or a test that cleared it).
func ensure_started() -> void:
	if not started:
		new_run()


# --- player -----------------------------------------------------------------------------------

## Max HP (roadmap 5.3, owner 2026-10-26): `stats.maxHp`, plus `heartQuarter.heartMaxHpBonus` (20)
## per whole heart made of quarters (`heartQuarter.perHeart`, 4; a quarter alone adds nothing), plus
## `fullHeart.maxHpBonus` (20) per boss's full heart (question 17; only a beaten boss gives one).
func max_hp() -> int:
	var constants := Services.constants()
	return _constant_int(constants, "character.player.stats.maxHp") \
			+ quarter_hearts() * _constant_int(constants, "character.player.heartQuarter.heartMaxHpBonus") \
			+ int(player.get("full_hearts", 0)) * _constant_int(constants, "character.player.fullHeart.maxHpBonus")


## Heart quarters found this run (`player.heart_quarters`).
func heart_quarters() -> int:
	return int(player.get("heart_quarters", 0))


## How many quarters make a whole heart (`heartQuarter.perHeart`, 4).
func quarters_per_heart() -> int:
	return maxi(1, _constant_int(Services.constants(), "character.player.heartQuarter.perHeart"))


## The whole hearts the quarters found make.
func quarter_hearts() -> int:
	return heart_quarters() / quarters_per_heart()


## The quarters found toward the next heart (0 .. perHeart - 1: 0 right after one completed a heart).
func heart_quarters_toward_next() -> int:
	return heart_quarters() % quarters_per_heart()


## How full the next heart is once `count` more quarters are found: 1 .. perHeart, perHeart when the
## last of them completes it (with `count` 0, the level the last quarter found reached); 0 with none
## found and none to come. A quarter's picture shows it (goo_heart.gd).
func heart_level_after(count: int = 0) -> int:
	var total := heart_quarters() + maxi(0, count)
	if total == 0:
		return 0
	var level := total % quarters_per_heart()
	return quarters_per_heart() if level == 0 else level


## Max energy: `stats.maxEnergy` plus `player.max_energy_bonus` (the raises a beaten boss gives,
## question 19; Godot, 2026-10-17).
func max_energy() -> int:
	return _constant_int(Services.constants(), "character.player.stats.maxEnergy") + int(player.get("max_energy_bonus", 0))


## Copies the live player's state into `player` and `location` (before a world is left).
## `state` = {"hp": int, "energy": float, "facing": "up"|"down"|"left"|"right", "x": float,
## "y": float} with x/y the old Phaser (centre) position.
func capture_player(map_id: String, state: Dictionary) -> void:
	if state.has("hp"):
		player["hp"] = clampi(int(state["hp"]), 0, max_hp())
	if state.has("energy"):
		player["energy"] = float(state["energy"])
	# The Gulp form and what the mouth holds (owner, 2026-10-08) go through doors and saves.
	if state.has("gulp_form"):
		player["gulp_form"] = str(state["gulp_form"])
	if state.has("held"):
		player["held"] = (state["held"] as Dictionary).duplicate() if state["held"] is Dictionary else {}
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


## GameState.addCoins: `max(0, coins + amount)`; nothing for 0. A gain plays the `Coin` cue
## (Phaser's AudioEventBridge played it on `coins.changed` with a positive delta).
func add_coins(amount: int) -> void:
	if amount == 0:
		return
	player["coins"] = maxi(0, coins() + amount)
	coins_changed.emit({"coins": coins(), "delta": amount})
	var feel := Services.feel()
	if amount > 0 and feel != null:
		feel.audio_cue(&"Coin")


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
## max stack plus a full stack per free slot; 0 for unknown items. A `belt` item (the belt slot)
## never takes a bag slot: as many fit as the potion belt has slots still closed. A find (a page or
## an upgrade: `is_find_item`) never takes one either: it always fits.
func item_capacity(item_id: String) -> int:
	if is_belt_item(item_id):
		return POTION_BELT_SLOTS - potion_belt_open()
	if is_find_item(item_id):
		return FIND_CAPACITY
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


## True when `item_id` is a permanent thing (a weapon or tool, a key).
static func is_permanent_item(item_id: String) -> bool:
	return str(ItemCatalog.definition(item_id).get("category", "")) in PERMANENT_ITEM_CATEGORIES


## True once `item_id`'s ceremony has played (or a quiet grant or an old save counted it).
func is_item_celebrated(item_id: String) -> bool:
	return item_id in _story_list(CELEBRATED_ITEMS)


## A permanent item seen for the first time: remembered, and announced unless the grant is quiet.
## Every way into the bag comes here: `_insert` (adds, world pickups, chest stacks) and crafting's
## `transact_items`.
func _note_permanent(item_id: String) -> void:
	if not is_permanent_item(item_id) or is_item_celebrated(item_id):
		return
	_story_list(CELEBRATED_ITEMS).append(item_id)
	if not quiet_items:
		permanent_item_gained.emit({"item_id": item_id})


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
	# A belt slot is used up as it comes: it opens one more slot of the potion belt.
	if is_belt_item(item_id):
		for _i in count:
			open_potion_belt_slot()
		return
	# A find (a page, an upgrade) is used up as it comes too.
	if is_find_item(item_id):
		_use_find(item_id)
		return
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
	if left < count:
		_note_permanent(item_id)


## `Inventory.transact` (crafting spec 2.5): all or nothing, one `inventory_changed`. Removals
## (summed per item, first-seen order) come out of the first matching slot onward; emptied slots
## are dropped; then additions (summed) fill that item's stacks below the max stack in slot order
## and append new stacks while slots are free. `removals` / `additions`: [{"item_id", "count"}]
## with counts > 0. False (nothing changed) when anything is missing, unknown or does not fit.
## `preview` (Inventory.previewTransact) only answers. A `belt` item added (Dollop's belt slot) takes
## no bag slot: it fits while the potion belt has slots closed, and opens them when it is committed.
## A find added (a page, an upgrade) always fits and is used when it is committed.
func transact_items(removals: Array, additions: Array, preview: bool = false) -> bool:
	var taken := _summed(removals)
	var given := _summed(additions)
	if taken.is_empty() and given.is_empty() and (not removals.is_empty() or not additions.is_empty()):
		return false
	var belt_slots := 0
	var finds: Array[String] = []
	for item_id: String in given.keys():
		if is_belt_item(item_id):
			belt_slots += int(given[item_id])
			given.erase(item_id)
		elif is_find_item(item_id):
			finds.append(item_id)
			given.erase(item_id)
	if belt_slots > POTION_BELT_SLOTS - potion_belt_open():
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
	for item_id: String in given:
		_note_permanent(item_id)
	for _i in belt_slots:
		open_potion_belt_slot()
	for item_id in finds:
		_use_find(item_id)
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


# --- potion belt (crafting spec 12.4; owner, 2026-11-19, question 161) ---------------------------
## `player.belt` = {"open": the slots found (0 .. POTION_BELT_SLOTS), "kinds": the potion kind each
## slot is set to ("" for none), POTION_BELT_SLOTS entries}. A slot keeps its kind when the stack
## runs out. Every way an item of category `belt` (the `belt-slot`) comes in (`add_item`, a pickup,
## a chest, `transact_items`: Dollop's shop) opens one more slot instead of filling a bag slot.
## The rules of what a slot takes and of drinking are game/inventory/potion_belt.gd's.

## One slot per input action `potion_1` .. `potion_4` (keys 1 to 4 in project.godot).
const POTION_BELT_SLOTS := 4
const BELT_KEY := "belt"
const BELT_ITEM_CATEGORY := "belt"


## True for an item that opens a belt slot instead of going into the bag (category `belt`).
static func is_belt_item(item_id: String) -> bool:
	return str(ItemCatalog.definition(item_id).get("category", "")) == BELT_ITEM_CATEGORY


## How many belt slots the slime has found (0 .. POTION_BELT_SLOTS).
func potion_belt_open() -> int:
	return clampi(int(_belt().get("open", 0)), 0, POTION_BELT_SLOTS)


## Each slot's potion kind ("" for none), POTION_BELT_SLOTS entries (closed slots have none).
func potion_belt_kinds() -> Array[String]:
	var raw: Variant = _belt().get("kinds", [])
	var out: Array[String] = []
	for index in POTION_BELT_SLOTS:
		var entry: Variant = (raw as Array)[index] if raw is Array and index < (raw as Array).size() else ""
		out.append(str(entry) if entry is String and index < potion_belt_open() else "")
	return out


## The potion kind slot `index` is set to ("" for none, or a closed slot).
func potion_belt_kind(index: int) -> String:
	var kinds := potion_belt_kinds()
	return kinds[index] if index >= 0 and index < kinds.size() else ""


## Opens one more belt slot (emits `potion_belt_changed` with its index); false when all are open.
func open_potion_belt_slot() -> bool:
	var open := potion_belt_open()
	if open >= POTION_BELT_SLOTS:
		return false
	_belt()["open"] = open + 1
	_emit_potion_belt(open)
	return true


## Sets the open slot `index` to the potion kind `kind` ("" empties it); a kind already on another
## slot moves from there (the owner: one kind per slot). False when nothing changed or the slot is
## not open.
func set_potion_belt_kind(index: int, kind: String) -> bool:
	if index < 0 or index >= potion_belt_open():
		return false
	var kinds := potion_belt_kinds()
	if kinds[index] == kind:
		return false
	if not kind.is_empty():
		for other in kinds.size():
			if kinds[other] == kind:
				kinds[other] = ""
	kinds[index] = kind
	var plain: Array = []
	plain.assign(kinds)
	_belt()["kinds"] = plain
	_emit_potion_belt(-1)
	return true


## `player.belt`, made empty when the run has none (a new run, a save from before 2026-11-20).
func _belt() -> Dictionary:
	var belt: Variant = player.get(BELT_KEY)
	if not belt is Dictionary:
		belt = _empty_belt()
		player[BELT_KEY] = belt
	return belt


static func _empty_belt() -> Dictionary:
	var kinds: Array = []
	for _i in POTION_BELT_SLOTS:
		kinds.append("")
	return {"open": 0, "kinds": kinds}


func _emit_potion_belt(opened: int, quiet: bool = false) -> void:
	potion_belt_changed.emit({"open": potion_belt_open(), "kinds": potion_belt_kinds(), "opened": opened,
		"quiet": quiet or quiet_items})


# --- finds: pages and upgrades (B4, B6; 2026-11-20) -----------------------------------------------
## Items used up as they come in, like the belt slot (every way in: `add_item`, a pickup, a chest,
## `transact_items`), never a bag slot:
## - a **war-journal page** (category `page`, items.json `page`: {number, title, lines}): kept in
##   `story.war_pages` (item ids, in the order found; the journal's War journal section lists them),
##   and `page_found` opens its reading panel (game/ui/screens/page_window.gd);
## - a **recipe page** (category `recipe-page`: `teachesRecipes`, `page`): its recipes are learned
##   (`learn_recipes`) and `page_found` opens its panel too;
## - an **upgrade** (category `upgrade`: `teachesAbility`): learned (`learn_ability`, quiet under
##   `quiet_items`), whose card QuestNotifications plays (AbilityDefinitions.UPGRADES: the Charged
##   Roll, `roll-charge`; its whole `charged-roll` find is now only for tools and tests);
## - a **fragment** (category `fragment`: `fragmentsNeeded`, `teachesAbility`): counted in
##   `story.fragments` ({item id: found}); `fragment_found` says so (QuestNotifications' toast), and the
##   last of them teaches the ability, with its card (owner, 2026-11-20: four `roll-fragment`s make the
##   Charged Roll: Burr's in Fatty's Lair, Yoi's chest, one in Glimmerhill, one in Gloop Forest).
## The war-journal pages and helpers to read them: game/quests/war_journal.gd.

const PAGE_CATEGORY := "page"
const RECIPE_PAGE_CATEGORY := "recipe-page"
const UPGRADE_CATEGORY := "upgrade"
const FRAGMENT_CATEGORY := "fragment"
const FIND_CATEGORIES: Array[String] = [PAGE_CATEGORY, RECIPE_PAGE_CATEGORY, UPGRADE_CATEGORY, FRAGMENT_CATEGORY]
const WAR_PAGES_KEY := "war_pages"
const FRAGMENTS_KEY := "fragments"
## How many of a find fit at once (any number: each is used as it comes).
const FIND_CAPACITY := 99


## True for an item used up as it comes in (a page, a recipe page, an upgrade).
static func is_find_item(item_id: String) -> bool:
	return str(ItemCatalog.definition(item_id).get("category", "")) in FIND_CATEGORIES


## How many of the fragment `item_id` are found (`story.fragments`).
func fragment_count(item_id: String) -> int:
	var found: Variant = story.get(FRAGMENTS_KEY, {})
	return int((found as Dictionary).get(item_id, 0)) if found is Dictionary else 0


## How many of the fragment `item_id` make the whole (its `fragmentsNeeded`, at least 1).
static func fragments_needed(item_id: String) -> int:
	return maxi(1, int(ItemCatalog.definition(item_id).get("fragmentsNeeded", 1)))


## True once the war-journal page `item_id` is found.
func has_war_page(item_id: String) -> bool:
	return item_id in _story_list(WAR_PAGES_KEY)


## The war-journal pages found (item ids), in the order found.
func war_page_ids() -> Array[String]:
	var out: Array[String] = []
	for page_id: Variant in _story_list(WAR_PAGES_KEY):
		out.append(str(page_id))
	return out


## Uses the find `item_id` as it comes in (see above).
func _use_find(item_id: String) -> void:
	var definition := ItemCatalog.definition(item_id)
	match str(definition.get("category", "")):
		PAGE_CATEGORY:
			if not has_war_page(item_id):
				_story_list(WAR_PAGES_KEY).append(item_id)
			page_found.emit({"item_id": item_id, "quiet": quiet_items})
		RECIPE_PAGE_CATEGORY:
			var recipes: Variant = definition.get("teachesRecipes", [])
			if recipes is Array:
				learn_recipes(recipes)
			page_found.emit({"item_id": item_id, "quiet": quiet_items})
		UPGRADE_CATEGORY:
			learn_ability(str(definition.get("teachesAbility", "")), quiet_items)
		FRAGMENT_CATEGORY:
			var found: Dictionary = story.get_or_add(FRAGMENTS_KEY, {})
			var count := int(found.get(item_id, 0)) + 1
			found[item_id] = count
			var total := fragments_needed(item_id)
			fragment_found.emit({"item_id": item_id, "count": count, "total": total, "quiet": quiet_items})
			if count >= total:
				learn_ability(str(definition.get("teachesAbility", "")), quiet_items)


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


## The tips heard from NPCs (`story.tips`: ids in the order heard; the texts live with the NPC's
## talks in npc-definitions.json, quests spec 14.4).
const TIPS_KEY := "tips"


## Remembers the tip `tip_id` as heard (the journal lists it). False when it already was.
func hear_tip(tip_id: String) -> bool:
	if tip_id.is_empty() or has_heard_tip(tip_id):
		return false
	_story_list(TIPS_KEY).append(tip_id)
	tip_heard.emit({"tip_id": tip_id})
	return true


func has_heard_tip(tip_id: String) -> bool:
	return tip_id in _story_list(TIPS_KEY)


## The heard tips' ids, oldest first.
func heard_tip_ids() -> Array[String]:
	var out: Array[String] = []
	for tip_id: Variant in _story_list(TIPS_KEY):
		out.append(str(tip_id))
	return out


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


## Returns false when it was already learned (except a lesson, not `quiet`, of one only lent for the
## session: `session_ability_ids`). `quiet` skips `ability_learned` (no banner; the playground's
## kit).
func learn_ability(ability_id: String, quiet := false) -> bool:
	if ability_id.is_empty():
		return false
	if has_learned_ability(ability_id):
		# Rework mode: a real lesson of an ability only lent for the session keeps it (saved from now
		# on) and is announced as any lesson. With nothing lent (classic) this never runs.
		if not quiet and session_ability_ids.has(ability_id):
			session_ability_ids.erase(ability_id)
			ability_learned.emit({"ability_id": ability_id})
			return true
		return false
	_story_list("learned_ability_ids").append(ability_id)
	if not quiet:
		ability_learned.emit({"ability_id": ability_id})
	return true


## Rework mode (main.gd `start_rework`): learns `ability_id` quietly for this session only (it is
## left out of every save, `session_ability_ids`). False when it was already learned (then it stays
## as it was: a real lesson stays saved).
func learn_session_ability(ability_id: String) -> bool:
	if not learn_ability(ability_id, true):
		return false
	session_ability_ids.append(ability_id)
	return true


# --- skins (docs/godot/SKINS.md; read through game/player/skins/skin_state.gd) -------------------
## `story.skin_ids`: the skins won (the Pearls), each always on once won (Direction "The skins");
## `story.skin_look`: the won skin the player picked as the everyday look in the bag ("" = the
## slime's own goo). Lent skins (`session_skin_ids`) count as won until the session ends.

## Before roadmap 7.8 the Pearls set a story flag per skin ("skin.heavy"); `install` wins those.
const LEGACY_SKIN_FLAG_PREFIX := "skin."
const SKIN_IDS_KEY := "skin_ids"
const SKIN_LOOK_KEY := "skin_look"


## True once `skin_id` is won (or lent for the session).
func has_skin(skin_id: String) -> bool:
	return not skin_id.is_empty() and skin_id in _story_list(SKIN_IDS_KEY)


## The skins won or lent, in the order they came.
func skin_ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in _story_list(SKIN_IDS_KEY):
		out.append(str(id))
	return out


## Wins `skin_id` for good (a Pearl). False when it was already won; a skin only lent for the
## session is won from now on (true).
func win_skin(skin_id: String) -> bool:
	if skin_id.is_empty():
		return false
	if has_skin(skin_id):
		if not session_skin_ids.has(skin_id):
			return false
		session_skin_ids.erase(skin_id)
	else:
		_story_list(SKIN_IDS_KEY).append(skin_id)
	skins_changed.emit({"skin_id": skin_id, "reason": "won"})
	return true


## Lends `skin_id` for this session only (the F6 dev powers, the Skins corner): left out of every
## save. False when it is already won or lent.
func lend_skin(skin_id: String) -> bool:
	if skin_id.is_empty() or has_skin(skin_id):
		return false
	_story_list(SKIN_IDS_KEY).append(skin_id)
	session_skin_ids.append(skin_id)
	skins_changed.emit({"skin_id": skin_id, "reason": "lent"})
	return true


## Takes a lent skin back (the Skins corner's pedestals). False for a won skin or one not lent.
func return_skin(skin_id: String) -> bool:
	if not session_skin_ids.has(skin_id):
		return false
	session_skin_ids.erase(skin_id)
	_story_list(SKIN_IDS_KEY).erase(skin_id)
	if skin_look() == skin_id:
		story[SKIN_LOOK_KEY] = ""
	skins_changed.emit({"skin_id": skin_id, "reason": "returned"})
	return true


## The everyday look: a won skin's id, or "" (the slime's own goo).
func skin_look() -> String:
	var look := str(story.get(SKIN_LOOK_KEY, ""))
	return look if look.is_empty() or has_skin(look) else ""


## Picks the everyday look ("" = the goo). False when `skin_id` is not won or is already the look.
func set_skin_look(skin_id: String) -> bool:
	if not skin_id.is_empty() and not has_skin(skin_id):
		return false
	if skin_look() == skin_id:
		return false
	story[SKIN_LOOK_KEY] = skin_id
	skins_changed.emit({"skin_id": skin_id, "reason": "look"})
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


## One more heart quarter; true when it completes a heart (max HP grows and HP fills). The one place
## that says so: the pickup, the chest and the ceremony take this answer (goo_heart.gd `grant`).
func add_heart_quarter() -> bool:
	player["heart_quarters"] = heart_quarters() + 1
	var completed := heart_quarters_toward_next() == 0
	if completed:
		player["hp"] = max_hp()
	return completed


## One more full heart (a boss's, question 17): max HP grows by `fullHeart.maxHpBonus`; HP fills.
func add_full_heart() -> void:
	player["full_hearts"] = int(player.get("full_hearts", 0)) + 1
	player["hp"] = max_hp()


## Max energy grows by `amount` for the rest of the run (question 19); energy fills.
func add_max_energy(amount: int) -> void:
	player["max_energy_bonus"] = int(player.get("max_energy_bonus", 0)) + maxi(0, amount)
	player["energy"] = float(max_energy())


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


## The one place a boss's fall is recorded (the boss camps, the Colossus's arena, the dungeons' room
## fights and the quest service call it): his id joins `world.defeated_boss_ids` once, and the story
## flag `story.bossFlags` in game-constants.json names for him is set (`chapter-1-complete` for
## Fatty One Eye, `chapter-2-complete` for the Matron, `chapter-3-complete` for the Crystal
## Colossus: quests spec 14.6). The flag is set even when the id was already there. False when he
## was already beaten.
func record_boss_defeated(boss_id: String) -> bool:
	if boss_id.is_empty():
		return false
	var defeated: Array = world.get_or_add("defeated_boss_ids", [])
	var first := not boss_id in defeated
	if first:
		defeated.append(boss_id)
	var flag := boss_flag(boss_id)
	if not flag.is_empty():
		set_flag(flag)
	return first


## The story flag a boss's fall sets (`story.bossFlags`), "" when none.
static func boss_flag(boss_id: String) -> String:
	var constants := Services.constants()
	var flags: Variant = constants.value(BOSS_FLAGS_PATH, {}) if constants != null else {}
	return str((flags as Dictionary).get(boss_id, "")) if flags is Dictionary else ""


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


## Copies of the map's placed-furniture records ({"id", "item_id", "scene_id", "x", "y"}), in
## placement order (WorldProgress.placedFurniture; furniture spec 6.3).
func placed_furniture(map_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record: Variant in (map_record(map_id).get_or_add("placed_furniture", {}) as Dictionary).values():
		if record is Dictionary:
			out.append((record as Dictionary).duplicate())
	return out


## `WorldProgress.placeFurniture`: records the furniture as "placed-furniture-<n>", n = max(the
## map's sequence, 1 + the highest numeric id); the sequence becomes n + 1 and never goes down.
## Returns a copy of the record.
func place_furniture(map_id: String, item_id: String, scene_id: String, x: float, y: float) -> Dictionary:
	var record_map := map_record(map_id)
	var placed: Dictionary = record_map.get_or_add("placed_furniture", {})
	var sequence := maxi(1, int(record_map.get("next_placed_furniture_sequence", 1)))
	for id: Variant in placed:
		var number := str(id).trim_prefix(PLACED_FURNITURE_PREFIX)
		if number.is_valid_int():
			sequence = maxi(sequence, int(number) + 1)
	var record := {"id": "%s%d" % [PLACED_FURNITURE_PREFIX, sequence], "item_id": item_id, "scene_id": scene_id,
		"x": x, "y": y}
	placed[record["id"]] = record
	record_map["next_placed_furniture_sequence"] = sequence + 1
	world_progress_changed.emit({"map_id": map_id})
	return record.duplicate()


## `WorldProgress.removePlacedFurniture`: the removed record (a copy), {} when there was none.
func remove_placed_furniture(map_id: String, placement_id: String) -> Dictionary:
	var placed: Dictionary = map_record(map_id).get_or_add("placed_furniture", {})
	if not placed.has(placement_id):
		return {}
	var record: Dictionary = (placed[placement_id] as Dictionary).duplicate()
	placed.erase(placement_id)
	world_progress_changed.emit({"map_id": map_id})
	return record


## Where the player wakes after defeat (the last bed slept in); {} when none.
func respawn_point() -> Dictionary:
	return world.get("respawn_point", {})


## `point` = {"area_id", "map_id", "x", "y", "bed_id"?} (old Phaser coordinates).
func set_respawn_point(point: Dictionary) -> void:
	world["respawn_point"] = point.duplicate()


## `WorldProgress.clearRespawnPoint` (a picked-up bed cannot be woken in).
func clear_respawn_point() -> void:
	world["respawn_point"] = {}


# --- navigation handoff -----------------------------------------------------------------------

## Queues the next world for main.gd (RunNavigationStore.writeRunNavigation). `entry_edge` is
## "north"|"east"|"south"|"west" or "", `entry_door` a door id in the target world or "",
## `entry_marker` the name of a Node2D in the target world or "" (a world exit's `entry_marker`;
## not in Phaser), `entry_along` where along `entry_edge` to arrive or NAN (a world exit's
## `keep_along`; not in Phaser).
func request_navigation(kind: String, map_id: String, entry_edge: String = "", entry_door: String = "", respawn_home: bool = false, entry_marker: String = "", entry_along: float = NAN) -> void:
	_navigation = {"kind": kind, "map_id": map_id}
	if not entry_edge.is_empty():
		_navigation["entry_edge"] = entry_edge
	if not entry_door.is_empty():
		_navigation["entry_door"] = entry_door
	if not entry_marker.is_empty():
		_navigation["entry_marker"] = entry_marker
	if not entry_edge.is_empty() and not is_nan(entry_along):
		_navigation["entry_along"] = entry_along
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

## The run as Phaser's GameSaveData (snake_case keys), ready for JSON. Abilities lent for the session
## (`session_ability_ids`, rework mode only) are left out of `story.learned_ability_ids`.
func serialize() -> Dictionary:
	_capture_live_player()
	var saved_story := story.duplicate(true)
	if not session_ability_ids.is_empty() and saved_story.get("learned_ability_ids") is Array:
		var kept: Array = []
		for ability_id: Variant in saved_story["learned_ability_ids"]:
			if not session_ability_ids.has(str(ability_id)):
				kept.append(ability_id)
		saved_story["learned_ability_ids"] = kept
	# Lent skins stay out too, and so does a look that is one of them.
	if not session_skin_ids.is_empty() and saved_story.get(SKIN_IDS_KEY) is Array:
		var won: Array = []
		for skin_id: Variant in saved_story[SKIN_IDS_KEY]:
			if not session_skin_ids.has(str(skin_id)):
				won.append(skin_id)
		saved_story[SKIN_IDS_KEY] = won
		if session_skin_ids.has(str(saved_story.get(SKIN_LOOK_KEY, ""))):
			saved_story[SKIN_LOOK_KEY] = ""
	return {
		"player": player.duplicate(true),
		"inventory": inventory.duplicate(true),
		"quests": quests.duplicate(true),
		"location": location.duplicate(true),
		"world": world.duplicate(true),
		"story": saved_story,
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
	dungeon_session = {}
	# Saves from before the heart quarters (2026-10-26): each Goo Heart taken (+10 max HP) is a quarter.
	if player.has("goo_hearts"):
		player["heart_quarters"] = heart_quarters() + int(player.get("goo_hearts", 0))
		player.erase("goo_hearts")
	# Saves from before 2026-10-24: the Lair gatehouse's inner winch held its outer gate up for good,
	# recorded as the gate unlocked. The winch is gone and the gate drops again each time.
	var maps: Variant = world.get("maps")
	var gate_map: Variant = (maps as Dictionary).get(OBSOLETE_HELD_GATE[0]) if maps is Dictionary else null
	if gate_map is Dictionary and (gate_map as Dictionary).get("unlocked_gate_ids") is Array:
		((gate_map as Dictionary)["unlocked_gate_ids"] as Array).erase(OBSOLETE_HELD_GATE[1])
	if int(player.get("hp", 0)) <= 0:
		player["hp"] = max_hp()
	player["hp"] = mini(int(player.get("hp", 0)), max_hp())
	world.get_or_add("maps", {})
	world.get_or_add("discovered_areas", [])
	_play_time_base_ms = float(fresh.get("play_time_ms", 0.0))
	_play_started_ms = Time.get_ticks_msec()
	_navigation = {}
	# The loaded run lends nothing yet (the rework mode lends again on the world build).
	session_ability_ids = []
	session_skin_ids = []
	# Saves from before roadmap 7.8: a Pearl's skin was a story flag ("skin.heavy").
	for flag: Variant in _flags():
		var flag_name := str(flag)
		var legacy := flag_name.trim_prefix(LEGACY_SKIN_FLAG_PREFIX)
		if flag_name.begins_with(LEGACY_SKIN_FLAG_PREFIX) and not has_skin(legacy):
			_story_list(SKIN_IDS_KEY).append(legacy)
	# Saves from before 2026-11-19: the chapter flags came from the retired chapter quests; now a
	# boss's fall sets his (`record_boss_defeated`). Set quietly here, so no end card opens.
	for boss_id: Variant in world.get("defeated_boss_ids", []):
		var boss_flag_id := boss_flag(str(boss_id))
		if not boss_flag_id.is_empty() and not has_flag(boss_flag_id):
			_flags().append(boss_flag_id)
	# Saves from before 2026-11-19: the Roll was free from birth. A run past Burr's cell or a Pearl
	# knows it already, so it is learned quietly (no ceremony); an earlier run learns it from his boy.
	if not has_learned_ability(ROLL_ID) and _past_the_roll_lesson():
		learn_ability(ROLL_ID, true)
	# Saves from before 2026-11-20 (Pip's Workshop): the Matron's Pearl home lit the Forge then; now it
	# raises the Workshop, which Pip's bow rune needs. Raised quietly (a Forge lit early stays lit).
	if has_flag(MATRON_PEARL_HOME_FLAG) and not has_flag(WORKSHOP_FLAG):
		_flags().append(WORKSHOP_FLAG)
	# Saves from before 2026-11-20: Burr was freed before he gave a Roll fragment. It is counted now,
	# quietly (no toast), unless the run already knows the Charged Roll.
	if has_flag(ROLL_KNOWN_FLAG) and not has_flag(BURR_FRAGMENT_FLAG) and not has_learned_ability(ROLL_CHARGE_ID):
		_flags().append(BURR_FRAGMENT_FLAG)
		var fragments: Dictionary = story.get_or_add(FRAGMENTS_KEY, {})
		fragments[ROLL_FRAGMENT_ID] = int(fragments.get(ROLL_FRAGMENT_ID, 0)) + 1
	# Saves from before 2026-11-19: the Verdant Gate is a fallen tree now; a gate opened is a tree
	# smashed (set quietly).
	if not has_flag(VERDANT_TREE_FLAG) and _verdant_gate_was_open():
		_flags().append(VERDANT_TREE_FLAG)
	# Saves from before 2026-11-20 have no potion belt (none open). A belt slot bought from Dollop
	# then sat in the bag: it leaves the bag and opens its slot now, quietly.
	var bag_slots: Array = []
	var found_belt_slots := 0
	for slot: Variant in inventory.get("slots", []):
		if slot is Dictionary and is_belt_item(str((slot as Dictionary).get("item_id", ""))):
			found_belt_slots += int((slot as Dictionary).get("count", 0))
		else:
			bag_slots.append(slot)
	if found_belt_slots > 0:
		inventory["slots"] = bag_slots
	var belt_kinds: Array = []
	belt_kinds.assign(potion_belt_kinds())
	_belt()["open"] = mini(POTION_BELT_SLOTS, potion_belt_open() + found_belt_slots)
	_belt()["kinds"] = belt_kinds
	start_kit_pending = false
	started = true
	# Saves from before the ceremony: what the bag already holds is no news.
	for slot: Variant in inventory.get("slots", []):
		var item_id := str((slot as Dictionary).get("item_id", "")) if slot is Dictionary else ""
		if is_permanent_item(item_id) and not is_item_celebrated(item_id):
			_story_list(CELEBRATED_ITEMS).append(item_id)
	# Views kept across worlds (the HUD belt and coins) follow the loaded run; the quest service
	# rebinds on its next call and reports it with `quest_changed`.
	inventory_changed.emit({})
	weapon_loadout_changed.emit({"slots": weapon_slots()})
	_emit_potion_belt(-1, true)
	coins_changed.emit({"coins": coins(), "delta": 0})
	return true


## True when the run is past where the Roll is taught (`install`'s migration): Burr freed from his
## cell, or any Pearl flag set.
func _past_the_roll_lesson() -> bool:
	for flag: Variant in _flags():
		var flag_name := str(flag)
		if flag_name == ROLL_KNOWN_FLAG or flag_name.begins_with(PEARL_FLAG_PREFIX):
			return true
	return false


## True when a map record of the run has the old Verdant Gate unlocked (`install`'s migration).
func _verdant_gate_was_open() -> bool:
	var maps: Variant = world.get("maps")
	if not maps is Dictionary:
		return false
	for record: Variant in (maps as Dictionary).values():
		var unlocked: Variant = (record as Dictionary).get("unlocked_gate_ids") if record is Dictionary else null
		if unlocked is Array and VERDANT_GATE_ID in (unlocked as Array):
			return true
	return false


func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Why the run cannot be saved now, "" when it can: "prologue" while the prologue runs
## (PrologueState.is_running; question 113: nothing of it is saved, so quitting plays it again from
## the birth); "dungeon" inside a dungeon (DungeonState.is_inside; question 109: no saving there, and
## the autosave waits until the slime is out). Every save (`save_slot`, the autosave,
## `write_recovery`) asks it; the pause menu greys Save out with the reason.
func saving_blocked_reason() -> String:
	if PrologueState.is_running(self):
		return PrologueState.NO_SAVE_REASON
	if DungeonState.is_inside(self):
		return DungeonState.NO_SAVE_REASON
	return ""


## True when the run may be saved now (`saving_blocked_reason` is "").
func can_save() -> bool:
	return saving_blocked_reason().is_empty()


## True when a quit or a closed window writes the dungeon's resume save: inside a dungeon (one that
## writes them: not the dev lab), the autosave slot then holds the run with the slime at the
## dungeon's entrance, and everything done inside kept (DungeonState.resume_data; question 109).
func _writes_dungeon_resume(slot: int) -> bool:
	return slot == AUTOSAVE_SLOT and saving_blocked_reason() == DungeonState.NO_SAVE_REASON \
		and DungeonState.writes_resume(self)


## Writes the run to `slot` (0 = the autosave). False when it could not be written, or when saving
## is blocked (`saving_blocked_reason`: the prologue, a dungeon). In a dungeon the autosave slot
## takes the resume save instead (`_writes_dungeon_resume`: Quit to Title and a closed window ask
## for slot 0).
func save_slot(slot: int = 0) -> bool:
	var resume := _writes_dungeon_resume(slot)
	if not started or (not can_save() and not resume):
		return false
	DirAccess.make_dir_recursive_absolute(save_root)
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_warning("RunState: cannot write %s (%s)" % [_slot_path(slot), error_string(FileAccess.get_open_error())])
		return false
	var data := serialize()
	if resume:
		data = DungeonState.resume_data(self, data)
	file.store_string(JSON.stringify({"schema_version": SAVE_SCHEMA_VERSION,
		"saved_at": Time.get_unix_time_from_system() * 1000.0, "data": data}, "\t"))
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
	if int(record.get("schema_version", 0)) > SAVE_SCHEMA_VERSION:
		return {"exists": true, "record": {}, "problem": "made by a newer version"}
	var data: Variant = record.get("data")
	if not data is Dictionary:
		return {"exists": true, "record": {}, "problem": "not a save file"}
	for key: String in ["player", "inventory", "location", "world", "story"]:
		if not (data as Dictionary).get(key) is Dictionary:
			return {"exists": true, "record": {}, "problem": "not a save file"}
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
	if not autosave_enabled or not started or _autosave_timer == null or not can_save():
		return
	_autosave_timer.start(AUTOSAVE_DELAY_MS / 1000.0)


## Writes the recovery autosave now, unless the slime is dead (`SaveSystem.writeRecovery`). In a
## dungeon (the window closing) it writes the dungeon's resume save (`save_slot`), dead or not: the
## slime wakes at the entrance anyway.
func write_recovery() -> bool:
	if _autosave_timer != null:
		_autosave_timer.stop()
	var resume := _writes_dungeon_resume(AUTOSAVE_SLOT)
	if not autosave_enabled or not started or (not can_save() and not resume):
		return false
	_capture_live_player()
	if int(player.get("hp", 0)) <= 0 and not resume:
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


## True when the main loop is a script under `res://tools/` (a `-s` tool run, not the game).
static func _running_a_tool() -> bool:
	return is_tool_script(_main_loop_script_path())


## The path of the main loop's script ("" for the game's own SceneTree).
static func _main_loop_script_path() -> String:
	var loop: MainLoop = Engine.get_main_loop()
	var script: Script = loop.get_script() as Script if loop != null else null
	return script.resource_path if script != null else ""


## True for a script under `res://tools/` (a render, bake or lab run with `-s`).
static func is_tool_script(path: String) -> bool:
	return path.begins_with(TOOLS_DIR)


## Where a run whose main loop script is `main_script_path` ("" for the game) saves: TOOL_SAVE_ROOT
## for a tool run, else PLAYER_SAVE_ROOT.
static func save_root_for(main_script_path: String) -> String:
	return TOOL_SAVE_ROOT if is_tool_script(main_script_path) else PLAYER_SAVE_ROOT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _running_a_tool():
		save_root = save_root_for(_main_loop_script_path())
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.one_shot = true
	_autosave_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_autosave_timer.timeout.connect(write_recovery)
	add_child(_autosave_timer)
	for changed: Signal in [inventory_changed, world_progress_changed, coins_changed, story_flag_changed, ability_learned,
			tip_heard, page_found, weapon_loadout_changed, weapon_equipped, recipes_learned, quests_changed]:
		changed.connect(func(_payload: Dictionary) -> void: schedule_autosave())
	# The Shell autoload comes after this one: the window joins it right after the Shell's _ready,
	# before the main scene (the title shows Load only when the action exists when it is built).
	var shell := Services.shell()
	if shell != null and shell.is_node_ready():
		_install_save_slots()
	elif shell != null:
		shell.ready.connect(_install_save_slots, CONNECT_ONE_SHOT)
	else:
		get_tree().root.child_entered_tree.connect(_on_root_child_entered)


## The save slots window joins the Shell and takes over its "save" and "load" actions
## (game/saves/save_slots_menu.gd).
func _install_save_slots() -> void:
	SaveSlotsMenu.install(Services.shell())


func _on_root_child_entered(node: Node) -> void:
	if node.name != &"Shell":
		return
	get_tree().root.child_entered_tree.disconnect(_on_root_child_entered)
	if node.is_node_ready():
		_install_save_slots()
	else:
		node.ready.connect(_install_save_slots, CONNECT_ONE_SHOT)


## Window close (Phaser `pagehide`): the autosave is written at once.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		write_recovery()
