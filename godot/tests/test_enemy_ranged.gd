extends RefCounted
## Ranged enemies, enemy projectiles, keep-distance and spider AI, slow, impact effects, immunities
## and the enemy types the worlds spawn (docs/godot/specs/enemy.md part 2, sections 11-19).
## - Worm archer (40 hp, range 220, fleeRange 120, windup 600, cooldown 2200): the arrow leaves
##   600 ms after the attack starts, from the archer's centre, toward where the player was, at
##   180 px/s; it hits for max(1, 22 - 3) = 19 with knockback 180 along its flight, then frees itself.
## - Projectiles live 3000 ms, stop at world-layer bodies, ignore enemy hurtboxes and the world
##   bounds, and are used up by a rejected (i-framed) hit too.
## - Slime spider: orbits in at 80 px/s (0.86 radial, 0.52 lateral), spits a web for 50 - 3 = 47
##   with a 1000 ms `web` effect; backs off (x1.08) when the player comes inside 0.72 x 120.
## - Worm brawler: melee 52 - 3 = 49, knockback 340, `enemy-worm-brawler-hit` 22 px along the swing.
## Tests run on open ground south of the starter camp (outside every camp and safe zone).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const ProjectileScript := preload("res://game/scripts/projectile.gd")
const EffectScript := preload("res://game/scripts/effect.gd")
const EnemyProjectiles := preload("res://game/enemy/enemy_projectiles.gd")
const SlimeSpiderAI := preload("res://game/enemy/slime_spider_ai.gd")
const EnemyPopulation := preload("res://game/enemy/enemy_population.gd")

## Open ground (a 700 x 260 rectangle free of walls and water around it), south of the starter
## camp's pursue rectangle, far from the safe zone and the other camps.
const OPEN := Vector2(880.0, 2120.0)
const STEP := TestContext.STEP_MS
const SLACK := TestContext.STEP_MS + 0.01
const ARCHER_WINDUP_MS := 600.0
const ARCHER_ARROW_SPEED := 180.0
const ARROW_HIT := 19
const ARROW_KNOCKBACK := 180.0
const PROJECTILE_LIFETIME_MS := 3000.0
const SPIDER_WEB_HIT := 47
const SPIDER_WEB_MS := 1000.0
const SPIDER_SPEED := 80.0
const BRAWLER_HIT := 49
const BRAWLER_IMPACT_DISTANCE := 22.0
## Every enemy type a world spawns (enemy spec 11).
const WORLD_TYPES: Array[String] = ["worm-swordsman", "worm-archer", "worm-brawler", "slime-spider", "orb-weaver"]


func test_archer_shoots_an_arrow_that_flies_and_hits(t: TestContext) -> void:
	t.teleport_player(OPEN)
	var archer := _spawn(t, "worm-archer", OPEN + Vector2(200.0, 0.0))
	if archer == null:
		return
	var started: Array = []
	archer.attack_started.connect(func(payload: Dictionary) -> void: started.append({"now": t.now(), "payload": payload}))
	var hits := _player_hits(t)
	var shot := {}
	var watch := func() -> bool:
		if shot.is_empty():
			var found := _projectiles(t)
			if not found.is_empty():
				var script: ProjectileScript = found[0]
				shot["script"] = script
				shot["id"] = script.get_instance_id()
				shot["root_id"] = script.get_parent().get_instance_id()
				shot["now"] = t.now()
				shot["position"] = (script.get_parent() as Node2D).global_position
				shot["velocity"] = script.body.velocity
				shot["rotation"] = script.visual.rotation
				shot["archer"] = archer.get_centre()
		return not shot.is_empty()
	if not t.check(await t.until(watch, 1200.0), "the archer never fired (attacks %s)" % [started]):
		return
	if not t.check(not started.is_empty(), "no attack_started before the arrow"):
		return
	var attack: Dictionary = started[0]
	t.equal(attack["payload"], {"ranged": true, "windupMs": ARCHER_WINDUP_MS}, "attack_started payload")
	t.between(float(shot["now"]) - float(attack["now"]), ARCHER_WINDUP_MS - SLACK, ARCHER_WINDUP_MS + SLACK, "windup to the shot (ms)")
	var script: ProjectileScript = shot["script"]
	t.equal(script.projectile_id, "worm-arrow", "projectile id")
	t.near_vec(shot["position"], shot["archer"], 4.0, "arrow spawn point (the archer's centre)")
	t.near_vec(shot["velocity"], Vector2.LEFT * ARCHER_ARROW_SPEED, 0.5, "arrow velocity")
	t.near(float(shot["rotation"]), PI, 0.01, "arrow rotation (pointing left)")
	var payload := script.get_damage_payload()
	t.equal(payload.get("weapon_tags"), ["enemy", "projectile"], "payload weapon tags")
	t.near(float(payload.get("damage", 0.0)), 22.0, 0.01, "payload damage")
	t.equal(payload.get("effects"), [], "an arrow carries no web")
	var hit := await t.until(func() -> bool: return not hits.is_empty(), 1500.0)
	if not t.check(hit, "the arrow never hit the player"):
		return
	var commit: Dictionary = hits[0]["commit"]
	var result: Dictionary = commit["result"]
	t.equal(int(result.get("actual_damage", 0)), ARROW_HIT, "arrow damage to the player")
	var request: Dictionary = commit["request"]
	t.equal(request.get("weapon_id"), "worm-arrow", "request weapon id")
	t.equal(result.get("applied_effects"), [{"effect_id": "knockback", "potency": ARROW_KNOCKBACK}], "applied effects")
	t.near_vec((request["impact"] as Dictionary)["knock"], Vector2.LEFT, 0.001, "knock along the flight")
	var flight_ms := float(hits[0]["now"]) - float(shot["now"])
	t.between(flight_ms, 700.0, 1150.0, "arrow flight time to the player (ms)")
	await t.steps(2)
	t.check(not is_instance_id_valid(shot["root_id"]) or (instance_from_id(shot["root_id"]) as Node).is_queued_for_deletion(),
		"the arrow outlived its hit")
	# One shot per cooldown: the next one comes 2200 ms after the first attack started.
	var second := await t.until(func() -> bool: return started.size() >= 2, 2600.0)
	if t.check(second, "no second shot"):
		t.between(float(started[1]["now"]) - float(attack["now"]), 2200.0 - SLACK, 2200.0 + SLACK, "archer cooldown (ms)")


func test_projectile_lifetime_walls_world_bounds_and_hurtboxes(t: TestContext) -> void:
	t.teleport_player(OPEN)
	var shooter := _spawn(t, "worm-archer", OPEN + Vector2(-300.0, -100.0), true)
	if shooter == null:
		return
	await t.steps(1)
	# 1. Lifetime: a slow arrow through open ground expires 3000 ms after the launch.
	var slow := _fire(t, shooter, OPEN + Vector2(-300.0, -60.0), Vector2.RIGHT, 50.0, 0.0)
	if slow == null:
		return
	var events := {"expired": []}
	var slow_script := EnemyProjectiles.find_projectile_script(slow)
	slow_script.expired.connect(func(payload: Dictionary) -> void: (events["expired"] as Array).append({"now": t.now(), "payload": payload}))
	var launched_at := t.now()
	await t.until(func() -> bool: return not (events["expired"] as Array).is_empty(), PROJECTILE_LIFETIME_MS + 200.0)
	if t.equal((events["expired"] as Array).size(), 1, "expired emissions"):
		t.between(float(events["expired"][0]["now"]) - launched_at, PROJECTILE_LIFETIME_MS - SLACK, PROJECTILE_LIFETIME_MS + 2.0 * SLACK, "lifetime (ms)")
		t.equal(events["expired"][0]["payload"], {"projectileId": "worm-arrow"}, "expired payload")
	# 2. A world-layer body stops it: expired on the step after the contact, far before its lifetime.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20.0, 200.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	t.world().entities_root().add_child(wall)
	wall.global_position = OPEN + Vector2(-100.0, -60.0)
	await t.steps(2)
	var blocked := _fire(t, shooter, OPEN + Vector2(-300.0, -60.0), Vector2.RIGHT, 300.0, 0.0)
	var blocked_script := EnemyProjectiles.find_projectile_script(blocked)
	var blocked_events := {"expired_at": -1.0}
	blocked_script.expired.connect(func(_payload: Dictionary) -> void: blocked_events["expired_at"] = t.now())
	var fired_at := t.now()
	await t.until(func() -> bool: return float(blocked_events["expired_at"]) >= 0.0, 1500.0)
	var stop_ms := float(blocked_events["expired_at"]) - fired_at
	t.between(stop_ms, 500.0, 800.0, "flight to the wall (190 px at 300 px/s) before expiring (ms)")
	wall.queue_free()
	# 3. World bounds do not stop projectiles (`collideWorldBounds` false): the runtime bounds body
	# is a collision exception of every projectile body.
	var out := _fire(t, shooter, OPEN + Vector2(-300.0, -100.0), Vector2.DOWN, 10.0, 0.0)
	var out_script := EnemyProjectiles.find_projectile_script(out)
	var exceptions := out_script.body.get_collision_exceptions().map(func(body: PhysicsBody2D) -> String: return String(body.name))
	t.check(exceptions.has("WorldBounds"), "the projectile collides with the world bounds (exceptions %s)" % [exceptions])
	out_script.expire()
	# 4. Enemy hurtboxes are ignored: the arrow flies through a passive worm to the player.
	var bystander := _spawn(t, "worm-swordsman", OPEN + Vector2(-120.0, 0.0), true)
	t.set_enemy_health(bystander, TestContext.SPEC_WORM_HP)
	await t.steps(1)
	var hits := _player_hits(t)
	_fire(t, shooter, OPEN + Vector2(-250.0, 0.0), Vector2.RIGHT, 300.0, 0.0)
	await t.until(func() -> bool: return not hits.is_empty(), 1500.0)
	t.near(float(bystander.get_damage_state()["hp"]), 90.0, 0.01, "bystander worm hp (the arrow passed through)")
	if t.check(not hits.is_empty(), "the arrow passing the worm never hit the player"):
		t.equal(int((hits[0]["commit"]["result"] as Dictionary).get("actual_damage", 0)), ARROW_HIT, "damage after passing the worm")
	# 5. A rejected hit (player in i-frames) still uses the projectile up.
	var routes := _routes_to_player(t)
	var spent := _fire(t, shooter, OPEN + Vector2(-80.0, 0.0), Vector2.RIGHT, 300.0, 0.0)
	var spent_id := spent.get_instance_id()
	var rejected := await t.until(func() -> bool:
		return routes.any(func(entry: Dictionary) -> bool: return str((entry["result"] as Dictionary).get("reason", "")) == "state-blocked"), 600.0)
	t.check(rejected, "the arrow in the i-frames was not rejected 'state-blocked' (routes %s)" % [routes])
	await t.steps(2)
	t.check(not is_instance_id_valid(spent_id) or (instance_from_id(spent_id) as Node).is_queued_for_deletion(), "a rejected arrow kept flying")


func test_flee_range_keeps_the_archer_at_distance(t: TestContext) -> void:
	t.teleport_player(OPEN)
	var archer := _spawn(t, "worm-archer", OPEN + Vector2(60.0, 0.0))
	if archer == null:
		return
	var started: Array = []
	archer.attack_started.connect(func(_payload: Dictionary) -> void: started.append(t.now()))
	await t.steps(3)
	t.equal(archer.get_runtime_state(), "flee", "state with the player 60 px away (fleeRange 120)")
	t.near_vec(archer.body.velocity, Vector2.RIGHT * 80.0, 0.5, "flee velocity (away from the player at movementSpeed)")
	var shooting := await t.until(func() -> bool: return not started.is_empty(), 1500.0)
	if not t.check(shooting, "the archer never stopped fleeing to shoot"):
		return
	var distance := archer.get_centre().distance_to(t.player().get_centre())
	t.between(distance, 120.0, 130.0, "distance when the archer turned to shoot")
	t.near_vec(archer.body.velocity, Vector2.ZERO, 0.01, "velocity while shooting")


func test_slime_spider_orbits_spits_webs_and_backs_off(t: TestContext) -> void:
	t.teleport_player(OPEN)
	var spider := _spawn(t, "slime-spider", OPEN + Vector2(260.0, 0.0))
	if spider == null:
		return
	await t.steps(2)
	# Out of range: it spirals in at 80 px/s, 31 degrees off the line to the player.
	t.equal(spider.get_runtime_state(), "chase", "spider state at 260 px")
	var velocity := spider.body.velocity
	var to_player := (t.player().get_centre() - spider.get_centre()).normalized()
	t.near(velocity.length(), SPIDER_SPEED, 0.5, "orbit speed")
	t.near(absf(rad_to_deg(velocity.angle_to(to_player))), rad_to_deg(atan2(0.52, 0.86)), 1.0, "orbit angle off the line to the player (deg)")
	var expected := SlimeSpiderAI.orbit_velocity({"dir": to_player, "centre": spider.get_centre()}, 0.86, 0.52, SPIDER_SPEED)
	t.near_vec(velocity, expected, 1.0, "orbit velocity (side from the spider's centre)")
	# In range: it stops and spits a web.
	var hits := _player_hits(t)
	var landed := await t.until(func() -> bool: return not hits.is_empty(), 3500.0)
	if not t.check(landed, "the spider's web never hit the player"):
		return
	var result: Dictionary = hits[0]["commit"]["result"]
	t.equal(int(result.get("actual_damage", 0)), SPIDER_WEB_HIT, "web damage")
	t.equal(result.get("applied_effects"), [{"effect_id": "knockback", "potency": 180.0}, {"effect_id": "web", "potency": SPIDER_WEB_MS}], "web hit effects")
	t.equal((hits[0]["commit"]["request"] as Dictionary).get("weapon_id"), "spider-web", "web weapon id")
	if not t.player().has_method(&"apply_web"):
		await t.steps(2)
		t.check(not _effects(t, "spider-web-cover").is_empty(), "no web cover on the player (fallback without apply_web)")
	# Pressured: inside 0.72 x 120 = 86.4 px it backs off, spiralling, at 80 x 1.08.
	# Wait for the spit's cooldown (attack state, no sequence), then step inside 0.72 x 120 px.
	var holding := await t.until(func() -> bool: return spider.get_runtime_state() == "attack" and not spider.is_attacking(), 3000.0)
	if not t.check(holding, "the spider never held between spits"):
		return
	t.teleport_player(spider.get_centre() + Vector2(-50.0, 0.0))
	await t.sim_wait(3.0 * STEP)
	t.equal(spider.get_runtime_state(), "flee", "spider state with the player 50 px away")
	var away := spider.body.velocity
	t.near(away.length(), SPIDER_SPEED * 1.08, 0.5, "retreat speed")
	t.check(away.dot(t.player().get_centre() - spider.get_centre()) < 0.0, "the spider does not move away from the player")


func test_brawler_melee_hit_spawns_its_impact_effect(t: TestContext) -> void:
	t.teleport_player(OPEN)
	var brawler := _spawn(t, "worm-brawler", OPEN + Vector2(30.0, 0.0))
	if brawler == null:
		return
	var hits := _player_hits(t)
	var started: Array = []
	brawler.attack_started.connect(func(payload: Dictionary) -> void: started.append({"now": t.now(), "payload": payload}))
	var landed := await t.until(func() -> bool: return not hits.is_empty(), 800.0)
	if not t.check(landed and not started.is_empty(), "the brawler never hit the player"):
		return
	t.equal(started[0]["payload"], {"ranged": false, "windupMs": 250.0}, "brawler attack_started payload")
	t.between(float(hits[0]["now"]) - float(started[0]["now"]), 250.0 - SLACK, 250.0 + SLACK, "brawler windup (ms)")
	t.equal(int((hits[0]["commit"]["result"] as Dictionary).get("actual_damage", 0)), BRAWLER_HIT, "brawler damage")
	t.equal((hits[0]["commit"]["result"] as Dictionary).get("applied_effects"), [{"effect_id": "knockback", "potency": 340.0}], "brawler knockback")
	await t.steps(1)
	var effects := _effects(t, "enemy-worm-brawler-hit")
	if t.equal(effects.size(), 1, "brawler impact effects"):
		var root := (effects[0] as Node).get_parent() as Node2D
		t.near_vec(FeetAnchor.phaser_position(root), brawler.get_centre() + Vector2.LEFT * BRAWLER_IMPACT_DISTANCE, 1.0, "impact effect position (22 px along the swing)")


func test_slow_scales_movement_and_skips_bosses(t: TestContext) -> void:
	t.teleport_player(OPEN)
	var worm := _spawn(t, "worm-swordsman", OPEN + Vector2(210.0, 0.0))
	if worm == null:
		return
	await t.steps(3)
	t.near_vec(worm.body.velocity, Vector2.LEFT * 75.0, 0.5, "chase velocity before the slow")
	worm.apply_slow(0.55, 400.0)
	await t.steps(2)
	t.check(worm.is_slowed(), "is_slowed() after apply_slow")
	t.near_vec(worm.body.velocity, Vector2.LEFT * 75.0 * 0.55, 0.5, "chase velocity while slowed")
	# A weaker slow does not replace a running stronger one; a longer one extends it.
	worm.apply_slow(0.8, 1000.0)
	await t.steps(2)
	t.near_vec(worm.body.velocity, Vector2.LEFT * 75.0 * 0.55, 0.5, "velocity after a weaker slow")
	worm.apply_slow(0.0, 1000.0)
	worm.apply_slow(1.0, 1000.0)
	await t.until(func() -> bool: return not worm.is_slowed(), 1200.0)
	await t.steps(2)
	t.near(worm.body.velocity.length(), 75.0, 0.5, "chase speed after the slow")
	# Bosses are never slowed.
	worm.rank = "boss"
	worm.apply_slow(0.5, 1000.0)
	t.check(not worm.is_slowed(), "a boss was slowed")
	# The world's slowEnemiesNear: only live population members near a point.
	var population := t.main.get("enemy_population") as EnemyPopulation
	if not t.check(population != null, "main has no enemy_population"):
		return
	var camp := _area(t, "level-1-starter-camp")
	var root := population.spawn_one(camp)
	if not t.check(root != null, "the starter camp did not spawn"):
		return
	var member := _script_of(root)
	t.equal(population.slow_enemies_near([member.get_centre() + Vector2(20.0, 0.0)], 26.0, 0.55, 400.0), 1, "enemies slowed near a point")
	t.check(member.is_slowed(), "the camp worm is not slowed")
	t.equal(population.slow_enemies_near([member.get_centre() + Vector2(30.0, 0.0)], 26.0, 0.55, 400.0), 0, "enemies slowed 30 px away")


func test_knockback_immunity_from_the_damage_rule(t: TestContext) -> void:
	t.teleport_player(OPEN)
	var worm := _spawn(t, "worm-swordsman", OPEN + Vector2(150.0, 0.0), true)
	if worm == null:
		return
	await t.steps(1)
	var router := Services.router()
	router.register_area(worm.damage_area, worm, {"priority": 0, "damageMultiplier": 1,
		"effectResponses": {"knockback": {"mode": "immune"}}}, ["enemy"])
	worm.body.velocity = Vector2.ZERO
	var result := _hit(t, worm, 10.0, 140.0)
	t.equal(result.get("status"), "accepted", "hit status")
	t.equal(result.get("rejected_effects"), [{"effect_id": "knockback", "reason": "immune"}], "rejected effects")
	t.near_vec(worm.body.velocity, Vector2.ZERO, 0.01, "no shove from an immune knockback")
	var start := worm.get_centre()
	await t.sim_wait(250.0)
	t.near_vec(worm.get_centre(), start, 0.5, "the stunned worm stays put")
	router.register_area(worm.damage_area, worm, {"priority": 0, "damageMultiplier": 1,
		"blockedWeaponTags": ["test"]}, ["enemy"])
	t.equal(_hit(t, worm, 10.0, 0.0).get("reason"), "source-blocked", "blocked weapon tag")


func test_every_world_enemy_type_spawns_and_fights(t: TestContext) -> void:
	var population := t.main.get("enemy_population") as EnemyPopulation
	if not t.check(population != null, "main has no enemy_population"):
		return
	population.allowed_types = PackedStringArray()
	# Through the camps: each level-1 area spawns its own types.
	for area_id: String in ["level-1-webwood", "level-1-autumn-grove", "level-1-south-meadow"]:
		var area := _area(t, area_id)
		var root := population.spawn_one(area)
		if t.check(root != null, "'%s' spawned nothing" % area_id):
			var allowed: Array = (area["data"]["enemies"] as Array).map(func(entry: Dictionary) -> String: return str(entry["type"]))
			t.check(allowed.has(_type_of(root)), "'%s' spawned '%s'" % [area_id, _type_of(root)])
			root.queue_free()
	await t.steps(2)
	# Each type, alone near the player, lands a hit.
	t.teleport_player(OPEN)
	for type_id: String in WORLD_TYPES:
		var offset := Vector2(30.0, 0.0) if type_id in ["worm-swordsman", "worm-brawler"] else Vector2(180.0, 0.0)
		var enemy := _spawn(t, type_id, t.player().get_centre() + offset)
		if enemy == null:
			continue
		var hits := _player_hits(t)
		var landed := await t.until(func() -> bool: return not hits.is_empty(), 2500.0)
		t.check(landed, "a %s never hit the player" % type_id)
		enemy.body.queue_free()
		for projectile: ProjectileScript in _projectiles(t):
			projectile.expire()
		await t.sim_wait(600.0)
		t.player().restore_run_state({"hp": t.player().get_max_hp()})
		t.teleport_player(OPEN)


func test_legacy_spawning_in_crystal_caverns(t: TestContext) -> void:
	if not t.check(t.main.travel_to("crystal-caverns", "west"), "travel to crystal-caverns was refused"):
		return
	var arrived := await t.until(func() -> bool: return t.world().map_id() == "crystal-caverns" and t.player() != null, 3000.0, 6000.0)
	if not t.check(arrived, "the player did not reach crystal-caverns"):
		return
	await t.steps(2)
	var population := t.main.get("enemy_population") as EnemyPopulation
	if not t.check(population != null and population.uses_legacy_spawning(), "crystal-caverns does not use legacy spawning"):
		return
	var centre := t.player().get_centre()
	t.equal(population.alive_count_all(), 8, "enemies seeded around the arrival (min(8, maxPopulation 16))")
	var size: Vector2 = t.world().world_rect().size
	for enemy: EnemyScript in population.live_enemies():
		var at := enemy.get_centre()
		var clamped := Vector2(clampf(at.x, 40.0, size.x - 40.0), clampf(at.y, 40.0, size.y - 40.0))
		t.near_vec(at, clamped, 0.5, "legacy spawn inside the 40 px inset")
		t.check(at.distance_to(centre) <= 500.0 + 1.0, "a legacy spawn %.0f px from the player" % at.distance_to(centre))
		t.check(enemy.get_spawn_area().is_empty(), "a legacy enemy has a spawn area")
	var seeded := population.alive_count_all()
	await t.sim_wait(1600.0)
	t.check(population.alive_count_all() > seeded, "no legacy spawn after the 1500 ms interval")
	# Beyond radius.max + 300 = 800 px from the player, legacy enemies are removed.
	var far := Vector2(size.x - 200.0, size.y - 200.0) if centre.x < size.x / 2.0 else Vector2(200.0, 200.0)
	var before: Array = population.live_enemies()
	t.teleport_player(far)
	await t.steps(3)
	var kept := 0
	for value: Variant in before:
		if not is_instance_valid(value):
			continue
		var enemy := value as EnemyScript
		if not enemy.body.is_queued_for_deletion() and enemy.get_centre().distance_to(far) > 800.0:
			kept += 1
	t.equal(kept, 0, "legacy enemies kept beyond the despawn radius")


# --- helpers ------------------------------------------------------------------------------------

## Spawns `character.<type>` with its centre at `centre` (no camp territory, no safe zones).
## `passive` zeroes its targeting radius and attack range.
static func _spawn(t: TestContext, type_id: String, centre: Vector2, passive: bool = false) -> EnemyScript:
	var root := t.world().spawn_at_phaser_position("character." + type_id, centre)
	if root == null:
		t.fail("character.%s did not spawn" % type_id)
		return null
	var enemy := _script_of(root)
	if enemy == null:
		t.fail("character.%s has no EnemyScript" % type_id)
		return null
	if passive:
		enemy.targeting_radius = 0.0
		enemy.attack_range = 0.0
	return enemy


static func _script_of(root: Node) -> EnemyScript:
	for child: Node in root.get_children():
		if child is EnemyScript:
			return child as EnemyScript
	return null


static func _type_of(root: Node) -> String:
	var path := root.scene_file_path.get_file().get_basename()
	return path


## Fires an arrow from `shooter`'s scene data at `from` along `direction`.
static func _fire(t: TestContext, shooter: EnemyScript, from: Vector2, direction: Vector2, speed: float, stick_ms: float) -> Node2D:
	var root := EnemyProjectiles.fire({"source": shooter, "position": from, "direction": direction, "speed": speed,
		"damage": 22.0, "knockback_strength": 180.0, "projectile_id": "worm-arrow", "asset_id": "", "stick_ms": stick_ms})
	if root == null:
		t.fail("the arrow did not spawn")
	return root


## Records every accepted hit on the player: [{"now", "commit"}].
static func _player_hits(t: TestContext) -> Array:
	var hits: Array = []
	t.player().damaged.connect(func(commit: Dictionary) -> void: hits.append({"now": t.now(), "commit": commit}))
	return hits


## Records every routed request at the player's hurtbox: [{"now", "result"}].
static func _routes_to_player(t: TestContext) -> Array:
	var routes: Array = []
	var hurtbox := t.player().get_damage_area()
	t.listen(Services.router().routed, func(payload: Dictionary) -> void:
		if (payload["request"] as Dictionary).get("target_area") == hurtbox:
			routes.append({"now": t.now(), "result": payload["result"]}))
	return routes


static func _projectiles(t: TestContext) -> Array:
	var found: Array = []
	for node: Node in t.world().entities_root().find_children("ProjectileScript", "Node", true, false):
		if node is ProjectileScript and (node as ProjectileScript).is_launched() and not node.is_queued_for_deletion():
			found.append(node)
	return found


static func _effects(t: TestContext, effect_id: String) -> Array:
	var found: Array = []
	for node: Node in t.world().entities_root().find_children("*", "Node", true, false):
		if node is EffectScript and (node as EffectScript).effect_id == effect_id and not node.is_queued_for_deletion():
			found.append(node)
	return found


static func _area(t: TestContext, area_id: String) -> Dictionary:
	for area: Dictionary in t.world().areas("enemy-spawn"):
		if str(area["id"]) == area_id:
			return area
	t.fail("no enemy-spawn area '%s'" % area_id)
	return {}


## One player hit on `enemy` through the router (its own activation), knock to the right.
static func _hit(t: TestContext, enemy: EnemyScript, damage: float, knockback: float) -> Dictionary:
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [player.get_damage_area()]
	var activation := router.begin_activation(player, areas)
	var effects: Array = []
	if knockback > 0.0:
		effects.append({"effect_id": "knockback", "potency": knockback})
	var result := router.route({"activation_id": activation, "source": player,
		"attack_area": player.get_damage_area(), "target_area": enemy.damage_area,
		"weapon_id": "test", "weapon_tags": ["test"], "damage_types": ["physical"],
		"base_damage": damage, "effects": effects,
		"impact": {"position": enemy.get_centre(), "knock": Vector2(1.0, 0.0)}})
	router.end_activation(activation)
	return result
