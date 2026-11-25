extends RefCounted
## The dungeon's seal and the Pearl's take (docs/godot/DUNGEONS.md "The seal"; decisions archive
## 2026-10-17, the Pearl inside the dungeon), in the dungeon lab (tools/build_dungeon_lab.gd): C1's
## Pearl rises once its guard falls; taking it grants its skin and seals the dungeon; the seal in
## B3's way out shuts and refuses, and every travel out refuses; a faint or a quit resumes at the
## entrance, inside, with the seal still on and everything opened for good still open; the boss
## (B0's Big Squint) shows his rage, and his fall breaks the seal.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const EnragedLook := preload("res://game/bosses/enraged_look.gd")

const LAB := "dungeon-lab"
const BOSS := "dungeon-lab-boss"
const GUARD := "dungeon-lab-guard"
const ENTRANCE := Vector2(1536, 3328)
## C1's Pearl (cells (8, 4.3) of the room at (32, 14)).
const PEARL_AT := Vector2(2560, 1171.2)
## B3's middle, above its seal (the way out south).
const ABOVE_SEAL := Vector2(1536, 3420)
## B0's middle (the boss room).
const BOSS_ROOM := Vector2(1536, 560)
const SLOT := 0


# --- the record ------------------------------------------------------------------------------------

func test_the_record_seals_until_the_boss_falls(t: TestContext) -> void:
	var run := Services.run()
	t.check(not DungeonState.is_sealed(run, "seal-test"), "a new dungeon is sealed")
	t.check(not DungeonState.seal(run, "seal-test", ""), "a seal without a boss")
	t.check(DungeonState.seal(run, "seal-test", "seal-test-boss", "seal-test-pearl"), "the seal did not take")
	t.check(DungeonState.is_sealed(run, "seal-test"), "not sealed after the seal")
	t.equal(DungeonState.sealed_by(run, "seal-test"), "seal-test-boss", "the boss who holds the seal")
	t.check(not DungeonState.seal(run, "seal-test", "seal-test-boss"), "sealed twice")
	var saved: Dictionary = ((run.serialize().get("world", {}) as Dictionary).get(DungeonState.RECORD_KEY, {}) as Dictionary).get("seal-test", {})
	t.equal(str((saved.get("seal", {}) as Dictionary).get("boss_id", "")), "seal-test-boss", "the seal in the saved record")
	t.check(DungeonState.unseal(run, "seal-test"), "unseal did not break a seal")
	t.check(not DungeonState.is_sealed(run, "seal-test"), "still sealed after unseal")
	# His fall breaks it, in the record or only in `defeated_boss_ids` (a boss camp's).
	DungeonState.seal(run, "seal-test", "seal-test-boss")
	DungeonState.mark_boss_beaten(run, "seal-test", "seal-test-boss")
	t.check(not DungeonState.is_sealed(run, "seal-test"), "sealed after his fall")
	t.check((DungeonState.record(run, "seal-test")["seal"] as Dictionary).is_empty(), "his fall left the seal in the record")
	DungeonState.seal(run, "seal-test-2", "seal-test-boss-2")
	(run.world.get_or_add("defeated_boss_ids", []) as Array).append("seal-test-boss-2")
	t.check(not DungeonState.is_sealed(run, "seal-test-2"), "sealed after his camp recorded his fall")
	# An old save that beat the boss first never seals.
	t.check(not DungeonState.seal(run, "seal-test", "seal-test-boss"), "a seal after his fall")


# --- the take ----------------------------------------------------------------------------------------

func test_the_pearl_rises_for_its_guard_and_its_take_seals_the_dungeon(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var pearl := _node(t, "c1-pearl")
	var seal := _node(t, "b3-seal")
	if not t.check(pearl != null and seal != null, "the lab has no Pearl or no seal"):
		return
	t.check(not bool(pearl.call(&"is_shown")), "the Pearl shows before its guard falls")
	t.check(not bool(seal.call(&"is_shut")), "the seal is shut before the take")
	DungeonState.mark_boss_beaten(run, LAB, GUARD)
	var shown := await t.until(func() -> bool: return bool(pearl.call(&"is_shown")), 2000.0)
	t.check(shown, "the Pearl did not rise once its guard fell")
	t.teleport_player(PEARL_AT + Vector2(72, 30))
	var taken := await t.until(func() -> bool: return bool(pearl.call(&"is_taken")), 2000.0)
	t.check(taken, "walking into the Pearl did not take it")
	t.check(run.has_flag("pearl.dungeon-lab"), "the Pearl's flag")
	t.check(SkinState.is_won(SkinState.FERAL), "the take did not grant the Feral skin")
	t.equal(SkinState.look(), &"", "the take changed the everyday look (a skin shows only while it works)")
	t.check(DungeonState.is_sealed(run, LAB), "the take did not seal the dungeon")
	t.equal(DungeonState.sealed_by(run, LAB), BOSS, "the seal's boss")
	t.check(bool(seal.call(&"is_shut")), "the entrance's seal is not shut after the take")
	# The moment: the roar, then the glimpse of the entrance's seal (the world paused, the view on it),
	# then the view back on the slime.
	var glimpsed := await t.until(func() -> bool: return _glimpsing(t), 60000.0, 4000.0)
	t.check(glimpsed, "the take did not glimpse the entrance's seal")
	if glimpsed:
		var camera: Camera2D = t.world().camera
		t.check(t.tree.paused, "the world runs during the glimpse")
		t.check((camera.call(&"view_rect") as Rect2).has_point((seal as Node2D).global_position), "the glimpse does not show the seal")
	var done := await t.until(func() -> bool: return _node(t, "SealMoment") == null and not t.tree.paused, 60000.0, 6000.0)
	t.check(done, "the take's moment did not end")
	t.near(float(seal.get(&"_height")), 1.0, 0.01, "the seal's block after the glimpse")
	var camera_after: Camera2D = t.world().camera
	t.check((camera_after.call(&"view_rect") as Rect2).has_point(t.player().get_centre()), "the view did not come back to the slime")


# --- the ways out --------------------------------------------------------------------------------------

func test_a_sealed_dungeon_refuses_its_ways_out(t: TestContext) -> void:
	await _enter_lab(t)
	var seal := _node(t, "b3-seal")
	var dungeon := DungeonState.current(t.tree)
	t.equal(DungeonState.world_dungeon_id(LAB), LAB, "the lab's dungeon id")
	t.equal(DungeonState.world_dungeon_id("weaver-hollow-c2-crown"), "weaver-hollow", "a room world's dungeon id, read from its scene")
	t.equal(DungeonState.world_dungeon_id("playground"), "", "the playground's dungeon id")
	t.equal(DungeonState.exit_refusal(t.tree, "playground"), "", "a way out refused before the seal")
	t.check(bool(dungeon.call(&"seal_now", "test", false)), "the dungeon did not seal")
	t.check(bool(seal.call(&"is_shut")), "the seal is not shut")
	t.check(str(DungeonState.exit_refusal(t.tree, "playground")).begins_with("Sealed."), "a way out is not refused while sealed")
	t.equal(DungeonState.exit_refusal(t.tree, LAB), "", "a way inside the dungeon is refused")
	var result: Dictionary = t.main.call(&"request_exit", {"map_id": LAB, "target_area_id": "playground",
		"entry_marker": "player-spawn", "transition": "iris"})
	t.equal(str(result.get("status", "")), "blocked", "the way out's travel while sealed")
	t.check(not bool(t.main.call(&"is_transitioning")), "the slime left a sealed dungeon")
	# Walked into, the seal refuses and holds.
	var refused: Array = []
	seal.connect(&"refused", func(payload: Dictionary) -> void: refused.append(payload))
	t.teleport_player(ABOVE_SEAL)
	t.press(&"move_down")
	await t.sim_wait(900.0)
	t.release(&"move_down")
	await t.steps(2)
	t.check(not refused.is_empty(), "walking into the seal was not refused")
	t.check(t.in_world(LAB) and not bool(t.main.call(&"is_transitioning")), "the slime walked out past the seal")
	t.check(t.player().get_centre().y < (seal as Node2D).global_position.y, "the slime passed the seal")
	# A bomb's blast is refused too.
	refused.clear()
	t.check(not bool(seal.call(&"receive_blast", {})), "a blast broke the seal")
	t.check(not refused.is_empty(), "a blast was not refused")
	# Unsealed (a test's), the way out is open again.
	DungeonState.unseal(Services.run(), LAB)
	t.equal(DungeonState.exit_refusal(t.tree, "playground"), "", "the way out after unsealing")


# --- resuming ----------------------------------------------------------------------------------------

func test_a_faint_and_a_quit_resume_inside_with_the_seal_on(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var door := _node(t, "b3-key-door")
	door.call(&"open_for_good")
	DungeonState.current(t.tree).call(&"seal_now", "test", false)
	# A faint: the slime wakes at the entrance, inside the seal; what was opened stays open.
	t.teleport_player(Vector2(1300, 2300))
	await t.steps(3)
	_hit(t, t.player().get_damage_area(), 9999.0)
	await t.until(func() -> bool: return not t.player().is_dead(), 6000.0, 8000.0)
	await t.steps(2)
	t.near_vec(t.player().get_centre(), ENTRANCE, 2.0, "where the fainted slime woke")
	t.check(bool(_node(t, "b3-seal").call(&"is_shut")), "the seal after the faint")
	t.check(bool(door.call(&"is_open")), "the key door after the faint")
	# A quit: the resume save puts the slime at the entrance; Continue builds the lab sealed.
	DungeonState.current(t.tree).set(&"resume_saves", true)
	t.teleport_player(Vector2(1300, 2300))
	await t.steps(3)
	t.check(run.save_slot(SLOT), "the quit's resume save was not written")
	t.check(bool(t.main.call(&"load_run", SLOT)), "the resume save did not load")
	await t.until(func() -> bool: return t.in_world(LAB) and t.player() != null and DungeonState.current(t.tree) != null, 4000.0)
	await t.steps(3)
	t.near_vec(t.player().get_centre(), ENTRANCE, 2.0, "the slime after Continue")
	t.check(DungeonState.is_sealed(run, LAB), "the dungeon after Continue")
	var seal := _node(t, "b3-seal")
	t.check(seal != null and bool(seal.call(&"is_shut")), "the seal after Continue")
	t.near(float(seal.get(&"_height")) if seal != null else 0.0, 1.0, 0.01, "the seal's block after Continue")
	t.check(bool(_node(t, "b3-key-door").call(&"is_open")), "the key door after Continue")
	run.delete_slot(SLOT)


# --- the boss -----------------------------------------------------------------------------------------

func test_the_boss_shows_his_rage_and_his_fall_breaks_the_seal(t: TestContext) -> void:
	var run := Services.run()
	await _enter_lab(t)
	var seal := _node(t, "b3-seal")
	DungeonState.current(t.tree).call(&"seal_now", "test", false)
	# His fight starts while sealed: his rage shows (presentation only).
	t.teleport_player(BOSS_ROOM)
	var fight := _node(t, "b0-fight")
	var started := await t.until(func() -> bool: return bool(fight.call(&"is_active")), 3000.0)
	t.check(started, "the boss fight did not start")
	var boss: Node = null
	for member: Node in fight.call(&"members"):
		boss = member.call(&"get_enemy")
	if t.check(boss != null, "no boss in the fight"):
		t.check(EnragedLook.is_on(boss), "the boss does not show his rage while sealed")
		var state: Dictionary = boss.call(&"get_damage_state")
		t.near(float(state.get("max_hp", 0.0)), 96.0, 0.01, "the enraged boss's health")
	# His fall: the seal sinks, the way out opens, his full heart shows.
	DungeonState.mark_boss_beaten(run, LAB, BOSS)
	var broke := await t.until(func() -> bool: return not bool(seal.call(&"is_shut")), 3000.0)
	t.check(broke, "his fall did not break the seal")
	t.check(not DungeonState.is_sealed(run, LAB), "sealed after his fall")
	t.equal(DungeonState.exit_refusal(t.tree, "playground"), "", "the way out after his fall")
	var heart := _node(t, "b0-full-heart")
	var shown := await t.until(func() -> bool: return bool(heart.get_node("FullHeartScript").call(&"is_shown")), 2000.0)
	t.check(shown, "his full heart did not show")
	# Built again, the seal stays down for good.
	await _enter_lab(t)
	t.check(not bool(_node(t, "b3-seal").call(&"is_shut")), "the seal after his fall and a rebuild")


# --- helpers ---------------------------------------------------------------------------------------------

func _enter_lab(t: TestContext) -> void:
	t.main.call(&"travel_to", LAB)
	await t.until(func() -> bool: return t.in_world(LAB) and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")) and DungeonState.current(t.tree) != null, 5000.0)
	await t.steps(4)


func _node(t: TestContext, node_name: String) -> Node:
	var world_root: Node = t.world().world_root if t.world() != null else null
	return world_root.find_child(node_name, true, false) if world_root != null else null


func _glimpsing(t: TestContext) -> bool:
	var moment := _node(t, "SealMoment")
	return moment != null and bool(moment.call(&"is_glimpsing"))


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
