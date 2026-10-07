extends RefCounted
## Water collision (docs/godot/specs/water.md "Water collision"; owner's rule, 2026-10-06).
## - Shallow water is walkable: not a solid tile, nothing to collide with, the slime walks in.
## - Deep water blocks (until the slime can swim): a solid tile, and its tiles' collision square
##   (terrain tile set, physics layer `water`) stops the slime at the cell side.
## - No baked water bodies are left under ground/TileCollision.
##
## level-1's lake: row 49 has land at x = 1..6 and shallow water from x = 7; row 43 has shallow water
## at x = 2..4 and deep water from x = 5 (a forest border tree stands on its land cell, x = 1).

const TestContext := preload("res://tests/lib/test_context.gd")

const MAP_ID := "level-1"
const CELL := 64.0
const ROW := 43
const SHALLOW_CELL := Vector2i(3, ROW)
const DEEP_CELL := Vector2i(6, ROW)
## Physics layer "water" (project.godot layer_names/2d_physics/layer_11).
const WATER_LAYER_BIT := 1 << 10
const WALK_MS := 2500.0


func test_shallow_water_is_walkable_and_deep_water_is_solid(t: TestContext) -> void:
	var world := t.world()
	t.check(not world.is_solid_tile(SHALLOW_CELL.x, SHALLOW_CELL.y), "shallow water is not a solid tile")
	t.check(world.is_solid_tile(DEEP_CELL.x, DEEP_CELL.y), "deep water is a solid tile")
	await t.steps(2)
	t.check(not _water_at(t, _centre(SHALLOW_CELL)), "nothing to collide with in shallow water")
	t.check(_water_at(t, _centre(DEEP_CELL)), "deep water's tile collision is on the water layer")
	var holder := world.ground_layer.get_node_or_null(^"TileCollision")
	if holder != null:
		for child in holder.get_children():
			var body := child as CollisionObject2D
			t.check(body == null or (body.collision_layer & WATER_LAYER_BIT) == 0, "baked water body left: %s" % child.name)


func test_the_slime_walks_from_land_into_shallow_water(t: TestContext) -> void:
	var body := t.player_body()
	t.teleport_player(_centre(Vector2i(5, 49)))
	await t.steps(2)
	t.press(&"move_right")
	var entered := await t.until(func() -> bool: return body.global_position.x > 7.5 * CELL, 1500.0)
	t.release_all()
	t.check(entered, "the slime did not walk into the shallow water (x = %.1f)" % body.global_position.x)


func test_the_slime_stops_at_deep_water(t: TestContext) -> void:
	var body := t.player_body()
	t.teleport_player(_centre(Vector2i(2, ROW)))
	await t.steps(2)
	t.press(&"move_right")
	await t.sim_wait(WALK_MS)
	t.release_all()
	await t.steps(2)
	# Deep water starts at x = 5 cells: the slime's 30-unit body stops at that cell side.
	var x := body.global_position.x
	t.check(x < 5.0 * CELL, "the slime walked into the deep water (x = %.1f)" % x)
	t.check(x > 5.0 * CELL - 30.0, "the slime stopped short of the deep water (x = %.1f)" % x)


func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


func _water_at(t: TestContext, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = WATER_LAYER_BIT
	return not t.tree.root.world_2d.direct_space_state.intersect_point(query, 1).is_empty()
