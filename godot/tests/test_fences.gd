extends RefCounted
## Fences along hill rims (docs/godot/FENCES.md), in the Fence Park (scripts/maps/build-fence-park.py):
## they mount with the elevation (pieces, shadows, collision, depth silhouettes), a body walking into
## one stops inside its line on every kind of face, and nothing drops or hops over it, while an
## unfenced stretch of the same rim still drops.

const TestContext := preload("res://tests/lib/test_context.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const ElevationFences := preload("res://game/world/elevation/fences/elevation_fences.gd")

const MAP_ID := "fence-park"
## The level-1 square hill (cells 2..11 x 2..8): its rims, and the gap in its east fence (rows 4-5);
## its stairs (column 5 south, row 6 west) leave gaps of their own.
const SQUARE_SOUTH := 9 * 64.0
const SQUARE_NORTH := 2 * 64.0
const SQUARE_EAST := 12 * 64.0
const GAP_Y := 5 * 64.0
## wood.json inset + game-constants.json fences.clearance: how far inside a rim bodies stop.
const STOP := 18.0


func test_fences_mount_with_the_elevation(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null and elevation.fences != null, "no fences in the fence park"):
		return
	var fences := elevation.fences
	for level in [-1, 0, 1, 2, 3]:
		# Holes are fenced on the ground around them (level 0), not inside (level -1).
		t.equal(fences.has_node("Collision/Level%d" % level), level != -1, "fence collision for level %d" % level)
	t.check(fences.has_node("Shadows"), "no fence shadows")
	var pieces := elevation.get_parent().get_parent().get_node_or_null(NodePath(ElevationFences.PIECES_NAME))
	t.check(pieces != null and pieces.get_child_count() > 300, "few fence pieces")
	t.check(pieces != null and pieces.y_sort_enabled, "fence pieces do not y-sort")


func test_walking_into_a_fence_stops_inside_its_rim(t: TestContext) -> void:
	var body := t.player_body()
	var elevation := t.world().elevation
	t.equal(elevation.level_of(body), 1, "player level on the square")
	_place_feet(t, Vector2(200.0, 450.0))
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(1500.0)
	t.release_all()
	t.near(body.global_position.y, SQUARE_SOUTH - STOP, 1.5, "feet against the south fence")
	t.equal(elevation.level_of(body), 1, "still on the square after pushing the south fence")
	_place_feet(t, Vector2(600.0, 470.0))
	await t.steps(2)
	t.press(&"move_right")
	await t.sim_wait(1500.0)
	t.release_all()
	t.near(body.global_position.x, SQUARE_EAST - STOP - 15.0, 1.5, "body against the east fence")
	t.equal(elevation.level_of(body), 1, "still on the square after pushing the east fence")


func test_nothing_drops_or_hops_over_a_fence(t: TestContext) -> void:
	var elevation := t.world().elevation
	var at_south := Vector2(200.0, SQUARE_SOUTH - STOP)
	t.check(elevation.drop_target(at_south, 1, Vector2.DOWN).is_empty(), "a drop over the south fence")
	t.check((elevation.hop_target(at_south, 1, Vector2.DOWN, 120.0)["feet"] as Vector2).y <= at_south.y + 0.5, "a hop over the south fence")
	var at_north := Vector2(420.0, SQUARE_NORTH + STOP + 26.0)
	t.check(elevation.drop_target(at_north, 1, Vector2.UP).is_empty(), "a drop over the north fence")
	t.check(not elevation.body_fits(Vector2(200.0, SQUARE_SOUTH - 4.0), 1), "a body fits between the fence and its rim")
	# The gap in the east fence still drops beside the hill.
	var gap := elevation.drop_target(Vector2(SQUARE_EAST - 16.0, GAP_Y), 1, Vector2.RIGHT)
	if t.check(not gap.is_empty(), "no drop at the gap in the east fence"):
		t.equal(int(gap["level"]), 0, "level beside the hill")


func test_fences_follow_every_face(t: TestContext) -> void:
	var fences := t.world().elevation.fences
	# Just inside each face of the level-2 diamond (centre 20.5, 6.5 cells; its faces run 45°): the
	# strip between fence and rim is closed, the middle of the top is not.
	var centre := Vector2(20.5, 6.5) * 64.0
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		# The middle of a face lies 2.25 cells from the centre along both axes; step 8 units inside.
		var point := centre + corner * (2.25 * 64.0 - 8.0)
		t.check(fences.blocks_point(point, 2), "diamond face %s is open at %s" % [corner, point])
	t.check(not fences.blocks_point(centre, 2), "the diamond's middle is closed")
	t.check(not fences.blocks_point(Vector2(200.0, SQUARE_SOUTH - 4.0), 0), "a fence closes another level")


func _place_feet(t: TestContext, feet: Vector2) -> void:
	var body := t.player_body()
	body.velocity = Vector2.ZERO
	body.global_position = feet
	body.reset_physics_interpolation()
