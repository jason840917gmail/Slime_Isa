extends RefCounted
## Falling planks over water (docs/godot/DUNGEONS.md "Falling planks over water"), in the plank lab
## (game/dev/planks/playground-planks.tscn, built by tools/build_plank_lab.gd): a walk onto the long
## bridge sinks the slime and puts it back on the bank it came from with less health; a single Roll
## falls short of the long bridge (no landing) and only a continuous Roll crosses it (the classic
## Roll held; in the body-shapes mode the charged Roll, the `roll-charge` upgrade, while the quick
## Roll and a hold without the upgrade fall in); a fallen plank comes back; a landing never falls.
##
## The lab (cells of 64 units): the lake rows 4-11, the long bridge's eight planks at column 5, the
## stepped bridge at column 12 (landings at rows 9 and 6), the island north of the lake.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")

const LAB := "playground-planks"
const CELL := 64.0
## The player's feet are this far below its centre (player_slime.tscn depth anchor).
const FEET := 27.56
const LONG_X := 5.5 * CELL
const STEPPED_X := 12.5 * CELL
## The lake's south shore and north shore (world y).
const SOUTH_SHORE := 12.0 * CELL
const NORTH_SHORE := 4.0 * CELL
## The south bank's return point (the long bridge's hazard's ReturnSouth: the slime's centre).
const RETURN_SOUTH := Vector2(LONG_X, 12.6 * CELL)
const ROLL_UPGRADE := "roll-charge"


func test_a_walk_falls_in_and_comes_back_on_the_bank_with_less_health(t: TestContext) -> void:
	var watch := await _enter_lab(t, false)
	if watch == null:
		return
	var falls: Array = []
	var backs: Array = []
	watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	watch.connect(&"returned", func(payload: Dictionary) -> void: backs.append(payload))
	var player := t.player()
	var hp := player.get_hp()
	await _stand_on_south_bank(t, LONG_X)
	t.press(&"move_up")
	var fell := await t.until(func() -> bool: return not falls.is_empty(), 3000.0)
	t.release(&"move_up")
	if not t.check(fell, "walking onto the long bridge did not fall in"):
		return
	t.equal(str((falls[0] as Dictionary).get("kind", "")), "water", "the fall's kind")
	t.check(await t.until(func() -> bool: return not backs.is_empty(), 2000.0), "the slime was not put back")
	await t.steps(2)
	t.equal(player.get_hp(), hp - int(DungeonState.number("water.damage", 10.0)), "health after the fall")
	t.near_vec(player.get_centre(), RETURN_SOUTH, 2.0, "the slime after the fall (the south bank's return point)")


func test_a_fallen_plank_comes_back_and_a_landing_never_falls(t: TestContext) -> void:
	var watch := await _enter_lab(t, false)
	if watch == null:
		return
	var plank := _node(t, "long-plank-11")
	await _stand_on_south_bank(t, LONG_X)
	t.press(&"move_up")
	await t.until(func() -> bool: return not bool(plank.call(&"holds")), 2000.0)
	t.release(&"move_up")
	t.check(not bool(plank.call(&"holds")), "the first plank did not fall under a walk")
	var back := await t.until(func() -> bool: return bool(plank.call(&"holds")),
		DungeonState.number("slab.returnMs", 10000.0) + DungeonState.number("slab.riseMs", 450.0) + 2000.0)
	t.check(back, "the fallen plank did not come back")
	# Standing on a landing for two seconds: it holds, the slime stays dry.
	var falls: Array = []
	watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	var landing := _node(t, "stepped-landing-9")
	t.teleport_player(Vector2(STEPPED_X, 9.5 * CELL) - Vector2(0.0, FEET - 6.0))
	await t.sim_wait(2000.0)
	t.check(bool(landing.call(&"holds")), "the landing fell")
	t.check(falls.is_empty(), "the slime fell in from a landing")


func test_a_held_roll_crosses_the_long_bridge_and_a_single_roll_falls_short(t: TestContext) -> void:
	var watch := await _enter_lab(t, false)
	if watch == null:
		return
	var falls: Array = []
	watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	# The classic Roll held all the way: it rolls on over the eight planks.
	await _stand_on_south_bank(t, LONG_X)
	var crossed := await _hold_roll_across(t)
	t.check(falls.is_empty(), "a held Roll over the long bridge fell in")
	t.check(crossed, "a held Roll did not reach the island (feet at %.1f)" % _feet_y(t))
	# One Roll (a tap) falls short: no landing to stop on.
	await _wait_for_planks(t)
	falls.clear()
	await _stand_on_south_bank(t, LONG_X)
	t.tap(&"dodge")
	t.check(await t.until(func() -> bool: return not falls.is_empty(), 3000.0), "a single Roll crossed the long bridge")


func test_in_the_shapes_mode_only_the_charged_roll_crosses_the_long_bridge(t: TestContext) -> void:
	var watch := await _enter_lab(t, true)
	if watch == null:
		return
	var falls: Array = []
	watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	var run := Services.run()
	# Without the upgrade a held key rolls the quick Roll on its release: it falls in.
	t.check(not run.has_learned_ability(ROLL_UPGRADE), "the lab lent the charged roll upgrade")
	await _stand_on_south_bank(t, LONG_X)
	await _hold_roll_across(t, false)
	t.check(await t.until(func() -> bool: return not falls.is_empty(), 2500.0), "a quick Roll (no upgrade) crossed the long bridge")
	# With `roll-charge`: the charged Roll, held, crosses.
	await t.until(func() -> bool: return not bool(watch.call(&"is_falling")), 2000.0)
	await _wait_for_planks(t)
	run.learn_session_ability(ROLL_UPGRADE)
	falls.clear()
	await _stand_on_south_bank(t, LONG_X)
	var crossed := await _hold_roll_across(t, false)
	t.check(falls.is_empty(), "the charged Roll over the long bridge fell in")
	t.check(crossed, "the charged Roll did not reach the island (feet at %.1f)" % _feet_y(t))


## Travels into the lab (`shapes`: in the body-shapes mode) and returns its hazard watch.
func _enter_lab(t: TestContext, shapes: bool) -> Node:
	t.main.call(&"travel_to", LAB)
	await t.until(func() -> bool: return t.in_world(LAB) and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")) and ReworkMode.is_on() == shapes, 5000.0)
	await t.steps(4)
	var run := Services.run()
	if run != null and not run.has_learned_ability("dodge"):
		run.learn_session_ability("dodge")
	await t.steps(2)
	var watch := _node(t, "HazardWatch")
	t.check(watch != null, "the lab has no hazard watch")
	return watch


func _node(t: TestContext, node_name: String) -> Node:
	var world_root: Node = t.world().world_root if t.world() != null else null
	return world_root.find_child(node_name, true, false) if world_root != null else null


## The slime on the south bank at `x`, its body just clear of the bridge's first plank, facing north.
func _stand_on_south_bank(t: TestContext, x: float) -> void:
	t.release_all()
	t.teleport_player(Vector2(x, SOUTH_SHORE - FEET + 27.0))
	t.player().face(Vector2.UP)
	await t.steps(3)


## Holds the Roll key, facing north, until the feet are on the island (true) or the Roll is over.
## `hold_way`: the way held too (the classic Roll spins up in place; in the body-shapes mode a held
## way would walk the slime onto the bridge before the charged Roll's launch, so it rolls the facing).
func _hold_roll_across(t: TestContext, hold_way: bool = true) -> bool:
	if hold_way:
		t.press(&"move_up")
	t.press(&"dodge")
	await t.until(func() -> bool: return t.player().is_rolling(), 800.0)
	var crossed := await t.until(func() -> bool: return _feet_y(t) < NORTH_SHORE - 12.0 or not t.player().is_rolling(), 4000.0) \
		and _feet_y(t) < NORTH_SHORE - 12.0
	t.release(&"dodge")
	t.release(&"move_up")
	await t.steps(2)
	await t.until(func() -> bool: return not t.player().is_rolling(), 2000.0)
	await t.sim_wait(400.0)
	return crossed and _feet_y(t) < NORTH_SHORE


func _feet_y(t: TestContext) -> float:
	return t.player().get_centre().y + FEET


## Every plank of the long bridge standing again.
func _wait_for_planks(t: TestContext) -> void:
	var planks: Array[Node] = []
	for y in range(4, 12):
		planks.append(_node(t, "long-plank-%d" % y))
	await t.until(func() -> bool:
		for plank: Node in planks:
			if not bool(plank.call(&"holds")):
				return false
		return true, DungeonState.number("slab.returnMs", 10000.0) + 3000.0)
	await t.sim_wait(DungeonState.number("slab.riseMs", 450.0))
