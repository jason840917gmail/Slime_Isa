extends RefCounted
## Area travel (docs/godot/specs/world.md section 8, game/world/area_travel.gd, Main.travel_to):
## level-1's east exit (`exit-1`, centre (3552, 576), target gloop-forest entry "west") is gated
## by `level-1-east-verdant-gate` (green key, consumed). Without the key the player stays and the
## exit reports "blocked"; with it the key is used, the gate is remembered, the picture fades out
## and gloop-forest is built with the player on the tile centre at its `player-entry-west` marker,
## keeping its HP.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")

const EXIT_CENTRE := Vector2(3552.0, 576.0)
const GATE_ID := "level-1-east-verdant-gate"
const KEY_ID := "green-key"
const TARGET_MAP := "gloop-forest"
const GRACE_MS := 650.0
const CARRIED_HP := 61


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


func _exit_script(t: TestContext, exit_id: String) -> Node:
	for node: Node in t.world().world_root.find_children("*", "Node", true, false):
		if node is WorldExitScript and (node as WorldExitScript).exit_id == exit_id:
			return node
	return null
