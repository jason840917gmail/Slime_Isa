extends RefCounted
## The prologue (roadmap 5.18 to 5.24; docs/design/2026-10-16-prologue.md; docs/godot/PROLOGUE.md):
## a new game opens on the slime's birth at the Wellspring (west-village-b4, B4's south edge), with
## no HUD until the birth is over; nothing is saved while it runs; the path out opens only once its
## light things are gone; stepping into the glade plays Yoi's fight with the slime held still; the
## rescue cannot be lost (a faint wakes the slime at the glade's edge, the worms back); Yoi teaches
## the Spear; the barred gate opens only to a Spear thrust through its bars; the path beyond leads
## into Slimeshire (level-1-c4), where Plop meets the slime with his satchel and ends the prologue;
## quitting during it leaves no save, so the next start plays it again from the birth.
##
## Every test starts in west-village-b4 (a run that is not playing the prologue: the places stand
## as after it) and enters the prologue itself (`_enter`), with the beats it skips already played.
## The ceremony is off in the test runner, so the Spear and the satchel show their banner instead.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const PrologueState := preload("res://game/prologue/prologue_state.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const TitleScript := preload("res://game/shell/title.gd")
const ShellScript := preload("res://game/shell/shell.gd")

const MAP_ID := "west-village-b4"
const TITLE_SCENE := "res://game/shell/title.tscn"
const DIRECTOR := "Prologue"
## Inside the glade trigger (the slime's centre).
const GLADE_ENTRY := Vector2(1150, 1600)
## In front of the barred gate's bars, facing them (the gate's foot is (1536, 1340)).
const AT_THE_BARS := Vector2(1536, 1330)
const BEYOND_THE_GATE := Vector2(1536, 1230)
## The path's end at B4's east edge (the exit into level-1-c4).
const EXIT_POINT := Vector2(2030, 1696)
## The birth's whole length (dawn, rise, wobble, drift, pop, hold) is about 6 s of game time.
const BIRTH_SIM_MS := 9000.0

var _parked_shell: Node
var _parked_index := 0


func test_a_new_game_starts_the_prologue_with_the_birth(t: TestContext) -> void:
	var run := Services.run()
	run.save_slot(0)
	_park_shell(t)
	t.main.remove_from_group(ShellScript.WORLD_MAIN_GROUP)
	var title := (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScript
	title.backdrop_enabled = false
	title.skip_for_launch_options = false
	var changes: Array[String] = []
	title.change_scene = func(path: String) -> void: changes.append(path)
	t.tree.root.add_child(title)
	await t.steps(1)
	title.new_game_button.pressed.emit()
	await t.steps(1)
	if title.confirm_row.visible:
		title.confirm_button.pressed.emit()
	await t.steps(1)
	t.equal(changes, ["res://game/main.tscn"] as Array[String], "New Game enters the game")
	var navigation := run.peek_navigation()
	t.equal(str(navigation.get("map_id", "")), PrologueState.START_MAP_ID, "New Game goes to the Wellspring's chunk")
	t.equal(str(navigation.get("entry_marker", "")), PrologueState.BIRTH_MARKER, "at the birth spot")
	t.check(PrologueState.is_running(run), "the prologue does not run after New Game")
	t.equal(int(run.inventory.get("max_slots", -1)), 0, "the newborn has no bag")
	t.check(not run.has_save(0), "the old autosave the player agreed to replace is still there")
	title.queue_free()
	await t.steps(1)
	t.main.add_to_group(ShellScript.WORLD_MAIN_GROUP)
	_unpark_shell(t)
	# main builds the queued world, as it does on its first boot.
	run.consume_navigation()
	t.main.call(&"travel_to", PrologueState.START_MAP_ID, "", "", PrologueState.BIRTH_MARKER)
	await t.until(func() -> bool: return _director(t) != null and int(_director(t).get(&"phase")) != 0, 3000.0)
	var director := _director(t)
	if not t.check(director != null, "no prologue director in %s" % MAP_ID):
		return
	t.check(ReworkMode.is_on(), "the prologue does not play in the body-shapes mode (its Spear)")
	var hud := t.main.get(&"hud") as CanvasLayer
	t.check(not hud.visible, "the HUD shows during the birth")
	t.check(not t.player_body().visible, "the slime shows before the bubble pops")
	t.near_vec(t.player().get_centre(), (director.get(&"birth") as Node2D).global_position, 4.0, "the slime's birth spot")
	var born := await t.until(func() -> bool: return PrologueState.has_beat(run, PrologueState.BORN), BIRTH_SIM_MS)
	t.check(born, "the birth did not end")
	await t.steps(2)
	t.check(hud.visible, "the HUD did not come back after the birth")
	t.check(t.player_body().visible, "the slime is not there after the birth")
	t.check(not bool(t.player().get(&"dodge_learned")), "the newborn can roll")
	t.check(not t.world().has_pause_reason(&"modal"), "a window is open after the birth")


func test_the_hints_follow_the_prologues_order(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [])
	var hints := t.main.get_node("ControlHints")
	await t.steps(4)
	t.equal(hints.get(&"current"), &"", "a hint shows during the birth")
	run.set_flag(PrologueState.BORN)
	await t.steps(4)
	t.equal(hints.get(&"current"), &"move", "the first hint after the birth")
	run.set_flag("hint.move")
	var lone := _director(t).get_node("LonePot").get_child(0) as Node2D
	t.teleport_player(lone.global_position + Vector2(0, 60))
	t.player().face(Vector2.UP)
	await t.until(func() -> bool: return hints.get(&"current") == &"mouth", 500.0)
	t.equal(hints.get(&"current"), &"mouth", "the Gulp's hint by the lone pot")
	var ids: Array = (hints.get_script() as Script).get_script_constant_map()["PROLOGUE_HINT_IDS"]
	for missing: StringName in [&"inventory", &"dodge", &"map", &"pause", &"journal", &"charge", &"interact"]:
		t.check(not ids.has(missing), "the prologue's hints name %s, which the slime does not have yet" % missing)
	t.check(not str(hints.call(&"hint_text", &"thrust-bars")).is_empty(), "no hint for the barred gate")


func test_nothing_is_saved_in_the_prologue(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN])
	t.equal(run.saving_blocked_reason(), PrologueState.NO_SAVE_REASON, "saving is not blocked")
	t.check(not run.save_slot(1), "a slot was saved in the prologue")
	t.check(not run.has_save(1), "slot 1 exists")
	run.autosave_enabled = true
	run.schedule_autosave()
	await t.sim_wait(600.0)
	t.check(not run.write_recovery(), "the recovery autosave was written")
	t.check(not run.has_save(0), "an autosave was written in the prologue")
	var shell := Services.shell()
	t.check(shell.open_pause(), "the pause menu did not open")
	await t.steps(1)
	t.check(shell.pause_menu.button_for(&"save").disabled, "Save is not greyed out in the prologue")
	t.equal(shell.pause_menu.hint_label.text, ShellScript.PROLOGUE_NO_SAVE_HINT, "the pause menu's hint")
	shell.pause_menu.close()
	await t.steps(1)
	PrologueState.finish(run)
	t.check(run.can_save(), "saving is still blocked after the prologue")
	t.check(run.save_slot(1), "a save failed after the prologue")
	run.delete_slot(1)
	run.autosave_enabled = false


func test_the_blocked_path_opens_only_once_its_light_things_are_gone(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN])
	var director := _director(t)
	var path := director.get(&"path_blocked") as Node2D
	var things: Array[Node] = []
	for child: Node in path.get_children():
		if child.get_node_or_null(^"LiftableScript") != null:
			things.append(child)
	t.check(things.size() >= 4, "the path has %d light things" % things.size())
	# The slime cannot walk out past them.
	t.teleport_player(Vector2(800, 1600))
	t.press(&"move_right")
	await t.sim_wait(1500.0)
	t.release(&"move_right")
	t.check(t.player().get_centre().x < 1030.0, "the slime walked out through the blocked path (x %.0f)" % t.player().get_centre().x)
	# The Gulp: the lone pot by the shore, sucked in and thrown.
	var lone := director.get_node("LonePot").get_child(0) as Node2D
	t.teleport_player(lone.global_position + Vector2(0, 70))
	t.player().face(Vector2.UP)
	await t.steps(2)
	t.press(&"eat")
	await t.until(func() -> bool: return not t.player().held().is_empty(), 1500.0)
	t.release(&"eat")
	await t.steps(2)
	t.equal(str(t.player().held().get("kind", "")), "clay-pot", "the Gulp sucked in the lone pot")
	t.tap(&"eat")
	await t.until(func() -> bool: return t.player().held().is_empty(), 1000.0)
	t.check(t.player().held().is_empty(), "the pot was not thrown")
	# Every piece but the last gone: still shut.
	for i in things.size() - 1:
		(things[i].get_node(^"LiftableScript") as Node).call(&"take")
	await t.steps(4)
	t.check(not PrologueState.has_beat(run, PrologueState.PATH_CLEARED), "the path opened with a piece left")
	TestContext.silence(_secret_cue(t))
	(things[things.size() - 1].get_node(^"LiftableScript") as Node).call(&"take")
	var opened := await t.until(func() -> bool: return PrologueState.has_beat(run, PrologueState.PATH_CLEARED), 500.0)
	t.check(opened, "the path did not open once cleared")
	await t.steps(3)
	t.check(director.get(&"barrier") == null, "the barrier is still there")
	t.check(TestContext.played(_secret_cue(t)), "the secret jingle did not play")
	# (A little further on, the glade's edge starts the attack and holds the slime.)
	t.teleport_player(Vector2(980, 1600))
	t.press(&"move_right")
	await t.until(func() -> bool: return t.player().get_centre().x > 1060.0, 3000.0)
	t.release(&"move_right")
	t.check(t.player().get_centre().x > 1060.0, "the slime cannot walk out of the cleared path")


func test_the_attack_plays_once_with_the_slime_held(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN, PrologueState.PATH_CLEARED])
	var director := _director(t)
	var struck_a := _enemy(director, &"worm_struck_a")
	var struck_b := _enemy(director, &"worm_struck_b")
	t.check(struck_a != null and struck_b != null, "the two worms on Yoi's line are not there")
	t.teleport_player(GLADE_ENTRY)
	await t.until(func() -> bool: return int(director.get(&"phase")) == 3, 500.0)
	t.equal(int(director.get(&"phase")), 3, "the attack did not start in the glade")
	var held_at := t.player().get_centre()
	t.press(&"move_left")
	await t.sim_wait(1000.0)
	t.release(&"move_left")
	t.near_vec(t.player().get_centre(), held_at, 2.0, "the slime moved during the attack")
	var camera := t.world().camera
	t.check(camera.center.distance_to(held_at) > 150.0, "the camera did not pan to the fight")
	var fell := await t.until(func() -> bool: return _defeated(struck_a) and _defeated(struck_b), 4000.0)
	t.check(fell, "the two worms on Yoi's line did not fall to his thrust")
	var called := await t.until(func() -> bool: return _box(t) != null and bool(_box(t).call(&"is_open")), 4000.0)
	t.check(called, "Yoi did not call for help")
	await _close_dialogues(t, func() -> bool: return PrologueState.has_beat(run, PrologueState.FIGHT_SEEN), 4000.0)
	t.check(PrologueState.has_beat(run, PrologueState.FIGHT_SEEN), "the attack did not end")
	await t.sim_wait(700.0)
	t.check(camera.view_rect().grow(-24.0).has_point(t.player().get_centre()), "the camera did not come back to the slime")
	t.near(camera.target_zoom, 1.0, 0.001, "the camera's zoom after the attack")
	var biter := _enemy(director, &"worm_biter")
	t.check(biter != null and biter.is_physics_processing(), "the worms left did not turn on the slime")
	t.press(&"move_left")
	await t.sim_wait(400.0)
	t.release(&"move_left")
	t.check(t.player().get_centre().x < held_at.x - 10.0, "the slime cannot move after the attack")
	# It never plays again.
	t.teleport_player(GLADE_ENTRY + Vector2(0, 20))
	await t.sim_wait(300.0)
	t.equal(int(director.get(&"phase")), 4, "the attack played again")


func test_the_rescue_cannot_be_lost(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN, PrologueState.PATH_CLEARED, PrologueState.FIGHT_SEEN])
	var director := _director(t)
	var biter := _enemy(director, &"worm_biter")
	var other := _enemy(director, &"worm_other")
	t.check(biter != null and other != null, "the rescue's two worms are not there")
	t.check(_enemy(director, &"worm_struck_a") == null, "a worm Yoi struck is back")
	var biter_home := (director.get(&"worm_biter") as Node2D).global_position
	# A worm's bite hurts the slime.
	var hurt_at := t.player().get_hp()
	t.teleport_player(biter.get_centre() + Vector2(-30, 0))
	await t.until(func() -> bool: return t.player().get_hp() < hurt_at, 5000.0)
	t.check(t.player().get_hp() < hurt_at, "a prologue worm's bite does not hurt")
	# The slime faints: no game over, it wakes at the glade's edge, the worms are back.
	var shell := Services.shell()
	_hit(t.player(), 9999)
	t.check(t.player().is_dead(), "the slime did not faint")
	var woke := await t.until(func() -> bool: return not t.player().is_dead(), 4000.0)
	t.check(woke, "the slime did not wake")
	await t.steps(6)
	t.check(not shell.game_over.is_open(), "the game-over screen showed in the prologue")
	t.near_vec(t.player().get_centre(), (director.get(&"wake") as Node2D).global_position, 6.0, "where the slime woke")
	var back_biter := _enemy(director, &"worm_biter")
	t.check(back_biter != null and not _defeated(back_biter), "the biting worm is not back")
	if back_biter != null:
		t.near_vec(back_biter.get(&"body").global_position, biter_home, 40.0, "the worm is not back at its spot")
	t.check(PrologueState.is_running(run) and not PrologueState.has_beat(run, PrologueState.RESCUED), "the rescue moved on")


func test_one_throw_kills_a_prologue_worm_and_the_rescue_ends(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN, PrologueState.PATH_CLEARED, PrologueState.FIGHT_SEEN])
	var director := _director(t)
	var other := _enemy(director, &"worm_other")
	var biter := _enemy(director, &"worm_biter")
	if not t.check(other != null and biter != null, "the rescue's worms are not there"):
		return
	# Keep the biter out of the way while the throw is checked.
	biter.set_physics_process(false)
	other.set_physics_process(false)
	var pot := (director.get(&"glade_things") as Node2D).get_child(0) as Node2D
	t.teleport_player(pot.global_position + Vector2(0, 70))
	t.player().face(Vector2.UP)
	await t.steps(2)
	t.press(&"eat")
	await t.until(func() -> bool: return not t.player().held().is_empty(), 1500.0)
	t.release(&"eat")
	await t.steps(2)
	t.check(not t.player().held().is_empty(), "nothing in the mouth to throw")
	var at: Vector2 = other.call(&"get_centre")
	t.teleport_player(at + Vector2(0, 110))
	t.player().face(Vector2.UP)
	await t.steps(2)
	t.tap(&"eat")
	var killed := await t.until(func() -> bool: return _defeated(other), 1500.0)
	t.check(killed, "one throw did not kill a prologue worm")
	# The glade's pot comes back.
	var came_back := await t.until(func() -> bool: return _things_standing(director) == _things_total(director), 6000.0)
	t.check(came_back, "a thrown glade pot did not come back")
	biter.set_physics_process(true)
	biter.call(&"take_reaction_damage", 1.0)
	var won := await t.until(func() -> bool: return int(director.get(&"phase")) == 5, 3000.0)
	t.check(won, "the rescue did not end with both worms down")
	t.check(PrologueState.has_beat(run, PrologueState.RESCUED), "the rescue beat")


func test_yoi_teaches_the_spear(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN, PrologueState.PATH_CLEARED, PrologueState.FIGHT_SEEN])
	var director := _director(t)
	t.check(not run.has_learned_ability(String(ShapeDefs.SPEAR)), "the slime knows the Spear before Yoi")
	for property: StringName in [&"worm_biter", &"worm_other"]:
		var enemy := _enemy(director, property)
		if enemy != null:
			enemy.set_physics_process(true)
			enemy.call(&"take_reaction_damage", 1.0)
	var talked := await t.until(func() -> bool: return _box(t) != null and bool(_box(t).call(&"is_open")), 4000.0)
	t.check(talked, "Yoi did not tell his story")
	await _close_dialogues(t, func() -> bool: return int(director.get(&"phase")) == 6, 8000.0)
	t.check(run.has_learned_ability(String(ShapeDefs.SPEAR)), "Yoi did not teach the Spear")
	t.check(PrologueState.has_beat(run, PrologueState.SPEAR), "the Spear beat")
	t.check(not run.session_ability_ids.has(String(ShapeDefs.SPEAR)), "the Spear is only lent")
	var shapes: Variant = t.player().get_shapes()
	t.check(shapes != null and StringName(shapes.call(&"current_shape_id")) == ShapeDefs.SPEAR, "the Spear is not the slime's shape")
	t.equal(int(director.get(&"phase")), 6, "the gate lesson did not follow")


func test_the_gate_opens_only_to_a_spear_thrust_through_the_bars(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN, PrologueState.PATH_CLEARED, PrologueState.FIGHT_SEEN,
		PrologueState.RESCUED])
	var director := _director(t)
	var gate := director.get(&"gate") as Node2D
	t.check(not bool(gate.call(&"is_open")), "the barred gate is open before the Spear")
	# A thrown pot, a roll and a sword hit the bars and the lever: refused.
	var refused: Array = []
	gate.connect(&"refused", func(payload: Dictionary) -> void: refused.append(payload))
	var bars := gate.get(&"bars_area") as Area2D
	var lever := gate.get_node("Lever/LeverArea") as Area2D
	for tags: Array in [["thrown", "clay-pot"], ["roll"], ["weapon"]]:
		_route(t, bars, tags)
		_route(t, lever, tags)
	await t.steps(2)
	t.check(not bool(gate.call(&"is_open")), "something else than the Spear opened the gate")
	t.check(refused.size() >= 3, "the wrong tools were not refused (%d)" % refused.size())
	# The slime cannot walk through the bars.
	t.teleport_player(AT_THE_BARS + Vector2(0, 40))
	t.press(&"move_up")
	await t.sim_wait(900.0)
	t.release(&"move_up")
	t.check(t.player().get_centre().y > 1300.0, "the slime walked through the bars")
	# Yoi's Spear: a thrust through the bars pulls the lever.
	run.learn_ability(String(ShapeDefs.SPEAR))
	(t.player().get_shapes() as Object).call(&"set_current", ShapeDefs.SPEAR)
	t.teleport_player(AT_THE_BARS + Vector2(0, 8))
	t.player().face(Vector2.UP)
	await t.steps(3)
	t.tap(&"attack")
	var opened := await t.until(func() -> bool: return bool(gate.call(&"is_open")), 1500.0)
	t.check(opened, "a Spear thrust through the bars did not open the gate")
	t.check(run.is_gate_unlocked(MAP_ID, "prologue-barred-gate"), "the gate's record is not kept")
	t.check(PrologueState.has_beat(run, PrologueState.GATE_OPEN), "the gate beat")
	await _close_dialogues(t, func() -> bool: return false, 1500.0)
	await t.sim_wait(1200.0)
	t.teleport_player(AT_THE_BARS + Vector2(0, 30))
	t.press(&"move_up")
	await t.until(func() -> bool: return t.player().get_centre().y < BEYOND_THE_GATE.y + 30.0, 3000.0)
	t.release(&"move_up")
	t.check(t.player().get_centre().y < BEYOND_THE_GATE.y + 30.0, "the open gate does not let the slime through")


func test_the_way_out_leads_to_slimeshire_where_plop_meets_the_slime(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN, PrologueState.PATH_CLEARED, PrologueState.FIGHT_SEEN,
		PrologueState.RESCUED, PrologueState.SPEAR, PrologueState.GATE_OPEN])
	run.learn_ability(String(ShapeDefs.SPEAR), true)
	t.teleport_player(EXIT_POINT + Vector2(-40, 0))
	t.press(&"move_right")
	var crossed := await t.until(func() -> bool: return t.in_world("level-1") and t.player() != null, 3000.0)
	t.release(&"move_right")
	t.check(crossed, "the path's end does not lead into Slimeshire")
	if not crossed:
		return
	t.equal(t.world().map_id(), PrologueState.TOWN_MAP_ID, "the path comes out in level-1-c4")
	var meeting := t.world().world_root.get_node_or_null("PrologueMeeting") as Node2D
	if not t.check(meeting != null, "no PrologueMeeting in level-1-c4"):
		return
	var met := await t.until(func() -> bool: return _box(t) != null and bool(_box(t).call(&"is_open")), 3000.0)
	t.check(met, "Plop did not meet the slime")
	var plop := _plop(t)
	if t.check(plop != null, "no Plop in level-1-c4"):
		t.near_vec((plop.get(&"body") as Node2D).global_position, (meeting.get(&"spot") as Node2D).global_position, 4.0, "Plop is not at the town's edge")
	t.check(str(_box(t).call(&"speaker")).contains("Plop"), "the first meeting is not Plop's")
	t.check(not run.can_save(), "saving works before Plop's meeting is over")
	await _close_dialogues(t, func() -> bool: return PrologueState.has_beat(run, PrologueState.DONE), 6000.0)
	t.check(PrologueState.has_beat(run, PrologueState.DONE), "the prologue did not end with Plop's meeting")
	if plop != null:
		var body := plop.get(&"body") as Node2D
		t.near_vec(body.global_position, meeting.get(&"_home_position"), 4.0, "Plop returned to his saved village position")
		t.near(body.modulate.a, 1.0, 0.01, "Plop faded back in")
		t.equal(t.world().elevation.level_of(body), 0, "Plop returned to the town's ground level")
	t.equal(int(run.inventory.get("max_slots", 0)), 10, "Plop's satchel has 10 pockets")
	t.check(run.can_save(), "saving does not work after the prologue")
	t.check(ReworkMode.is_on(), "Slimeshire after the prologue is not in the shapes mode")
	t.check(run.has_learned_ability(String(ShapeDefs.SPEAR)), "the Spear did not come along")
	# The forest path leads back to the Wellspring, which stands as after the prologue.
	t.teleport_player(Vector2(60, 1696))
	t.press(&"move_left")
	var back := await t.until(func() -> bool: return t.in_world("west-village") and t.player() != null, 3000.0)
	t.release(&"move_left")
	t.check(back, "the forest path does not lead back to the Wellspring")
	await t.steps(3)
	var director := _director(t)
	t.check(director != null and director.get(&"yoi") == null, "Yoi is still in the glade after the prologue")
	var gate := director.get(&"gate") as Node2D if director != null else null
	t.check(gate != null and bool(gate.call(&"is_open")), "the gate is shut after the prologue")


func test_quitting_in_the_prologue_starts_it_again_from_the_birth(t: TestContext) -> void:
	var run := Services.run()
	await _enter(t, [PrologueState.BORN, PrologueState.PATH_CLEARED, PrologueState.FIGHT_SEEN])
	var shell := Services.shell()
	run.autosave_enabled = true
	var changes: Array[String] = []
	var change_before: Callable = shell.change_scene
	shell.change_scene = func(path: String) -> void: changes.append(path)
	shell.quit_to_title()
	await t.until(func() -> bool: return not changes.is_empty(), 1500.0, 3000.0)
	shell.change_scene = change_before
	run.autosave_enabled = false
	t.equal(changes, [ShellScript.TITLE_SCENE] as Array[String], "Quit to Title")
	t.check(not run.has_save(0), "quitting in the prologue wrote a save")
	# The title has nothing to continue; New Game plays the prologue again from the birth.
	_park_shell(t)
	t.main.remove_from_group(ShellScript.WORLD_MAIN_GROUP)
	var title := (load(TITLE_SCENE) as PackedScene).instantiate() as TitleScript
	title.backdrop_enabled = false
	title.skip_for_launch_options = false
	title.change_scene = func(_path: String) -> void: pass
	t.tree.root.add_child(title)
	await t.steps(1)
	t.check(not title.continue_button.visible, "Continue offers a save of the prologue")
	title.new_game_button.pressed.emit()
	await t.steps(1)
	t.check(PrologueState.is_running(run) and not PrologueState.has_beat(run, PrologueState.BORN), "New Game does not start the prologue from the birth")
	t.equal(str(run.peek_navigation().get("entry_marker", "")), PrologueState.BIRTH_MARKER, "New Game does not go to the birth spot")
	run.consume_navigation()
	title.queue_free()
	await t.steps(1)
	t.main.add_to_group(ShellScript.WORLD_MAIN_GROUP)
	_unpark_shell(t)
	shell.call(&"_end_quit")


# --- helpers ----------------------------------------------------------------------------------

## Starts the prologue on the run with `beats` already played and builds the Wellspring's chunk at
## the birth spot (the slime is placed where the beats leave it by the test).
func _enter(t: TestContext, beats: Array) -> void:
	var run := Services.run()
	PrologueState.begin(run)
	run.consume_navigation()
	for flag: Variant in beats:
		run.set_flag(str(flag))
	t.main.call(&"travel_to", PrologueState.START_MAP_ID, "", "", PrologueState.BIRTH_MARKER)
	await t.until(func() -> bool: return _director(t) != null and bool(_director(t).get(&"_started")) \
		and t.player() != null and not bool(t.main.call(&"is_transitioning")), 3000.0)
	await t.steps(2)


func _director(t: TestContext) -> Node:
	var world := t.world()
	if world == null or world.world_root == null or not is_instance_valid(world.world_root):
		return null
	return world.world_root.get_node_or_null(DIRECTOR)


func _enemy(director: Node, property: StringName) -> Node:
	var placed: Variant = director.get(property)
	if not is_instance_valid(placed) or not placed is Node:
		return null
	return (placed as Node).call(&"get_enemy")


static func _defeated(enemy: Node) -> bool:
	return enemy == null or not is_instance_valid(enemy) or bool(enemy.call(&"is_defeated"))


func _box(t: TestContext) -> Node:
	return t.tree.get_first_node_in_group(&"dialogue_box")


## Closes every conversation that opens (finished) until `done` or `real_ms` of real time.
func _close_dialogues(t: TestContext, done: Callable, real_ms: float) -> void:
	var started := float(Time.get_ticks_msec())
	while float(Time.get_ticks_msec()) - started < real_ms:
		if bool(done.call()):
			return
		var box := _box(t)
		if box != null and bool(box.call(&"is_open")):
			box.call(&"close", true)
		await t.tree.physics_frame


func _things_total(director: Node) -> int:
	return (director.get(&"_glade_spots") as Array).size()


func _things_standing(director: Node) -> int:
	var standing := 0
	for spot: Dictionary in director.get(&"_glade_spots"):
		var node: Variant = spot["node"]
		if is_instance_valid(node) and node is Node and not (node as Node).is_queued_for_deletion():
			standing += 1
	return standing


func _plop(t: TestContext) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.get(&"npc_definition_id")) == "village-elder-plop":
			return node
	return null


func _secret_cue(t: TestContext) -> Node:
	return t.tree.root.find_child("SecretFound", true, false)


## A routed hit on `area` with `tags` (what a throw, a roll or a weapon sends).
func _route(t: TestContext, area: Area2D, tags: Array) -> void:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-" + str(tags[0]), "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 20.0,
		"effects": [], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()


## A router hit of `damage` on the slime (what an enemy's strike commits).
func _hit(player: Node, damage: int) -> void:
	var commit := {"result": {"actual_damage": damage, "defeated": true, "applied_effects": []},
		"request": {"impact": {"knock": Vector2.RIGHT}}, "simulation_time": Services.now_ms()}
	player.commit_damage(commit)
	player.publish_damage_feedback(commit)


## The title makes its own Shell while the registered one is out of the tree (as test_shell.gd does).
func _park_shell(t: TestContext) -> void:
	var registered := t.tree.root.get_node_or_null(^"Shell")
	if registered == null or _parked_shell != null:
		return
	_parked_shell = registered
	_parked_index = registered.get_index()
	t.tree.root.remove_child(registered)


func _unpark_shell(t: TestContext) -> void:
	if _parked_shell == null:
		return
	t.tree.root.add_child(_parked_shell)
	t.tree.root.move_child(_parked_shell, mini(_parked_index, t.tree.root.get_child_count() - 1))
	_parked_shell = null
