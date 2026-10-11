extends RefCounted
## Area travel (docs/godot/specs/world.md section 8, game/world/area_travel.gd, Main.travel_to):
## level-1's east exit (`exit-1`, centre (4064, 576), target gloop-forest entry "west") is gated
## by `level-1-east-verdant-gate` (green key, consumed). Without the key the player stays and the
## exit reports "blocked"; with it the key is used, the gate is remembered, the picture fades out
## and gloop-forest is built with the player on the tile centre at its `player-entry-west` marker,
## keeping its HP. An exit's `entry_marker` (a Node2D's name in the target world) arrives there
## instead, after a door and before the entry edge.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")

const EXIT_CENTRE := Vector2(4064.0, 576.0)
const GATE_ID := "level-1-east-verdant-gate"
const KEY_ID := "green-key"
const TARGET_MAP := "gloop-forest"
const GRACE_MS := 650.0
const CARRIED_HP := 61
## A marker gloop-forest has (its east entry), named by an exit with no entry edge.
const NAMED_MARKER := "player-entry-east"
## A marker the test builds in gloop-forest, nested one level down.
const BUILT_MARKER := "test-arrival-marker"
const BUILT_HOLDER_POSITION := Vector2(1024.0, 1024.0)
const BUILT_MARKER_OFFSET := Vector2(128.0, 64.0)
## gloop-forest's hut door (its arrival child is under the door's parent).
const DOOR_ID := "hut-door"


func test_gated_exit_blocks_then_travels_with_the_key(t: TestContext) -> void:
	var run := Services.run()
	var exit_node := _exit_script(t, "exit-1")
	if not t.check(exit_node != null, "level-1 has no exit-1 world exit script"):
		return
	var results: Array = []
	t.listen(exit_node.navigation_resolved, func(result: Dictionary) -> void: results.append(result))
	t.player().restore_run_state({"hp": CARRIED_HP})
	await t.sim_wait(GRACE_MS)
	t.teleport_player(EXIT_CENTRE)
	await t.sim_wait(200.0)
	t.equal(t.world().map_id(), "level-1", "map while the gate is locked")
	t.check(not results.is_empty() and str(results[-1].get("status")) == "blocked",
		"the locked exit did not report blocked (got %s)" % [results])
	t.check(not run.is_gate_unlocked("level-1", GATE_ID), "the gate unlocked without the key")

	(run.inventory["slots"] as Array).append({"item_id": KEY_ID, "count": 1})
	var travelled := await t.until(func() -> bool: return t.world().map_id() == TARGET_MAP and t.player() != null, 3000.0, 6000.0)
	if not t.check(travelled, "the player did not reach %s" % TARGET_MAP):
		return
	t.equal(run.item_count(KEY_ID), 0, "green keys left after the unlock")
	t.check(run.is_gate_unlocked("level-1", GATE_ID), "the gate is not remembered as unlocked")
	t.check(TARGET_MAP in (run.world["discovered_areas"] as Array), "%s not marked discovered" % TARGET_MAP)
	var marker: Variant = AreaTravel.entry_marker(t.world().world_root, "west")
	if not t.check(marker != null, "%s has no player-entry-west marker" % TARGET_MAP):
		return
	var expected: Vector2 = t.world().find_spawn_point(marker)
	t.near_vec(t.player().get_centre(), expected, 0.01, "arrival centre (entry-west tile centre)")
	t.equal(t.player().get_hp(), CARRIED_HP, "HP carried across the travel")
	t.check(not t.main.is_transitioning(), "main still transitioning after the arrival")


## A second request during the leave fade is ignored, and an unknown world is refused.
func test_travel_requests_while_travelling_are_ignored(t: TestContext) -> void:
	t.check(not t.main.travel_to("no-such-world", "west"), "travel to an unknown world was accepted")
	t.check(t.main.travel_to(TARGET_MAP, "west"), "travel to %s was refused" % TARGET_MAP)
	t.check(not t.main.travel_to("level-1", "east"), "a second travel during the fade was accepted")
	var travelled := await t.until(func() -> bool: return t.world().map_id() == TARGET_MAP and t.player() != null, 3000.0, 6000.0)
	t.check(travelled, "the player did not reach %s" % TARGET_MAP)


## An exit with an `entry_marker` and no entry edge travels, and the player arrives on the tile
## centre at the Node2D of that name. In the built world a named marker (found at any depth) wins
## over the entry edge's marker, a door wins over the named marker, and a name the world lacks
## falls back to the entry edge (with a warning).
func test_exit_arrives_at_a_named_marker(t: TestContext) -> void:
	var result: Dictionary = t.main.request_exit({"map_id": "level-1", "exit_id": "test-exit",
		"target_area_id": TARGET_MAP, "entry": "", "entry_marker": NAMED_MARKER, "gate": {}})
	t.equal(str(result.get("status")), "queued", "status of an exit with only an entry marker")
	var travelled := await t.until(func() -> bool: return t.world().map_id() == TARGET_MAP and t.player() != null, 3000.0, 6000.0)
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
	var edge: Variant = AreaTravel.entry_marker(world_root, "west")
	var door: Variant = AreaTravel.door_arrival(world_root, DOOR_ID)
	if not t.check(edge != null and door != null, "%s has no player-entry-west marker or %s" % [TARGET_MAP, DOOR_ID]):
		return
	var handoff := {"kind": "area", "map_id": TARGET_MAP, "entry_edge": "west", "entry_marker": BUILT_MARKER}
	t.near_vec(AreaTravel.arrival_point(handoff, Vector2.ZERO), t.world().find_spawn_point(built.global_position), 0.01,
		"a nested named marker over the entry edge")
	handoff["entry_door"] = DOOR_ID
	t.near_vec(AreaTravel.arrival_point(handoff, Vector2.ZERO), t.world().find_spawn_point(door), 0.01,
		"a door over the named marker")
	handoff.erase("entry_door")
	handoff["entry_marker"] = "no-such-marker"
	t.near_vec(AreaTravel.arrival_point(handoff, Vector2.ZERO), t.world().find_spawn_point(edge), 0.01,
		"a missing named marker falls back to the entry edge")
	holder.queue_free()


func _exit_script(t: TestContext, exit_id: String) -> Node:
	for node: Node in t.world().world_root.find_children("*", "Node", true, false):
		if node is WorldExitScript and (node as WorldExitScript).exit_id == exit_id:
			return node
	return null
