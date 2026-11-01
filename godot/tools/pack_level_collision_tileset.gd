extends SceneTree
## Writes the paint palette of the `level-collision` layer (game/world/elevation/
## level_collision_layer.gd; docs/godot/ELEVATION.md "Painting collision"): a native texture
## (level_collision_palette.res, no editor import needed) and its tile set
## (level_collision_tileset.tres). The first four columns are the whole tiles: **rim** (orange,
## striped: the upper floor's edge, a body there is held and pushing on drops it), **base** (red: the
## wall foot a body of that level bumps into), **edge** (a rim with a red border: a rim for its level
## and a base for every level below, a raised floor's north border) and **open** (green: nothing of
## that level collides there); then the 45° halves of rim, base and edge, four each (the solid half in
## the north-east, north-west, south-east and south-west corner, the rest of the tile clear). One row
## per level, −3 … 3, its number drawn in the solid part. 16 units a tile (a quarter of a cell): fine
## enough to follow a 24-unit side wall or a rim drawn mid-cell. The columns of the first three kinds
## never move, so painted scenes keep their tiles.
##     "<Godot console exe>" --headless --path godot -s res://tools/pack_level_collision_tileset.gd

const LayerScript := preload("res://game/world/elevation/level_collision_layer.gd")
const PALETTE := "res://game/world/elevation/level_collision_palette.res"
const TILESET := "res://game/world/elevation/level_collision_tileset.tres"
const TILE := 16
## 3 x 5 pixel digits (rows top to bottom, bit 2 = left).
const DIGITS := {
	"0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [7, 1, 7, 4, 7], "3": [7, 1, 7, 1, 7], "-": [0, 0, 7, 0, 0],
}
## Where a tile's level number goes, by shape ("" a whole tile).
const NUMBER_AT := {"": Vector2i(3, 5), "ne": Vector2i(8, 2), "nw": Vector2i(1, 2), "se": Vector2i(8, 9), "sw": Vector2i(1, 9)}


func _initialize() -> void:
	var levels: Array[int] = []
	for level in range(LayerScript.MIN_LEVEL, LayerScript.MAX_LEVEL + 1):
		levels.append(level)
	# [kind, shape] per palette column (LayerScript.tile_of's order)
	var columns: Array = []
	for kind in LayerScript.KINDS:
		columns.append([kind, ""])
	for kind in LayerScript.SLOPED_KINDS:
		for shape in LayerScript.SHAPES:
			columns.append([kind, shape])
	var image := Image.create(TILE * columns.size(), TILE * levels.size(), false, Image.FORMAT_RGBA8)
	for column in columns.size():
		var kind: String = columns[column][0]
		var shape: String = columns[column][1]
		for row in levels.size():
			_draw_tile(image, Vector2i(column * TILE, row * TILE), kind, shape, levels[row])
	var texture := ImageTexture.create_from_image(image)
	var err := ResourceSaver.save(texture, PALETTE, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		print("level collision palette: ", error_string(err))
		quit(1)
		return
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var data_layers := [[LayerScript.KIND_DATA, TYPE_STRING], [LayerScript.LEVEL_DATA, TYPE_INT], [LayerScript.SHAPE_DATA, TYPE_STRING]]
	for index in data_layers.size():
		tile_set.add_custom_data_layer()
		tile_set.set_custom_data_layer_name(index, data_layers[index][0])
		tile_set.set_custom_data_layer_type(index, data_layers[index][1])
	var source := TileSetAtlasSource.new()
	source.texture = load(PALETTE)
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	for column in columns.size():
		for row in levels.size():
			var at := Vector2i(column, row)
			source.create_tile(at)
			var data := source.get_tile_data(at, 0)
			data.set_custom_data(LayerScript.KIND_DATA, columns[column][0])
			data.set_custom_data(LayerScript.LEVEL_DATA, levels[row])
			data.set_custom_data(LayerScript.SHAPE_DATA, columns[column][1])
	# the scenes name the tile set by its uid: keep it
	var uid := ResourceLoader.get_resource_uid(TILESET) if ResourceLoader.exists(TILESET) else ResourceUID.INVALID_ID
	err = ResourceSaver.save(tile_set, TILESET)
	if err == OK and uid != ResourceUID.INVALID_ID:
		err = ResourceSaver.set_uid(TILESET, uid)
	print("level collision tileset: ", "saved " + TILESET if err == OK else error_string(err))
	quit(0 if err == OK else 1)


## One palette tile at `origin`: its kind's colour (a higher level a lighter tint) over the solid part
## of `shape`, rims and edges striped, an edge's border red, an open tile framed lighter; its level's
## number in white.
func _draw_tile(image: Image, origin: Vector2i, kind: String, shape: String, level: int) -> void:
	var colour: Color = LayerScript.KIND_COLOURS[kind]
	var tint := colour.lightened(0.12 * float(level - LayerScript.MIN_LEVEL) / 2.0)
	var red: Color = LayerScript.KIND_COLOURS[LayerScript.BASE]
	for y in TILE:
		for x in TILE:
			if not LayerScript.in_shape(shape, Vector2(x + 0.5, y + 0.5) / TILE):
				continue
			var pixel := tint
			if (kind == LayerScript.RIM or kind == LayerScript.EDGE) and posmod(x - y, 5) == 4:
				pixel = tint.darkened(0.25)
			var ring := mini(mini(x, y), mini(TILE - 1 - x, TILE - 1 - y))
			if kind == LayerScript.EDGE and ring < 3:
				# the base's red round it: the lower levels' wall foot
				pixel = red
			elif kind == LayerScript.OPEN and ring < 2:
				pixel = tint.lightened(0.45)
			image.set_pixelv(origin + Vector2i(x, y), pixel)
	_text(image, origin + NUMBER_AT[shape], str(level), Color(1, 1, 1))


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
