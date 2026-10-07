extends Node
class_name EnemyPopulation
## Enemy spawning (Phaser `enemies/AuthoredEnemyPopulationController.ts`, owned by
## CombatController): camps from enemy-spawn world areas (enemy spec section 3) and, in a world
## without spawn areas, the legacy player-relative spawning of `metadata.spawns` (enemy spec 18;
## crystal-caverns, icege). Also the world's `slowEnemiesNear` (enemy spec 15).
##
## Created by main.gd after the player is registered: `setup(...)`, `allowed_types = [...]`,
## `seed_initial()`. Runs in `_physics_process` (pausable) with `Services.now_ms()`.
## Player position tests use the player CENTRE (`Services.world().primary_target().centre`);
## spawn points are centres placed with `WorldService.spawn_at_phaser_position` (root at
## point + depth_anchor).
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")
const Perimeter := preload("res://game/shared/perimeter.gd")
const EnemyScript := preload("res://game/scripts/enemy.gd")

## AuthoredEnemyPopulationController.ts:206 / CombatController.ts:137.
const SPAWN_POINT_ATTEMPTS := 32
const INITIAL_SEED_COUNT := 8
## Legacy spawning: despawn radius = radius.max + 300 (CombatController.ts:122); spawn points stay
## 40 px inside the world (AuthoredEnemyPopulationController.ts:218-219).
const LEGACY_DESPAWN_MARGIN := 300.0
const LEGACY_WORLD_INSET := 40.0
## World definition metadata key of the legacy spawn table.
const SPAWNS_KEY := "spawns"
const SCENE_PREFIX := "character."

## Trial filter set by main.gd: only these enemy types spawn (types without a ported script are
## skipped; their areas still count for nothing). Empty = every type.
var allowed_types: PackedStringArray = PackedStringArray()

var _areas: Array[Dictionary] = []
## Safe zones handed to each spawned enemy (the world's enemy-safe-zone areas).
var _safe_zones: Array[Dictionary] = []
## Safe zones that reject spawn points: the areas plus `metadata.spawns.safeZones`
## (CombatController.safeZones, :269-274).
var _spawn_safe_zones: Array[Dictionary] = []
var _spawn_parent: Node
## Each member: {"enemy": EnemyScript, "root": Node2D, "type": String, "area_id": String ("" for
## legacy spawns)}.
var _members: Array[Dictionary] = []
var _last_spawn_at: Dictionary = {}
## `metadata.spawns` of the world definition ({} when none): {enemies, radius {min, max},
## intervalMs, maxPopulation, safeZones?}.
var _spawns: Dictionary = {}
var _legacy_last_spawn_at: float = 0.0
## Gameplay time of `setup` (the world load). Phaser's world simulation time starts at 0 there,
## so every spawn timer starts from it (SimClock keeps running across world travel).
var _world_started_at: float = 0.0


## Stores the enemy-spawn area records, the safe-zone perimeters and the parent for spawned
## enemies (WorldService.entities_root()), and reads the world's legacy `metadata.spawns`.
func setup(spawn_areas: Array[Dictionary], safe_zones: Array[Dictionary], spawn_parent: Node) -> void:
	_areas = spawn_areas
	_safe_zones = safe_zones
	_spawn_parent = spawn_parent
	_members.clear()
	_last_spawn_at.clear()
	_world_started_at = Services.now_ms()
	_legacy_last_spawn_at = _world_started_at
	_spawns = {}
	var world := Services.world()
	if world != null and is_instance_valid(world.definition):
		var spawns: Variant = world.definition.metadata.get(SPAWNS_KEY)
		if spawns is Dictionary:
			_spawns = spawns
	_spawn_safe_zones = safe_zones.duplicate()
	var extra: Variant = _spawns.get("safeZones", [])
	if extra is Array:
		for zone: Variant in extra:
			if zone is Dictionary:
				_spawn_safe_zones.append(zone)


## True when this world spawns the legacy way: no spawn areas, a `metadata.spawns` table.
func uses_legacy_spawning() -> bool:
	return _areas.is_empty() and not _spawns.is_empty()


## `seed(min(8, spawns.maxPopulation ?? 8))` (enemy spec 3.2 and 18): with areas, for each area
## whose pursue perimeter contains the player centre spawn `min(count, maxPopulation)` at once
## (does not set last_spawn_at); with legacy spawning, `count` around the player. `max_count < 0`
## uses the default count. Warms the scenes it may spawn first.
func seed_initial(max_count: int = -1) -> void:
	warm_scenes()
	if max_count < 0:
		max_count = mini(INITIAL_SEED_COUNT, int(_spawns.get("maxPopulation", INITIAL_SEED_COUNT)))
	var player_centre: Variant = _player_centre()
	if player_centre == null:
		return
	if uses_legacy_spawning():
		for _i in max_count:
			spawn_legacy_one()
		return
	for area in _areas:
		if not Perimeter.contains(area.get("perimeter", {}), player_centre):
			continue
		for _i in mini(max_count, _max_population(area)):
			spawn_one(area)


## Loads `character.<type>` for every type this population may spawn (Phaser loads every scene
## before the world starts), so the first spawn of a type does not read it mid-step.
func warm_scenes() -> void:
	var world := Services.world()
	if world == null:
		return
	var types: Dictionary = {}
	var tables: Array = [_spawns.get("enemies", [])] if uses_legacy_spawning() else []
	for area in _areas:
		tables.append(_area_data(area).get("enemies", []))
	for table: Variant in tables:
		if not table is Array:
			continue
		for entry: Variant in table:
			if entry is Dictionary:
				var type_id := str((entry as Dictionary).get("type", ""))
				if not type_id.is_empty() and (allowed_types.is_empty() or allowed_types.has(type_id)):
					types[type_id] = true
	for type_id: String in types:
		world.packed_scene(SCENE_PREFIX + type_id)


## `update(time)` (enemy spec 3.2 and 18; times from the world load): drop freed and defeated
## members; legacy members
## beyond the despawn radius are freed; for each area containing the player centre, spawn one when
## `now > last_spawn_at + intervalMs` and alive < maxPopulation, then set last_spawn_at = now (even
## when the spawn failed); legacy spawning does the same with the world-wide count.
func _physics_process(_delta: float) -> void:
	var player_centre: Variant = _player_centre()
	if player_centre == null:
		return
	# Freed members are forgotten; defeated ones too (their bodies free themselves 800 ms later).
	# Camp members are never despawned by distance; legacy ones beyond the despawn radius are.
	var despawn_radius := _legacy_radius("max") + LEGACY_DESPAWN_MARGIN
	var kept: Array[Dictionary] = []
	for member in _members:
		if not _member_alive(member):
			continue
		if str(member["area_id"]).is_empty() and not _spawns.is_empty():
			var enemy := member["enemy"] as EnemyScript
			if enemy.get_centre().distance_to(player_centre) > despawn_radius:
				(member["root"] as Node).queue_free()
				continue
		kept.append(member)
	_members = kept

	var now := Services.now_ms()
	if uses_legacy_spawning():
		var interval := float(_spawns.get("intervalMs", 0.0))
		if now > _legacy_last_spawn_at + interval and alive_count_all() < int(_spawns.get("maxPopulation", 0)):
			spawn_legacy_one()
			_legacy_last_spawn_at = now
		return
	for area in _areas:
		if not Perimeter.contains(area.get("perimeter", {}), player_centre):
			continue
		var area_id := _area_id(area)
		var last_spawn_at := float(_last_spawn_at.get(area_id, _world_started_at))
		var interval_ms := float(_area_data(area).get("intervalMs", 0.0))
		if now > last_spawn_at + interval_ms and alive_count(area_id) < _max_population(area):
			spawn_one(area)
			_last_spawn_at[area_id] = now


## `spawnOne(area)` (enemy spec 3.2): candidate types under their maxAlive (and in
## allowed_types), weighted pick, up to SPAWN_POINT_ATTEMPTS random stay-perimeter points not in
## a safe zone, instance `character.<type>`, call `configure_navigation(area, safe_zones)` on its
## EnemyScript before its first physics step, record the member. Returns the root or null.
func spawn_one(area: Dictionary) -> Node2D:
	var area_id := _area_id(area)
	var picked_type := _pick_type(_area_data(area).get("enemies", []), area_id)
	if picked_type.is_empty():
		return null
	var point: Variant = _find_spawn_point(area)
	if point == null:
		return null
	return _spawn(picked_type, point, area)


## Legacy `spawnOne()` (enemy spec 18): a weighted type from `metadata.spawns.enemies`, a point
## `min..max` px from the player centre at a random angle, clamped 40 px inside the world and
## outside the safe zones (32 tries); the enemy has no spawn area (no territory).
func spawn_legacy_one() -> Node2D:
	var picked_type := _pick_type(_spawns.get("enemies", []), "")
	if picked_type.is_empty():
		return null
	var point: Variant = _find_legacy_spawn_point()
	if point == null:
		return null
	return _spawn(picked_type, point, {})


## Alive (not defeated, not freed) members of `area_id` ("" = legacy spawns), optionally of one type.
func alive_count(area_id: String, type_id: String = "") -> int:
	var count := 0
	for member in _members:
		if member["area_id"] != area_id:
			continue
		if not type_id.is_empty() and member["type"] != type_id:
			continue
		if _member_alive(member):
			count += 1
	return count


## Alive members of every area and the legacy spawns (Phaser `count`).
func alive_count_all() -> int:
	var count := 0
	for member in _members:
		if _member_alive(member):
			count += 1
	return count


## The live members' EnemyScripts.
func live_enemies() -> Array[EnemyScript]:
	var result: Array[EnemyScript] = []
	for member in _members:
		if _member_alive(member):
			result.append(member["enemy"] as EnemyScript)
	return result


## `slowEnemiesNear` (UniversalSceneWorldController.ts:1236-1249, enemy spec 15): every live enemy
## of this population whose centre is within `radius` of any point (old Phaser positions) gets
## `apply_slow(multiplier, duration_ms)`. Returns how many. Bosses are not members.
func slow_enemies_near(points: Array, radius: float, multiplier: float, duration_ms: float) -> int:
	if points.is_empty():
		return 0
	var radius_squared := radius * radius
	var slowed := 0
	for enemy in live_enemies():
		var at := enemy.get_centre()
		var near := false
		for point: Variant in points:
			if point is Vector2 and (point as Vector2).distance_squared_to(at) <= radius_squared:
				near = true
				break
		if not near:
			continue
		enemy.apply_slow(multiplier, duration_ms)
		slowed += 1
	return slowed


# --- private ----------------------------------------------------------------------------------

## Weighted pick among the entries of `table` whose `maxAlive` is not reached by live members of
## that type in `area_id` (and in allowed_types): roll in [0, total) and walk the entries until the
## roll is used up. "" when none qualifies.
func _pick_type(table: Variant, area_id: String) -> String:
	var candidates: Array[Dictionary] = []
	if table is Array:
		for entry_value: Variant in table:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var type_id := str(entry.get("type", ""))
			if type_id.is_empty():
				continue
			if not allowed_types.is_empty() and not allowed_types.has(type_id):
				continue
			var max_alive: Variant = entry.get("maxAlive")
			if (max_alive is int or max_alive is float) and alive_count(area_id, type_id) >= int(max_alive):
				continue
			candidates.append(entry)
	if candidates.is_empty():
		return ""
	var total_weight := 0.0
	for entry in candidates:
		total_weight += float(entry.get("weight", 0.0))
	var roll := randf() * total_weight
	var picked: Dictionary = candidates[0]
	for entry in candidates:
		roll -= float(entry.get("weight", 0.0))
		if roll <= 0.0:
			picked = entry
			break
	return str(picked.get("type", ""))


## Instances `character.<type>` at `point` (old Phaser centre), configures its navigation and
## records the member. Null on failure.
func _spawn(type_id: String, point: Vector2, area: Dictionary) -> Node2D:
	var world := Services.world()
	if world == null:
		return null
	var root := world.spawn_at_phaser_position(SCENE_PREFIX + type_id, point, _spawn_parent)
	if root == null:
		push_error("EnemyPopulation: no converted scene for enemy type '%s'" % type_id)
		return null
	var enemy := _find_enemy_script(root)
	if enemy == null:
		push_error("EnemyPopulation: scene 'character.%s' has no EnemyScript" % type_id)
		root.queue_free()
		return null
	enemy.configure_navigation(area, _safe_zones)
	_members.append({"enemy": enemy, "root": root, "type": type_id, "area_id": _area_id(area)})
	return root


## `findSpawnPoint` (AuthoredEnemyPopulationController.ts:203-214): up to 32 random points in the
## stay perimeter, rejecting any inside a safe zone (inclusive). Old Phaser centre, or null.
func _find_spawn_point(area: Dictionary) -> Variant:
	var stay: Variant = area.get("stay_perimeter", {})
	if not stay is Dictionary or (stay as Dictionary).is_empty():
		push_error("EnemyPopulation: spawn area '%s' has no stay perimeter" % _area_id(area))
		return null
	for _attempt in SPAWN_POINT_ATTEMPTS:
		var candidate := Perimeter.random_point(stay)
		if not _in_safe_zone(candidate):
			return candidate
	return null


## AuthoredEnemyPopulationController.ts:216-224: random angle, distance min..max from the player
## centre, clamped 40 px inside the world; rejected inside a safe zone. Null after 32 tries.
func _find_legacy_spawn_point() -> Variant:
	var player_centre: Variant = _player_centre()
	var world := Services.world()
	if player_centre == null or world == null:
		return null
	var size := world.world_rect().size
	var min_radius := _legacy_radius("min")
	var max_radius := _legacy_radius("max")
	for _attempt in SPAWN_POINT_ATTEMPTS:
		var angle := randf() * TAU
		var distance := min_radius + randf() * (max_radius - min_radius)
		var x := clampf((player_centre as Vector2).x + cos(angle) * distance, LEGACY_WORLD_INSET, size.x - LEGACY_WORLD_INSET)
		var y := clampf((player_centre as Vector2).y + sin(angle) * distance, LEGACY_WORLD_INSET, size.y - LEGACY_WORLD_INSET)
		var candidate := Vector2(x, y)
		if not _in_safe_zone(candidate):
			return candidate
	return null


func _in_safe_zone(point: Vector2) -> bool:
	for zone in _spawn_safe_zones:
		var x := float(zone.get("x", 0.0))
		var y := float(zone.get("y", 0.0))
		if point.x >= x and point.x <= x + float(zone.get("w", 0.0)) and point.y >= y and point.y <= y + float(zone.get("h", 0.0)):
			return true
	return false


## `metadata.spawns.radius.<key>` (0 when absent).
func _legacy_radius(key: String) -> float:
	var radius: Variant = _spawns.get("radius", {})
	return float((radius as Dictionary).get(key, 0.0)) if radius is Dictionary else 0.0


func _find_enemy_script(root: Node) -> EnemyScript:
	for child in root.get_children():
		if child is EnemyScript:
			return child as EnemyScript
	return null


func _member_alive(member: Dictionary) -> bool:
	var root: Variant = member.get("root")
	var enemy: Variant = member.get("enemy")
	if not is_instance_valid(root) or not is_instance_valid(enemy):
		return false
	if (root as Node).is_queued_for_deletion():
		return false
	return not (enemy as EnemyScript).is_defeated()


## Player centre (old Phaser position) or null when no player is registered.
func _player_centre() -> Variant:
	var world := Services.world()
	if world == null:
		return null
	var target := world.primary_target()
	if target.is_empty() or not target.get("centre") is Vector2:
		return null
	return target["centre"]


static func _area_id(area: Dictionary) -> String:
	return str(area.get("id", ""))


static func _area_data(area: Dictionary) -> Dictionary:
	var data: Variant = area.get("data", {})
	return data if data is Dictionary else {}


static func _max_population(area: Dictionary) -> int:
	return int(_area_data(area).get("maxPopulation", 0))
