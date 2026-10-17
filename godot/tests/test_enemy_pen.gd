extends RefCounted
## The playground keeps its spawn areas as a testbed (roadmap 5.25, enemy spec 3.2): the game
## worlds' enemies are placed (test_camp.gd), but `playground-enemy-pen` still spawns on its
## `intervalMs` while the player is inside its pursue perimeter, and refills after a kill. The
## test lets only worm brawlers spawn (`allowed_types`, maxAlive 3) and makes each one passive as
## soon as it appears (targeting radius and attack range 0, its territory set up again with them:
## it never notices the player). Only the pen's own enemies count (other corners of the playground
## may have their own).

## run_tests.gd starts every test of this file in the playground.
const MAP_ID := "playground"

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const Perimeter := preload("res://game/shared/perimeter.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const EnemyPopulation := preload("res://game/enemy/enemy_population.gd")

const PEN_ID := "playground-enemy-pen"
const BRAWLER := "worm-brawler"
const SLACK := TestContext.STEP_MS + 0.01


func test_the_playground_pen_spawns_on_its_timer_and_refills(t: TestContext) -> void:
	var world := t.world()
	var pen := {}
	for area: Dictionary in world.areas(world.AREA_ENEMY_SPAWN):
		if str(area.get("id", "")) == PEN_ID:
			pen = area
	if not t.check(not pen.is_empty(), "the playground has no '%s' enemy-spawn area" % PEN_ID):
		return
	var population := t.main.get("enemy_population") as EnemyPopulation
	if not t.check(population != null, "main.gd has no enemy_population"):
		return
	population.allowed_types = PackedStringArray([BRAWLER])
	var interval := float((pen["data"] as Dictionary).get("intervalMs", 0.0))
	if not t.check(interval > 0.0, "the pen has no intervalMs"):
		return
	var stay: Dictionary = pen["stay_perimeter"]
	t.teleport_player(Perimeter.centre(stay))
	t.check(Perimeter.contains(pen["perimeter"], t.player().get_centre()), "the player is not inside the pen's pursue perimeter")
	var seen := {"spawns": []}
	var safe_zones := world.safe_zones()
	var track := func() -> bool:
		for enemy: EnemyScript in population.live_enemies():
			if enemy.targeting_radius > 0.0 and str(enemy.get_spawn_area().get("id", "")) == PEN_ID:
				# New: passive before its first step (its territory too), and its spawn time noted.
				enemy.targeting_radius = 0.0
				enemy.attack_range = 0.0
				enemy.configure_navigation(enemy.get_spawn_area(), safe_zones)
				(seen["spawns"] as Array).append({"now": t.now(), "enemy": enemy})
		return false
	var before := population.alive_count(PEN_ID)
	await t.until(func() -> bool:
		track.call()
		return (seen["spawns"] as Array).size() >= 2, 2.0 * interval + 1000.0)
	var spawns: Array = seen["spawns"]
	if not t.check(spawns.size() >= 2, "only %d brawler(s) came in %d ms in the pen" % [spawns.size(), 2.0 * interval + 1000.0]):
		return
	t.between(float(spawns[1]["now"]) - float(spawns[0]["now"]), interval - SLACK, interval + SLACK, "between two spawns (ms)")
	t.equal(population.alive_count(PEN_ID), before + 2, "alive in the pen after two spawns")
	for spawn: Dictionary in spawns:
		var enemy: EnemyScript = spawn["enemy"]
		t.equal(str(enemy.get_spawn_area().get("id", "")), PEN_ID, "a brawler's spawn area")
		t.check(Perimeter.distance_outside(stay, enemy.get_centre()) <= 2.0, "a brawler spawned outside the pen's stay perimeter")
	# A kill: the pen fills up again on its timer.
	var victim: EnemyScript = spawns[0]["enemy"]
	_kill(t, victim.damage_area)
	await t.steps(2)
	t.check(victim.is_defeated(), "the brawler survived a 999 hit")
	var after_kill := population.alive_count(PEN_ID)
	t.equal(after_kill, before + 1, "alive in the pen after the kill")
	await t.until(func() -> bool:
		track.call()
		return population.alive_count(PEN_ID) > after_kill, interval + 500.0)
	t.equal(population.alive_count(PEN_ID), after_kill + 1, "alive in the pen one interval after the kill")


## One big router hit (a stand-in activation), enough to beat any ordinary enemy.
static func _kill(t: TestContext, target_area: Area2D) -> void:
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
