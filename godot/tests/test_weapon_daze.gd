extends RefCounted
## A combo sets up the throw (one combat, piece 3 of docs/design/2026-11-25-weapons-beside-throws.md;
## THROW_COMBAT.md "Enemies as ammo"): a weapon's finisher or charge that lands leaves the enemy dazed and
## helpless for `combat.rules.weaponDaze.windowMs` once its knock is over, so the Gulp can lift it if its
## level lifts the weight; a heavy enemy only when the blow broke its poise; plain taps never; a boss
## never. EnemyReactions `_note_weapon_daze`, `_start_weapon_daze`; game/throw/weapon_daze_hint.gd.
##
## Every test travels to the playground (its shapes testbed has the boss-preset dummy), the Gulp at the
## level the test names, and strikes with the Spear through the attack key.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const WeaponDazeHint := preload("res://game/throw/weapon_daze_hint.gd")
const TrainingDummyScript := preload("res://game/scripts/training_dummy.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")

const MAP_ID := "playground"
## A clear stretch of grass north of the playground's spawn.
const RANGE_FROM_SPAWN := Vector2(0.0, -260.0)
## Where the struck enemy stands from the slime's centre: in the Spear's reach.
const AHEAD := Vector2(72.0, 0.0)
const PLENTY_HP := 1000.0
## Taps in rhythm (inside the link window) and plain taps (past it: each a new chain's first jab).
const RHYTHM_MS := 250.0
const PLAIN_GAP_MS := 800.0
const BOSS_DUMMY := "shapes-dummy-boss"
## A heavy enemy the Axe hurts (bark, piece 4): its poise of 4 breaks on the chop (sweep 1, backswing 1, chop 2).
const GUARD_SCENE_ID := "character.thorn-guard"


func test_a_finisher_dazes_a_worm_the_gulp_can_take(t: TestContext) -> void:
	await _enter(t, 2)
	var worm := await _worm(t)
	t.check(not Services.run().has_flag(WeaponDazeHint.FLAG), "the hint was learned before the first daze")
	await _combo(t)
	t.check(await t.until(func() -> bool: return EnemyReactions.is_helpless(worm), 2500.0),
		"the finisher did not leave it helpless")
	var gulpable: Node = worm.body.get_node_or_null("GulpableEnemy")
	t.check(gulpable != null and bool(gulpable.call(&"can_take")), "the Gulp at level 2 cannot take a dazed swordsman")
	t.check(Services.run().has_flag(WeaponDazeHint.FLAG), "the first weapon daze did not show the hint")
	t.check(worm.body.find_child(WeaponDazeHint.CUE_NAME, true, false) != null, "no pointer flashes the dazed worm")
	var window := Services.constants().number("combat.rules.weaponDaze.windowMs")
	t.near(window, 1500.0, 0.01, "the daze's window")
	await t.sim_wait(window + 200.0)
	t.check(not EnemyReactions.is_helpless(worm), "still helpless after the window")


func test_the_hammers_boom_dazes_and_a_lone_thud_does_not(t: TestContext) -> void:
	await _enter(t, 2)
	var shapes := t.player().get_shapes()
	if not t.check(shapes.set_current(ShapeDefs.HAMMER), "the Hammer could not be taken"):
		return
	var worm := await _worm(t, Vector2(68.0, 0.0))
	var state := EnemyReactions.state_of(worm)
	t.tap(&"attack")
	var until := t.now() + 1500.0
	var seen := false
	while t.now() < until:
		await t.steps(1)
		seen = seen or EnemyReactions.is_helpless(worm) or state.weapon_daze_ms > 0.0
	t.check(not seen, "a lone thud set it up")
	t.place_worm(worm, t.player().get_centre() + Vector2(68.0, 0.0))
	await t.steps(2)
	t.tap(&"attack")
	await t.sim_wait(RHYTHM_MS + 150.0)
	t.tap(&"attack")
	t.check(await t.until(func() -> bool: return EnemyReactions.is_helpless(worm), 3000.0),
		"the BOOM did not leave it helpless")


func test_plain_taps_never_daze(t: TestContext) -> void:
	await _enter(t, 2)
	var worm := await _worm(t)
	var state := EnemyReactions.state_of(worm)
	var seen := false
	for tap in 3:
		t.tap(&"attack")
		var until := t.now() + PLAIN_GAP_MS
		while t.now() < until:
			await t.steps(1)
			seen = seen or EnemyReactions.is_helpless(worm) or state.weapon_daze_ms > 0.0
			# Back in the Spear's reach once a tap's push is over.
			var spot := t.player().get_centre() + AHEAD
			if worm.get_centre().distance_to(spot) > 60.0 and not state.in_stun(t.now()):
				t.place_worm(worm, spot)
	await t.sim_wait(1500.0)
	t.check(not seen and not EnemyReactions.is_helpless(worm), "a plain tap left it dazed for the Gulp")


func test_a_charge_dazes(t: TestContext) -> void:
	await _enter(t, 2)
	var worm := await _worm(t, Vector2(110.0, 0.0))
	t.press(&"attack")
	await t.sim_wait(ShapeDefs.chain_number("chargeStartMs") + ShapeDefs.num(ShapeDefs.charge(ShapeDefs.SPEAR), "ringMs") + 150.0)
	t.release(&"attack")
	t.check(await t.until(func() -> bool: return EnemyReactions.is_helpless(worm), 2500.0),
		"the Lunge did not leave it helpless")


func test_a_heavy_one_only_when_its_poise_breaks(t: TestContext) -> void:
	await _enter(t, 3)
	var player := t.player()
	var root := Services.world().spawn_at_phaser_position(GUARD_SCENE_ID, player.get_centre() + Vector2(60.0, 0.0))
	var guard: Node = null
	if root != null:
		for child: Node in root.get_children():
			if child.has_method(&"wake"):
				guard = child
	if not t.check(guard != null, "no Thorn Guard"):
		return
	t.set_enemy_health(guard as EnemyScript, PLENTY_HP)
	# Woken (asleep or waking it is shielded: its own rule), struck with the Axe (bark takes only the Axe).
	guard.call(&"wake", t.now())
	await t.until(func() -> bool: return not ["asleep", "wake"].has(str(guard.get(&"_phase"))), 3000.0)
	player.get_shapes().set_current(ShapeDefs.AXE)
	(guard.get(&"body") as Node2D).global_position = player.body.global_position + Vector2(58.0, 0.0)
	player.face(Vector2.RIGHT)
	await t.steps(3)
	var state := EnemyReactions.state_of(guard)
	var broke := false
	var before_break := false
	var after_break := false
	for combo in 4:
		(guard.get(&"body") as Node2D).global_position = player.body.global_position + Vector2(58.0, 0.0)
		await t.steps(2)
		for tap in 3:
			var poise_before := state.poise
			t.tap(&"attack")
			var until := t.now() + (RHYTHM_MS if tap < 2 else 1200.0)
			while t.now() < until:
				await t.steps(1)
				if poise_before >= 0.0 and state.poise > poise_before + 0.5:
					broke = true
					poise_before = state.poise
				var helpless := EnemyReactions.is_helpless(guard)
				before_break = before_break or (helpless and not broke)
				after_break = after_break or (helpless and broke)
		if after_break:
			break
	t.check(broke, "the Axe never broke its poise")
	t.check(not before_break, "it was liftable before its poise broke")
	t.check(after_break, "the blow that broke its poise did not leave it helpless")


func test_never_a_boss(t: TestContext) -> void:
	await _enter(t, 3)
	var dummy := _dummy(t, BOSS_DUMMY)
	if not t.check(dummy != null, "no boss dummy"):
		return
	t.equal(str(dummy.get(&"reaction_preset")), "boss", "the dummy's preset")
	var body := dummy.call(&"get_body") as Node2D
	t.teleport_player(body.global_position + Vector2(-78.0, -28.0))
	t.player().face(Vector2.RIGHT)
	await t.steps(3)
	var state := EnemyReactions.state_of(dummy)
	var pending := false
	t.tap(&"attack")
	await t.sim_wait(RHYTHM_MS)
	t.tap(&"attack")
	await t.sim_wait(RHYTHM_MS)
	t.tap(&"attack")
	var until := t.now() + 2000.0
	while t.now() < until:
		await t.steps(1)
		pending = pending or state.weapon_daze_ms > 0.0 or (state.verb == "daze" and state.throw_helpless)
	t.check(not pending, "a combo dazed a boss for the Gulp")


func test_too_heavy_for_the_gulp_is_dazed_and_refused(t: TestContext) -> void:
	await _enter(t, 1)
	var worm := await _worm(t)
	await _combo(t)
	t.check(await t.until(func() -> bool: return EnemyReactions.is_helpless(worm), 2500.0),
		"the finisher did not daze the swordsman")
	var gulpable: Node = worm.body.get_node_or_null("GulpableEnemy")
	t.check(gulpable != null and bool(gulpable.call(&"is_too_heavy")), "a medium swordsman is not too heavy at level 1")
	t.teleport_player(worm.get_centre() + Vector2(-60.0, 0.0))
	t.player().face(Vector2.RIGHT)
	await t.steps(2)
	t.tap(&"eat")
	await t.sim_wait(600.0)
	t.check(t.player().held().is_empty(), "the Gulp at level 1 took a medium enemy")


# --- helpers ----------------------------------------------------------------------------------------

## The playground again, the Gulp at `level`, the Spear in hand, the slime on open grass.
func _enter(t: TestContext, level: int) -> void:
	ThrowMode.set_assist(false)
	t.main.call(&"travel_to", MAP_ID)
	await t.until(func() -> bool: return ReworkMode.is_on() and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")), 3000.0)
	await t.steps(3)
	ThrowMode.set_dev_level(level)
	var run := Services.run()
	run.learn_session_ability(String(ShapeDefs.SPEAR))
	var shapes := t.player().get_shapes()
	shapes.sync_learned()
	shapes.set_current(ShapeDefs.SPEAR)
	t.teleport_player(Services.world().player_spawn_point() + RANGE_FROM_SPAWN)
	t.player().face(Vector2.RIGHT)
	await t.steps(2)


## A passive worm swordsman (medium, plenty of health) `offset` right of the slime.
func _worm(t: TestContext, offset: Vector2 = AHEAD) -> EnemyScript:
	var worm := t.spawn_worm(offset, true)
	t.set_enemy_health(worm, PLENTY_HP)
	await t.steps(3)
	return worm


## The Spear's combo in rhythm: jab, jab, lunging jab.
func _combo(t: TestContext) -> void:
	t.tap(&"attack")
	await t.sim_wait(RHYTHM_MS)
	t.tap(&"attack")
	await t.sim_wait(RHYTHM_MS)
	t.tap(&"attack")


func _dummy(t: TestContext, name: String) -> Node:
	var dummy_root := t.tree.root.find_child(name, true, false)
	if dummy_root == null:
		return null
	for node: Node in dummy_root.find_children("*", "", true, false):
		if node.get_script() == TrainingDummyScript:
			return node
	return null
