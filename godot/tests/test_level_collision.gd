extends RefCounted
## Hand-painted level collision (docs/godot/ELEVATION.md "Painting collision";
## game/world/elevation/level_collision_layer.gd) in the level collision lab
## (tools/build_level_collision_lab.gd): painted, it replaces the automatic collision: a painted rim
## holds a body on its level and pushing on drops it past the wall foot; a painted base blocks the
## level it is painted for; an unpainted gap collides nothing; with the layer empty the automatic
## collision works again.

const TestContext := preload("res://tests/lib/test_context.gd")
const LevelCollision := preload("res://game/world/elevation/level_collision_layer.gd")
const MAP_ID := "level-collision-lab"
const CELL := 64.0


func test_the_painted_collision_replaces_the_automatic_one(t: TestContext) -> void:
	var elevation: Node = t.world().elevation
	if not t.check(elevation != null, "the lab has no elevation"):
		return
	t.check(bool(elevation.get(&"_painted_on")), "the painted layer is not in use")
	var holder := elevation.get_node_or_null("Collision")
	if not t.check(holder != null, "no collision built"):
		return
	var levels := []
	for body: Node in holder.get_children():
		if not str(body.name).begins_with("Level"):
			continue
		levels.append(str(body.name))
		for shape: Node in body.get_children():
			t.check((shape as CollisionShape2D).shape is RectangleShape2D, "%s has an automatic outline" % body.name)
	levels.sort()
	t.equal(levels, ["Level-1", "Level0", "Level1"], "the painted levels' bodies")


## On the platform (level 1) the rim holds the slime; pushing on drops it to level 0 past the face's
## foot.
func test_a_painted_rim_holds_and_drops(t: TestContext) -> void:
	_stand(t, Vector2(12.0, 5.5) * CELL, 1)
	await t.steps(6)
	t.press(&"move_down")
	await t.sim_wait(120.0)
	t.check(_level(t) == 1, "the slime left the platform at once")
	t.check(t.player_body().global_position.y < 6.0 * CELL, "the rim did not hold the slime (at %s)" % t.player_body().global_position)
	var dropped := await t.until(func() -> bool: return _level(t) == 0, 2500.0)
	await t.sim_wait(500.0)
	t.release_all()
	t.check(dropped, "pushing on did not drop the slime")
	t.check(t.player_body().global_position.y > 7.0 * CELL, "the slime landed on the face, not past its foot (at %s)" % t.player_body().global_position)


## On level 0 the platform's painted foot stops the slime walking north into its face.
func test_a_painted_base_blocks_its_level(t: TestContext) -> void:
	_stand(t, Vector2(12.0, 8.5) * CELL, 0)
	await t.steps(6)
	t.press(&"move_up")
	await t.sim_wait(1500.0)
	t.release_all()
	var y := t.player_body().global_position.y
	t.check(y >= 7.0 * CELL - 2.0, "the slime walked into the platform's face (at y %.0f)" % y)
	t.check(_level(t) == 0, "the slime changed level")
	# the pit's painted walls hold a slime in the pit (level -1) the same way
	_stand(t, Vector2(4.5, 9.5) * CELL, -1)
	await t.steps(6)
	t.press(&"move_up")
	await t.sim_wait(1500.0)
	t.release_all()
	y = t.player_body().global_position.y
	t.check(y >= 8.0 * CELL - 2.0, "the slime in the pit walked up its north wall (at y %.0f)" % y)


## Only what is painted collides: through the gap in the pit's east rim a level-0 slime walks on
## over the pit cells (still level 0).
func test_an_unpainted_gap_collides_nothing(t: TestContext) -> void:
	_stand(t, Vector2(8.0, 8.5) * CELL, 0)
	await t.steps(6)
	t.press(&"move_left")
	var over := await t.until(func() -> bool: return t.player_body().global_position.x < 6.0 * CELL, 3000.0)
	t.release_all()
	t.check(over, "the slime did not walk over the pit through the gap (at %s)" % t.player_body().global_position)
	t.check(_level(t) == 0, "the slime changed level over the gap")


## A deck's passage (a slab over the pit) opens the painted rim where it joins the floor: a level-0
## slime walks from the floor onto it.
func test_a_decks_passage_opens_the_painted_rim(t: TestContext) -> void:
	var elevation: Node = t.world().elevation
	_stand(t, Vector2(4.0 * CELL, 6.6 * CELL), 0)
	await t.steps(6)
	t.press(&"move_down")
	await t.sim_wait(200.0)
	t.release_all()
	t.check(t.player_body().global_position.y < 7.0 * CELL - 14.0, "the rim did not hold the slime before the passage")
	elevation.call(&"open_passage", Rect2(Vector2(3.0, 7.0) * CELL, Vector2(2.0, 1.0) * CELL), 0)
	await t.steps(4)
	_stand(t, Vector2(4.0 * CELL, 6.6 * CELL), 0)
	await t.steps(6)
	t.press(&"move_down")
	var on := await t.until(func() -> bool: return t.player_body().global_position.y > 7.3 * CELL, 2000.0)
	t.release_all()
	t.check(on, "the slime did not walk onto the passage (at %s)" % t.player_body().global_position)
	t.check(_level(t) == 0, "the slime changed level on the passage")


## With the layer empty the world's automatic collision is back: the gap is a rim again.
func test_an_empty_layer_leaves_the_automatic_collision(t: TestContext) -> void:
	var layer := t.world().world_root.get_node(LevelCollision.NODE_NAME) as TileMapLayer
	var kept := {}
	for cell: Vector2i in layer.get_used_cells():
		kept[cell] = layer.get_cell_atlas_coords(cell)
	layer.clear()
	var elevation: Node = t.world().elevation
	elevation.call(&"rebuild")
	await t.steps(4)
	t.check(not bool(elevation.get(&"_painted_on")), "the empty layer is still in use")
	var outline := false
	for body: Node in elevation.get_node("Collision").get_children():
		for shape: Node in body.get_children():
			if shape is CollisionShape2D and (shape as CollisionShape2D).shape is ConcavePolygonShape2D:
				outline = true
	var found := []
	for body: Node in elevation.get_node("Collision").get_children():
		found.append("%s:%d" % [body.name, body.get_child_count()])
	t.check(outline, "no automatic outline was built (%s; from cache %s)" % [", ".join(found), elevation.get(&"from_cache")])
	# against the rim, for less than the push that drops
	_stand(t, Vector2(7.0 * CELL + 22.0, 8.5 * CELL), 0)
	await t.steps(6)
	t.press(&"move_left")
	await t.sim_wait(180.0)
	t.release_all()
	t.check(t.player_body().global_position.x > 7.0 * CELL - 2.0, "the automatic rim did not hold the slime at the pit (at %s)" % t.player_body().global_position)
	for cell: Vector2i in kept:
		layer.set_cell(cell, 0, kept[cell])
	elevation.call(&"rebuild")
	await t.steps(4)


func _level(t: TestContext) -> int:
	return int(t.world().elevation.level_of(t.player_body()))


## Puts the slime's feet at `feet` on `level`.
func _stand(t: TestContext, feet: Vector2, level: int) -> void:
	var player := t.player()
	var body := t.player_body()
	player.teleport(feet - (body.global_position - player.get_centre()))
	t.world().elevation.track(body, level)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
