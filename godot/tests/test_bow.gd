extends RefCounted
## The Bow (docs/godot/BODY_SHAPES.md "The Bow"; game/player/abilities/bow_sequence.gd, bow_arrow.gd):
## a press aims along the movement keys (else the facing) and draws the goo bow without spending
## anything; the release shoots and spends its 6 energy (too little: "Low energy", nothing flies); the
## arrow flies straight on the slime's level and strikes the first Bow target in its way (a crystal
## lens struck for good, a lash bell rung), is stopped by the bars of a barred gate, a wall and
## higher ground, and by the lake camp (level-1-c5) the two lenses across the river raise the hidden
## chest.
## The tests play in the playground (no abilities learned there in a test: the Bow is lent for the
## session): open level-0 ground at the foot of Elevation Park's level-2 hill (cells 14..22 x 31..35,
## its wall rows 36-37, the foot row 38: test_elevation.gd), and the Barred-gate corner (its gate's foot
## at (2976, 4596), the walled yard north of it: test_barred_gate.gd).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const BowSequence := preload("res://game/player/abilities/bow_sequence.gd")

const MAP_ID := "playground"
const BOW := &"bow"
const USE := &"ability_use"
const ENERGY := 6.0
## Open level-0 ground below the park hill's wall (row 39), and the hill's top (level 2) above it.
const OPEN_GROUND := Vector2(15.5 * 64.0, 39.5 * 64.0)
const HILL_TOP := Vector2(15.5 * 64.0, 33.0 * 64.0)
const BELOW_HILL := Vector2(15.5 * 64.0, 41.0 * 64.0)
const HILL_WALL_TOP_Y := 36.0 * 64.0
## The Barred-gate corner: the gate's foot, the yard behind the bars.
const GATE_FOOT := Vector2(2976.0, 4596.0)
const GATE_YARD := Vector2(2976.0, 4440.0)
## The Bow's first lock by the lake camp in level-1-c5 (BODY_SHAPES.md "The Bow"): the lenses on the
## river's north bank, the hidden chest by the camp, and the camp's bank below each lens.
const CAMP_MAP := "level-1-c5"
const CAMP_LENSES := ["CampRiverLenses/camp-river-lens-west", "CampRiverLenses/camp-river-lens-east"]
const CAMP_CHEST := "CampRiverLenses/camp-river-lens-chest"
const CAMP_FLAG := "camp-river.lenses-struck"
const CAMP_BANK_WEST := Vector2(1150.0, 610.0)
const CAMP_BANK_EAST := Vector2(1250.0, 610.0)


func test_the_press_draws_and_the_release_shoots_and_spends(t: TestContext) -> void:
	var player := _lend_the_bow(t)
	await _stand(t, OPEN_GROUND, 0)
	player.face(Vector2.RIGHT)
	player.set_energy(float(player.get_max_energy()))
	await t.steps(2)
	var full: float = player.get_energy()
	# The aim is the movement keys at the press (up), not the facing (right).
	t.press(&"move_up")
	t.press(USE)
	var drawn := await t.until(func() -> bool: return _drawing(player), 300.0)
	t.release(&"move_up")
	if not t.check(drawn, "the press did not draw the bow"):
		return
	await t.sim_wait(300.0)
	t.check(_drawing(player), "the bow was not held drawn while the key was held")
	# The body is the bow (owner, 2026-11-20): the slime's own clip, aimed up, held on its drawn frame.
	var clips: AnimationPlayer = player.get(&"animation")
	t.equal(String(clips.assigned_animation), "bow-draw-up", "the clip while the bow is drawn up")
	t.check(player.get(&"body").get_node_or_null(^"GooBow") == null, "a separate bow sprite was drawn")
	t.check(_arrows(t).is_empty(), "an arrow flew before the release")
	t.check(float(player.get_energy()) >= full - 0.01, "the draw spent energy: %s of %s" % [player.get_energy(), full])
	t.release(USE)
	var shot := await t.until(func() -> bool: return not _arrows(t).is_empty(), 300.0)
	if not t.check(shot, "the release shot no arrow"):
		return
	t.equal(String(clips.assigned_animation), "bow-shot-up", "the clip as the string snaps")
	t.between(float(player.get_energy()), full - ENERGY - 0.01, full - ENERGY + 1.0, "energy after one arrow")
	var arrow: Node2D = _arrows(t)[0]
	var from := arrow.global_position
	await t.steps(4)
	if is_instance_valid(arrow):
		t.check(arrow.global_position.y < from.y - 20.0 and absf(arrow.global_position.x - from.x) < 1.0,
			"the arrow did not fly straight up (the movement keys' aim): %s -> %s" % [from, arrow.global_position])


func test_too_little_energy_shoots_nothing(t: TestContext) -> void:
	var player := _lend_the_bow(t)
	await _stand(t, OPEN_GROUND, 0)
	player.face(Vector2.RIGHT)
	player.set_energy(3.0)
	await t.steps(1)
	t.tap(USE)
	await t.sim_wait(400.0)
	t.check(_arrows(t).is_empty(), "an arrow flew with 3 energy (it costs 6)")
	t.check(not _drawing(player), "the bow was drawn with 3 energy")


func test_an_arrow_strikes_a_crystal_lens_and_rings_a_bell(t: TestContext) -> void:
	var player := _lend_the_bow(t)
	var lens := _spawn(t, "object.crystal-lens", OPEN_GROUND + Vector2(320.0, 0.0))
	if not t.check(lens != null, "no crystal lens spawned"):
		return
	await _stand(t, OPEN_GROUND, 0)
	var struck: Array = []
	lens.connect(&"struck", func(payload: Dictionary) -> void: struck.append(payload))
	var end := await _shoot(t, Vector2.RIGHT)
	t.check(bool(lens.call(&"is_struck")), "the arrow did not strike the lens (it ended at %s)" % end)
	t.equal(struck.size(), 1, "the lens's struck signals")
	t.check(end.x < lens.global_position.x + 30.0, "the arrow flew on past the lens to %s" % end)
	lens.queue_free()
	var post := _spawn(t, "object.lash-bell-post", OPEN_GROUND + Vector2(320.0, 0.0))
	if not t.check(post != null, "no lash bell spawned"):
		return
	var bell := post.get_node("LashBellScript")
	var rung: Array = []
	bell.connect(&"rung", func(payload: Dictionary) -> void: rung.append(payload))
	await t.steps(2)
	player.set_energy(float(player.get_max_energy()))
	await t.sim_wait(350.0)
	end = await _shoot(t, Vector2.RIGHT)
	t.equal(rung.size(), 1, "the bell's rings after one arrow (it ended at %s)" % end)


func test_a_wall_stops_the_arrow(t: TestContext) -> void:
	_lend_the_bow(t)
	var lens := _spawn(t, "object.crystal-lens", OPEN_GROUND + Vector2(360.0, 0.0))
	var wall := StaticBody2D.new()
	wall.name = "TestWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(64.0, 96.0)
	shape.shape = box
	wall.add_child(shape)
	t.world().entities_root().add_child(wall)
	wall.global_position = OPEN_GROUND + Vector2(180.0, -20.0)
	await _stand(t, OPEN_GROUND, 0)
	var end := await _shoot(t, Vector2.RIGHT)
	t.check(not bool(lens.call(&"is_struck")), "the arrow flew through a wall to the lens")
	t.between(end.x, OPEN_GROUND.x + 100.0, wall.global_position.x - 20.0, "where the arrow splatted on the wall (x)")
	wall.queue_free()


func test_higher_ground_stops_the_arrow(t: TestContext) -> void:
	_lend_the_bow(t)
	var elevation: Node = t.world().elevation
	t.equal(int(elevation.call(&"level_at", BELOW_HILL, -99)), 0, "the level below the park hill")
	t.equal(int(elevation.call(&"level_at", HILL_TOP, -99)), 2, "the level of the park hill's top")
	var lens := _spawn(t, "object.crystal-lens", HILL_TOP)
	await _stand(t, BELOW_HILL, 0)
	var end := await _shoot(t, Vector2.UP)
	t.check(not bool(lens.call(&"is_struck")), "an arrow from level 0 struck a lens on the level-2 hill")
	t.check(end.y > HILL_WALL_TOP_Y, "the arrow flew over the hill's wall to %s" % end)


func test_the_bars_of_a_barred_gate_stop_the_arrow(t: TestContext) -> void:
	_lend_the_bow(t)
	var gate := _gate(t)
	if not t.check(gate != null, "no barred gate in the playground"):
		return
	var refused: Array = []
	gate.connect(&"refused", func(payload: Dictionary) -> void: refused.append(payload))
	var lens := _spawn(t, "object.crystal-lens", GATE_YARD)
	await _stand(t, GATE_FOOT + Vector2(0.0, 150.0), 0)
	var end := await _shoot(t, Vector2.UP)
	t.check(not bool(lens.call(&"is_struck")), "the arrow flew through the bars to the lens")
	t.check(end.y > GATE_YARD.y + 60.0, "the arrow passed the bars: it ended at %s" % end)
	t.check(not bool(gate.call(&"is_open")), "an arrow opened the barred gate")
	t.check(refused.is_empty(), "the bars said their refusal line to an arrow")


func test_both_lenses_by_the_lake_camp_raise_the_hidden_chest(t: TestContext) -> void:
	if not await _travel(t, CAMP_MAP):
		return
	_lend_the_bow(t)
	var root := t.world().world_root
	var lenses: Array[Node] = []
	for path: String in CAMP_LENSES:
		lenses.append(root.get_node_or_null(path))
	var chest := root.get_node_or_null(CAMP_CHEST + "/ChestScript")
	if not t.check(not lenses.has(null) and chest != null, "the lake camp lacks its lenses or chest"):
		return
	t.check(not bool(chest.call(&"is_shown")), "the lens chest shows before the lenses")
	# Each lens from the camp's bank straight below it, north across the river (water never stops an
	# arrow on its level).
	await _stand(t, CAMP_BANK_WEST, 0)
	var end := await _shoot(t, Vector2.UP)
	t.check(bool(lenses[0].call(&"is_struck")), "the west lens was not struck across the river (the arrow ended at %s)" % end)
	t.check(not bool(lenses[1].call(&"is_struck")), "one arrow struck both lenses")
	t.check(not Services.run().has_flag(CAMP_FLAG), "one lens set %s" % CAMP_FLAG)
	t.player().set_energy(float(t.player().get_max_energy()))
	await t.sim_wait(350.0)
	await _stand(t, CAMP_BANK_EAST, 0)
	end = await _shoot(t, Vector2.UP)
	t.check(bool(lenses[1].call(&"is_struck")), "the east lens was not struck across the river (the arrow ended at %s)" % end)
	t.check(Services.run().has_flag(CAMP_FLAG), "both lenses struck did not set %s" % CAMP_FLAG)
	await t.steps(3)
	t.check(bool(chest.call(&"is_shown")), "the lens chest did not rise when both lenses were struck")


# --- helpers ---------------------------------------------------------------------------------------

## Lends the Bow for the session and chooses it in the Ability Box.
func _lend_the_bow(t: TestContext) -> Node:
	var player := t.player()
	Services.run().learn_session_ability(String(BOW))
	t.check(AbilityBox.select(player, BOW), "could not choose the Bow in the Ability Box")
	return player


## Puts the slime's feet at `feet` on `level`, still, and lets the world settle.
func _stand(t: TestContext, feet: Vector2, level: int) -> void:
	var body := t.player_body()
	body.velocity = Vector2.ZERO
	body.global_position = feet
	body.reset_physics_interpolation()
	var elevation: Node = t.world().elevation
	if elevation != null:
		elevation.call(&"track", body, level)
	await t.steps(3)


## Shoots one arrow along `aim` (the slime turned that way, no movement key) and follows it until it
## ends; returns its last place (Vector2.INF when none flew).
func _shoot(t: TestContext, aim: Vector2) -> Vector2:
	t.player().face(aim)
	await t.steps(1)
	t.press(USE)
	await t.sim_wait(200.0)
	t.release(USE)
	if not await t.until(func() -> bool: return not _arrows(t).is_empty(), 300.0):
		t.fail("no arrow flew along %s" % aim)
		return Vector2.INF
	var arrow: Node2D = _arrows(t)[0]
	var last := arrow.global_position
	while is_instance_valid(arrow) and not arrow.is_queued_for_deletion() and not t.aborted:
		last = arrow.global_position
		await t.steps(1)
	await t.sim_wait(350.0)
	return last


## The arrows in flight (BowArrow nodes under the entities root).
func _arrows(t: TestContext) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var parent := t.world().entities_root()
	if parent == null:
		return out
	for child: Node in parent.get_children():
		if child is Node2D and String(child.name).begins_with("BowArrow") and not child.is_queued_for_deletion():
			out.append(child as Node2D)
	return out


## True while the Bow's sequence has the bow drawn.
func _drawing(player: Node) -> bool:
	var abilities: Object = player.call(&"get_abilities")
	var sequence: Variant = abilities.get(&"_sequence") if abilities != null else null
	return sequence is BowSequence and bool((sequence as BowSequence).is_drawing())


## An object scene placed with its root at `feet` under the entities root.
func _spawn(t: TestContext, scene_id: String, feet: Vector2) -> Node2D:
	var node := t.world().instantiate_scene(scene_id) as Node2D
	if node == null:
		return null
	t.world().entities_root().add_child(node)
	node.global_position = feet
	return node


func _gate(t: TestContext) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"barred_gate"):
		if node.is_inside_tree():
			return node
	return null


## Travels to `map` (its west entry); false when it did not arrive.
static func _travel(t: TestContext, map: String) -> bool:
	if not t.check(t.main.travel_to(map, "west"), "travel to %s was refused" % map):
		return false
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == map and t.player() != null, 3000.0, 6000.0)
	if not t.check(arrived, "the player did not reach %s" % map):
		return false
	await t.steps(2)
	return true
