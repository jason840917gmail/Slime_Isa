extends RefCounted
class_name DamageResolver
## Pure damage resolution (Phaser `features/combat/DamageResolver.ts:62-187`). Combat spec 7.1
## step 6. Shapes: see res://game/combat/damage_router.gd.
##
## Rounding: `roundi()` everywhere a round appears (JS Math.round == round half away from zero
## for non-negative values).
##
## Owner: combat builder.

const REASON_INVALID := "invalid"
const REASON_INACTIVE := "inactive-attack"
const REASON_DUPLICATE := "duplicate"
const REASON_SOURCE_BLOCKED := "source-blocked"
const REASON_DEAD := "dead"
const REASON_STATE_BLOCKED := "state-blocked"
const REASON_IMMUNE := "immune"
const EFFECT_REASON_IMMUNE := "immune"
const EFFECT_REASON_ZERO_POTENCY := "zero-potency"
const DEFAULT_DAMAGE_TYPE := "physical"


## Validates/normalises a request (finite non-negative base_damage, non-null areas/source,
## unique sorted weapon_tags, damage_types default ["physical"]). Returns {} when invalid.
## Effects are sorted by effect_id (Phaser localeCompare) and must have unique non-empty ids
## with finite non-negative potency. `impact` needs finite `position` / `knock` Vector2s.
static func normalize_request(request: Dictionary) -> Dictionary:
	if request.is_empty():
		return {}
	var activation_id: Variant = request.get("activation_id", 0)
	if not (activation_id is int) or int(activation_id) <= 0:
		return {}
	if not _valid_object(request.get("source")):
		return {}
	if not _valid_area(request.get("attack_area")) or not _valid_area(request.get("target_area")):
		return {}
	var base_damage: Variant = request.get("base_damage", -1.0)
	if not _finite_non_negative(base_damage):
		return {}
	var weapon_tags: Variant = _identifier_list(request.get("weapon_tags", []))
	if weapon_tags == null:
		return {}
	var damage_types: Variant = _identifier_list(request.get("damage_types", [DEFAULT_DAMAGE_TYPE]))
	if damage_types == null:
		return {}
	var impact: Variant = request.get("impact", null)
	if not (impact is Dictionary):
		return {}
	var position: Variant = (impact as Dictionary).get("position", null)
	var knock: Variant = (impact as Dictionary).get("knock", null)
	if not (position is Vector2) or not (knock is Vector2):
		return {}
	if not (position as Vector2).is_finite() or not (knock as Vector2).is_finite():
		return {}
	var effects: Array = []
	var seen_effects: Dictionary = {}
	var raw_effects: Variant = request.get("effects", [])
	if not (raw_effects is Array):
		return {}
	for raw: Variant in raw_effects:
		if not (raw is Dictionary):
			return {}
		var effect_id := str((raw as Dictionary).get("effect_id", ""))
		var potency: Variant = (raw as Dictionary).get("potency", -1.0)
		if effect_id.strip_edges().is_empty() or not _finite_non_negative(potency):
			return {}
		if seen_effects.has(effect_id):
			return {}
		seen_effects[effect_id] = true
		effects.append({"effect_id": effect_id, "potency": float(potency)})
	effects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["effect_id"]) < String(b["effect_id"]))
	var normalized := request.duplicate(false)
	normalized["activation_id"] = int(activation_id)
	normalized["base_damage"] = float(base_damage)
	normalized["weapon_id"] = str(request.get("weapon_id", ""))
	normalized["weapon_tags"] = weapon_tags
	normalized["damage_types"] = damage_types
	normalized["effects"] = effects
	normalized["impact"] = {"position": position, "knock": knock}
	normalized["true_damage"] = bool(request.get("true_damage", false))
	return normalized


## `damageSourceMatches` (DamageResolver.ts:62-76): blockedWeaponTags hit -> false;
## acceptedSources absent -> true; otherwise any matcher whose weaponIds / allWeaponTags /
## anyDamageTypes clauses all match.
static func source_matches(rule: Dictionary, request: Dictionary) -> bool:
	var weapon_tags: Array = request.get("weapon_tags", [])
	var blocked: Variant = rule.get("blockedWeaponTags", null)
	if blocked is Array:
		for tag: Variant in blocked:
			if weapon_tags.has(str(tag)):
				return false
	var accepted_sources: Variant = rule.get("acceptedSources", null)
	if accepted_sources == null:
		return true
	if not (accepted_sources is Array) or (accepted_sources as Array).is_empty():
		return false
	var damage_types: Array = request.get("damage_types", [])
	var weapon_id := str(request.get("weapon_id", ""))
	for matcher: Variant in accepted_sources:
		if not (matcher is Dictionary) or not _valid_matcher(matcher):
			return false
	for matcher: Variant in accepted_sources:
		var m: Dictionary = matcher
		var weapon_matches := true
		if m.has("weaponIds"):
			weapon_matches = not weapon_id.is_empty() and (m["weaponIds"] as Array).has(weapon_id)
		var tags_match := true
		if m.has("allWeaponTags"):
			for tag: Variant in m["allWeaponTags"]:
				if not weapon_tags.has(str(tag)):
					tags_match = false
					break
		var types_match := true
		if m.has("anyDamageTypes"):
			types_match = false
			for damage_type: Variant in m["anyDamageTypes"]:
				if damage_types.has(str(damage_type)):
					types_match = true
					break
		if weapon_matches and tags_match and types_match:
			return true
	return false


## `resolveDamage` (combat spec 7.1 step 6): source, dead, scaled = base * damageMultiplier *
## product(damageTypeMultipliers), can_receive_damage, mitigate_damage, rounded, clamp to hp,
## effects (immune / multiplier / zero potency), immune when nothing lands; else accepted with
## `defeated = actual >= hp`. `receiver` implements the receiver API.
static func resolve(receiver: Object, request: Dictionary, rule: Dictionary, simulation_time: float) -> Dictionary:
	var normalized := normalize_request(request)
	if normalized.is_empty() or not _valid_rule(rule) or not is_finite(simulation_time):
		return rejected(REASON_INVALID)
	if receiver == null or not is_instance_valid(receiver) or not receiver.has_method("get_damage_state"):
		return rejected(REASON_INVALID)
	if not source_matches(rule, normalized):
		return rejected(REASON_SOURCE_BLOCKED)

	var state_value: Variant = receiver.call("get_damage_state")
	if not (state_value is Dictionary):
		return rejected(REASON_INVALID)
	var state: Dictionary = state_value
	if not _valid_state(state):
		return rejected(REASON_INVALID)
	var hp := float(state["hp"])
	if bool(state.get("dead", false)) or hp <= 0.0:
		return rejected(REASON_DEAD)

	var scaled_damage := float(normalized["base_damage"]) * _rule_number(rule, "damageMultiplier", 1.0)
	var type_multipliers: Variant = rule.get("damageTypeMultipliers", {})
	for damage_type: Variant in normalized["damage_types"]:
		if type_multipliers is Dictionary and (type_multipliers as Dictionary).has(damage_type):
			scaled_damage *= float((type_multipliers as Dictionary)[damage_type])
	if not _finite_non_negative(scaled_damage):
		return rejected(REASON_INVALID)

	var input := {
		"scaled_damage": scaled_damage,
		"request": normalized,
		"rule": rule,
		"area": rule,
		"state": state,
		"simulation_time": simulation_time,
	}
	if receiver.has_method("can_receive_damage"):
		var decision: Variant = receiver.call("can_receive_damage", input)
		if decision is Dictionary and not (decision as Dictionary).is_empty() \
				and not bool((decision as Dictionary).get("accepted", true)):
			var reason := str((decision as Dictionary).get("reason", ""))
			if reason.is_empty():
				reason = REASON_STATE_BLOCKED
			return rejected(reason)

	var mitigated := scaled_damage
	if receiver.has_method("mitigate_damage"):
		var value: Variant = receiver.call("mitigate_damage", input)
		if not (value is float or value is int):
			return rejected(REASON_INVALID)
		mitigated = float(value)
	if not _finite_non_negative(mitigated):
		return rejected(REASON_INVALID)
	var rounded := maxi(0, roundi(mitigated))
	var actual := int(minf(hp, float(rounded)))

	var applied: Array = []
	var rejected_effects: Array = []
	var responses: Variant = rule.get("effectResponses", {})
	for effect: Dictionary in normalized["effects"]:
		var effect_id: String = effect["effect_id"]
		var response: Variant = (responses as Dictionary).get(effect_id, null) if responses is Dictionary else null
		var mode := str((response as Dictionary).get("mode", "")) if response is Dictionary else ""
		if mode == "immune":
			rejected_effects.append({"effect_id": effect_id, "reason": EFFECT_REASON_IMMUNE})
			continue
		var potency := float(effect["potency"])
		if mode == "multiplier":
			potency *= float((response as Dictionary).get("multiplier", 1.0))
		if not _finite_non_negative(potency):
			return rejected(REASON_INVALID)
		if potency == 0.0:
			rejected_effects.append({"effect_id": effect_id, "reason": EFFECT_REASON_ZERO_POTENCY})
		else:
			applied.append({"effect_id": effect_id, "potency": potency})
	if actual == 0 and applied.is_empty():
		return rejected(REASON_IMMUNE)
	return accepted(actual, float(actual) >= hp, applied, rejected_effects)


## Accepted result Dictionary.
static func accepted(actual_damage: int, defeated: bool, applied_effects: Array, rejected_effects: Array) -> Dictionary:
	return {
		"status": "accepted",
		"reason": "",
		"retryable": false,
		"actual_damage": actual_damage,
		"defeated": defeated,
		"applied_effects": applied_effects,
		"rejected_effects": rejected_effects,
	}


## Rejected result Dictionary; `retryable` is true only for "state-blocked".
static func rejected(reason: String) -> Dictionary:
	return {
		"status": "rejected",
		"reason": reason,
		"retryable": reason == REASON_STATE_BLOCKED,
		"actual_damage": 0,
		"defeated": false,
		"applied_effects": [],
		"rejected_effects": [],
	}


## Sum of the applied potencies of `effect_id` in a result (receivers read "knockback" this way).
static func applied_potency(result: Dictionary, effect_id: String) -> float:
	var total := 0.0
	for effect: Variant in result.get("applied_effects", []):
		if effect is Dictionary and str((effect as Dictionary).get("effect_id", "")) == effect_id:
			total += float((effect as Dictionary).get("potency", 0.0))
	return total


## True when `effect_id` was rejected as "immune" in a result.
static func effect_immune(result: Dictionary, effect_id: String) -> bool:
	for effect: Variant in result.get("rejected_effects", []):
		if effect is Dictionary and str((effect as Dictionary).get("effect_id", "")) == effect_id \
				and str((effect as Dictionary).get("reason", "")) == EFFECT_REASON_IMMUNE:
			return true
	return false


# --- private ---------------------------------------------------------------------------------

static func _finite_non_negative(value: Variant) -> bool:
	if not (value is float or value is int):
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


static func _valid_object(value: Variant) -> bool:
	return value is Object and is_instance_valid(value)


static func _valid_area(value: Variant) -> bool:
	return value is Area2D and is_instance_valid(value)


## Unique non-empty strings, sorted; null when invalid.
static func _identifier_list(value: Variant) -> Variant:
	if not (value is Array):
		return null
	var seen: Dictionary = {}
	var out: Array = []
	for entry: Variant in value:
		if not (entry is String or entry is StringName):
			return null
		var text := String(entry)
		if text.strip_edges().is_empty() or seen.has(text):
			return null
		seen[text] = true
		out.append(text)
	out.sort()
	return out


static func _valid_matcher(matcher: Dictionary) -> bool:
	var clauses := 0
	for key: String in ["weaponIds", "allWeaponTags", "anyDamageTypes"]:
		if not matcher.has(key):
			continue
		clauses += 1
		var list: Variant = matcher[key]
		if not (list is Array) or (list as Array).is_empty() or _identifier_list(list) == null:
			return false
	return clauses > 0


## `validateDamageAreaRule` without the areaNodeId check (the router keys rules by area).
## Missing priority / damageMultiplier default to 0 / 1 (the receivers' authored defaults).
static func _valid_rule(rule: Dictionary) -> bool:
	if not _finite_non_negative(_rule_number(rule, "damageMultiplier", 1.0)):
		return false
	var priority: Variant = rule.get("priority", 0)
	if not (priority is int or priority is float) or not is_finite(float(priority)):
		return false
	var type_multipliers: Variant = rule.get("damageTypeMultipliers", {})
	if type_multipliers is Dictionary:
		for value: Variant in (type_multipliers as Dictionary).values():
			if not _finite_non_negative(value):
				return false
	var responses: Variant = rule.get("effectResponses", {})
	if responses is Dictionary:
		for response: Variant in (responses as Dictionary).values():
			if not (response is Dictionary):
				return false
			var mode := str((response as Dictionary).get("mode", ""))
			if mode == "immune":
				continue
			if mode != "multiplier" or not _finite_non_negative((response as Dictionary).get("multiplier", -1.0)):
				return false
	return true


static func _rule_number(rule: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = rule.get(key, fallback)
	return float(value) if (value is float or value is int) else NAN


## `validState`: finite hp/max_hp, max_hp >= 0, 0 <= hp <= max_hp.
static func _valid_state(state: Dictionary) -> bool:
	var hp: Variant = state.get("hp", null)
	var max_hp: Variant = state.get("max_hp", null)
	if not (hp is float or hp is int) or not (max_hp is float or max_hp is int):
		return false
	var h := float(hp)
	var m := float(max_hp)
	return is_finite(h) and is_finite(m) and m >= 0.0 and h >= 0.0 and h <= m
