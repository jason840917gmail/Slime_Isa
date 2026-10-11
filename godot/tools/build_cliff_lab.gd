extends SceneTree
## Builds the hand-painted cliff tiles' TileSet and the cliff lab world (docs/godot/CLIFFS.md).
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_cliff_lab.gd
## Reads the sheet and tile list scripts/art/build-cliff-tiles.py writes into
## res://asset/MAPS/cliffs/ (import the sheet in the editor first) and writes:
## - res://game/world/cliffs/cliff_tileset.tres: one 128 px tile per 64-unit cell (the layer is
##   scaled 0.5) and one terrain set "Cliffs" (Match Corners and Sides) with four terrains:
##   "Highland top" (a raised top: its ground, ragged border and inner corners), "Rock wall top"
##   (a wall's top row, with the lip), "Rock wall" (the rows below it) and "Wall foot". A top tile that stands on a wall has an alternative matching the wall below
##   (no border at its foot: the wall's lip takes over). Walls are solid on physics layer 1
##   (world), and so is a strip along a top's open sides (a raised top is not walked onto or off,
##   as in Zelda).
## - res://game/scenes/worlds/cliff-lab.tscn (world.cliff-lab): a grass field with cliffs painted
##   through the terrain on one `cliffs` layer, the way they are painted by hand. Rebuilding
##   overwrites the lab.

const TILE_LIST := "res://asset/MAPS/cliffs/meadow-rock-highland.json"
const SHEET := "res://asset/MAPS/cliffs/meadow-rock-highland.png"
const TILESET_PATH := "res://game/world/cliffs/cliff_tileset.tres"
const LAB_PATH := "res://game/scenes/worlds/cliff-lab.tscn"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const TILE := 128
const CELL := 64
const GRASS_SOURCE := 7   # grass-a in terrain_tileset.tres
const SHEET_CELLS := 19
## Thickness of a top's solid border, in tile pixels (12 world units).
const RIM := 24.0
## The terrain set and its terrains (the tile list's peering values; -1 is nothing).
const CLIFF_SET := 0
const TOP := 0
const WALL := 1
const FOOT := 2
const CAP := 3
const TERRAINS := {"top": TOP, "wall": WALL, "foot": FOOT, "cap": CAP}
const NEIGHBOUR_BITS := {
	"N": TileSet.CELL_NEIGHBOR_TOP_SIDE, "NE": TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	"E": TileSet.CELL_NEIGHBOR_RIGHT_SIDE, "SE": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	"S": TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, "SW": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	"W": TileSet.CELL_NEIGHBOR_LEFT_SIDE, "NW": TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
}
## The lab: '#' a raised top, 'w' a wall, '.' the grass below (a wall's foot goes under its lowest
## row by itself). A wall goes under a top's south edge, one row per level; the pit's walls are
## its far (north) side. Every foot keeps a free row under it before the next top. The octagon at
## the bottom gets its 45 degree pieces from HAND_PLACED.
const PLAN: PackedStringArray = [
	"............................................",
	"..##########..........##########............",
	"..##########..........##########............",
	"..##########..........##wwww####............",
	"..##########..........##wwww####............",
	"..wwwwwwwwww..........##....####............",
	"..wwwwwwwwww..........##....####............",
	"......................##########............",
	"......................##########............",
	"..########............wwwwwwwwww............",
	"..########............wwwwwwwwww............",
	"..wwwwwwww............wwwwwwwwww............",
	"............................................",
	"................######..............########",
	"................######..............########",
	"..####..........######..............wwwwwwww",
	"..######........###www..............wwwwwwww",
	"..########......###www..............wwwwwwww",
	"..########......www.................wwwwwwww",
	"..wwwwwwww......www.........................",
	"..wwwwwwww..................................",
	"............................................",
	"............................................",
	"....######..................................",
	"...########.................................",
	"..##########................................",
	"..##########................................",
	"..w########w................................",
	"..ww######ww................................",
	"...wwwwwwww.................................",
	"....wwwwww..................................",
	"............................................",
	"............................................",
]
## Tiles placed by hand after the terrain painting (cell -> tile label in the tile list): the
## octagon's 45 degree chamfers, tops over its 45 walls, the plain stone under them and their feet.
const HAND_PLACED := {
	Vector2i(4, 23): "45 top NW", Vector2i(3, 24): "45 top NW", Vector2i(2, 25): "45 top NW",
	Vector2i(9, 23): "45 top NE", Vector2i(10, 24): "45 top NE", Vector2i(11, 25): "45 top NE",
	Vector2i(2, 26): "45 top over wall SW", Vector2i(3, 27): "45 top over wall SW", Vector2i(4, 28): "45 top over wall SW",
	Vector2i(2, 27): "wall middle middle", Vector2i(3, 28): "wall middle middle", Vector2i(4, 29): "wall middle middle",
	Vector2i(2, 28): "45 wall foot SW", Vector2i(3, 29): "45 wall foot SW", Vector2i(4, 30): "45 wall foot SW",
	Vector2i(11, 26): "45 top over wall SE", Vector2i(10, 27): "45 top over wall SE", Vector2i(9, 28): "45 top over wall SE",
	Vector2i(11, 27): "wall middle middle", Vector2i(10, 28): "wall middle middle", Vector2i(9, 29): "wall middle middle",
	Vector2i(11, 28): "45 wall foot SE", Vector2i(10, 29): "45 wall foot SE", Vector2i(9, 30): "45 wall foot SE",
}
const SPAWN_CELL := Vector2i(19, 11)


func _initialize() -> void:
	var tile_set := build_tile_set()
	if tile_set == null:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TILESET_PATH.get_base_dir()))
	var err := ResourceSaver.save(tile_set, TILESET_PATH)
	if err != OK:
		push_error("could not save %s (%d)" % [TILESET_PATH, err])
		quit(1)
		return
	tile_set = load(TILESET_PATH) as TileSet
	err = build_lab(tile_set)
	print("cliff tile set and lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


func build_tile_set() -> TileSet:
	var list: Variant = JSON.parse_string(FileAccess.get_file_as_string(TILE_LIST))
	var sheet := load(SHEET) as Texture2D
	if not (list is Dictionary) or sheet == null:
		push_error("cliff art missing: run scripts/art/build-cliff-tiles.py and import it in the editor")
		return null
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 0)
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(CLIFF_SET, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	for terrain: Array in [["Highland top", Color(0.45, 0.8, 0.3)], ["Rock wall", Color(0.75, 0.6, 0.4)],
			["Wall foot", Color(0.5, 0.65, 0.35)], ["Rock wall top", Color(0.9, 0.75, 0.45)]]:
		var index := tile_set.get_terrains_count(CLIFF_SET)
		tile_set.add_terrain(CLIFF_SET)
		tile_set.set_terrain_name(CLIFF_SET, index, terrain[0])
		tile_set.set_terrain_color(CLIFF_SET, index, terrain[1])
	var source := TileSetAtlasSource.new()
	source.texture = sheet
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	for entry: Dictionary in (list as Dictionary)["tiles"]:
		var atlas := Vector2i(int(entry["atlas"][0]), int(entry["atlas"][1]))
		source.create_tile(atlas)
		var terrain: int = TERRAINS[entry["kind"]]
		_set_up(source.get_tile_data(atlas, 0), entry, entry["peering"], terrain)
		for alternative: Dictionary in entry.get("alternatives", []):
			var alt := source.create_alternative_tile(atlas)
			_set_up(source.get_tile_data(atlas, alt), entry, alternative, terrain)
	return tile_set


## One tile (or alternative): terrain, neighbours, weight and collision.
func _set_up(data: TileData, entry: Dictionary, peering: Dictionary, terrain: int) -> void:
	data.probability = float(entry["probability"])
	data.terrain_set = CLIFF_SET
	data.terrain = terrain
	for name: String in NEIGHBOUR_BITS:
		data.set_terrain_peering_bit(NEIGHBOUR_BITS[name], int(peering[name]))
	var shapes: Array[PackedVector2Array] = []
	if entry.has("shapes"):
		for points: Array in entry["shapes"]:
			var polygon := PackedVector2Array()
			for xy: Array in points:
				polygon.append(Vector2(float(xy[0]), float(xy[1])))
			shapes.append(polygon)
	elif bool(entry["solid"]):
		shapes.append(_box(-TILE / 2.0, -TILE / 2.0, TILE / 2.0, TILE / 2.0))
	elif terrain == TOP:
		shapes = _rim_shapes(peering)
	for shape in shapes:
		var index := data.get_collision_polygons_count(0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, index, shape)


## A top's solid border (as in Zelda, a raised top is entered and left only where a ledge or
## stairs say so): a RIM-thick strip inside each side with nothing there (a wall below is solid
## itself), and a RIM square at each inner corner (both sides top, the diagonal nothing). In tile
## pixels around the cell's centre.
func _rim_shapes(peering: Dictionary) -> Array[PackedVector2Array]:
	var h := TILE / 2.0
	var r := h - RIM
	var shapes: Array[PackedVector2Array] = []
	if int(peering["N"]) == -1:
		shapes.append(_box(-h, -h, h, -r))
	if int(peering["S"]) == -1:
		shapes.append(_box(-h, r, h, h))
	if int(peering["W"]) == -1:
		shapes.append(_box(-h, -h, -r, h))
	if int(peering["E"]) == -1:
		shapes.append(_box(r, -h, h, h))
	for corner: Array in [["NW", "N", "W", -1, -1], ["NE", "N", "E", 1, -1], ["SW", "S", "W", -1, 1], ["SE", "S", "E", 1, 1]]:
		if int(peering[corner[1]]) == TOP and int(peering[corner[2]]) == TOP and int(peering[corner[0]]) == -1:
			var sx: float = corner[3]
			var sy: float = corner[4]
			shapes.append(_box(minf(sx * r, sx * h), minf(sy * r, sy * h), maxf(sx * r, sx * h), maxf(sy * r, sy * h)))
	return shapes


func _box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


func build_lab(tile_set: TileSet) -> Error:
	var columns := PLAN[0].length()
	var rows := PLAN.size()
	var root := Node2D.new()
	root.name = "cliff-lab"
	root.y_sort_enabled = true

	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in rows:
		for x in columns:
			ground.set_cell(Vector2i(x, y), GRASS_SOURCE, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", columns * rows)
	ground.set_meta(&"columns", columns)
	ground.set_meta(&"rows", rows)
	ground.set_script(load(WORLD_GROUND))
	root.add_child(ground)

	var cliffs := TileMapLayer.new()
	cliffs.name = "cliffs"
	cliffs.z_index = -1
	cliffs.scale = Vector2(0.5, 0.5)
	cliffs.tile_set = tile_set
	root.add_child(cliffs)
	# Tops, then each wall's top row, then the rows below it, then the feet (docs/godot/CLIFFS.md
	# "Painting").
	var walls := _cells("w")
	var caps: Array[Vector2i] = []
	var bodies: Array[Vector2i] = []
	for cell in walls:
		if walls.has(cell + Vector2i.UP):
			bodies.append(cell)
		else:
			caps.append(cell)
	cliffs.set_cells_terrain_connect(_cells("#"), CLIFF_SET, TOP, false)
	cliffs.set_cells_terrain_connect(caps, CLIFF_SET, CAP, false)
	cliffs.set_cells_terrain_connect(bodies, CLIFF_SET, WALL, false)
	cliffs.set_cells_terrain_connect(_feet(), CLIFF_SET, FOOT, false)
	var atlas_of := {}
	for entry: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string(TILE_LIST)) as Dictionary)["tiles"]:
		atlas_of[entry["label"]] = Vector2i(int(entry["atlas"][0]), int(entry["atlas"][1]))
	for cell: Vector2i in HAND_PLACED:
		cliffs.set_cell(cell, 0, atlas_of[HAND_PLACED[cell]])

	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := Vector2(SPAWN_CELL) * CELL + Vector2(CELL, CELL) * 0.5
	definition.set(&"map_id", "cliff-lab")
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", columns)
	definition.set(&"rows", rows)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	root.add_child(definition)
	var marker := Node2D.new()
	marker.name = "player-spawn"
	marker.y_sort_enabled = true
	marker.position = spawn
	root.add_child(marker)

	for child in root.get_children():
		child.owner = root
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, LAB_PATH)
	root.free()
	return err


## The cell under each wall's lowest cell, where the wall's foot goes.
func _feet() -> Array[Vector2i]:
	var walls := _cells("w")
	var feet: Array[Vector2i] = []
	for cell in walls:
		var below := cell + Vector2i.DOWN
		var last_of_45 := HAND_PLACED.has(cell) and String(HAND_PLACED[cell]).begins_with("45")
		if not walls.has(below) and not last_of_45 and below.y < PLAN.size() and PLAN[below.y][below.x] == ".":
			feet.append(below)
	return feet


func _cells(mark: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in PLAN.size():
		for x in PLAN[y].length():
			if PLAN[y][x] == mark:
				cells.append(Vector2i(x, y))
	return cells
