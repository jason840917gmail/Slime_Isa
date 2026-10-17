extends RefCounted
## The Crystal Mine, Chapter 3's dungeon (docs/godot/DUNGEONS.md "The Crystal Mine (built)";
## docs/design/2026-10-16-dungeon-crystal-caverns.md; the Pearl inside it since 2026-10-17:
## docs/design/2026-10-17-pearl-mid-dungeon.md), built by tools/build_crystal_mine.gd: its rooms and
## dark rooms load; the open gaps between rooms on the main path can be walked through, the stair down
## into the Den too; the mine's own pieces work: the mine cart, the ore lift, the crystal lens, the
## crystal veil, the Dark Maze's lantern gate, the Gloomling that smothers a candle, the braziers that
## burn until put out and the slams that put them out, the rotten timbers, the climbable walls (the
## Feral skin climbs them while interact is held); the Den holds Pearl 3 behind the Shardback and its
## take seals the mine; the Feral second half (the Den's ledge, M11's rift, M12's balcony, the shaft's
## roots); and the Crystal Colossus's fight: his weak spot only while all four braziers burn and only
## from its side, his stomp putting a brazier out, his claws on the wall (three Spear hits from a
## climbing slime and he falls, stunned, his back open; the Spear strikes from the face), his fall
## breaking the seal and the climb out to the Lookout.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const MineTravel := preload("res://game/crystal_mine/mine_travel.gd")
const CandleScript := preload("res://game/world/fire/candle.gd")
const ClimbWall := preload("res://game/scripts/climb_wall.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const MAP_ID := "crystal-mine"
const LOOKOUT_ID := "crystal-caverns-h4"
const COLOSSUS_ID := "crystal-colossus"
const SHARDBACK_ID := "crystal-mine-shardback"
const CELL := 64.0
const ROOMS: PackedStringArray = ["M1-mine-mouth", "M2-lamp-tunnel", "M5-tally-room", "M3-survey-office",
	"M4-great-shaft", "M6-bat-gallery", "M7-ore-store", "M8-dark-maze", "M9-the-chasm", "M10-prism-gallery",
	"M11-crystal-veil", "M12-fort-hall", "M13-shardback-den", "M15-colossus-arena"]
const DARK_ROOMS: PackedStringArray = ["dark-M2-lamp-tunnel", "dark-M5-tally-room", "dark-M6-bat-gallery",
	"dark-M8-dark-maze", "dark-M11-crystal-veil", "dark-M13-shardback-den", "dark-M15-colossus-arena"]
const ARENA_BRAZIERS: PackedStringArray = ["M15-brazier-nw", "M15-brazier-ne", "M15-brazier-sw", "M15-brazier-se"]
const MAZE_CANDLES: PackedStringArray = ["M8-candle-nw", "M8-candle-ne", "M8-candle-sw", "M8-candle-se"]
## Walks through the open gaps of the main path: [the slime's feet (in tiles), key, the room it ends
## in]. The gaps a lock shuts (the shutter, the rotten timbers, the Foreman's Gate, the maze's gate, the
## bridge, the veil, the Den's shutters, the boss door, the seal) are tested with their pieces.
const WALKS := [
	[Vector2(28.0, 60.0), &"move_up", "M2-lamp-tunnel"],
	[Vector2(28.0, 45.5), &"move_up", "M4-great-shaft"],
	[Vector2(20.0, 50.5), &"move_left", "M5-tally-room"],
	[Vector2(46.0, 39.5), &"move_down", "M6-bat-gallery"],
	[Vector2(34.5, 6.0), &"move_left", "M8-dark-maze"],
	[Vector2(46.0, 21.6), &"move_right", "M11-crystal-veil"],
	[Vector2(62.0, 21.6), &"move_right", "M12-fort-hall"],
]
const WALK_MS := 2400.0
const ARENA_FEET := Vector2(53.0, 37.5)
## M15's roots beside his climb spots (x 50, 53, 56, 59) and the one this file's claw tests climb.
const CLAW_ROOTS := "M15-claw-roots-2"


func test_the_mine_loads_with_its_rooms_and_dark_rooms(t: TestContext) -> void:
	if not await _enter(t):
		return
	var root: Node2D = t.world().world_root
	t.check(t.world().elevation != null, "the mine has no elevation")
	var rooms := root.get_node_or_null("CameraRooms")
	if t.check(rooms != null, "the mine has no CameraRooms"):
		t.equal(rooms.get_child_count(), ROOMS.size(), "camera rooms")
		for room_name: String in ROOMS:
			t.check(rooms.has_node(room_name), "no camera room " + room_name)
	var dark := root.get_node_or_null("DarkRooms")
	if t.check(dark != null, "the mine has no DarkRooms"):
		for room_name: String in DARK_ROOMS:
			t.check(dark.has_node(room_name), "no dark room " + room_name)
	var dungeon := root.get_node_or_null("Dungeon")
	if t.check(dungeon != null, "the mine has no Dungeon node"):
		t.equal(str(dungeon.get(&"dungeon_id")), MAP_ID, "the dungeon's id")
		t.equal(str(dungeon.get(&"boss_id")), COLOSSUS_ID, "the boss whose fall breaks the seal")
	t.check(root.get_node_or_null("dungeon-entrance") != null, "no dungeon-entrance marker")
	t.equal(_room_at(t), "M1-mine-mouth", "the room the slime arrives in")
	var markers := root.get_node_or_null("KitMarkers")
	if markers != null:
		for marker: Node in markers.get_children():
			t.check(marker.has_meta(&"kit"), "kit marker %s has no kind" % marker.name)


func test_the_open_gaps_of_the_main_path_can_be_walked_through(t: TestContext) -> void:
	if not await _enter(t):
		return
	for walk: Array in WALKS:
		_stand(t, _t(walk[0]))
		await t.steps(4)
		t.press(walk[1])
		var ended := await t.until(func() -> bool: return _room_at(t) == walk[2], WALK_MS)
		t.release(walk[1])
		t.check(ended, "walking %s from %s did not reach %s (in %s)" % [walk[1], walk[0], walk[2], _room_at(t)])
		await t.steps(4)


func test_the_chasms_far_side_leads_down_a_stair_into_the_den(t: TestContext) -> void:
	if not await _enter(t):
		return
	# M9's old door east to M10 is bricked: the far rim's only way on is the stair south.
	t.check(not t.world().elevation.is_walkable(_t(Vector2(47.5, 5.5)), 0), "M9's old doorway to M10 is still open")
	_stand(t, _t(Vector2(45.0, 12.3)))
	await t.steps(4)
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the slime's level on the far rim")
	t.press(&"move_down")
	var down := await t.until(func() -> bool: return t.player_body().global_position.y > 17.4 * CELL, 5000.0)
	t.release(&"move_down")
	t.check(down, "walking south from the far rim did not go down the stair (feet at %.1f)" % (t.player_body().global_position.y / CELL))
	await t.steps(6)
	t.equal(_room_at(t), "M13-shardback-den", "the room at the stair's foot")
	t.equal(t.world().elevation.level_of(t.player_body()), -1, "the slime's level on the Den's floor")


func test_the_mine_cart_rides_between_the_chasm_and_the_mine_mouth(t: TestContext) -> void:
	if not await _enter(t):
		return
	var objects := _objects(t)
	var chasm: Node = objects.get_node("M9-cart-station")
	var mouth: Node = objects.get_node("M1-cart-station")
	t.check(bool(chasm.call(&"has_cart")), "the cart does not start at the Chasm")
	t.check(not bool(mouth.call(&"can_use")), "the empty station at the Mine Mouth can be ridden")
	t.check(not bool(mouth.call(&"use")), "riding from the empty station did something")
	_stand(t, (chasm as Node2D).global_position + Vector2(0, -60))
	await t.steps(4)
	t.check(bool(chasm.call(&"use")), "the cart at the Chasm cannot be ridden")
	var arrived := await t.until(func() -> bool: return _room_at(t) == "M1-mine-mouth", 3000.0)
	t.check(arrived, "the ride did not bring the slime to the Mine Mouth (in %s)" % _room_at(t))
	await t.sim_wait(600.0)
	t.check(bool(mouth.call(&"has_cart")), "the cart did not come to the Mine Mouth")
	t.check(not bool(chasm.call(&"has_cart")), "the cart is still at the Chasm")
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the slime's level after the ride")
	t.check(bool(mouth.call(&"use")), "the cart cannot be ridden back")
	var back := await t.until(func() -> bool: return _room_at(t) == "M9-the-chasm", 3000.0)
	t.check(back, "the ride back did not reach the Chasm")


func test_the_ore_lift_runs_from_the_gallery_only_once_worked_from_below(t: TestContext) -> void:
	if not await _enter(t):
		return
	var objects := _objects(t)
	var upper: Node = objects.get_node("M4-lift-upper")
	var lower: Node = objects.get_node("M4-lift-lower")
	t.check(not bool(upper.call(&"can_use")), "the lift is offered from the gallery before it was worked")
	t.check(bool(lower.call(&"can_use")), "the lift's crank below cannot be worked")
	_stand(t, (lower as Node2D).global_position + Vector2(56, 0))
	await t.steps(4)
	t.equal(t.world().elevation.level_of(t.player_body()), -2, "the slime's level on the shaft's floor")
	t.check(bool(lower.call(&"use")), "working the crank did nothing")
	await t.sim_wait(1200.0)
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the slime's level on the gallery after the lift")
	t.check(t.player_body().global_position.x < (lower as Node2D).global_position.x, "the slime did not come up on the gallery")
	t.check(bool(upper.call(&"is_working")), "the lift is not working after the ride")
	t.check(bool(upper.call(&"can_use")), "the lift does not run down once worked")


func test_the_crystal_lens_is_struck_for_good_and_lowers_the_chasm_bridge(t: TestContext) -> void:
	if not await _enter(t):
		return
	var objects := _objects(t)
	var lens: Node = objects.get_node("M9-chasm-lens")
	var bridge: Node = objects.get_node("M9-chasm-bridge")
	t.check(lens.is_in_group(&"bow_targets"), "the lens is not a Bow target")
	t.check(not bool(lens.call(&"is_struck")), "the lens starts struck")
	t.check(not bool(bridge.call(&"is_lowered")), "the chasm's bridge starts lowered")
	var struck: Array = []
	lens.connect(&"struck", func(payload: Dictionary) -> void: struck.append(payload))
	t.check(bool(lens.call(&"on_arrow_hit", {})), "the lens did not take the arrow")
	t.check(bool(lens.call(&"is_struck")), "the lens is not struck")
	t.equal(struck, [{"lens_id": "chasm-bridge"}], "the lens's struck payloads")
	await t.sim_wait(1000.0)
	t.check(bool(bridge.call(&"is_lowered")), "the struck lens did not lower the bridge")
	t.check(bool(lens.call(&"on_arrow_hit", {})), "a struck lens let a second arrow fly on")
	t.equal(struck.size(), 1, "struck signals after a second arrow")
	# Across the bridge: the slime walks from the near edge to the far rim without falling.
	_stand(t, _t(Vector2(37.2, 9.0)))
	await t.steps(4)
	t.press(&"move_right")
	var across := await t.until(func() -> bool: return t.player_body().global_position.x > 44.6 * CELL, 3000.0)
	t.release(&"move_right")
	t.check(across, "the slime could not walk across the lowered bridge")
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the slime's level on the far rim")


func test_the_kit_pieces_are_tied_to_the_mines_own(t: TestContext) -> void:
	if not await _enter(t):
		return
	var objects := _objects(t)
	# The crank in M7 lifts M1's iron shutter for good.
	var crank: Node = objects.get_node("M7-crank")
	var shutter: Node = objects.get_node("M1-east-shutter")
	t.check(bool(shutter.call(&"is_shut")), "M1's east shutter starts open")
	var targets: Array = crank.get(&"targets")
	t.check(targets.size() == 1 and crank.get_node_or_null(targets[0]) == shutter, "the crank is not tied to M1's shutter")
	# The Den: a boss fight (the Shardback's id); won, its two south rim shutters sink for good.
	var fight: Node = objects.get_node("M13-den-fight")
	t.equal(str(fight.get(&"boss_id")), SHARDBACK_ID, "the Den fight's boss")
	for rim_name: String in ["M13-den-ledge", "M13-den-ledge-east"]:
		t.check(bool(objects.get_node(rim_name).call(&"is_shut")), "the Den's rim shutter %s starts open" % rim_name)
	fight.emit_signal(&"cleared", {"fightId": "shardback-den"})
	await t.sim_wait(600.0)
	for rim_name: String in ["M13-den-ledge", "M13-den-ledge-east"]:
		t.check(not bool(objects.get_node(rim_name).call(&"is_shut")), "the won Den did not open %s" % rim_name)
	# The doors: the Foreman's Gate has two keyholes, the boss door the big lock; the Den's old key
	# door and K3 are gone; the big chest is on M12's balcony.
	t.equal(int(objects.get_node("M4-foremans-gate").get(&"keyholes")), 2, "the Foreman's Gate's keyholes")
	t.equal(str(objects.get_node("M14-boss-door").get(&"lock")), "big", "the boss door's lock")
	t.check(objects.get_node_or_null("M11-den-door") == null, "the Den's key door is still there")
	t.check(objects.get_node_or_null("M12-K3-chest") == null, "K3's chest is still there")
	var big := objects.get_node_or_null("M12-big-key-chest")
	t.check(big != null and not bool(big.get_node("ChestScript").get(&"hidden")), "the big chest is not standing on M12's balcony")
	# The seal stands in the mouth and at the climb out.
	t.check(objects.get_node_or_null("M1-mouth-seal") != null, "no seal in the mine's mouth")
	t.check(bool(objects.get_node("M1-mouth-seal").get(&"glimpse")), "the mouth's seal is not the take's glimpse")
	t.check(objects.get_node_or_null("M15-climb-out-seal") != null, "no seal at the climb out")
	# The compass marks the Colossus's arena until he falls.
	var arena: Node = objects.get_node("ColossusArena")
	t.check(arena.is_in_group(&"dungeon_map_mark") and str(arena.get(&"mark")) == "boss", "the arena is not the compass's boss mark")


func test_the_crystal_veil_opens_only_while_its_brazier_burns(t: TestContext) -> void:
	if not await _enter(t):
		return
	var objects := _objects(t)
	var veil: Node = objects.get_node("M11-veil")
	var north: Node = objects.get_node("M11-brazier-north")
	await t.steps(2)
	t.check(not bool(veil.call(&"is_open")), "the veil starts open")
	# Walking at the grown veil from the north (M10's doorway): held back.
	var rect: Rect2 = veil.call(&"barrier_rect")
	_stand(t, Vector2(rect.get_center().x, rect.position.y - 50.0))
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(700.0)
	t.release(&"move_down")
	t.check(t.player_body().global_position.y < rect.position.y + 4.0, "the slime walked through the grown veil")
	north.call(&"light")
	await t.steps(3)
	t.check(bool(veil.call(&"is_open")), "the veil did not open while its brazier burns")
	# Standing in the veil when its brazier goes out: pushed out to a side.
	_stand(t, rect.get_center() + Vector2(0, -6))
	await t.steps(2)
	north.call(&"put_out")
	await t.steps(4)
	t.check(not bool(veil.call(&"is_open")), "the veil stays open with no brazier burning")
	t.check(not rect.has_point(t.player_body().global_position), "the slime was left inside the veil")
	# A timed brazier: the veil grows back when it burns down.
	north.call(&"light")
	await t.steps(2)
	t.check(bool(veil.call(&"is_open")), "the veil did not open again")
	await t.sim_wait(float(north.get(&"burn_ms")) + 500.0)
	t.check(not bool(veil.call(&"is_open")), "the veil did not grow back when the brazier burned down")


func test_the_dark_mazes_four_candles_open_its_gate_and_a_gloomling_smothers_one(t: TestContext) -> void:
	if not await _enter(t):
		return
	var objects := _objects(t)
	var gate: Node = objects.get_node("M8-exit-gate")
	var nw: Node = objects.get_node("M8-candle-nw")
	t.check(not bool(gate.call(&"is_open")), "the maze's gate starts open")
	# In the maze, so its Gloomlings are up.
	_stand(t, (nw as Node2D).global_position + Vector2(160, 40))
	var found := await t.until(func() -> bool: return _placed_enemy(t, "M8-gloomling-candle") != null, 2000.0)
	var gloomling: Node = _placed_enemy(t, "M8-gloomling-candle")
	for candle_name: String in ["M8-candle-ne", "M8-candle-sw", "M8-candle-se"]:
		objects.get_node(candle_name).call(&"light")
	await t.steps(2)
	t.check(not bool(gate.call(&"is_open")), "the gate opened with three candles")
	if t.check(found and gloomling != null, "the Gloomling on the north-west candle did not come up"):
		gloomling.set_physics_process(false)
		var shadow := gloomling.get(&"body") as Node2D
		shadow.global_position = (nw as Node2D).global_position + Vector2(0, -10)
		await t.steps(2)
		t.check(bool(nw.call(&"is_smothered")), "the Gloomling on the candle does not smother it")
		t.check(bool(nw.call(&"receive_fire", {})), "the smothered candle let the flame fly on")
		t.check(not bool(nw.call(&"is_lit")), "the smothered candle lit")
		shadow.global_position = (nw as Node2D).global_position + Vector2(320, 200)
		await t.steps(2)
		t.check(not bool(nw.call(&"is_smothered")), "the candle is still smothered once the shadow left it")
	t.check(bool(nw.call(&"receive_fire", {})), "the free candle did not take the flame")
	await t.steps(2)
	t.check(bool(nw.call(&"is_lit")), "the candle did not light once the shadow left it")
	t.check(bool(gate.call(&"is_open")), "the four candles did not open the gate")
	for candle_name: String in MAZE_CANDLES:
		objects.get_node(candle_name).call(&"put_out")
	await t.steps(2)
	t.check(bool(gate.call(&"is_open")), "the gate shut again when the candles went out")
	if gloomling != null and is_instance_valid(gloomling):
		gloomling.set_physics_process(true)


func test_braziers_burn_until_put_out_and_a_slam_puts_out_only_the_stomp_ones(t: TestContext) -> void:
	if not await _enter(t):
		return
	var objects := _objects(t)
	var nw: Node = objects.get_node("M15-brazier-nw")
	var ne: Node = objects.get_node("M15-brazier-ne")
	var den: Node = objects.get_node("M13-brazier-w")
	var lamp: Node = objects.get_node("M4-brazier-w")
	t.check(bool(lamp.call(&"is_lit")), "the Great Shaft's brazier does not burn from the start")
	nw.call(&"light")
	ne.call(&"light")
	await t.sim_wait(21000.0)
	t.check(bool(nw.call(&"is_lit")) and bool(ne.call(&"is_lit")), "a brazier that burns until put out went out by itself")
	var put := CandleScript.put_out_near(t.tree, (nw as Node2D).global_position + Vector2(10, 0), Vector2(4000, 4000), true)
	t.equal(put, 1, "braziers the nearest-only stomp put out")
	t.check(not bool(nw.call(&"is_lit")), "the nearest brazier is still lit")
	t.check(bool(ne.call(&"is_lit")), "the farther brazier went out too")
	t.equal(CandleScript.put_out_near(t.tree, (lamp as Node2D).global_position, Vector2(200, 200)), 0, "braziers a slam put out by the shaft")
	t.check(bool(lamp.call(&"is_lit")), "a slam put out a brazier that is not stomp_puts_out")
	# The Den's braziers: the Shardback's slam ring puts them out (game/scripts/shardback.gd).
	den.call(&"light")
	t.equal(CandleScript.put_out_near(t.tree, (den as Node2D).global_position + Vector2(40, 0), Vector2(158, 108)), 1, "Den braziers a slam put out")
	t.check(not bool(den.call(&"is_lit")), "the Den's brazier is still lit after the slam")
	ne.call(&"put_out")


func test_the_rotten_timbers_break_only_under_a_heavy_roll(t: TestContext) -> void:
	if not await _enter(t):
		return
	var timbers: Node = _objects(t).get_node("M6-rotten-timbers")
	var area := timbers.get_node("DamageArea") as Area2D
	_route(t, area, ["roll"])
	t.check(not bool(timbers.call(&"is_smashed")), "a plain Roll smashed the timbers")
	_route(t, area, ["spear"])
	t.check(not bool(timbers.call(&"is_smashed")), "the Spear smashed the timbers")
	_route(t, area, ["roll", "heavy"])
	t.check(bool(timbers.call(&"is_smashed")), "a Heavy Roll did not smash the timbers")
	t.check(Services.run().has_flag(str(timbers.get(&"flag_id"))), "the smashed timbers' flag is not set")


func test_the_root_wall_needs_the_feral_skin_and_climbs_to_the_shelf(t: TestContext) -> void:
	if not await _enter(t):
		return
	var wall: Node = _objects(t).get_node("M1-root-wall")
	t.check(not bool(wall.call(&"can_use")), "the roots can be climbed without the Feral skin")
	t.check(not bool(wall.call(&"use")), "climbing without the Feral skin did something")
	SkinState.lend(SkinState.FERAL)
	_stand(t, (wall as Node2D).global_position + Vector2(0, 24))
	await t.steps(4)
	# The Feral skin climbs while the interact key is held (game/player/skins/feral_climb.gd).
	t.press(&"interact")
	t.check(bool(wall.call(&"use")), "the Feral skin did not climb the roots")
	await t.until(func() -> bool: return not bool(wall.call(&"is_climbing")), 4000.0)
	t.release(&"interact")
	await t.steps(3)
	t.equal(t.world().elevation.level_of(t.player_body()), 1, "the slime's level on the shelf")
	t.check(t.player_body().collision_mask != 0, "the slime's collision did not come back after the climb")


func test_the_den_holds_pearl_three_behind_the_shardback_and_its_take_seals_the_mine(t: TestContext) -> void:
	if not await _enter(t):
		return
	var run := Services.run()
	var objects := _objects(t)
	var pearl: Node = objects.get_node("M13-pearl-three")
	var mouth: Node = objects.get_node("M1-mouth-seal")
	t.equal(str(pearl.get(&"boss_id")), SHARDBACK_ID, "Pearl 3's guard")
	t.equal(str(pearl.get(&"skin_id")), "feral", "Pearl 3's skin")
	t.check(not bool(pearl.call(&"is_shown")), "Pearl 3 shows before the Shardback falls")
	# Into the Den from the stair: the fight starts, the north shutter closes behind the slime.
	_stand(t, _t(Vector2(39.0, 19.5)))
	var fight: Node = objects.get_node("M13-den-fight")
	var started := await t.until(func() -> bool: return bool(fight.call(&"is_active")), 3000.0)
	t.check(started, "the Den's fight did not start")
	await t.until(func() -> bool: return bool(objects.get_node("M13-den-shutter").call(&"is_shut")), 1000.0)
	t.check(bool(objects.get_node("M13-den-shutter").call(&"is_shut")), "the Den's north shutter did not close behind the slime")
	var shardback := _placed_enemy(t, "M13-shardback")
	if not t.check(shardback != null, "the Shardback is not in his Den"):
		return
	shardback.call(&"_defeat")
	var won := await t.until(func() -> bool: return bool(fight.call(&"is_done")), 4000.0)
	t.check(won, "the Den's fight was not won when the Shardback fell")
	t.check(SHARDBACK_ID in (run.world.get("defeated_boss_ids", []) as Array), "the Shardback was not recorded beaten")
	await t.until(func() -> bool: return bool(pearl.call(&"is_shown")), 1500.0)
	t.check(bool(pearl.call(&"is_shown")), "Pearl 3 did not rise when the Shardback fell")
	t.check(not bool(objects.get_node("M13-den-ledge").call(&"is_shut")), "the Den's south rim stayed shut")
	t.check(not DungeonState.is_sealed(run, MAP_ID), "the mine is sealed before the take")
	# The take: the Feral skin, and the mine sealed until the Colossus falls.
	_stand(t, (pearl as Node2D).global_position + Vector2(0, -10))
	await t.until(func() -> bool: return bool(pearl.call(&"is_taken")), 1500.0)
	t.check(bool(pearl.call(&"is_taken")), "the slime did not take Pearl 3")
	t.check(SkinState.is_won(SkinState.FERAL), "Pearl 3 did not grant the Feral skin")
	t.check(not (objects.get_node("M13-pearl-glint") as CanvasItem).visible, "Pearl 3's glint stayed after the take")
	t.check(DungeonState.is_sealed(run, MAP_ID), "taking Pearl 3 did not seal the mine")
	t.equal(DungeonState.sealed_by(run, MAP_ID), COLOSSUS_ID, "the boss who holds the seal")
	await t.until(func() -> bool: return bool(mouth.call(&"is_shut")), 3000.0)
	t.check(bool(mouth.call(&"is_shut")), "the mouth's seal is not shut after the take")


func test_the_feral_second_half_climbs_from_the_den_to_the_balcony(t: TestContext) -> void:
	if not await _enter(t):
		return
	SkinState.lend(SkinState.FERAL)
	var objects := _objects(t)
	# The teach: the root wall up the Den's ledge (-1 to 0).
	t.check(await _climb(t, objects.get_node("M13-ledge-roots")), "the climb up the Den's ledge did not finish")
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the slime's level on the Den's ledge")
	# The test: M11's rift, down the west landing's face (0 to -2), across, up the east landing's.
	t.check(await _climb(t, objects.get_node("M11-west-roots-down")), "the climb down into the rift did not finish")
	t.equal(t.world().elevation.level_of(t.player_body()), -2, "the slime's level on the rift's floor")
	var east: Node2D = objects.get_node("M11-east-roots")
	t.press(&"move_right")
	var across := await t.until(func() -> bool: return t.player_body().global_position.x >= east.global_position.x - 8.0, 6000.0)
	t.release(&"move_right")
	t.check(across, "the slime could not walk the rift's floor to the east face (at %.1f)" % (t.player_body().global_position.x / CELL))
	t.check(await _climb(t, east), "the climb up out of the rift did not finish")
	t.equal(t.world().elevation.level_of(t.player_body()), 0, "the slime's level on the east landing")
	# The twist: M12's balcony (0 to 2), the big chest on it.
	t.check(await _climb(t, objects.get_node("M12-west-roots")), "the climb up to the balcony did not finish")
	t.equal(t.world().elevation.level_of(t.player_body()), 2, "the slime's level on the balcony")
	var chest: Node2D = objects.get_node("M12-big-key-chest")
	t.check(t.player_body().global_position.distance_to(chest.global_position) < 320.0, "the big chest is not on the balcony by the roots")
	# Off the balcony's west end: a drop lands by the west door (no skin needed, no cost).
	var hp := t.player().get_hp()
	_stand(t, _t(Vector2(66.8, 17.5)))
	await t.steps(4)
	t.press(&"move_down")
	var dropped := await t.until(func() -> bool: return t.world().elevation.level_of(t.player_body()) == 0, 3000.0)
	t.release(&"move_down")
	t.check(dropped, "the slime could not drop off the balcony's west end")
	await t.steps(6)
	t.check(t.player_body().global_position.x < 68.5 * CELL, "the drop off the balcony did not land by the west door")
	t.equal(t.player().get_hp(), hp, "the drop off the balcony cost health")


func test_the_shaft_roots_join_the_den_and_the_shaft_floor(t: TestContext) -> void:
	if not await _enter(t):
		return
	SkinState.lend(SkinState.FERAL)
	var objects := _objects(t)
	for rim_name: String in ["M13-den-ledge", "M13-den-ledge-east"]:
		objects.get_node(rim_name).call(&"trigger")
	await t.sim_wait(600.0)
	t.check(await _climb(t, objects.get_node("M14-shaft-roots-down")), "the climb down the shaft's wall did not finish")
	t.equal(t.world().elevation.level_of(t.player_body()), -2, "the slime's level on the shaft's floor")
	t.equal(_room_at(t), "M4-great-shaft", "the room at the roots' foot")
	t.check(await _climb(t, objects.get_node("M14-shaft-roots")), "the climb up the shaft's wall did not finish")
	t.equal(t.world().elevation.level_of(t.player_body()), -1, "the slime's level on the Den's rim")


func test_the_colossus_is_hurt_only_through_his_open_weak_spot(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var arena: Node = fight["arena"]
	var boss: Node = fight["boss"]
	boss.set_physics_process(false)
	var hp := _hp(boss)
	t.check(not bool(boss.call(&"is_exposed")), "his weak spot is open with the braziers cold")
	_hit(t, boss, ["spear"], Vector2(0, 1))
	t.near(_hp(boss), hp, 0.1, "his health after a Spear hit with the braziers cold")
	_light_all(t)
	await t.steps(3)
	t.check(bool(arena.call(&"all_lit")), "the four braziers do not all burn")
	t.check(bool(boss.call(&"is_exposed")), "all four braziers did not open his weak spot")
	var toward := _weak_toward(boss)
	_hit(t, boss, ["spear"], -toward)
	t.near(_hp(boss), hp, 0.1, "his health after a Spear hit from the side away from the weak spot")
	_hit(t, boss, ["weapon"], toward)
	t.near(_hp(boss), hp, 0.1, "his health after a hit on the weak spot that is not the Spear's")
	_hit(t, boss, ["spear"], toward)
	t.check(_hp(boss) < hp, "a Spear hit on his open weak spot did not hurt him")
	boss.set_physics_process(true)


func test_the_colossus_stomp_puts_out_a_brazier(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var arena: Node = fight["arena"]
	var boss: Node = fight["boss"]
	t.check(bool(arena.call(&"is_fighting")), "the fight is not on")
	t.check(not bool(arena.call(&"all_lit")), "the braziers were not cold at the start")
	_light_all(t)
	await t.steps(2)
	var out := await t.until(func() -> bool:
		t.player().restore_run_state({"hp": t.player().get_max_hp()})
		return not bool(arena.call(&"all_lit")), 9000.0)
	t.check(out, "his stomps did not put out a brazier")
	t.check(arena.call(&"get_live_boss") == boss, "the fight was reset while he stomped")
	var still := 0
	for brazier_name: String in ARENA_BRAZIERS:
		if bool(_objects(t).get_node(brazier_name).call(&"is_lit")):
			still += 1
	t.equal(still, 3, "braziers still burning after his first stomp")
	await t.steps(2)
	t.check(not bool(boss.call(&"is_exposed")), "his weak spot stayed open with a brazier out")


func test_the_colossus_loses_his_grip_to_three_claw_hits_and_lies_stunned(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var arena: Node = fight["arena"]
	var boss: Node = fight["boss"]
	SkinState.lend(SkinState.FERAL)
	_light_all(t)
	if not await _onto_the_wall(t, boss):
		return
	var hp := _hp(boss)
	# A Spear hit from the floor does not reach his claws; the climbing slime's does.
	_hit_from_here(t, boss, ["spear"])
	t.equal(int(boss.call(&"claw_hits")), 0, "a hit from the floor counted on his claws")
	var roots: Node2D = _objects(t).get_node(CLAW_ROOTS)
	if not await _cling_at_top(t, roots):
		return
	t.check(bool(arena.call(&"is_fighting")), "climbing his wall ended the fight")
	_hit_from_here(t, boss, ["weapon"])
	t.equal(int(boss.call(&"claw_hits")), 0, "a hit that is not the Spear's counted on his claws")
	for i in 3:
		_hit_from_here(t, boss, ["spear"])
		await t.steps(1)
	t.near(_hp(boss), hp, 0.1, "his health after the claw hits")
	var down := await t.until(func() -> bool: return bool(boss.call(&"is_stunned")), 2000.0)
	t.check(down, "three Spear hits on his claws did not bring him down (phase %s)" % boss.get(&"_phase"))
	t.check(bool(arena.call(&"all_lit")), "his crash put out a brazier")
	# Stunned, his back open: a Spear hit from any side lands.
	t.release(&"interact")
	await t.sim_wait(450.0)
	var stunned_hp := _hp(boss)
	_hit(t, boss, ["spear"], Vector2(0, 1))
	t.check(_hp(boss) < stunned_hp, "a Spear hit on his open back did not hurt him")
	var up := await t.until(func() -> bool:
		t.player().restore_run_state({"hp": t.player().get_max_hp()})
		return not bool(boss.call(&"is_stunned")), 4000.0)
	t.check(up, "he did not get up after his stun")


func test_the_spear_strikes_his_claws_from_the_face(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var boss: Node = fight["boss"]
	# The body-shapes mode with the Spear (the test runner plays classic): the strike while clinging.
	ReworkMode.set_on(true)
	Services.run().learn_session_ability(String(ShapeDefs.SPEAR))
	t.main.call(&"start_rework")
	var shapes: Node = t.player().get_shapes()
	if not t.check(shapes != null, "no ShapeController in the body-shapes mode"):
		ReworkMode.set_on(false)
		return
	shapes.call(&"set_current", ShapeDefs.SPEAR)
	SkinState.lend(SkinState.FERAL)
	if not await _onto_the_wall(t, boss):
		ReworkMode.set_on(false)
		return
	var roots: Node2D = _objects(t).get_node(CLAW_ROOTS)
	if not await _cling_at_top(t, roots):
		ReworkMode.set_on(false)
		return
	var held_y := t.player_body().global_position.y
	# Toward him (he clings left of these roots): a tap of attack with the left key held.
	t.press(&"move_left")
	t.press(&"attack")
	await t.steps(2)
	t.release(&"attack")
	var striking := await t.until(func() -> bool: return bool(shapes.call(&"is_busy")), 600.0)
	t.check(striking, "an attack press while clinging did not strike")
	t.check(t.player().is_climbing(), "the strike let go of the wall")
	t.near(t.player_body().global_position.y, held_y, 3.0, "the slime's height while it strikes from the face")
	var hit := await t.until(func() -> bool: return int(boss.call(&"claw_hits")) >= 1, 1000.0)
	t.release(&"move_left")
	t.check(hit, "the Spear's strike from the face did not reach his claws")
	ReworkMode.set_on(false)


func test_his_fall_breaks_the_seal_and_the_climb_out_leads_to_the_lookout(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var run := Services.run()
	var arena: Node = fight["arena"]
	var boss: Node = fight["boss"]
	boss.set_physics_process(false)
	SkinState.lend(SkinState.FERAL)
	DungeonState.seal(run, MAP_ID, COLOSSUS_ID, "crystal-colossus")
	var wall: Node = _objects(t).get_node("M15-root-wall")
	await t.steps(2)
	t.check(not bool(wall.call(&"can_use")), "the climb out can be used while the mine is sealed")
	_light_all(t)
	await t.steps(3)
	t.set_enemy_health(boss, 10.0)
	_hit(t, boss, ["spear"], _weak_toward(boss))
	if not t.check(bool(boss.call(&"is_defeated")), "a Spear hit on his weak spot with 10 health left did not fell him"):
		return
	await t.steps(2)
	t.check(bool(arena.call(&"is_beaten")), "his fall was not recorded")
	t.check(COLOSSUS_ID in (run.world.get("defeated_boss_ids", []) as Array), "defeated_boss_ids has no crystal-colossus")
	t.check(not DungeonState.is_sealed(run, MAP_ID), "his fall did not break the seal")
	t.check(bool(arena.call(&"all_lit")), "the braziers do not burn for good after his fall")
	var heart: Node = _objects(t).get_node("M15-full-heart/FullHeartScript")
	await t.until(func() -> bool: return bool(heart.call(&"is_shown")), 1500.0)
	t.check(bool(heart.call(&"is_shown")), "his full heart did not rise")
	var seal: Node = _objects(t).get_node("M15-climb-out-seal")
	await t.until(func() -> bool: return not bool(seal.call(&"is_shut")), 3000.0)
	t.check(not bool(seal.call(&"is_shut")), "the climb out's seal did not sink")
	t.check(bool(wall.call(&"can_use")), "the arena's root wall cannot be climbed out once he fell")
	_stand(t, (wall as Node2D).global_position + Vector2(0, 6))
	await t.steps(4)
	t.press(&"interact")
	t.check(bool(wall.call(&"use")), "the climb out did not start")
	var out := await t.until(func() -> bool: return t.in_world(LOOKOUT_ID) and t.player_body() != null, 8000.0)
	t.release(&"interact")
	t.check(out, "the climb out did not bring the slime to the Lookout (%s)" % LOOKOUT_ID)


# --- helpers ---------------------------------------------------------------------------------------

## The runner starts each test in the mine (MAP_ID); waits for the slime there.
func _enter(t: TestContext) -> bool:
	if not t.in_world(MAP_ID):
		t.main.call(&"travel_to", MAP_ID)
	var arrived := await t.until(func() -> bool: return t.in_world(MAP_ID) and t.player_body() != null, 10000.0)
	await t.steps(8)
	return t.check(arrived, "could not travel to " + MAP_ID)


## Into the arena: the fight starts. {"arena", "boss"}, or {} when it did not.
func _start_fight(t: TestContext) -> Dictionary:
	if not await _enter(t):
		return {}
	var arena: Node = _objects(t).get_node("ColossusArena")
	_stand(t, _t(ARENA_FEET))
	var started := await t.until(func() -> bool: return arena.call(&"get_live_boss") != null, 2000.0)
	if not t.check(started, "the fight did not start when the slime walked into the arena"):
		return {}
	await t.steps(2)
	return {"arena": arena, "boss": arena.call(&"get_live_boss")}


## The climb up or down `wall` from its start (the slime's feet there), the interact key held until it
## ends. True when it finished there (not dropped).
func _climb(t: TestContext, wall: Node) -> bool:
	_stand(t, (wall as Node2D).global_position)
	await t.steps(4)
	t.press(&"interact")
	if not t.check(bool(wall.call(&"use")), "%s could not be climbed" % wall.name):
		t.release(&"interact")
		return false
	var done := await t.until(func() -> bool: return not t.player().is_climbing(), 6000.0)
	t.release(&"interact")
	await t.steps(4)
	return done


## He leaps onto the wall at the spot nearest CLAW_ROOTS and clings there (no mites thrown).
func _onto_the_wall(t: TestContext, boss: Node) -> bool:
	t.player().restore_run_state({"hp": t.player().get_max_hp()})
	var roots: Node2D = _objects(t).get_node(CLAW_ROOTS)
	boss.call(&"_leap_up", t.now(), roots.global_position + Vector2(-90.0, -40.0))
	var on := await t.until(func() -> bool: return str(boss.get(&"_phase")) == "cling", 2000.0)
	if not t.check(on, "he did not cling to his wall (phase %s)" % boss.get(&"_phase")):
		return false
	boss.set(&"_next_throw_at", INF)
	return true


## The slime up CLAW_ROOTS to their top beside him, clinging there (the interact key kept held).
func _cling_at_top(t: TestContext, roots: Node2D) -> bool:
	_stand(t, roots.global_position)
	await t.steps(4)
	t.press(&"interact")
	if not t.check(bool(roots.call(&"use")), "the roots beside his spot could not be climbed"):
		return false
	var holding := await t.until(func() -> bool: return bool(t.player().get_climb().call(&"is_holding")), 4000.0)
	return t.check(holding, "the slime did not cling at the top of the roots beside him")


func _light_all(t: TestContext) -> void:
	for brazier_name: String in ARENA_BRAZIERS:
		_objects(t).get_node(brazier_name).call(&"light")


## The way from his centre toward where the slime must stand to hit his open weak spot.
static func _weak_toward(boss: Node) -> Vector2:
	var sides := {"front": Vector2(0, 1), "back": Vector2(0, -1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}
	return sides.get(str(boss.call(&"weak_side")), Vector2(0, 1))


static func _t(cell: Vector2) -> Vector2:
	return cell * CELL


func _objects(t: TestContext) -> Node:
	return t.world().world_root.get_node("Objects")


## Puts the slime's feet at `feet` and takes its level there (the rooms lie at different levels).
func _stand(t: TestContext, feet: Vector2) -> void:
	var player := t.player()
	var offset := t.player_body().global_position - player.get_centre()
	MineTravel.place(player, feet - offset, Vector2.ZERO)
	t.player_body().velocity = Vector2.ZERO
	t.player_body().reset_physics_interpolation()


func _room_at(t: TestContext) -> String:
	var rooms: Node = t.world().world_root.get_node_or_null("CameraRooms")
	if rooms == null or t.player_body() == null:
		return ""
	var feet := t.player_body().global_position
	for room: Node in rooms.get_children():
		if (room.call(&"rect") as Rect2).has_point(feet):
			return str(room.name)
	return "(none)"


func _placed_enemy(t: TestContext, node_name: String) -> Node:
	var placed: Node = t.world().world_root.get_node_or_null("Enemies/" + node_name)
	return placed.call(&"get_enemy") if placed != null else null


static func _hp(enemy: Object) -> float:
	return float((enemy.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


## A hit of 20 with `tags` on `area` from a stand-in source (the barred gate tests' way).
func _route(t: TestContext, area: Area2D, tags: Array) -> void:
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


## A hit of 30 with `tags` on the Colossus from the slime standing on his `side` (a unit vector from
## his centre toward the slime).
func _hit(t: TestContext, boss: Node, tags: Array, side: Vector2) -> void:
	var centre: Vector2 = boss.call(&"get_centre")
	# On that side, but inside the arena (out of it the fight would start over).
	var rect: Rect2 = _objects(t).get_node("ColossusArena").get(&"arena_rect")
	t.teleport_player((centre + side * 120.0).clamp(rect.position + Vector2(24, 24), rect.end - Vector2(24, 24)))
	_hit_from_here(t, boss, tags)


## A hit of 30 with `tags` on the Colossus from the slime where it is (its own activation).
func _hit_from_here(t: TestContext, boss: Node, tags: Array) -> void:
	var centre: Vector2 = boss.call(&"get_centre")
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [player.get_damage_area()]
	var activation := router.begin_activation(player, areas)
	var knock := (centre - player.get_centre()).normalized()
	router.route({"activation_id": activation, "source": player, "attack_area": player.get_damage_area(),
		"target_area": boss.get(&"damage_area"), "weapon_id": "test-" + str(tags[0]), "weapon_tags": tags,
		"damage_types": ["physical"], "base_damage": 30.0, "effects": [],
		"impact": {"position": centre, "knock": knock}})
	router.end_activation(activation)
