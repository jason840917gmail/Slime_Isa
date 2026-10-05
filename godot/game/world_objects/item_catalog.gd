extends RefCounted
## Item definitions (Phaser `content/items/ItemCatalog.ts` + `systems/Inventory.ts` registry):
## `game/data/items.json` (via GameConstants.data_file) with `maxStack` from game-constants
## `inventory.maxStackByItem`. Weapons are items too (Inventory.ts:35-45): id = weapon id, name =
## its `displayName`, category "weapon", icon and description from `game/data/weapons.json`
## (game/inventory/weapon_catalog.gd), `equipment: {weaponId}`, max stack
## `inventory.weaponMaxStack` (1). A weapon missing from weapons.json still counts when the scene
## index knows `weapon.<id>`. An unknown id has no definition (capacity 0).
## World-objects spec 8.2, crafting spec 1.4 and 11.4.
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const WeaponCatalog := preload("res://game/inventory/weapon_catalog.gd")

const ITEMS_FILE := "items.json"
const WEAPON_SCENE_PREFIX := "weapon."


## The item definition of `item_id` (camelCase keys): the items.json entry, else for a weapon
## {"id", "name" (displayName), "category": "weapon", "icon" (iconKey), "iconFrame",
## "description", "equipment": {"weaponId"}}; {} when unknown.
static func definition(item_id: String) -> Dictionary:
	var base := base_definition(item_id)
	if not base.is_empty():
		return base
	if not is_weapon(item_id):
		return {}
	var weapon := WeaponCatalog.find(item_id)
	return {
		"id": item_id,
		"name": str(weapon.get("displayName", item_id)),
		"category": "weapon",
		"icon": str(weapon.get("iconKey", "")),
		"iconFrame": int(weapon.get("iconFrame", 0)),
		"description": str(weapon.get("description", "")),
		"equipment": {"weaponId": item_id},
	}


## Ids of the items.json items that can be placed in the world (`placeable.sceneIds`).
static func placeable_item_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var constants := Services.constants()
	var items: Variant = constants.data_file(ITEMS_FILE) if constants != null else null
	if items is Dictionary:
		for item_id: Variant in items:
			if (items[item_id] as Dictionary).get("placeable") is Dictionary:
				ids.append(str(item_id))
	return ids


## The items.json entry of `item_id`, {} when it is not a plain item.
static func base_definition(item_id: String) -> Dictionary:
	var constants := Services.constants()
	if constants == null:
		return {}
	var items: Variant = constants.data_file(ITEMS_FILE)
	if items is Dictionary and (items as Dictionary).get(item_id) is Dictionary:
		return items[item_id]
	return {}


static func is_weapon(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	if not WeaponCatalog.find(item_id).is_empty():
		return true
	var world := Services.world()
	return world != null and not world.scene_path(WEAPON_SCENE_PREFIX + item_id).is_empty()


static func is_known(item_id: String) -> bool:
	return not base_definition(item_id).is_empty() or is_weapon(item_id)


## `inventory.maxStackByItem[id]` for items, `inventory.weaponMaxStack` for weapons, else 0.
static func max_stack(item_id: String) -> int:
	var constants := Services.constants()
	if constants == null:
		return 0
	if not base_definition(item_id).is_empty():
		var by_item: Dictionary = constants.dictionary("inventory.maxStackByItem")
		return int(by_item.get(item_id, 0))
	if is_weapon(item_id):
		return constants.integer("inventory.weaponMaxStack")
	return 0


## The item's `name` (a weapon's `displayName`, "Basic sword"), else the id (WorldScene.ts:1367).
static func item_name(item_id: String) -> String:
	return str(definition(item_id).get("name", item_id))


## `weaponItemFor` the other way round: the weapon id of an equipment item, "" for anything else.
static func weapon_id_of(item_id: String) -> String:
	var equipment: Variant = definition(item_id).get("equipment")
	return str((equipment as Dictionary).get("weaponId", "")) if equipment is Dictionary else ""
