extends SceneTree
## Writes the paint palette of the `vines` VineLayer (game/world/vines/vine_layer.gd;
## docs/godot/SKINS.md "Painting vines"): vine_tileset.tres, its texture inside it (a native image,
## no editor import needed). Two tiles, 64 units: **vines** at (0, 0), a green square with the root
## wall's picture small in it, and **balcony** at (1, 0), a stone-coloured square with the balcony's
## picture. The vines' tile never moves, so painted worlds keep their cells.
##     "<Godot console exe>" --headless --path godot -s res://tools/pack_vine_tileset.gd

const TILESET := "res://game/world/vines/vine_tileset.tres"
const VINES_ART := "res://asset/MAPS/props/mine/256x256-root-wall.webp"
const BALCONY_ART := "res://asset/MAPS/objects/balcony-meadow-rock.webp"
const TILE := 64
## [atlas column, the square's colour, the picture's file, how much of the square it takes].
const TILES: Array = [
	[0, Color(0.25, 0.62, 0.22, 0.85), VINES_ART, 0.8],
	[1, Color(0.62, 0.5, 0.3, 0.85), BALCONY_ART, 0.92],
]


func _initialize() -> void:
	var image := Image.create(TILE * TILES.size(), TILE, false, Image.FORMAT_RGBA8)
	for tile: Array in TILES:
		var origin := Vector2i(int(tile[0]) * TILE, 0)
		var colour: Color = tile[1]
		for y in TILE:
			for x in TILE:
				var edge := x < 3 or y < 3 or x >= TILE - 3 or y >= TILE - 3
				image.set_pixelv(origin + Vector2i(x, y), colour.darkened(0.35) if edge else colour)
		# the picture's own file, read as it is (a headless run has no need of its import)
		var art := Image.load_from_file(ProjectSettings.globalize_path(str(tile[2])))
		if art == null:
			print("vine tileset: no picture at ", tile[2])
			continue
		art.convert(Image.FORMAT_RGBA8)
		var used := art.get_used_rect()
		art = art.get_region(used)
		var side := float(TILE) * float(tile[3])
		var scale := side / float(maxi(art.get_width(), art.get_height()))
		art.resize(maxi(1, roundi(art.get_width() * scale)), maxi(1, roundi(art.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
		var at := origin + Vector2i((TILE - art.get_width()) / 2, (TILE - art.get_height()) / 2)
		image.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), at)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	for tile: Array in TILES:
		source.create_tile(Vector2i(int(tile[0]), 0))
	# the scenes name the tile set by its uid: keep it
	var uid := ResourceLoader.get_resource_uid(TILESET) if ResourceLoader.exists(TILESET) else ResourceUID.INVALID_ID
	var err := ResourceSaver.save(tile_set, TILESET)
	if err == OK and uid != ResourceUID.INVALID_ID:
		err = ResourceSaver.set_uid(TILESET, uid)
	print("vine tileset: ", "saved " + TILESET if err == OK else error_string(err))
	quit(0 if err == OK else 1)
