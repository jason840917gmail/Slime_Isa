extends RefCounted
## The Clod Stomper (roadmap 8.12; res://game/scripts/clod_stomper.gd), spawned by hand in the
## playground: in reach it crouches behind a ring telegraph, hops and slams; a slime in the ring is
## hit, one outside is not; the slam breaks cracked ground next to it; beaten, it drops a stone
## essence.
##
## Playground places: open ground around (1280, 1536); the cracked ground at (1600, 1040)
## (`cracked.playground-sinkhole`).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")

const MAP_ID := "playground"
const OPEN := Vector2(1280.0, 1536.0)
const CRACKED := Vector2(1600.0, 1040.0)
const CRACK_FLAG := "cracked.playground-sinkhole"
const SCENE_ID := "character.clod-stomper"


func test_it_stomps_behind_a_ring_and_hits_a_slime_in_it(t: TestContext) -> void:
	var player := t.player()
	t.teleport_player(OPEN)
	await t.steps(2)
	var stomper := _spawn(t, OPEN + Vector2(60.0, 0.0))
	if stomper == null:
		return
	var hp := player.get_hp()
	t.check(await t.until(func() -> bool: return stomper.get_phase() == "crouch", 3000.0), "it never crouched next to the slime")
	t.check(AttackTelegraph.of(stomper) != null, "no ring telegraph during the crouch")
	t.check(await t.until(func() -> bool: return stomper.get_phase() == "dazed", 2000.0), "it never slammed")
	t.check(AttackTelegraph.of(stomper) == null, "the telegraph stayed after the slam")
	t.check(player.get_hp() < hp, "the slam missed a slime standing in the ring (hp %d -> %d)" % [hp, player.get_hp()])
	t.check(await t.until(func() -> bool: return stomper.get_phase() == "chase", 2000.0), "it never got up")
	t.check(stomper.get_next_stomp_at() > Services.now_ms(), "the next stomp does not wait its cooldown")


func test_a_slime_that_steps_out_of_the_ring_is_not_hit(t: TestContext) -> void:
	var player := t.player()
	t.teleport_player(OPEN)
	await t.steps(2)
	var stomper := _spawn(t, OPEN + Vector2(60.0, 0.0))
	if stomper == null:
		return
	t.check(await t.until(func() -> bool: return stomper.get_phase() == "crouch", 3000.0), "it never crouched next to the slime")
	t.teleport_player(OPEN - Vector2(200.0, 0.0))
	var hp := player.get_hp()
	t.check(await t.until(func() -> bool: return stomper.get_phase() == "dazed", 2000.0), "it never slammed")
	t.equal(player.get_hp(), hp, "a slime outside the ring was hit")


func test_its_slam_breaks_cracked_ground_next_to_it(t: TestContext) -> void:
	var run := Services.run()
	t.check(not run.has_flag(CRACK_FLAG), "the playground's cracked ground starts broken")
	t.teleport_player(CRACKED + Vector2(0.0, 70.0))
	await t.steps(2)
	var stomper := _spawn(t, CRACKED + Vector2(40.0, 0.0))
	if stomper == null:
		return
	t.check(await t.until(func() -> bool: return stomper.get_phase() == "dazed", 4000.0), "it never slammed")
	await t.steps(2)
	t.check(run.has_flag(CRACK_FLAG), "the slam next to the cracked ground did not break it")


func test_it_drops_a_stone_essence(t: TestContext) -> void:
	t.teleport_player(OPEN)
	await t.steps(2)
	var stomper := _spawn(t, OPEN + Vector2(160.0, 0.0))
	if stomper == null:
		return
	stomper.targeting_radius = 0.0
	stomper.attack_range = 0.0
	await t.steps(1)
	_kill(t, stomper.damage_area)
	var dropped := func() -> bool:
		for node: Node in t.tree.get_nodes_in_group(&"essence"):
			if str(node.get(&"essence")) == "stone" and node.is_inside_tree():
				return true
		return false
	t.check(await t.until(dropped, 1500.0), "no stone essence fell from the beaten Clod Stomper")


func _spawn(t: TestContext, centre: Vector2) -> Node:
	var root := Services.world().spawn_at_phaser_position(SCENE_ID, centre)
	if not t.check(root != null, "%s did not spawn" % SCENE_ID):
		return null
	var stomper := root.get_node_or_null(^"EnemyScript")
	t.check(stomper != null, "the Clod Stomper has no EnemyScript")
	return stomper


func _kill(t: TestContext, target_area: Area2D) -> void:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": target_area,
		"weapon_id": "test-blade", "weapon_tags": ["weapon"], "damage_types": ["physical"], "base_damage": 999.0,
		"effects": [], "impact": {"position": target_area.global_position, "knock": Vector2.RIGHT}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
