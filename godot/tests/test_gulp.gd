extends RefCounted
## The Gulp in the playground (redesigned 2026-10-08; GAME_GUIDELINES "Signature Mechanic: Gulp";
## game/player/gulp/), as the body-shapes mode plays it (on in every world since 2026-10-24; its Q
## table: BODY_SHAPES.md "Mouth", game/player/gulp/mouth_hold.gd). A Q press with an empty mouth
## sucks in an essence, a rock, a puffball or a pinecone (a half-second burst that ends on the catch);
## the slime holds it (no attacks), throws a thing with Q (it breaks, hitting what it meets), spits an
## essence out whole with a tap of Q, or swallows it with a hold of Q (`gulp.rework.swallowHoldMs`;
## the Swallow key does nothing in the mode) to take its form. A hit pops the form out as a
## short-lived essence; Q held with an empty mouth in a form (`spitHoldMs`) spits the form out whole.
## Interact puts an essence in the bag; the bag's Use puts it back in the mouth. The forms' rules:
## Stone walks slower and ignores knockback; since roadmap 7.8 the Heavy skin, not the Stone form,
## holds the heavy plate (1344, 780) that opens `playground-heavy-gate`, and the Squash Slam (a box
## ability, used with F: `ability_use`) with it breaks the cracked ground (1600, 1040, reach 52).
##
## Playground places: the old stone spot is a stone essence at (1120, 800); the gulp yard has rocks
## at (1000, 1180), (1060, 1230), (960, 1260), puffballs at (1160, 1180) and (1140, 1270), a
## pinecone at (1210, 1225), a stone essence at (1300, 1150), a silk one at (1360, 1200) and a swim
## one at (1300, 1250) (away from the spawn camp's chest, whose Interact wins); training dummies
## stand at (1480, 1400) and on.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const GulpForms := preload("res://game/player/gulp/gulp_forms.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")

const MAP_ID := "playground"
const STONE_ESSENCE := Vector2(1120.0, 800.0)
const YARD_ROCK := Vector2(1000.0, 1180.0)
const YARD_PUFFBALL := Vector2(1160.0, 1180.0)
const YARD_SILK := Vector2(1360.0, 1200.0)
const DUMMY := Vector2(1480.0, 1400.0)
const HEAVY_PLATE := Vector2(1344.0, 780.0)
const HEAVY_GATE := "playground-heavy-gate"
const CRACKED := Vector2(1600.0, 1040.0)
const CRACK_FLAG := "cracked.playground-sinkhole"
## The slime's centre sits this far below a thing to suck it in from the south, facing up.
const BELOW := Vector2(0.0, 70.0)
## Open grass at the player spawn (the shapes testbed's ground).
const OPEN := Vector2(1280.0, 1536.0)


func test_suck_an_essence_and_swallow_it(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("swallow", true)
	await _suck_from_below(t, STONE_ESSENCE)
	t.equal(player.held(), {"kind": "essence", "essence": "stone"}, "the stone essence is in the mouth")
	t.check(_essence_near(t, STONE_ESSENCE) == null, "the sucked essence left the world")
	# The Swallow key does nothing in the body-shapes mode: Q held swallows.
	t.tap(&"swallow")
	await t.steps(3)
	t.equal(player.current_form_id(), &"", "the Swallow key swallowed")
	t.press(&"eat")
	var pressed := t.now()
	await t.until(func() -> bool: return player.current_form_id() == GulpForms.HEAVY, _gulp_rework("swallowHoldMs") + 300.0)
	t.release(&"eat")
	t.equal(player.current_form_id(), GulpForms.HEAVY, "the Stone form")
	t.between(t.now() - pressed, _gulp_rework("swallowHoldMs"), _gulp_rework("swallowHoldMs") + 3.0 * TestContext.STEP_MS,
		"the hold of Q that swallows (ms)")
	t.equal(player.held(), {}, "the mouth is empty after swallowing")
	# Since roadmap 7.8 the Heavy skin presses plates, not the Stone form (docs/godot/SKINS.md).
	t.check(not player.presses_plates(), "the Stone form still presses plates")
	t.equal(player.form_remaining_ms(), 0.0, "no timer")


func test_holding_blocks_attacks_and_q_throws(t: TestContext) -> void:
	var player := t.player()
	await _suck_from_below(t, YARD_ROCK)
	t.equal(str(player.held().get("kind", "")), "rock", "holding the rock")
	t.tap(&"attack")
	await t.steps(4)
	t.check(not player.get_combat().is_attacking(), "the slime attacked while holding")
	Services.run().learn_ability("swallow", true)
	t.tap(&"swallow")
	await t.steps(3)
	t.equal(str(player.held().get("kind", "")), "rock", "a rock is too big to swallow")
	t.tap(&"eat")
	await t.steps(2)
	t.equal(player.held(), {}, "thrown")
	t.check(not _thrown(t).is_empty(), "a thrown rock flies")
	await t.until(func() -> bool: return _thrown(t).is_empty(), 1500.0)
	t.check(_thrown(t).is_empty(), "the rock broke")


## Q with an essence held spits it out whole in front, where it stays (owner, 2026-10-09: essences
## are never thrown); the full slime walks at the held weight's `holdingSpeed` (an essence is light:
## `gulp.throwCombat.weights.light.holdingSpeed`; the throw rules are always on since 2026-11-25).
func test_q_spits_an_essence_out_whole_and_a_full_slime_walks_slower(t: TestContext) -> void:
	var player := t.player()
	await _suck_from_below(t, YARD_SILK)
	t.equal(player.held(), {"kind": "essence", "essence": "silk"}, "holding the silk essence")
	# The walk on the open grass of the spawn: east of the silk essence the playground's repaint put
	# a door down (`down-door`, (1400, 1300)), whose travel would hold the slime.
	t.check(not player.is_movement_suppressed(), "the suck held the slime still")
	t.teleport_player(OPEN)
	await t.steps(2)
	t.press(&"move_right")
	await t.steps(8)
	var holding := ThrowMode.weight_number(ThrowMode.weight_of_held(player.held()), "holdingSpeed",
		Services.constants().number("gulp.holdingSpeedMultiplier"))
	t.near(t.player_body().velocity.length(), _walk_speed() * holding, 0.5,
		"the full slime's walking speed")
	t.release(&"move_right")
	await t.steps(2)
	player.face(Vector2.UP)
	t.tap(&"eat")
	await t.steps(2)
	t.equal(player.held(), {}, "spat out")
	t.check(_thrown(t).is_empty(), "the essence flew like a thrown thing")
	var spat := _essence_of(t, "silk")
	if t.check(spat != null, "no silk essence lies in front of the slime"):
		t.equal(float(spat.get(&"fade_ms")), 0.0, "a spat essence stays")


## A puffball is a sleep throw (the throw rules, always on since 2026-11-25): it strikes the dummy once
## for no damage (`gulp.throwCombat.effects.sleep.damageScale` 0).
func test_a_thrown_puffball_hits_a_dummy(t: TestContext) -> void:
	var player := t.player()
	await _suck_from_below(t, YARD_PUFFBALL)
	t.equal(str(player.held().get("kind", "")), "puffball", "holding the puffball")
	var dummy := _script_near(t, &"hit", DUMMY)
	if not t.check(dummy != null, "no training dummy"):
		return
	var hits: Array = []
	dummy.hit.connect(func(payload: Dictionary) -> void: hits.append(payload))
	t.teleport_player(DUMMY + Vector2(0.0, 150.0))
	player.face(Vector2.UP)
	await t.steps(2)
	t.tap(&"eat")
	await t.until(func() -> bool: return not hits.is_empty(), 1500.0)
	t.equal(hits.size(), 1, "the dummy took one hit")
	if not hits.is_empty():
		# The throw's base damage x its material x its weight x its effect (sleep: x 0).
		var material := LiftableScript.material_of("puffball")
		var by_material := float(Services.constants().dictionary("gulp.throwDamageByMaterial").get(material, 1.0))
		var effect := ThrowMode.effect_of("puffball", material)
		t.equal(effect, ThrowMode.SLEEP, "a puffball's effect")
		var expected := ThrowFeel.base_damage() * by_material * ThrowMode.weight_number(ThrowMode.weight_of("puffball"), "damageScale") \
			* float(ThrowMode.effect_row(effect).get("damageScale", 1.0))
		t.near(float(hits[0]["damage"]), expected, 0.01, "the throw's damage")


func test_a_hit_pops_the_form_and_drops_the_held_thing(t: TestContext) -> void:
	var player := t.player()
	t.teleport_player(Vector2(1280.0, 1536.0))
	await t.steps(2)
	t.equal(player.get_gulp().swallow("stone-essence"), "started", "Stone")
	t.check(player.take_into_mouth("silk-essence"), "a silk essence into the mouth")
	_hit(player, 5)
	await t.steps(2)
	t.equal(player.current_form_id(), &"", "the hit popped the form")
	t.equal(player.held(), {}, "the hit made the slime drop what it held")
	var stone := _essence_of(t, "stone")
	var silk := _essence_of(t, "silk")
	t.check(stone != null, "the popped stone essence lies beside the slime")
	t.check(silk != null, "the dropped silk essence lies beside the slime")
	if stone != null:
		t.near(float(stone.get(&"fade_ms")), Services.constants().number("gulp.popGrabMs"), 0.01, "a popped essence fades soon")
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.01, "the pop took the knockback")


func test_q_held_with_nothing_held_spits_the_form_out(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("swallow", true)
	t.teleport_player(Vector2(1280.0, 1536.0))
	await t.steps(2)
	player.get_gulp().swallow("silk-essence")
	t.press(&"eat")
	await t.until(func() -> bool: return player.current_form_id() == &"", _gulp_rework("spitHoldMs") + 300.0)
	t.release(&"eat")
	t.equal(player.current_form_id(), &"", "spat out")
	var silk := _essence_of(t, "silk")
	t.check(silk != null and float(silk.get(&"fade_ms")) == 0.0, "the spat essence lies whole and stays")
	await t.sim_wait(Services.constants().number("gulp.popGrabMs") + 500.0)
	t.check(is_instance_valid(silk) and silk.is_inside_tree(), "the spat essence is still there")


func test_interact_puts_an_essence_in_the_bag_and_use_puts_it_in_the_mouth(t: TestContext) -> void:
	var player := t.player()
	var run := Services.run()
	var before := run.item_count("silk-essence")
	t.teleport_player(YARD_SILK + Vector2(0.0, 30.0))
	await t.steps(3)
	t.tap(&"interact")
	await t.until(func() -> bool: return run.item_count("silk-essence") > before, 500.0)
	t.equal(run.item_count("silk-essence"), before + 1, "picked up into the bag")
	await t.steps(2)
	t.check(_essence_near(t, YARD_SILK) == null, "the picked-up essence left the world")
	var actions := t.tree.get_first_node_in_group(&"inventory_actions")
	actions.call(&"use_item", "silk-essence")
	t.equal(player.held(), {"kind": "essence", "essence": "silk"}, "Use put it in the mouth")
	t.equal(run.item_count("silk-essence"), before, "taken from the bag")
	actions.call(&"use_item", "silk-essence")
	t.equal(run.item_count("silk-essence"), before, "a full mouth leaves the bag alone")


func test_form_and_held_go_through_doors_and_saves(t: TestContext) -> void:
	var player := t.player()
	player.get_gulp().swallow("stone-essence")
	player.take_into_mouth("silk-essence")
	var snapshot := player.run_snapshot()
	t.equal(snapshot.get("gulp_form"), "heavy", "the snapshot keeps the form")
	t.equal(snapshot.get("held"), {"kind": "essence", "essence": "silk"}, "the snapshot keeps the held essence")
	player.get_gulp().clear()
	player.get_mouth().clear()
	player.restore_run_state(snapshot)
	t.equal(player.current_form_id(), GulpForms.HEAVY, "the form came back")
	t.equal(player.held(), {"kind": "essence", "essence": "silk"}, "the held essence came back")


func test_stone_walks_slower_and_ignores_knockback(t: TestContext) -> void:
	var player := t.player()
	player.get_gulp().swallow("stone-essence")
	t.teleport_player(Vector2(1280.0, 1536.0))
	t.press(&"move_right")
	await t.steps(4)
	var stone_walk := _walk_speed() * float(GulpForms.by_id(GulpForms.HEAVY).get("speed", 1.0))
	t.near(t.player_body().velocity.x, stone_walk, 0.01, "Stone walk speed")
	t.release_all()
	await t.steps(2)
	player.apply_knockback(Vector2.RIGHT, 260.0, 160.0)
	await t.steps(1)
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.01, "velocity after a knockback in Stone")
	t.check(not player.is_movement_suppressed(), "Stone was knocked back")


## The Heavy skin (SkinState, roadmap 7.8) holds the pressure plate down; the Stone form alone does not.
func test_the_heavy_skin_presses_the_plate_and_opens_the_gate(t: TestContext) -> void:
	t.player().get_gulp().swallow("stone-essence")
	var plate := _script_near(t, &"pressed", HEAVY_PLATE)
	var gate := _gate(t, HEAVY_GATE)
	if not t.check(plate != null and gate != null, "no heavy plate or gate"):
		return
	var presses: Array = []
	plate.pressed.connect(func(payload: Dictionary) -> void: presses.append(payload))
	t.teleport_player(HEAVY_PLATE + Vector2(0.0, 20.0))
	await t.steps(3)
	t.equal(presses, [], "the Stone form pressed the plate")
	SkinState.lend(SkinState.HEAVY)
	await t.steps(3)
	t.equal(presses, [{"plateId": "playground-heavy-plate"}], "plate presses")
	t.check(gate.is_open(), "the heavy gate did not open")
	t.equal(plate.visual.frame, 7, "pressed plate frame")


func test_light_slime_does_not_press(t: TestContext) -> void:
	var plate := _script_near(t, &"pressed", HEAVY_PLATE)
	if not t.check(plate != null, "no heavy plate"):
		return
	t.teleport_player(HEAVY_PLATE + Vector2(0.0, 20.0))
	await t.steps(3)
	t.check(not plate.is_down(), "a slime without the Heavy skin pressed the plate")


func test_a_heavy_slam_breaks_cracked_ground(t: TestContext) -> void:
	var run := Services.run()
	if not _choose_the_slam(t):
		return
	SkinState.lend(SkinState.HEAVY)
	t.teleport_player(CRACKED + Vector2(0.0, 20.0))
	await t.steps(3)
	t.check(not run.has_flag(CRACK_FLAG), "standing with the Heavy skin cracked the ground")
	t.tap(&"ability_use")
	await t.until(func() -> bool: return run.has_flag(CRACK_FLAG), 2000.0)
	t.check(run.has_flag(CRACK_FLAG), "a Squash Slam with the Heavy skin did not crack the ground")


func test_slam_without_the_heavy_skin_leaves_cracked_ground(t: TestContext) -> void:
	var run := Services.run()
	if not _choose_the_slam(t):
		return
	t.teleport_player(CRACKED + Vector2(0.0, 20.0))
	await t.steps(3)
	t.tap(&"ability_use")
	await t.sim_wait(1500.0)
	t.check(t.player().get_energy() < t.player().get_max_energy(), "the slam did not run")
	t.check(not run.has_flag(CRACK_FLAG), "a slam without the Heavy skin cracked the ground")


func test_swapping_essences_pops_the_old_form(t: TestContext) -> void:
	var player := t.player()
	player.get_gulp().swallow("stone-essence")
	t.equal(player.get_gulp().swallow("silk-essence"), "switched", "Silk replaces Stone")
	await t.steps(2)
	# Since roadmap 7.8 the Silk skin crosses webs, not the Silk form (docs/godot/SKINS.md).
	t.check(player.is_sticky_form() and not player.crosses_webs(), "the Silk form still crosses webs")
	t.check(_essence_of(t, "stone") != null, "the old stone essence popped out")


## The form skin (form_skin.gdshader on the Visual): Stone paints cobbles (skin 1), Silk (skin 2),
## no form clears it; the tint fallback stays off.
func test_form_skin_follows_the_form(t: TestContext) -> void:
	var player := t.player()
	var visual := player.visual as CanvasItem
	var skin_material := visual.material as ShaderMaterial
	if not t.check(skin_material != null, "the Visual has no skin material"):
		return
	player.get_gulp().swallow("stone-essence")
	t.equal(int(skin_material.get_shader_parameter(&"skin")), 1, "Stone's skin")
	t.equal(visual.self_modulate, Color.WHITE, "no tint over the skin")
	player.get_gulp().swallow("silk-essence")
	t.equal(int(skin_material.get_shader_parameter(&"skin")), 2, "Silk's skin")
	player.get_gulp().spit_out()
	t.equal(int(skin_material.get_shader_parameter(&"skin")), 0, "no skin after the form")


# --- helpers ----------------------------------------------------------------------------------

## Stands the slime south of `at`, facing it, and holds Q until something is in the mouth and the
## suck burst is over (it roots the slime and takes no Q press while it runs: mouth_hold.gd).
func _suck_from_below(t: TestContext, at: Vector2) -> void:
	t.teleport_player(at + BELOW)
	t.player().face(Vector2.UP)
	await t.steps(2)
	t.press(&"eat")
	await t.until(func() -> bool: return not t.player().held().is_empty(), 1000.0)
	t.release(&"eat")
	await t.until(func() -> bool: return not t.player().get_mouth_hold().roots_player(), 1000.0)
	await t.steps(1)


## The Squash Slam learned and chosen in the Ability Box (its key in the mode is `ability_use`).
func _choose_the_slam(t: TestContext) -> bool:
	Services.run().learn_session_ability(String(AbilityDefinitions.SQUASH_SLAM))
	return t.check(AbilityBox.select(t.player(), AbilityDefinitions.SQUASH_SLAM), "could not choose the Squash Slam in the Ability Box")


## Player spec 4.3: the walk is `character.player.movement.baseSpeed` under `movementSpeedCap`.
static func _walk_speed() -> float:
	var constants := Services.constants()
	return minf(constants.number("character.player.movement.movementSpeedCap"),
		constants.number("character.player.movement.baseSpeed"))


static func _gulp_rework(name: String) -> float:
	return Services.constants().number("gulp.rework." + name)


## A router hit of `damage` on the slime (what an enemy's strike commits), with a knockback.
func _hit(player: Node, damage: int) -> void:
	var commit := {"result": {"actual_damage": damage, "defeated": false,
		"applied_effects": [{"effect_id": "knockback", "potency": 300.0}]},
		"request": {"impact": {"knock": Vector2.RIGHT}}, "simulation_time": Services.now_ms()}
	player.commit_damage(commit)
	player.publish_damage_feedback(commit)


func _thrown(t: TestContext) -> Array:
	return t.world().entities_root().find_children("Thrown*", "Node2D", false, false)


func _essence_near(t: TestContext, at: Vector2) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"essence"):
		if (node.call(&"origin") as Vector2).distance_to(at) < 8.0:
			return node
	return null


func _essence_of(t: TestContext, kind: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"essence"):
		if str(node.get(&"essence")) == kind and float(node.get(&"fade_ms")) >= 0.0 and _spawned(node):
			return node
	return null


## Spawned at run time (not one of the playground's placed essences, which have an instance id).
func _spawned(node: Node) -> bool:
	return not (node.get_parent() as Node).has_meta(&"instance_id")


## The script with signal `signal_name` whose parent is nearest `at`.
func _script_near(t: TestContext, signal_name: StringName, at: Vector2) -> Node:
	var best: Node = null
	var best_distance := INF
	for node: Node in t.world().world_root.find_children("*", "Node", true, false):
		if not node.has_signal(signal_name) or not node.get_parent() is Node2D:
			continue
		var distance := (node.get_parent() as Node2D).global_position.distance_to(at)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best if best_distance < 64.0 else null


func _gate(t: TestContext, gate_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"gate"):
		if str(node.get(&"gate_id")) == gate_id:
			return node
	return null
