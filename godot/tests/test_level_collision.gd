extends RefCounted
## Hand-painted level collision (docs/godot/ELEVATION.md "Painting collision";
## game/world/elevation/level_collision_layer.gd) in the level collision lab
## (tools/build_level_collision_lab.gd): painted, it replaces the automatic collision: a painted rim
## holds a body on its level and pushing on drops it past the wall foot; a painted base blocks the
## level it is painted for; an unpainted gap collides nothing; with the layer empty the automatic
## collision works again. A bridge (decks' passages, laid over the lab's pit here with a void under
## it) holds the slime by its sides and drops it with the ledge drop, painted or automatic; a slab
## that fell closes its passage, so the floor's rim holds at the gap; a fence on a painted rim is
## never dropped over; the queries (`is_walkable`, `body_fits`) follow the paint and its levels; a
## key on a slab takes the slab's level; a void or a pit takes its floor and rim from the paint.

const TestContext := preload("res://tests/lib/test_context.gd")
const LevelCollision := preload("res://game/world/elevation/level_collision_layer.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const HazardScript := preload("res://game/dungeon/hazard.gd")
const DeckScript := preload("res://game/dungeon/hazard_deck.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SLAB_SCENE := "res://game/scenes/objects/dungeon/falling-slab.tscn"
const KEY_SCENE := "res://game/scenes/objects/dungeon/dungeon-key.tscn"
const FENCE_TILESET := "res://game/world/fences/fence_tileset.tres"
const MAP_ID := "level-collision-lab"
const CELL := 64.0
## The lab's pit (level -1, tools/build_level_collision_lab.gd PIT) and a bridge across it, one
## cell wide, from the north floor to the south floor (world units).
const PIT := Rect2(128.0, 448.0, 320.0, 256.0)
const BRIDGE := Rect2(256.0, 448.0, 64.0, 256.0)
## FallingSlab.State.GONE / STANDING.
const SLAB_GONE := 3
const SLAB_STANDING := 0


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
	var layer := LevelCollision.find_beside(t.world().ground_layer)
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


## H2 (owner, 2026-10-19: "bridges should hold the player in by the sides"): with nothing painted
## along it, a bridge's passage closes its sides (`_update_passage_paint`): walking off its side the
## slime is held on the deck (no fall), pushing on drops it (the ledge drop, a hop), and it walks off
## the bridge's end onto the floor (the floor's rim opens there).
func test_a_painted_bridge_holds_the_slime_by_its_sides(t: TestContext) -> void:
	await _bridge_holds_by_its_sides(t, true)


## The same with the lab's automatic collision (the layer cleared): the outdoor outline round the
## passage holds the same way.
func test_an_automatic_bridge_holds_the_slime_by_its_sides(t: TestContext) -> void:
	await _bridge_holds_by_its_sides(t, false)


func _bridge_holds_by_its_sides(t: TestContext, painted: bool) -> void:
	if not painted:
		await _clear_paint(t)
	await _bridge(t, 0)
	var watch := t.world().world_root.get_node_or_null("HazardWatch")
	if not t.check(watch != null, "no hazard watch"):
		return
	_stand(t, BRIDGE.get_center(), 0)
	await t.steps(6)
	t.press(&"move_left")
	await t.sim_wait(180.0)
	var feet := t.player_body().global_position
	t.check(feet.x >= BRIDGE.position.x + 8.0, "the slime walked off the bridge's side (feet %s)" % feet)
	t.check(not bool(watch.call(&"is_falling")) and _level(t) == 0, "the slime fell off the bridge's side at once (feet %s)" % feet)
	var hopped := await t.until(func() -> bool: return bool(t.player().call(&"is_airborne")), 2500.0)
	t.release_all()
	t.check(hopped, "pushing on did not drop the slime over the bridge's side with the ledge drop")
	await t.until(func() -> bool: return not bool(watch.call(&"is_falling")) and not bool(t.player().call(&"is_airborne")), 4000.0)
	# along the bridge and off its north end onto the floor
	_stand(t, BRIDGE.get_center() + Vector2(0.0, 40.0), 0)
	await t.steps(6)
	t.press(&"move_up")
	var off := await t.until(func() -> bool: return t.player_body().global_position.y < BRIDGE.position.y - 24.0, 3000.0)
	t.release_all()
	t.check(off, "the slime did not walk off the bridge's end onto the floor (at %s)" % t.player_body().global_position)
	t.check(_level(t) == 0 and not bool(watch.call(&"is_falling")), "the slime fell at the bridge's end")
	# beside the bridge's end the floor's rim still holds (no gap)
	_stand(t, Vector2(BRIDGE.position.x - 18.0, BRIDGE.position.y - 30.0), 0)
	await t.steps(6)
	t.press(&"move_down")
	await t.sim_wait(180.0)
	t.release_all()
	# (the automatic rim's drawn edge wobbles a few units round the cell line)
	t.check(t.player_body().global_position.y <= BRIDGE.position.y + 8.0 and not bool(watch.call(&"is_falling")),
		"the floor's rim beside the bridge's end let the slime in (feet %s)" % t.player_body().global_position)


## The owner (2026-10-19, R7): a slab that fell leaves a gap the floor's rim holds at, as any rim,
## and a push drops the slime with the ledge drop (its passage closes while the slab is gone and opens
## again when it is back). Painted.
func test_a_fallen_slabs_gap_holds_at_the_painted_rim(t: TestContext) -> void:
	await _fallen_slab_gap(t, true)


## The same with the automatic collision.
func test_a_fallen_slabs_gap_holds_at_the_automatic_rim(t: TestContext) -> void:
	await _fallen_slab_gap(t, false)


func _fallen_slab_gap(t: TestContext, painted: bool) -> void:
	if not painted:
		await _clear_paint(t)
	var slabs := await _bridge(t, 1)
	var watch := t.world().world_root.get_node_or_null("HazardWatch")
	if not t.check(watch != null and slabs.size() == 1, "no hazard watch or slab"):
		return
	var slab: Node = slabs[0]
	slab.set(&"return_ms", 1200.0)
	slab.call(&"touch")
	var gone := await t.until(func() -> bool: return int(slab.get(&"state")) == SLAB_GONE, 2000.0)
	await t.steps(4)
	if not t.check(gone, "the slab did not fall"):
		return
	var above := Vector2(BRIDGE.get_center().x, BRIDGE.position.y - 30.0)
	_stand(t, above, 0)
	await t.steps(6)
	t.press(&"move_down")
	await t.sim_wait(180.0)
	var feet := t.player_body().global_position
	t.check(feet.y <= BRIDGE.position.y + 8.0 and _level(t) == 0 and not bool(watch.call(&"is_falling")),
		"the floor's rim did not hold the slime at the fallen slab's gap (feet %s)" % feet)
	var hopped := await t.until(func() -> bool: return bool(t.player().call(&"is_airborne")), 2500.0)
	t.check(hopped, "pushing on did not drop the slime into the gap with the ledge drop")
	var landed := await t.until(func() -> bool: return not bool(t.player().call(&"is_airborne")) and (_level(t) == -1 or bool(watch.call(&"is_falling"))), 2500.0)
	t.release_all()
	t.check(landed, "the ledge drop into the gap did not land in the pit (level %d)" % _level(t))
	# back: its passage opens again, the slime walks onto it from the floor
	await t.until(func() -> bool: return not bool(watch.call(&"is_falling")), 4000.0)
	var back := await t.until(func() -> bool: return int(slab.get(&"state")) == SLAB_STANDING, 4000.0)
	await t.steps(4)
	t.check(back, "the slab did not come back")
	_stand(t, above, 0)
	await t.steps(6)
	t.press(&"move_down")
	var on := await t.until(func() -> bool: return t.player_body().global_position.y > BRIDGE.position.y + 8.0, 1500.0)
	t.release_all()
	t.check(on, "the slab back, the slime did not walk onto it (at %s)" % t.player_body().global_position)


## M12: a fence on a painted rim is never dropped over: the ledge probes stop at its band as outdoors
## (Fences.blocks_sweep), whatever paint lies past it.
func test_a_fence_on_a_painted_rim_is_never_dropped_over(t: TestContext) -> void:
	var elevation: Node = t.world().elevation
	# above the platform's south rim (level 1), probing far enough to cross a fence in row 5
	var feet := Vector2(12.0 * CELL, 340.0)
	var reach := 40.0
	t.equal(int(elevation.call(&"ledge_below", feet, 1, Vector2.DOWN, reach)), 0, "without a fence the probe meets the platform's rim (test assumption)")
	var fences := TileMapLayer.new()
	fences.name = "fences"
	fences.tile_set = load(FENCE_TILESET)
	for x in range(10, 14):
		fences.set_cell(Vector2i(x, 5), 0, Vector2i(0, 0))
	t.world().world_root.add_child(fences)
	elevation.call(&"rebuild")
	await t.steps(2)
	if not t.check(elevation.get(&"fences") != null, "the lab's fence did not mount"):
		return
	t.equal(int(elevation.call(&"ledge_below", feet, 1, Vector2.DOWN, reach)), Elevation.NO_LEDGE, "a probe across the fence dropped over the painted rim past it")
	t.check((elevation.call(&"drop_target", feet, 1, Vector2.DOWN, -1.0, reach) as Dictionary).is_empty(), "a drop over the fence on the painted rim")


## M15: with painted collision the queries follow the paint and the painted levels, square: the pit is
## no ground of level 0 (paths, hops, landings), the platform's face none of level 0, the floor is.
func test_painted_walkability_follows_the_paint_and_its_levels(t: TestContext) -> void:
	var elevation: Node = t.world().elevation
	t.check(bool(elevation.call(&"is_walkable", Vector2(4.5, 9.5) * CELL, -1)), "the pit's floor is no ground of its level")
	t.check(not bool(elevation.call(&"is_walkable", Vector2(4.5, 9.5) * CELL, 0)), "the pit counts as level-0 floor (paths would cross it)")
	t.check(bool(elevation.call(&"is_walkable", Vector2(8.0, 9.0) * CELL, 0)), "the floor is no ground of level 0")
	t.check(not bool(elevation.call(&"is_walkable", Vector2(12.0, 6.5) * CELL, 0)), "the platform's face counts as level-0 floor")
	t.check(not bool(elevation.call(&"body_fits", Vector2(12.0 * CELL, 7.0 * CELL), 0)), "a body fits on the platform's face, behind its painted foot")
	t.check(bool(elevation.call(&"body_fits", Vector2(12.0 * CELL, 7.0 * CELL + 30.0), 0)), "a body does not fit past the platform's painted foot")
	# the gap in the pit's east rim: walking crosses it at level 0, but no landing or path stops there
	t.check(not bool(elevation.call(&"body_fits", Vector2(5.5, 9.0) * CELL, 0)), "a level-0 body fits over the pit")


## M13: a key standing on a slab over the pit takes the slab's level (reached from the slab, not from
## the pit under it); once the slab is gone, the pit's.
func test_a_key_on_a_slab_takes_the_slabs_level(t: TestContext) -> void:
	# the bridge's second slab: past the north floor's face (the pit's first row), over its floor
	var slabs := await _bridge(t, 2)
	var key := (load(KEY_SCENE) as PackedScene).instantiate() as Node2D
	key.name = "lab-key"
	key.position = BRIDGE.position + Vector2(32.0, CELL + 40.0)
	t.world().world_root.add_child(key)
	var free := Node2D.new()
	free.name = "lab-in-the-pit"
	free.position = PIT.position + Vector2(40.0, 200.0)
	t.world().world_root.add_child(free)
	await t.steps(2)
	t.equal(DungeonState.level_of_node(key), 0, "the key on the slab")
	t.equal(DungeonState.level_of_node(free), -1, "a node in the pit")
	# only the levels count (the slime stays away from the key)
	t.world().elevation.track(t.player_body(), -1)
	t.check(not DungeonState.on_level_of(key), "a slime in the pit reaches the key on the slab")
	t.world().elevation.track(t.player_body(), 0)
	t.check(DungeonState.on_level_of(key), "a slime on the slab's level does not reach the key on it")
	var slab: Node = slabs[1]
	slab.call(&"touch")
	await t.until(func() -> bool: return int(slab.get(&"state")) == SLAB_GONE, 2000.0)
	t.equal(DungeonState.level_of_node(key), -1, "the key over the fallen slab's gap")


## M14: a void takes its floor and rim from the paint: a `level` set on it (here the wrong one) never
## keeps a slime over it from falling, and its rectangle catches only on the hole's cells.
func test_a_void_falls_by_the_paint_whatever_its_level(t: TestContext) -> void:
	var hazard := _hazard(t, "void", Rect2(PIT.position - Vector2(64.0, 0.0), PIT.size + Vector2(64.0, 0.0)))
	hazard.set(&"level", -2)
	await t.steps(4)
	t.equal(int(hazard.call(&"floor_level")), -1, "the void's floor (the paint's)")
	t.equal(int(hazard.call(&"rim")), 0, "the void's rim (the paint's, not level + pit_depth)")
	t.check(not bool(hazard.call(&"covers", PIT.position + Vector2(-32.0, 100.0))), "the void catches on the level-0 floor its rectangle covers")
	var watch := t.world().world_root.get_node_or_null("HazardWatch")
	_stand(t, PIT.get_center(), 0)
	var fell := await t.until(func() -> bool: return watch != null and bool(watch.call(&"is_falling")), 1500.0)
	t.check(fell, "a level-0 slime over the void did not fall")


## M14: a spike pit painted two levels down with the default `pit_depth` drops a level-0 slime in when
## the slab under it falls, onto its floor (level -2), instead of leaving it floating.
func test_a_deep_spike_pit_drops_the_slime_when_its_slab_falls(t: TestContext) -> void:
	var elevation: Node = t.world().elevation
	var painted := t.world().world_root.get_node("elevation") as TileMapLayer
	for y in range(7, 11):
		for x in range(2, 7):
			painted.set_cell(Vector2i(x, y), 0, Vector2i(1, 0))
	elevation.call(&"rebuild")
	await t.steps(2)
	var hazard := _hazard(t, "spikes", PIT)
	var slabs := await _bridge(t, 1)
	t.equal(int(hazard.call(&"floor_level")), -2, "the pit's floor (the paint's)")
	t.equal(int(hazard.call(&"rim")), 0, "the pit's rim")
	var watch := t.world().world_root.get_node("HazardWatch")
	_stand(t, BRIDGE.position + Vector2(32.0, 40.0), 0)
	await t.steps(2)
	var slab: Node = slabs[0]
	var dropped := await t.until(func() -> bool:
		t.player().restore_run_state({"hp": t.player().get_max_hp()})
		return _level(t) == -2 and not bool(watch.call(&"is_falling")), 3000.0)
	t.check(dropped, "the slab gone (state %d), the slime did not drop into the pit (level %d)" % [int(slab.get(&"state")), _level(t)])


## A hazard of `kind` over `area` (world), added to the lab.
func _hazard(t: TestContext, kind: String, area: Rect2) -> Node2D:
	var hazard := HazardScript.new()
	hazard.name = "lab-" + kind
	hazard.set(&"kind", kind)
	hazard.set(&"size", area.size)
	hazard.position = area.position
	t.world().world_root.add_child(hazard)
	return hazard


## Lays a void over the lab's pit and a bridge across it: its first `slab_rows` cells falling slabs,
## the rest one deck. Returns the slabs.
func _bridge(t: TestContext, slab_rows: int) -> Array[Node]:
	var root := t.world().world_root
	if root.get_node_or_null("lab-void") == null and root.get_node_or_null("lab-spikes") == null:
		_hazard(t, "void", PIT)
	var slabs: Array[Node] = []
	for row in slab_rows:
		var slab := (load(SLAB_SCENE) as PackedScene).instantiate() as Node2D
		slab.name = "lab-slab-%d" % row
		slab.position = BRIDGE.position + Vector2(0.0, row * CELL)
		root.add_child(slab)
		slabs.append(slab)
	var deck := DeckScript.new()
	deck.name = "lab-bridge"
	deck.position = BRIDGE.position + Vector2(0.0, slab_rows * CELL)
	deck.set(&"size", Vector2(BRIDGE.size.x, BRIDGE.size.y - slab_rows * CELL))
	root.add_child(deck)
	await t.steps(4)
	return slabs


## Clears the lab's painted collision (the automatic one comes back).
func _clear_paint(t: TestContext) -> void:
	LevelCollision.find_beside(t.world().ground_layer).clear()
	t.world().elevation.call(&"rebuild")
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
