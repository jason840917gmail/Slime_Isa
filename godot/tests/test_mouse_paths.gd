extends RefCounted
## Click-order routes on ground levels (game/player/mouse/click_path.gd, docs/godot/MOUSE_CONTROLS.md)
## in the playground's Elevation Park (docs/godot/ELEVATION.md): from below a hill's wall, a click
## on the hill top goes up its stairs; from the top, a click below the wall drops off the rim (shorter
## than the stairs). The park's level-2 square hill covers cells 14..22 x 31..35, its wall rows 36-37
## and its stairs come down column 18 (tests/test_elevation.gd).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const MAP_ID := "playground"
const CELL := 64.0
## Below the hill's wall, west of its stairs (level 0).
const BELOW_WALL := Vector2(15.5 * CELL, 39.5 * CELL)
## On the hill top, straight above BELOW_WALL (level 2).
const ON_TOP := Vector2(15.5 * CELL, 32.5 * CELL)
## The flight of stairs: x, and from the rim (y) to its foot.
const STAIRS_X := 18.5 * CELL
const HILL_RIM := 36.0 * CELL
const FLIGHT_END := 36.0 * CELL + 4.0 * CELL + 11.0


func test_route_climbs_the_stairs_to_a_hill_top(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	var body := t.player_body()
	_place(t, BELOW_WALL, 0)
	await t.steps(2)
	var orders := t.player().get_click_orders()
	var started := Time.get_ticks_usec()
	var route: Dictionary = orders.path.find(body.global_position, ON_TOP, t.now())
	t.notes.append("stairs route planned in %.1f ms (%d nodes, %d waypoints)" % [(Time.get_ticks_usec() - started) / 1000.0, int(route.get("expansions", 0)), (route["points"] as PackedVector2Array).size()])
	t.check(bool(route["complete"]), "no complete route up the hill (ends at %s)" % [_last(route)])
	var levels: PackedInt32Array = route["levels"]
	t.check(not levels.is_empty() and levels[levels.size() - 1] == 2, "the route does not end on level 2: %s" % [levels])
	var on_stairs := false
	for point: Vector2 in route["points"]:
		if absf(point.x - STAIRS_X) < 40.0 and point.y > HILL_RIM - 40.0 and point.y < FLIGHT_END:
			on_stairs = true
	t.check(on_stairs, "the route does not take the stairs: %s" % [route["points"]])
	orders.move_to(ON_TOP)
	if not t.check(await t.until(func() -> bool: return not orders.is_active(), 10000.0),
			"the walk up the hill did not finish in 10 s (feet %s, level %d)" % [body.global_position, elevation.level_of(body)]):
		return
	t.equal(elevation.level_of(body), 2, "level at the end")
	t.near_vec(body.global_position, ON_TOP, 8.0, "feet at the clicked point on the hill")


func test_route_drops_off_the_rim_when_shorter(t: TestContext) -> void:
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	var body := t.player_body()
	_place(t, ON_TOP + Vector2(0.0, CELL), 2)
	await t.steps(2)
	var orders := t.player().get_click_orders()
	var started := Time.get_ticks_usec()
	var route: Dictionary = orders.path.find(body.global_position, BELOW_WALL, t.now())
	t.notes.append("drop route planned in %.1f ms (%d nodes)" % [(Time.get_ticks_usec() - started) / 1000.0, int(route.get("expansions", 0))])
	t.check(bool(route["complete"]), "no complete route down (ends at %s)" % [_last(route)])
	var drops := 0
	for drop: Vector2 in route["drops"]:
		if drop != Vector2.ZERO:
			drops += 1
	t.equal(drops, 1, "drops on the way down")
	orders.move_to(BELOW_WALL)
	if not t.check(await t.until(func() -> bool: return not orders.is_active(), 6000.0),
			"the walk down did not finish in 6 s (feet %s, level %d)" % [body.global_position, elevation.level_of(body)]):
		return
	t.equal(elevation.level_of(body), 0, "level at the end")
	t.near_vec(body.global_position, BELOW_WALL, 8.0, "feet at the clicked point below the wall")


func test_route_from_the_hill_top_to_its_back_uses_the_top(t: TestContext) -> void:
	# On the same level the route stays on it: across the top, not down and around.
	var elevation := t.world().elevation
	if not t.check(elevation != null, "no elevation in the playground"):
		return
	var body := t.player_body()
	_place(t, Vector2(15.5 * CELL, 34.5 * CELL), 2)
	await t.steps(2)
	var goal := Vector2(21.5 * CELL, 31.8 * CELL)
	var route: Dictionary = t.player().get_click_orders().path.find(body.global_position, goal, t.now())
	t.check(bool(route["complete"]), "no route across the top")
	for level: int in route["levels"]:
		t.equal(level, 2, "a level off the top on the way across")


static func _last(route: Dictionary) -> Variant:
	var points: PackedVector2Array = route["points"]
	return points[points.size() - 1] if not points.is_empty() else null


func _place(t: TestContext, feet: Vector2, level: int) -> void:
	var body := t.player_body()
	body.velocity = Vector2.ZERO
	body.global_position = feet
	body.reset_physics_interpolation()
	t.world().elevation.track(body, level)
