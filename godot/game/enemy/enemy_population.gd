extends Node
class_name EnemyPopulation
## Camp spawning from enemy-spawn world areas (Phaser `enemies/AuthoredEnemyPopulationController.ts`,
## owned by CombatController). Enemy spec section 3.
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

## Trial filter set by main.gd: only these enemy types spawn (types without a ported script are
## skipped; their areas still count for nothing). Empty = every type.
var allowed_types: PackedStringArray = PackedStringArray()

var _areas: Array[Dictionary] = []
var _safe_zones: Array[Dictionary] = []
var _spawn_parent: Node
## Each member: {"enemy": EnemyScript, "root": Node2D, "type": String, "area_id": String}.
var _members: Array[Dictionary] = []
var _last_spawn_at: Dictionary = {}


## Stores the enemy-spawn area records, the safe-zone perimeters and the parent for spawned
## enemies (WorldService.entities_root()).
func setup(spawn_areas: Array[Dictionary], safe_zones: Array[Dictionary], spawn_parent: Node) -> void:
	_areas = spawn_areas
	_safe_zones = safe_zones
	_spawn_parent = spawn_parent
	_members.clear()
	_last_spawn_at.clear()


## `seed(8)` (enemy spec 3.2): for each area whose pursue perimeter contains the player centre,
## spawn `min(max_count, maxPopulation)` immediately (does not set last_spawn_at).
func seed_initial(max_count: int = INITIAL_SEED_COUNT) -> void:
	var player_centre: Variant = _player_centre()
	if player_centre == null:
		return
	for area in _areas:
		if not Perimeter.contains(area.get("perimeter", {}), player_centre):
			continue
		for _i in mini(max_count, _max_population(area)):
			spawn_one(area)


## `update(time)` (enemy spec 3.2): drop freed and defeated members; for each area containing
## the player centre, spawn one when `now > last_spawn_at + intervalMs` and alive < maxPopulation,
## then set last_spawn_at = now (even when the spawn failed).
func _physics_process(_delta: float) -> void:
	var player_centre: Variant = _player_centre()
	if player_centre == null:
		return
	# Freed members are forgotten; defeated ones too (their bodies free themselves 800 ms later).
	# Camp members are never despawned by distance.
	var kept: Array[Dictionary] = []
	for member in _members:
		if _member_alive(member):
			kept.append(member)
	_members = kept

	var now := Services.now_ms()
	for area in _areas:
		if not Perimeter.contains(area.get("perimeter", {}), player_centre):
			continue
		var area_id := _area_id(area)
		var last_spawn_at := float(_last_spawn_at.get(area_id, 0.0))
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
	var candidates: Array[Dictionary] = []
	var entries: Variant = _area_data(area).get("enemies", [])
	if entries is Array:
		for entry_value: Variant in entries:
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
		return null

	# Weighted pick: roll in [0, total) and walk the entries until the roll is used up.
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
	var picked_type := str(picked.get("type", ""))

	var point: Variant = _find_spawn_point(area)
	if point == null:
		return null

	var world := Services.world()
	if world == null:
		return null
	var root := world.spawn_at_phaser_position("character." + picked_type, point, _spawn_parent)
	if root == null:
		push_error("EnemyPopulation: no converted scene for enemy type '%s'" % picked_type)
		return null
	var enemy := _find_enemy_script(root)
	if enemy == null:
		push_error("EnemyPopulation: scene 'character.%s' has no EnemyScript" % picked_type)
		root.queue_free()
		return null
	enemy.configure_navigation(area, _safe_zones)
	_members.append({"enemy": enemy, "root": root, "type": picked_type, "area_id": area_id})
	return root


## Alive (not defeated, not freed) members of `area_id`, optionally of one type.
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


# --- private ----------------------------------------------------------------------------------

## `findSpawnPoint` (AuthoredEnemyPopulationController.ts:203-214): up to 32 random points in the
## stay perimeter, rejecting any inside a safe zone (inclusive). Old Phaser centre, or null.
func _find_spawn_point(area: Dictionary) -> Variant:
	var stay: Variant = area.get("stay_perimeter", {})
	if not stay is Dictionary or (stay as Dictionary).is_empty():
		push_error("EnemyPopulation: spawn area '%s' has no stay perimeter" % _area_id(area))
		return null
	for _attempt in SPAWN_POINT_ATTEMPTS:
		var candidate := Perimeter.random_point(stay)
		var blocked := false
		for zone in _safe_zones:
			if candidate.x >= float(zone.get("x", 0.0)) and candidate.x <= float(zone.get("x", 0.0)) + float(zone.get("w", 0.0)) 					and candidate.y >= float(zone.get("y", 0.0)) and candidate.y <= float(zone.get("y", 0.0)) + float(zone.get("h", 0.0)):
				blocked = true
				break
		if not blocked:
			return candidate
	return null


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
