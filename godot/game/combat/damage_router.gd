extends Node
## Autoload `DamageRouter` (Phaser `features/combat/DamageRouter.ts` + `AttackActivation.ts`
## + `DamageReceiver.ts`). Combat spec 7.1. One router for the whole world; used by the weapon
## (player -> enemies) and by enemies (enemy -> player). Access: `Services.router()`.
##
## Data shapes (internal Dictionaries, snake_case keys):
##   rule (receiver): the scene `damageRule` Dictionary as authored, camelCase keys:
##     {"priority": int, "damageMultiplier": float, "damageTypeMultipliers"?: {type: float},
##      "effectResponses"?: {...}, "acceptedSources"?: [...], "blockedWeaponTags"?: [...]}
##   request: {"activation_id": int, "source": Object, "attack_area": Area2D,
##     "target_area": Area2D, "weapon_id": String, "weapon_tags": Array[String],
##     "damage_types": Array[String], "base_damage": float,
##     "effects": Array[{"effect_id": String, "potency": float}],
##     "impact": {"position": Vector2 (old centre), "knock": Vector2}}
##   input (to receiver hooks): {"scaled_damage": float, "request": Dictionary, "rule": Dictionary,
##     "state": Dictionary, "simulation_time": float}
##   result: {"status": "accepted"|"rejected", "reason": String ("" when accepted; "invalid",
##     "inactive-attack", "duplicate", "source-blocked", "dead", "state-blocked", "immune"),
##     "retryable": bool, "actual_damage": int, "defeated": bool,
##     "applied_effects": Array[{"effect_id", "potency"}],
##     "rejected_effects": Array[{"effect_id", "reason"}]}
##   commit (to commit_damage / publish_damage_feedback, and the `damaged` signal payload):
##     {"request": Dictionary, "rule": Dictionary, "result": Dictionary,
##      "simulation_time": float, "receiver": Object}
##
## Receiver API (duck-typed on the registered receiver): `get_damage_state() -> {"hp", "max_hp",
## "dead"}`, optional `can_receive_damage(input) -> {"accepted", "reason"}`, optional
## `mitigate_damage(input) -> float`, `commit_damage(commit)`, optional
## `publish_damage_feedback(commit)`.
## No elevation reach gate (not on this branch).
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")
const DamageResolver := preload("res://game/combat/damage_resolver.gd")
const AttackActivations := preload("res://game/combat/attack_activations.gd")

## Emitted after every routed request (debug overlay / tests). Payload {"request", "result"}.
signal routed(payload: Dictionary)

## Reason pushed as a warning when a request is malformed (integration aid; Phaser threw or
## silently rejected).
const WARN_INVALID := true

var _activations: AttackActivations = AttackActivations.new()
## area instance id -> {"area": Area2D, "receiver": Object, "rule": Dictionary, "tags": Array[String]}
var _registry: Dictionary = {}


## Registers a hurtbox. Re-registering an area replaces its entry. `tags` may be a typed or an
## untyped Array of Strings (e.g. ["enemy"]); they are the target tags weapons use for damage
## modifiers, in authored order.
func register_area(area: Area2D, receiver: Object, rule: Dictionary, tags: Array = []) -> void:
	if area == null or receiver == null:
		push_error("DamageRouter.register_area: area and receiver are required")
		return
	var typed_tags: Array[String] = []
	for tag: Variant in tags:
		typed_tags.append(str(tag))
	_registry[area.get_instance_id()] = {"area": area, "receiver": receiver, "rule": rule, "tags": typed_tags}


## Removes a hurtbox (receiver `_exit_tree`).
func unregister_area(area: Area2D) -> void:
	if area == null:
		return
	_registry.erase(area.get_instance_id())


## Receiver registered for `area`, or null (unregistered areas are ignored by weapons).
func receiver_for_area(area: Area2D) -> Object:
	var entry := _entry_for(area)
	return entry.get("receiver") if not entry.is_empty() else null


## Tags of the registered area ([] when unknown); weapons use them for damage modifiers.
func tags_for_area(area: Area2D) -> Array[String]:
	var entry := _entry_for(area)
	if entry.is_empty():
		return []
	var tags: Array[String] = entry["tags"]
	return tags.duplicate()


## The rule `area` was registered with ({} when unknown).
func rule_for_area(area: Area2D) -> Dictionary:
	var entry := _entry_for(area)
	return entry.get("rule", {}) if not entry.is_empty() else {}


## Starts an attack activation (one-hit-per-receiver token) for `source` and its attack areas.
## Returns its id (> 0; 0 on invalid input). `attack_areas` may be typed (Array[Area2D]) or an
## untyped array literal such as `[attack_area]`.
func begin_activation(source: Object, attack_areas: Array) -> int:
	return _activations.begin(source, attack_areas)


## Ends an activation; later requests with it are rejected "inactive-attack".
func end_activation(activation_id: int) -> void:
	_activations.end(activation_id)


## True while the activation is open.
func is_activation_active(activation_id: int) -> bool:
	return _activations.is_active(activation_id)


## `DamageRouter.routeStep` with one request, combat spec 7.1 steps 1-8: validate, activation
## check, receiver lookup, source match, duplicate check, `DamageResolver.resolve(...)` with
## `Services.now_ms()`, record the outcome on the activation (accepted -> receiver done;
## non-retryable rejection -> area signature terminal; retryable -> nothing), then on accept
## `receiver.commit_damage(commit)` followed by `receiver.publish_damage_feedback(commit)`.
## Returns the result Dictionary.
func route(request: Dictionary) -> Dictionary:
	var result := _route(request)
	routed.emit({"request": request, "result": result})
	return result


func _route(request: Dictionary) -> Dictionary:
	var simulation_time := Services.now_ms()
	# 1. normalise / validate.
	var normalized := DamageResolver.normalize_request(request)
	if normalized.is_empty():
		if WARN_INVALID:
			push_warning("DamageRouter.route: invalid request %s" % [request])
		return DamageResolver.rejected(DamageResolver.REASON_INVALID)
	# 2. the activation must be open, from this source, and own this attack area.
	var activation_id: int = normalized["activation_id"]
	if not _activations.validate(activation_id, normalized["source"], normalized["attack_area"]):
		return DamageResolver.rejected(DamageResolver.REASON_INACTIVE)
	# 3. target area -> receiver.
	var target_area: Area2D = normalized["target_area"]
	var entry := _entry_for(target_area)
	if entry.is_empty():
		if WARN_INVALID:
			push_warning("DamageRouter.route: target area %s is not registered" % target_area.get_path())
		return DamageResolver.rejected(DamageResolver.REASON_INVALID)
	var receiver: Object = entry["receiver"]
	var rule: Dictionary = entry["rule"]
	# 4./5. one candidate area: its signature is the area itself, matching or not.
	var signature := str(target_area.get_instance_id())
	var cached := _activations.before_attempt(activation_id, receiver, signature)
	if not cached.is_empty():
		return DamageResolver.rejected(cached)
	# 6. resolve.
	var result: Dictionary
	if DamageResolver.source_matches(rule, normalized):
		result = DamageResolver.resolve(receiver, normalized, rule, simulation_time)
	else:
		result = DamageResolver.rejected(DamageResolver.REASON_SOURCE_BLOCKED)
	if result.get("reason", "") == DamageResolver.REASON_INVALID and WARN_INVALID:
		push_warning("DamageRouter.route: resolver rejected the request as invalid (receiver %s)" % [receiver])
	# 7. record on the activation.
	_activations.record(activation_id, receiver, signature, result)
	# 8. commit + feedback.
	if result.get("status", "") == "accepted":
		var commit := {
			"request": normalized,
			"rule": rule,
			"area": rule,
			"result": result,
			"simulation_time": simulation_time,
			"receiver": receiver,
		}
		if receiver.has_method("commit_damage"):
			receiver.call("commit_damage", commit)
		if is_instance_valid(receiver) and receiver.has_method("publish_damage_feedback"):
			receiver.call("publish_damage_feedback", commit)
	return result


## Registry entry for a live area whose receiver is still valid; stale entries are dropped.
func _entry_for(area: Area2D) -> Dictionary:
	if area == null:
		return {}
	var key := area.get_instance_id()
	var entry: Dictionary = _registry.get(key, {})
	if entry.is_empty():
		return {}
	if not is_instance_valid(entry["receiver"]) or not is_instance_valid(entry["area"]):
		_registry.erase(key)
		return {}
	return entry
