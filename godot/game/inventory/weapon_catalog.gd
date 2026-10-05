extends RefCounted
## Weapon names, descriptions, icons and stats for the bag, the belt and crafting (Phaser
## `content/weapons/<id>/weapon.json` through `virtual-weapon-content.ts`): the converted
## `generated/data/weapons.json`, in definition order. The weapon scenes (`weapon.<id>`) carry the
## combat numbers; this list is for what the windows show. Crafting spec 1.4, 10.2.
##
## Entries keep the JSON's camelCase keys: weaponId, displayName, description, category, iconKey,
## iconFrame, baseDamage, cooldownMs, harvestCapabilities?.
##
## Owner: crafting / inventory.

const Services := preload("res://game/shared/services.gd")

const WEAPONS_FILE := "weapons.json"


## Every weapon entry, definition order ([] when the file is missing).
static func all() -> Array:
	var constants := Services.constants()
	if constants == null:
		return []
	var data: Variant = constants.data_file(WEAPONS_FILE)
	return data if data is Array else []


## The entry of `weapon_id`; {} when unknown.
static func find(weapon_id: String) -> Dictionary:
	if weapon_id.is_empty():
		return {}
	for entry: Variant in all():
		if entry is Dictionary and str((entry as Dictionary).get("weaponId", "")) == weapon_id:
			return entry
	return {}


## Weapon ids in definition order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in all():
		if entry is Dictionary:
			out.append(str((entry as Dictionary).get("weaponId", "")))
	return out


## `displayName` ("Basic sword", "Stone Axe"); the id when unknown.
static func display_name(weapon_id: String) -> String:
	return str(find(weapon_id).get("displayName", weapon_id))


## `harvestCapabilities` ({resource tag: tier}); {} when the weapon harvests nothing.
static func harvest_capabilities(weapon_id: String) -> Dictionary:
	var value: Variant = find(weapon_id).get("harvestCapabilities")
	return value if value is Dictionary else {}
