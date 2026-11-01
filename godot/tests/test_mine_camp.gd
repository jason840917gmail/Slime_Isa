extends RefCounted
## The Crystal Mine's outside (docs/godot/DUNGEONS.md "The Crystal Mine (built)"), laid by
## tools/build_mine_outside.gd: the smith's mine camp in G4 (the smith gives the Lantern once and
## teaches the gate's brazier; the brazier opens the mine's gate for good; the way in and the mine's
## way out, shut by the seal from Pearl 3's take inside until the Colossus falls), and the smith gone
## home once the Colossus fell. The climb out to the Lookout (H4) is in test_crystal_mine.gd.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const MineTravel := preload("res://game/crystal_mine/mine_travel.gd")
const MineCamp := preload("res://game/crystal_mine/mine_camp.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const MAP_ID := "crystal-caverns-g4"
const MINE_ID := "crystal-mine"
const CELL := 64.0


func test_the_camp_has_the_smith_the_shut_gate_and_its_cold_brazier(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	var outside := _outside(t)
	if not t.check(outside != null, "G4 has no MineOutside"):
		return
	var smith := outside.get_node_or_null("smith") as Node2D
	t.check(smith != null and smith.visible, "the smith is not at his camp")
	t.check(smith != null and smith.is_in_group(&"usable"), "the smith cannot be talked to")
	t.check(not bool(outside.get_node("mine-gate").call(&"is_open")), "the mine's gate starts open")
	t.check(not bool(outside.get_node("mine-gate-brazier").call(&"is_lit")), "the gate's brazier starts lit")
	t.check(outside.get_node_or_null("exit-to-crystal-mine") != null, "no way into the mine")
	t.check(outside.get_node_or_null("camp-mine-mouth") != null, "no arrival door for the mine's way out")
	t.check(t.world().elevation != null, "G4 has no elevation (the mountain)")
	# The camp is a rest spot: no worm camp is left in it.
	var enemies := t.world().world_root.get_node_or_null("Enemies")
	if enemies != null:
		for enemy: Node in enemies.get_children():
			var at := (enemy as Node2D).position
			t.check(not Rect2(3 * CELL, 0, 26 * CELL, 25 * CELL).has_point(at), "a placed enemy stands in the camp: " + enemy.name)


func test_the_smith_gives_the_lantern_once_and_teaches_the_brazier(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	var run := Services.run()
	var outside := _outside(t)
	var smith := outside.get_node("smith")
	var camp := outside.get_node("MineCamp")
	t.check(not run.has_flag(MineCamp.GIFT_FLAG), "the Lantern was given before the smith was met")
	t.check(bool(smith.call(&"use")), "talking to the smith did nothing")
	var speakers := await _close_boxes(t, smith)
	t.check("The smith" in speakers, "the smith did not speak (%s)" % [speakers])
	t.check(run.has_flag(MineCamp.GIFT_FLAG), "the smith did not give the Lantern")
	t.check(run.has_learned_ability("lantern"), "the Lantern was not learned")
	t.check(not bool(camp.call(&"give_lantern")), "the Lantern was given a second time")
	# Again while the gate is shut: the brazier's lesson, no second gift.
	t.check(bool(smith.call(&"use")), "a second talk did nothing")
	var again := await _close_boxes(t, smith)
	t.check(again.size() >= 1, "the smith said nothing the second time")


func test_the_brazier_opens_the_mine_gate_for_good(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	var outside := _outside(t)
	var gate := outside.get_node("mine-gate")
	var brazier := outside.get_node("mine-gate-brazier")
	t.check(bool(brazier.call(&"receive_fire", {})), "the brazier did not take the flame")
	await t.steps(2)
	t.check(bool(brazier.call(&"is_lit")), "the brazier did not light")
	t.check(bool(gate.call(&"is_open")), "the lit brazier did not open the gate")
	t.check(DungeonState.is_done(t.tree, "lantern-gate:crystal-mine-gate") or bool(gate.call(&"is_open")), "the gate's opening is not kept")
	# Built again, the gate is still open and the brazier still burns.
	t.main.call(&"travel_to", "crystal-caverns-h4")
	await t.until(func() -> bool: return t.in_world("crystal-caverns-h4") and t.player_body() != null, 8000.0)
	if not await _enter(t, MAP_ID):
		return
	t.check(bool(_outside(t).get_node("mine-gate").call(&"is_open")), "the gate shut again when G4 was built again")
	t.check(bool(_outside(t).get_node("mine-gate-brazier").call(&"is_lit")), "the brazier went out when G4 was built again")


func test_the_open_gate_leads_into_the_mine_and_its_way_out_comes_back(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	var outside := _outside(t)
	outside.get_node("mine-gate").call(&"open_for_good")
	await t.steps(4)
	_stand(t, Vector2(16 * CELL, 11.8 * CELL))
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
	if not t.check(out, "the mine's south doorway did not lead out to the camp"):
		return
	await t.steps(8)
	var marker := _outside(t).get_node("camp-mine-mouth") as Node2D
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
	# His fall breaks the seal: the mouth leads out to the camp again.
	DungeonState.mark_boss_beaten(run, MINE_ID, "crystal-colossus")
	await t.until(func() -> bool: return not bool(seal.call(&"is_shut")), 3000.0)
	t.check(not bool(seal.call(&"is_shut")), "the mouth's seal did not sink when the Colossus fell")
	_stand(t, Vector2(24 * CELL, 68.6 * CELL))
	await t.steps(4)
	t.press(&"move_down")
	var out := await t.until(func() -> bool: return t.in_world(MAP_ID) and t.player_body() != null, 6000.0)
	t.release(&"move_down")
	t.check(out, "the unsealed mouth did not lead out to the camp")


func test_once_the_colossus_fell_the_smith_has_gone_home(t: TestContext) -> void:
	if not await _enter(t, MAP_ID):
		return
	var run := Services.run()
	(run.world.get_or_add("defeated_boss_ids", []) as Array).append("crystal-colossus")
	t.main.call(&"travel_to", "crystal-caverns-h4")
	await t.until(func() -> bool: return t.in_world("crystal-caverns-h4") and t.player_body() != null, 8000.0)
	if not await _enter(t, MAP_ID):
		return
	var smith := _outside(t).get_node("smith") as Node2D
	t.check(not smith.visible, "the smith is still at the camp after the Colossus fell")
	t.check(not bool(smith.call(&"can_use")), "the smith can still be talked to after the Colossus fell")


# --- helpers ---------------------------------------------------------------------------------------

func _enter(t: TestContext, world_id: String) -> bool:
	if not t.in_world(world_id):
		t.main.call(&"travel_to", world_id)
	var arrived := await t.until(func() -> bool: return t.in_world(world_id) and t.player_body() != null, 10000.0)
	await t.steps(8)
	return t.check(arrived, "could not travel to " + world_id)


func _outside(t: TestContext) -> Node:
	return t.world().world_root.get_node_or_null("MineOutside")


## Closes every dialogue page the talk opens until the smith is free again; the speakers seen.
func _close_boxes(t: TestContext, smith: Node) -> Array:
	var speakers: Array = []
	for i in 12:
		await t.until(func() -> bool:
			var b := t.tree.get_first_node_in_group(&"dialogue_box")
			return (b != null and bool(b.call(&"is_open"))) or bool(smith.call(&"can_use")), 2000.0)
		var box := t.tree.get_first_node_in_group(&"dialogue_box")
		if box != null and bool(box.call(&"is_open")):
			speakers.append(str(box.call(&"speaker")))
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
