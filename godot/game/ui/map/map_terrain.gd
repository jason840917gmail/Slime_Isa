extends RefCounted
class_name MapTerrain
## Bakes a world's ground into one small Image for the minimap (docs/godot/specs/map.md 3.2):
## one pixel per tile, the tile's average colour; empty cells stay transparent. Nothing is per
## tile at draw time: the minimap wraps the Image in one ImageTexture.
##
## A tile's colour is the box average of its atlas region: the whole atlas texture shrunk to its
## grid with trilinear filtering (mipmaps, so each grid pixel averages its tile exactly) when the
## atlas has no margins or separation and divides evenly, else each used region shrunk to 1 x 1.
## The shrunk atlases are cached for the run (`_atlas_cache`, keyed by texture path and region
## size), so only a world's first new ground atlas decodes its texture.
##
## Owner: map (game/ui/map).

## texture key -> Image (atlas shrunk to its grid, RGBA8) or Dictionary (region -> Color).
static var _atlas_cache: Dictionary = {}


## The ground of `layer` over `columns` x `rows` cells from (0, 0): an RGBA8 Image, or null when
## there is no layer or tile set.
static func bake(layer: TileMapLayer, columns: int, rows: int) -> Image:
	if layer == null or layer.tile_set == null or columns <= 0 or rows <= 0:
		return null
	var image := Image.create_empty(columns, rows, false, Image.FORMAT_RGBA8)
	var tile_set := layer.tile_set
	for cell: Vector2i in layer.get_used_cells():
		if cell.x < 0 or cell.y < 0 or cell.x >= columns or cell.y >= rows:
			continue
		var source := tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if source == null:
			continue
		var color := tile_color(source, layer.get_cell_atlas_coords(cell))
		if color.a > 0.0:
			image.set_pixelv(cell, color)
	return image


## Average colour of the tile at `coords` in `source` (transparent when its texture is unreadable).
static func tile_color(source: TileSetAtlasSource, coords: Vector2i) -> Color:
	var texture := source.texture
	if texture == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var region_size := source.texture_region_size
	var key := "%s|%d|%d|%s|%s" % [_texture_key(texture), region_size.x, region_size.y, source.margins, source.separation]
	var cached: Variant = _atlas_cache.get(key)
	if cached == null:
		cached = _shrink_atlas(source)
		_atlas_cache[key] = cached
	if cached is Image:
		var grid := cached as Image
		if coords.x < grid.get_width() and coords.y < grid.get_height():
			return grid.get_pixelv(coords)
		return Color(0.0, 0.0, 0.0, 0.0)
	var regions := cached as Dictionary
	if not regions.has(coords):
		regions[coords] = _region_average(regions.get(&"image") as Image, source, coords)
	return regions[coords]


## Drops the cached atlas colours (tests; a changed tile set).
static func clear_cache() -> void:
	_atlas_cache.clear()


static func _texture_key(texture: Texture2D) -> String:
	return texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_rid().get_id())


## The atlas shrunk to its grid (Image), or {&"image": the readable atlas} to average regions one
## by one ({} when the texture cannot be read).
static func _shrink_atlas(source: TileSetAtlasSource) -> Variant:
	var image := _readable_image(source.texture)
	if image == null:
		return {}
	var grid := source.get_atlas_grid_size()
	var region := source.texture_region_size
	var even := source.margins == Vector2i.ZERO and source.separation == Vector2i.ZERO \
		and image.get_width() == grid.x * region.x and image.get_height() == grid.y * region.y
	if not even or grid.x <= 0 or grid.y <= 0:
		return {&"image": image}
	image.resize(grid.x, grid.y, Image.INTERPOLATE_TRILINEAR)
	return image


static func _region_average(image: Image, source: TileSetAtlasSource, coords: Vector2i) -> Color:
	if image == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var region := source.get_tile_texture_region(coords).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if region.size.x <= 0 or region.size.y <= 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var part := image.get_region(region)
	part.resize(1, 1, Image.INTERPOLATE_TRILINEAR)
	return part.get_pixel(0, 0)


## An uncompressed RGBA8 copy of the texture's image, or null.
static func _readable_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image
