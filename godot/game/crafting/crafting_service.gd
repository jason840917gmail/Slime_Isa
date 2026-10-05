extends RefCounted
## Quotes and crafts (Phaser `crafting/CraftingService.ts`), on the run's bag (RunState
## `item_count` / `transact_items`). Crafting spec 2.
##
## A quote says how many of a recipe the bag can make at a site and why not: the first failing
## check wins (wrong station, tier, not learned, unique output owned, missing materials, no room),
## else "ready". `maxCraftable` is the largest quantity whose all-or-nothing transaction fits (the
## ingredients come out first, so the output can land in a slot they emptied). A craft takes a
## ready quote's materials and adds its output in one transaction, then reports `craft.completed`
## (RunState.recipe_crafted, the quest events, the CraftSuccess cue).
##
## Quote dictionaries keep Phaser's camelCase keys: recipeId, requestedQuantity, maxCraftable,
## outputItemId, outputQuantity, requirements [{itemId, perCraft, required, available, missing}],
## stats [{label, value}], status.
##
## Owner: crafting.

const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const WeaponCatalog := preload("res://game/inventory/weapon_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

## JavaScript's Number.MAX_SAFE_INTEGER (the unique-output limit of an ordinary recipe).
const MAX_SAFE_INTEGER := 9007199254740991

const READY := "ready"
const WRONG_STATION := "wrong-station"
const STATION_TIER := "station-tier"
const NOT_LEARNED := "not-learned"
const UNIQUE_OWNED := "unique-owned"
const MISSING_MATERIALS := "missing-materials"
const INVENTORY_FULL := "inventory-full"
const INVALID_RECIPE := "invalid-recipe"

const CUE_SUCCESS := &"CraftSuccess"
const CUE_FAIL := &"CraftFail"


## `normalizeQuantity` (CraftingService.ts:83-90): 0 when nothing can be made; a non-number,
## non-finite or non-positive request becomes 1; otherwise the request truncated into 1..max.
static func normalize_quantity(value: Variant, max_craftable: int) -> int:
	var limit := max_craftable if max_craftable > 0 else 0
	if limit == 0:
		return 0
	var numeric := NAN
	if value is int or value is float:
		numeric = float(value)
	elif value is String:
		var text := (value as String).strip_edges()
		numeric = text.to_float() if text.is_valid_float() else (0.0 if text.is_empty() else NAN)
	if not is_finite(numeric) or numeric <= 0.0:
		return 1
	return clampi(int(numeric), 1, limit)


## `quote(recipe, requested, site)` (CraftingService.ts:153-202).
static func quote(recipe: Dictionary, requested: Variant, site: Dictionary = RecipeCatalog.PORTABLE_SITE) -> Dictionary:
	var output: Dictionary = recipe.get("output") if recipe.get("output") is Dictionary else {}
	var output_id := str(output["itemId"]) if output.get("itemId") is String else ""
	var output_def := ItemCatalog.definition(output_id) if not output_id.is_empty() else {}
	if output_def.is_empty() or not is_valid_recipe(recipe, output_def):
		return {"recipeId": str(recipe["id"]) if recipe.get("id") is String else "", "requestedQuantity": 0,
			"maxCraftable": 0, "outputItemId": output_id, "outputQuantity": 0, "requirements": [], "stats": [],
			"status": INVALID_RECIPE}
	var run := Services.run()
	var totals := _totals(recipe)
	var ingredient_limit := MAX_SAFE_INTEGER
	for item_id: String in totals:
		ingredient_limit = mini(ingredient_limit, floori(float(run.item_count(item_id)) / float(totals[item_id])))
	var unique := bool(recipe.get("uniqueOutput", false))
	var unique_limit := MAX_SAFE_INTEGER
	if unique:
		unique_limit = 0 if run.item_count(output_id) > 0 else 1
	var candidate := maxi(0, mini(ingredient_limit, unique_limit))
	var max_craftable := _max_transaction(recipe, candidate)
	var quantity := normalize_quantity(requested, max_craftable)
	var requirement_quantity := maxi(1, quantity)
	var requirements: Array = []
	for ingredient: Dictionary in recipe.get("ingredients", []):
		var item_id := str(ingredient.get("itemId", ""))
		var per_craft := int(ingredient.get("count", 0))
		var available := run.item_count(item_id)
		var required := per_craft * requirement_quantity
		requirements.append({"itemId": item_id, "perCraft": per_craft, "required": required,
			"available": available, "missing": maxi(0, required - available)})
	return {
		"recipeId": str(recipe["id"]),
		"requestedQuantity": quantity,
		"maxCraftable": max_craftable,
		"outputItemId": output_id,
		"outputQuantity": int(output.get("count", 0)) * quantity,
		"requirements": requirements,
		"stats": item_stats(output_def),
		"status": _status(recipe, site, max_craftable, requirements),
	}


## `craft(recipe, requested, site)` (CraftingService.ts:204-229): a ready quote's transaction, then
## `craft.completed`. {"ok": true, "recipe", "quote", "output_quantity"} or {"ok": false, "recipe",
## "quote", "reason"} (the bag untouched).
static func craft(recipe: Dictionary, requested: Variant, site: Dictionary = RecipeCatalog.PORTABLE_SITE) -> Dictionary:
	var result_quote := quote(recipe, requested, site)
	if str(result_quote["status"]) != READY:
		return {"ok": false, "recipe": recipe, "quote": result_quote, "reason": result_quote["status"]}
	var run := Services.run()
	var transaction := transaction_for(recipe, int(result_quote["requestedQuantity"]))
	if not run.transact_items(transaction["removals"], transaction["additions"]):
		result_quote = quote(recipe, requested, site)
		var reason := INVENTORY_FULL if str(result_quote["status"]) == READY else str(result_quote["status"])
		return {"ok": false, "recipe": recipe, "quote": result_quote, "reason": reason}
	var payload := {"recipeId": str(recipe["id"]), "itemId": str(result_quote["outputItemId"]),
		"quantity": int(result_quote["outputQuantity"])}
	run.recipe_crafted.emit(payload.duplicate())
	QuestEvents.emit(QuestEvents.CRAFT_COMPLETED, payload.duplicate())
	_cue(CUE_SUCCESS)
	return {"ok": true, "recipe": recipe, "quote": result_quote, "output_quantity": int(result_quote["outputQuantity"])}


## The Craft button was refused (Phaser `craft.failed`): RunState.craft_failed and the CraftFail cue.
static func report_failure(recipe_id: String, reason: String) -> void:
	var run := Services.run()
	if run != null:
		run.craft_failed.emit({"recipeId": recipe_id, "reason": reason})
	_cue(CUE_FAIL)


## `transactionFor`: {"removals": [{"item_id", "count"}] per ingredient (summed per id),
## "additions": [{"item_id": output, "count"}]} for `quantity` crafts.
static func transaction_for(recipe: Dictionary, quantity: int) -> Dictionary:
	var removals: Array = []
	var totals := _totals(recipe)
	for item_id: String in totals:
		removals.append({"item_id": item_id, "count": int(totals[item_id]) * quantity})
	var output: Dictionary = recipe.get("output", {})
	return {"removals": removals,
		"additions": [{"item_id": str(output.get("itemId", "")), "count": int(output.get("count", 0)) * quantity}]}


## `itemStats` (CraftingService.ts:111-151): a harvesting weapon's "Harvest" lines, another
## weapon's "Damage" and "Cooldown", a consumable's "Effect" lines; nothing else.
static func item_stats(item: Dictionary) -> Array:
	var stats: Array = []
	var equipment: Variant = item.get("equipment")
	if equipment is Dictionary:
		var weapon := WeaponCatalog.find(str((equipment as Dictionary).get("weaponId", "")))
		if weapon.is_empty():
			return stats
		var harvest: Variant = weapon.get("harvestCapabilities")
		if harvest is Dictionary and not (harvest as Dictionary).is_empty():
			for tag: Variant in harvest:
				stats.append({"label": "Harvest", "value": "%s: %s" % [str(tag), js_number(harvest[tag])]})
			return stats
		stats.append({"label": "Damage", "value": str(roundi(float(weapon.get("baseDamage", 0.0))))})
		stats.append({"label": "Cooldown", "value": "%.1fs" % (float(weapon.get("cooldownMs", 0.0)) / 1000.0)})
		return stats
	var use: Variant = item.get("use")
	if not use is Dictionary:
		return stats
	if (use as Dictionary).has("healHp"):
		stats.append({"label": "Effect", "value": "+%s HP" % js_number(use["healHp"])})
	if (use as Dictionary).has("healEnergy"):
		stats.append({"label": "Effect", "value": "+%s energy" % js_number(use["healEnergy"])})
	return stats


## `isValidRecipe` (CraftingService.ts:231-244).
static func is_valid_recipe(recipe: Dictionary, output_def: Dictionary) -> bool:
	if not recipe.get("id") is String or str(recipe["id"]).strip_edges().is_empty():
		return false
	var output: Variant = recipe.get("output")
	if not output is Dictionary or not (output as Dictionary).get("itemId") is String:
		return false
	var ingredients: Variant = recipe.get("ingredients")
	if not ingredients is Array or (ingredients as Array).is_empty():
		return false
	if output_def.is_empty() or not _positive_integer((output as Dictionary).get("count")):
		return false
	var equipment: Variant = output_def.get("equipment")
	if equipment is Dictionary and WeaponCatalog.find(str((equipment as Dictionary).get("weaponId", ""))).is_empty() \
			and not ItemCatalog.is_weapon(str((equipment as Dictionary).get("weaponId", ""))):
		return false
	for ingredient: Variant in ingredients:
		if not ingredient is Dictionary:
			return false
		var item_id: Variant = (ingredient as Dictionary).get("itemId")
		if not item_id is String or (item_id as String).strip_edges().is_empty():
			return false
		if ItemCatalog.definition(item_id).is_empty() or not _positive_integer((ingredient as Dictionary).get("count")):
			return false
	return true


## A JSON number the way a JavaScript template literal prints it (40.0 -> "40").
static func js_number(value: Variant) -> String:
	if (value is float or value is int) and is_finite(float(value)) and float(value) == floorf(float(value)) \
			and absf(float(value)) < 1.0e15:
		return str(int(value))
	return str(value)


# --- private ------------------------------------------------------------------------------------

## `resolveStatus` (CraftingService.ts:259-274): the most fundamental reason wins.
static func _status(recipe: Dictionary, site: Dictionary, max_craftable: int, requirements: Array) -> String:
	var run := Services.run()
	if not RecipeCatalog.station_crafts(str(site.get("station", "")), recipe):
		return WRONG_STATION
	if int(recipe.get("tier", 1)) > int(site.get("tier", 1)):
		return STATION_TIER
	if bool(recipe.get("learnedByQuest", false)) and not run.knows_recipe(str(recipe["id"])):
		return NOT_LEARNED
	if bool(recipe.get("uniqueOutput", false)) and run.item_count(str((recipe["output"] as Dictionary)["itemId"])) > 0:
		return UNIQUE_OWNED
	for requirement: Dictionary in requirements:
		if int(requirement["available"]) < int(requirement["perCraft"]):
			return MISSING_MATERIALS
	if max_craftable == 0:
		return INVENTORY_FULL
	return READY


## `findMaximumTransaction`: the largest n in [0, candidate] whose transaction fits.
static func _max_transaction(recipe: Dictionary, candidate: int) -> int:
	if candidate <= 0:
		return 0
	var run := Services.run()
	var low := 0
	var high := candidate
	while low < high:
		var mid := ceili((low + high) / 2.0)
		var transaction := transaction_for(recipe, mid)
		if run.transact_items(transaction["removals"], transaction["additions"], true):
			low = mid
		else:
			high = mid - 1
	return low


## `aggregateIngredients`: {item id: count per craft}, first-seen order.
static func _totals(recipe: Dictionary) -> Dictionary:
	var totals := {}
	for ingredient: Variant in recipe.get("ingredients", []):
		if ingredient is Dictionary:
			var item_id := str((ingredient as Dictionary).get("itemId", ""))
			totals[item_id] = int(totals.get(item_id, 0)) + int((ingredient as Dictionary).get("count", 0))
	return totals


static func _positive_integer(value: Variant) -> bool:
	if value is int:
		return int(value) > 0 and int(value) <= MAX_SAFE_INTEGER
	if value is float:
		var number := float(value)
		return is_finite(number) and number == floorf(number) and number > 0.0 and number <= float(MAX_SAFE_INTEGER)
	return false


static func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)
