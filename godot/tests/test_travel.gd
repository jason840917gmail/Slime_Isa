extends RefCounted
## Area travel (docs/godot/specs/world.md section 8, game/world/area_travel.gd, Main.travel_to):
## level-1's east exit (`exit-1`, target gloop-forest entry "west") has no gate of its own (owner,
## 2026-11-01: the Verdant Gate object before it takes the green key, so the border is never reached
## locked). level-1 is cut into chunk worlds (docs/godot/WORLD_ATLAS.md): the exit is in chunk D4
## (`level-1-d4`, its origin at level-1's (2048, 0)), centre (2016, 576) there. A world exit's gate
## is tried on it with one the test gives it, its record kept under that chunk's map id. Without
## the key the player stays and the exit reports "blocked"; with it the key is used, the gate is
## remembered, the screen scrolls across the border into gloop-forest (its chunk E4: gloop-forest is
## cut into chunk worlds, docs/godot/WORLD_ATLAS.md) with the player at the same height on its west
## edge (docs/design/2026-10-31-crossings-and-arrivals.md), keeping its HP. A named spot
## (`entry_marker`: a Node2D's name in the target world, the prologue's birth) arrives there
## instead, after a door and before the entry edge.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")

## run_tests.gd starts every test of this file in the gate's chunk of level-1.
const MAP_ID := "level-1-d4"
const EXIT_CENTRE := Vector2(2016.0, 576.0)
## The gate the test puts on exit-1 (as the gated exits of other worlds have one).
const GATE_ID := "test-exit-gate"
const KEY_ID := "green-key"
const TARGET_MAP := "gloop-forest"
const GRACE_MS := 650.0
const CARRIED_HP := 61
## A marker gloop-forest has (its spawn, in chunk E4 with the west entry and the hut door), named by
## an exit with no entry edge.
const NAMED_MARKER := "player-spawn"
## A marker the test builds in gloop-forest, nested one level down.
const BUILT_MARKER := "test-arrival-marker"
const BUILT_HOLDER_POSITION := Vector2(1024.0, 1024.0)
const BUILT_MARKER_OFFSET := Vector2(128.0, 64.0)
## gloop-forest's hut door (side north: it arrives `arrival_step` below the door's parent).
const DOOR_ID := "hut-door"


func test_gated_exit_blocks_then_travels_with_the_key(t: TestContext) -> void:
	var run := Services.run()
	var exit_node := _exit_script(t, "exit-1")
	if not t.check(exit_node != null, "level-1-d4 has no exit-1 world exit script"):
		return
	t.check((exit_node as WorldExitScript).gate.is_empty(), "exit-1 has a gate of its own (the Verdant Gate object takes the key)")
	(exit_node as WorldExitScript).gate = {"id": GATE_ID, "requiredItemId": KEY_ID, "consumeOnUnlock": true,
			"lockedMessage": "Locked."}
	var results: Array = []
	t.listen(exit_node.navigation_resolved, func(result: Dictionary) -> void: results.append(result))
	t.player().restore_run_state({"hp": CARRIED_HP})
	await t.sim_wait(GRACE_MS)
	t.teleport_player(EXIT_CENTRE)
	await t.sim_wait(200.0)
	t.equal(t.world().map_id(), MAP_ID, "map while the gate is locked")
	t.check(not results.is_empty() and str(results[-1].get("status")) == "blocked",
		"the locked exit did not report blocked (got %s)" % [results])
	t.check(not run.is_gate_unlocked(MAP_ID, GATE_ID), "the gate unlocked without the key")

	(run.inventory["slots"] as Array).append({"item_id": KEY_ID, "count": 1})
	var travelled := await t.until(func() -> bool: return t.in_world(TARGET_MAP) and t.player() != null, 3000.0, 6000.0)
	if not t.check(travelled, "the player did not reach %s" % TARGET_MAP):
		return
	t.equal(run.item_count(KEY_ID), 0, "green keys left after the unlock")
	t.check(run.is_gate_unlocked(MAP_ID, GATE_ID), "the gate is not remembered as unlocked")
	t.check(TARGET_MAP in (run.world["discovered_areas"] as Array), "%s not marked discovered" % TARGET_MAP)
	# A border into the next region crosses by coordinates (2026-10-31, docs/design/
	# 2026-10-31-crossings-and-arrivals.md D5): gloop-forest's chunk across the edge has its exit back
	# there, so the screen scrolls and the slime comes out at the same height on its west edge.
	t.check(await t.until(func() -> bool: return not t.main.is_transitioning(), 3000.0, 6000.0), "the border scroll did not end")
	var expected: Vector2 = AreaTravel.arrival_point({"entry_edge": "west", "entry_along": EXIT_CENTRE.y}, Vector2.ZERO)
	t.near_vec(t.player().get_centre(), expected, 1.0, "arrival centre (across the border at the same height)")
	t.equal(t.player().get_hp(), CARRIED_HP, "HP carried across the travel")
	t.check(not t.main.is_transitioning(), "main still transitioning after the arrival")


## A second request during the leave fade is ignored, and an unknown world is refused.
func test_travel_requests_while_travelling_are_ignored(t: TestContext) -> void:
	t.check(not t.main.travel_to("no-such-world", "west"), "travel to an unknown world was accepted")
	t.check(t.main.travel_to(TARGET_MAP, "west"), "travel to %s was refused" % TARGET_MAP)
	t.check(not t.main.travel_to("level-1", "east"), "a second travel during the fade was accepted")
	var travelled := await t.until(func() -> bool: return t.in_world(TARGET_MAP) and t.player() != null, 3000.0, 6000.0)
	t.check(travelled, "the player did not reach %s" % TARGET_MAP)


## A door's lead-in (door.gd `lead_ms`: its leaf opening, a climb down a ladder, a fall into a hole)
## holds the iris back: `travel_to` with `lead_ms` is travelling at once, the iris only comes after
## the lead-in, and the world swaps after it closes.
func test_travel_lead_in_waits_before_the_iris(t: TestContext) -> void:
	t.check(t.main.travel_to(TARGET_MAP, "", DOOR_ID, "", true, 400.0), "travel to %s was refused" % TARGET_MAP)
	t.check(t.main.is_transitioning(), "not travelling during the lead-in")
	await t.sim_wait(200.0)
	t.check(t.main.get_node_or_null(^"IrisTransition") == null, "the iris started during the lead-in")
	t.check(t.player().is_movement_suppressed(), "the slime moves during the lead-in")
	var irised := await t.until(func() -> bool: return t.main.get_node_or_null(^"IrisTransition") != null, 600.0, 2000.0)
	t.check(irised, "the iris did not start after the lead-in")
	var travelled := await t.until(func() -> bool: return t.in_world(TARGET_MAP) and t.player() != null, 3000.0, 6000.0)
	t.check(travelled, "the player did not reach %s" % TARGET_MAP)


## A travel to a named spot (`entry_marker`) and no entry edge travels, and the player arrives on
## the tile centre at the Node2D of that name. In the built world a named spot (found at any depth)
## wins over the entry edge, a door wins over the named spot, and a name the world lacks falls back
## to the spawn (with a warning).
func test_exit_arrives_at_a_named_marker(t: TestContext) -> void:
	var result: Dictionary = t.main.request_exit({"map_id": MAP_ID, "exit_id": "test-exit",
		"target_area_id": TARGET_MAP, "entry": "", "entry_marker": NAMED_MARKER, "gate": {}})
	t.equal(str(result.get("status")), "queued", "status of an exit with only an entry marker")
	var travelled := await t.until(func() -> bool: return t.in_world(TARGET_MAP) and t.player() != null, 3000.0, 6000.0)
	if not t.check(travelled, "the player did not reach %s" % TARGET_MAP):
		return
	var world_root := t.world().world_root
	var named: Variant = AreaTravel.named_marker(world_root, NAMED_MARKER)
	if not t.check(named != null, "%s has no %s marker" % [TARGET_MAP, NAMED_MARKER]):
		return
	t.near_vec(t.player().get_centre(), t.world().find_spawn_point(named), 0.01, "arrival centre (named marker's tile centre)")

	var holder := Node2D.new()
	holder.position = BUILT_HOLDER_POSITION
	world_root.add_child(holder)
	var built := Node2D.new()
	built.name = BUILT_MARKER
	built.position = BUILT_MARKER_OFFSET
	holder.add_child(built)
	var door: Variant = AreaTravel.door_arrival(world_root, DOOR_ID)
	if not t.check(door != null, "%s has no %s" % [TARGET_MAP, DOOR_ID]):
		return
	var handoff := {"kind": "area", "map_id": TARGET_MAP, "entry_edge": "west", "entry_marker": BUILT_MARKER}
	t.near_vec(AreaTravel.arrival_point(handoff, Vector2.ZERO), t.world().find_spawn_point(built.global_position), 0.01,
		"a nested named marker over the entry edge")
	handoff["entry_door"] = DOOR_ID
	# The hut door has a side (north): its open arrival is used unsnapped.
	t.near_vec(AreaTravel.arrival_point(handoff, Vector2.ZERO), door, 0.01, "a door over the named marker")
	handoff.erase("entry_door")
	handoff["entry_marker"] = "no-such-marker"
	t.near_vec(AreaTravel.arrival_point(handoff, Vector2.ZERO), t.world().find_spawn_point(t.world().player_spawn_marker()), 0.01,
		"a missing named spot falls back to the spawn")
	holder.queue_free()


func _exit_script(t: TestContext, exit_id: String) -> Node:
	for node: Node in t.world().world_root.find_children("*", "Node", true, false):
		if node is WorldExitScript and (node as WorldExitScript).exit_id == exit_id:
			return node
	return null
