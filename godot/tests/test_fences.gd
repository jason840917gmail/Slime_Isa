extends RefCounted
## One painted fence layer on ordinary and elevated ground (docs/godot/FENCES.md), in Fence Park
## (scripts/maps/build-fence-park.py): each neighbor pair draws and collides once; tile placement
## does not change elevation rims, and a single tile has square collision.

const TestContext := preload("res://tests/lib/test_context.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const MeshData := preload("res://game/world/elevation/elevation_mesh.gd")
const ElevationFences := preload("res://game/world/elevation/fences/elevation_fences.gd")
const FENCE_TILESET := preload("res://game/world/elevation/fences/fence_tileset.tres")

const MAP_ID := "fence-park"
## Fence Park's authored square: fence links use cell centers, with an east drop opening.
const SQUARE_SOUTH_LINK := 8.5 * 64.0
const SQUARE_EAST_LINK := 11.5 * 64.0
const SQUARE_EAST := 12 * 64.0
const GAP_Y := 5 * 64.0


func test_isolated_fence_tile_uses_full_square_collision(t: TestContext) -> void:
	var fences := ElevationFences.new()
	fences.grid = ElevationGrid.build(4, 4, {}, {})
	fences.cell = 64.0
	fences._pieces = Node2D.new()
	fences._pieces.name = ElevationFences.PIECES_NAME
	fences.add_child(fences._pieces)
	var shadows := MeshData.new()
	var depth := {}
	var segments := {}
	var solid_tiles := {}
	fences._add_connected_network({Vector2i(1, 1): {"style": "wood", "direction": 2, "level": 0}},
			shadows, depth, segments, solid_tiles)
	t.check(segments.is_empty(), "an isolated cell kept edge-only collision")
	fences._build_collision(segments, solid_tiles)
	var body := fences.get_node_or_null("Collision/Level0") as StaticBody2D
	if t.check(body != null, "isolated fence tile has no collision body"):
		var shapes := body.find_children("*", "CollisionShape2D", false, false)
		t.equal(shapes.size(), 1, "isolated fence tile has extra collision shapes")
		if not shapes.is_empty():
			var collision := shapes[0] as CollisionShape2D
			t.check(collision.shape is RectangleShape2D, "isolated fence collision is not square")
			if collision.shape is RectangleShape2D:
				t.equal((collision.shape as RectangleShape2D).size, Vector2(64.0, 64.0), "isolated collision size")
			t.equal(collision.position, Vector2(96.0, 96.0), "isolated collision centre")
	t.check(fences.blocks_point(Vector2(96.0, 96.0), 0), "the isolated tile still accepts a landing")
	fences.free()


func test_painted_material_does_not_change_with_ground(t: TestContext) -> void:
	var atlas := FENCE_TILESET.get_source(0) as TileSetAtlasSource
	t.equal(atlas.get_tiles_count(), 63, "palette still includes an extra ground-selected style")
	var painted := TileMapLayer.new()
	painted.tile_set = FENCE_TILESET
	painted.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	painted.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0))
	var fences := ElevationFences.new()
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
		Vector2i(4, 4): {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(5, 4): {"style": "twig", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 0},
	}
	var links := ElevationFences.connected_links(cells)
	if t.check(links.size() == 1, "adjacent all-neighbor fence cells did not make one shared connection"):
		t.equal(links[0]["from"], Vector2i(4, 4), "the connection start is unstable")
		t.equal(links[0]["to"], Vector2i(5, 4), "the connection end is wrong")
	cells[Vector2i(4, 4)]["direction"] = 2
	cells[Vector2i(5, 4)]["direction"] = 6
	t.equal(ElevationFences.connected_links(cells).size(), 1, "reciprocal direction did not connect")
	cells[Vector2i(4, 4)]["direction"] = 0
	cells[Vector2i(5, 4)]["direction"] = 4
	t.check(ElevationFences.connected_links(cells).is_empty(), "mismatched directions unexpectedly joined")
	cells = {
		Vector2i(4, 4): {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 1},
		Vector2i(5, 5): {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 1},
	}
	t.equal(ElevationFences.connected_links(cells).size(), 1, "diagonal fence cells did not connect")
	cells[Vector2i(5, 5)]["level"] = 0
	t.check(ElevationFences.connected_links(cells).is_empty(), "a fence connected across elevation levels")
	cells = {
		Vector2i(4, 4): {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(5, 4): {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(4, 5): {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 0},
		Vector2i(5, 5): {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 0},
	}
	t.equal(ElevationFences.connected_links(cells).size(), 4,
			"a 2x2 fence produced doubled diagonal rails over its four sides")


func test_connected_tiles_add_ground_and_elevated_collision_without_changing_rims(t: TestContext) -> void:
	var elevation := t.world().elevation
	var fences := elevation.fences as ElevationFences
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
	var ground_from := Vector2(28.5, 33.5) * 64.0
	var ground_to := Vector2(29.5, 33.5) * 64.0
	var raised_from := Vector2(4.5, 32.5) * 64.0
	var raised_to := Vector2(5.5, 32.5) * 64.0
	t.check(_has_fence_rectangle(ground_body, ground_from.lerp(ground_to, 0.5), 64.0, 16.0, 0.0),
			"ground fence is missing its wide rectangular collision")
	t.check(_has_fence_rectangle(raised_body, raised_from.lerp(raised_to, 0.5), 64.0, 16.0, 0.0),
			"elevated fence is missing its wide rectangular collision")
	t.check(fences.blocks_point(ground_from.lerp(ground_to, 0.5) + Vector2(0.0, 4.0), 0),
			"ground fence link does not block a drop or hop")
	t.check(fences.blocks_point(raised_from.lerp(raised_to, 0.5) + Vector2(0.0, 4.0), 1),
			"elevated fence link does not block a drop or hop")
	t.check(not fences.blocks_point(raised_from.lerp(raised_to, 0.5), 0), "elevated fence blocks ground level")
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
	var pieces := elevation.get_parent().get_parent().get_node_or_null(NodePath(ElevationFences.PIECES_NAME))
	t.check(pieces != null and pieces.get_child_count() > 300, "few fence pieces")
	t.check(pieces != null and pieces.y_sort_enabled, "fence pieces do not y-sort")
	_check_post_feet_match_collision(t)


func test_c4_fence_art_matches_collision_with_elevation_above_the_map(t: TestContext) -> void:
	t.main.travel_to("level-1-c4")
	if not t.check(await t.until(func() -> bool: return t.in_world("level-1-c4") and not t.main.is_transitioning(), 5000.0), "could not enter C4"):
		return
	var elevation := t.world().elevation
	t.check(elevation.cell_offset.y > 0, "C4 no longer exercises elevation rows above the map")
	_check_post_feet_match_collision(t)
	# Walk into the painted east rail on this row, away from stairs and the intentional gap.
	_place_feet(t, Vector2(28.5, 21.5) * 64.0)
	elevation.track(t.player_body(), 1)
	var fences := elevation.fences as ElevationFences
	var line_x := -INF
	var feet_y := t.player_body().global_position.y
	for segment: PackedVector2Array in fences._connected_collision.get(1, []):
		var a := fences.to_global(segment[0])
		var b := fences.to_global(segment[1])
		if absf(a.x - b.x) < 0.1 and feet_y >= minf(a.y, b.y) - 1.0 and feet_y <= maxf(a.y, b.y) + 1.0:
			line_x = maxf(line_x, a.x)
	if not t.check(is_finite(line_x), "C4 has no painted east fence link at the test position"):
		return
	t.press(&"move_right")
	await t.steps(2)
	await t.sim_wait(1500.0)
	t.release_all()
	t.near(t.player_body().global_position.x, line_x - 23.0, 1.5, "body stopped at C4's painted east fence link")
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
	t.near(body.global_position.y, SQUARE_SOUTH_LINK - 8.0, 1.5, "feet stopped at the south fence's wide collider")
	t.equal(elevation.level_of(body), 1, "still on the square after pushing the south fence")
	_place_feet(t, Vector2(600.0, 470.0))
	await t.steps(2)
	t.press(&"move_right")
	await t.sim_wait(1500.0)
	t.release_all()
	t.near(body.global_position.x, SQUARE_EAST_LINK - 23.0, 1.5, "body stopped at the east painted fence link")
	t.equal(elevation.level_of(body), 1, "still on the square after pushing the east fence")


func test_nothing_drops_or_hops_over_a_fence(t: TestContext) -> void:
	var elevation := t.world().elevation
	var at_south := Vector2(200.0, SQUARE_SOUTH_LINK)
	t.check(elevation.drop_target(at_south, 1, Vector2.DOWN).is_empty(), "a drop over the south fence")
	t.check((elevation.hop_target(at_south, 1, Vector2.DOWN, 120.0)["feet"] as Vector2).y <= at_south.y + 0.5, "a hop over the south fence")
	var at_north := Vector2(420.0, 2.5 * 64.0 + 26.0)
	t.check(elevation.drop_target(at_north, 1, Vector2.UP).is_empty(), "a drop over the north fence")
	t.check(not elevation.body_fits(Vector2(200.0, SQUARE_SOUTH_LINK + 4.0), 1), "a body fits through the painted fence")
	# The gap in the east fence still drops beside the hill.
	var gap := elevation.drop_target(Vector2(SQUARE_EAST - 16.0, GAP_Y), 1, Vector2.RIGHT)
	if t.check(not gap.is_empty(), "no drop at the gap in the east fence"):
		t.equal(int(gap["level"]), 0, "level beside the hill")


func test_all_eight_directions_connect_without_rim_inference(t: TestContext) -> void:
	for direction_index in ElevationFences.DIRECTIONS.size():
		var start := Vector2i(10, 10)
		var target := start + ElevationFences.DIRECTIONS[direction_index]
		var cells := {
			start: {"style": "wood", "direction": direction_index, "level": 2},
			target: {"style": "wood", "direction": ElevationFences.ALL_NEIGHBORS_DIRECTION, "level": 2},
		}
		var links := ElevationFences.connected_links(cells)
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


## Recover each drawn post's foot from its mesh and shader data, then check the real blocked band.
## This catches a picture displaced from collision even when all physical movement tests pass.
func _check_post_feet_match_collision(t: TestContext) -> void:
	var fences := t.world().elevation.fences
	if not t.check(fences != null, "no fences"):
		return
	var pieces := t.world().world_root.get_node(ElevationFences.PIECES_NAME)
	var posts := 0
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
			foot_y += vertices[i].y - (colors[i].g * 512.0 - 128.0)
		var feet := piece.to_global(Vector2((left + right) * 0.5, foot_y / colors.size()))
		var level := roundi(colors[0].a * 8.0 - 4.0)
		t.check(fences.blocks_point(feet, level), "drawn fence post is outside its collision band at %s, level %d" % [feet, level])
		posts += 1
	t.check(posts > 0, "no drawn fence posts checked")
