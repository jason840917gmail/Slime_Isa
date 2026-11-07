@tool
extends Resource
## Each ground's default wall style (docs/godot/ELEVATION.md "Wall styles"; the owner, 2026-11-06:
## "being able to change the default wall for a ground"): the wall a cliff takes under a top of that
## ground where the world's `cliffs` layer paints none over it and the world gives that ground no
## style of its own (the ground layer's `cliff_wall_styles` metadata). One resource for the game,
## ground_wall_styles.tres beside this script: open it in the Inspector, one drop-down per ground of
## every style the `cliffs` layer paints. An open world's walls follow at once; every world's do, so
## bake the elevation caches after a change (tools/bake_elevation.gd: a game run from the project
## rebuilds a world whose cache is out of date, an exported one only reads them).
##
## Owner: world (elevation).

## The grounds that stand on walls, in the Inspector's order, with their names there.
const GROUNDS := {
	"highland": "Grass", "gravel-path": "Gravel path", "garden-soil": "Garden soil",
	"sanddessert": "Sand", "frozen": "Snow", "forest-floor": "Forest floor",
	"forest-moss": "Forest moss", "amberleaf": "Fallen leaves", "cavern-floor": "Cavern floor",
	"crystal-floor": "Crystal floor", "town-cobble": "Cobble",
}
## The styles as shipped (each ground's revert value in the Inspector, and the table without the
## resource).
const DEFAULTS := {
	"highland": "meadow-rock", "frozen": "snow-rock", "sanddessert": "sandstone",
	"forest-floor": "root-rock", "forest-moss": "mossy-rock", "amberleaf": "red-rock",
	"cavern-floor": "cave-rock", "crystal-floor": "crystal-rock", "town-cobble": "masonry",
	"garden-soil": "root-rock", "gravel-path": "meadow-rock",
}
## The styles offered: every one painted by the `cliffs` layer's tile set (its `wall_style` data).
const CLIFF_TILESET := "res://game/world/elevation/cliffs/cliff_tileset.tres"
const STYLE_DATA_LAYER := "wall_style"
const PREFIX := "ground/"

## ground -> wall style (a ground left out: DEFAULTS, else Elevation.DEFAULT_WALL_STYLE).
@export_storage var styles: Dictionary = DEFAULTS.duplicate()


## The style of `ground`: its own, else as shipped, else "".
func style_of(ground: String) -> String:
	return str(styles.get(ground, DEFAULTS.get(ground, "")))


func _get_property_list() -> Array[Dictionary]:
	var choices := style_names()
	var out: Array[Dictionary] = []
	for ground: String in GROUNDS:
		var options := choices.duplicate()
		var now := style_of(ground)
		if now != "" and not options.has(now):
			options.append(now)
		out.append({
			"name": property_of(ground), "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM,
			"hint_string": ",".join(options), "usage": PROPERTY_USAGE_EDITOR,
		})
	return out


func _get(property: StringName) -> Variant:
	var ground := _ground_of(property)
	return style_of(ground) if ground != "" else null


func _set(property: StringName, value: Variant) -> bool:
	var ground := _ground_of(property)
	if ground == "":
		return false
	styles[ground] = str(value)
	emit_changed()
	return true


func _property_can_revert(property: StringName) -> bool:
	var ground := _ground_of(property)
	return DEFAULTS.has(ground) and style_of(ground) != str(DEFAULTS[ground])


func _property_get_revert(property: StringName) -> Variant:
	return DEFAULTS.get(_ground_of(property), null)


## A ground's property in the Inspector: "ground/Sand (sanddessert)".
static func property_of(ground: String) -> String:
	return "%s%s (%s)" % [PREFIX, GROUNDS.get(ground, ground), ground]


## The ground a property is for ("" for none of them).
static func _ground_of(property: StringName) -> String:
	var name := str(property)
	if not name.begins_with(PREFIX) or not name.ends_with(")") or not name.contains("("):
		return ""
	var ground := name.substr(name.rfind("(") + 1).trim_suffix(")")
	return ground if GROUNDS.has(ground) else ""


## Every wall style the `cliffs` layer's tile set paints, in its order.
static func style_names() -> PackedStringArray:
	var names := PackedStringArray()
	var tiles := load(CLIFF_TILESET) as TileSet
	if tiles == null:
		return names
	for index in tiles.get_source_count():
		var atlas := tiles.get_source(tiles.get_source_id(index)) as TileSetAtlasSource
		if atlas == null:
			continue
		for tile in atlas.get_tiles_count():
			var data := atlas.get_tile_data(atlas.get_tile_id(tile), 0)
			var style := str(data.get_custom_data(STYLE_DATA_LAYER)) if data != null else ""
			if style != "" and not names.has(style):
				names.append(style)
	return names
