extends RefCounted
## Health, destruction and persistence of a world object (Phaser `DestructibleScript.ts`,
## world-objects spec 3). No scene uses `game.destructible` on its own, so the logic lives here
## and `resource_node.gd` owns one; a future `destructible.gd` would wrap the same helper.
## Records live in `RunState.map_record(map_id).resources[instance_id]` (spec 9).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const ResourceRespawn := preload("res://game/world_objects/resource_respawn.gd")

var map_id: String
var instance_id: String
var max_health: float
var health: float
var destroyed: bool = false
## Resource nodes regrow (their destruction starts the regrow timer); plain destructibles do not.
var regrows: bool


## `DestructibleScript` constructor (:82-84): `max(1, max)`, `initial > 0 ? min(max, initial) : max`.
func _init(map: String, instance: String, maximum: float, initial: float, regrowing: bool) -> void:
	map_id = map
	instance_id = instance
	max_health = maxf(1.0, maximum)
	health = minf(max_health, initial) if initial > 0.0 else max_health
	regrows = regrowing


## Spec 3.2 steps 2-3: reads the record (regrowth resolved when `regrows`, rewritten or cleared on
## change), applies it and returns it ({} when none).
func load() -> Dictionary:
	var run := Services.run()
	if run == null:
		return {}
	var record := run.resource_record(map_id, instance_id)
	if regrows and not record.is_empty():
		var resolution := ResourceRespawn.resolve(record, ResourceRespawn.now_epoch_ms(), ResourceRespawn.respawn_ms())
		if bool(resolution["changed"]):
			record = resolution["record"]
			if record.is_empty():
				run.clear_resource_record(map_id, instance_id)
			else:
				run.set_resource_record(map_id, instance_id, record)
	if record.is_empty():
		return {}
	destroyed = str(record.get("stage", "node")) != "node"
	health = 0.0 if destroyed else clampf(float(record.get("value", max_health)), 0.0, max_health)
	return record


## `health = max(0, health - actual)`.
func apply(actual: float) -> void:
	health = maxf(0.0, health - actual)


## Record {stage "node", value health} (persistHealth).
func save() -> void:
	var run := Services.run()
	if run != null:
		run.set_resource_record(map_id, instance_id, {"stage": "node", "value": health})


## `destroyObject` (:179-185): false when already destroyed. Writes {stage "depleted", value 0}
## and, when `regrows`, the regrow timer `now + respawnMs`.
func mark_destroyed() -> bool:
	if destroyed:
		return false
	destroyed = true
	health = 0.0
	var run := Services.run()
	if run != null:
		var record := {"stage": "depleted", "value": 0.0}
		if regrows:
			record["respawn_ready_at_epoch_ms"] = ResourceRespawn.now_epoch_ms() + ResourceRespawn.respawn_ms()
		run.set_resource_record(map_id, instance_id, record)
	return true
