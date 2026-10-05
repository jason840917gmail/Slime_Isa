extends RefCounted
## Hand-made terrain edges (docs/godot/TERRAIN_LAB.md, game/world/terrain_edges/).
## - Every converted terrain tile id is either a ground with edges (TerrainMaterials.TILE_GROUNDS)
##   or one of the hard-edged walls and floors, and every ground but water has its edge art.
## - Dual grid: a corner where grounds meet gets the lowest ground's full tile on level 0 and each
##   higher ground's edge tile on the next level, index = TL + 2 TR + 4 BL + 8 BR over the cells
##   that stack at least that high; corners with one ground, a hard-edged tile or the map border
##   get nothing.
## - Shores: water is the lowest ground and fills with the water shader (the water surface's own
##   parameters); land edge tiles draw over it.
## - level-1: the edges are the ground layer's child after the water surface (drawn over it).

const TestContext := preload("res://tests/lib/test_context.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")
const TerrainMaterials := preload("res://game/world/terrain_edges/terrain_materials.gd")
const WaterSurface := preload("res://game/world/water_surface.gd")

const TERRAIN_TILESET_PATH := "res://generated/resources/terrain_tileset.tres"
## Terrain tiles that keep hard edges, as in Phaser (no natural-ground transition).
const HARD_EDGED := ["rock-wall", "wood-floor", "mushroom-earth-floor", "mushroom-plain-floor", "mushroom-clover-floor"]
## Test map keys -> tile ids.
const KEYS := {".": "grass-a", "s": "sanddessert-ground", "z": "frozen-ground", "~": "water", "r": "rock-wall"}


func test_every_terrain_tile_is_a_ground_or_hard_edged(t: TestContext) -> void:
	var tile_set := load(TERRAIN_TILESET_PATH) as TileSet
	if not t.check(tile_set != null, "no terrain tile set"):
		return
	for tile_id: String in _sources_by_tile_id(tile_set):
		t.check(TerrainMaterials.TILE_GROUNDS.has(tile_id) or tile_id in HARD_EDGED,
			"terrain tile '%s' is neither a ground with edges nor a known hard-edged tile" % tile_id)
	for ground: String in TerrainMaterials.ORDER:
		if ground == TerrainMaterials.WATER:
			continue
		t.check(ResourceLoader.exists(TerrainMaterials.edges_path(ground)), "no edge art for %s" % ground)
		t.check(ResourceLoader.exists(TerrainMaterials.rim_path(ground)), "no rim weights for %s" % ground)
	for ground: String in TerrainMaterials.TILE_GROUNDS.values():
		t.check(TerrainMaterials.order_of(ground) >= 0, "ground %s has no stacking order" % ground)


func test_two_grounds_stack_on_a_dual_grid(t: TestContext) -> void:
	# A 2 x 2 sand patch in grass. Grass stacks higher than sand (ORDER), so grass draws its edge
	# tiles over a sand fill.
	var layer := _layer(t, [
		"......",
		"..ss..",
		"..ss..",
		"......",
	])
	var edges := TerrainEdges.mount(layer)
	if not t.check(edges != null, "no terrain edges"):
		return
	t.equal(edges.get_parent(), layer, "edges parent")
	t.equal(edges.position, Vector2(-32, -32), "half a cell up and left (dual grid)")
	var sand := TerrainMaterials.order_of("sanddessert")
	var grass := TerrainMaterials.order_of("highland")
	t.check(grass > sand, "grass stacks over sand")
	# Corners touching the patch: (2..4) x (1..3); 9 corners, all mixed except the inner one (3, 2).
	t.equal(edges.corners, 8, "mixed corners")
	t.equal(edges.placed, 16, "tiles placed (two levels per mixed corner)")
	# Level 0 holds the lower ground's full tile: sand.
	var level0 := edges.layers[0]
	var level1 := edges.layers[1]
	t.equal(level0.get_cell_source_id(Vector2i(2, 1)), int(edges.sources["sanddessert"]), "level 0 = sand")
	t.equal(level0.get_cell_atlas_coords(Vector2i(2, 1)), Vector2i(3, 3), "level 0 = the full tile (15)")
	# Level 1: grass over the cells that are grass. Corner (2, 1) touches grass at TL, TR, BL and
	# sand at BR: index 1 + 2 + 4 = 7 -> atlas (3, 1).
	t.equal(level1.get_cell_source_id(Vector2i(2, 1)), int(edges.sources["highland"]), "level 1 = grass")
	t.equal(level1.get_cell_atlas_coords(Vector2i(2, 1)), Vector2i(3, 1), "corner (2, 1): grass on TL TR BL")
	# Corner (3, 1): grass TL TR, sand BL BR -> 3 -> (3, 0).
	t.equal(level1.get_cell_atlas_coords(Vector2i(3, 1)), Vector2i(3, 0), "corner (3, 1): grass on top")
	# The patch's middle corner and the far grass get nothing.
	t.equal(level0.get_cell_source_id(Vector2i(3, 2)), -1, "inner sand corner is plain")
	t.equal(level0.get_cell_source_id(Vector2i(1, 1)), -1, "grass-only corner is plain")
	layer.queue_free()


func test_three_grounds_and_hard_edges(t: TestContext) -> void:
	# Corner (1, 1) touches grass (TL), snow (TR, BR) and sand (BL); the rock wall at (4, 1) touches
	# corners (4..5, 1..2).
	var layer := _layer(t, [
		".z....",
		"sz..r.",
		"ss....",
	])
	var edges := TerrainEdges.mount(layer)
	if not t.check(edges != null, "no terrain edges"):
		return
	var corner := Vector2i(1, 1)   # cells (0,0) grass, (1,0) snow, (0,1) sand, (1,1) snow
	var stack := [TerrainMaterials.order_of("sanddessert"), TerrainMaterials.order_of("highland"), TerrainMaterials.order_of("frozen")]
	t.check(stack[0] < stack[1] and stack[1] < stack[2], "sand < grass < snow")
	t.equal(edges.layers[0].get_cell_source_id(corner), int(edges.sources["sanddessert"]), "level 0: the lowest (sand)")
	t.equal(edges.layers[1].get_cell_source_id(corner), int(edges.sources["highland"]), "level 1: grass")
	# Grass level covers the cells at least as high as grass: grass TL, snow TR and BR -> 1 + 2 + 8 = 11.
	t.equal(edges.layers[1].get_cell_atlas_coords(corner), Vector2i(3, 2), "grass covers grass and snow cells")
	t.equal(edges.layers[2].get_cell_source_id(corner), int(edges.sources["frozen"]), "level 2: snow")
	# Snow level: TR and BR -> 2 + 8 = 10.
	t.equal(edges.layers[2].get_cell_atlas_coords(corner), Vector2i(2, 2), "snow covers the snow cells")
	# The rock wall keeps hard edges: none of its four corners get a tile.
	for wall_corner: Vector2i in [Vector2i(4, 1), Vector2i(5, 1), Vector2i(4, 2), Vector2i(5, 2)]:
		t.equal(edges.layers[0].get_cell_source_id(wall_corner), -1, "corner %s by the wall is plain" % wall_corner)
	layer.queue_free()


func test_shores_fill_with_the_water_shader(t: TestContext) -> void:
	var layer := _layer(t, [
		"......",
		".~~~s.",
		".~~~s.",
		"......",
	])
	var surface := WaterSurface.mount(layer)
	var edges := TerrainEdges.mount(layer)
	if not t.check(surface != null and edges != null, "no water surface or edges"):
		return
	t.check(surface.get_index() < edges.get_index(), "the edges draw after the water surface")
	t.check(edges.sources.has(TerrainMaterials.WATER), "no water fill source")
	var corner := Vector2i(1, 1)   # grass TL TR BL, water BR
	t.equal(edges.layers[0].get_cell_source_id(corner), int(edges.sources[TerrainMaterials.WATER]), "level 0: water fill")
	t.equal(edges.layers[1].get_cell_atlas_coords(corner), Vector2i(3, 1), "level 1: grass on TL TR BL (7)")
	var fill := edges.layers[0].tile_set.get_source(int(edges.sources[TerrainMaterials.WATER])) as TileSetAtlasSource
	var water_material := fill.get_tile_data(Vector2i.ZERO, 0).material as ShaderMaterial
	var surface_material := surface.material as ShaderMaterial
	if t.check(water_material != null and surface_material != null, "water fill has no ShaderMaterial"):
		t.equal(water_material.get_shader_parameter(&"water_mask"), surface_material.get_shader_parameter(&"water_mask"),
			"the fill reads the surface's own mask")
		t.equal(water_material.get_shader_parameter(&"grid_size"), surface_material.get_shader_parameter(&"grid_size"), "grid size")
	# The sand strip (4, 1)-(4, 2) is a shore: corner (4, 2) has water TL and BL, sand TR and BR.
	t.equal(edges.layers[0].get_cell_source_id(Vector2i(4, 2)), int(edges.sources[TerrainMaterials.WATER]), "sand shore over water")
	layer.queue_free()


func test_level_1_mounts_edges_over_the_water(t: TestContext) -> void:
	var ground: TileMapLayer = t.world().ground_layer
	if not t.check(ground != null, "level-1 has no ground layer"):
		return
	var edges := ground.get_node_or_null(NodePath(TerrainEdges.NODE_NAME)) as TerrainEdges
	var surface := ground.get_node_or_null(NodePath(WaterSurface.NODE_NAME))
	if not t.check(edges != null and surface != null, "level-1 lacks its edges or water surface"):
		return
	t.check(surface.get_index() < edges.get_index(), "level-1's edges draw after its water")
	t.check(edges.corners > 500, "level-1 has few edge corners (%d)" % edges.corners)
	for ground_name: String in ["water", "sanddessert", "highland", "forest-moss", "forest-floor", "town-cobble", "amberleaf"]:
		t.check(edges.sources.has(ground_name), "level-1 edges lack %s" % ground_name)


# --- helpers ------------------------------------------------------------------------------------

func _layer(t: TestContext, rows: Array) -> TileMapLayer:
	var tile_set := load(TERRAIN_TILESET_PATH) as TileSet
	var sources := _sources_by_tile_id(tile_set)
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	for y in rows.size():
		var line: String = rows[y]
		for x in line.length():
			layer.set_cell(Vector2i(x, y), int(sources[KEYS[line[x]]]), Vector2i(posmod(x, 19), posmod(y, 19)))
	layer.set_meta("columns", (rows[0] as String).length())
	layer.set_meta("rows", rows.size())
	t.main.add_child(layer)
	return layer


func _sources_by_tile_id(tile_set: TileSet) -> Dictionary:
	var out := {}
	for i in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(i)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.get_tiles_count() == 0:
			continue
		var tile_id := str(source.get_tile_data(source.get_tile_id(0), 0).get_custom_data("tile_id"))
		if not tile_id.is_empty() and not out.has(tile_id):
			out[tile_id] = source_id
	return out
