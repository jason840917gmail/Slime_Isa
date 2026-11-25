extends RefCounted
## The dungeon mechanisms (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the runaway
## cart"), in their lab (game/dev/mechanisms/mechanism-lab.tscn, built by
## tools/build_mechanism_lab.gd): the knock target (a thrown hit, an arrow and a blast knock it;
## the Spear only knocks on it; knocked, it sets its targets off each time and hangs slack until its
## mechanism rearms it, or by itself without one), the ram (its cycle; the slime shoved across its
## lane, an enemy and a heavy one struck with true damage, a sleeping statue struck but rooted, a
## hooked node on its lane; the bricked arch it bursts for good) and the runaway cart (its roll; the
## rail gate it smashes and runs through; the things on its rails; hauled back, or spent for good).
##
## The lab (cells of 64 units): lane A the ram `a-ram` at (576, 768) aimed north at `a-arch`
## (576, 512), its target `a-target` (160, 768) across the pit; lane B the ram `b-ram` aimed east;
## lane C the cart `c-cart` (it stays where it ends) with `c-gate` on its line and `c-cart-2` (hauled
## back) aimed west.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const HookProbe := preload("res://tests/lib/mechanism_hook_probe.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")

const LAB := "mechanism-lab"
const GUARD_SCENE_ID := "character.thorn-guard"
const PRISM_EYE_SCENE_ID := "character.prism-eye"
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
## The cart's script by its path (a new class: the class cache may not know `RamCart` yet).
const RamCartScript := preload("res://game/crystal_mine/ram_cart.gd")
const TARGET_SCENE := "res://game/scenes/objects/dungeon/knock-target.tscn"
## game/combat/reactions/hit_reaction.gd IMPACT_EFFECT_ID.
const IMPACT_EFFECT := "impact"


# --- the knock target -------------------------------------------------------------------------------

func test_a_thrown_hit_knocks_the_target_and_lets_its_ram_go(t: TestContext) -> void:
	await _enter_lab(t)
	var target := _node(t, "b-target")
	var ram := _node(t, "b-ram")
	var knocks: Array = []
	target.connect(&"knocked", func(payload: Dictionary) -> void: knocks.append(payload))
	t.check(bool(target.call(&"is_armed")), "the target starts armed")
	t.check(bool(ram.call(&"is_ready")), "the ram starts ready")
	_route(t, target.get(&"damage_area"), ["thrown", "clay-pot"])
	t.equal(knocks.size(), 1, "knocks after a thrown hit")
	t.equal(str(target.call(&"state_name")), "spin", "the target after a thrown hit")
	t.equal(str(ram.call(&"state_name")), "windup", "the ram after its target was knocked")
	# Slack: further hits only rock it, and set nothing off again.
	await t.sim_wait(DungeonState.number("knockTarget.spinMs", 400.0) + 60.0)
	t.equal(str(target.call(&"state_name")), "slack", "the target after its spin")
	_route(t, target.get(&"damage_area"), ["thrown", "clay-pot"])
	t.equal(knocks.size(), 1, "knocks after a hit on a slack target")


func test_the_spear_and_a_push_only_knock_on_the_target(t: TestContext) -> void:
	await _enter_lab(t)
	var target := _node(t, "b-target")
	var ram := _node(t, "b-ram")
	for tags: Array in [["weapon", "spear"], ["roll"], ["slam"]]:
		var result := _route(t, target.get(&"damage_area"), tags)
		t.equal(str(result.get("status", "")), "rejected", "a %s hit on the target" % [tags])
		t.equal(str(result.get("reason", "")), "immune", "the refusal of a %s hit" % [tags])
	t.check(bool(target.call(&"is_armed")), "the target stays armed after hits that cannot knock it")
	t.check(bool(ram.call(&"is_ready")), "the ram stays ready")
	# The slime's body on its post.
	var foot := (target as Node2D).global_position
	t.teleport_player(foot + Vector2(40.0, -24.0))
	await _clear_enemies(t)
	await _walk(t, &"move_left", 500.0)
	t.check(bool(target.call(&"is_armed")), "the target stays armed after a push")
	t.check(bool(ram.call(&"is_ready")), "the ram stays ready after a push")


func test_an_arrow_and_a_blast_knock_the_target(t: TestContext) -> void:
	await _enter_lab(t)
	var target := _node(t, "b-target")
	t.check(target.is_in_group(&"bow_targets"), "the target is a Bow target")
	t.check(target.is_in_group(&"blast_targets"), "the target is a blast target")
	t.check(bool(target.call(&"on_arrow_hit", {})), "an arrow is spent on the target")
	t.equal(str(target.call(&"state_name")), "spin", "the target after an arrow")
	var other := _node(t, "a-target")
	t.check(bool(other.call(&"receive_blast", {})), "a blast reaches the target")
	t.equal(str(other.call(&"state_name")), "spin", "the target after a blast")


func test_a_target_without_a_mechanism_rearms_by_itself(t: TestContext) -> void:
	await _enter_lab(t)
	var target := (load(TARGET_SCENE) as PackedScene).instantiate() as Node2D
	target.position = Vector2(700.0, 1000.0)
	_node(t, "Objects").add_child(target)
	await t.steps(3)
	var rearms: Array = []
	target.connect(&"rearmed", func(payload: Dictionary) -> void: rearms.append(payload))
	target.call(&"strike")
	t.check(not bool(target.call(&"is_armed")), "a knocked target is not armed")
	var rearm_ms := DungeonState.number("knockTarget.rearmMs", 3000.0)
	await t.sim_wait(rearm_ms - 300.0)
	t.check(not bool(target.call(&"is_armed")), "it rearmed before its time")
	await t.sim_wait(300.0 + DungeonState.number("knockTarget.rearmSnapMs", 180.0) + 100.0)
	t.check(bool(target.call(&"is_armed")), "it did not rearm by itself")
	t.equal(rearms.size(), 1, "rearms")
	target.queue_free()


# --- the ram ----------------------------------------------------------------------------------------

func test_the_ram_runs_its_cycle_and_rearms_its_target(t: TestContext) -> void:
	await _enter_lab(t)
	var target := _node(t, "b-target")
	var ram := _node(t, "b-ram")
	await _clear_enemies(t)
	var started := t.now()
	target.call(&"strike")
	t.equal(str(ram.call(&"state_name")), "windup", "the ram let go")
	# It cannot be let go again until it is ready.
	ram.call(&"trigger")
	t.equal(str(ram.call(&"state_name")), "windup", "a second trigger during the shudder")
	t.check(await t.until(func() -> bool: return str(ram.call(&"state_name")) == "swing", 1000.0), "the swing never started")
	t.near(t.now() - started, DungeonState.number("ram.windupMs", 350.0), 40.0, "the shudder's length")
	t.check(await t.until(func() -> bool: return str(ram.call(&"state_name")) == "hold", 1000.0), "the swing never ended")
	t.near(t.now() - started, DungeonState.number("ram.windupMs", 350.0) + DungeonState.number("ram.swingMs", 420.0), 50.0, "the swing's end")
	t.check(await t.until(func() -> bool: return str(ram.call(&"state_name")) == "rewind", 2000.0), "the winch never started")
	t.check(not bool(target.call(&"is_armed")), "the target rearmed while the ram was away")
	var total := DungeonState.number("ram.windupMs", 350.0) + DungeonState.number("ram.swingMs", 420.0) \
		+ DungeonState.number("ram.holdMs", 150.0) + DungeonState.number("ram.returnMs", 600.0) + DungeonState.number("ram.rewindMs", 8000.0)
	t.check(await t.until(func() -> bool: return bool(ram.call(&"is_ready")), 12000.0, 30000.0), "the ram never came back")
	t.near(t.now() - started, total, 120.0, "the whole cycle")
	await t.sim_wait(DungeonState.number("knockTarget.rearmSnapMs", 180.0) + 100.0)
	t.check(bool(target.call(&"is_armed")), "the ram did not rearm its target")


func test_the_ram_shoves_a_slime_on_its_middle_line_across_the_lane(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	await _clear_enemies(t)
	# on the middle line, halfway down the lane: it goes down the screen (the lane runs east)
	await _shove_test(t, ram, Vector2(160.0, 0.0), 1.0)


func test_the_ram_shoves_a_slime_near_its_far_end_to_its_own_side(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	await _clear_enemies(t)
	# north of the middle line, near the far end: it goes up the screen
	await _shove_test(t, ram, Vector2(290.0, -24.0), -1.0)


## The slime's feet at `spot` from lane B's ram (its lane runs east, 128 wide); one swing. It takes
## `slimeDamage`, is never carried down the lane, and is clear of the lane on the side `side` (1 down
## the screen, -1 up) by the time the head reaches where it stood.
func _shove_test(t: TestContext, ram: Node2D, spot: Vector2, side: float) -> void:
	var body := t.player_body()
	body.velocity = Vector2.ZERO
	body.global_position = ram.global_position + spot
	body.reset_physics_interpolation()
	await t.steps(3)
	var hp := t.player().get_hp()
	var from := body.global_position
	var half := float(ram.get(&"width")) * 0.5
	ram.call(&"trigger")
	# a lambda captures locals by value: the reading goes into a dictionary
	var seen := {"off": -999.0}
	t.check(await t.until(func() -> bool:
		var head: Vector2 = ram.call(&"head_point")
		if float(seen["off"]) < -900.0 and head.x >= from.x:
			seen["off"] = (body.global_position.y - ram.global_position.y) * side - half
		return str(ram.call(&"state_name")) == "return", 2000.0), "the ram never swung back")
	var off_when_passed := float(seen["off"])
	t.equal(hp - t.player().get_hp(), int(DungeonState.number("ram.slimeDamage", 20.0)), "the ram's damage to the slime")
	var moved := body.global_position - from
	t.check(absf(moved.x) < 24.0, "the slime was carried down the lane (moved %s)" % moved)
	t.check(moved.y * side > 0.0, "the slime was shoved to the wrong side (moved %s)" % moved)
	t.check(off_when_passed > 0.0, "the slime was still in the lane when the head reached it (%s units outside)" % off_when_passed)


func test_the_ram_leaves_a_slime_beside_its_lane_alone(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	t.teleport_player(ram.global_position + Vector2(120.0, 130.0))
	await _clear_enemies(t)
	var hp := t.player().get_hp()
	ram.call(&"trigger")
	await t.until(func() -> bool: return str(ram.call(&"state_name")) == "return", 2000.0)
	t.equal(t.player().get_hp(), hp, "the slime's health beside the lane")


func test_the_ram_strikes_an_enemy_and_knocks_it_down_the_lane(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	t.teleport_player(ram.global_position + Vector2(-60.0, 200.0))
	await _clear_enemies(t)
	var worm := t.spawn_worm(Vector2(300.0, 0.0), true)
	if worm == null:
		return
	t.set_enemy_health(worm, 200.0)
	t.place_worm(worm, ram.global_position + Vector2(150.0, -22.0))
	await t.steps(2)
	var from := worm.get_centre()
	ram.call(&"trigger")
	await t.until(func() -> bool: return str(ram.call(&"state_name")) == "return", 2000.0)
	await t.sim_wait(400.0)
	# a mechanism's blow is true damage: `ram.damage` whole
	t.equal(200.0 - float(worm.get(&"_hp")), DungeonState.number("ram.damage", 60.0), "the ram's damage to an enemy")
	t.check(worm.get_centre().x - from.x > 30.0, "the enemy was not knocked down the lane (moved %s)" % (worm.get_centre() - from))


func test_the_ram_moves_a_heavy_enemy_two_cells_and_deals_true_damage(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	t.teleport_player(ram.global_position + Vector2(-60.0, 200.0))
	await _clear_enemies(t)
	var guard := _spawn_guard(t, ram.global_position + Vector2(380.0, 200.0))
	if guard == null:
		return
	# awake and marching (asleep it is a rooted statue: the next test)
	guard.call(&"wake", Services.now_ms())
	# its wake (`wakeMs`, 700 in enemy-types.json) and a step into its march
	await t.sim_wait(1000.0)
	t.equal(str(guard.call(&"reaction_phase")), "march", "the guard's phase after waking")
	var hp := float(guard.get(&"_hp"))
	t.place_worm(guard, ram.global_position + Vector2(200.0, -6.0))
	guard.call(&"set_hit_stun_until", Services.now_ms() + 1500.0)
	await t.steps(2)
	var from: Vector2 = guard.call(&"get_centre")
	ram.call(&"trigger")
	await t.until(func() -> bool: return str(ram.call(&"state_name")) == "return", 2000.0)
	await t.sim_wait(1200.0)
	t.equal(hp - float(guard.get(&"_hp")), DungeonState.number("ram.damage", 60.0), "the ram's damage to a heavy enemy")
	var moved := (guard.call(&"get_centre") as Vector2) - from
	t.check(moved.x >= 128.0, "a heavy enemy travelled less than two cells (moved %s)" % moved)


func test_the_ram_strikes_a_sleeping_statue_through_its_shield_but_cannot_move_it(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	t.teleport_player(ram.global_position + Vector2(-60.0, 200.0))
	await _clear_enemies(t)
	var guard := _spawn_guard(t, ram.global_position + Vector2(200.0, -6.0))
	if guard == null:
		return
	await t.steps(3)
	t.equal(str(guard.call(&"reaction_phase")), "asleep", "the guard's phase")
	var profile := ReactionProfile.for_enemy(guard)
	t.check(HitReaction.blow_lands(profile, {"true_blow": true}, "asleep"), "a mechanism's blow does not land on a sleeping statue")
	t.check(not HitReaction.blow_lands(profile, {}, "asleep"), "any hit lands on a sleeping statue")
	var hp := float(guard.get(&"_hp"))
	var from: Vector2 = guard.call(&"get_centre")
	ram.call(&"trigger")
	await t.until(func() -> bool: return str(ram.call(&"state_name")) == "return", 2000.0)
	await t.sim_wait(800.0)
	t.equal(hp - float(guard.get(&"_hp")), DungeonState.number("ram.damage", 60.0), "the ram's damage to a sleeping statue")
	# asleep it stands rooted (thorn_guard.gd `_slides_when_stunned`): the knock is not forced on it
	t.near_vec(guard.call(&"get_centre"), from, 2.0, "a sleeping statue moved")


func test_a_mechanism_clinks_on_an_enemy_invulnerable_by_design(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	t.teleport_player(ram.global_position + Vector2(-60.0, 200.0))
	await _clear_enemies(t)
	# the Prism Eye with `pattern.invulnerable` (owner, 2026-11-21: "you have to go around him")
	var eye := _spawn_enemy(t, PRISM_EYE_SCENE_ID, ram.global_position + Vector2(200.0, -6.0))
	if eye == null:
		return
	await t.steps(3)
	t.check(EnemyReactions.invulnerable_by_design(eye), "the Prism Eye is not invulnerable by design")
	var request := HitReaction.attach({"weapon_tags": ["mechanism", "ram"]}, HitReaction.build_hit("thrown-heavy", {"true_blow": true}))
	t.check(not EnemyReactions.blow_lands(eye, request), "a mechanism's blow lands through the Prism Eye's shield")
	var hp := float(eye.get(&"_hp"))
	ram.call(&"trigger")
	await t.until(func() -> bool: return str(ram.call(&"state_name")) == "return", 2000.0)
	await t.sim_wait(300.0)
	t.check(is_instance_valid(eye) and not bool(eye.call(&"is_defeated")), "the ram killed the Prism Eye")
	if is_instance_valid(eye):
		t.equal(float(eye.get(&"_hp")), hp, "the Prism Eye's health after the ram")


func test_a_hooked_node_gets_the_mechanism_call_instead_of_damage(t: TestContext) -> void:
	await _enter_lab(t)
	var ram := _node(t, "b-ram") as Node2D
	t.teleport_player(ram.global_position + Vector2(-60.0, 200.0))
	await _clear_enemies(t)
	var probe := HookProbe.new()
	probe.position = ram.global_position + Vector2(160.0, 10.0)
	_node(t, "Objects").add_child(probe)
	await t.steps(2)
	ram.call(&"trigger")
	await t.until(func() -> bool: return str(ram.call(&"state_name")) == "return", 2000.0)
	t.equal(probe.calls.size(), 1, "hook calls from one swing")
	if probe.calls.size() == 1:
		t.equal(probe.calls[0][0], &"ram", "the hook's kind")
		t.equal(probe.calls[0][1], ram, "the hook's source")
	t.equal(probe.commits, 0, "damage sent to a hooked node")
	probe.queue_free()


func test_the_ram_bursts_the_bricked_arch_for_good(t: TestContext) -> void:
	await _enter_lab(t)
	var arch := _node(t, "a-arch")
	var ram := _node(t, "a-ram")
	t.check(not bool(arch.call(&"is_burst")), "the arch starts whole")
	t.check(not _shapes_off(arch.get(&"body")), "the whole arch blocks")
	# Weapons and a blast do nothing to it.
	var result := _route(t, arch.get(&"damage_area"), ["weapon", "spear"])
	t.equal(str(result.get("reason", "")), "immune", "a weapon on the arch")
	t.check(not bool(arch.call(&"receive_blast", {})), "a blast opened the arch")
	# a bomb laid against the bricks (it stops about 28 units out from the arch's foot) reaches it
	var bomb_at := (arch as Node2D).global_position + Vector2(0.0, 28.0)
	t.check(GooBlast.in_ellipse(arch.call(&"blast_point"), bomb_at, GooBlast.half_size()), "a bomb against the bricks does not reach the arch")
	t.equal(arch.call(&"get_body"), arch.get(&"body"), "the arch's body for a throw's line test")
	t.check(not bool(arch.call(&"is_burst")), "the arch after a weapon and a blast")
	t.check(arch.is_in_group(&"ram_breakable"), "the arch is a ram breakable")
	ram.call(&"trigger")
	t.check(await t.until(func() -> bool: return bool(arch.call(&"is_burst")), 2000.0), "the ram did not burst the arch")
	await t.steps(3)
	t.check(_shapes_off(arch.get(&"body")), "the burst arch still blocks")
	# Built again, it stands burst.
	await _enter_lab(t)
	await t.steps(3)
	arch = _node(t, "a-arch")
	t.check(bool(arch.call(&"is_burst")), "the arch did not stay burst")
	DungeonState.clear_done(t.tree, DungeonState.object_key(arch, "arch:a-arch"))


# --- the runaway cart -------------------------------------------------------------------------------

func test_the_cart_smashes_the_rail_gate_and_stays_at_its_end(t: TestContext) -> void:
	await _enter_lab(t)
	var cart := _node(t, "c-cart") as Node2D
	var gate := _node(t, "c-gate")
	var target := _node(t, "c-target")
	t.teleport_player(cart.global_position + Vector2(-200.0, 200.0))
	await _clear_enemies(t)
	t.check(bool(cart.call(&"is_held")), "the cart starts held")
	t.check(not bool(gate.call(&"is_smashed")), "the gate starts shut")
	var result := _route(t, gate.get(&"damage_area"), ["weapon", "spear"])
	t.equal(str(result.get("reason", "")), "immune", "a weapon on the gate")
	t.check(not bool(gate.call(&"receive_blast", {})), "a blast opened the gate")
	_route(t, target.get(&"damage_area"), ["thrown", "clay-pot"])
	t.equal(str(cart.call(&"state_name")), "brake", "the cart after its target was knocked")
	t.check(await t.until(func() -> bool: return str(cart.call(&"state_name")) == "roll", 600.0), "the cart never rolled")
	# It speeds up as it goes.
	var early := (cart.call(&"cart_point") as Vector2).y
	await t.sim_wait(150.0)
	var first := (cart.call(&"cart_point") as Vector2).y - early
	early = (cart.call(&"cart_point") as Vector2).y
	await t.sim_wait(150.0)
	var second := (cart.call(&"cart_point") as Vector2).y - early
	t.check(second > first and first > 0.0, "the cart does not speed up (%s then %s units)" % [first, second])
	t.check(await t.until(func() -> bool: return str(cart.call(&"state_name")) == "spent", 4000.0), "the cart never stopped for good")
	t.check(bool(gate.call(&"is_smashed")), "the cart did not smash the gate")
	t.near_vec(cart.call(&"cart_point"), cart.global_position + Vector2(0.0, float(cart.call(&"line_length"))), 1.0, "where the cart ended")
	t.check(not bool(target.call(&"is_armed")), "a spent cart rearmed its target")
	cart.call(&"trigger")
	t.equal(str(cart.call(&"state_name")), "spent", "a spent cart let go again")
	# Built again: the cart at its end, the gate open.
	await _enter_lab(t)
	await t.steps(3)
	cart = _node(t, "c-cart") as Node2D
	gate = _node(t, "c-gate")
	t.equal(str(cart.call(&"state_name")), "spent", "the cart after the world was built again")
	t.check(bool(gate.call(&"is_smashed")), "the gate did not stay open")
	DungeonState.clear_done(t.tree, DungeonState.object_key(cart, "ram-cart:c-cart"))
	DungeonState.clear_done(t.tree, DungeonState.object_key(gate, "rail-gate:c-gate"))


func test_the_cart_knocks_the_slime_and_an_enemy_off_its_rails(t: TestContext) -> void:
	await _enter_lab(t)
	var cart := _node(t, "c-cart-2") as Node2D
	t.teleport_player(cart.global_position + Vector2(-150.0, -27.0 - 6.0))
	await _clear_enemies(t)
	var worm := t.spawn_worm(Vector2(80.0, 0.0), true)
	if worm == null:
		return
	t.set_enemy_health(worm, 200.0)
	t.place_worm(worm, cart.global_position + Vector2(-90.0, -16.0))
	await t.steps(2)
	var hp := t.player().get_hp()
	var slime_from := t.player_body().global_position
	cart.call(&"trigger")
	await t.until(func() -> bool: return str(cart.call(&"state_name")) == "bump", 3000.0)
	await t.sim_wait(300.0)
	t.equal(hp - t.player().get_hp(), int(DungeonState.number("ramCart.slimeDamage", 20.0)), "the cart's damage to the slime")
	t.check(absf(t.player_body().global_position.y - slime_from.y) > 30.0, "the slime was not knocked off the rails sideways")
	t.equal(200.0 - float(worm.get(&"_hp")), DungeonState.number("ramCart.damage", 60.0), "the cart's damage to an enemy (true damage)")


func test_the_cart_stops_against_a_hooked_node(t: TestContext) -> void:
	await _enter_lab(t)
	var cart := _node(t, "c-cart-2") as Node2D
	t.teleport_player(cart.global_position + Vector2(-100.0, 180.0))
	await _clear_enemies(t)
	var probe := HookProbe.new()
	probe.position = cart.global_position + Vector2(-150.0, 10.0)
	_node(t, "Objects").add_child(probe)
	await t.steps(2)
	var stops: Array = []
	var calls_at_bump: Array = []
	cart.connect(&"bumped", func(payload: Dictionary) -> void:
		stops.append(payload)
		calls_at_bump.append(probe.calls.size()))
	cart.call(&"trigger")
	await t.until(func() -> bool: return not stops.is_empty(), 3000.0)
	t.equal(probe.calls.size(), 1, "hook calls from one run")
	if probe.calls.size() == 1:
		t.equal(probe.calls[0][0], &"cart", "the hook's kind")
	t.equal(probe.commits, 0, "damage sent to a hooked node")
	if not stops.is_empty():
		t.equal((stops[0] as Dictionary).get("by"), probe, "what the cart stopped against")
		# the call comes at the touch, with the bump
		t.equal(calls_at_bump[0], 1, "hook calls when the cart bumped")
	# it stops at contact: its front (the side picture's bumper; it runs west) on the hurtbox's near edge
	var stopped: Vector2 = cart.call(&"cart_point")
	var front_x := stopped.x - RamCartScript.CONTACT_SIDE
	var edge_x := probe.global_position.x + HookProbe.SIZE.x * 0.5
	t.near(front_x, edge_x, 1.0, "the cart's front against the hooked node's hurtbox")
	probe.queue_free()


func test_a_cart_that_returns_is_hauled_back_and_rearms_its_target(t: TestContext) -> void:
	await _enter_lab(t)
	var cart := _node(t, "c-cart-2") as Node2D
	var target := _node(t, "c-target-2")
	t.teleport_player(cart.global_position + Vector2(-100.0, 180.0))
	await _clear_enemies(t)
	target.call(&"strike")
	t.check(await t.until(func() -> bool: return str(cart.call(&"state_name")) == "bump", 3000.0), "the cart never reached its end")
	t.near_vec(cart.call(&"cart_point"), cart.global_position - Vector2(float(cart.call(&"line_length")), 0.0), 1.0, "where the cart stopped")
	t.check(await t.until(func() -> bool: return str(cart.call(&"state_name")) == "return", 3000.0), "the cart was never hauled back")
	var started := t.now()
	t.check(not bool(target.call(&"is_armed")), "the target rearmed while the cart was away")
	t.check(await t.until(func() -> bool: return bool(cart.call(&"is_held")), 10000.0, 30000.0), "the cart never came home")
	t.near(t.now() - started, DungeonState.number("ramCart.returnMs", 8000.0), 80.0, "the haul back's length")
	t.near_vec(cart.call(&"cart_point"), cart.global_position, 0.5, "the cart at home")
	await t.sim_wait(DungeonState.number("knockTarget.rearmSnapMs", 180.0) + 100.0)
	t.check(bool(target.call(&"is_armed")), "the cart did not rearm its target")


# --- helpers ----------------------------------------------------------------------------------------

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


## A Thorn Guard (heavy, `knockbackScale` 0.2, asleep at first) whose centre is `centre`, passive.
func _spawn_guard(t: TestContext, centre: Vector2) -> EnemyScript:
	return _spawn_enemy(t, GUARD_SCENE_ID, centre)


## The enemy of scene `scene_id` whose centre is `centre`, passive.
func _spawn_enemy(t: TestContext, scene_id: String, centre: Vector2) -> EnemyScript:
	var root := t.world().spawn_at_phaser_position(scene_id, centre)
	if root == null:
		t.fail("no %s spawned" % scene_id)
		return null
	for child: Node in root.get_children():
		if child is EnemyScript:
			var enemy := child as EnemyScript
			enemy.targeting_radius = 0.0
			enemy.attack_range = 0.0
			return enemy
	t.fail("%s has no EnemyScript" % scene_id)
	return null


## Takes the lab's own enemies out (a camera room entered brings its placed enemies back first).
func _clear_enemies(t: TestContext) -> void:
	await t.sim_wait(900.0)
	for enemy: Node in t.tree.get_nodes_in_group(&"enemy"):
		var holder := enemy.get_parent()
		if holder != null:
			holder.queue_free()
	await t.steps(2)


## True when every collision shape of `body` is off.
func _shapes_off(body: Variant) -> bool:
	if not (body is Node):
		return false
	for child: Node in (body as Node).get_children():
		if child is CollisionShape2D and not (child as CollisionShape2D).disabled:
			return false
	return true


## One hit with `tags` routed to `area`, carrying the impact effect every thrown hit carries (a hit
## that deals no damage is committed only with an effect: the target's knock, as the bell's ring).
## Returns the router's result.
func _route(t: TestContext, area: Variant, tags: Array) -> Dictionary:
	if not (area is Area2D):
		t.fail("no hurtbox to hit")
		return {}
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	var result: Dictionary = router.route({"activation_id": activation, "source": source, "attack_area": attack,
		"target_area": area, "weapon_id": "test-hit", "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 10.0,
		"effects": [{"effect_id": IMPACT_EFFECT, "potency": 1.0}],
		"impact": {"position": (area as Area2D).global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
	return result
