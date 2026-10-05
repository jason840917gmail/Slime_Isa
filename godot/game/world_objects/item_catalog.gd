extends RefCounted
## Item definitions (Phaser `content/items/ItemCatalog.ts` + `systems/Inventory.ts` registry):
## `generated/data/items.json` (via GameConstants.data_file) with `maxStack` from game-constants
## `inventory.maxStackByItem`. Weapons are items too (Inventory.ts:35-45): id = weapon id,
## category "weapon", max stack `inventory.weaponMaxStack` (1); a weapon id is any scene id
## `weapon.<id>` the scene index knows. An unknown id has no definition (capacity 0).
## World-objects spec 8.2.
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")

const ITEMS_FILE := "items.json"
const WEAPON_SCENE_PREFIX := "weapon."


## The items.json entry of `item_id` (camelCase keys), {} when it is not a plain item.
static func definition(item_id: String) -> Dictionary:
	var constants := Services.constants()
	if constants == null:
		return {}
	var items: Variant = constants.data_file(ITEMS_FILE)
	if items is Dictionary and (items as Dictionary).get(item_id) is Dictionary:
		return items[item_id]
	return {}


static func is_weapon(item_id: String) -> bool:
	var world := Services.world()
	return world != null and not item_id.is_empty() and not world.scene_path(WEAPON_SCENE_PREFIX + item_id).is_empty()


static func is_known(item_id: String) -> bool:
	return not definition(item_id).is_empty() or is_weapon(item_id)


## `inventory.maxStackByItem[id]` for items, `inventory.weaponMaxStack` for weapons, else 0.
static func max_stack(item_id: String) -> int:
	var constants := Services.constants()
	if constants == null:
		return 0
	if not definition(item_id).is_empty():
		var by_item: Dictionary = constants.dictionary("inventory.maxStackByItem")
		return int(by_item.get(item_id, 0))
	if is_weapon(item_id):
		return constants.integer("inventory.weaponMaxStack")
	return 0


## items.json `name`, else the id (WorldScene.ts:1367).
static func item_name(item_id: String) -> String:
	var entry := definition(item_id)
	return str(entry.get("name", item_id)) if not entry.is_empty() else item_id
