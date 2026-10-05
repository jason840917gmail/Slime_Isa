extends RefCounted
## Starter camp population (docs/godot/specs/enemy.md section 3; world.md 3.1).
## level-1-starter-camp: pursue rect (488, 1069, 1288 x 881), stay rect (990, 1424, 280 x 181),
## worm-swordsman only, intervalMs 2500, maxPopulation 3. Spawns happen only while the player
## centre is inside the pursue rect, at the first tick with now > last_spawn + 2500 (last_spawn
## starts at 0), never above 3 alive; nothing is seeded when the player starts outside.

const TestContext := preload("res://tests/lib/test_context.gd")
const Perimeter := preload("res://game/shared/perimeter.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")

const CAMP_ID := "level-1-starter-camp"
const INTERVAL_MS := 2500.0
const MAX_POPULATION := 3
const PURSUE := Rect2(488.0, 1069.0, 1288.0, 881.0)
const STAY := Rect2(990.0, 1424.0, 280.0, 181.0)
## Inside the pursue rect, outside every safe zone, and more than 1.5 x the worm's 220 px aggro
## away from the stay rect, so the spawned worms never notice the player.
const INSIDE_POINT := Vector2(560.0, 1880.0)
const WORM_AGGRO := 220.0


func test_starter_camp_spawns_only_in_pursue_area_at_interval_up_to_cap(t: TestContext) -> void:
	var world := t.world()
	var population = t.main.get("enemy_population")
	if not t.check(population != null, "main.gd has no enemy_population"):
		return
	var camp := _camp(world.areas(world.AREA_ENEMY_SPAWN))
	if not t.check(not camp.is_empty(), "level-1 has no '%s' enemy-spawn area" % CAMP_ID):
		return
	var data: Dictionary = camp["data"]
	t.equal(float(data.get("intervalMs", 0)), INTERVAL_MS, "camp intervalMs")
	t.equal(int(data.get("maxPopulation", 0)), MAX_POPULATION, "camp maxPopulation")
	t.equal(_rect(camp["perimeter"]), PURSUE, "camp pursue rect")
	t.equal(_rect(camp["stay_perimeter"]), STAY, "camp stay rect")
	var outside := world.player_spawn_marker()
	# Preconditions of the chosen points.
	t.check(not PURSUE.has_point(outside), "the spawn marker %s is inside the pursue rect" % outside)
	t.check(Perimeter.contains(camp["perimeter"], INSIDE_POINT), "%s is not inside the pursue rect" % INSIDE_POINT)
	for zone: Dictionary in world.safe_zones():
		t.check(not _rect(zone).has_point(INSIDE_POINT), "%s is inside a safe zone" % INSIDE_POINT)
	var tile := float(world.dimensions()["tile_size"])
	t.check(not world.is_solid_tile(floori(INSIDE_POINT.x / tile), floori(INSIDE_POINT.y / tile)), "%s is on a solid tile" % INSIDE_POINT)
	t.check(_distance_to_rect(INSIDE_POINT, STAY) > WORM_AGGRO * 1.5, "%s is within sight of the camp" % INSIDE_POINT)
	if not t.failures.is_empty():
		return
	t.equal(population.alive_count(CAMP_ID), 0, "worms seeded with the player outside the camp")
	if not t.equal(_camp_enemies(t).size(), 0, "enemies in level-1 before the camp spawned any"):
		return

	var spawns: Array = [] # [{"now", "centre"}]
	var track := func() -> bool:
		var enemies := _camp_enemies(t)
		while spawns.size() < enemies.size():
			spawns.append({"now": t.now(), "centre": (enemies[spawns.size()] as EnemyScript).get_centre()})
		return false

	# 1. Inside from the start: the first worm at the first tick after 2500 ms, the second 2500 ms later.
	t.teleport_player(INSIDE_POINT)
	await t.until(func() -> bool:
		track.call()
		return spawns.size() >= 2, 2 * INTERVAL_MS + 500.0)
	if not t.check(spawns.size() >= 2, "only %d worm(s) spawned in %d ms inside the pursue rect" % [spawns.size(), 2 * INTERVAL_MS + 500.0]):
		return
	t.between(float(spawns[0]["now"]), INTERVAL_MS, INTERVAL_MS + TestContext.STEP_MS + 0.01, "first spawn time (ms)")
	t.between(float(spawns[1]["now"]) - float(spawns[0]["now"]), INTERVAL_MS, INTERVAL_MS + TestContext.STEP_MS + 0.01, "second spawn interval (ms)")

	# 2. Outside for longer than the interval: nothing spawns.
	t.teleport_player(outside)
	var left_at := t.now()
	await t.until(func() -> bool:
		track.call()
		return t.now() >= left_at + INTERVAL_MS + 1000.0, INTERVAL_MS + 1500.0)
	t.equal(spawns.size(), 2, "worms after %d ms with the player outside the pursue rect" % (INTERVAL_MS + 1000.0))

	# 3. Back inside: the interval has long passed, so the third worm comes on the next tick.
	t.teleport_player(INSIDE_POINT)
	var entered_at := t.now()
	await t.until(func() -> bool:
		track.call()
		return spawns.size() >= 3, 500.0)
	if not t.check(spawns.size() >= 3, "no worm spawned after re-entering the pursue rect"):
		return
	t.between(float(spawns[2]["now"]) - entered_at, 0.0, 2.0 * TestContext.STEP_MS + 0.01, "re-entry -> spawn (ms)")

	# 4. At the cap: nothing more, however long the player stays.
	var full_at := t.now()
	await t.until(func() -> bool:
		track.call()
		return t.now() >= full_at + INTERVAL_MS + 1000.0, INTERVAL_MS + 1500.0)
	t.equal(spawns.size(), MAX_POPULATION, "worms spawned in all (cap)")
	t.equal(population.alive_count(CAMP_ID), MAX_POPULATION, "alive camp worms at the cap")
	for spawn: Dictionary in spawns:
		var centre: Vector2 = spawn["centre"]
		t.check(STAY.grow(2.0).has_point(centre), "a worm spawned at %s, outside the stay rect %s" % [centre, STAY])


## Every live worm (EnemyScript in the "enemy" group) in spawn order.
static func _camp_enemies(t: TestContext) -> Array:
	var result: Array = []
	for node in t.tree.get_nodes_in_group(&"enemy"):
		if node is EnemyScript and not (node as EnemyScript).is_defeated():
			result.append(node)
	return result


static func _camp(areas: Array[Dictionary]) -> Dictionary:
	for area in areas:
		if str(area.get("id", "")) == CAMP_ID:
			return area
	return {}


static func _rect(perimeter: Dictionary) -> Rect2:
	return Rect2(float(perimeter.get("x", 0)), float(perimeter.get("y", 0)), float(perimeter.get("w", 0)), float(perimeter.get("h", 0)))


static func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(nearest)
