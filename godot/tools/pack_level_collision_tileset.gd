extends SceneTree
## Writes the paint palette of the `level-collision` layer (game/world/elevation/
## level_collision_layer.gd; docs/godot/ELEVATION.md "Painting collision"): a native texture
## (level_collision_palette.res, no editor import needed) and its tile set
## (level_collision_tileset.tres). Two columns, the two kinds: **rim** (orange, striped: the upper
## floor's edge, a body there is held and pushing on drops it) and **base** (red: the wall foot a body
## of that level bumps into); one row per level, −3 … 3, its number drawn in the tile. 16 units a
## tile (a quarter of a cell): fine enough to follow a 24-unit side wall or a rim drawn mid-cell.
##     "<Godot console exe>" --headless --path godot -s res://tools/pack_level_collision_tileset.gd

const LayerScript := preload("res://game/world/elevation/level_collision_layer.gd")
const PALETTE := "res://game/world/elevation/level_collision_palette.res"
const TILESET := "res://game/world/elevation/level_collision_tileset.tres"
const TILE := 16
## 3 x 5 pixel digits (rows top to bottom, bit 2 = left).
const DIGITS := {
	"0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [7, 1, 7, 4, 7], "3": [7, 1, 7, 1, 7], "-": [0, 0, 7, 0, 0],
}


func _initialize() -> void:
	var levels: Array[int] = []
	for level in range(LayerScript.MIN_LEVEL, LayerScript.MAX_LEVEL + 1):
		levels.append(level)
	var image := Image.create(TILE * LayerScript.KINDS.size(), TILE * levels.size(), false, Image.FORMAT_RGBA8)
	for column in LayerScript.KINDS.size():
		var kind: String = LayerScript.KINDS[column]
		var colour: Color = LayerScript.KIND_COLOURS[kind]
		for row in levels.size():
			var origin := Vector2i(column * TILE, row * TILE)
			# a higher level a lighter tint, so neighbouring levels read apart
			var tint := colour.lightened(0.12 * float(levels[row] - LayerScript.MIN_LEVEL) / 2.0)
			image.fill_rect(Rect2i(origin, Vector2i(TILE, TILE)), tint)
			if kind == "rim":
				for i in range(-TILE, TILE, 5):
					for t in TILE:
						var x := i + t
						if x >= 0 and x < TILE:
							image.set_pixelv(origin + Vector2i(x, t), tint.darkened(0.25))
			_text(image, origin + Vector2i(3, 5), str(levels[row]), Color(1, 1, 1))
	var texture := ImageTexture.create_from_image(image)
	var err := ResourceSaver.save(texture, PALETTE, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		print("level collision palette: ", error_string(err))
		quit(1)
		return
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, LayerScript.KIND_DATA)
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(1, LayerScript.LEVEL_DATA)
	tile_set.set_custom_data_layer_type(1, TYPE_INT)
	var source := TileSetAtlasSource.new()
	source.texture = load(PALETTE)
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	for column in LayerScript.KINDS.size():
		for row in levels.size():
			var at := Vector2i(column, row)
			source.create_tile(at)
			var data := source.get_tile_data(at, 0)
			data.set_custom_data(LayerScript.KIND_DATA, LayerScript.KINDS[column])
			data.set_custom_data(LayerScript.LEVEL_DATA, levels[row])
	err = ResourceSaver.save(tile_set, TILESET)
	print("level collision tileset: ", "saved " + TILESET if err == OK else error_string(err))
	quit(0 if err == OK else 1)


func _text(image: Image, at: Vector2i, text: String, colour: Color) -> void:
	var x := at.x
	if text.length() == 1:
		x += 2
	for ch in text:
		var rows: Array = DIGITS.get(ch, DIGITS["0"])
		for y in rows.size():
			for b in 3:
				if int(rows[y]) & (4 >> b):
					image.set_pixelv(Vector2i(x + b, at.y + y), colour)
		x += 4
