extends RefCounted
## The Weaver Hollow's Goo Bomb pieces (docs/design/2026-10-16-dungeon-weaver-hollow.md "What must be
## built" -> The Goo Bomb's locks; roadmap 7.10), in the playground (classic: its Bomb corner takes
## itself out, so the pieces are spawned by hand on open ground):
## - a blast breaks cracked ground (game/scripts/cracked_ground.gd), and the playground's sinkhole
##   leads down to `playground-cavern`; the Stone form's Squash Slam still breaks it; the creak hint
##   names a blast once the bomb is learned;
## - a cracked floor (`object.cracked-floor`, cracked_floor.gd) blown by a bomb is a one-way fall
##   into another world, landing on a named marker there (door.gd `target_marker`);
## - the cracked winch post (`object.winch-post-cracked`, winch_post.gd) triggers its target once,
##   and built again after a save and load it stands broken and calls it with "instant";
## - blast kegs (`object.blast-keg`, blast_keg.gd) a blast apart go off one after another
##   (`puzzles.blastKeg.delayMs` apart) and the last breaks a cracked wall beside it; a keg refuses
##   weapon hits and is not suckable;
## - a Cocoon Mimic with a swallowed drop (cocoon_mimic.gd `swallowed_*`) spits it out once: a
##   second Mimic with the same flag drops nothing, and a picked-up drop does not come back.
##
## Playground places: open ground around (1280, 1536); the cracked ground at (1600, 1040)
## (`cracked.playground-sinkhole`, a ladder down to `playground-cavern`, door `playground-sinkhole`).

const TestContext := preload("res://tests/lib/test_context.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const Services := preload("res://game/shared/services.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")
const CrackedGround := preload("res://game/scripts/cracked_ground.gd")
const DoorScriptType := preload("res://game/scripts/door.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")

const MAP_ID := "playground"
const OPEN := Vector2(1280.0, 1536.0)
const CRACKED := Vector2(1600.0, 1040.0)
const CRACK_FLAG := "cracked.playground-sinkhole"
const CAVERN := "playground-cavern"
const CAVERN_MARKER := "player-spawn"
const FLOOR_FLAG := "test.weaver-well-floor"
const POST_FLAG := "test.weaver-winch-post"
const PILLAR_FLAG := "test.weaver-pillar-crack"
const MIMIC_FLAG := "test.weaver-mimic-key"
const KEY_SCENE := "object.collectible-green-key"
const KEY_ITEM := "green-key"
## Far enough from every spawned piece that no blast reaches the slime.
const AWAY := Vector2(0.0, 320.0)
## A door waits `worldNavigation.edgeTransitionGraceMs` (650) once it is in the tree.
const DOOR_GRACE_MS := 700.0
const KEG_SPACING := 80.0


## Stands in for the kit's drawbridge: counts its calls.
class FakeBridge extends Node2D:
	var calls: Array[Dictionary] = []

	func lower(payload: Dictionary) -> void:
		calls.append(payload)


func test_a_blast_breaks_cracked_ground_and_its_sinkhole_leads_down(t: TestContext) -> void:
	var run := Services.run()
	var ground := _cracked_ground_near(t, CRACKED)
	if not t.check(ground != null, "no cracked ground at %s" % CRACKED):
		return
	t.check(not run.has_flag(CRACK_FLAG) and not ground.is_broken(), "the cracked ground starts broken")
	t.check(ground.is_in_group(&"blast_targets"), "cracked ground is not a blast target")
	t.teleport_player(CRACKED + AWAY)
	await t.steps(2)
	# A blast whose ellipse holds it, off to one side (as a bomb spat beside it).
	GooBlast.detonate(CRACKED + Vector2(50.0, 20.0), false)
	t.check(run.has_flag(CRACK_FLAG), "the blast did not break the cracked ground")
	t.check(ground.is_broken(), "the cracked ground does not know it broke")
	await t.sim_wait(DOOR_GRACE_MS)
	var door := AreaTravel.find_door(t.world().world_root, "playground-sinkhole")
	if not t.check(door != null, "no sinkhole door after the break"):
		return
	await _walk_into(t, door)
	var travelled := await t.until(func() -> bool: return t.in_world(CAVERN) and t.player() != null, 5000.0, 12000.0)
	t.release_all()
	t.check(travelled, "the sinkhole did not lead down to %s" % CAVERN)


func test_a_blast_out_of_reach_leaves_it(t: TestContext) -> void:
	var run := Services.run()
	t.teleport_player(CRACKED + AWAY)
	await t.steps(2)
	var half := GooBlast.half_size()
	GooBlast.detonate(CRACKED + Vector2(half.x + 12.0, 0.0), false)
	await t.steps(2)
	t.check(not run.has_flag(CRACK_FLAG), "a blast whose ellipse missed it broke the cracked ground")


## The Heavy skin's slam (presses_plates since roadmap 7.8, the Stone form's before).
func test_the_heavy_slam_still_breaks_cracked_ground(t: TestContext) -> void:
	var run := Services.run()
	run.learn_ability("squash-slam")
	SkinState.lend(SkinState.HEAVY)
	t.teleport_player(CRACKED + Vector2(0.0, 20.0))
	await t.steps(3)
	t.check(not run.has_flag(CRACK_FLAG), "standing with the Heavy skin cracked the ground")
	t.tap(&"squash_slam")
	await t.until(func() -> bool: return run.has_flag(CRACK_FLAG), 1000.0)
	t.check(run.has_flag(CRACK_FLAG), "a Squash Slam with the Heavy skin no longer cracks the ground")


func test_the_creak_names_a_blast_once_the_bomb_is_learned(t: TestContext) -> void:
	var player := t.player()
	t.equal(CrackedGround.creak_text(false, player, false), CrackedGround.CREAK_TEXT,
		"the creak with nothing learned")
	var blast := CrackedGround.creak_text(true, player, true)
	t.check(blast.contains("blast") and not blast.contains("slam"), "the creak with the bomb learned: '%s'" % blast)


func test_a_cracked_floor_drops_one_way_into_another_world(t: TestContext) -> void:
	var run := Services.run()
	var cracked_floor := Services.world().instantiate_scene("object.cracked-floor") as Node2D
	if not t.check(cracked_floor != null, "object.cracked-floor did not load"):
		return
	cracked_floor.set(&"flag_id", FLOOR_FLAG)
	cracked_floor.set(&"target_area_id", CAVERN)
	cracked_floor.set(&"target_marker", CAVERN_MARKER)
	cracked_floor.position = OPEN
	t.world().entities_root().add_child(cracked_floor)
	t.teleport_player(OPEN + AWAY)
	await t.steps(3)
	var door: Node = cracked_floor.call(&"get_door")
	if not t.check(door != null, "the cracked floor has no hole door"):
		return
	t.equal(str(door.get(&"kind")), "fall", "the hole's kind")
	t.equal(str(door.get(&"target_marker")), CAVERN_MARKER, "the hole's marker")
	t.check(not door.is_inside_tree(), "the hole is there before the floor broke")
	t.check(not bool(cracked_floor.call(&"is_broken")), "the cracked floor starts broken")
	GooBlast.detonate(OPEN + Vector2(-40.0, 10.0), false)
	t.check(run.has_flag(FLOOR_FLAG), "the blast did not break the cracked floor")
	await t.steps(2)
	t.check(door.is_inside_tree(), "the hole did not open")
	await t.sim_wait(DOOR_GRACE_MS)
	await _walk_into(t, door)
	var travelled := await t.until(func() -> bool: return t.in_world(CAVERN) and t.player() != null, 5000.0, 12000.0)
	t.release_all()
	if not t.check(travelled, "the hole did not drop into %s" % CAVERN):
		return
	var marker: Variant = AreaTravel.named_marker(t.world().world_root, CAVERN_MARKER)
	if not t.check(marker != null, "%s has no %s" % [CAVERN, CAVERN_MARKER]):
		return
	t.near_vec(t.player().get_centre(), t.world().find_spawn_point(marker), 0.01, "landed on the marker's tile centre")


## A door with no target is an arrival point only: pushing into it never travels.
func test_a_door_without_a_target_never_travels(t: TestContext) -> void:
	var holder := Node2D.new()
	holder.position = OPEN
	var door := DoorScriptType.new()
	door.door_id = "test-arrival-only"
	door.kind = "fall"
	holder.add_child(door)
	t.world().entities_root().add_child(holder)
	await t.sim_wait(DOOR_GRACE_MS)
	await _walk_into(t, door)
	await t.sim_wait(600.0)
	t.release_all()
	t.check(not t.main.is_transitioning() and t.world().map_id() == MAP_ID, "an arrival-only door travelled")
	holder.queue_free()


func test_the_winch_post_triggers_its_target_once_and_stays_broken(t: TestContext) -> void:
	var run := Services.run()
	var bridge := FakeBridge.new()
	bridge.position = OPEN + Vector2(160.0, -40.0)
	t.world().entities_root().add_child(bridge)
	var post := _spawn_post(t, bridge)
	if post == null:
		return
	t.teleport_player(OPEN + AWAY)
	await t.steps(2)
	var refused: Dictionary = post.call(&"can_receive_damage", {})
	t.check(not bool(refused.get("accepted", true)) and str(refused.get("reason", "")) == "immune",
		"a hit on the post was not refused as a clink: %s" % [refused])
	t.equal(str(post.get(&"refusal_text")), "It needs a blast.", "the post's refusal line")
	t.equal(bridge.calls.size(), 0, "the bridge was triggered before the blast")
	GooBlast.detonate(OPEN + Vector2(30.0, 10.0), false)
	t.check(bool(post.call(&"is_broken")) and run.has_flag(POST_FLAG), "the blast did not break the post")
	if not t.equal(bridge.calls.size(), 1, "calls on the bridge after the blast"):
		return
	t.check(not bool(bridge.calls[0].get("instant", true)), "the blast's call says instant")
	await t.steps(2)
	GooBlast.detonate(OPEN + Vector2(-20.0, 0.0), false)
	t.equal(bridge.calls.size(), 1, "a second blast triggered the bridge again")

	# Saved and loaded, then built again: the post stands broken and lays the bridge down at once.
	var saved: Variant = JSON.parse_string(JSON.stringify(run.serialize()))
	t.check(saved is Dictionary and run.install(saved), "the run did not load again")
	t.check(run.has_flag(POST_FLAG), "the post's flag was not saved")
	post.get_parent().queue_free()
	await t.steps(2)
	var again := _spawn_post(t, bridge)
	if again == null:
		return
	await t.steps(2)
	t.check(bool(again.call(&"is_broken")), "the post built again is not broken")
	t.check(again.get_node_or_null(^"DamageArea") == null or again.get_node(^"DamageArea").is_queued_for_deletion(),
		"the broken post still has its hurtbox")
	if t.equal(bridge.calls.size(), 2, "calls on the bridge after the post was built again"):
		t.check(bool(bridge.calls[1].get("instant", false)), "the load's call is not instant")
	GooBlast.detonate(OPEN, false)
	t.equal(bridge.calls.size(), 2, "a blast on the broken post triggered the bridge")
	bridge.queue_free()


func test_kegs_chain_and_break_the_cracked_target(t: TestContext) -> void:
	var run := Services.run()
	t.teleport_player(OPEN + AWAY)
	await t.steps(2)
	var kegs: Array[Node] = []
	var blown: Array[float] = []
	var wall_broken_before_last := {"value": false}
	for i in 4:
		var keg := Services.world().instantiate_scene("object.blast-keg") as Node2D
		if not t.check(keg != null, "object.blast-keg did not load"):
			return
		keg.position = OPEN + Vector2(KEG_SPACING * i, 0.0)
		t.world().entities_root().add_child(keg)
		kegs.append(keg)
	var wall := Services.world().instantiate_scene("object.cracked-wall") as Node2D
	if not t.check(wall != null, "object.cracked-wall did not load"):
		return
	wall.set(&"flag_id", PILLAR_FLAG)
	wall.position = OPEN + Vector2(KEG_SPACING * 3.0 + 60.0, 0.0)
	t.world().entities_root().add_child(wall)
	for i in kegs.size():
		kegs[i].connect(&"set_off", _on_keg_blown.bind(blown, i == kegs.size() - 2, wall, wall_broken_before_last))
	await t.steps(2)
	# A blast that reaches only the first keg.
	GooBlast.detonate(OPEN + Vector2(-50.0, 0.0), false)
	t.check(bool(kegs[0].call(&"is_lit")), "the blast did not light the first keg")
	t.check(not bool(kegs[1].call(&"is_lit")), "the blast reached the second keg itself")
	var all_blown := func() -> bool:
		for keg: Node in kegs:
			if not bool(keg.call(&"is_spent")):
				return false
		return true
	if not t.check(await t.until(all_blown, 2000.0), "the chain stopped (%d of 4 kegs blew)" % blown.size()):
		return
	var delay := Services.constants().number("puzzles.blastKeg.delayMs")
	for i in range(1, blown.size()):
		t.between(blown[i] - blown[i - 1], delay - 1.0, delay + 40.0, "keg %d went off after keg %d" % [i + 1, i])
	t.check(not wall_broken_before_last["value"], "the cracked wall broke before the last keg blew")
	t.check(run.has_flag(PILLAR_FLAG) and bool(wall.call(&"is_broken")), "the last keg did not break the cracked wall")


func test_a_keg_refuses_hits_and_the_gulp(t: TestContext) -> void:
	var keg := Services.world().instantiate_scene("object.blast-keg") as Node2D
	if not t.check(keg != null, "object.blast-keg did not load"):
		return
	keg.position = OPEN
	t.world().entities_root().add_child(keg)
	t.teleport_player(OPEN + AWAY)
	await t.steps(2)
	var area := keg.get_node_or_null(^"DamageArea") as Area2D
	if not t.check(area != null, "the keg has no hurtbox"):
		return
	var result := _hit(t, area)
	t.check(str(result.get("status", "")) != "accepted", "a weapon hit on the keg was accepted: %s" % [result])
	var refused: Dictionary = keg.call(&"can_receive_damage", {})
	t.equal(str(refused.get("reason", "")), "immune", "the keg's refusal")
	t.equal(str(keg.get(&"refusal_text")), "It needs a blast.", "the keg's refusal line")
	await t.steps(2)
	t.check(not bool(keg.call(&"is_lit")) and not bool(keg.call(&"is_spent")), "a weapon hit set the keg off")
	t.check(not keg.is_in_group(&"suckable") and not keg.is_in_group(&"liftable"), "the Gulp can take a keg")
	t.check(keg is StaticBody2D and (keg as StaticBody2D).collision_layer != 0, "the keg does not block")


func test_the_mimic_drops_its_key_once(t: TestContext) -> void:
	var run := Services.run()
	t.teleport_player(OPEN + AWAY + AWAY)
	await t.steps(2)
	var first := _spawn_mimic(t, OPEN)
	if first == null:
		return
	await t.steps(2)
	t.check(bool(first.call(&"has_swallowed")), "the Mimic has nothing swallowed")
	_hit(t, first.get(&"damage_area") as Area2D, 9999.0)
	t.check(await t.until(func() -> bool: return bool(first.call(&"is_defeated")), 1000.0), "the Mimic was not beaten")
	t.check(run.has_flag(MIMIC_FLAG), "beaten, the Mimic did not set its flag")
	var drops := _drops(t)
	if not t.equal(drops.size(), 1, "drops after the first Mimic"):
		return
	var collectible := drops[0].get_node_or_null(^"CollectibleScript")
	if t.check(collectible != null, "the drop is not the collectible"):
		t.equal(str(collectible.get(&"instance_id")), MIMIC_FLAG, "the drop's record id")
		t.equal(str(collectible.get(&"map_id")), t.world().map_id(), "the drop's map")

	# Another Mimic with the same flag (built again): it has nothing more, and the drop is not doubled.
	var second := _spawn_mimic(t, OPEN + Vector2(200.0, 0.0))
	if second == null:
		return
	await t.steps(3)
	t.check(not bool(second.call(&"has_swallowed")), "a Mimic with the flag set still has something swallowed")
	t.equal(_drops(t).size(), 1, "drops once the second Mimic is built")
	_hit(t, second.get(&"damage_area") as Area2D, 9999.0)
	await t.until(func() -> bool: return bool(second.call(&"is_defeated")), 1000.0)
	await t.steps(2)
	t.equal(_drops(t).size(), 1, "drops after the second Mimic")

	# Picked up, it never comes back.
	var area := drops[0].get_node_or_null(^"PickupArea") as Area2D
	await t.until(func() -> bool: return area != null and is_instance_valid(area) and area.monitorable, 1000.0)
	if collectible != null and is_instance_valid(collectible):
		collectible.call(&"request_pickup", t.player().get_pickup_area())
	t.equal(run.item_count(KEY_ITEM), 1, "keys in the bag after the pickup")
	await t.steps(2)
	var third := _spawn_mimic(t, OPEN + Vector2(-200.0, 0.0))
	if third == null:
		return
	await t.steps(4)
	t.equal(_drops(t).size(), 0, "a taken drop came back with a Mimic built again")
	t.equal(run.item_count(KEY_ITEM), 1, "keys in the bag at the end")


# --- helpers -------------------------------------------------------------------------------------

func _cracked_ground_near(t: TestContext, at: Vector2) -> Node:
	for node: Node in t.tree.get_nodes_in_group(CrackedGround.GROUP):
		var root := node.get_parent() as Node2D
		if root != null and root.global_position.distance_to(at) < 8.0:
			return node
	return null


## Puts the slime's body centre just above the middle of `door`'s doorway and walks it down through.
func _walk_into(t: TestContext, door: Node) -> void:
	var trigger: Rect2 = door.call(&"trigger_global")
	var body_offset := DoorScriptType._body_rect(t.player_body()).get_center() - t.player().get_centre()
	t.teleport_player(trigger.get_center() - Vector2(0.0, trigger.size.y * 0.45) - body_offset)
	await t.steps(1)
	t.press(&"move_down")


func _spawn_post(t: TestContext, bridge: Node) -> Node:
	var post := Services.world().instantiate_scene("object.winch-post-cracked") as Node2D
	if not t.check(post != null, "object.winch-post-cracked did not load"):
		return null
	post.set(&"flag_id", POST_FLAG)
	post.set(&"target_path", bridge.get_path())
	post.set(&"target_method", &"lower")
	# The fake bridge keeps no record of its own, so the post lays it down again when built broken.
	post.set(&"call_on_load", true)
	# A holder, so the test can free the whole post as a world teardown would.
	var holder := Node2D.new()
	holder.add_child(post)
	post.position = OPEN
	t.world().entities_root().add_child(holder)
	return post


func _spawn_mimic(t: TestContext, feet: Vector2) -> Node:
	var root := Services.world().instantiate_scene("character.cocoon-mimic") as Node2D
	if not t.check(root != null, "character.cocoon-mimic did not load"):
		return null
	var mimic := root.get_node_or_null(^"EnemyScript")
	if not t.check(mimic != null, "the Mimic has no EnemyScript"):
		root.free()
		return null
	# As a placed enemy's `overrides` set them.
	mimic.set(&"swallowed_flag", MIMIC_FLAG)
	mimic.set(&"swallowed_scene_id", KEY_SCENE)
	mimic.set(&"targeting_radius", 0.0)
	root.position = feet
	t.world().entities_root().add_child(root)
	return mimic


## A keg's `set_off`: its time, and (for the one before the last) whether the wall already broke.
static func _on_keg_blown(_payload: Dictionary, blown: Array[float], before_last: bool, wall: Node, state: Dictionary) -> void:
	blown.append(Services.now_ms())
	if before_last:
		state["value"] = bool(wall.call(&"is_broken"))


## The swallowed drops in the world (not freed).
func _drops(t: TestContext) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in t.tree.get_nodes_in_group(&"swallowed_drops"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.is_inside_tree():
			found.append(node)
	return found


## One router hit of `damage` on `target_area` (a test blade); returns the router's result.
func _hit(t: TestContext, target_area: Area2D, damage: float = 30.0) -> Dictionary:
	var router := Services.router()
	if target_area == null or router == null:
		return {}
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	var result: Dictionary = router.route({"activation_id": activation, "source": source, "attack_area": attack,
		"target_area": target_area, "weapon_id": "test-blade", "weapon_tags": ["weapon"], "damage_types": ["physical"],
		"base_damage": damage, "effects": [], "impact": {"position": target_area.global_position, "knock": Vector2.RIGHT}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
	return result
