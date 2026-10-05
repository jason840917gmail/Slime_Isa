extends RefCounted
class_name AreaTitles
## The area name and banner colour shown when a world loads (Phaser `world/Area.ts` AREAS and
## `getAreaDefinition`, `world/Biome.ts` BIOMES[].titleColor; WorldScene.ts:517). Content kept
## here until the converter exports area definitions as data (docs/godot/specs/shell.md 4).
##
## Owner: shell.

## BIOMES[biome].titleColor.
const BIOME_TITLE_COLORS := {
	"icege": Color("#bcecff"),
	"meadow": Color("#a3f0c0"),
	"gloop-forest": Color("#8cff9a"),
	"crystal-caverns": Color("#9ad8ff"),
}
## AREAS: map id -> name and biome. Other worlds (interiors, the playground) get a name made from
## their id and the meadow colour, as `getAreaDefinition` does.
const AREAS := {
	"level-1": {"name": "Slimeshire Meadow", "biome": "meadow"},
	"icege": {"name": "Icege", "biome": "icege"},
	"gloop-forest": {"name": "Gloop Forest", "biome": "gloop-forest"},
	"crystal-caverns": {"name": "Crystal Caverns", "biome": "crystal-caverns"},
}
const DEFAULT_BIOME := "meadow"


## "Slimeshire Meadow" for level-1; an unknown id is title-cased per "-" part ("elder-house" ->
## "Elder House").
static func area_name(map_id: String) -> String:
	if AREAS.has(map_id):
		return str(AREAS[map_id]["name"])
	var parts := PackedStringArray()
	for part: String in map_id.split("-"):
		parts.append(part.left(1).to_upper() + part.substr(1))
	return " ".join(parts)


## The area's biome title colour.
static func title_color(map_id: String) -> Color:
	var biome := str(AREAS[map_id]["biome"]) if AREAS.has(map_id) else DEFAULT_BIOME
	return BIOME_TITLE_COLORS.get(biome, BIOME_TITLE_COLORS[DEFAULT_BIOME])
