extends RefCounted
class_name AreaTitles
## The area name and banner colour shown when a world loads (Phaser `world/Area.ts` AREAS and
## `getAreaDefinition`, `world/Biome.ts` BIOMES[].titleColor; WorldScene.ts:517). Content kept
## here until the converter exports area definitions as data (docs/godot/specs/shell.md 4).
## A region world of the world layout (res://game/data/world-map.json, a region's `world`) that
## is not in AREAS takes the region's name (`region_name`, also the world map's) and its colour
## lifted towards the text colour. A chunk world of a region cut into chunk worlds
## (game/world/atlas/world_chunks.gd) takes its region world's name and colour.
##
## Owner: shell.

const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")

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
## How far a region's sketch colour is mixed towards the text colour, so it reads on the banner.
const REGION_COLOR_LIFT := 0.4

## Overworld map id -> its world-map.json region, read once (empty without the file).
static var _regions: Dictionary = {}
static var _regions_read := false


## "Slimeshire Meadow" for level-1 (and its chunk worlds, "level-1-c4"); a region world its
## region's name (`region_name`); any other id is title-cased per "-" part ("elder-house" ->
## "Elder House").
static func area_name(map_id: String) -> String:
	map_id = _whole_world(map_id)
	if AREAS.has(map_id):
		return str(AREAS[map_id]["name"])
	var region_title := region_name(_region(map_id))
	if not region_title.is_empty():
		return region_title
	var parts := PackedStringArray()
	for part: String in map_id.split("-"):
		parts.append(part.left(1).to_upper() + part.substr(1))
	return " ".join(parts)


## The area's biome title colour (a region world's: its region colour, lifted).
static func title_color(map_id: String) -> Color:
	map_id = _whole_world(map_id)
	var fallback: Color = BIOME_TITLE_COLORS[DEFAULT_BIOME]
	if AREAS.has(map_id):
		return BIOME_TITLE_COLORS.get(str(AREAS[map_id]["biome"]), fallback)
	var region := _region(map_id)
	if region.has("color"):
		return Color.from_string(str(region["color"]), fallback).lerp(UiTokens.TEXT, REGION_COLOR_LIFT)
	return fallback


## A world-map.json region's name as players read it (the area banner, the save slots, the world
## map): its `name` without a trailing note in parentheses, the sketch tool's planning note on an
## open design slot ("Desert (open)" -> "Desert"; the file keeps it). "" when it has no name.
static func region_name(region: Dictionary) -> String:
	var text := str(region.get("name", "")).strip_edges()
	var note := text.rfind("(")
	if text.ends_with(")") and note > 0:
		text = text.left(note).strip_edges()
	return text


## The region world chunk world `map_id` was cut from; `map_id` itself for any other world.
static func _whole_world(map_id: String) -> String:
	var world := WorldChunks.world_of(map_id)
	return map_id if world.is_empty() else world


## The world-map.json region whose overworld is `map_id` ({} when none).
static func _region(map_id: String) -> Dictionary:
	if not _regions_read:
		_regions_read = true
		var map: WorldMapData = WorldMapData.load_file() if FileAccess.file_exists(WorldMapData.PATH) else null
		if map != null:
			for region: Dictionary in map.regions():
				var world := str(region.get("world", ""))
				if not world.is_empty():
					_regions[world] = region
	return _regions.get(map_id, {})
