extends RefCounted
## The recipe table and the crafting stations (Phaser `content/recipes/RecipeCatalog.ts`):
## `game/data/recipes.json` (15 recipes, catalogue order, camelCase keys: id, name, station,
## tier, description, ingredients [{itemId, count}], output {itemId, count}, uniqueOutput?,
## learnedByQuest?). A crafting site is {"station", "tier"}; the portable site is the Crafting tab
## of the menu (there is no C key, crafting spec K1). Crafting spec 1.1-1.2.
##
## Owner: crafting.

const Services := preload("res://game/shared/services.gd")

const RECIPES_FILE := "recipes.json"
## `PORTABLE_SITE` (RecipeCatalog.ts:90).
const PORTABLE_SITE := {"station": "portable", "tier": 1}
## `STATION_INCLUDES` (RecipeCatalog.ts:93-99): a station also crafts these stations' recipes.
const STATION_INCLUDES := {
	"portable": [],
	"workbench": [],
	"workshop": ["workbench"],
	"forge": [],
	"kitchen": [],
}
## `STATION_NAMES` (RecipeCatalog.ts:101-107).
const STATION_NAMES := {
	"portable": "Crafting",
	"workbench": "Workbench",
	"workshop": "Workshop",
	"forge": "Forge",
	"kitchen": "Kitchen",
}


## Every recipe, catalogue order ([] when the file is missing).
static func all() -> Array:
	var constants := Services.constants()
	if constants == null:
		return []
	var data: Variant = constants.data_file(RECIPES_FILE)
	return data if data is Array else []


## The recipe `recipe_id`; {} when unknown.
static func find(recipe_id: String) -> Dictionary:
	for recipe: Variant in all():
		if recipe is Dictionary and str((recipe as Dictionary).get("id", "")) == recipe_id:
			return recipe
	return {}


static func is_station(value: Variant) -> bool:
	return value is String and STATION_NAMES.has(value)


static func station_name(station: String) -> String:
	return str(STATION_NAMES.get(station, station))


## `siteTitle`: "Workshop · Tier 2" above tier 1, else the station name ("Crafting", "Forge").
static func site_title(site: Dictionary) -> String:
	var title := station_name(str(site.get("station", "")))
	var tier := int(site.get("tier", 1))
	return "%s · Tier %d" % [title, tier] if tier > 1 else title


## `stationServes`: the station is the recipe's, or includes it (the Workshop crafts workbench
## recipes).
static func station_serves(station: String, recipe_station: String) -> bool:
	return recipe_station == station or recipe_station in (STATION_INCLUDES.get(station, []) as Array)


static func station_crafts(station: String, recipe: Dictionary) -> bool:
	return station_serves(station, str(recipe.get("station", "")))


## `upgradesOf`: the stations that include this one (workbench -> [workshop]).
static func upgrades_of(station: String) -> Array[String]:
	var out: Array[String] = []
	for other: String in STATION_INCLUDES:
		if station in (STATION_INCLUDES[other] as Array):
			out.append(other)
	return out


## `recipesAt` (RecipeCatalog.ts:144-154): the station's own recipes (lowest tier first, its own
## station before the ones it shares, then catalogue order), then the tier-1 recipes of the
## stations that build on it (shown locked, "At the Workshop").
static func recipes_at(site: Dictionary) -> Array:
	var station := str(site.get("station", ""))
	var upgrades := upgrades_of(station)
	var own: Array = []
	var teasers: Array = []
	var recipes := all()
	for index in recipes.size():
		var recipe: Dictionary = recipes[index]
		var entry := {"recipe": recipe, "index": index, "tier": int(recipe.get("tier", 1)),
			"shared": 0 if str(recipe.get("station", "")) == station else 1}
		if station_crafts(station, recipe):
			own.append(entry)
		elif str(recipe.get("station", "")) in upgrades and int(recipe.get("tier", 1)) == 1:
			teasers.append(entry)
	own.sort_custom(_before)
	teasers.sort_custom(_before)
	var out: Array = []
	for entry: Dictionary in own + teasers:
		out.append(entry["recipe"])
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["tier"]) != int(b["tier"]):
		return int(a["tier"]) < int(b["tier"])
	if int(a["shared"]) != int(b["shared"]):
		return int(a["shared"]) < int(b["shared"])
	return int(a["index"]) < int(b["index"])
