@tool
extends EditorExportPlugin
## Leaves the paint layers' palette pictures out of an exported game (docs/godot/PROPS.md). The game
## never draws a painted cell's tile: the prop, wall and forest layers draw their props, walls and
## trees themselves. But a world refers to its layers' tile sets, so it would load every palette
## picture, about 170 MB of textures. In the export each of these tile sets keeps every tile and
## its data, its pictures turned into placeholders of the same size (no pixels), and the picture
## files are left out. Registered by the Scenery plugin (plugin.gd).
##
## Owner: world (props).

## The paint layers' tile sets.
const TILE_SETS: PackedStringArray = [
	"res://game/world/props/props_cell_tileset.tres",
	"res://game/world/props/props_detail_tileset.tres",
	"res://game/world/props/props_tileset.tres",
	"res://game/world/props/walls_tileset.tres",
	"res://game/world/walls/wall_tileset.tres",
	"res://game/world/forest/forest_tileset.tres",
]
## Their pictures (files, or folders ending in "/"), not exported.
const PICTURES: PackedStringArray = [
	"res://asset/MAPS/palettes/",
	"res://asset/MAPS/walls/sets/palette.png",
	"res://asset/MAPS/forest/forest_paint_tiles.png",
]


func _get_name() -> String:
	return "PaletteExport"


func _begin_customize_resources(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool:
	return true


func _get_customization_configuration_hash() -> int:
	return hash([TILE_SETS, PICTURES, 1])


func _customize_resource(resource: Resource, path: String) -> Resource:
	if not TILE_SETS.has(path) or not resource is TileSet:
		return null
	return stripped(resource as TileSet)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	for picture in PICTURES:
		if path == picture or (picture.ends_with("/") and path.begins_with(picture)):
			skip()
			return


## A copy of `tile_set` whose atlas pictures are placeholders of the same size: every tile, its
## place and its custom data stay.
static func stripped(tile_set: TileSet) -> TileSet:
	var copy := tile_set.duplicate(true) as TileSet
	for i in copy.get_source_count():
		var source := copy.get_source(copy.get_source_id(i)) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		var placeholder := PlaceholderTexture2D.new()
		placeholder.size = source.texture.get_size()
		source.texture = placeholder
	return copy
