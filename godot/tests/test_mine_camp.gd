extends RefCounted
## The Crystal Mine's outside since the Spiral (roadmap 12.9; docs/godot/DUNGEONS.md "Outside: the
## Spiral"), laid by tools/build_caverns_spiral.gd and tools/build_caverns_rooms.gd: the mine's gate
## in G4's first yard (shut, its brazier cold; one flame opens it for good; the way in and the mine's
## way out, shut by the seal from Pearl 3's take inside until the Colossus falls), and the smith in his
## ore cave in the peak's face (`crystal-caverns-smith-cave`): the first talk gives the Lantern and, in
## the same visit, the Smith's Crystal (`mine-crystal`, for Pip's bow rune; none when the Bow is
## learned already), then his lamp's lesson; the lamp frees his cart, which rides once, one way, down
## to the yard; he stays in his cave once the Colossus fell (owner, 2026-11-20). The climb out to the
## Lookout (H4) is in test_crystal_mine.gd.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const MineTravel := preload("res://game/crystal_mine/mine_travel.gd")
const MineCamp := preload("res://game/crystal_mine/mine_camp.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const MAP_ID := "crystal-caverns-g4"
const CAVE_ID := "crystal-caverns-smith-cave"
const MINE_ID := "crystal-mine"
const CELL := 64.0
## The gate in the yard's mountain face (tools/build_caverns_spiral.gd: cell (4, 22)).
const GATE_FEET := Vector2(4 * CELL, 22.8 * CELL)


func test_the_yard_has_the_shut_gate_its_cold_brazier_and_the_carts_empty_end(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	var spiral := _spiral(t)
	if not t.check(spiral != null, "G4 has no Spiral"):
		return
	t.check(not bool(spiral.get_node("mine-gate").call(&"is_open")), "the mine's gate starts open")
	t.check(not bool(spiral.get_node("mine-gate-brazier").call(&"is_lit")), "the gate's brazier starts lit")
	t.check(spiral.get_node_or_null("exit-to-crystal-mine") != null, "no way into the mine")
	t.check(spiral.get_node_or_null("camp-mine-mouth") != null, "no arrival door for the mine's way out")
	t.check(spiral.get_node_or_null("yard-cart") != null, "no arrival door for the smith's cart")
	var station := spiral.get_node("yard-cart-station")
	t.check(not bool(station.call(&"has_cart")), "the smith's cart stands in the yard before it was ridden")
	t.check(not bool(station.call(&"can_use")), "the yard's end of the cart line can be ridden")
	t.check(t.world().elevation != null, "G4 has no elevation")


func test_the_first_talk_gives_the_lantern_and_the_crystal_and_teaches_the_lamp(t: TestContext) -> void:
	if not await _enter(t, CAVE_ID):
		return
	var run := Services.run()
	var smith := _cave(t, "smith")
	var camp := _cave(t, "MineCamp")
	t.check(smith != null and (smith as Node2D).visible, "the smith is not in his cave")
	t.check(not run.has_flag(MineCamp.GIFT_FLAG), "the Lantern was given before the smith was met")
	t.check(bool(smith.call(&"use")), "talking to the smith did nothing")
	var pages: Array[String] = []
	var speakers := await _close_boxes(t, smith, pages)
	t.check("The smith" in speakers, "the smith did not speak (%s)" % [speakers])
	t.check(run.has_flag(MineCamp.GIFT_FLAG), "the smith did not give the Lantern")
	t.check(run.has_learned_ability("lantern"), "the Lantern was not learned")
	t.check(run.has_flag(MineCamp.CRYSTAL_FLAG), "the smith did not give his crystal in the same visit")
	t.equal(run.item_count(MineCamp.CRYSTAL_ITEM), 1, "the smith's crystal in the bag")
	t.check(pages.size() >= MineCamp.TEACH.size() and pages.slice(pages.size() - MineCamp.TEACH.size()) == MineCamp.TEACH,
			"the first talk does not end with the lamp's lesson (%s)" % [pages])
	t.check(not bool(camp.call(&"give_lantern")), "the Lantern was given a second time")
	t.check(not bool(camp.call(&"give_crystal")), "the crystal was given a second time")
	# Again while the lamp is cold: the lesson again, no second gift.
	t.check(bool(smith.call(&"use")), "a second talk did nothing")
	pages.clear()
	await _close_boxes(t, smith, pages)
	t.equal(pages, MineCamp.TEACH, "the smith's lines while his lamp is cold")


func test_the_lamp_frees_the_cart_which_rides_once_one_way_to_the_yard(t: TestContext) -> void:
	if not await _enter(t, CAVE_ID):
		return
	var run := Services.run()
	var cart := _cave(t, "smith-cart")
	var lamp := _cave(t, "smith-cave-lamp")
	t.check(bool(cart.call(&"has_cart")), "the smith's cart is not in his cave")
	t.check(not bool(cart.call(&"use")), "the cart rode with the lamp cold")
	t.check(not run.has_flag("smith-cart.ridden"), "the cold cart counts as ridden")
	t.check(bool(lamp.call(&"receive_fire", {})), "the lamp did not take the flame")
	await t.steps(2)
	t.check(run.has_flag(MineCamp.LAMP_FLAG), "the lit lamp set no flag")
	t.check(bool(cart.call(&"use")), "the cart did not ride with the lamp lit")
	var down := await t.until(func() -> bool: return t.in_world(MAP_ID) and t.player_body() != null, 8000.0)
	if not t.check(down, "the cart did not take the slime down to the yard"):
		return
	await t.steps(8)
	var spiral := _spiral(t)
	var arrival := spiral.get_node("yard-cart") as Node2D
	t.check(t.player().get_centre().distance_to(arrival.global_position) < 160.0, "the slime did not come out by the cart")
	var station := spiral.get_node("yard-cart-station")
	t.check(bool(station.call(&"has_cart")), "the cart does not stand in the yard after the ride")
	t.check(not bool(station.call(&"can_use")), "the cart can ride back up from the yard")


func test_the_brazier_opens_the_mine_gate_for_good(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	var spiral := _spiral(t)
	var gate := spiral.get_node("mine-gate")
	var brazier := spiral.get_node("mine-gate-brazier")
	t.check(bool(brazier.call(&"receive_fire", {})), "the brazier did not take the flame")
	await t.steps(2)
	t.check(bool(brazier.call(&"is_lit")), "the brazier did not light")
	t.check(bool(gate.call(&"is_open")), "the lit brazier did not open the gate")
	t.check(Services.run().has_flag(MineCamp.GATE_FLAG), "the lit brazier set no flag for the smith")
	t.check(DungeonState.is_done(t.tree, "lantern-gate:crystal-mine-gate") or bool(gate.call(&"is_open")), "the gate's opening is not kept")
	# Built again, the gate is still open and the brazier still burns.
	t.main.call(&"travel_to", "crystal-caverns-h4")
	await t.until(func() -> bool: return t.in_world("crystal-caverns-h4") and t.player_body() != null, 8000.0)
	if not await _enter(t, MAP_ID):
		return
	t.check(bool(_spiral(t).get_node("mine-gate").call(&"is_open")), "the gate shut again when G4 was built again")
	t.check(bool(_spiral(t).get_node("mine-gate-brazier").call(&"is_lit")), "the brazier went out when G4 was built again")


func test_the_open_gate_leads_into_the_mine_and_its_way_out_comes_back(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	_spiral(t).get_node("mine-gate").call(&"open_for_good")
	await t.steps(4)
	_stand(t, GATE_FEET)
	await t.steps(4)
	t.press(&"move_up")
	var inside := await t.until(func() -> bool: return t.in_world(MINE_ID) and t.player_body() != null, 6000.0)
	t.release(&"move_up")
	if not t.check(inside, "walking into the open gate did not enter the mine"):
		return
	await t.steps(8)
	var arrival := t.world().world_root.get_node("mine-entrance") as Node2D
	t.check(t.player().get_centre().distance_to(arrival.global_position) < 160.0, "the slime did not arrive at the mine's mouth")
	# Out by the mine's south doorway: back in front of the gate.
	_stand(t, Vector2(24 * CELL, 68.6 * CELL))
	await t.steps(4)
	t.press(&"move_down")
	var out := await t.until(func() -> bool: return t.in_world(MAP_ID) and t.player_body() != null, 6000.0)
	t.release(&"move_down")
	if not t.check(out, "the mine's south doorway did not lead out to the yard"):
		return
	await t.steps(8)
	var marker := _spiral(t).get_node("camp-mine-mouth") as Node2D
	t.check(t.player().get_centre().distance_to(marker.global_position) < 160.0, "the slime did not come out in front of the gate")


func test_while_sealed_the_mines_mouth_keeps_the_slime_in_until_the_colossus_falls(t: TestContext) -> void:
	# Pearl 3 lies inside since 2026-10-17 (the Shardback's Den): its take seals the mine's mouth until
	# the Colossus falls (docs/godot/DUNGEONS.md "The seal").
	if not await _enter(t, MINE_ID):
		return
	var run := Services.run()
	t.check(DungeonState.seal(run, MINE_ID, "crystal-colossus", "crystal-colossus"), "the mine could not be sealed")
	await t.steps(4)
	var seal := t.world().world_root.get_node("Objects/M1-mouth-seal")
	t.check(bool(seal.call(&"is_shut")), "the mouth's seal is not shut while sealed")
	_stand(t, Vector2(24 * CELL, 68.0 * CELL))
	await t.steps(4)
	t.press(&"move_down")
	await t.sim_wait(1500.0)
	t.release(&"move_down")
	t.check(t.in_world(MINE_ID), "the slime walked out of the sealed mine")
	# His fall breaks the seal: the mouth leads out to the yard again.
	DungeonState.mark_boss_beaten(run, MINE_ID, "crystal-colossus")
	await t.until(func() -> bool: return not bool(seal.call(&"is_shut")), 3000.0)
	t.check(not bool(seal.call(&"is_shut")), "the mouth's seal did not sink when the Colossus fell")
	_stand(t, Vector2(24 * CELL, 68.6 * CELL))
	await t.steps(4)
	t.press(&"move_down")
	var out := await t.until(func() -> bool: return t.in_world(MAP_ID) and t.player_body() != null, 6000.0)
	t.release(&"move_down")
	t.check(out, "the unsealed mouth did not lead out to the yard")


func test_after_the_lamp_he_sends_the_slime_down_then_reminds_of_the_crystal_then_tips(t: TestContext) -> void:
	if not await _enter(t, CAVE_ID):
		return
	var run := Services.run()
	var smith := _cave(t, "smith")
	run.set_flag(MineCamp.GIFT_FLAG)
	run.set_flag(MineCamp.CRYSTAL_FLAG)
	run.set_flag(MineCamp.LAMP_FLAG)
	t.check(bool(smith.call(&"use")), "talking to the smith did nothing")
	var pages: Array[String] = []
	await _close_boxes(t, smith, pages)
	t.equal(pages, MineCamp.RIDE, "the smith's lines with the lamp lit and the gate shut")
	run.set_flag(MineCamp.GATE_FLAG)
	t.check(bool(smith.call(&"use")), "a talk with the gate open did nothing")
	pages.clear()
	await _close_boxes(t, smith, pages)
	t.equal(pages, MineCamp.CRYSTAL_AGAIN, "the smith's lines with the gate open and no Bow")
	run.learn_ability("bow")
	t.check(bool(smith.call(&"use")), "a talk with the Bow did nothing")
	pages.clear()
	await _close_boxes(t, smith, pages)
	t.equal(pages, MineCamp.TIPS, "the smith's lines with the Bow")


func test_with_the_bow_learned_first_the_smith_gives_no_crystal(t: TestContext) -> void:
	if not await _enter(t, CAVE_ID):
		return
	var run := Services.run()
	var smith := _cave(t, "smith")
	run.learn_ability("bow")
	t.check(bool(smith.call(&"use")), "talking to the smith did nothing")
	var pages: Array[String] = []
	await _close_boxes(t, smith, pages)
	t.check(run.has_flag(MineCamp.GIFT_FLAG), "the smith did not give the Lantern")
	t.check(not run.has_flag(MineCamp.CRYSTAL_FLAG), "the crystal flag was set with the Bow learned already")
	t.equal(run.item_count(MineCamp.CRYSTAL_ITEM), 0, "a crystal was given with the Bow learned already")


func test_once_the_colossus_fell_the_smith_stays_in_his_cave(t: TestContext) -> void:
	if not await _enter(t, CAVE_ID):
		return
	var run := Services.run()
	run.set_flag(MineCamp.GIFT_FLAG)
	run.set_flag(MineCamp.LAMP_FLAG)
	run.set_flag(MineCamp.GATE_FLAG)
	(run.world.get_or_add("defeated_boss_ids", []) as Array).append("crystal-colossus")
	t.main.call(&"travel_to", MAP_ID)
	await t.until(func() -> bool: return t.in_world(MAP_ID) and t.player_body() != null, 8000.0)
	if not await _enter(t, CAVE_ID):
		return
	var smith := _cave(t, "smith") as Node2D
	t.check(smith.visible, "the smith left his cave after the Colossus fell")
	t.check(bool(smith.call(&"can_use")), "the smith cannot be talked to after the Colossus fell")
	t.check(bool(smith.call(&"use")), "talking to the smith did nothing")
	var pages: Array[String] = []
	await _close_boxes(t, smith, pages)
	t.equal(pages, MineCamp.AFTER_COLOSSUS, "the smith's lines after the Colossus fell")
	t.check(not run.has_flag(MineCamp.CRYSTAL_FLAG), "the smith gave his crystal after the Colossus fell")


# --- helpers ---------------------------------------------------------------------------------------

func _enter(t: TestContext, world_id: String) -> bool:
	if not t.in_world(world_id):
		t.main.call(&"travel_to", world_id)
	var arrived := await t.until(func() -> bool: return t.in_world(world_id) and t.player_body() != null, 10000.0)
	await t.steps(8)
	return t.check(arrived, "could not travel to " + world_id)


## G4's laid maze (the yard, the gate, the cart's end).
func _spiral(t: TestContext) -> Node:
	return t.world().world_root.get_node_or_null("Spiral")


## A node of the smith's cave (under its `Objects`).
func _cave(t: TestContext, node_name: String) -> Node:
	return t.world().world_root.get_node_or_null("Objects/" + node_name)


## Closes every dialogue page the talk opens until the smith is free again; the speakers seen (and
## every box's pages appended to `pages`).
func _close_boxes(t: TestContext, smith: Node, pages: Array[String] = []) -> Array:
	var speakers: Array = []
	for i in 16:
		await t.until(func() -> bool:
			var b := t.tree.get_first_node_in_group(&"dialogue_box")
			return (b != null and bool(b.call(&"is_open"))) or bool(smith.call(&"can_use")), 2000.0)
		var box := t.tree.get_first_node_in_group(&"dialogue_box")
		if box != null and bool(box.call(&"is_open")):
			speakers.append(str(box.call(&"speaker")))
			pages.append_array(box.call(&"pages") as Array)
			box.call(&"close", true)
			await t.steps(3)
		elif bool(smith.call(&"can_use")):
			break
	return speakers


## Puts the slime's feet at `feet` and takes its level there.
func _stand(t: TestContext, feet: Vector2) -> void:
	var player := t.player()
	var offset := t.player_body().global_position - player.get_centre()
	MineTravel.place(player, feet - offset, Vector2.ZERO)
	t.player_body().velocity = Vector2.ZERO
	t.player_body().reset_physics_interpolation()
