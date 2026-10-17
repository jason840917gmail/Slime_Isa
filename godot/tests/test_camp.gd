extends RefCounted
## The starter camp's placed worms (roadmap 5.25; docs/godot/specs/enemy.md section 3.3; world.md
## 3.1). Level-1 starts in its village chunk C4 (`level-1-c4`, level-1's own coordinates), where
## `level-1-starter-camp` is an enemy-wander area (the old camp's stay rect (990, 1424, 280 x 181);
## it was an enemy-spawn area: worm swordsmen every 2500 ms up to 3 while the player was inside its
## pursue rect) shared by three placed worm swordsmen under `Enemies`. They stand there as soon as
## the chunk is built, wherever the player is; nothing spawns on a timer, even with the player
## where the old camp spawned; a beaten one stays beaten while the slime is in the chunk and is
## back once the chunk is built again (a travel into it, as walking back in does). The
## playground's pen still spawns on its timer (test_enemy_pen.gd).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const Perimeter := preload("res://game/shared/perimeter.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")
const EnemyPopulation := preload("res://game/enemy/enemy_population.gd")
const PlacedEnemyScript := preload("res://game/enemy/placed_enemy.gd")

const MAP := "level-1-c4"
const CAMP_ID := "level-1-starter-camp"
const WORM := "worm-swordsman"
const WORMS := 3
const STAY := Rect2(990.0, 1424.0, 280.0, 181.0)
## The old camp's interval: nothing may spawn after it, nor after twice it.
const OLD_INTERVAL_MS := 2500.0
## Inside the old pursue rect (488, 1069, 1288 x 881), outside every safe zone, and more than 1.5 x
## the worm's 220 px aggro away from the camp, so the worms never notice the player.
const INSIDE_POINT := Vector2(560.0, 1880.0)
const WORM_AGGRO := 220.0
## How far a worm may have wandered from its spot in the few steps before a check.
const SPOT_SLACK := 6.0


func test_starter_camp_worms_are_placed_and_stand_at_once(t: TestContext) -> void:
	var world := t.world()
	t.equal(world.map_id(), MAP, "level-1's starting chunk")
	t.equal(world.areas(world.AREA_ENEMY_SPAWN).size(), 0, "enemy-spawn areas in %s" % MAP)
	t.equal(world.definition.metadata.get("spawns"), null, "%s's spawns table" % MAP)
	var camp := _area(world.areas(world.AREA_ENEMY_WANDER), CAMP_ID)
	if not t.check(not camp.is_empty(), "%s has no '%s' enemy-wander area" % [MAP, CAMP_ID]):
		return
	t.equal(_rect(camp["perimeter"]), STAY, "the camp's wander rect")
	t.equal(_rect(camp["stay_perimeter"]), STAY, "the camp's stay rect (its territory home)")
	var population := _population(t)
	if population == null:
		return
	t.check(not population.uses_legacy_spawning(), "%s spawns the legacy way" % MAP)
	# The player starts far from the camp (the spawn marker, in the village's safe zone): the worms
	# stand anyway.
	t.check(not STAY.grow(WORM_AGGRO).has_point(t.player().get_centre()), "the player starts next to the camp")
	var placed := _camp_nodes(population)
	if not t.equal(placed.size(), WORMS, "placed enemies naming the camp"):
		return
	for node in placed:
		t.equal(node.enemy_type, WORM, "%s's type" % node.name)
		t.equal(str(node.get_parent().name), "Enemies", "%s's parent" % node.name)
		if not t.check(node.is_standing(), "%s does not stand once the chunk is built" % node.name):
			continue
		var enemy := node.get_enemy() as EnemyScript
		t.near_vec(enemy.body.global_position, node.global_position, SPOT_SLACK, "%s's feet on its spot" % node.name)
		t.check(STAY.grow(2.0).has_point(enemy.get_centre()), "%s stands outside the camp rect (%s)" % [node.name, enemy.get_centre()])
		t.equal(str(enemy.get_spawn_area().get("id", "")), CAMP_ID, "%s's territory" % node.name)
		t.near_vec(node.wander_centre(), STAY.get_center(), 1.0, "%s's wander centre" % node.name)
	t.equal(population.alive_placed_count(CAMP_ID), WORMS, "standing camp worms")
	t.equal(_live_worms(t).size(), WORMS, "live enemies in %s" % MAP)


func test_beaten_worms_stay_beaten_until_the_chunk_is_built_again(t: TestContext) -> void:
	var world := t.world()
	var population := _population(t)
	if population == null:
		return
	var population_id := population.get_instance_id()
	var tile := float(world.dimensions()["tile_size"])
	t.check(not world.is_solid_tile(floori(INSIDE_POINT.x / tile), floori(INSIDE_POINT.y / tile)), "%s is on a solid tile" % INSIDE_POINT)
	for zone: Dictionary in world.safe_zones():
		t.check(not _rect(zone).has_point(INSIDE_POINT), "%s is inside a safe zone" % INSIDE_POINT)
	t.check(_distance_to_rect(INSIDE_POINT, STAY) > WORM_AGGRO * 1.5, "%s is within sight of the camp" % INSIDE_POINT)
	if not t.failures.is_empty():
		return
	# Where the old camp spawned, for longer than two of its intervals: nobody comes.
	t.teleport_player(INSIDE_POINT)
	await t.sim_wait(2.0 * OLD_INTERVAL_MS + 500.0)
	t.equal(_live_worms(t).size(), WORMS, "live worms after %d ms in the old pursue rect" % (2.0 * OLD_INTERVAL_MS + 500.0))
	# One beaten: it stays beaten, and nothing takes its place.
	var placed := _camp_nodes(population)
	if not t.equal(placed.size(), WORMS, "placed camp worms"):
		return
	var beaten: PlacedEnemyScript = placed[0]
	var enemy := beaten.get_enemy() as EnemyScript
	if not t.check(enemy != null, "%s has no enemy" % beaten.name):
		return
	_kill(t, enemy.damage_area)
	await t.steps(2)
	t.check(enemy.is_defeated(), "the worm survived a 999 hit")
	t.check(not beaten.is_standing(), "the beaten worm still stands")
	await t.sim_wait(2.0 * OLD_INTERVAL_MS + 1000.0)
	t.equal(population.alive_placed_count(CAMP_ID), WORMS - 1, "standing camp worms %d ms after one was beaten" % (2.0 * OLD_INTERVAL_MS + 1000.0))
	t.equal(_live_worms(t).size(), WORMS - 1, "live enemies in %s" % MAP)
	t.check(not beaten.is_standing(), "the beaten worm came back while the slime stayed in the chunk")
	# The chunk built again (re-entering it, a load): all three stand on their spots again.
	if not t.check(t.main.travel_to(MAP, "south"), "travel into %s was refused" % MAP):
		return
	var rebuilt := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == MAP and t.player() != null, 3000.0, 6000.0)
	if not t.check(rebuilt, "%s was not built again" % MAP):
		return
	await t.steps(2)
	var again := _population(t)
	if again == null:
		return
	t.check(again.get_instance_id() != population_id, "the population was not made anew")
	t.equal(again.alive_placed_count(CAMP_ID), WORMS, "standing camp worms after the chunk was built again")
	for node in _camp_nodes(again):
		if t.check(node.is_standing(), "%s is not back" % node.name):
			t.near_vec((node.get_enemy() as EnemyScript).body.global_position, node.global_position, SPOT_SLACK, "%s back on its spot" % node.name)


# --- helpers ------------------------------------------------------------------------------------

static func _population(t: TestContext) -> EnemyPopulation:
	var population := t.main.get("enemy_population") as EnemyPopulation
	t.check(population != null, "main.gd has no enemy_population")
	return population


## The placed enemies naming the camp, in tree order.
static func _camp_nodes(population: EnemyPopulation) -> Array[PlacedEnemyScript]:
	var nodes: Array[PlacedEnemyScript] = []
	for node: PlacedEnemyScript in population.placed_enemies():
		if node.wander_area_id == CAMP_ID:
			nodes.append(node)
	return nodes


## Every live (not defeated) EnemyScript in the "enemy" group.
static func _live_worms(t: TestContext) -> Array:
	var result: Array = []
	for node in t.tree.get_nodes_in_group(&"enemy"):
		if node is EnemyScript and not (node as EnemyScript).is_defeated() and not node.is_queued_for_deletion():
			result.append(node)
	return result


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


static func _area(areas: Array[Dictionary], area_id: String) -> Dictionary:
	for area in areas:
		if str(area.get("id", "")) == area_id:
			return area
	return {}


static func _rect(perimeter: Dictionary) -> Rect2:
	return Rect2(float(perimeter.get("x", 0)), float(perimeter.get("y", 0)), float(perimeter.get("w", 0)), float(perimeter.get("h", 0)))


static func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(nearest)
