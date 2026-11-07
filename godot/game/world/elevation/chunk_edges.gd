extends RefCounted
## What a chunk world's cliffs see past its own edges (docs/godot/ELEVATION.md "Across chunk
## lines"): the paint of the chunk worlds around it on the atlas grid, a few cells deep, so a hill
## or a mountain running across a chunk line is built the same on both sides of it: its walls, 45°
## faces, corners and shadows (owner, 2026-11-06: one mountain over several chunks, as in Zelda).
##
## A chunk world is still loaded alone. Its neighbours (game/data/world-chunks.json, chunk "A1" the
## north-west one, in any region) are read from their scene files, never instanced
## (`PackedScene.get_state`, as BorderCrossing reads a way back), and each read is kept until its
## file changes. Only what the cliffs are built from is read: the `elevation` layer's levels (a
## stairs or ramp cell as the ground it leads down to: flights are not built past the edge), the
## ground under them and the wall styles painted on `cliffs`.
##
## Owner: world (elevation).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")
const BorderCrossing := preload("res://game/world/crossings/border_crossing.gd")

## Cells read past an edge that has a neighbour: north and south as deep as the tallest wall
## reaches (a wall hanging in from the north, a top in front of a wall hiding its foot from the
## south), west and east enough for a 45° face, a round corner, a fold and a wall's shadow.
const NORTH := Elevation.MAX_ROWS_ABOVE
const SOUTH := Elevation.MAX_ROWS_ABOVE
const SIDE := 4
## The eight neighbours, as steps on the atlas grid.
const STEPS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

## Scene path -> {"modified", "levels", "grounds", "sources", "styles"} (the scene's own cells).
static var _reads: Dictionary = {}


## The atlas grid cell of chunk world `root` (its metadata `world_map_chunk`: "C4" -> (2, 3)); null
## when it is no chunk world.
static func chunk_cell_of(root: Node) -> Variant:
	if root == null or not root.has_meta(&"world_map_chunk") or not root.has_meta(&"world_map_chunk_of"):
		return null
	return BorderCrossing.chunk_cell(str(root.get_meta(&"world_map_chunk")))


## Where chunk world `root`'s north-west corner lies on the overworld (world units); null when it is
## no chunk world.
static func overworld_corner(root: Node) -> Variant:
	var at: Variant = chunk_cell_of(root)
	var units := BorderCrossing.chunk_units()
	if not at is Vector2i or not is_finite(units):
		return null
	return Vector2(at as Vector2i) * units


## The scenes of the chunk worlds around grid cell `at`, in any region: step -> scene path.
static func neighbours(at: Vector2i) -> Dictionary:
	var out := {}
	var table := WorldChunks.table()
	for world: String in table:
		var chunk_names: Dictionary = (table[world] as Dictionary).get("chunks", {})
		for chunk_world: String in chunk_names:
			var cell: Variant = BorderCrossing.chunk_cell(str(chunk_names[chunk_world]))
			if not cell is Vector2i:
				continue
			var step: Vector2i = (cell as Vector2i) - at
			if STEPS.has(step):
				out[step] = WorldChunks.scene_path(chunk_world)
	return out


## The paint past chunk world `root`'s edges, in its own cells (the chunk is `tiles` cells big):
## {"rect": Rect2i (the chunk and the margins read, its edges with no neighbour not widened),
## "levels": {cell: level}, "grounds": {cell: ground}, "sources": {ground: its source id in the
## terrain tile set every ground layer uses},
## "styles": {cell: wall style}, "signature": int (changes when any of them does)}. Only cells
## outside the chunk are listed. A margin cell no neighbour covers (a corner past the overworld's
## edge) takes the nearest covered cell's paint across the line. {} when `root` is no chunk world
## or has no neighbour.
static func read(root: Node, tiles: Vector2i) -> Dictionary:
	var at: Variant = chunk_cell_of(root)
	if not at is Vector2i or tiles.x <= 0 or tiles.y <= 0:
		return {}
	var around := neighbours(at as Vector2i)
	if around.is_empty():
		return {}
	var west := SIDE if around.has(Vector2i(-1, 0)) else 0
	var east := SIDE if around.has(Vector2i(1, 0)) else 0
	var north := NORTH if around.has(Vector2i(0, -1)) else 0
	var south := SOUTH if around.has(Vector2i(0, 1)) else 0
	var rect := Rect2i(-west, -north, tiles.x + west + east, tiles.y + north + south)
	var own := Rect2i(Vector2i.ZERO, tiles)
	var levels := {}
	var grounds := {}
	var sources := {}
	var styles := {}
	var covered := {}
	for step: Vector2i in around:
		var part := rect.intersection(Rect2i(step * tiles, tiles))
		if not part.has_area():
			continue
		var paint := _paint_of(str(around[step]))
		if paint.is_empty():
			continue
		var shift := step * tiles
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				var cell := Vector2i(x, y)
				var theirs := cell - shift
				covered[cell] = true
				var table_levels: Dictionary = paint["levels"]
				if table_levels.has(theirs):
					levels[cell] = table_levels[theirs]
				var table_grounds: Dictionary = paint["grounds"]
				if table_grounds.has(theirs):
					grounds[cell] = table_grounds[theirs]
				var table_styles: Dictionary = paint["styles"]
				if table_styles.has(theirs):
					styles[cell] = table_styles[theirs]
		var their_sources: Dictionary = paint["sources"]
		for ground: String in their_sources:
			if not sources.has(ground):
				sources[ground] = their_sources[ground]
	# Corners no chunk covers: the paint across the nearer line, as a map border does.
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if own.has_point(cell) or covered.has(cell):
				continue
			var near := Vector2i(clampi(x, 0, tiles.x - 1), y)
			if not covered.has(near):
				near = Vector2i(x, clampi(y, 0, tiles.y - 1))
			if not covered.has(near):
				continue
			if levels.has(near):
				levels[cell] = levels[near]
			if grounds.has(near):
				grounds[cell] = grounds[near]
			if styles.has(near):
				styles[cell] = styles[near]
	return {
		"rect": rect, "levels": levels, "grounds": grounds, "sources": sources, "styles": styles,
		"signature": _signature(rect, levels, grounds, styles),
	}


## Forgets every scene read (a tool that rewrote chunks in one go).
static func forget() -> void:
	_reads.clear()


## The cliff paint of the chunk world saved at `path`, in its own cells; {} when it cannot be read.
## Kept until the file's modified time changes.
static func _paint_of(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	var modified := FileAccess.get_modified_time(path)
	var known: Dictionary = _reads.get(path, {})
	if not known.is_empty() and int(known["modified"]) == modified:
		return known
	var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		return {}
	# The world's own layers, rebuilt as loose nodes under one holder, so Elevation's readers find
	# them beside each other as they do in a world.
	var holder := Node.new()
	var state := scene.get_state()
	for index: int in state.get_node_count():
		if state.get_node_type(index) != "TileMapLayer" or str(state.get_node_path(index, true)) != ".":
			continue
		var layer := TileMapLayer.new()
		for p: int in state.get_node_property_count(index):
			match str(state.get_node_property_name(index, p)):
				"tile_set":
					layer.tile_set = state.get_node_property_value(index, p) as TileSet
				"tile_map_data":
					layer.tile_map_data = state.get_node_property_value(index, p) as PackedByteArray
		if layer.tile_set == null:
			layer.free()
			continue
		holder.add_child(layer)
	var paint := {"modified": modified, "levels": {}, "grounds": {}, "sources": {}, "styles": {}}
	var any := holder.get_child(0) as TileMapLayer if holder.get_child_count() > 0 else null
	if any != null:
		paint["levels"] = Elevation.painted_levels(any)
		paint["styles"] = Elevation.painted_wall_styles(any)
		var ground := Elevation.find_ground_in(holder)
		if ground != null:
			_read_grounds(ground, paint["grounds"], paint["sources"])
	holder.free()
	_reads[path] = paint
	return paint


## Each ground cell's ground name (as Elevation names its own) and each ground's source id.
static func _read_grounds(ground: TileMapLayer, names: Dictionary, sources: Dictionary) -> void:
	var by_source := {}
	var has_ids := ground.tile_set.has_custom_data_layer_by_name(Elevation.TILE_ID_DATA_LAYER)
	for cell: Vector2i in ground.get_used_cells():
		var source_id := ground.get_cell_source_id(cell)
		if not by_source.has(source_id):
			var data := ground.get_cell_tile_data(cell)
			var tile_id := str(data.get_custom_data(Elevation.TILE_ID_DATA_LAYER)) if data != null and has_ids else ""
			var name_of_ground := TerrainMaterials.ground_of(tile_id)
			by_source[source_id] = name_of_ground
			if name_of_ground != "" and not sources.has(name_of_ground):
				sources[name_of_ground] = source_id
		names[cell] = by_source[source_id]


## A hash of the margins' paint that does not depend on the order cells were read in.
static func _signature(rect: Rect2i, levels: Dictionary, grounds: Dictionary, styles: Dictionary) -> int:
	var lines := PackedStringArray()
	for cell: Vector2i in levels:
		lines.append("l%d,%d=%s" % [cell.x, cell.y, str(levels[cell])])
	for cell: Vector2i in grounds:
		lines.append("g%d,%d=%s" % [cell.x, cell.y, str(grounds[cell])])
	for cell: Vector2i in styles:
		lines.append("s%d,%d=%s" % [cell.x, cell.y, str(styles[cell])])
	lines.sort()
	return ("%s|%s" % [str(rect), "|".join(lines)]).hash()
