extends RefCounted
## The crafting window's model (Phaser `CraftingSurfacePort.snapshot`, crafting spec 4.3): what
## the window shows for its state, with the exact texts. Pure apart from reading the bag.
##
## `state` (owned by the window, updated here): {"site": {"station", "tier"},
## "selected_recipe_id": String, "quantities": {recipe id: int} (kept across openings),
## "status": String or null (a message after Craft), "status_color": Color or null}.
##
## Model keys: title, recipes [{id, label, item_id, locked, short}], selected_index, recipe (the
## selected recipe or {}), details_name, details, materials [{id, label, item_id, short}],
## quantity, status, status_color, craft_disabled, quantity_disabled.
##
## Owner: crafting (UI).

const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const CraftingService := preload("res://game/crafting/crafting_service.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

## STATUS_COLORS (CraftingSurfacePort.ts:232).
const HINT_COLOR := UiTokens.WARNING
const REFUSED_COLOR := UiTokens.DANGER
const SUCCESS_COLOR := UiTokens.ACCENT
const LOCKED_STATUSES: PackedStringArray = ["not-learned", "station-tier", "wrong-station"]
const CRAFTABLE_STATUSES: PackedStringArray = ["ready", "missing-materials", "inventory-full"]


## A new window state at the portable site.
static func new_state() -> Dictionary:
	return {"site": RecipeCatalog.PORTABLE_SITE.duplicate(), "selected_recipe_id": "", "quantities": {},
		"status": null, "status_color": null}


## The recipes the state's site lists.
static func recipes(state: Dictionary) -> Array:
	return RecipeCatalog.recipes_at(state["site"])


## The selected recipe ({} when the site lists none); rewrites the selection to it.
static func selected_recipe(state: Dictionary) -> Dictionary:
	var list := recipes(state)
	if list.is_empty():
		return {}
	var index := _index_of(list, str(state.get("selected_recipe_id", "")))
	var recipe: Dictionary = list[maxi(0, index)]
	state["selected_recipe_id"] = str(recipe["id"])
	return recipe


## `quote(recipe)` (CraftingSurfacePort.ts:174-179): the stored quantity (1 when none),
## re-normalised against the current maximum and written back.
static func quote_for(state: Dictionary, recipe: Dictionary) -> Dictionary:
	var site: Dictionary = state["site"]
	var max_craftable := int(CraftingService.quote(recipe, 1, site)["maxCraftable"])
	var quantities: Dictionary = state["quantities"]
	var quantity := CraftingService.normalize_quantity(quantities.get(str(recipe["id"]), 1), max_craftable)
	quantities[str(recipe["id"])] = quantity
	return CraftingService.quote(recipe, quantity, site)


static func snapshot(state: Dictionary) -> Dictionary:
	var site: Dictionary = state["site"]
	var list := recipes(state)
	var recipe := selected_recipe(state)
	var selected_index := _index_of(list, str(recipe.get("id", "")))
	var quote := quote_for(state, recipe) if not recipe.is_empty() else {}
	var rows: Array = []
	for entry: Dictionary in list:
		var row_quote := CraftingService.quote(entry, 1, site)
		var status := str(row_quote["status"])
		var short := status == CraftingService.MISSING_MATERIALS
		var state_text := "Missing " + missing_list(row_quote, 2) if short else row_state(status, entry)
		var output_id := str((entry.get("output", {}) as Dictionary).get("itemId", ""))
		rows.append({"id": str(entry["id"]), "label": "%s\n%s" % [str(entry.get("name", "")), state_text],
			"item_id": output_id if not ItemCatalog.definition(output_id).is_empty() else "",
			"locked": status in LOCKED_STATUSES, "short": short})
	var model := {
		"title": RecipeCatalog.site_title(site),
		"recipes": rows,
		"selected_index": selected_index if not recipe.is_empty() else -1,
		"recipe": recipe,
		"details_name": "Nothing to craft here",
		"details": "No recipes available",
		"materials": [],
		"quantity": "Amount: 0",
		"status": "",
		"status_color": HINT_COLOR,
		"craft_disabled": true,
		"quantity_disabled": true,
	}
	if recipe.is_empty():
		return model
	var output_id := str((recipe.get("output", {}) as Dictionary).get("itemId", ""))
	model["details_name"] = str(ItemCatalog.definition(output_id).get("name", recipe.get("name", "")))
	model["details"] = details_for(recipe, quote)
	model["materials"] = material_rows(quote)
	model["quantity"] = "Amount: %d  ·  MAX %d" % [int(quote["requestedQuantity"]), int(quote["maxCraftable"])]
	var quote_status := str(quote["status"])
	if state.get("status") != null:
		model["status"] = str(state["status"])
	elif quote_status != CraftingService.READY:
		model["status"] = reason_text(quote_status, recipe, site, quote)
	if state.get("status_color") is Color:
		model["status_color"] = state["status_color"]
	model["craft_disabled"] = not quote_status in CRAFTABLE_STATUSES
	model["quantity_disabled"] = int(quote["maxCraftable"]) < 1
	return model


## `detailsFor`: the description, then a blank line and the stat lines joined by "  ·  ".
static func details_for(recipe: Dictionary, quote: Dictionary) -> String:
	var lines := PackedStringArray()
	for stat: Dictionary in quote.get("stats", []):
		lines.append("%s: %s" % [str(stat["label"]), str(stat["value"])])
	var text := str(recipe.get("description", ""))
	if not lines.is_empty():
		text += "\n\n" + "  ·  ".join(lines)
	return text


## `materialRows`: "<name>\n<available> / <required>" + "  (need N more)" or "  ✓".
static func material_rows(quote: Dictionary) -> Array:
	var rows: Array = []
	for cost: Dictionary in quote.get("requirements", []):
		var item_id := str(cost["itemId"])
		var missing := int(cost["missing"])
		var suffix := "  (need %d more)" % missing if missing > 0 else "  ✓"
		rows.append({"id": "material-" + item_id,
			"label": "%s\n%d / %d%s" % [ItemCatalog.item_name(item_id), int(cost["available"]), int(cost["required"]), suffix],
			"item_id": item_id if not ItemCatalog.definition(item_id).is_empty() else "",
			"short": missing > 0})
	return rows


## `rowState` (CraftingSurfacePort.ts:219-230).
static func row_state(status: String, recipe: Dictionary) -> String:
	match status:
		"ready":
			return "Ready to craft"
		"station-tier":
			return "Needs tier %d" % int(recipe.get("tier", 1))
		"not-learned":
			return "Not learned yet"
		"unique-owned":
			return "Already owned"
		"inventory-full":
			return "Inventory full"
		"wrong-station":
			return "At the %s" % RecipeCatalog.station_name(str(recipe.get("station", "")))
		"missing-materials":
			return "Materials needed"
	return "Unavailable"


## `missingList` (CraftingSurfacePort.ts:235-239): "12 Wood, 3 Stone"; past `limit` materials the
## first ones then ", …". `limit` < 0 = no limit.
static func missing_list(quote: Dictionary, limit: int = -1) -> String:
	var missing: Array = []
	for requirement: Dictionary in quote.get("requirements", []):
		if int(requirement["missing"]) > 0:
			missing.append(requirement)
	var shown := PackedStringArray()
	for index in missing.size():
		if limit >= 0 and index >= limit:
			break
		var requirement: Dictionary = missing[index]
		shown.append("%d %s" % [int(requirement["missing"]), ItemCatalog.item_name(str(requirement["itemId"]))])
	var text := ", ".join(shown)
	return text + ", …" if limit >= 0 and missing.size() > limit else text


## `reasonText` (CraftingSurfacePort.ts:242-252): why the recipe cannot be crafted here.
static func reason_text(reason: String, recipe: Dictionary, site: Dictionary, quote: Dictionary = {}) -> String:
	match reason:
		"invalid-recipe":
			return "This recipe is unavailable."
		"wrong-station":
			return "Craft this at the %s." % RecipeCatalog.station_name(str(recipe.get("station", "")))
		"station-tier":
			return "Needs a tier %d %s." % [int(recipe.get("tier", 1)), RecipeCatalog.station_name(str(site.get("station", "")))]
		"not-learned":
			return "Not learned yet — a quest will teach it."
		"unique-owned":
			return "You already have this item."
		"missing-materials":
			var missing := missing_list(quote) if not quote.is_empty() else ""
			return "Missing: %s." % missing if not missing.is_empty() else "More materials are needed."
		"inventory-full":
			return "Make room in your inventory first."
	return ""


static func _index_of(list: Array, recipe_id: String) -> int:
	for index in list.size():
		if str((list[index] as Dictionary).get("id", "")) == recipe_id:
			return index
	return -1
