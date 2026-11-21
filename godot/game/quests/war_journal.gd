extends RefCounted
## The Thorn Guard's war journal (Release 1's lore manuscripts, question 108; quests spec 14.8): its
## pages are items of category `page` in game/data/items.json, each with a `page` block {number,
## title, lines}. A page found is used up as it comes in (RunState "finds": `story.war_pages`), its
## reading panel opens (game/ui/screens/page_window.gd), and the journal's War journal section lists
## the pages found to read again (quest_journal_model.gd). A recipe page (category `recipe-page`) has
## a `page` block too, read the same way, but it is no part of the journal.
##
## Owner: quests (story).

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const ITEMS_FILE := "items.json"
const PAGE_CATEGORY := "page"
const RECIPE_PAGE_CATEGORY := "recipe-page"


## The page item `item_id` as the panel and the journal show it: {"item_id", "kind" ("war" or
## "recipe"), "number" (0 for a recipe page), "title", "lines": Array[String], "name",
## "recipes": Array[String] (a recipe page's)}; {} when it is no page.
static func page(item_id: String) -> Dictionary:
	var definition := ItemCatalog.definition(item_id)
	var category := str(definition.get("category", ""))
	if category != PAGE_CATEGORY and category != RECIPE_PAGE_CATEGORY:
		return {}
	var block: Dictionary = definition.get("page", {}) if definition.get("page") is Dictionary else {}
	var lines: Array[String] = []
	if block.get("lines") is Array:
		for line: Variant in block["lines"]:
			lines.append(str(line))
	var recipes: Array[String] = []
	if definition.get("teachesRecipes") is Array:
		for recipe_id: Variant in definition["teachesRecipes"]:
			recipes.append(str(recipe_id))
	return {
		"item_id": item_id,
		"kind": "war" if category == PAGE_CATEGORY else "recipe",
		"number": int(block.get("number", 0)),
		"title": str(block.get("title", definition.get("name", item_id))),
		"lines": lines,
		"name": str(definition.get("name", item_id)),
		"recipes": recipes,
	}


## Every war-journal page in items.json (item ids), by page number.
static func page_ids() -> Array[String]:
	var constants := Services.constants()
	var items: Variant = constants.data_file(ITEMS_FILE) if constants != null else null
	var numbered: Array = []
	if items is Dictionary:
		for item_id: Variant in items:
			var entry: Variant = items[item_id]
			if entry is Dictionary and str((entry as Dictionary).get("category", "")) == PAGE_CATEGORY:
				numbered.append([int(page(str(item_id)).get("number", 0)), str(item_id)])
	numbered.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array[String] = []
	for pair: Array in numbered:
		out.append(pair[1])
	return out


## How many pages the journal has.
static func page_count() -> int:
	return page_ids().size()


## The pages `run` has found (`page` dictionaries), by page number.
static func found_pages(run: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if run == null or not run.has_method(&"has_war_page"):
		return out
	for item_id in page_ids():
		if bool(run.call(&"has_war_page", item_id)):
			out.append(page(item_id))
	return out
