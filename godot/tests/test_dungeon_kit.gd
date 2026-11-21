extends RefCounted
## The dungeon kit (docs/godot/DUNGEONS.md), in its lab (game/scenes/worlds/dev/dungeon-lab.tscn,
## built by tools/build_dungeon_lab.gd): no saving inside and a quit or a faint resuming at the
## entrance with everything kept; small keys opening one keyhole each, the boss door, the bolted
## door; chests giving their keys to the dungeon; the falling slabs' timing (a walk falls, a Roll
## crosses) and the void putting the slime back on its rim; the spikes' hits; a room fight's
## shutters and its ambush that never repeats; rooms whose enemies and pots come back; the winch and
## the drawbridge; the energy flower; the map's fog and the HUD's keys; the shadow path's light.
##
## The lab's rooms (cells of 64 units; a room is 16 x 14): B3 the entrance (1536, 3328), C3 the
## ambush, C2 the slabs, B2 the hub, B1 the winch and the drawbridge, B0 the boss, A2 the dark room
## with the shadow path, A3 the spike pit and the bolted door.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonMapDraw := preload("res://game/dungeon/dungeon_map_draw.gd")

const LAB := "dungeon-lab"
const ENTRANCE := Vector2(1536, 3328)
const SLOT := 0
const MANUAL_SLOT := 4
## The player's feet are this far below its centre (player_slime.tscn depth anchor).
const FEET := 27.56


# --- the dungeon state ----------------------------------------------------------------------------

func test_saving_is_blocked_inside_and_a_quit_resumes_at_the_entrance(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	t.equal(run.saving_blocked_reason(), DungeonState.NO_SAVE_REASON, "the reason inside a dungeon")
	t.check(not run.can_save(), "the run can be saved inside a dungeon")
	t.check(not run.save_slot(MANUAL_SLOT), "a slot was saved inside a dungeon")
	run.schedule_autosave()
	var timer: Timer = run.get(&"_autosave_timer")
	t.check(timer == null or timer.is_stopped(), "the autosave did not wait inside the dungeon")
	# A dungeon that writes its resume save (the lab writes none, as the playground writes no autosave).
	var dungeon := DungeonState.current(t.tree)
	dungeon.set(&"resume_saves", true)
	DungeonState.add_small_key(run, LAB)
	DungeonState.give_item(run, LAB, DungeonState.MAP)
	t.teleport_player(Vector2(1300, 2300))
	await t.steps(3)
	t.check(run.save_slot(SLOT), "a quit's resume save was not written")
	var record := run.read_slot(SLOT)
	var data: Dictionary = record.get("data", {})
	var location: Dictionary = data.get("location", {})
	t.equal(str(location.get("map_id", "")), LAB, "the resume save's world")
	t.near_vec(Vector2(float(location.get("x", 0)), float(location.get("y", 0))), ENTRANCE, 0.5, "the resume save's spot")
	var saved: Dictionary = ((data.get("world", {}) as Dictionary).get(DungeonState.RECORD_KEY, {}) as Dictionary).get(LAB, {})
	t.equal(int(saved.get("small_keys", -1)), 1, "the resume save's small keys")
	t.check(DungeonState.MAP in (saved.get("items", []) as Array), "the resume save lost the map")
	# Continue: the slime is at the entrance with what it had.
	t.check(bool(t.main.call(&"load_run", SLOT)), "the resume save did not load")
	await t.until(func() -> bool: return t.in_world(LAB) and t.player() != null and DungeonState.current(t.tree) != null, 4000.0)
	await t.steps(3)
	t.near_vec(t.player().get_centre(), ENTRANCE, 2.0, "the slime after Continue")
	t.equal(DungeonState.small_keys(run, LAB), 1, "small keys after Continue")
	# Out of the dungeon, saving works again.
	t.main.call(&"travel_to", "level-1")
	await t.until(func() -> bool: return t.in_world("level-1") and not bool(t.main.call(&"is_transitioning")), 5000.0)
	await t.steps(3)
	t.equal(run.saving_blocked_reason(), "", "the reason out of the dungeon")
	run.delete_slot(SLOT)


func test_fainting_wakes_at_the_entrance_and_keeps_the_dungeon(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	DungeonState.add_small_key(run, LAB, 2)
	DungeonState.give_item(run, LAB, DungeonState.BIG_KEY)
	t.teleport_player(Vector2(1300, 2300))
	await t.steps(3)
	_hit(t, t.player().get_damage_area(), 9999.0)
	t.check(t.player().is_dead(), "the slime did not faint")
	await t.until(func() -> bool: return not t.player().is_dead(), 6000.0, 8000.0)
	await t.steps(2)
	t.near_vec(t.player().get_centre(), ENTRANCE, 2.0, "where the fainted slime woke")
	t.equal(t.player().get_hp(), t.player().get_max_hp(), "health after waking")
	t.equal(DungeonState.small_keys(run, LAB), 2, "small keys after fainting")
	t.check(DungeonState.has_item(run, LAB, DungeonState.BIG_KEY), "the big key after fainting")


# --- keys and doors -------------------------------------------------------------------------------

func test_small_keys_open_keyholes_one_key_each(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var door := _node(t, "b3-key-door")
	var refused: Array = []
	door.connect(&"refused", func(payload: Dictionary) -> void: refused.append(payload))
	t.teleport_player(Vector2(1536, 2950))
	await _walk(t, &"move_up", 700.0)
	t.check(not refused.is_empty(), "a push without a key was not refused")
	t.check(not bool(door.call(&"is_open")), "the door opened without a key")
	DungeonState.add_small_key(run, LAB)
	t.press(&"move_up")
	var opened := await t.until(func() -> bool: return bool(door.call(&"is_open")), 2000.0)
	t.release(&"move_up")
	t.check(opened, "a small key did not open the door")
	t.equal(DungeonState.small_keys(run, LAB), 0, "keys after one keyhole")
	# Two keyholes: one key opens one, the door waits for the second.
	var double := _node(t, "b2-double-door")
	DungeonState.add_small_key(run, LAB)
	t.teleport_player(Vector2(1536, 2030))
	t.press(&"move_up")
	await t.until(func() -> bool: return int(double.call(&"open_keyholes")) == 1, 2000.0)
	await t.sim_wait(600.0)
	t.release(&"move_up")
	t.equal(int(double.call(&"open_keyholes")), 1, "keyholes after one key")
	t.check(not bool(double.call(&"is_open")), "a door with two keyholes opened with one key")
	t.equal(DungeonState.small_keys(run, LAB), 0, "keys spent on the first keyhole")
	DungeonState.add_small_key(run, LAB)
	t.press(&"move_up")
	opened = await t.until(func() -> bool: return bool(double.call(&"is_open")), 3000.0)
	t.release(&"move_up")
	t.check(opened, "the second key did not open the door")
	# Built again, both stay open.
	await _enter_lab(t)
	t.check(bool(_node(t, "b3-key-door").call(&"is_open")), "the small-key door is shut again")
	t.check(bool(_node(t, "b2-double-door").call(&"is_open")), "the two-keyhole door is shut again")


func test_the_boss_door_opens_with_the_big_key_only(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var door := _node(t, "b1-boss-door")
	DungeonState.add_small_key(run, LAB, 3)
	t.teleport_player(Vector2(1536, 1150))
	await _walk(t, &"move_up", 800.0)
	t.check(not bool(door.call(&"is_open")), "small keys opened the boss door")
	t.equal(DungeonState.small_keys(run, LAB), 3, "the boss door took a small key")
	DungeonState.give_item(run, LAB, DungeonState.BIG_KEY)
	t.press(&"move_up")
	var opened := await t.until(func() -> bool: return bool(door.call(&"is_open")), 2000.0)
	t.release(&"move_up")
	t.check(opened, "the big key did not open the boss door")
	t.check(DungeonState.has_item(run, LAB, DungeonState.BIG_KEY), "the big key was spent")


func test_a_bolted_door_opens_from_its_bolt_side_only(t: TestContext) -> void:
	await _enter_lab(t)
	var door := _node(t, "a3-bolted-door")
	var refused: Array = []
	door.connect(&"refused", func(payload: Dictionary) -> void: refused.append(payload))
	# From the entrance (its back).
	t.teleport_player(Vector2(1090, 3366))
	await _walk(t, &"move_left", 900.0)
	t.check(not refused.is_empty(), "the back of the bolted door said nothing")
	t.equal(str((refused[0] as Dictionary).get("text", "")) if not refused.is_empty() else "", "Bolted from the other side.",
		"the bolted door's line")
	t.check(not bool(door.call(&"is_open")), "the bolted door opened from its back")
	# From its face, in A3.
	t.teleport_player(Vector2(920, 3366))
	t.press(&"move_right")
	var opened := await t.until(func() -> bool: return bool(door.call(&"is_open")), 2500.0)
	t.release(&"move_right")
	t.check(opened, "the bolt did not slide from its side")
	t.check(DungeonState.is_done(t.tree, str(door.call(&"record_key"))), "the opened bolt is not recorded")


func test_a_chest_gives_its_key_to_the_dungeon_and_stays_open(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var chest := _node(t, "b3-key-chest").get_node("ChestScript")
	t.check(not bool(chest.call(&"is_empty")), "the key chest starts empty")
	t.equal(str(chest.call(&"request_open")), "opened", "the chest's answer")
	t.equal(DungeonState.small_keys(run, LAB), 1, "small keys after the chest")
	t.equal(run.item_count("dungeon-small-key"), 0, "the small key went into the bag")
	t.check(bool(chest.call(&"is_empty")), "the chest is not empty after giving its key")
	var hidden := _node(t, "c3-reward-chest").get_node("ChestScript")
	t.check(not bool(hidden.call(&"is_shown")), "the ambush's chest is there before the fight")
	t.check(not hidden.is_in_group(&"chest"), "a hidden chest is offered to the interact key")
	await _enter_lab(t)
	t.check(bool(_node(t, "b3-key-chest").get_node("ChestScript").call(&"is_empty")), "the opened chest is full again")


func test_a_chest_with_a_key_and_loot_opens_once(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var chest := _node(t, "b3-key-chest").get_node("ChestScript")
	# Coins beside its key (its record, as `initial_contents` would make it).
	run.set_chest_remaining(str(chest.get(&"map_id")), str(chest.get(&"instance_id")), {"dungeon-small-key": 1, "coins": 5})
	var requested: Array = []
	chest.connect(&"open_requested", func(payload: Dictionary) -> void: requested.append(payload))
	t.equal(str(chest.call(&"request_open")), "opened", "the chest's answer")
	await t.steps(2)
	t.equal(requested.size(), 1, "open_requested for a key beside coins")
	t.equal(DungeonState.small_keys(run, LAB), 1, "small keys after the chest")
	var window := t.tree.get_first_node_in_group(&"chest_window")
	t.check(window != null and window.call(&"current_chest") == chest, "the window did not open on the coins")
	if window != null and window.has_method(&"close"):
		window.call(&"close")


# --- the void, slabs and spikes ---------------------------------------------------------------------

func test_a_walk_over_falling_slabs_falls_and_a_roll_crosses(t: TestContext) -> void:
	await _enter_lab(t)
	var watch := _node(t, "HazardWatch")
	if not t.check(watch != null, "the lab has no hazard watch"):
		return
	var falls: Array = []
	watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	var player := t.player()
	var hp := player.get_hp()
	# Walking north onto the narrow bridge (two slabs over the void): it gives under the slime.
	t.teleport_player(Vector2(2304, 2400))
	await t.steps(3)
	t.press(&"move_up")
	var fell := await t.until(func() -> bool: return not falls.is_empty(), 2500.0)
	t.release(&"move_up")
	t.check(fell, "walking over falling slabs did not fall")
	await t.until(func() -> bool: return not bool(watch.call(&"is_falling")), 2000.0)
	await t.steps(2)
	t.equal(player.get_hp(), hp - int(DungeonState.number("void.damage", 10.0)), "health after the fall")
	t.check(player.get_centre().y + FEET >= 2367.5, "the fall did not put the slime back on the rim it came from (feet at %.1f)" % (player.get_centre().y + FEET))
	# The slabs come back after returnMs.
	var slabs := [_node(t, "c2-slab-narrow-7"), _node(t, "c2-slab-narrow-8")]
	var back := await t.until(func() -> bool: return bool(slabs[0].call(&"holds")) and bool(slabs[1].call(&"holds")),
		DungeonState.number("slab.returnMs", 10000.0) + 2000.0)
	t.check(back, "the fallen slabs did not come back")
	# A Roll from the rim's edge crosses (and the way held on walks off the last slab). The Roll is
	# young Burr's lesson since 2026-11-19: lent here.
	Services.run().learn_session_ability("dodge")
	falls.clear()
	t.teleport_player(Vector2(2304, 2368.0 - FEET + 26.0 + 1.0))
	player.face(Vector2.UP)
	await t.steps(2)
	t.tap(&"dodge")
	await t.until(func() -> bool: return player.is_rolling(), 200.0)
	await t.until(func() -> bool: return not player.is_rolling(), 2500.0)
	t.press(&"move_up")
	await t.sim_wait(250.0)
	t.release(&"move_up")
	await t.sim_wait(600.0)
	t.check(falls.is_empty(), "a Roll over two slabs fell")
	t.check(player.get_centre().y + FEET < 2240.0, "the Roll did not reach the far rim (feet at %.1f)" % (player.get_centre().y + FEET))


func test_the_void_puts_the_slime_back_on_its_rim(t: TestContext) -> void:
	await _enter_lab(t)
	var watch := _node(t, "HazardWatch")
	var returned: Array = []
	watch.connect(&"returned", func(payload: Dictionary) -> void: returned.append(payload))
	# On the shadow path over the void; a step off it falls.
	t.teleport_player(Vector2(480, 2144 - FEET + 10.0))
	await t.steps(5)
	t.press(&"move_down")
	var back := await t.until(func() -> bool: return not returned.is_empty(), 4000.0)
	t.release(&"move_down")
	t.check(back, "stepping off the shadow path never fell into the void")
	await t.steps(2)
	t.near_vec(t.player().get_centre(), Vector2(672, 2144), 2.0, "the slime after the fall (the path's mouth)")


func test_spikes_hurt_each_time_the_invulnerability_ends(t: TestContext) -> void:
	await _enter_lab(t)
	var watch := _node(t, "HazardWatch")
	var hits: Array[float] = []
	watch.connect(&"hurt", func(_payload: Dictionary) -> void: hits.append(t.now()))
	# Into the spike pit (a slab gone from under it drops it in).
	t.teleport_player(Vector2(480, 3200 - FEET))
	await t.sim_wait(1800.0)
	var elevation: Node = t.world().elevation
	if elevation != null:
		t.equal(int(elevation.call(&"level_of", t.player_body())), -1, "the slime's level in the pit")
	t.between(float(hits.size()), 2.0, 4.0, "spike hits in 1.8 s")
	var spacing := Services.constants().number("character.player.hitInvulnerabilityMs")
	for i in range(1, hits.size()):
		t.check(hits[i] - hits[i - 1] >= spacing - TestContext.STEP_MS, "two spike hits %.0f ms apart" % (hits[i] - hits[i - 1]))


# --- room logic -------------------------------------------------------------------------------------

func test_a_room_fight_shuts_its_shutters_until_won_and_an_ambush_never_repeats(t: TestContext) -> void:
	await _enter_lab(t)
	var fight := _node(t, "c3-fight")
	var shutters := [_node(t, "c3-shutter-west"), _node(t, "c3-shutter-north")]
	t.check(not bool(shutters[0].call(&"is_shut")), "the shutters start shut")
	t.teleport_player(Vector2(2304, 3136))
	var started := await t.until(func() -> bool: return bool(fight.call(&"is_active")), 1000.0)
	t.check(started, "the ambush did not start")
	t.check(bool(shutters[0].call(&"is_shut")) and bool(shutters[1].call(&"is_shut")), "the shutters did not shut")
	for enemy: Node in _enemies_in(t, Rect2(fight.global_position, fight.get(&"size"))):
		_hit(t, enemy.get(&"damage_area"), 9999.0)
	var won := await t.until(func() -> bool: return not bool(fight.call(&"is_active")), 4000.0)
	t.check(won, "the fight was not won with its enemies beaten")
	t.check(not bool(shutters[0].call(&"is_shut")) and not bool(shutters[1].call(&"is_shut")), "the shutters stayed shut")
	t.check(bool(_node(t, "c3-reward-chest").get_node("ChestScript").call(&"is_shown")), "the reward chest did not rise")
	t.check(bool(fight.call(&"is_done")), "the ambush is not recorded")
	# Out and back in: it never runs again, its enemies are gone for good.
	t.teleport_player(Vector2(1300, 3200))
	await t.steps(5)
	t.teleport_player(Vector2(2304, 3136))
	await t.sim_wait(600.0)
	t.check(not bool(fight.call(&"is_active")), "the ambush ran again")
	t.equal(_enemies_in(t, Rect2(fight.global_position, fight.get(&"size"))).size(), 0, "the ambush's enemies came back")


func test_room_enemies_and_pots_come_back_when_the_room_is_entered_again(t: TestContext) -> void:
	await _enter_lab(t)
	var placed := _node(t, "a3-worm")
	if not t.check(placed != null and bool(placed.call(&"is_standing")), "the lab's room worm does not stand"):
		return
	t.teleport_player(Vector2(300, 2900))
	await t.steps(3)
	_hit(t, (placed.call(&"get_enemy") as Node).get(&"damage_area"), 9999.0)
	await t.until(func() -> bool: return not bool(placed.call(&"is_standing")), 3000.0)
	await t.sim_wait(1500.0)
	t.check(not bool(placed.call(&"is_standing")), "the beaten worm stood up in the same visit")
	t.teleport_player(Vector2(1300, 3200))
	await t.steps(5)
	t.teleport_player(Vector2(300, 2900))
	var back := await t.until(func() -> bool: return bool(placed.call(&"is_standing")), 1000.0)
	t.check(back, "the room's worm is not back when the room is entered again")
	# A pot taken from the entrance leaves what it hid and is back with its room.
	var pot_at := Vector2(1248, 3424)
	var pot := _liftable_near(t, pot_at)
	if not t.check(pot != null, "no pot in the entrance"):
		return
	pot.get_node("LiftableScript").call(&"take")
	await t.steps(4)
	t.check(t.tree.root.find_child("DungeonPickup", true, false) != null, "the pot left nothing where it stood")
	t.check(_liftable_near(t, pot_at) == null, "the taken pot is still there")
	t.teleport_player(Vector2(1300, 2300))
	await t.steps(5)
	t.teleport_player(Vector2(1536, 3200))
	await t.steps(5)
	t.check(_liftable_near(t, pot_at) != null, "the pot is not back when the room is entered again")


func test_a_winch_lowers_the_drawbridge_for_good(t: TestContext) -> void:
	await _enter_lab(t)
	var winch := _node(t, "b1-winch")
	var bridge := _node(t, "b1-drawbridge")
	t.check(not bool(bridge.call(&"holds")), "the drawbridge starts down")
	t.teleport_player(Vector2(1280, 1640))
	t.press(&"move_up")
	var turned := await t.until(func() -> bool: return bool(winch.call(&"is_turned")), 3000.0)
	t.release(&"move_up")
	t.check(turned, "pushing the winch did not turn it")
	var down := await t.until(func() -> bool: return bool(bridge.call(&"holds")), 2000.0)
	t.check(down, "the drawbridge did not come down")
	var watch := _node(t, "HazardWatch")
	var falls: Array = []
	watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	t.teleport_player(Vector2(1536, 1500))
	await _walk(t, &"move_up", 1300.0)
	t.check(falls.is_empty(), "the slime fell off the lowered drawbridge")
	t.check(t.player().get_centre().y + FEET < 1290.0, "the drawbridge did not carry the slime across")
	await _enter_lab(t)
	await t.steps(3)
	t.check(bool(_node(t, "b1-drawbridge").call(&"holds")), "the drawbridge is up again after the world was built again")


## Regression (2026-10-17): in a world loaded from its baked elevation cache, a passage opened at run
## time (a lowered drawbridge, Elevation.open_passage) rebuilt its level's collision from side shapes
## the cache had stripped of their edges, and every rebuild raised a script error. The lab is loaded
## from its cache; the passages open without an error (the runner fails a test on any) and are
## walkable.
func test_passages_open_in_a_world_loaded_from_its_elevation_cache(t: TestContext) -> void:
	await _enter_lab(t)
	var elevation: Node = t.world().elevation
	if not t.check(elevation != null, "the lab has no elevation"):
		return
	t.check(bool(elevation.get(&"from_cache")), "the lab was not loaded from its elevation cache (bake it: tools/bake_elevation.gd -- --world=dungeon-lab)")
	# The slab bridge's passage, opened with the world.
	t.check(bool(elevation.call(&"is_walkable", Vector2(2304, 2272), 0)), "the slab bridge is not walkable")
	# The drawbridge's, opened when it comes down.
	var deck := Vector2(1536, 1376)
	t.check(not bool(elevation.call(&"is_walkable", deck, 0)), "the void under the raised drawbridge is walkable")
	_node(t, "b1-winch").call(&"turn")
	await t.until(func() -> bool: return bool(_node(t, "b1-drawbridge").call(&"holds")), 2000.0)
	await t.steps(3)
	t.check(bool(elevation.call(&"is_walkable", deck, 0)), "the lowered drawbridge is not walkable")
	# One opened directly, over the wide void beside its slabs.
	var spot := Vector2(2560 + 32, 2368 + 32)
	t.check(not bool(elevation.call(&"is_walkable", spot, 0)), "the void beside the slabs is walkable")
	elevation.call(&"open_passage", Rect2(Vector2(2560, 2368), Vector2(64, 64)), 0)
	await t.steps(3)
	t.check(bool(elevation.call(&"is_walkable", spot, 0)), "a passage opened over the void is not walkable")


func test_the_energy_flower_grows_back(t: TestContext) -> void:
	await _enter_lab(t)
	var flower := _node(t, "b3-flower")
	var player := t.player()
	player.set_energy(10.0)
	t.teleport_player(flower.global_position - Vector2(0.0, FEET))
	await t.steps(3)
	t.near(player.get_energy(), 10.0 + DungeonState.number("refill.flowerEnergy", 25.0), 1.0, "energy after the flower")
	t.check(not bool(flower.call(&"is_in_bloom")), "the drunk flower is still in bloom")
	flower.set(&"_regrow_at_ms", Services.now_ms() + 100.0)
	var grown := await t.until(func() -> bool: return bool(flower.call(&"is_in_bloom")), 1000.0)
	t.check(grown, "the flower did not grow back")


# --- the map, the HUD, the dark ---------------------------------------------------------------------

func test_the_map_fogs_rooms_not_visited_and_the_hud_counts_keys(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var dungeon := DungeonState.current(t.tree)
	t.check(DungeonState.is_visited(run, LAB, LAB + "/B3"), "the entrance is not visited")
	t.check(not DungeonState.is_visited(run, LAB, LAB + "/B2"), "the hub is visited before the slime went there")
	t.teleport_player(Vector2(1300, 2300))
	await t.steps(3)
	t.check(DungeonState.is_visited(run, LAB, LAB + "/B2"), "the hub was not visited")
	t.equal(str(dungeon.call(&"current_room_key")), LAB + "/B2", "the room the slime is in")
	var hud := dungeon.get_node_or_null("DungeonHud")
	if t.check(hud != null, "no dungeon HUD"):
		t.equal(str(hud.call(&"key_text")), "x 0", "the HUD's keys")
		DungeonState.add_small_key(run, LAB, 2)
		await t.steps(1)
		t.equal(str(hud.call(&"key_text")), "x 2", "the HUD's keys after two")
	t.check(DungeonMapDraw.boss_points(dungeon).size() == 1, "the compass would not mark the boss's room")
	var page := t.tree.root.find_child("DungeonMapPage", true, false)
	if t.check(page != null, "no dungeon map page"):
		t.check(str(page.call(&"summary_text")).begins_with("Small keys: 2"), "the map page's summary: %s" % page.call(&"summary_text"))


func test_the_shadow_path_shows_only_in_light(t: TestContext) -> void:
	await _enter_lab(t)
	var path := _node(t, "a2-shadow-path")
	var cell := Vector2(480, 2144)
	var none: Array[Vector3] = []
	t.near(float(path.call(&"shown_at", cell, none)), 0.0, 0.001, "the moss in the dark without a light")
	var lit: Array[Vector3] = [Vector3(cell.x, cell.y, 160.0)]
	t.near(float(path.call(&"shown_at", cell, lit)), 1.0, 0.001, "the moss in the slime's light")
	var far: Array[Vector3] = [Vector3(cell.x + 400.0, cell.y, 160.0)]
	t.near(float(path.call(&"shown_at", cell, far)), 0.0, 0.001, "the moss beyond a light's reach")
	t.check(bool(path.call(&"holds_at", cell)), "the shadow path does not hold the slime")


# --- helpers ----------------------------------------------------------------------------------------

## Travels into the lab (again: a fresh build of it) and waits until it is played.
func _enter_lab(t: TestContext) -> void:
	t.main.call(&"travel_to", LAB)
	await t.until(func() -> bool: return t.in_world(LAB) and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")) and DungeonState.current(t.tree) != null, 5000.0)
	await t.steps(4)


func _node(t: TestContext, node_name: String) -> Node:
	var world_root: Node = t.world().world_root if t.world() != null else null
	return world_root.find_child(node_name, true, false) if world_root != null else null


func _walk(t: TestContext, action: StringName, ms: float) -> void:
	t.press(action)
	await t.sim_wait(ms)
	t.release(action)
	await t.steps(2)


func _enemies_in(t: TestContext, rect: Rect2) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in t.tree.get_nodes_in_group(&"placed_enemy"):
		if not is_instance_valid(node) or not rect.has_point((node as Node2D).global_position):
			continue
		var enemy: Node = node.call(&"get_enemy")
		if enemy != null and bool(node.call(&"is_standing")):
			out.append(enemy)
	return out


func _liftable_near(t: TestContext, at: Vector2) -> Node2D:
	for node: Node in t.tree.get_nodes_in_group(&"liftable"):
		var root := node.get_parent() as Node2D
		if root != null and not root.is_queued_for_deletion() and root.global_position.distance_to(at) < 12.0:
			return root
	return null


## A plain hit of `amount` (true damage) on the receiver of `area`.
func _hit(t: TestContext, area: Area2D, amount: float) -> void:
	if area == null:
		t.fail("no hurtbox to hit")
		return
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-hit", "weapon_tags": ["weapon"], "damage_types": ["physical"], "base_damage": amount,
		"true_damage": true, "effects": [], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
