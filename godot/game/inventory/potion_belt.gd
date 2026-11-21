extends RefCounted
## The potion belt's rules (docs/godot/specs/crafting.md 12.4; owner, 2026-11-19, question 161:
## "with the slots we can have many potion types but assign only one type to the fast-use slot; a
## stack of 5 health potions assigned to slot 1 is used until it is gone"): which bag items a slot
## takes, each slot's key, and whether a drink would do anything. The state lives in RunState
## (`player.belt`: `potion_belt_open`, `potion_belt_kinds`, `set_potion_belt_kind`; a `belt-slot`
## opens a slot as it comes in); drinking is InventoryActions `drink_belt_slot` (keys 1 to 4, a click
## on the HUD's slot), setting a kind is the bag's Belt row (InventoryActions `assign_belt_slot`), and
## the HUD's group is game/ui/potion_belt_bar.gd. Static helpers.
##
## Owner: crafting / inventory.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

## The input action of each slot (project.godot: keys 1 to 4), slot order.
const ACTIONS: Array[StringName] = ControlLabels.POTION_ACTIONS
## A slot takes a `consumable` that is drunk or eaten (its `use` heals, restores energy or cures).
const POTION_CATEGORY := "consumable"
## Why a drink is refused when it would do nothing (`useless_reason`).
const FULL_HP_TEXT := "Your health is full"
const FULL_ENERGY_TEXT := "Your energy is full"
const FULL_BOTH_TEXT := "Your health and energy are full"


## True for a potion kind a belt slot can be set to: a `consumable` with a `use` that is not an
## essence's gulp (the Slime Tonic, the Fizzy Brew, the Berry Basket).
static func is_potion(item_id: String) -> bool:
	var definition := ItemCatalog.definition(item_id)
	var use: Variant = definition.get("use")
	return str(definition.get("category", "")) == POTION_CATEGORY and use is Dictionary \
		and not bool((use as Dictionary).get("gulp", false))


## How many belt slots are open (0 without a run).
static func open_count() -> int:
	var run := Services.run()
	return run.potion_belt_open() if run != null else 0


## The open slot the potion kind `item_id` is set to, -1 when none.
static func slot_of(item_id: String) -> int:
	var run := Services.run()
	if run == null or item_id.is_empty():
		return -1
	var index := run.potion_belt_kinds().find(item_id)
	return index if index < run.potion_belt_open() else -1


## The label of slot `index`'s key ("1" .. "4", read from the InputMap; "" when unbound).
static func key_label(index: int) -> String:
	return ControlLabels.control_label(ACTIONS[index]) if index >= 0 and index < ACTIONS.size() else ""


## Why drinking one `item_id` now would do nothing for `player` (the live player script), "" when it
## would do something: its HP gain with health full (or the slime dead), its energy gain with energy
## full, and no status it cures on the slime. The bag's Use drinks anyway (crafting spec 7, K10);
## the belt's quick keys refuse, so a stray key never wastes a potion.
static func useless_reason(item_id: String, player: Node) -> String:
	var use: Variant = ItemCatalog.definition(item_id).get("use")
	if not use is Dictionary or player == null or not is_instance_valid(player):
		return ""
	var effects: Dictionary = use
	var heals := float(effects.get("healHp", 0.0)) > 0.0
	var restores := float(effects.get("healEnergy", 0.0)) > 0.0
	if heals and not bool(player.call(&"is_dead")) and int(player.call(&"get_hp")) < int(player.call(&"get_max_hp")):
		return ""
	if restores and float(player.call(&"get_energy")) < float(player.call(&"get_max_energy")):
		return ""
	var cures: Variant = effects.get("cureStatus")
	if cures is Array and player.has_method(&"get_status"):
		var status: Object = player.call(&"get_status")
		for kind: Variant in cures:
			if status != null and bool(status.call(&"has", StringName(str(kind)))):
				return ""
	if heals and restores:
		return FULL_BOTH_TEXT
	if heals:
		return FULL_HP_TEXT
	if restores:
		return FULL_ENERGY_TEXT
	return ""
