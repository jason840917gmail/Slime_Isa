extends RefCounted
## Cliffs, holes and ground levels (docs/godot/ELEVATION.md): the model's shapes (square corners,
## 45° edges from single-cell steps, walls one cell per level, holes whose near rim hides the
## wall), flights of stairs (a landing, steps, railings; levels and depth along them), the 3D
## ground (a capped strip behind a hill and under a hole's near rim) and, in the playground's
## Elevation Park, walls that block, stairs on every side that change the player's level between
## their railings, rims that hold the player until it insists and then drop it where the picture
## says it falls, a jump that never climbs, walking behind a hill and the player ghosted there.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ElevationGrid := preload("res://game/world/elevation/elevation_grid.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const ElevationStairs := preload("res://game/world/elevation/elevation_stairs.gd")

const MAP_ID := "playground"
## The park's level-2 square hill (cells 14..22 x 31..35), its wall rows 36-37 and its flight of
## stairs at column 18, down 2 cells of wall and 2 of run (scripts/maps/build-elevation-park.py).
## The stairs showcase: a level-2 octagon (cells 4..14 x 131..139) with a flight on every side.
const HILL_TOP := 31 * 64.0
const HILL_RIM := 36 * 64.0
const HILL_FOOT := 38 * 64.0
const HILL_EAST := 23 * 64.0
const STAIRS_X := 18.5 * 64.0
const FLIGHT_END := 36 * 64.0 + 4 * 64.0 + 11.0
const SHOWCASE := Rect2(0.0, 125 * 64.0, 17 * 64.0, 20 * 64.0)
## The level-1 octagon beside it: flights two cells wide and open landings.
const SHOWCASE_WIDE := Rect2(18 * 64.0, 125 * 64.0, 20 * 64.0, 20 * 64.0)
const WEST_X := 15.5 * 64.0
const BELOW_WALL := Vector2(WEST_X, 39.5 * 64.0)
## game-constants.json elevation.behindDepth.
const BEHIND := 32.0
const JUMP_DISTANCE := 168.0


static func _grid(columns: int, rows: int, cells: Dictionary) -> ElevationGrid:
	return ElevationGrid.build(columns, rows, cells, {})


static func _block(x0: int, y0: int, x1: int, y1: int, level: int, into: Dictionary = {}) -> Dictionary:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			into[Vector2i(x, y)] = level
	return into


func test_square_hill_has_one_wall_row_per_level(t: TestContext) -> void:
	var grid := _grid(10, 10, _block(2, 2, 5, 4, 2))
	t.equal(grid.patches.size(), 0, "a square hill keeps square corners (no chamfer)")
	# Walls hang under the south edge only, two cells (8 tris) deep, in each of 8 half-columns.
	t.equal(grid.bands.size(), 8, "walls under the south edge")
	for band: Dictionary in grid.bands:
		t.equal(int(band["drop"]), 2, "wall drop")
		t.equal(int(band["end"]) - int(band["start"]) + 1, 8, "wall tris (one cell per level)")
	t.check(grid.level_at(Vector2(3.5, 5.5), 9) == 9, "the wall row is walkable")
	t.equal(grid.level_at(Vector2(3.5, 3.5)), 2, "the top")
	t.equal(grid.level_at(Vector2(3.5, 7.5)), 0, "below the wall")


func test_single_steps_make_diagonal_edges(t: TestContext) -> void:
	# Two single steps down to the right: the corners between them are cut at 45°.
	var cells := _block(1, 1, 6, 6, 1)
	cells.erase(Vector2i(6, 6))
	cells.erase(Vector2i(5, 6))
	cells.erase(Vector2i(6, 5))
	var grid := _grid(9, 9, cells)
	# The convex corner of cell (5, 5) is cut: its bottom-right corner lies on the lower ground.
	t.equal(grid.level_at(Vector2(5.95, 5.95)), 0, "cut convex corner")
	t.equal(grid.level_at(Vector2(5.5, 5.5)), 1, "the cell's middle stays up")
	# The concave corner of cell (5, 6) is filled: its top-left corner belongs to the hill.
	t.equal(grid.level_at(Vector2(5.05, 6.05)), 1, "filled concave corner")
	var diagonal := 0
	for band: Dictionary in grid.bands:
		if not is_zero_approx(float(band["slope"])):
			diagonal += 1
	t.check(diagonal > 0, "no diagonal (south-east) wall")


func test_hole_wall_is_hidden_by_its_near_rim(t: TestContext) -> void:
	# A hole two levels deep but one row long: the far wall shows one cell, then the near rim.
	var grid := _grid(8, 8, _block(2, 3, 5, 3, -2))
	for band: Dictionary in grid.bands:
		t.equal(int(band["drop"]), 2, "hole wall drop")
		t.check(not bool(band["natural"]), "the near rim did not hide the wall's foot")
		t.equal(int(band["end"]) - int(band["start"]) + 1, 4, "visible tris above the rim (one cell)")


func test_a_flight_joins_two_levels(t: TestContext) -> void:
	# A front flight two levels down from a rim drawn at (100, 200): the landing above the rim, the
	# steps two units down on screen per unit along it (a cell of wall and one of run per level),
	# the last step 11 deeper; railings beside the steps.
	var flight := ElevationStairs.create("s", Vector2(100.0, 200.0), 2, 0, 1, false)
	t.near(flight.end, 128.0 + 11.0, 0.01, "length along the flight")
	t.near(flight.s_at(Vector2(100.0, 300.0)), 50.0, 0.5, "s of a point on the steps")
	t.check(flight.walks(Vector2(100.0, 190.0)) and flight.walks(Vector2(100.0, 300.0)) and flight.walks(Vector2(100.0, 450.0)), "landing or steps not walkable")
	t.check(not flight.walks(Vector2(140.0, 300.0)) and flight.occupies(Vector2(140.0, 300.0)), "the railing is not solid")
	t.equal([flight.level_at(Vector2(100.0, 190.0), -9), flight.level_at(Vector2(100.0, 225.0), -9), flight.level_at(Vector2(100.0, 300.0), -9), flight.level_at(Vector2(100.0, 450.0), -9)],
			[2, 2, 1, 0], "levels along the flight (landing, top, middle, foot)")
	t.check(flight.walks_level(Vector2(100.0, 190.0), 2) and not flight.walks_level(Vector2(100.0, 190.0), 0), "the landing belongs to the top level only")
	t.check(flight.walks_level(Vector2(100.0, 300.0), 0) and flight.walks_level(Vector2(100.0, 300.0), 2), "the steps take every level they join")
	t.near(flight.depth_at(Vector2(100.0, 300.0)), 300.0 + flight.nosing(50.0), 0.5, "depth of a body on the steps (its ground position)")
	# A back flight is foreshortened: a level runs 1.5 cells and shows a third of it on screen.
	var north := ElevationStairs.create("n", Vector2(100.0, 200.0), 1, 0, 1, false)
	t.near(north.s_at(Vector2(100.0, 180.0)), 60.0, 0.5, "s on a north flight")
	t.equal([north.level_at(Vector2(100.0, 195.0), -9), north.level_at(Vector2(100.0, 170.0), -9)], [1, 0], "levels on a north flight")
	# A side flight runs down at 45° on screen, its walkable width across it in y.
	var east := ElevationStairs.create("e", Vector2(100.0, 200.0), 1, 0, 2, true)
	t.near(east.s_at(Vector2(132.0, 232.0)), 32.0, 0.5, "s on an east flight")
	t.check(east.walks(Vector2(132.0, 232.0 + 60.0)) and not east.walks(Vector2(132.0, 232.0 + 70.0)), "a two-cell east flight's width")


func test_ground_behind_a_hill_and_under_a_near_rim(t: TestContext) -> void:
	# Level-2 hill on cells 3..6 x 4..7 (wall rows 8-9); hole of depth 1 on cells 10..13 x 4..7.
	var cells := _block(3, 4, 6, 7, 2)
	_block(10, 4, 13, 7, -1, cells)
	var grid := _grid(16, 14, cells)
	var walkable := func(x: float, y: float, level: int) -> bool: return grid.is_walkable_point(Vector2(x, y), level)
	# Level 0 walks half a cell (the cap) into the hill from the north, never further.
	t.check(walkable.call(4.5, 3.9, 0) and walkable.call(4.5, 4.4, 0), "no walking behind the level-2 hill")
	t.check(not walkable.call(4.5, 4.6, 0) and not walkable.call(4.5, 5.5, 0), "walked too far behind the hill")
	t.check(not walkable.call(4.5, 8.5, 0), "walked through the hill's wall")
	t.check(walkable.call(4.5, 4.5, 2) and walkable.call(4.5, 7.5, 2), "the top is not walkable at its level")
	t.check(not walkable.call(4.5, 8.5, 2), "the wall is walkable at the top's level")
	# East and west sides stay plain rims.
	t.check(walkable.call(2.5, 6.5, 0) and walkable.call(7.5, 6.5, 0), "the ground beside the hill is blocked")
	t.check(not walkable.call(3.2, 6.5, 0), "walked into the hill from its west side")
	# The hole: its far wall row is blocked, its floor continues half a cell under the near rim.
	t.check(not walkable.call(11.5, 4.5, -1), "the hole's far wall is walkable")
	t.check(walkable.call(11.5, 6.5, -1) and walkable.call(11.5, 8.4, -1), "no floor under the near rim")
	t.check(not walkable.call(11.5, 8.6, -1), "the hole's floor reaches too far south")
	t.check(walkable.call(11.5, 8.5, 0), "the ground south of the hole is blocked")
	# The collision follows: level 0's back rim lies half a cell south of the hill's north edge.
	var segments := grid.collision_segments(0)
	var moved := 0
	for i in range(0, segments.size(), 2):
		var a := segments[i]
		var b := segments[i + 1]
		if is_equal_approx(a.y, 4.5) and is_equal_approx(b.y, 4.5) and minf(a.x, b.x) >= 3.0 and maxf(a.x, b.x) <= 7.0:
			moved += 1
	t.check(moved > 0, "level 0's collision has no back rim at y 4.5")


func test_collision_outlines_close_at_every_corner(t: TestContext) -> void:
	# The terrain's outline: every end of a segment meets another (an even count at every point),
	# here where a hole's far-wall foot meets its near rim and the strip under the rim.
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	for level in range(ElevationGrid.MIN_LEVEL, ElevationGrid.MAX_LEVEL + 1):
		var open := _open_ends(elevation.grid.collision_segments(level), 8.0)
		t.check(open.is_empty(), "level %d's terrain outline is open at %s (cells x 8)" % [level, open.slice(0, 6)])
	# The real collision, stairs merged in (world units): no end is left loose (one meeting the
	# middle of another segment closes too).
	for level in range(ElevationGrid.MIN_LEVEL, ElevationGrid.MAX_LEVEL + 1):
		var body := elevation.get_node_or_null("Collision/Level%d" % level) as StaticBody2D
		if body == null:
			continue
		var segments := ((body.get_child(0) as CollisionShape2D).shape as ConcavePolygonShape2D).segments
		var loose: Array = []
		for point: Vector2 in _open_ends(segments, 1.0):
			if not _on_a_segment(point, segments):
				loose.append(point)
		t.check(loose.is_empty(), "level %d's collision has loose ends at %s (world)" % [level, loose.slice(0, 6)])


## Points (rounded to 1 / `scale`) where an odd number of segment ends meet.
static func _open_ends(segments: PackedVector2Array, scale: float) -> Array:
	var ends := {}
	for point: Vector2 in segments:
		var key := Vector2i(roundi(point.x * scale), roundi(point.y * scale))
		ends[key] = int(ends.get(key, 0)) + 1
	var open: Array = []
	for key: Vector2i in ends:
		if int(ends[key]) % 2 == 1:
			open.append(Vector2(key) / scale)
	return open


## True when `point` lies within 2 units of the inside of a segment (not at its ends).
static func _on_a_segment(point: Vector2, segments: PackedVector2Array) -> bool:
	for i in range(0, segments.size(), 2):
		var a := segments[i]
		var b := segments[i + 1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		if closest.distance_to(point) < 2.0 and closest.distance_to(a) > 2.0 and closest.distance_to(b) > 2.0:
			return true
	return false


func test_park_mounts_cliffs_and_collision(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	t.check(elevation.grid.bands.size() > 100, "few walls in the park")
	for mesh_name in ["meadow-rock", "meadow-rock:end-right", "meadow-rock:end-left"]:
		t.check(_has_mesh(elevation, "Walls", mesh_name), "no '%s' mesh (walls, wall ends)" % mesh_name)
	t.check(_has_mesh(elevation, "Stairs", "stairs"), "no stairs mesh")
	t.check(elevation.stairs.size() >= 30, "few flights of stairs in the park (%d)" % elevation.stairs.size())
	t.check(_has_mesh(elevation, "Water", "water"), "no water at the foot of the lake's cliff")
	for ground in ["highland", "frozen", "sanddessert", "forest-floor", "forest-moss", "amberleaf", "cavern-floor", "crystal-floor", "town-cobble"]:
		t.check(_has_mesh(elevation, "Lips", ground + ":fringe"), "no %s cliff lip" % ground)
	for level in [-3, -2, -1, 0, 1, 2, 3]:
		t.check(elevation.has_node("Collision/Level%d" % level), "no collision for level %d" % level)
	t.check(elevation.has_node("Shadows/cast"), "no cast shadows")
	t.check(elevation.occlusion != null and elevation.occlusion.texture != null, "no depth map")
	t.equal(elevation.level_of(t.player_body()), 0, "player level at the spawn")
	t.check(t.player_body().collision_mask & Elevation.level_bit(0) != 0, "player does not collide with level 0")


func test_wall_blocks_the_lower_ground(t: TestContext) -> void:
	var body := t.player_body()
	_place_feet(t, BELOW_WALL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(1500.0)
	t.release_all()
	t.check(body.global_position.y > HILL_FOOT, "walked into the wall (feet y %.1f)" % body.global_position.y)
	t.check(body.global_position.y < HILL_FOOT + 40.0, "did not reach the wall (feet y %.1f)" % body.global_position.y)
	t.equal(t.world().elevation.level_of(body), 0, "level after pushing against the wall")


func test_stairs_climb_and_descend(t: TestContext) -> void:
	var body := t.player_body()
	var elevation := t.world().elevation
	_place_feet(t, Vector2(STAIRS_X, FLIGHT_END + 60.0))
	await t.steps(2)
	t.press(&"move_up")
	var climbed := await t.until(func() -> bool: return elevation.level_of(body) == 2 and body.global_position.y < HILL_RIM - 40.0, 4000.0)
	t.release_all()
	t.check(climbed, "did not climb to level 2 (level %d, feet y %.1f)" % [elevation.level_of(body), body.global_position.y])
	t.check(body.collision_mask & Elevation.level_bit(2) != 0 and body.collision_mask & Elevation.level_bit(0) == 0, "collision mask on the hill")
	# Halfway down, the railings hold the slime between them.
	_place_feet(t, Vector2(STAIRS_X, HILL_RIM + 128.0))
	elevation.track(body, 1)
	await t.steps(2)
	t.equal(elevation.level_of(body), 1, "level halfway down a two-level flight")
	for action: StringName in [&"move_right", &"move_left"]:
		t.press(action)
		await t.sim_wait(600.0)
		t.release_all()
		t.check(absf(body.global_position.x - STAIRS_X) <= 18.0, "walked through a railing (feet x %.1f)" % body.global_position.x)
	# Back down the stairs.
	_place_feet(t, Vector2(STAIRS_X, HILL_RIM - 60.0))
	elevation.track(body, 2)
	await t.steps(2)
	t.press(&"move_down")
	var descended := await t.until(func() -> bool: return elevation.level_of(body) == 0 and body.global_position.y > FLIGHT_END + 10.0, 4000.0)
	t.release_all()
	t.check(descended, "did not walk down to level 0 (level %d, feet y %.1f)" % [elevation.level_of(body), body.global_position.y])


func test_stairs_on_every_side(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	var found := {}
	for flight: ElevationStairs in elevation.stairs:
		var rim_world := flight.rim + elevation.global_position
		if not SHOWCASE.has_point(rim_world):
			continue
		found[flight.direction_name] = true
		t.equal([flight.top, flight.bottom], [2, 0], "%s flight's levels" % flight.direction_name)
		var at := func(s: float, t_across: float, h: float) -> Vector2: return flight.screen_of(Vector3(s, t_across, h)) + elevation.global_position
		var middle: Vector2 = at.call(flight.ramp * 0.5, 0.0, flight.nosing(flight.ramp * 0.5))
		t.check(elevation.is_walkable(middle, 0) and elevation.is_walkable(middle, 1) and elevation.is_walkable(middle, 2), "%s flight's steps not walkable at every level" % flight.direction_name)
		# The railings block where they stand: beside the steps at their height (for every level the
		# flight joins), at their foot for the lower ground's.
		for side: float in [-1.0, 1.0]:
			var beside: Vector2 = at.call(flight.ramp * 0.5, side * (flight.half + 9.0), flight.nosing(flight.ramp * 0.5))
			t.check(not elevation.is_walkable(beside, 0) and not elevation.is_walkable(beside, 1) and not elevation.is_walkable(beside, 2),
					"%s flight's railing (%+d) lets a body off the steps" % [flight.direction_name, side])
			# (The far railing's foot is drawn behind the steps: there a body stands on the steps.)
			var foot: Vector2 = at.call(flight.ramp * 0.5, side * (flight.half + 9.0), 0.0)
			if not flight.walks(foot - elevation.global_position):
				t.check(not elevation.is_walkable(foot, 0), "%s flight's railing (%+d) has no foot on the lower ground" % [flight.direction_name, side])
		var landing: Vector2 = at.call(-16.0, 0.0, flight.nosing(-16.0))
		t.check(elevation.is_walkable(landing, 2) and not elevation.is_walkable(landing, 0), "%s flight's landing is not the top's alone" % flight.direction_name)
		t.equal(elevation.level_at(middle), 1, "%s flight's level halfway" % flight.direction_name)
		# What of a back flight hides behind the hill's top neither shows nor blocks the top.
		var hidden: Vector2 = at.call(4.0, -(flight.half + 9.0), 30.0)
		if elevation.grid.level_at((hidden - elevation.global_position) / 64.0, -9) == 2:
			t.check(elevation.is_walkable(hidden, 2), "%s flight's hidden railing blocks the hill's top" % flight.direction_name)
	t.equal(found.size(), 8, "directions of the showcase's flights %s" % [found.keys()])


func test_every_flight_walks_through_both_ends(t: TestContext) -> void:
	# A body walks down every showcase flight from the hilltop and back up from the lower ground:
	# 8 directions, one and two cells wide, railed and open landings (nothing at either end, posts
	# included, narrows the way in).
	var body := t.player_body()
	var elevation := t.world().elevation
	var flights: Array = []
	for flight: ElevationStairs in elevation.stairs:
		var rim_world := flight.rim + elevation.global_position
		if SHOWCASE.has_point(rim_world) or SHOWCASE_WIDE.has_point(rim_world):
			flights.append(flight)
	t.equal(flights.size(), 16, "showcase flights")
	for flight: ElevationStairs in flights:
		var label := "%s%s%s" % [flight.direction_name, " wide" if flight.half > 40.0 else "", " open" if flight.open_landing else ""]
		var top_end := flight.screen_of(Vector3(-ElevationStairs.LANDING, 0.0, flight.nosing(-1.0))) + elevation.global_position
		var bottom_end := flight.screen_of(Vector3(flight.end, 0.0, 0.0)) + elevation.global_position
		var along := bottom_end - top_end
		var progress := func() -> float: return (body.global_position - top_end).dot(along) / along.length_squared()
		var margin := 20.0 / along.length()
		for down: bool in [true, false]:
			var start := flight.screen_of(Vector3(-ElevationStairs.LANDING - 40.0, 0.0, flight.nosing(-1.0)) if down else Vector3(flight.end + 40.0, 0.0, 0.0)) + elevation.global_position
			var start_level := flight.top if down else flight.bottom
			if not t.check(elevation.is_walkable(start, start_level), "%s: the start %s is not walkable" % [label, start]):
				continue
			_place_feet(t, start)
			elevation.track(body, start_level)
			await t.steps(2)
			var way := flight.dir if down else -flight.dir
			var keys: Array[StringName] = []
			if way.x > 0.3:
				keys.append(&"move_right")
			elif way.x < -0.3:
				keys.append(&"move_left")
			if way.y > 0.3:
				keys.append(&"move_down")
			elif way.y < -0.3:
				keys.append(&"move_up")
			for key in keys:
				t.press(key)
			var end_level := flight.bottom if down else flight.top
			var through := await t.until(func() -> bool:
				var at: float = progress.call()
				return elevation.level_of(body) == end_level and (at > 1.0 + margin if down else at < -margin), 6000.0)
			t.release_all()
			t.check(through, "%s: stuck going %s (level %d, feet %s, %.2f along)" % [label, "down" if down else "up", elevation.level_of(body), body.global_position, float(progress.call())])


func test_walking_up_a_side_flight(t: TestContext) -> void:
	var body := t.player_body()
	var elevation := t.world().elevation
	var west: ElevationStairs = null
	for flight: ElevationStairs in elevation.stairs:
		if flight.direction_name == "w" and SHOWCASE.has_point(flight.rim + elevation.global_position):
			west = flight
	if not t.check(west != null, "no west flight in the showcase"):
		return
	_place_feet(t, west.screen_of(Vector3(west.end + 30.0, 0.0, 0.0)) + elevation.global_position)
	elevation.track(body, 0)
	await t.steps(2)
	t.press(&"move_right")
	var top_x := west.rim.x + elevation.global_position.x + 24.0
	var climbed := await t.until(func() -> bool: return elevation.level_of(body) == 2 and body.global_position.x > top_x, 5000.0)
	t.release_all()
	t.check(climbed, "did not walk up the west flight (level %d, feet %s)" % [elevation.level_of(body), body.global_position])


func test_drop_targets_match_the_picture(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	# Over the south face: down to the wall's foot, straight below.
	var south := elevation.drop_target(Vector2(WEST_X, HILL_RIM - 2.0), 2, Vector2.DOWN)
	if t.check(not south.is_empty(), "no drop over the south face"):
		t.equal(int(south["level"]), 0, "level below the south face")
		t.between((south["feet"] as Vector2).y, HILL_FOOT, HILL_FOOT + 64.0, "south drop lands at the wall's foot (feet y)")
		t.near((south["feet"] as Vector2).x, WEST_X, 0.5, "south drop x")
	# Over the back (north) rim: behind the hill, inside the capped strip.
	var north := elevation.drop_target(Vector2(WEST_X, HILL_TOP + 26.0), 2, Vector2.UP)
	if t.check(not north.is_empty(), "no drop over the back rim"):
		t.equal(int(north["level"]), 0, "level behind the hill")
		t.between((north["feet"] as Vector2).y, HILL_TOP, HILL_TOP + BEHIND, "back drop lands behind the hill (feet y)")
	# Over the east rim: beside the hill, as far down on screen as the drop is high.
	var east := elevation.drop_target(Vector2(HILL_EAST - 14.0, 33.0 * 64.0), 2, Vector2.RIGHT)
	if t.check(not east.is_empty(), "no drop over the east rim"):
		t.equal(int(east["level"]), 0, "level beside the hill")
		t.check((east["feet"] as Vector2).x > HILL_EAST + 13.0, "east drop lands beside the hill (feet x %.1f)" % (east["feet"] as Vector2).x)
		t.near((east["feet"] as Vector2).y, 33.0 * 64.0 + 128.0, 0.5, "east drop falls two levels on screen")
	# No drop on open ground, up a wall or from the ground behind a hill.
	t.check(elevation.drop_target(Vector2(WEST_X, 33.0 * 64.0), 2, Vector2.DOWN).is_empty(), "a drop in the middle of the top")
	t.check(elevation.drop_target(Vector2(WEST_X, HILL_FOOT + 13.0), 0, Vector2.UP).is_empty(), "a drop up a wall")
	t.check(elevation.drop_target(Vector2(WEST_X, HILL_TOP + BEHIND - 2.0), 0, Vector2.DOWN).is_empty(), "a drop into the hill")


func test_drops_go_by_height_on_every_shape(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	# [name, start on the top (cells), level, push direction]: 45° faces, a tip, straight faces.
	var cases: Array = [
		["diamond south-east face", Vector2(20.5, 45.5), 2, Vector2.DOWN],
		["diamond south-west face", Vector2(17.5, 45.5), 2, Vector2.DOWN],
		["diamond south-east face, head-on", Vector2(19.5, 45.5), 2, Vector2(1, 1)],
		["diamond south tip", Vector2(19.5, 45.5), 2, Vector2.DOWN],
		["level-3 diamond south-west face", Vector2(31.5, 45.5), 3, Vector2(-1, 1)],
		["octagon south-west face", Vector2(19.5, 57.5), 2, Vector2(-1, 1)],
		["octagon south-east face", Vector2(19.5, 57.5), 2, Vector2(1, 1)],
		["octagon south face (beside its stairs)", Vector2(21.4, 57.5), 2, Vector2.DOWN],
		["octagon west tip (beside its wall)", Vector2(19.5, 57.5), 2, Vector2.LEFT],
		["octagon east tip (beside its wall)", Vector2(19.5, 57.5), 2, Vector2.RIGHT],
		["diamond east tip", Vector2(19.5, 45.0), 2, Vector2.RIGHT],
	]
	for entry: Array in cases:
		var start: Vector2 = entry[1] * 64.0
		var level := int(entry[2])
		var unit := (entry[3] as Vector2).normalized()
		if not t.check(elevation.body_fits(start, level), "%s: the start is not on the level-%d top" % [entry[0], level]):
			continue
		var at := _walk_to_rim(elevation, start, level, unit)
		var lower := elevation.ledge_below(at, level, unit)
		if not t.equal(lower, 0, "%s: ground below the ledge (feet %s)" % [entry[0], at]):
			continue
		var target := elevation.drop_target(at, level, unit)
		if not t.check(not target.is_empty(), "%s: no landing" % entry[0]):
			continue
		var landing: Vector2 = target["feet"]
		t.equal(int(target["drop"]), level, "%s: drop" % entry[0])
		t.check(landing.y >= at.y + float(level) * 64.0, "%s: landed above where a fall straight down lands (%s from %s)" % [entry[0], landing, at])
		t.check(elevation.body_fits(landing, 0), "%s: the landing has no room" % entry[0])
		t.equal(elevation.level_at(landing + Vector2(0.0, -2.0)), 0, "%s: ground seen at the landing" % entry[0])
	# Off the diamond's back (north-east) rim: behind it, in the strip.
	var back := _walk_to_rim(elevation, Vector2(20.5, 45.5) * 64.0, 2, Vector2.UP)
	var behind := elevation.drop_target(back, 2, Vector2.UP)
	if t.check(not behind.is_empty(), "no drop off the diamond's back rim"):
		t.equal(int(behind["level"]), 0, "level behind the diamond")


func test_rim_of_a_diamond_drops_when_pushed(t: TestContext) -> void:
	var body := t.player_body()
	var elevation := t.world().elevation
	_place_feet(t, Vector2(20.5, 45.5) * 64.0)
	elevation.track(body, 2)
	await t.steps(2)
	t.press(&"move_down")
	var dropped := await t.until(func() -> bool: return t.player().is_ability_busy(), 2000.0)
	t.release_all()
	if not t.check(dropped, "pushing down against the diamond's south-east face never dropped (feet %s)" % body.global_position):
		return
	await t.until(func() -> bool: return not t.player().is_ability_busy(), 1500.0)
	t.equal(elevation.level_of(body), 0, "level after the drop off the diamond")
	t.check(body.collision_mask & Elevation.level_bit(0) != 0, "collision mask after the drop off the diamond")


func test_walking_down_a_back_face_slides_past_the_tip(t: TestContext) -> void:
	# Behind the level-2 diamond's north-east face, pressing down: the slime slides along the
	# strip's edge, past the east tip and down beside the wall's end (no notch at the tip to catch it).
	var body := t.player_body()
	var elevation := t.world().elevation
	_place_feet(t, Vector2(22.5, 43.0) * 64.0)
	elevation.track(body, 0)
	await t.steps(2)
	t.press(&"move_down")
	var past := await t.until(func() -> bool: return body.global_position.y > 47.5 * 64.0 + 16.0, 4000.0)
	t.release_all()
	t.check(past, "caught behind the diamond's east tip (feet %s)" % body.global_position)
	t.equal(elevation.level_of(body), 0, "level after walking past the tip")


func test_hop_never_climbs(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	# Up at the wall from below: stops before it, on level 0.
	var up := elevation.hop_target(Vector2(WEST_X, HILL_FOOT + 60.0), 0, Vector2.UP, JUMP_DISTANCE)
	t.equal(int(up["level"]), 0, "hop at a wall level")
	t.check((up["feet"] as Vector2).y > HILL_FOOT, "hopped into the wall (feet y %.1f)" % (up["feet"] as Vector2).y)
	# East along the ground towards the level-3 hill's west side: stops beside it.
	var beside := elevation.hop_target(Vector2(25.5 * 64.0, 33.0 * 64.0), 0, Vector2.RIGHT, JUMP_DISTANCE)
	t.equal(int(beside["level"]), 0, "hop at a higher top's side level")
	t.check((beside["feet"] as Vector2).x < 27.0 * 64.0, "hopped onto the level-3 hill (feet x %.1f)" % (beside["feet"] as Vector2).x)
	# Off the south rim: over it and down, landing as far out as the hop goes.
	var off := elevation.hop_target(Vector2(WEST_X, 35.0 * 64.0), 2, Vector2.DOWN, JUMP_DISTANCE)
	t.equal(int(off["level"]), 0, "hop off the south rim level")
	t.check((off["feet"] as Vector2).y > HILL_FOOT, "hop off the rim landed on the wall (feet y %.1f)" % (off["feet"] as Vector2).y)


func test_rim_holds_then_drops_in_front_of_its_wall(t: TestContext) -> void:
	var body := t.player_body()
	var elevation := t.world().elevation
	_place_feet(t, Vector2(WEST_X, HILL_RIM - 30.0))
	elevation.track(body, 2)
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(200.0)
	t.equal(elevation.level_of(body), 2, "level after a short push against the rim")
	t.check(body.global_position.y <= HILL_RIM + 0.5, "walked off the rim without insisting (feet y %.1f)" % body.global_position.y)
	var dropped := await t.until(func() -> bool: return t.player().is_ability_busy(), 1000.0)
	if not t.check(dropped, "pushing against the rim never dropped"):
		t.release_all()
		return
	t.release_all()
	# The flight carries the body down the wall's face (the camera follows it).
	await t.sim_wait(200.0)
	t.check(body.global_position.y > HILL_RIM - 2.0 and body.global_position.y < HILL_FOOT + 40.0, "body not on its way down (feet y %.1f)" % body.global_position.y)
	await t.until(func() -> bool: return not t.player().is_ability_busy(), 1500.0)
	t.equal(elevation.level_of(body), 0, "level after the drop")
	t.between(body.global_position.y, HILL_FOOT, HILL_FOOT + 64.0, "landing at the wall's foot (feet y)")
	t.check(body.collision_mask & Elevation.level_bit(0) != 0 and body.collision_mask & Elevation.level_bit(2) == 0, "collision mask after the drop")
	# The jump still works after it: a full hop to the left on level 0 (the flight of stairs is to
	# the right).
	Services.run().learn_ability("jump")
	await t.steps(2)
	t.press(&"move_left")
	await t.steps(1)
	var before := body.global_position
	t.tap(&"jump")
	var jumped := await t.until(func() -> bool: return t.player().is_ability_busy(), 200.0)
	t.release_all()
	if not t.check(jumped, "no jump after the drop"):
		return
	await t.until(func() -> bool: return not t.player().is_ability_busy(), 1500.0)
	t.between(before.x - body.global_position.x, JUMP_DISTANCE - 24.0, JUMP_DISTANCE + 24.0, "jump distance after the drop")
	t.equal(elevation.level_of(body), 0, "level after the jump")


func test_walking_behind_a_hill_ghosts_the_player(t: TestContext) -> void:
	var body := t.player_body()
	var elevation := t.world().elevation
	_place_feet(t, Vector2(16.5 * 64.0, HILL_TOP - 40.0))
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(2000.0)
	t.release_all()
	await t.steps(2)
	t.equal(elevation.level_of(body), 0, "level behind the hill")
	t.check(not t.player().is_ability_busy(), "pushing into the hill from behind started a drop")
	# Behind the level-2 hill: into its top on screen, as far as the cap.
	t.check(body.global_position.y > HILL_TOP + BEHIND * 0.5, "stopped at the hill's north rim (feet y %.1f)" % body.global_position.y)
	t.check(body.global_position.y <= HILL_TOP + BEHIND + 1.0, "walked past the cap (feet y %.1f)" % body.global_position.y)
	var material := (t.player().visual as CanvasItem).material as ShaderMaterial
	if not t.check(material != null, "the player's sprite has no shader material"):
		return
	t.near(float(material.get_shader_parameter(&"elevation_body_depth")), body.global_position.y, 1.0, "body depth (feet y + 64 · level 0)")
	t.check((material.get_shader_parameter(&"elevation_rect") as Vector4).z > 0.0, "no depth map on the player")
	t.check(float(material.get_shader_parameter(&"elevation_silhouette")) > 0.0, "the player shows no ghost")


## Where a body of `level` walking from `start` along `unit` stops on its level (2-unit steps).
static func _walk_to_rim(elevation: Elevation, start: Vector2, level: int, unit: Vector2) -> Vector2:
	var at := start
	for i in 400:
		if not elevation.body_fits(at + unit * 2.0, level):
			break
		at += unit * 2.0
	return at


## A mesh of the elevation drawing (node names turn ':' into '_').
static func _has_mesh(elevation: Node, group: String, key: String) -> bool:
	var holder := elevation.get_node_or_null(NodePath(group))
	return holder != null and holder.get_node_or_null(NodePath(key.validate_node_name())) != null


func _place_feet(t: TestContext, feet: Vector2) -> void:
	var body := t.player_body()
	body.velocity = Vector2.ZERO
	body.global_position = feet
	body.reset_physics_interpolation()
