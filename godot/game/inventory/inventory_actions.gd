extends Node
## The bag, belt and crafting glue of Phaser's `WorldScene` (crafting spec 3, 7, 8.4, 8.8,
## 11.6): a child "InventoryActions" of main, made once and kept across worlds, group
## `inventory_actions`, PROCESS_MODE_ALWAYS (the bag uses it while the game is paused).
##
## - Belt: `switch_weapon_slot` (the wheel and the HUD hotbar), `equip_weapon_slot`,
##   `equip_weapon_from_bag` ("Hold in hand", a belt click in the bag), `assign_weapon_slot`.
##   Texts: "<name> equipped" (yellow, big, 48 px above the centre); refusals in white, small,
##   42 px above it ("Slot 2 is empty", "Weapon not in inventory", "Finish the attack first",
##   "Weapon is unavailable"). The hand changing plays EquipBlade (sword, spear) or EquipTool.
## - `use_item` (the bag's Use): heal, energy, then one taken from the item's first stack.
## - `on_crafted` (the crafting window): a crafted weapon goes onto the belt and into an empty hand,
##   then "Crafted: <recipe name>" (green, big, 44 px up). A crafted Workbench closes the crafting
##   window and starts furniture placement (game/building/furniture_placement.gd).
## - `harvest_message`: a resource node's "Requires an Axe" plus where the right tool is.
## - World build: `grant_trial_weapon` (a new run, owner decision C3) and `equip_run_weapon`.
## Every text also goes out on `message_shown` (test hook).
##
## Owner: crafting / inventory.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const WeaponCatalog := preload("res://game/inventory/weapon_catalog.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const PlayerCombat := preload("res://game/combat/player_combat.gd")

const GROUP := &"inventory_actions"
## WorldScene.ts floating-text heights above the old centre.
const EQUIP_TEXT_RISE := 48.0
const FAIL_TEXT_RISE := 42.0
const CRAFTED_TEXT_RISE := 44.0
const HEAL_TEXT_RISE := 30.0
## AudioEventBridge: `energy.changed` plays EnergyRestore from a gain of 20.
const ENERGY_CUE_MIN_DELTA := 20.0
## AudioEventBridge.ts:60: `/sword|spear/` weapons play EquipBlade, the rest EquipTool.
const BLADE_PATTERNS: PackedStringArray = ["sword", "spear"]
const CUE_EQUIP_BLADE := &"EquipBlade"
const CUE_EQUIP_TOOL := &"EquipTool"
const CUE_HEAL := &"Heal"
const CUE_ENERGY_RESTORE := &"EnergyRestore"
## WorldScene.equipWeaponSlot failure texts (by WeaponLoadout reason).
const FAIL_TEXTS := {
	"empty": "Slot %d is empty",
	"not-owned": "Weapon not in inventory",
	"busy": "Finish the attack first",
	"unknown": "Weapon is unavailable",
}
const NOT_OWNED_TEXT := "Weapon not in inventory"
const WEAPON_SWITCH_CONTROL := "weapon-switch"

## A text was shown. Payload: {"text", "color" (GameFeel colour name), "big", "x", "y"}.
signal message_shown(payload: Dictionary)

## True while the world build sets the hand (no equip cue for a load or a new run).
var _quiet: bool = false


func _init() -> void:
	name = "InventoryActions"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_to_group(GROUP)
	var run := Services.run()
	if run != null and not run.weapon_equipped.is_connected(_on_weapon_equipped):
		run.weapon_equipped.connect(_on_weapon_equipped)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.weapon_equipped.is_connected(_on_weapon_equipped):
		run.weapon_equipped.disconnect(_on_weapon_equipped)


# --- the belt ------------------------------------------------------------------------------------

## `switchWeaponSlot` (the wheel, the HUD hotbar): equips the slot; when the hand changed, reports
## the `weapon-switch` control to the quests. True when the hand changed.
func switch_weapon_slot(index: int) -> bool:
	if not equip_weapon_slot(index):
		return false
	QuestEvents.emit(QuestEvents.CONTROL_USED, {"controlId": WEAPON_SWITCH_CONTROL})
	return true


## `equipWeaponSlot`: puts belt slot `index`'s weapon in hand (mounting it on PlayerCombat).
## True when the weapon in hand changed.
func equip_weapon_slot(index: int) -> bool:
	var result := WeaponLoadout.equip_slot(index, _mount)
	if bool(result["ok"]):
		if bool(result["changed"]):
			_text(EQUIP_TEXT_RISE, "%s equipped" % ItemCatalog.item_name(str(result["weapon_id"])), &"yellow", true)
		return bool(result["changed"])
	var text: String = FAIL_TEXTS.get(str(result["reason"]), FAIL_TEXTS["unknown"])
	if str(result["reason"]) == WeaponLoadout.REASON_EMPTY:
		text = text % (index + 1)
	_text(FAIL_TEXT_RISE, text, &"white", false)
	return false


## `equipWeaponFromInventory`: holds a bag weapon; it goes onto its belt slot, else the first empty
## one, else (a full belt) the slot of the weapon in hand (slot 1 with an empty hand).
func equip_weapon_from_bag(weapon_id: String) -> void:
	var slot := WeaponLoadout.ensure_assigned(weapon_id)
	if slot >= 0:
		equip_weapon_slot(slot)
		return
	var run := Services.run()
	var in_hand: Variant = run.equipped_weapon_id()
	var hand_slot := run.weapon_slots().find(in_hand) if in_hand != null else -1
	assign_weapon_slot(weapon_id, maxi(0, hand_slot))
	if run.equipped_weapon_id() != weapon_id:
		equip_weapon_slot(maxi(0, hand_slot))


## `assignWeaponSlot`: puts a weapon on belt slot `index` (swapping within the belt); a bag weapon
## that replaced the hand's slot goes into the hand.
func assign_weapon_slot(weapon_id: String, index: int) -> void:
	var assignment := WeaponLoadout.assign_weapon(index, weapon_id)
	if not bool(assignment["ok"]):
		_text(FAIL_TEXT_RISE, NOT_OWNED_TEXT, &"white", false)
		return
	if bool(assignment["equip_assigned_weapon"]):
		equip_weapon_slot(index)


# --- items ---------------------------------------------------------------------------------------

## `useItem` (WorldScene.ts:2005-2024): heals ("+N", green, big, 30 px up, the Heal cue when HP
## rose), restores energy (EnergyRestore from a gain of 20), then takes one from the item's FIRST
## stack. A potion is used up even at full health (K10, kept: owner decision C4).
func use_item(item_id: String) -> void:
	var run := Services.run()
	var use: Variant = ItemCatalog.definition(item_id).get("use")
	if not use is Dictionary or run.item_count(item_id) <= 0:
		return
	var effects: Dictionary = use
	var player := _player()
	if float(effects.get("healHp", 0.0)) != 0.0:
		var healed: int = player.heal(int(effects["healHp"])) if player != null else 0
		if healed > 0:
			_text(HEAL_TEXT_RISE, "+%d" % healed, &"green", true)
			_cue(CUE_HEAL)
	if float(effects.get("healEnergy", 0.0)) != 0.0 and player != null:
		var gained: float = player.restore_energy(float(effects["healEnergy"]))
		if gained >= ENERGY_CUE_MIN_DELTA:
			_cue(CUE_ENERGY_RESTORE)
	var cures: Variant = effects.get("cureStatus")
	if cures is Array and player != null:
		for kind: Variant in cures:
			player.get_status().remove(StringName(str(kind)))
	run.remove_item(item_id, 1)


## `onCrafted` (WorldScene.ts:2295-2311) after a successful craft (`result` from
## CraftingService.craft).
func on_crafted(result: Dictionary) -> void:
	var recipe: Dictionary = result.get("recipe", {})
	var output := str((recipe.get("output", {}) as Dictionary).get("itemId", ""))
	var crafted_text := "Crafted: %s" % str(recipe.get("name", output))
	if ItemCatalog.definition(output).has("placeable"):
		# WorldScene.ts:2296-2300: the crafting window closes and placement starts.
		var menus := get_tree().get_first_node_in_group(&"menu_windows")
		var crafting: Variant = menus.get(&"crafting") if menus != null else null
		if crafting != null and is_instance_valid(crafting) and bool((crafting as Node).call(&"is_open")):
			(crafting as Node).call(&"close")
		var furniture := get_tree().get_first_node_in_group(&"furniture_placement")
		if furniture != null:
			furniture.call(&"start", output)
		_text(CRAFTED_TEXT_RISE, crafted_text, &"green", true)
		return
	var weapon_id := ItemCatalog.weapon_id_of(output)
	if not weapon_id.is_empty():
		var slot := WeaponLoadout.ensure_assigned(weapon_id)
		if slot >= 0 and Services.run().equipped_weapon_id() == null:
			equip_weapon_slot(slot)
	_text(CRAFTED_TEXT_RISE, crafted_text, &"green", true)


## `harvestBlockedMessage` (WorldScene.ts:2188-2203, HarvestAdvice.ts): `payload` is a resource
## node's `harvest_blocked` payload ({targetTag, minimumTier, message, ...}). Adds ": switch with the
## mouse wheel" when an owned belt weapon can harvest it, ": put yours on the belt (E)" when only a
## bag weapon can, nothing when none can.
func harvest_message(payload: Dictionary) -> String:
	var message := str(payload.get("message", ""))
	var tag := str(payload.get("targetTag", ""))
	var tier := float(payload.get("minimumTier", 0.0))
	var harvests := func(weapon_id: String) -> bool:
		return float(WeaponCatalog.harvest_capabilities(weapon_id).get(tag, 0.0)) >= tier
	if WeaponLoadout.belt_weapons().any(harvests):
		return "%s: switch with the %s" % [message, ControlLabels.control_label(&"weapon_next").to_lower()]
	if WeaponLoadout.owned_weapons().any(harvests):
		return "%s: put yours on the belt (%s)" % [message, ControlLabels.control_label(&"menu")]
	return message


# --- world build -----------------------------------------------------------------------------------

## The trial weapon (owner decision C3): `weapon_id` into the bag (when not owned), onto the belt
## (slot 1 at a new run) and into the hand, without a cue. An unknown id falls back to
## `fallback_id`. Returns the weapon put in hand ("" when none could be).
func grant_trial_weapon(weapon_id: String, fallback_id: String = "") -> String:
	var chosen := weapon_id
	if not ItemCatalog.is_weapon(chosen):
		push_warning("InventoryActions: unknown trial weapon '%s'" % chosen)
		chosen = fallback_id
	if chosen.is_empty() or not ItemCatalog.is_weapon(chosen):
		return ""
	_quiet = true
	WeaponLoadout.grant([chosen])
	var slot := WeaponLoadout.ensure_assigned(chosen)
	if slot >= 0:
		Services.run().set_equipped_weapon(chosen)
	_quiet = false
	return chosen if slot >= 0 else ""


## Every world build (`WeaponLoadout.reconcile`, then the hand mounted on the new PlayerCombat;
## nothing in hand mounts nothing). Travel and loads keep the hand.
func equip_run_weapon() -> void:
	_quiet = true
	WeaponLoadout.reconcile()
	_quiet = false
	var combat := _combat()
	if combat == null:
		return
	var weapon_id: Variant = Services.run().equipped_weapon_id()
	if weapon_id == null:
		combat.unequip()
	elif not combat.equip(str(weapon_id)):
		push_warning("InventoryActions: could not mount '%s'" % str(weapon_id))


# --- private -------------------------------------------------------------------------------------

## `CombatController.equipWeapon`: refused while a swing is in flight; the weapon already mounted
## is kept; else mounted and the player goes idle.
func _mount(weapon_id: String) -> bool:
	var combat := _combat()
	if combat == null:
		return false
	var mounted := combat.get_weapon()
	if mounted != null and mounted.weapon_id == weapon_id:
		return not combat.is_attacking()
	if not combat.equip(weapon_id):
		return false
	var player := _player()
	if player != null:
		player.play_animation("idle")
	return true


func _on_weapon_equipped(payload: Dictionary) -> void:
	var weapon_id: Variant = payload.get("weapon_id")
	if _quiet or not weapon_id is String:
		return
	for pattern: String in BLADE_PATTERNS:
		if (weapon_id as String).contains(pattern):
			_cue(CUE_EQUIP_BLADE)
			return
	_cue(CUE_EQUIP_TOOL)


func _text(rise: float, text: String, color: StringName, big: bool) -> void:
	var player := _player()
	var at := player.get_centre() - Vector2(0.0, rise) if player != null else Vector2.ZERO
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at, text, color, big)
	message_shown.emit({"text": text, "color": String(color), "big": big, "x": at.x, "y": at.y})


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


func _player() -> PlayerScript:
	var world := Services.world()
	var player: PlayerScript = world.player if world != null else null
	return player if player != null and is_instance_valid(player) and player.is_inside_tree() else null


func _combat() -> PlayerCombat:
	var player := _player()
	var combat: PlayerCombat = player.get_combat() if player != null else null
	return combat if combat != null and is_instance_valid(combat) else null
