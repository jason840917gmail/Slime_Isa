extends RefCounted
## Animated water and water life (docs/godot/specs/water.md).
## - The mask has one texel per tile: r = 1 on `water` (shallow), g = 1 on `deep-water`, black
##   elsewhere; a world without water gets no surface.
## - level-1: 204 shallow and 58 deep tiles; the WaterSurface quad is the ground layer's child (drawn
##   right after its tiles, z -2), below the underwater life (z -2, y-sorted after the ground), the
##   world-sorted decals (z -1: lily pads, bubbles) and the entities (z 0: reeds).
## - Travel (Main.travel_to) frees the old world's surface with its ground layer and mounts a new
##   one for the next world: gloop-forest has 181 deep tiles and no shallow ones, so both texture
##   slots hold the deep-water sheet.
## - level-1's 65 water-life instances play their looping `object.water-life.idle` clip with the
##   authored tint and alpha (fish #b9dcef at 0.72, kelp #7ea4bf at 0.5, waterweed #a9d2e3 at 0.6,
##   fish shadows 0.75, bubbles 0.9).

const TestContext := preload("res://tests/lib/test_context.gd")
const WaterSurface := preload("res://game/world/water_surface.gd")

const TERRAIN_TILESET_PATH := "res://game/world/terrain_tileset.tres"
const WATER_SHADER_PATH := "res://game/world/water_surface.gdshader"
const LEVEL1_SHALLOW_TILES := 204
const LEVEL1_DEEP_TILES := 58
const LEVEL1_WATER_LIFE := 65
const GLOOP_FOREST_DEEP_TILES := 181
const IDLE_CLIP := &"object.water-life.idle"
const WATER_LIFE_SCENE_PREFIX := "water-life--"
## Phaser presentation per water-life scene (scene JSON `tint`, `alpha`, depth band):
## [name prefix, tint, alpha, absolute z_index].
const PRESENTATION := [
	["fish-", "#b9dcef", 0.72, -2],
	["deep-fish-shadow-", "#ffffff", 0.75, -2],
	["kelp-", "#7ea4bf", 0.5, -2],
	["waterweed-", "#a9d2e3", 0.6, -2],
	["lilypad-", "#ffffff", 1.0, -1],
	["frog-lilypad", "#ffffff", 1.0, -1],
	["bubbles", "#ffffff", 0.9, -1],
	["reeds-", "#ffffff", 1.0, 0],
]


func test_mask_marks_shallow_and_deep_tiles(t: TestContext) -> void:
	var tile_set := load(TERRAIN_TILESET_PATH) as TileSet
	if not t.check(tile_set != null, "no terrain tile set at %s" % TERRAIN_TILESET_PATH):
		return
	var sources := _sources_by_tile_id(tile_set)
	for tile_id: String in ["water", "deep-water", "grass-a"]:
		if not t.check(sources.has(tile_id), "terrain tile set has no '%s' source" % tile_id):
			return
	# 5 x 4: grass border, shallow at (1,1) (2,1) (1,2), deep at (3,1) (2,2) (3,2).
	var rows: Array[String] = [".....", ".~~D.", ".~DD.", "....."]
	var layer := _layer(t, tile_set, sources, rows)
	var surface := WaterSurface.mount(layer)
	if not t.check(surface != null, "no water surface on a layer with water"):
		return
	t.equal(surface.get_parent(), layer, "surface parent")
	t.equal(String(surface.name), WaterSurface.NODE_NAME, "surface name")
	t.equal(surface.columns, 5, "mask columns")
	t.equal(surface.rows, 4, "mask rows")
	t.equal(surface.shallow_cells, 3, "shallow cells")
	t.equal(surface.deep_cells, 3, "deep cells")
	var codes := {".": Color(0, 0, 0, 1), "~": Color(1, 0, 0, 1), "D": Color(0, 1, 0, 1)}
	for y in rows.size():
		for x in rows[y].length():
			t.equal(surface.mask_image.get_pixel(x, y), codes[rows[y][x]], "mask texel (%d, %d)" % [x, y])
	t.equal(surface.kind_at(1, 1), WaterSurface.Kind.SHALLOW, "kind at (1, 1)")
	t.equal(surface.kind_at(3, 2), WaterSurface.Kind.DEEP, "kind at (3, 2)")
	t.equal(surface.kind_at(0, 0), WaterSurface.Kind.NONE, "kind at (0, 0)")
	# Water spans tiles (1,1)-(3,2); one tile of margin, clamped to the grid.
	t.equal(surface.water_rect, Rect2(0, 0, 5 * 64, 4 * 64), "drawn rectangle")
	var shader_material := surface.material as ShaderMaterial
	if t.check(shader_material != null, "the surface has no ShaderMaterial"):
		t.equal(shader_material.shader.resource_path, WATER_SHADER_PATH, "shader")
		t.equal(shader_material.get_shader_parameter(&"grid_size"), Vector2(5, 4), "grid_size uniform")
		t.equal(shader_material.get_shader_parameter(&"tile_size"), 64.0, "tile_size uniform")
		t.equal(shader_material.get_shader_parameter(&"texture_period"), 1216.0, "texture_period uniform")
		t.equal(shader_material.get_shader_parameter(&"shallow_texture"), _source_texture(tile_set, sources["water"]), "shallow texture = the water sheet")
		t.equal(shader_material.get_shader_parameter(&"deep_texture"), _source_texture(tile_set, sources["deep-water"]), "deep texture = the deep-water sheet")
	t.equal(WaterSurface.mount(layer), surface, "a second mount returns the same surface")
	var dry := _layer(t, tile_set, sources, ["...", "..."])
	t.check(WaterSurface.mount(dry) == null, "a layer without water got a surface")
	t.equal(dry.get_node_or_null(NodePath(WaterSurface.NODE_NAME)), null, "a dry layer has no WaterSurface child")


func test_level1_surface_covers_the_water_tiles_in_draw_order(t: TestContext) -> void:
	var ground := t.world().ground_layer
	if not t.check(ground != null, "no ground layer"):
		return
	var surface := ground.get_node_or_null(NodePath(WaterSurface.NODE_NAME)) as WaterSurface
	if not t.check(surface != null, "level-1's ground layer has no WaterSurface"):
		return
	t.equal(surface.shallow_cells, LEVEL1_SHALLOW_TILES, "shallow tiles")
	t.equal(surface.deep_cells, LEVEL1_DEEP_TILES, "deep tiles")
	t.equal(surface.kind_at(27, 0), WaterSurface.Kind.SHALLOW, "the river at (27, 0) is shallow")
	t.equal(surface.kind_at(8, 40), WaterSurface.Kind.DEEP, "the lake centre (8, 40) is deep")
	t.equal(surface.kind_at(9, 43), WaterSurface.Kind.NONE, "the lake island (9, 43) is dry")
	t.equal(surface.kind_at(0, 0), WaterSurface.Kind.NONE, "(0, 0) is dry")
	var mismatches := 0
	for cell: Vector2i in ground.get_used_cells():
		var tile_id: Variant = ground.get_cell_tile_data(cell).get_custom_data("tile_id")
		var expected := WaterSurface.Kind.NONE
		if tile_id == "water":
			expected = WaterSurface.Kind.SHALLOW
		elif tile_id == "deep-water":
			expected = WaterSurface.Kind.DEEP
		if surface.kind_at(cell.x, cell.y) != expected:
			mismatches += 1
		elif expected != WaterSurface.Kind.NONE and not surface.water_rect.encloses(Rect2(Vector2(cell) * 64.0, Vector2(64, 64))):
			t.fail("the drawn rectangle %s misses water tile %s" % [surface.water_rect, cell])
	t.equal(mismatches, 0, "mask texels that differ from the ground's tiles")
	# Draw order: the surface draws with the ground layer's z, right after its tiles.
	var ground_z := _absolute_z(ground)
	t.equal(ground_z, -2, "ground layer z")
	t.equal(_absolute_z(surface), ground_z, "surface z (same as the ground, drawn after its tiles)")
	t.check(surface.visible and surface.is_visible_in_tree(), "the surface is hidden")
	var life := _water_life(t.world().world_root)
	var below := 0
	for root: Node2D in life:
		var visual := root.get_node_or_null(^"Visual") as Sprite2D
		if visual == null:
			continue
		var z := _absolute_z(visual)
		if z == ground_z:
			below += 1
			# Same z as the surface: the world y-sort puts it after the ground layer (y 0) and so
			# after the surface, which is drawn with the ground.
			t.check(visual.global_position.y > ground.global_position.y,
				"%s sorts before the ground layer (y %.1f)" % [root.name, visual.global_position.y])
		else:
			t.check(z > ground_z, "%s draws below the water surface (z %d)" % [root.name, z])
	t.check(below > 0, "no underwater life in level-1")


func test_level1_water_life_plays_with_phaser_presentation(t: TestContext) -> void:
	var life := _water_life(t.world().world_root)
	t.equal(life.size(), LEVEL1_WATER_LIFE, "water-life instances in level-1")
	var before := {}
	for root: Node2D in life:
		var player := root.get_node_or_null(^"AmbientAnimation") as AnimationPlayer
		var visual := root.get_node_or_null(^"Visual") as Sprite2D
		if not t.check(player != null and visual != null, "%s has no AmbientAnimation or Visual" % root.name):
			continue
		t.check(player.is_playing(), "%s: the ambient clip is not playing" % root.name)
		t.equal(player.current_animation, String(IDLE_CLIP), "%s clip" % root.name)
		_check_presentation(t, root, visual)
		before[root] = [player.current_animation_position, visual.frame, visual.position]
	var started := Time.get_ticks_msec()
	await t.steps(70)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	var frozen: PackedStringArray = []
	for root: Node2D in before:
		var player := root.get_node(^"AmbientAnimation") as AnimationPlayer
		var visual := root.get_node(^"Visual") as Sprite2D
		var was: Array = before[root]
		var length := player.get_animation(IDLE_CLIP).length
		var advanced := fposmod(player.current_animation_position - float(was[0]), length)
		t.check(advanced > 0.5 * minf(elapsed, length * 0.5), "%s: the clip advanced %.2f s in %.2f s" % [root.name, advanced, elapsed])
		# Every clip changes its frame at least every 0.34 s except the frog, which holds a frame
		# for up to 2.8 s between blinks.
		var moved: bool = visual.frame != int(was[1]) or visual.position != (was[2] as Vector2)
		if not moved and not _scene_name(root).begins_with("frog-lilypad"):
			frozen.append(String(root.name))
	t.check(frozen.is_empty(), "water life that did not change frame or position in %.2f s: %s" % [elapsed, ", ".join(frozen)])


func test_travel_rebuilds_the_surface_for_the_next_world(t: TestContext) -> void:
	var old_surface := t.world().ground_layer.get_node_or_null(NodePath(WaterSurface.NODE_NAME))
	if not t.check(old_surface != null, "level-1 has no WaterSurface"):
		return
	if not t.check(t.main.travel_to("gloop-forest", "west"), "travel to gloop-forest was refused"):
		return
	var travelled := await t.until(func() -> bool: return t.world().map_id() == "gloop-forest" and t.player() != null, 3000.0, 6000.0)
	if not t.check(travelled, "the player did not reach gloop-forest"):
		return
	await t.steps(2)
	t.check(not is_instance_valid(old_surface), "level-1's WaterSurface outlived its world")
	var ground := t.world().ground_layer
	var surface := ground.get_node_or_null(NodePath(WaterSurface.NODE_NAME)) as WaterSurface
	if not t.check(surface != null, "gloop-forest's ground layer has no WaterSurface"):
		return
	t.equal(surface.shallow_cells, 0, "gloop-forest shallow tiles")
	t.equal(surface.deep_cells, GLOOP_FOREST_DEEP_TILES, "gloop-forest deep tiles")
	var shader_material := surface.material as ShaderMaterial
	t.equal(shader_material.get_shader_parameter(&"shallow_texture"), shader_material.get_shader_parameter(&"deep_texture"),
		"a deep-only world samples the deep sheet in both slots")
	t.equal(t.tree.root.find_children(WaterSurface.NODE_NAME, "", true, false).size(), 1, "WaterSurface nodes in the tree")


# --- helpers -----------------------------------------------------------------------------------

func _check_presentation(t: TestContext, root: Node2D, visual: Sprite2D) -> void:
	var scene := _scene_name(root)
	for entry: Array in PRESENTATION:
		if not scene.begins_with(String(entry[0])):
			continue
		var expected := Color(String(entry[1]), float(entry[2]))
		var actual := visual.self_modulate
		t.check(actual.is_equal_approx(expected), "%s (%s): self_modulate %s, Phaser tint/alpha %s" % [root.name, scene, actual, expected])
		t.equal(_absolute_z(visual), int(entry[3]), "%s (%s) z" % [root.name, scene])
		return
	t.fail("%s: unknown water-life scene '%s'" % [root.name, scene])


## Instance roots of `object.water-life.*` scenes under `root`, in tree order.
func _water_life(root: Node) -> Array[Node2D]:
	var found: Array[Node2D] = []
	if root == null:
		return found
	_collect_water_life(root, found)
	return found


func _collect_water_life(node: Node, found: Array[Node2D]) -> void:
	if node is Node2D and node.scene_file_path.get_file().begins_with(WATER_LIFE_SCENE_PREFIX):
		found.append(node as Node2D)
		return
	for child: Node in node.get_children():
		_collect_water_life(child, found)


## "fish-koi-lane" for an instance of res://game/scenes/objects/water-life--fish-koi-lane.tscn.
static func _scene_name(node: Node) -> String:
	return node.scene_file_path.get_file().get_basename().trim_prefix(WATER_LIFE_SCENE_PREFIX)


## The z the renderer uses: z_index plus the parent's absolute z while z_as_relative.
static func _absolute_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		var canvas_item := node as CanvasItem
		z += canvas_item.z_index
		if not canvas_item.z_as_relative:
			break
		node = node.get_parent()
	return z


## Terrain tile id -> atlas source id (from the `tile_id` custom data of the source's first tile).
static func _sources_by_tile_id(tile_set: TileSet) -> Dictionary:
	var result := {}
	for index in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(index)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.get_tiles_count() == 0:
			continue
		var tile_data := source.get_tile_data(source.get_tile_id(0), 0)
		var tile_id: Variant = tile_data.get_custom_data("tile_id")
		if tile_id is String and not result.has(tile_id):
			result[tile_id] = source_id
	return result


static func _source_texture(tile_set: TileSet, source_id: int) -> Texture2D:
	return (tile_set.get_source(source_id) as TileSetAtlasSource).texture


## A TileMapLayer under the test's main scene from `rows` ("~" water, "D" deep-water, "." grass-a),
## with the converter's `columns` / `rows` metadata.
func _layer(t: TestContext, tile_set: TileSet, sources: Dictionary, rows: Array[String]) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	var ids := {"~": "water", "D": "deep-water", ".": "grass-a"}
	for y in rows.size():
		for x in rows[y].length():
			layer.set_cell(Vector2i(x, y), int(sources[ids[rows[y][x]]]), Vector2i.ZERO)
	layer.set_meta("columns", rows[0].length())
	layer.set_meta("rows", rows.size())
	t.main.add_child(layer)
	return layer
