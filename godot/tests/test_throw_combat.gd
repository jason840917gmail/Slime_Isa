extends RefCounted
## The throw rules in the one combat (docs/godot/THROW_COMBAT.md; since 2026-11-25 always on, with the
## weapon on the attack key beside them): the playground. What the Gulp lifts follows its level, a
## thing's weight and material set its damage and effect, the attack key strikes with the weapon (its
## charges free), the Ability Box holds box abilities only, and missed arrows and a Brawler's blows make
## ammo.
##
## run_tests.gd starts every test of this file in the playground; each test travels there again with
## the Gulp at level 1 and the aim help off.
##
## The new throw feel (game/throw/throw_feel.gd, `gulp.throwFeel`) changes a throw's damage, so the
## damage expectations are read from the constants (`_throw_damage`), whichever feel is on.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")

const MAP_ID := "playground"
## A clear stretch of grass north of the playground's spawn, for the throws.
const RANGE_FROM_SPAWN := Vector2(0.0, -260.0)
const WORM_AHEAD_PX := 150.0
## Health for a worm that must live through every throw of a test (test setup only).
const PLENTY_HP := 1000.0


func test_the_yard_the_box_and_the_attack(t: TestContext) -> void:
	await _enter(t)
	var player := t.player()
	t.equal(ThrowMode.gulp_level(), 1, "the Gulp's level")
	var yard: Node = t.main.get(&"world_root").get_node_or_null("ThrowTestbed")
	if not t.check(yard != null, "no throw yard"):
		return
	await t.steps(3)
	var filled := 0
	for slot: Dictionary in yard.get(&"slots"):
		if slot["root"] != null:
			filled += 1
	t.equal(filled, 12, "things in the yard")
	var box := AbilityBox.box_ids(player)
	t.check(not box.has(&"shape-spear") and not box.has(&"shape-hammer"), "a weapon is in the Ability Box: %s" % str(box))
	t.tap(&"attack")
	await t.steps(4)
	t.check(player.get_shapes().is_busy(), "the attack key did not strike with the weapon")


func test_weight_follows_the_gulp_level(t: TestContext) -> void:
	await _enter(t)
	var player := t.player()
	var worm := t.spawn_worm(Vector2(WORM_AHEAD_PX, 0.0), true)
	t.set_enemy_health(worm, PLENTY_HP)
	await t.steps(2)
	await _catch(t, "clay-pot")
	t.equal(str(player.held().get("kind", "")), "clay-pot", "held")
	t.near(await _throw_at(t, worm), _throw_damage(ThrowMode.LIGHT), 0.5, "a light pot's damage")
	await t.sim_wait(1500.0)
	ThrowAmmo.spawn_liftable("crate", player.body.global_position + Vector2(0.0, 30.0))
	await t.steps(2)
	player.face(Vector2.DOWN)
	t.tap(&"eat")
	await t.sim_wait(700.0)
	t.check(player.held().is_empty(), "level 1 lifted a crate")
	ThrowMode.set_dev_level(2)
	await t.sim_wait(400.0)
	t.tap(&"eat")
	await t.sim_wait(600.0)
	t.equal(str(player.held().get("kind", "")), "crate", "held at level 2")
	await t.sim_wait(1500.0)
	t.near(await _throw_at(t, worm), _throw_damage(ThrowMode.MEDIUM), 0.5, "a medium crate's damage")


func test_effects_freeze_sleep_and_pierce(t: TestContext) -> void:
	await _enter(t)
	ThrowMode.set_dev_level(2)
	var worm := t.spawn_worm(Vector2(WORM_AHEAD_PX, 0.0), true)
	var other := t.spawn_worm(Vector2(WORM_AHEAD_PX + 80.0, 0.0), true)
	t.set_enemy_health(worm, PLENTY_HP)
	t.set_enemy_health(other, PLENTY_HP)
	await t.steps(2)
	await _catch(t, "snowball")
	await _throw_at(t, worm)
	await t.steps(2)
	var ice := worm.body.get_node_or_null("ThrowStatusLook")
	t.check(ice != null and str(ice.get(&"effect")) == "freeze", "a snowball did not freeze it")
	await t.sim_wait(3500.0)
	await _catch(t, "puffball")
	await _throw_at(t, other)
	await t.steps(2)
	var zz := other.body.get_node_or_null("ThrowStatusLook")
	t.check(zz != null and str(zz.get(&"effect")) == "sleep", "a puffball did not put it to sleep")
	await t.sim_wait(4500.0)
	await _catch(t, "kettle")
	var centre := t.player().get_centre()
	t.place_worm(worm, centre + Vector2(110.0, 0.0))
	t.place_worm(other, centre + Vector2(190.0, 0.0))
	await t.steps(2)
	var hp1 := float(worm.get(&"_hp"))
	var hp2 := float(other.get(&"_hp"))
	t.player().face(Vector2.RIGHT)
	t.tap(&"eat")
	await t.sim_wait(900.0)
	t.check(float(worm.get(&"_hp")) < hp1 and float(other.get(&"_hp")) < hp2,
		"a kettle did not pierce both (%s -> %s, %s -> %s)" % [hp1, worm.get(&"_hp"), hp2, other.get(&"_hp")])


func test_a_charge_is_free_and_an_ability_is_picked_in_the_bag(t: TestContext) -> void:
	await _enter(t)
	var player := t.player()
	var shapes := player.get_shapes()
	shapes.set_current(ShapeDefs.SPEAR)
	player.set_energy(0.0)
	t.press(&"attack")
	var hold_ms := ShapeDefs.chain_number("chargeStartMs") + ShapeDefs.num(ShapeDefs.charge(ShapeDefs.SPEAR), "ringMs")
	await t.sim_wait(hold_ms + 150.0)
	t.check(shapes.charge_progress() >= 1.0, "the ring did not fill (%.2f)" % shapes.charge_progress())
	# Energy refills slowly on its own: the charge spends none of it (it was 15 before 2026-11-25).
	var before := player.get_energy()
	t.check(before < 15.0, "the slime had enough energy for the old cost (%.1f)" % before)
	t.release(&"attack")
	await t.steps(3)
	t.check(shapes.is_busy(), "the Lunge did not fire short of the old energy cost")
	t.check(player.get_energy() >= before - 0.01, "the charge spent energy (%.2f -> %.2f)" % [before, player.get_energy()])
	await t.sim_wait(1200.0)
	var box := AbilityBox.box_ids(player)
	if not t.check(box.size() >= 2, "the playground lends fewer than two box abilities: %s" % str(box)):
		return
	var pick: StringName = box[1] if AbilityBox.selected(player) == box[0] else box[0]
	t.check(AbilityBox.choose(player, pick), "the bag's pick was refused")
	t.equal(AbilityBox.selected(player), pick, "the ability on D")
	t.check(not AbilityBox.choose(player, ShapeDefs.AXE), "a weapon was put in the Ability Box")


func test_weapon_hits_are_scaled_and_throws_are_not(t: TestContext) -> void:
	await _enter(t)
	var scale := ShapeDefs.weapon_damage_scale()
	t.near(scale, 0.5, 0.001, "shapes.weaponDamageScale")
	var constants := Services.constants()
	var attack := constants.number(ShapeDefs.STAT_ATTACK) / 10.0
	var lunge := ShapeDefs.num(ShapeDefs.charge(ShapeDefs.SPEAR), "damageScale")
	t.near(ShapeDefs.damage(ShapeDefs.SPEAR, lunge), ShapeDefs.base_damage(ShapeDefs.SPEAR) * attack * lunge * scale, 0.01,
		"the Lunge's damage")
	var worm := t.spawn_worm(Vector2(WORM_AHEAD_PX, 0.0), true)
	t.set_enemy_health(worm, PLENTY_HP)
	await t.steps(2)
	await _catch(t, "clay-pot")
	t.near(await _throw_at(t, worm), _throw_damage(ThrowMode.LIGHT), 0.5, "a light pot's damage, unscaled")


func test_enemies_make_ammo(t: TestContext) -> void:
	await _enter(t)
	var player := t.player()
	var world := Services.world()
	var arrow := world.instantiate_scene("projectile.worm-arrow") as Node2D
	world.entities_root().add_child(arrow)
	arrow.global_position = player.get_centre() + Vector2(0.0, -40.0)
	for child: Node in arrow.get_children():
		if child.has_method(&"launch"):
			child.call(&"launch", Vector2.UP, 300.0, {})
	await t.sim_wait(3500.0)
	var spent := 0
	for node: Node in t.tree.get_nodes_in_group(&"suckable"):
		if node.name.begins_with("SpentShot"):
			spent += 1
	t.check(spent >= 1, "a missed arrow left nothing")
	var rocks := 0
	for i in 20:
		if ThrowAmmo.knock_loose("worm-brawler", player.get_centre() + Vector2(-300.0 + i * 50.0, 120.0), Vector2.DOWN):
			rocks += 1
	t.check(rocks > 0 and rocks < 20, "a brawler's blows knocked %d rocks of 20 loose" % rocks)


## The playground again, the Gulp at level 1 and the aim help off, the slime on open grass north of the
## spawn.
func _enter(t: TestContext) -> void:
	ThrowMode.set_dev_level(1)
	ThrowMode.set_assist(false)
	t.main.call(&"travel_to", MAP_ID)
	await t.until(func() -> bool: return ReworkMode.is_on() and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")), 3000.0)
	await t.steps(3)
	var world := Services.world()
	t.teleport_player(t.player().get_centre() + RANGE_FROM_SPAWN if world == null
		else world.player_spawn_point() + RANGE_FROM_SPAWN)
	await t.steps(2)


## What a thing whose material deals x 1 (clay, wood) deals at `weight`: the throw's base damage (the
## new throw feel's `throwDamage` while it is on, else `gulp.throwCombat.throwDamage`) x the weight's
## `damageScale`.
func _throw_damage(weight: String) -> float:
	return ThrowFeel.base_damage() * ThrowMode.weight_number(weight, "damageScale")


## Lays a `kind` liftable just under the slime and sucks it in.
func _catch(t: TestContext, kind: String) -> void:
	var player := t.player()
	ThrowAmmo.spawn_liftable(kind, player.body.global_position + Vector2(0.0, 30.0))
	await t.steps(2)
	player.face(Vector2.DOWN)
	t.tap(&"eat")
	await t.until(func() -> bool: return not player.held().is_empty(), 900.0)
	await t.sim_wait(350.0)


## Puts `worm` WORM_AHEAD_PX right of the slime, throws what the mouth holds at it and returns the
## damage it took.
func _throw_at(t: TestContext, worm: Node) -> float:
	t.place_worm(worm, t.player().get_centre() + Vector2(WORM_AHEAD_PX, 0.0))
	await t.steps(2)
	var before := float(worm.get(&"_hp"))
	t.player().face(Vector2.RIGHT)
	t.tap(&"eat")
	await t.until(func() -> bool: return float(worm.get(&"_hp")) < before, 1500.0)
	return before - float(worm.get(&"_hp"))
