extends RefCounted
## The painted fences (docs/godot/FENCES.md) on ordinary and elevated ground, in Fence Park
## (scripts/maps/build-fence-park.py) and in a flat world built here: each neighbour pair draws and
## collides once, as a thin band at the rails' feet; a post collides as wide as its kit draws it; a
## lone tile is two posts along its arrow; painting does not change elevation rims; hops, drops and
## landings do not pass a fence. Dungeon dividers' gates: a shut gate closes its whole cell (eye and
## pen, east-west and north-south lines, beside a lone tile), opens when its block is out of the way,
## sits where the scenes paint it in the palette, and takes a dungeon small key when asked for one.

const TestContext := preload("res://tests/lib/test_context.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const LevelCode := preload("res://game/world/elevation/level_code.gd")
## How near its place a post's foot read back from the mesh's colours must be.
const FOOT_READ_PX := LevelCode.DY_SPAN / 255.0 * 0.5 + 1.0
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const Fences := preload("res://game/world/fences/fences.gd")
const FenceLayer := preload("res://game/world/fences/fence_layer.gd")
const DividerGate := preload("res://game/dungeon/divider_gate.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const Services := preload("res://game/shared/services.gd")
const WorldDefinition := preload("res://game/scripts/world_definition.gd")
const FENCE_TILESET := preload("res://game/world/fences/fence_tileset.tres")

const MAP_ID := "fence-park"
## Fence Park's authored square: fence links use cell centers, with an east drop opening.
const SQUARE_SOUTH_LINK := 8.5 * 64.0
const SQUARE_EAST_LINK := 11.5 * 64.0
const SQUARE_EAST := 12 * 64.0
const GAP_Y := 5 * 64.0
## The band (game-constants.json `fences`): its top and bottom above the posts' foot line, and the
## half width of a north-south band. A post's rect is as wide as its kit's post
## (asset/MAPS/fences/<style>.json `posts.half_width`: `_post_half`). The player's collision rect:
## 30 wide.
const BAND_ABOVE := 10.0
const BAND_BELOW := 2.0
const SIDE_HALF := 7.0
const BODY_HALF_WIDTH := 15.0
## The fence palette's tiles (scripts/art/build-fence-paint-tiles.py): the Lair divider's column
## (all neighbours, the east and west arrows) and the gates, where the Lair's scenes paint them.
const DIVIDER := Vector2i(7, 0)
const DIVIDER_EAST := Vector2i(7, 3)
const DIVIDER_WEST := Vector2i(7, 7)
const EYE_GATE := Vector2i(8, 0)
const PEN_GATE := Vector2i(9, 0)
## The Lair's rooms with divider gates (game/scenes/worlds/rooms/fatty-lair/).
## (the Old Armoury moved out of the Lair, 2026-10-19: res://game/scenes/worlds/rooms/d4/slimeshire-old-armoury.tscn)
const GATE_ROOMS: PackedStringArray = ["c2-weigh-house", "../../slimeshire-old-armoury", "r5-eye-hall", "r7-bell-bridge"]
const ROOMS_DIR := "res://game/scenes/worlds/rooms/fatty-lair/%s.tscn"
## How far beside a gate's middle the hole a shut gate used to leave was (between its old 52-unit body
## and the post's 14-unit rect, 31 units wide: the 30-wide slime fit through).
const OLD_HOLE := 41.5


## A Fences node with its pieces holder, for building cells without a world.
func _bare_fences(columns: int, rows: int) -> Fences:
	var fences := Fences.new()
	fences.grid = ElevationGrid.build(columns, rows, {}, {})
	fences.cell = 64.0
	fences._pieces = Node2D.new()
	fences._pieces.name = Fences.PIECES_NAME
	fences.add_child(fences._pieces)
	return fences


func test_constants_are_the_band(t: TestContext) -> void:
	t.equal(Fences.setting("bandAbove"), BAND_ABOVE, "fences.bandAbove")
	t.equal(Fences.setting("bandBelow"), BAND_BELOW, "fences.bandBelow")
	t.equal(Fences.setting("sideHalfWidth"), SIDE_HALF, "fences.sideHalfWidth")


func test_lone_tile_is_two_posts_the_way_its_arrow_points(t: TestContext) -> void:
	# Each arrow, and the all-neighbour tile (east): the second post half a cell along it.
	var expected := {
		0: Vector2(0.0, -32.0), 1: Vector2(32.0, -32.0), 2: Vector2(32.0, 0.0), 3: Vector2(32.0, 32.0),
		4: Vector2(0.0, 32.0), 5: Vector2(-32.0, 32.0), 6: Vector2(-32.0, 0.0), 7: Vector2(-32.0, -32.0),
		Fences.ALL_NEIGHBORS_DIRECTION: Vector2(32.0, 0.0),
	}
	var raise := Vector2(0.0, -(BAND_ABOVE + BAND_BELOW) * 0.5)
	var foot := Vector2(2.5, 2.5) * 64.0
	for direction: int in expected:
		var label := "lone tile, direction %d" % direction
		var fences := _bare_fences(6, 6)
		fences._add_connected_network({Vector2i(2, 2): {"style": "wood", "direction": direction, "level": 0}},
				MeshData.new(), {})
		fences._build_collision()
		var far: Vector2 = foot + expected[direction]
		t.near_vec(Fences.lone_stub(direction) * 64.0, expected[direction], 0.01, label + ": stub")
		# The drawn posts: its own and the far one.
		var drawn: Array[Vector2] = []
		for piece: MeshInstance2D in fences._pieces.get_children():
			var arrays := piece.mesh.surface_get_arrays(0)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors[0].b > 0.25:
				continue
			var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
			var left := INF
			var right := -INF
			var foot_y := 0.0
			for i in colors.size():
				left = minf(left, vertices[i].x)
				right = maxf(right, vertices[i].x)
				foot_y += vertices[i].y - LevelCode.dy_from(colors[i].g)
			drawn.append(piece.position + Vector2((left + right) * 0.5, foot_y / colors.size()))
		t.equal(drawn.size(), 2, label + ": posts drawn")
		var has_own := false
		var has_far := false
		for point: Vector2 in drawn:
			# a post's foot is read back from its depth in the mesh's colours: half a step of 8 bits off
			# at most (LevelCode: 6 units a step since the walls go up to level 16)
			has_own = has_own or point.distance_to(foot) < FOOT_READ_PX
			has_far = has_far or point.distance_to(far) < FOOT_READ_PX
		t.check(has_own and has_far, label + ": posts not at the cell and %s along the arrow (%s)" % [expected[direction], drawn])
		# Collision: both posts and the band between them, nothing on the other side.
		var body := fences.get_node_or_null("Collision/Level0") as StaticBody2D
		if t.check(body != null, label + ": no collision"):
			t.equal(body.get_child_count(), 3, label + ": two posts and one band")
			t.check(_has_fence_rectangle(body, far + raise, _post_half("wood") * 2.0, BAND_ABOVE - BAND_BELOW, 0.0),
					label + ": the far post's rect")
		t.check(fences.blocks_point(foot + raise, 0), label + ": own post does not block")
		t.check(fences.blocks_point(far + raise, 0), label + ": far post does not block")
		t.check(fences.blocks_point(foot.lerp(far, 0.5) + raise, 0), label + ": the rail between does not block")
		t.check(not fences.blocks_point(foot - (far - foot) + raise, 0), label + ": blocks the other way")
		if direction != 4:
			# (A south stub's band runs down past its own post's foot.)
			t.check(not fences.blocks_point(foot, 0), label + ": blocks below its foot line")
		fences.free()


func test_diagonal_link_collides_as_a_rotated_band(t: TestContext) -> void:
	var fences := _bare_fences(8, 8)
	fences._add_connected_network({
		Vector2i(4, 4): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(5, 5): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
	}, MeshData.new(), {})
	fences._build_collision()
	var body := fences.get_node_or_null("Collision/Level0") as StaticBody2D
	var raise := Vector2(0.0, -(BAND_ABOVE + BAND_BELOW) * 0.5)
	var centre := Vector2(5.0, 5.0) * 64.0 + raise
	if t.check(body != null, "diagonal fence has no collision body"):
		t.equal(body.get_child_count(), 3, "a diagonal link collides as one band and two posts")
		t.check(_has_fence_rectangle(body, centre, 64.0 * sqrt(2.0), BAND_ABOVE - BAND_BELOW, PI * 0.25),
				"the diagonal band runs foot to foot at 45 degrees, raised to the rails' feet")
	var across := Vector2(-1.0, 1.0).normalized()
	t.check(fences.blocks_point(centre, 0), "the diagonal band does not block its middle")
	t.check(fences.blocks_point(centre + across * 3.5, 0), "the diagonal band is thinner than 8")
	t.check(not fences.blocks_point(centre + across * 5.0, 0), "the diagonal band is thicker than 8")
	t.check(fences.blocks_rect(Rect2(centre + Vector2(-20.0, -4.0), Vector2(40.0, 8.0)), 0),
			"a rect over the diagonal band fits")
	t.check(not fences.blocks_rect(Rect2(centre + across * 30.0 - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), 0),
			"a rect clear of the diagonal band does not fit")
	t.check(fences.blocks_sweep(centre - across * 20.0, centre + across * 20.0, 0), "a sweep through the diagonal band passes")
	t.check(not fences.blocks_sweep(centre + across * 6.0 + Vector2(-20.0, -20.0), centre + across * 6.0 + Vector2(20.0, 20.0), 0),
			"a sweep along the band's side is blocked")
	fences.free()


func test_painted_material_does_not_change_with_ground(t: TestContext) -> void:
	var atlas := FENCE_TILESET.get_source(0) as TileSetAtlasSource
	t.equal(atlas.get_tiles_count(), 74, "the palette is 8 styles x (all neighbours + 8 arrows) + 2 divider gate tiles")
	var painted := TileMapLayer.new()
	painted.tile_set = FENCE_TILESET
	painted.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	painted.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0))
	var fences := Fences.new()
	fences.grid = ElevationGrid.build(2, 1, {}, {
		Vector2i(0, 0): "frozen", Vector2i(1, 0): "sanddessert",
	})
	var cells := fences._painted_connections(painted)
	t.equal(cells[Vector2i(0, 0)]["style"], "wood", "snow ground changed the painted wood style")
	t.equal(cells[Vector2i(1, 0)]["style"], "wood", "sand ground changed the painted wood style")
	painted.free()
	fences.free()


func test_connected_fence_tiles_join_only_selected_neighbors(t: TestContext) -> void:
	var cells := {
		Vector2i(4, 4): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(5, 4): {"style": "twig", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
	}
	var links := Fences.connected_links(cells)
	if t.check(links.size() == 1, "adjacent all-neighbor fence cells did not make one shared connection"):
		t.equal(links[0]["from"], Vector2i(4, 4), "the connection start is unstable")
		t.equal(links[0]["to"], Vector2i(5, 4), "the connection end is wrong")
	cells[Vector2i(4, 4)]["direction"] = 2
	cells[Vector2i(5, 4)]["direction"] = 6
	t.equal(Fences.connected_links(cells).size(), 1, "reciprocal direction did not connect")
	cells[Vector2i(4, 4)]["direction"] = 0
	cells[Vector2i(5, 4)]["direction"] = 4
	t.check(Fences.connected_links(cells).is_empty(), "mismatched directions unexpectedly joined")
	# An arrow refuses an all-neighbour neighbour it does not point to.
	cells[Vector2i(5, 4)]["direction"] = Fences.ALL_NEIGHBORS_DIRECTION
	t.check(Fences.connected_links(cells).is_empty(), "an arrow joined an all-neighbour tile it does not point to")
	cells[Vector2i(4, 4)]["direction"] = 2
	t.equal(Fences.connected_links(cells).size(), 1, "an arrow did not join the all-neighbour tile it points to")
	cells = {
		Vector2i(4, 4): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 1},
		Vector2i(5, 5): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 1},
	}
	t.equal(Fences.connected_links(cells).size(), 1, "diagonal fence cells did not connect")
	cells[Vector2i(5, 5)]["level"] = 0
	t.check(Fences.connected_links(cells).is_empty(), "a fence connected across elevation levels")
	cells = {
		Vector2i(4, 4): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(5, 4): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(4, 5): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(5, 5): {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 0},
	}
	t.equal(Fences.connected_links(cells).size(), 4,
			"a 2x2 fence produced doubled diagonal rails over its four sides")


func test_connected_tiles_add_ground_and_elevated_collision_without_changing_rims(t: TestContext) -> void:
	var elevation := t.world().elevation
	var fences := elevation.fences as Fences
	if not t.check(fences != null, "connected fence samples did not mount"):
		return
	var ground_index := fences.grid.cell_index(Vector2i(28, 33))
	var raised_index := fences.grid.cell_index(Vector2i(5, 32))
	t.equal(fences.grid.cell_level[ground_index], 0, "ground fence sample is not on ordinary ground")
	t.equal(fences.grid.cell_level[raised_index], 1, "elevated fence sample lost its raised platform")
	t.equal(fences.grid.cell_level[fences.grid.cell_index(Vector2i(5, 34))], 0,
			"the elevation rim beneath the raised fence changed")
	var ground_body := fences.get_node_or_null("Collision/Level0") as StaticBody2D
	var raised_body := fences.get_node_or_null("Collision/Level1") as StaticBody2D
	if not t.check(ground_body != null and raised_body != null, "fences did not add collision on both levels"):
		return
	# Collision shapes are in the Fences node's space (the Elevation's: rows above the map shift it).
	var raise := Vector2(0.0, -(BAND_ABOVE + BAND_BELOW) * 0.5)
	var ground_from := Vector2(28.5, 33.5) * 64.0
	var ground_to := Vector2(29.5, 33.5) * 64.0
	var raised_from := Vector2(4.5, 32.5) * 64.0
	var raised_to := Vector2(5.5, 32.5) * 64.0
	var shift := fences.global_position
	t.check(_has_fence_rectangle(ground_body, ground_from.lerp(ground_to, 0.5) + raise - shift, 64.0, BAND_ABOVE - BAND_BELOW, 0.0),
			"ground fence link is not one 64 x 8 band, foot to foot, at the rails' feet")
	var painted := Fences.find_layer(elevation.get_parent() as TileMapLayer)
	var post_style := Fences.painted_style(painted, painted.local_to_map(painted.to_local(ground_to)))
	t.check(_has_fence_rectangle(ground_body, ground_to + raise - shift, _post_half(post_style) * 2.0, BAND_ABOVE - BAND_BELOW, 0.0),
			"ground fence post is not as wide as its kit's ('%s') post, 8 tall" % post_style)
	t.check(_has_fence_rectangle(raised_body, raised_from.lerp(raised_to, 0.5) + raise - shift, 64.0, BAND_ABOVE - BAND_BELOW, 0.0),
			"elevated fence link is not one 64 x 8 band")
	var middle := ground_from.lerp(ground_to, 0.5)
	t.check(fences.blocks_point(middle + Vector2(0.0, -BAND_BELOW - 0.5), 0), "the band's bottom edge is too high")
	t.check(fences.blocks_point(middle + Vector2(0.0, -BAND_ABOVE + 0.5), 0), "the band's top edge is too low")
	t.check(not fences.blocks_point(middle + Vector2(0.0, -BAND_BELOW + 1.0), 0), "the band reaches below the rails' feet")
	t.check(not fences.blocks_point(middle + Vector2(0.0, -BAND_ABOVE - 1.0), 0), "the band reaches above its top")
	t.check(fences.blocks_point(raised_from.lerp(raised_to, 0.5) + raise, 1), "elevated fence link does not block")
	t.check(not fences.blocks_point(raised_from.lerp(raised_to, 0.5) + raise, 0), "elevated fence blocks ground level")
	t.check(fences.has_node("Shadows"), "painted connected fences have no shadows")


func _has_fence_rectangle(body: StaticBody2D, center: Vector2, length: float, width: float,
		angle: float) -> bool:
	for child: Node in body.get_children():
		var collision := child as CollisionShape2D
		if collision == null or not collision.shape is RectangleShape2D:
			continue
		var rectangle := collision.shape as RectangleShape2D
		if rectangle.size.distance_to(Vector2(length, width)) < 0.1 \
				and collision.position.distance_to(center) < 0.1 \
				and absf(wrapf(collision.rotation - angle, -PI, PI)) < 0.001:
			return true
	return false


func test_fences_mount_with_the_elevation(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null and elevation.fences != null, "no fences in the fence park"):
		return
	var fences := elevation.fences
	var renderers := t.world().world_root.find_children("Fences", "Node2D", true, false)
	t.equal(renderers.size(), 1, "the same paint spawned multiple fence renderers")
	for level in [-1, 0, 1, 2, 3]:
		# Holes are fenced on the ground around them (level 0), not inside (level -1).
		t.equal(fences.has_node("Collision/Level%d" % level), level != -1, "fence collision for level %d" % level)
	t.check(fences.has_node("Shadows"), "no fence shadows")
	var pieces := elevation.get_parent().get_parent().get_node_or_null(NodePath(Fences.PIECES_NAME))
	t.check(pieces != null and pieces.get_child_count() > 300, "few fence pieces")
	t.check(pieces != null and pieces.y_sort_enabled, "fence pieces do not y-sort")
	_check_post_feet_match_collision(t)


func test_flat_world_mounts_fences_beside_the_ground(t: TestContext) -> void:
	var root := Node2D.new()
	root.name = "flat-fence-world"
	t.tree.root.add_child(root)
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.tile_set = load(Elevation.TERRAIN_TILESET_PATH)
	var source := ground.tile_set.get_source_id(0)
	for y in 6:
		for x in 8:
			ground.set_cell(Vector2i(x, y), source, Vector2i.ZERO)
	ground.set_meta(&"columns", 8)
	ground.set_meta(&"rows", 6)
	root.add_child(ground)
	var painted := TileMapLayer.new()
	painted.name = "fences"
	painted.tile_set = FENCE_TILESET
	for x in range(2, 5):
		painted.set_cell(Vector2i(x, 3), 0, Vector2i(0, 0))
	root.add_child(painted)
	t.check(Elevation.mount(ground, true) == null, "a flat world built an elevation")
	var fences := root.get_node_or_null(NodePath(Fences.NODE_NAME)) as Fences
	if t.check(fences != null, "a flat world did not mount its fences beside the ground"):
		t.check(root.get_node_or_null(NodePath(Fences.PIECES_NAME)) != null, "a flat world's fences have no pieces")
		var body := fences.get_node_or_null("Collision/Level0") as StaticBody2D
		if t.check(body != null, "a flat world's fences have no level-0 collision"):
			# Three posts and two links.
			t.equal(body.get_child_count(), 5, "a flat world's three-post run collides as 3 posts and 2 bands")
		var foot := Vector2(3.5, 3.5) * 64.0
		t.check(fences.blocks_point(foot + Vector2(0.0, -6.0), 0), "a flat world's fence does not block at its band")
		t.check(not fences.blocks_point(foot + Vector2(0.0, 6.0), 0), "a flat world's fence blocks below its band")
	painted.clear()
	t.check(Elevation.mount(ground, true) == null, "a flat world built an elevation")
	await t.steps(1)
	t.check(root.get_node_or_null(NodePath(Fences.NODE_NAME)) == null, "erased fences were not removed")
	root.free()


## A flat world's fence stops a walker (2026-10-19 review: in the Lair's rooms without levels the
## fences' level-0 bodies were on the `level 0` layer, which no body's mask has without an Elevation
## to track it, so the slime walked through every divider).
func test_a_flat_worlds_fence_stops_a_body(t: TestContext) -> void:
	var root := Node2D.new()
	root.name = "flat-fence-walk"
	t.tree.root.add_child(root)
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.tile_set = load(Elevation.TERRAIN_TILESET_PATH)
	var source := ground.tile_set.get_source_id(0)
	for y in 8:
		for x in 8:
			ground.set_cell(Vector2i(x, y), source, Vector2i.ZERO)
	ground.set_meta(&"columns", 8)
	ground.set_meta(&"rows", 8)
	root.add_child(ground)
	var painted := TileMapLayer.new()
	painted.name = "fences"
	painted.tile_set = FENCE_TILESET
	for x in range(2, 6):
		painted.set_cell(Vector2i(x, 3), 0, Vector2i(0, 0))
	root.add_child(painted)
	Elevation.mount(ground, true)
	# The player's own mask (player_slime.tscn: world, enemy, npc, water), no level bit: nothing
	# tracks a body onto a level in a flat world.
	var body := CharacterBody2D.new()
	body.collision_layer = 0
	body.collision_mask = 1 | 4 | 128 | 1024
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2.0 * BODY_HALF_WIDTH, 26.0)
	shape.shape = rectangle
	body.add_child(shape)
	body.position = Vector2(3.5 * 64.0, 3.5 * 64.0 + 40.0)
	root.add_child(body)
	await t.steps(2)
	t.check(body.test_move(body.global_transform, Vector2(0.0, -80.0)), "a body walked north through a flat world's fence")
	# past the run's east end nothing stops it: the fence did
	body.position.x = 6.5 * 64.0
	await t.steps(2)
	t.check(not body.test_move(body.global_transform, Vector2(0.0, -80.0)), "a body was stopped where no fence stands")
	root.free()


## The fence palette's tile of `style` (a gate tile: `lair-divider-eye`).
static func _style_tile(style: String) -> Vector2i:
	var source := FENCE_TILESET.get_source(0) as TileSetAtlasSource
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if str(source.get_tile_data(coords, 0).get_custom_data(Fences.STYLE_DATA_LAYER)) == style:
			return coords
	return Vector2i(-1, -1)


## Painted divider gates (docs/godot/FENCES.md "Dungeon dividers"; 2026-10-19 review: erasing a gate
## tile and undoing it lost the Weigh House gate's id, and every painted gate shared one record): a
## gate the layer makes has a record of its own; one given a setting of its own is never removed
## with its tile and is adopted again when the tile comes back; one nobody changed goes with its tile.
func test_painted_gates_keep_their_settings_and_records(t: TestContext) -> void:
	var room := Node2D.new()
	room.name = "gate-room"
	t.main.add_child(room)
	var definition := WorldDefinition.new()
	definition.name = "world-definition"
	definition.map_id = "gate-room-world"
	room.add_child(definition)
	var objects := Node2D.new()
	objects.name = "Objects"
	room.add_child(objects)
	var layer := FenceLayer.new()
	layer.name = "fences"
	layer.tile_set = FENCE_TILESET
	room.add_child(layer)
	var eye := _style_tile("lair-divider-eye")
	if not t.check(eye.x >= 0, "the palette has no eye gate tile"):
		room.free()
		return
	layer.set_cell(Vector2i(3, 4), 0, eye)
	layer.set_cell(Vector2i(6, 4), 0, eye)
	t.equal(layer.sync_gates(), 2, "gates made for two painted gate tiles")
	var first := objects.get_node_or_null("divider-gate-3-4")
	var second := objects.get_node_or_null("divider-gate-6-4")
	if not t.check(first != null and second != null, "the painted gates are missing"):
		room.free()
		return
	var first_script := first.get_node("GateScript")
	t.equal(str(first_script.get(&"gate_id")), "gate-room-gate-3-4", "a painted gate's own record")
	t.equal(str(first_script.get(&"map_id")), "gate-room-world", "a painted gate's record map")
	t.check(str(second.get_node("GateScript").get(&"gate_id")) != str(first_script.get(&"gate_id")), "two painted gates share one record")
	# Given a setting of its own, the first survives its tile erased and is adopted again.
	first_script.set(&"locked_message", "The pen is shut.")
	layer.erase_cell(Vector2i(3, 4))
	layer.sync_gates()
	t.check(is_instance_valid(first) and first.get_parent() == objects, "a gate with a setting of its own was removed with its tile")
	layer.set_cell(Vector2i(3, 4), 0, eye)
	t.equal(layer.sync_gates(), 0, "a gate was made beside the kept one")
	if is_instance_valid(first):
		t.equal(str(first.get_meta(FenceLayer.GATE_CELL_META, "")), "3,4", "the kept gate was not adopted again")
		t.equal(str(first_script.get(&"locked_message")), "The pen is shut.", "the kept gate's setting")
	# One the layer made and nobody changed goes with its tile.
	layer.erase_cell(Vector2i(6, 4))
	layer.sync_gates()
	t.check(not is_instance_valid(second), "an untouched painted gate stayed after its tile was erased")
	room.free()


func test_c4_fence_art_matches_collision_with_elevation_above_the_map(t: TestContext) -> void:
	t.main.travel_to("level-1-c4")
	if not t.check(await t.until(func() -> bool: return t.in_world("level-1-c4") and not t.main.is_transitioning(), 5000.0), "could not enter C4"):
		return
	var elevation := t.world().elevation
	t.check(elevation.cell_offset.y > 0, "C4 no longer exercises elevation rows above the map")
	_check_post_feet_match_collision(t)
	# Walk into the painted east fence (its north-south links) on this row, away from the stairs.
	_place_feet(t, Vector2(28.5, 21.5) * 64.0)
	elevation.track(t.player_body(), 1)
	var fences := elevation.fences as Fences
	var line_x := -INF
	var feet_y := t.player_body().global_position.y
	var line_y := 0.0
	var nearest_y_distance := INF
	for box: Dictionary in fences._boxes.get(1, []):
		var axis: Vector2 = box["axis"]
		if absf(axis.x) > 0.01:
			continue
		var centre := fences.to_global(box["centre"] as Vector2)
		var distance := absf(centre.y - feet_y)
		if distance < nearest_y_distance:
			nearest_y_distance = distance
			line_x = centre.x
			line_y = centre.y
	if not t.check(is_finite(line_x) and nearest_y_distance <= 32.0,
			"C4 has no painted east fence link at the test position"):
		return
	_place_feet(t, Vector2(t.player_body().global_position.x, line_y))
	t.press(&"move_right")
	await t.steps(2)
	await t.sim_wait(1500.0)
	t.release_all()
	t.near(t.player_body().global_position.x, line_x - SIDE_HALF - BODY_HALF_WIDTH, 1.5, "body stopped at C4's painted east fence link")
	t.equal(elevation.level_of(t.player_body()), 1, "still on C4's plateau")


func test_walking_into_a_fence_stops_at_its_painted_link(t: TestContext) -> void:
	var body := t.player_body()
	var elevation := t.world().elevation
	t.equal(elevation.level_of(body), 1, "player level on the square")
	_place_feet(t, Vector2(200.0, 450.0))
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(1500.0)
	t.release_all()
	t.near(body.global_position.y, SQUARE_SOUTH_LINK - BAND_ABOVE, 1.5, "feet stopped at the south fence's band (the rails' feet)")
	t.equal(elevation.level_of(body), 1, "still on the square after pushing the south fence")
	_place_feet(t, Vector2(600.0, 470.0))
	await t.steps(2)
	t.press(&"move_right")
	await t.sim_wait(1500.0)
	t.release_all()
	t.near(body.global_position.x, SQUARE_EAST_LINK - SIDE_HALF - BODY_HALF_WIDTH, 1.5, "body stopped at the east painted fence link")
	t.equal(elevation.level_of(body), 1, "still on the square after pushing the east fence")


func test_nothing_drops_or_hops_over_a_fence(t: TestContext) -> void:
	var elevation := t.world().elevation
	# Feet where a body stops against the south fence from the north.
	var at_south := Vector2(200.0, SQUARE_SOUTH_LINK - BAND_ABOVE - 0.5)
	t.check(elevation.drop_target(at_south, 1, Vector2.DOWN).is_empty(), "a drop over the south fence")
	t.check((elevation.hop_target(at_south, 1, Vector2.DOWN, 120.0)["feet"] as Vector2).y <= at_south.y + 0.5, "a hop over the south fence")
	var at_north := Vector2(420.0, 2.5 * 64.0 + 26.0)
	t.check(elevation.drop_target(at_north, 1, Vector2.UP).is_empty(), "a drop over the north fence")
	# The band lies between the old sample points (feet and head rows): the whole rect is tested.
	t.check(not elevation.body_fits(Vector2(200.0, SQUARE_SOUTH_LINK + 5.0), 1), "a body fits over the painted fence's band")
	t.check(elevation.body_fits(Vector2(200.0, SQUARE_SOUTH_LINK - BAND_ABOVE - 0.5), 1), "a body against the fence does not fit")
	# A ledge probe that ends past the band still meets it (Fences.blocks_sweep).
	var fences := elevation.fences as Fences
	var middle := Vector2(200.0, SQUARE_SOUTH_LINK)
	t.check(fences.blocks_sweep(middle + Vector2(0.0, -BAND_ABOVE - 1.0), middle + Vector2(0.0, 4.0), 1), "a probe across the band passes it")
	t.check(not fences.blocks_point(middle + Vector2(0.0, 4.0), 1), "the probe's end is not on the band (test assumption)")
	# The gap in the east fence still drops beside the hill.
	var gap := elevation.drop_target(Vector2(SQUARE_EAST - 16.0, GAP_Y), 1, Vector2.RIGHT)
	if t.check(not gap.is_empty(), "no drop at the gap in the east fence"):
		t.equal(int(gap["level"]), 0, "level beside the hill")


func test_all_eight_directions_connect_without_rim_inference(t: TestContext) -> void:
	for direction_index in Fences.DIRECTIONS.size():
		var start := Vector2i(10, 10)
		var target := start + Fences.DIRECTIONS[direction_index]
		var cells := {
			start: {"style": "wood", "direction": direction_index, "level": 2},
			target: {"style": "wood", "direction": Fences.ALL_NEIGHBORS_DIRECTION, "level": 2},
		}
		var links := Fences.connected_links(cells)
		t.equal(links.size(), 1, "direction %d did not make exactly one painted connection" % direction_index)
		if not links.is_empty():
			t.check((links[0]["from"] == start and links[0]["to"] == target)
					or (links[0]["from"] == target and links[0]["to"] == start),
					"direction %d connected the wrong pair" % direction_index)


func _place_feet(t: TestContext, feet: Vector2) -> void:
	var body := t.player_body()
	body.velocity = Vector2.ZERO
	body.global_position = feet
	body.reset_physics_interpolation()


## Recover each drawn post's foot from its mesh and shader data, then check the band at the rails'
## feet just above it. This catches a picture displaced from collision even when all physical
## movement tests pass.
func _check_post_feet_match_collision(t: TestContext) -> void:
	var fences := t.world().elevation.fences
	if not t.check(fences != null, "no fences"):
		return
	var pieces := t.world().world_root.get_node(Fences.PIECES_NAME)
	var posts := 0
	var raise := Vector2(0.0, -(BAND_ABOVE + BAND_BELOW) * 0.5)
	for piece: MeshInstance2D in pieces.get_children():
		var arrays := piece.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if colors[0].b > 0.25:
			continue
		var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
		var left := INF
		var right := -INF
		var foot_y := 0.0
		for i in colors.size():
			left = minf(left, vertices[i].x)
			right = maxf(right, vertices[i].x)
			foot_y += vertices[i].y - LevelCode.dy_from(colors[i].g)
		var feet := piece.to_global(Vector2((left + right) * 0.5, foot_y / colors.size()))
		var level := roundi(LevelCode.level_from(colors[0].a))
		t.check(fences.blocks_point(feet + raise, level), "drawn fence post is outside its collision at %s, level %d" % [feet, level])
		posts += 1
	t.check(posts > 0, "no drawn fence posts checked")


## The half width of `style`'s post as its kit draws it (asset/MAPS/fences/<style>.json).
static func _post_half(style: String) -> float:
	var kit: Variant = JSON.parse_string(FileAccess.get_file_as_string(Fences.KIT % [style, ".json"]))
	return float((kit as Dictionary)["posts"]["half_width"]) if kit is Dictionary else 0.0


## A post collides as wide as its kit draws it (2026-10-19 review M21: every post used the wood
## kit's 7, so a body overlapped the Lair divider's 24-wide posts by about 5 units).
func test_posts_collide_as_wide_as_their_kit_draws_them(t: TestContext) -> void:
	var raise := Vector2(0.0, -(BAND_ABOVE + BAND_BELOW) * 0.5)
	for style: String in ["wood", "lair-divider"]:
		var fences := _bare_fences(6, 6)
		fences._add_connected_network({Vector2i(2, 2): {"style": style, "direction": 2, "level": 0}}, MeshData.new(), {})
		fences._build_collision()
		var half := _post_half(style)
		var foot := Vector2(2.5, 2.5) * 64.0
		var body := fences.get_node_or_null("Collision/Level0") as StaticBody2D
		if t.check(body != null and half > 0.0, style + ": no collision or no kit"):
			t.check(_has_fence_rectangle(body, foot + raise, half * 2.0, BAND_ABOVE - BAND_BELOW, 0.0),
					"%s: the post's rect is not %.1f wide" % [style, half * 2.0])
		t.check(fences.blocks_point(foot + raise - Vector2(half - 0.5, 0.0), 0), style + ": the post's west side does not block")
		t.check(not fences.blocks_point(foot + raise - Vector2(half + 0.5, 0.0), 0), style + ": the post blocks past its west side")
		fences.free()


## The palette's gate tiles sit where the Lair's scenes paint them (2026-10-19 review H5: they
## followed the styles, so adding a style moved them and every painted gate became a post): the eye
## at (8, 0), the pen at (9, 0), and every divider gate in a Lair room stands on a cell painted with
## its kind's gate tile.
func test_the_gate_tiles_sit_where_the_scenes_paint_them(t: TestContext) -> void:
	var source := FENCE_TILESET.get_source(0) as TileSetAtlasSource
	for tile: Array in [[EYE_GATE, "lair-divider-eye"], [PEN_GATE, "lair-divider-pen"]]:
		var coords: Vector2i = tile[0]
		if t.check(source.has_tile(coords), "the palette has no tile at %s" % coords):
			t.equal(str(source.get_tile_data(coords, 0).get_custom_data(Fences.STYLE_DATA_LAYER)), tile[1], "the gate tile at %s" % coords)
	var gates := 0
	for room_name: String in GATE_ROOMS:
		var room := (load(ROOMS_DIR % room_name) as PackedScene).instantiate() as Node2D
		var layer := room.get_node_or_null("fences") as TileMapLayer
		if not t.check(layer != null, room_name + " has no fences layer"):
			room.free()
			continue
		for node: Node in room.get_node("Objects").find_children("*", "Node2D", true, false):
			if node.scene_file_path != FenceLayer.GATE_SCENE:
				continue
			gates += 1
			var cell := layer.local_to_map(layer.to_local((node as Node2D).global_position))
			var style := Fences.painted_style(layer, cell)
			t.equal(str(Fences.GATE_STYLES.get(style, "")), str(node.get(&"kind")),
					"%s: the gate %s stands on %s painted '%s'" % [room_name, node.name, cell, style])
		room.free()
	t.check(gates >= 6, "the Lair's rooms have %d divider gates (6 or more expected)" % gates)


## A flat room built here with Lair dividers: an east-west run (cells 1..12 of row 3) with an eye gate
## at 4 and a pen gate at 9; R7's case (a gate at (3, 7) between a lone west arrow and a lone east
## arrow); a north-south run (column 14, rows 2..6) with an eye gate at (14, 4). The fence layer makes
## the gates (sync_gates) and the fences are mounted with their collision. Returns the room.
func _gate_room(t: TestContext) -> Node2D:
	var room := Node2D.new()
	room.name = "divider-room"
	t.main.add_child(room)
	var definition := WorldDefinition.new()
	definition.name = "world-definition"
	definition.map_id = "divider-room-world"
	room.add_child(definition)
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.tile_set = load(Elevation.TERRAIN_TILESET_PATH)
	var source := ground.tile_set.get_source_id(0)
	for y in 10:
		for x in 16:
			ground.set_cell(Vector2i(x, y), source, Vector2i.ZERO)
	ground.set_meta(&"columns", 16)
	ground.set_meta(&"rows", 10)
	room.add_child(ground)
	var objects := Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	room.add_child(objects)
	var layer := FenceLayer.new()
	layer.name = "fences"
	layer.tile_set = FENCE_TILESET
	for x in range(1, 13):
		layer.set_cell(Vector2i(x, 3), 0, EYE_GATE if x == 4 else (PEN_GATE if x == 9 else DIVIDER))
	layer.set_cell(Vector2i(2, 7), 0, DIVIDER_WEST)
	layer.set_cell(Vector2i(3, 7), 0, EYE_GATE)
	layer.set_cell(Vector2i(4, 7), 0, DIVIDER_EAST)
	for y in range(2, 7):
		layer.set_cell(Vector2i(14, y), 0, EYE_GATE if y == 4 else DIVIDER)
	room.add_child(layer)
	t.equal(layer.sync_gates(), 4, "the fence layer made a gate on each of the 4 gate tiles")
	Elevation.mount(ground, true)
	return room


## A body with the player's collision rect and mask (no level bit: a flat world) at `feet`.
func _walker(room: Node2D, feet: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 0
	body.collision_mask = 1 | 4 | 128 | 1024
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2.0 * BODY_HALF_WIDTH, 26.0)
	shape.shape = rectangle
	shape.position = Vector2(0.0, -13.0)
	body.add_child(shape)
	body.position = feet
	room.add_child(body)
	return body


## True when a body with its feet at `feet` can move by `motion` without meeting anything.
func _passes(body: CharacterBody2D, feet: Vector2, motion: Vector2) -> bool:
	body.global_position = feet
	return not body.test_move(body.global_transform, motion)


## Where a walk across a gate's line starts: 40 before the line (a north-south line's walk at the
## height of its bands, 6 above the posts' foot line, plus half the body).
static func _walk_start(foot: Vector2, way: Vector2) -> Vector2:
	return foot - way * 40.0 + (Vector2(0.0, 7.0) if way == Vector2.LEFT else Vector2.ZERO)


## A shut divider gate closes its whole cell (2026-10-19 review H3: its body covered 52 units and no
## rail joined it, so a 31-unit hole on each side let the slime through; M19: a gate in a north-south
## line was not turned): beside each gate the fences' bands reach its block, the block blocks, and
## only once the gate has opened (its block sunk, its bars swung: not at once) does a body pass
## through its middle; beside it the way stays shut. The gate's picture sorts at its foot (M16); the
## pen's bars stay in sight folded open.
func test_a_shut_divider_gate_closes_its_whole_cell(t: TestContext) -> void:
	var room := _gate_room(t)
	var objects := room.get_node("Objects")
	await t.steps(3)
	var body := _walker(room, Vector2.ZERO)
	await t.steps(1)
	var raise := Vector2(0.0, -(BAND_ABOVE + BAND_BELOW) * 0.5)
	var fences := room.get_node(NodePath(Fences.NODE_NAME)) as Fences
	# [gate, its foot, the way across its line]
	var cases := [
		[objects.get_node("divider-gate-4-3"), Vector2(4.5, 3.5) * 64.0, Vector2.UP],
		[objects.get_node("divider-gate-9-3"), Vector2(9.5, 3.5) * 64.0, Vector2.UP],
		[objects.get_node("divider-gate-3-7"), Vector2(3.5, 7.5) * 64.0, Vector2.UP],
		[objects.get_node("divider-gate-14-4"), Vector2(14.5, 4.5) * 64.0, Vector2.LEFT],
	]
	for entry: Array in cases:
		var gate := entry[0] as Node2D
		var foot: Vector2 = entry[1]
		var way: Vector2 = entry[2]
		var along := Vector2(way.y, way.x).abs()
		var label := "%s (%s)" % [gate.name, gate.get(&"kind")]
		t.near_vec(gate.global_position, foot, 0.01, label + ": the gate stands on its cell's foot")
		# a walk from 40 before the line to 40 past it, at the gate's middle and in the old holes
		for offset: float in [0.0, -OLD_HOLE, OLD_HOLE]:
			t.check(not _passes(body, _walk_start(foot, way) + along * offset, way * 80.0),
					"%s: a body passed the shut gate %+.1f from its middle" % [label, offset])
		t.check(fences.blocks_point(foot + along * OLD_HOLE + (raise if way == Vector2.UP else Vector2.ZERO), 0),
				label + ": no band beside the gate")
		var look := gate.get_node("Look") as Sprite2D
		t.near(look.position.y, 0.0, 0.01, label + ": the picture does not sort at the gate's foot")
		t.near(look.position.y + look.scale.y * (look.offset.y + look.region_rect.size.y), 0.0, 0.01,
				label + ": the picture's bottom is not on the foot")
	var turned := objects.get_node("divider-gate-14-4/Doors/Shape") as Node2D
	t.near(turned.rotation, PI * 0.5, 0.001, "the gate in the north-south line did not turn its body")
	t.near((objects.get_node("divider-gate-4-3/Doors/Shape") as Node2D).rotation, 0.0, 0.001, "a gate in an east-west line turned")
	# R7's case: the lone arrows beside the gate keep their stubs (they point away from it)
	t.check(fences.blocks_point(Vector2(2.0, 7.5) * 64.0 + raise, 0) and fences.blocks_point(Vector2(5.0, 7.5) * 64.0 + raise, 0),
			"the lone tiles beside the gate lost their stubs")
	# Open: not at once, then the middle passes and beside stays shut.
	for entry: Array in cases:
		(entry[0] as Node).get_node("GateScript").call(&"open")
	await t.steps(3)
	for entry: Array in cases:
		t.check(not _passes(body, _walk_start(entry[1], entry[2]), (entry[2] as Vector2) * 80.0),
				"%s: the way opened before the gate was out of the way" % (entry[0] as Node).name)
	await t.sim_wait(DividerGate.OPEN_MS + 100.0)
	await t.steps(2)
	for entry: Array in cases:
		var gate := entry[0] as Node2D
		var way: Vector2 = entry[2]
		var along := Vector2(way.y, way.x).abs()
		var start := _walk_start(entry[1], way)
		t.check(_passes(body, start, way * 80.0), "%s: a body does not pass the open gate" % gate.name)
		for offset: float in [-OLD_HOLE, OLD_HOLE]:
			t.check(not _passes(body, start + along * offset, way * 80.0), "%s: a body passed beside the open gate %+.1f" % [gate.name, offset])
	t.check((objects.get_node("divider-gate-9-3/Look") as Sprite2D).visible, "the open pen gate's folded bars are hidden")
	room.free()


## A gate opened while its room is being built (its record, a plate already held) shows open at once
## and lets a body through at once: no sinking, no dust (2026-10-19 review: entering a room again
## replayed the opening).
func test_a_gate_opened_as_its_room_is_built_is_open_at_once(t: TestContext) -> void:
	var room := _gate_room(t)
	var gate := room.get_node("Objects/divider-gate-9-3")
	gate.get_node("GateScript").call(&"open")
	var body := _walker(room, Vector2.ZERO)
	await t.steps(2)
	var foot := Vector2(9.5, 3.5) * 64.0
	t.check(_passes(body, _walk_start(foot, Vector2.UP), Vector2(0.0, -80.0)), "a gate opened as its room was built still blocks")
	t.check(not bool(gate.get(&"_moving")), "a gate opened as its room was built plays its opening")
	room.free()


## A gate asking for a dungeon small key (`required_item_id` "small-key", 2026-10-19 review M20: the
## key path counted inventory items, where small keys never are): refused without one, opened with
## one, which it spends; its record is unlocked. A gate asking for an inventory item is unchanged.
func test_a_gate_asking_for_a_small_key_spends_one(t: TestContext) -> void:
	t.main.travel_to("fatty-lair-c2-weigh-house")
	if not t.check(await t.until(func() -> bool: return t.in_world("fatty-lair-c2-weigh-house") and not t.main.is_transitioning(), 8000.0),
			"could not enter the Weigh House"):
		return
	var run := Services.run()
	var dungeon := DungeonState.current_id(t.tree)
	t.equal(dungeon, "fatty-lair", "the Weigh House's dungeon")
	var objects := t.world().world_root.get_node("Objects")
	var gate := objects.get_node("c2-east-door/GateScript")
	gate.set(&"required_item_id", DungeonState.SMALL_KEY)
	while DungeonState.small_keys(run, dungeon) > 0:
		DungeonState.spend_small_key(run, dungeon)
	t.equal(str(gate.call(&"try_unlock")), "missing-item", "a small-key gate opened without a small key")
	t.check(not bool(gate.call(&"is_open")), "a refused gate opened")
	DungeonState.add_small_key(run, dungeon)
	t.check(bool(gate.call(&"push_open")), "a small key did not open the gate")
	t.check(bool(gate.call(&"is_open")), "the gate is not open")
	t.equal(DungeonState.small_keys(run, dungeon), 0, "the small key was not spent")
	t.check(run.is_gate_unlocked(str(gate.get(&"map_id")), str(gate.get(&"gate_id"))), "the gate's record was not unlocked")
	# an inventory key's gate still counts the inventory: a small key is not its key
	var other := objects.get_node("c2-west-door/GateScript")
	other.set(&"required_item_id", "green-key")
	DungeonState.add_small_key(run, dungeon)
	t.equal(str(other.call(&"try_unlock")), "missing-item", "a small key opened an inventory key's gate")
	t.equal(DungeonState.small_keys(run, dungeon), 1, "an inventory key's gate spent a small key")


## The fences keep their pieces when their scene leaves the tree and comes back (2026-10-19 review
## M17: an editor tab switch freed them and nothing built them again); freed with the fences.
func test_fences_keep_their_pieces_out_of_the_tree(t: TestContext) -> void:
	var room := _gate_room(t)
	var pieces := room.get_node_or_null(NodePath(Fences.PIECES_NAME))
	if not t.check(pieces != null and pieces.get_child_count() > 0, "the divider room has no fence pieces"):
		room.free()
		return
	var count := pieces.get_child_count()
	t.main.remove_child(room)
	await t.steps(2)
	t.main.add_child(room)
	await t.steps(2)
	t.check(is_instance_valid(pieces) and pieces.get_child_count() == count, "the fence pieces went when the scene left the tree")
	var fences := room.get_node(NodePath(Fences.NODE_NAME))
	fences.free()
	await t.steps(2)
	t.check(not is_instance_valid(pieces), "the fence pieces stayed after their fences were freed")
	room.free()
