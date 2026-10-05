extends RefCounted
## Objective matchers (Phaser `quests/matchers/ObjectiveMatchers.ts`; quests spec 2.5): which input
## event advances which objective kind, by how much, and the fact id that makes it count once.
##
## `match_objective(objective, event, payload, consumed)` returns {"matched": bool, "amount": int,
## "fact_id": String ("" = none)}. `consumed` is the record's `consumed_fact_ids` ({objective id:
## [fact ids]}): a fact already consumed for this objective does not match. Payload keys are
## Phaser's camelCase.
##
## Owner: quests.

const QuestEvents := preload("res://game/quests/quest_events.gd")

## Objective kind -> the input event it listens to (OBJECTIVE_MATCHERS).
const EVENT_BY_KIND := {
	"collect": QuestEvents.COLLECTIBLE_COLLECTED,
	"kill": QuestEvents.ENEMY_DIED,
	"talk-to-npc": QuestEvents.NPC_TALKED,
	"craft-item": QuestEvents.CRAFT_COMPLETED,
	"escort-character": QuestEvents.ESCORT_COMPLETED,
	"defeat-boss": QuestEvents.BOSS_DEFEATED,
	"activate-object": QuestEvents.OBJECT_ACTIVATED,
	"survive-duration": QuestEvents.SURVIVAL_COMPLETED,
	"place-item": QuestEvents.FURNITURE_PLACED,
	"discover-area": QuestEvents.AREA_ENTER,
	"use-control": QuestEvents.CONTROL_USED,
}


static func match_objective(objective: Dictionary, event: StringName, payload: Dictionary, consumed: Dictionary) -> Dictionary:
	var kind := str(objective.get("kind", ""))
	if not EVENT_BY_KIND.has(kind) or EVENT_BY_KIND[kind] != event:
		return _no()
	var result := _match(kind, objective, payload)
	if not bool(result["matched"]) or str(result["fact_id"]).is_empty():
		return result
	var facts: Variant = consumed.get(str(objective.get("id", "")), [])
	if facts is Array and str(result["fact_id"]) in (facts as Array):
		return _no()
	return result


static func _match(kind: String, objective: Dictionary, payload: Dictionary) -> Dictionary:
	match kind:
		"collect":
			var quantity: Variant = payload.get("quantity")
			if not bool(payload.get("recovered", false)) and _has(objective, "itemIds", payload.get("itemId")) and _positive_int(quantity):
				return _yes(int(quantity))
		"kill":
			if _values_include(objective, "enemyKinds", payload.get("kind")) and _values_include(objective, "areaIds", payload.get("areaId")) \
					and _tags_include_all(objective, payload.get("tags")):
				return _yes()
		"talk-to-npc":
			if _has(objective, "npcIds", payload.get("npcId")):
				return _yes()
		"craft-item":
			var crafted: Variant = payload.get("quantity")
			if _has(objective, "itemIds", payload.get("itemId")) and _values_include(objective, "recipeIds", payload.get("recipeId")) \
					and _positive_int(crafted):
				return _yes(int(crafted))
		"escort-character":
			if _values_include(objective, "escortIds", payload.get("escortId")) and _values_include(objective, "characterIds", payload.get("characterId")) \
					and _values_include(objective, "destinationIds", payload.get("destinationId", "")):
				return _yes(1, _fact(payload, "runId", "escortId"))
		"defeat-boss":
			if _has(objective, "bossIds", payload.get("bossId")):
				return _yes(1, _fact(payload, "factId", "bossId"))
		"activate-object":
			if _values_include(objective, "objectIds", payload.get("objectId")) and _values_include(objective, "instanceIds", payload.get("instanceId")) \
					and _values_include(objective, "areaIds", payload.get("areaId")):
				return _yes(1, str(payload.get("instanceId", "")))
		"survive-duration":
			var duration: Variant = payload.get("durationMs")
			if _has(objective, "encounterIds", payload.get("encounterId")) and (duration is int or duration is float) \
					and is_finite(float(duration)) and float(duration) >= float(objective.get("requiredDurationMs", 0)):
				return _yes(1, _fact(payload, "factId", "encounterId"))
		"place-item":
			if _has(objective, "itemIds", payload.get("itemId")):
				return _yes(1, str(payload.get("placementId", "")))
		"discover-area":
			if _has(objective, "areaIds", payload.get("areaId")):
				return _yes(1, str(payload.get("areaId", "")))
		"use-control":
			if _has(objective, "controlIds", payload.get("controlId")):
				return _yes(1, str(payload.get("controlId", "")))
	return _no()


## `values.includes(value)` for a required list.
static func _has(objective: Dictionary, key: String, value: Variant) -> bool:
	var values: Variant = objective.get(key)
	return values is Array and value != null and str(value) in (values as Array)


## `valuesInclude`: an absent list matches anything.
static func _values_include(objective: Dictionary, key: String, value: Variant) -> bool:
	if not objective.has(key) or objective[key] == null:
		return true
	return _has(objective, key, value)


## `tagsIncludeAll`: an absent list matches anything; else every listed tag is in `tags`.
static func _tags_include_all(objective: Dictionary, tags: Variant) -> bool:
	if not objective.has("enemyTags") or objective["enemyTags"] == null:
		return true
	if not tags is Array:
		return false
	for tag: Variant in objective["enemyTags"]:
		if not tag in (tags as Array):
			return false
	return true


## `Number.isInteger(value) && value > 0`.
static func _positive_int(value: Variant) -> bool:
	if value is int:
		return int(value) > 0
	if value is float:
		var number: float = value
		return is_finite(number) and number == floorf(number) and number > 0.0
	return false


## `payload[primary] ?? payload[fallback]` as a String.
static func _fact(payload: Dictionary, primary: String, fallback: String) -> String:
	var value: Variant = payload.get(primary)
	if value == null or str(value).is_empty():
		value = payload.get(fallback, "")
	return str(value)


static func _yes(amount: int = 1, fact_id: String = "") -> Dictionary:
	return {"matched": true, "amount": amount, "fact_id": fact_id}


static func _no() -> Dictionary:
	return {"matched": false, "amount": 0, "fact_id": ""}
