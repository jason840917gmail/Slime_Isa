extends RefCounted
## The skins (docs/godot/SKINS.md; roadmap 7.8): the Pearls' powers, always on once won, stacking,
## with the bag's Skins row picking only the everyday look (owner, 2026-10-15 and 2026-10-17).
## - the record: won skins and the look are saved (RunState `story.skin_ids`, `story.skin_look`),
##   lent ones are not, and an old save's `skin.<id>` flags win their skins;
## - the Pearl's grant: won for good, the everyday look left as it was, no stand-in flag;
## - stacking and the look: every skin on works whatever the look; a skin shows while it works,
##   then the everyday look comes back;
## - Heavy: a Heavy Roll breaks the old things a plain Roll bonks off, and its shake knocks a loose
##   prize down;
## - Feral: the climb while interact is held (up to the plateau's level, down from its lip, a drop
##   midway that costs nothing), and the Spear's steps at twice the tempo;
## - the bag's Skins row.
## The Silk skin's webs are tests/test_weaver_webs.gd's and tests/test_matron.gd's (they lend it),
## the heavy plate test_gulp.gd's. Every test runs in the playground east of the Bestiary corner,
## where the Skins corner is (its pieces only in the body-shapes mode; the plateau is painted).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const VineLayerScript := preload("res://game/world/vines/vine_layer.gd")

const MAP_ID := "playground"
## Open ground east of the Bestiary corner (old Phaser centre), with room to roll right.
const OPEN := Vector2(6880.0, 1060.0)
const CENTRE_RISE := 27.56
## The Feral plateau (level 2, cells 110-117 x 30-33): its south rim and a climb's foot (feet).
const RIM_Y := 2176.0
const FACE_FOOT_Y := 2304.0
const CLIMB_X := 7136.0
## The column of the plateau's face the vines test paints (cells; east of the corner's own vines).
const VINES_CELL := Vector2i(116, 34)
const FOOT_FEET := Vector2(CLIMB_X, 2330.0)


func test_skins_are_won_lent_and_saved(t: TestContext) -> void:
	var run := Services.run()
	t.check(SkinState.on_ids().is_empty(), "a new run starts with a skin")
	t.check(SkinState.grant(SkinState.HEAVY), "the first grant of the Heavy skin is not new")
	t.check(not SkinState.grant(SkinState.HEAVY), "a second grant counts as new")
	t.check(SkinState.lend(SkinState.SILK), "lending the Silk skin failed")
	t.check(not SkinState.lend(SkinState.HEAVY), "a won skin was lent again")
	t.equal(SkinState.on_ids(), [SkinState.HEAVY, SkinState.SILK], "the skins on")
	t.check(SkinState.is_won(SkinState.HEAVY) and not SkinState.is_won(SkinState.SILK), "won and lent are mixed up")
	t.check(SkinState.set_look(SkinState.SILK), "the lent Silk skin cannot be the look")
	var data := run.serialize()
	t.equal(data["story"]["skin_ids"], ["heavy"], "the saved skins (a lent one left out)")
	t.equal(data["story"].get("skin_look", ""), "", "a lent look was saved")
	t.check(SkinState.set_look(SkinState.HEAVY), "the Heavy skin cannot be the look")
	data = run.serialize()
	t.equal(data["story"]["skin_look"], "heavy", "the saved look")
	t.check(run.install(data), "the save did not load")
	t.equal(SkinState.on_ids(), [SkinState.HEAVY], "the skins after a load")
	t.equal(SkinState.look(), SkinState.HEAVY, "the look after a load")
	t.check(not SkinState.give_back(SkinState.HEAVY), "a won skin was given back")
	t.check(not SkinState.set_look(SkinState.FERAL), "a skin not won became the look")


func test_an_old_save_with_skin_flags_wins_its_skins(t: TestContext) -> void:
	var run := Services.run()
	var data := run.serialize()
	(data["story"] as Dictionary).erase("skin_ids")
	(data["story"]["world_flags"] as Array).append("skin.silk")
	t.check(run.install(data), "the old save did not load")
	t.check(SkinState.is_won(SkinState.SILK), "the old skin.silk flag did not win the Silk skin")
	t.check(t.player().crosses_webs(), "the migrated Silk skin does not cross webs")


func test_the_pearl_grants_its_skin_and_leaves_the_look(t: TestContext) -> void:
	var run := Services.run()
	var pearl := t.world().instantiate_scene("object.pearl-two") as Node2D
	if not t.check(pearl != null, "object.pearl-two did not load"):
		return
	# Found inside the dungeon before its boss (owner, 2026-10-17): no boss to wait for.
	pearl.set(&"boss_id", "")
	pearl.position = OPEN + Vector2(160.0, CENTRE_RISE)
	t.world().world_root.add_child(pearl)
	t.teleport_player(OPEN)
	await t.steps(3)
	t.check(bool(pearl.call(&"is_shown")), "a Pearl without a boss is hidden")
	t.check(not t.player().crosses_webs(), "the slime crosses webs before Pearl 2")
	t.teleport_player(pearl.position - Vector2(0.0, CENTRE_RISE))
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_taken")), 1000.0), "walking into the Pearl did not take it")
	t.check(SkinState.is_won(SkinState.SILK), "Pearl 2 did not win the Silk skin")
	t.equal(SkinState.look(), &"", "Pearl 2 changed the everyday look (a skin shows only while it works)")
	t.check(run.has_flag("pearl.orb-weaver-matron"), "the Pearl's own flag is not set")
	t.check(not run.has_flag("skin.silk"), "the Pearl still sets the old stand-in flag")
	t.check(t.player().crosses_webs(), "the won Silk skin does not cross webs")


func test_skins_stack_and_the_look_is_only_a_look(t: TestContext) -> void:
	var player := t.player()
	for id: StringName in SkinState.RELEASE_ONE:
		SkinState.lend(id)
	t.check(player.presses_plates() and player.crosses_webs() and SkinState.is_on(player, SkinState.FERAL),
		"the three skins do not all work at once")
	for look: StringName in [&"", SkinState.HEAVY, SkinState.SILK, SkinState.FERAL]:
		SkinState.set_look(look)
		t.check(player.presses_plates() and player.crosses_webs() and SkinState.is_on(player, SkinState.FERAL),
			"a skin stopped working with the look %s" % look)


## A skin shows while it works (SkinState.show), for `skins.lookShowMs`, then the everyday look.
func test_a_skin_shows_while_it_works_then_the_everyday_look(t: TestContext) -> void:
	var player := t.player()
	var skin_material := player.get_visual().material as ShaderMaterial
	if not t.check(skin_material != null, "the Visual has no skin material"):
		return
	SkinState.lend(SkinState.HEAVY)
	SkinState.lend(SkinState.FERAL)
	SkinState.set_look(&"")
	await t.steps(4)
	t.equal(player.shown_skin(), &"", "a skin shows with the goo picked and nothing at work")
	player.show_skin(SkinState.HEAVY)
	await t.until(func() -> bool: return float(skin_material.get_shader_parameter(&"skin_amount")) >= 1.0, 600.0)
	t.equal(player.shown_skin(), SkinState.HEAVY, "the Heavy skin does not show while it works")
	t.equal(int(skin_material.get_shader_parameter(&"skin")), SkinState.look_index(SkinState.HEAVY), "the Heavy look's pattern")
	var wait := SkinState.setting("lookShowMs", 900.0) + SkinState.setting("lookFadeOutMs", 320.0) + 300.0
	t.check(await t.until(func() -> bool: return player.shown_skin() == &"", wait, wait + 2000.0),
		"the Heavy look stays after it stopped working")
	SkinState.set_look(SkinState.FERAL)
	await t.until(func() -> bool: return player.shown_skin() == SkinState.FERAL, 600.0)
	t.equal(int(skin_material.get_shader_parameter(&"skin")), SkinState.look_index(SkinState.FERAL), "the Feral everyday look")


func test_a_heavy_roll_breaks_old_things_and_a_plain_roll_bonks_off(t: TestContext) -> void:
	var rock := _spawn(t, "object.loose-rock", OPEN + Vector2(150.0, CENTRE_RISE))
	var trunk := _spawn(t, "object.old-trunk", OPEN + Vector2(0.0, 260.0))
	var fence := _spawn(t, "object.old-fence", OPEN + Vector2(260.0, 260.0))
	if rock == null or trunk == null or fence == null:
		return
	await t.steps(2)
	# Without the skin: a Roll into the rock bonks; Roll hits on the wood are refused.
	await _roll_right(t)
	t.check(not bool(rock.call(&"is_broken")), "a plain Roll broke the loose rock")
	for thing: Node in [trunk, fence]:
		_route(t, thing.get_node(^"DamageArea") as Area2D, ["roll"])
	await t.steps(2)
	t.check(not bool(trunk.call(&"is_smashed")) and not bool(fence.call(&"is_smashed")), "a plain Roll smashed old wood")
	# With it: the same Roll breaks the rock, and a Heavy Roll's bonk smashes the wood.
	SkinState.lend(SkinState.HEAVY)
	await t.sim_wait(_movement("rollCooldownMs") + 200.0)
	await _roll_right(t)
	t.check(await t.until(func() -> bool: return bool(rock.call(&"is_broken")), 600.0), "a Heavy Roll did not break the loose rock")
	for thing: Node in [trunk, fence]:
		_route(t, thing.get_node(^"DamageArea") as Area2D, ["roll", "heavy"])
	await t.steps(2)
	t.check(bool(trunk.call(&"is_smashed")) and bool(fence.call(&"is_smashed")), "a Heavy Roll did not smash old wood")


func test_a_heavy_shake_knocks_a_loose_prize_down(t: TestContext) -> void:
	var run := Services.run()
	var prize := _spawn(t, "object.loose-prize", OPEN + Vector2(0.0, 200.0))
	if prize == null:
		return
	await t.steps(2)
	var coins := run.coins()
	var at := prize.global_position + Vector2(30.0, 0.0)
	prize.call(&"on_ground_shake", at, 200.0, false)
	t.check(not bool(prize.call(&"is_fallen")), "a plain bonk's shake knocked the prize down")
	prize.call(&"on_ground_shake", at + Vector2(400.0, 0.0), 200.0, true)
	t.check(not bool(prize.call(&"is_fallen")), "a heavy shake out of reach knocked the prize down")
	prize.call(&"on_ground_shake", at, 200.0, true)
	t.check(bool(prize.call(&"is_fallen")), "a heavy shake did not knock the prize down")
	var pays := int(prize.get(&"coins"))
	t.check(await t.until(func() -> bool: return run.coins() == coins + pays, 2000.0), "the fallen prize did not pay its coins")


func test_the_feral_skin_climbs_while_interact_is_held(t: TestContext) -> void:
	var player := t.player()
	var up := _spawn(t, "object.climb-wall", Vector2(CLIMB_X, FACE_FOOT_Y))
	var down := _spawn(t, "object.climb-wall", Vector2(CLIMB_X, 2150.0))
	if up == null or down == null:
		return
	up.set(&"top", Vector2(0.0, -170.0))
	down.set(&"top", Vector2(0.0, 165.0))
	down.set(&"show_art", false)
	await _stand(t, FOOT_FEET, Vector2.UP)
	# Without the skin nothing climbs.
	t.press(&"interact")
	await t.steps(4)
	t.check(not player.is_climbing(), "the slime climbed without the Feral skin")
	t.release(&"interact")
	SkinState.lend(SkinState.FERAL)
	await t.steps(2)
	t.press(&"interact")
	t.check(await t.until(func() -> bool: return player.is_climbing(), 300.0), "holding interact at the roots did not take hold")
	await t.steps(4)
	t.check(t.player_body().collision_mask == 0, "the climbing slime still collides with the rock")
	# The held key only clings: the movement keys move the slime over the wall.
	var clung := t.player_body().global_position
	await t.sim_wait(200.0)
	t.near_vec(t.player_body().global_position, clung, 1.0, "the slime moved on the wall with no movement key held")
	t.press(&"move_up")
	t.check(await t.until(func() -> bool: return not player.is_climbing(), 4000.0), "the climb never ended")
	t.release(&"move_up")
	t.release(&"interact")
	await t.steps(3)
	t.check(t.player_body().global_position.y < RIM_Y, "the climb did not end on the plateau (feet %s)" % t.player_body().global_position)
	t.equal(t.world().elevation.level_of(t.player_body()), 2, "the slime's level on the plateau")
	t.check(t.player_body().collision_mask != 0, "the slime's collision did not come back")
	# Back down from the lip.
	await _stand(t, Vector2(CLIMB_X, 2150.0), Vector2.DOWN)
	t.press(&"interact")
	t.check(await t.until(func() -> bool: return player.is_climbing(), 300.0), "holding interact at the lip did not take hold")
	t.press(&"move_down")
	await t.until(func() -> bool: return not player.is_climbing(), 4000.0)
	t.release(&"move_down")
	t.release(&"interact")
	await t.steps(3)
	t.check(t.player_body().global_position.y > FACE_FOOT_Y, "the climb down did not end below the face")
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the slime's level below the plateau")
	# Letting go midway drops the slime to the foot, unhurt.
	var hp := player.get_hp()
	await _stand(t, FOOT_FEET, Vector2.UP)
	# Where the climb starts: the body settles a few px below FOOT_FEET, clear of the face's foot.
	var start := t.player_body().global_position
	t.press(&"interact")
	await t.until(func() -> bool: return player.is_climbing(), 300.0)
	t.press(&"move_up")
	await t.sim_wait(350.0)
	t.release(&"move_up")
	var high := t.player_body().global_position.y
	t.check(high < start.y - 20.0, "the slime did not climb before letting go")
	t.release(&"interact")
	t.check(await t.until(func() -> bool: return not player.is_climbing(), 1500.0), "letting go midway did not drop the slime")
	await t.steps(3)
	t.near_vec(t.player_body().global_position, start, 1.0, "the drop's landing (where the climb started)")
	t.check(t.player_body().global_position.y > FACE_FOOT_Y, "the drop landed on the face")
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the level after the drop")
	t.equal(player.get_hp(), hp, "the fall cost health")


func test_painted_vines_are_clung_to_and_crossed_any_way(t: TestContext) -> void:
	var player := t.player()
	var body := t.player_body()
	# Vines on the plateau's face: one column from rim to foot, and beside it only the lower row.
	var layer := VineLayerScript.new()
	layer.name = "test-vines"
	layer.tile_set = load(VineLayerScript.TILESET)
	t.world().world_root.add_child(layer)
	for cell: Vector2i in [VINES_CELL, VINES_CELL + Vector2i.DOWN, VINES_CELL + Vector2i(1, 1)]:
		layer.set_cell(cell, 0, Vector2i.ZERO)
	await t.steps(2)
	var column_x := (VINES_CELL.x + 0.5) * 64.0
	var foot := Vector2(column_x, 2330.0)
	SkinState.lend(SkinState.FERAL)
	await _stand(t, foot, Vector2.UP)
	t.press(&"interact")
	if not t.check(await t.until(func() -> bool: return player.is_climbing(), 300.0), "holding interact at the vines' foot did not take hold"):
		t.release_all()
		layer.queue_free()
		return
	await t.steps(6)
	var clung := body.global_position
	await t.sim_wait(200.0)
	t.near_vec(body.global_position, clung, 1.0, "the slime moved on the vines with no movement key held")
	# Sideways onto the next column.
	t.press(&"move_right")
	await t.sim_wait(450.0)
	t.release(&"move_right")
	var column_end := (VINES_CELL.x + 2) * 64.0
	t.check(body.global_position.x > column_end - 64.0, "the slime did not cross onto the next column of vines (feet %s)" % body.global_position)
	t.check(player.is_climbing() and not player.get_climb().is_falling(), "the slime let go on the vines' second column")
	# That column stops short of the rim: no way up it.
	t.press(&"move_up")
	await t.sim_wait(700.0)
	t.release(&"move_up")
	t.check(player.is_climbing(), "the slime got off vines that stop short of the rim")
	t.check(body.global_position.y > RIM_Y + 64.0, "the slime climbed past the vines' top (feet %s)" % body.global_position)
	# Letting go drops it before the wall's foot, unhurt.
	var hp := player.get_hp()
	t.release(&"interact")
	t.check(await t.until(func() -> bool: return not player.is_climbing(), 1500.0), "letting go did not drop the slime")
	await t.steps(3)
	t.check(body.global_position.y > FACE_FOOT_Y, "the drop landed on the face (feet %s)" % body.global_position)
	t.equal(t.world().elevation.level_of(body), 0, "the level after the drop")
	t.equal(player.get_hp(), hp, "the fall cost health")
	# A catch: the key pressed again as the slime drops takes hold right there.
	await _stand(t, foot, Vector2.UP)
	t.press(&"interact")
	await t.until(func() -> bool: return player.is_climbing(), 300.0)
	t.press(&"move_up")
	await t.sim_wait(500.0)
	t.release(&"move_up")
	t.release(&"interact")
	t.check(await t.until(func() -> bool: return player.get_climb().is_falling(), 300.0), "letting go did not start a drop")
	t.press(&"interact")
	await t.steps(3)
	t.check(player.is_climbing() and not player.get_climb().is_falling(), "the key pressed again did not catch the vines mid-drop")
	t.check(body.global_position.y < FACE_FOOT_Y, "the catch was not on the face (feet %s)" % body.global_position)
	t.release(&"interact")
	await t.until(func() -> bool: return not player.is_climbing(), 1500.0)
	await t.steps(3)
	# No limit at the vines' side (the owner, 2026-11-13): moved off it, the slime falls, unhurt.
	await _stand(t, foot, Vector2.UP)
	t.press(&"interact")
	await t.until(func() -> bool: return player.is_climbing(), 300.0)
	t.press(&"move_up")
	await t.sim_wait(300.0)
	t.release(&"move_up")
	t.press(&"move_left")
	t.check(await t.until(func() -> bool: return player.get_climb().is_falling() or not player.is_climbing(), 1200.0),
		"moving off the vines' side did not drop the slime")
	t.release(&"move_left")
	t.check(body.global_position.x < VINES_CELL.x * 64.0, "the slime fell before it was off the vines' side (feet %s)" % body.global_position)
	t.check(await t.until(func() -> bool: return not player.is_climbing(), 1500.0), "the fall off the vines' side never ended")
	t.release_all()
	await t.steps(3)
	t.check(body.global_position.y > FACE_FOOT_Y, "the fall off the side landed on the face (feet %s)" % body.global_position)
	t.equal(t.world().elevation.level_of(body), 0, "the level after the fall off the side")
	t.equal(player.get_hp(), hp, "the fall off the side cost health")
	# Up the whole column: pushing on at the rim gets the slime onto the plateau.
	await _stand(t, foot, Vector2.UP)
	t.press(&"interact")
	await t.until(func() -> bool: return player.is_climbing(), 300.0)
	t.press(&"move_up")
	t.check(await t.until(func() -> bool: return not player.is_climbing(), 4000.0), "the climb up the vines never ended")
	t.release_all()
	await t.steps(3)
	t.check(body.global_position.y < RIM_Y, "the climb did not end on the plateau (feet %s)" % body.global_position)
	t.equal(t.world().elevation.level_of(body), 2, "the slime's level on the plateau")
	# From the lip, facing down, and off at the foot.
	await _stand(t, Vector2(column_x, 2150.0), Vector2.DOWN)
	t.press(&"interact")
	t.check(await t.until(func() -> bool: return player.is_climbing(), 300.0), "holding interact on the lip over the vines did not take hold")
	t.press(&"move_down")
	t.check(await t.until(func() -> bool: return not player.is_climbing(), 4000.0), "the climb down the vines never ended")
	t.release_all()
	await t.steps(3)
	t.check(body.global_position.y > FACE_FOOT_Y, "the climb down did not end below the face (feet %s)" % body.global_position)
	t.equal(t.world().elevation.level_of(body), 0, "the slime's level below the plateau")
	layer.queue_free()


func test_the_feral_spear_strikes_twice_as_fast(t: TestContext) -> void:
	await _enter_shapes_mode(t)
	var shapes: Node = t.player().get_shapes()
	if not t.check(shapes != null, "the body-shapes mode has no ShapeController"):
		return
	shapes.call(&"set_current", ShapeDefs.SPEAR)
	await t.steps(2)
	if not t.check(StringName(shapes.call(&"current_shape_id")) == ShapeDefs.SPEAR, "the Spear is not the shape"):
		return
	t.teleport_player(OPEN)
	await t.steps(3)
	var plain := await _step_length(t, shapes)
	await t.sim_wait(1200.0)
	SkinState.lend(SkinState.FERAL)
	var feral := await _step_length(t, shapes)
	t.check(plain > 0.0 and feral > 0.0, "a Spear tap did not run a step (%.0f, %.0f ms)" % [plain, feral])
	t.check(feral <= plain * 0.65, "the Feral Spear's step is not twice as fast (%.0f ms against %.0f)" % [feral, plain])


func test_the_bag_skins_row_picks_only_the_look(t: TestContext) -> void:
	await _enter_shapes_mode(t)
	SkinState.lend(SkinState.HEAVY)
	SkinState.lend(SkinState.SILK)
	var menus: Node = t.main.get(&"menu_windows")
	if not t.check(menus != null and bool(menus.call(&"open_bag")), "the bag did not open"):
		return
	await t.steps(2)
	var bag: Node = menus.get(&"bag")
	var row := bag.get(&"skin_list") as Container
	if t.check(row != null, "the bag has no Skins row"):
		t.equal(row.get_child_count(), 3, "the Skins row's looks (the goo and two skins)")
		t.check(row.visible, "the Skins row hides with skins on")
	bag.call(&"choose_skin", SkinState.SILK)
	t.equal(SkinState.look(), SkinState.SILK, "choosing Silk in the bag")
	bag.call(&"choose_skin", &"")
	t.equal(SkinState.look(), &"", "choosing the goo in the bag")
	t.check(t.player().presses_plates() and t.player().crosses_webs(), "picking a look turned a skin off")
	bag.call(&"close")


# --- helpers ---------------------------------------------------------------------------------------

func _spawn(t: TestContext, scene_id: String, at: Vector2) -> Node2D:
	var node := t.world().instantiate_scene(scene_id) as Node2D
	if not t.check(node != null, "%s did not load" % scene_id):
		return null
	node.position = at
	t.world().world_root.add_child(node)
	return node


## The slime's feet at `feet`, facing `facing`, its level where it stands.
func _stand(t: TestContext, feet: Vector2, facing: Vector2) -> void:
	t.release_all()
	t.teleport_player(feet - Vector2(0.0, CENTRE_RISE))
	t.player().face(facing)
	t.world().elevation.track(t.player_body())
	await t.steps(3)


## A Roll to the right from OPEN, until it is over.
func _roll_right(t: TestContext) -> void:
	t.teleport_player(OPEN)
	t.player().face(Vector2.RIGHT)
	await t.steps(2)
	t.tap(&"dodge")
	await t.until(func() -> bool: return t.player().is_rolling(), 200.0)
	await t.until(func() -> bool: return not t.player().is_rolling(), 2500.0)
	await t.steps(2)


## How long (gameplay ms) one Spear tap keeps the controller busy (its first chain step).
func _step_length(t: TestContext, shapes: Node) -> float:
	t.tap(&"attack")
	if not await t.until(func() -> bool: return bool(shapes.call(&"is_busy")), 500.0):
		return 0.0
	var started := t.now()
	await t.until(func() -> bool: return not bool(shapes.call(&"is_busy")), 2000.0)
	return t.now() - started


## The playground again with the body-shapes mode on (the test runner keeps it off).
func _enter_shapes_mode(t: TestContext) -> void:
	t.main.call(&"travel_to", MAP_ID)
	await t.until(func() -> bool: return ReworkMode.is_on() and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")), 3000.0)
	await t.steps(2)


func _route(t: TestContext, area: Area2D, tags: Array) -> void:
	if not t.check(area != null, "no area to hit"):
		return
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var areas: Array[Area2D] = [attack]
	var activation := router.begin_activation(source, areas)
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-" + str(tags[0]), "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 20.0,
		"effects": [], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()


static func _movement(name: String) -> float:
	return Services.constants().number("character.player.movement." + name)
