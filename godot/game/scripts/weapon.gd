extends Node
class_name WeaponScript
## Scene script `game.weapon` (Phaser `features/scripts/WeaponScript.ts`). Combat spec 4.3, 5, 6.
## Used by every weapon scene; the trial mounts only `weapon.basic-sword`. Harvesting
## (harvest_capabilities, resource/stone modifiers vs resources) is OUT but the exports exist.
##
## The weapon root is mounted on the player by PlayerCombat; the node "WeaponScript" is a plain
## Node child of it. Swing clock: SimClock (frozen by hit-stop).
## Hit detection (combat spec 6.2): `attack_area.monitoring` stays true while mounted; only the
## CollisionShape2D children named "<direction>--<hitboxId>" are toggled (`disabled`). Three
## paths feed one resolver (the per-window receiver set dedupes them):
## - same-step shape query: after the windows update, a deferred `intersect_shape` per enabled
##   shape (run once every script has moved its body this step) stands in for Phaser's
##   `collectManagedContacts` -> `area_entered` in the SAME fixed step
##   (PhaserSceneTreeHost.ts:101-107), so a target already inside the sector is hit in the step
##   the window opens, and a target entering an open window is hit in the step it enters;
## - at the START of each physics step while swinging, `attack_area.get_overlapping_areas()`
##   (Phaser's level-triggered `currentContacts` poll: continuity across window changes);
## - `on_area_entered` (Godot emits it only at the next step's query flush; kept as a fallback).
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")
const Directions := preload("res://game/shared/directions.gd")

## JSON `weaponId` ("basic-sword").
@export var weapon_id: String = ""
## JSON `category` ("melee").
@export var category: String = ""
## JSON `attackArea`: the Area2D (layer hitbox, mask hurtbox) holding the sector shapes.
@export var attack_area: Area2D
## JSON `animation`: the weapon AnimationPlayer (idle, attack-right/left/up/down).
@export var animation: AnimationPlayer
## JSON `baseDamage` (20).
@export var base_damage: float = 0.0
## JSON `cooldownMs` (1200), counted from swing start.
@export var cooldown_ms: float = 0.0
## JSON `knockStrength` (140).
@export var knock_strength: float = 0.0
## JSON `damageModifiers`: [{"targetTag": String, "modifier": float}] (camelCase).
@export var damage_modifiers: Array = []
## JSON `harvestCapabilities` (OUT).
@export var harvest_capabilities: Dictionary = {}
## JSON `scaling`: {"damage": {attr: coef}, "cooldown": {...}, "knockback": {...}}.
@export var scaling: Dictionary = {}
## JSON `onHitEffectId` ("basic-sword-impact").
@export var on_hit_effect_id: String = ""
## JSON `attackPlans`: direction -> {"animationId", "durationMs", "framesPerSecond",
## "hitboxSpans": [{"hitboxId", "from", "through", "damageMultiplier", "knockbackMultiplier"}],
## "events", "mirrored"} (camelCase).
@export var attack_plans: Dictionary = {}

## -> SwingSfx.play_cue. Payload {"weaponId": String, "direction": String}.
signal attack_started(payload: Dictionary)
## Payload {"weaponId": String, "direction": String}.
signal attack_finished(payload: Dictionary)

## Default span multipliers (WeaponScript.ts:220-221).
const DEFAULT_SPAN_MULTIPLIER := 1.0
## Separator between the direction and the hitbox id in attack shape names ("right--primary").
const SHAPE_NAME_SEPARATOR := "--"
const DEFAULT_DAMAGE_TYPES: Array[String] = ["physical"]
const KNOCKBACK_EFFECT_ID := "knockback"

## The combat port (PlayerCombat; duck-typed so weapon scenes load without it).
var _combat: Node
var _active_direction: String = ""
var _active_plan: Dictionary = {}
var _active_since: float = 0.0
var _ready_at: float = 0.0
var _payload: Dictionary = {}
## span index -> {"span": Dictionary, "activation_id": int, "resolved": {receiver instance id: true}}
var _windows: Dictionary = {}
## The weapon's view of the gameplay clock: `Services.now_ms()` sampled at the top of each of its
## physics steps. Phaser's WeaponScript advanced its own clock in its `_physics_process`, so a
## swing started earlier in the same step (by the player state machine) saw the previous step's
## time; sampling SimClock here keeps that exact timing (first step of a swing sees elapsed one
## step, windows and cooldown on the same frames as Phaser) without a separate accumulator.
var _weapon_time: float = 0.0
## Bumped whenever a swing starts or ends; lets `_resolve_contact` notice a swing ended while
## routing (WeaponScript.ts:342-343).
var _swing_serial: int = 0
## True while a deferred same-step shape query is queued (one per physics step).
var _shape_query_queued: bool = false


## Disables every attack shape, sets `attack_area.monitoring = true`, plays "idle".
func _ready() -> void:
	_weapon_time = Services.now_ms()
	if attack_area == null:
		push_error("WeaponScript '%s' requires an attack_area reference" % weapon_id)
	else:
		attack_area.monitoring = true
	_set_attack_area_active(false, {})
	if animation != null and animation.has_animation(&"idle"):
		_play_clip(&"idle")


## `cancel_attack()` when leaving the tree.
func _exit_tree() -> void:
	cancel_attack()


## Binds the combat port (PlayerCombat): on_attack_started/finished, transform_damage,
## on_outcome, wielder_receiver.
func bind_combat(port: Node) -> void:
	_combat = port


## `simTime >= readyAt and no active plan` (WeaponScript.ts:133-135).
func can_begin_attack() -> bool:
	return _weapon_time >= _ready_at and _active_plan.is_empty()


## SimClock time at which the next swing is allowed.
func get_ready_at() -> float:
	return _ready_at


## `beginAttack` (combat spec 4.3): plan for `direction` (missing -> false), remember payload
## {"damage", "knockback_strength", "cooldown_ms", "weapon_tags", "damage_types"}, ready_at =
## now + payload.cooldown_ms, `_combat.on_attack_started(weapon_id, direction)`, play the plan's
## animationId, emit attack_started.
## "now" is the weapon clock (`_weapon_time`, see its comment). An empty payload swings without
## dealing damage (no activations), as in Phaser.
func try_begin_attack(direction: String, payload: Dictionary) -> bool:
	if not can_begin_attack():
		return false
	var plan := _attack_plan(direction)
	if plan.is_empty():
		return false
	_active_direction = direction
	_active_plan = plan
	_active_since = _weapon_time
	var cooldown: Variant = payload.get("cooldown_ms", cooldown_ms)
	_ready_at = _weapon_time + (float(cooldown) if (cooldown is float or cooldown is int) else cooldown_ms)
	_payload = payload.duplicate()
	_swing_serial += 1
	if _has_combat():
		_combat.call(&"on_attack_started", weapon_id, direction)
	var animation_id := StringName(str(plan["animationId"]))
	if animation != null and animation.has_animation(animation_id):
		_play_clip(animation_id)
	attack_started.emit({"weaponId": weapon_id, "direction": direction})
	return true


## `finishAttack()` if a swing is active (combat spec 5.2).
func cancel_attack() -> void:
	if _active_plan.is_empty():
		return
	_finish_attack()


func is_attacking() -> bool:
	return not _active_plan.is_empty()


## "right" | "left" | "up" | "down" while swinging, else "".
func get_active_direction() -> String:
	return _active_direction


## Combat spec 5.2 order: resolve current overlaps for open windows; finish when elapsed >=
## durationMs; else frame = floor(elapsed / 1000 * fps), open/close windows
## (`Services.router().begin_activation/end_activation`), toggle shapes.
func _physics_process(_delta: float) -> void:
	_weapon_time = Services.now_ms()
	if _active_plan.is_empty() or _active_direction.is_empty():
		return
	var plan := _active_plan
	# Contacts gathered by the previous physics step describe the windows open then
	# (level-triggered: targets already inside, or staying inside, are hit too).
	_resolve_current_overlaps()
	if _active_plan.is_empty():
		return
	var elapsed := _weapon_time - _active_since
	if elapsed >= float(plan["durationMs"]):
		_finish_attack()
		return
	_update_windows(floori(elapsed / 1000.0 * float(plan["framesPerSecond"])))
	# Phaser resolves new contacts later in the same fixed step (collectManagedContacts ->
	# area_entered); Godot's own area_entered only arrives at the next step's query flush.
	_queue_shape_query()


## Converted connection `AttackArea.area_entered -> on_area_entered`: same resolver as the
## polling path. The signal arrives while the physics server flushes its queries, where the
## damage chain (knockback, effect spawns, collision toggles) must not run, so the contact is
## resolved deferred; the per-window receiver set dedupes it against the polling path.
func on_area_entered(area: Node) -> void:
	if _active_plan.is_empty() or not (area is Area2D):
		return
	_resolve_contact_deferred.call_deferred(area.get_instance_id())


# --- private steps ----------------------------------------------------------------------------

func _resolve_contact_deferred(area_id: int) -> void:
	var area := instance_from_id(area_id) as Area2D
	if area != null and area.is_inside_tree():
		_resolve_contact(area)


func _queue_shape_query() -> void:
	if _shape_query_queued or _windows.is_empty() or attack_area == null:
		return
	_shape_query_queued = true
	_resolve_shape_query.call_deferred(_swing_serial)


## Same-step contact pass (Phaser `collectManagedContacts` -> `area_entered` -> `resolveContact`):
## runs from the deferred-call flush at the end of this physics step's process pass, after every
## script has moved its body and before the physics server steps. Queries each enabled attack
## shape against the space (areas only, `attack_area.collision_mask`, monitorable areas, the
## attack area itself excluded) and resolves every hit hurtbox; skipped when the swing that
## queued it has ended.
func _resolve_shape_query(serial: int) -> void:
	_shape_query_queued = false
	if serial != _swing_serial or _windows.is_empty() or _payload.is_empty():
		return
	if attack_area == null or not is_instance_valid(attack_area) or not attack_area.is_inside_tree() \
			or not attack_area.monitoring:
		return
	var space := attack_area.get_world_2d().direct_space_state
	if space == null:
		return
	var areas: Array[Area2D] = []
	var seen: Dictionary = {}
	var exclude: Array[RID] = [attack_area.get_rid()]
	var area_transform := attack_area.global_transform
	# Shape owners cover CollisionShape2D and CollisionPolygon2D children alike.
	for owner_id in attack_area.get_shape_owners():
		if attack_area.is_shape_owner_disabled(owner_id):
			continue
		var owner_transform := area_transform * attack_area.shape_owner_get_transform(owner_id)
		for shape_index in attack_area.shape_owner_get_shape_count(owner_id):
			var shape := attack_area.shape_owner_get_shape(owner_id, shape_index)
			if shape == null:
				continue
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape
			query.transform = owner_transform
			query.collide_with_areas = true
			query.collide_with_bodies = false
			query.collision_mask = attack_area.collision_mask
			query.exclude = exclude
			for hit: Dictionary in space.intersect_shape(query):
				var area := hit.get("collider") as Area2D
				if area == null or not area.monitorable or seen.has(area.get_instance_id()):
					continue
				seen[area.get_instance_id()] = true
				areas.append(area)
	for area in areas:
		if _swing_serial != serial:
			return
		if is_instance_valid(area) and area.is_inside_tree():
			_resolve_contact(area)


func _resolve_current_overlaps() -> void:
	if _windows.is_empty() or attack_area == null or not attack_area.monitoring:
		return
	var serial := _swing_serial
	for area in attack_area.get_overlapping_areas():
		if _swing_serial != serial:
			return
		_resolve_contact(area)


## Combat spec 6.1 / 6.3 for one overlapping hurtbox: skip unregistered areas and the wielder;
## per open window not yet tried for this receiver: mark tried, build the request (damage via
## `_combat.transform_damage(payload.damage * span.damageMultiplier, target)`, knockback effect
## `knockback_strength * span.knockbackMultiplier`, impact at the hurtbox global position = target
## centre, knock = Directions.cardinal_vector(direction)), route it, `_combat.on_outcome(...)`;
## stop if the swing ended meanwhile.
## Shape filter: every open window qualifies (Phaser's rule when a contact names no known shape).
## Only the active direction's shapes of open windows are enabled, so for single-span weapons
## (all trial weapons) any overlap belongs to that window.
func _resolve_contact(area: Area2D) -> void:
	if _payload.is_empty() or _active_direction.is_empty() or _windows.is_empty() or not _has_combat():
		return
	if area == null or not is_instance_valid(area) or attack_area == null:
		return
	var router := Services.router()
	if router == null:
		return
	var receiver := router.receiver_for_area(area)
	if receiver == null:
		return
	var wielder: Variant = _combat.call(&"wielder_receiver")
	if wielder is Object and wielder == receiver:
		return
	var receiver_id := receiver.get_instance_id()
	var serial := _swing_serial
	var direction := _active_direction
	var payload := _payload
	for index: Variant in _windows.keys():
		var window: Dictionary = _windows.get(index, {})
		if window.is_empty():
			continue
		var activation_id: int = window["activation_id"]
		var resolved: Dictionary = window["resolved"]
		if activation_id <= 0 or resolved.has(receiver_id):
			continue
		resolved[receiver_id] = true
		var span: Dictionary = window["span"]
		var target := {
			"area": area,
			"receiver": receiver,
			"position": area.global_position,
			"attack_direction": direction,
			"tags": router.tags_for_area(area),
		}
		var base := float(payload.get("damage", 0)) * float(span["damageMultiplier"])
		var routed_damage := int(_combat.call(&"transform_damage", base, target))
		var knockback := float(payload.get("knockback_strength", 0.0))
		var effects: Array = []
		if knockback > 0.0:
			effects.append({"effect_id": KNOCKBACK_EFFECT_ID, "potency": knockback * float(span["knockbackMultiplier"])})
		var weapon_tags: Variant = payload.get("weapon_tags", null)
		if not (weapon_tags is Array):
			weapon_tags = ["spear" if weapon_id.contains("spear") else "weapon"]
		var damage_types: Variant = payload.get("damage_types", null)
		if not (damage_types is Array):
			damage_types = DEFAULT_DAMAGE_TYPES.duplicate()
		var request := {
			"activation_id": activation_id,
			"source": self,
			"attack_area": attack_area,
			"target_area": area,
			"weapon_id": weapon_id,
			"weapon_tags": weapon_tags,
			"damage_types": damage_types,
			"base_damage": float(maxi(0, routed_damage)),
			"effects": effects,
			"impact": {"position": target["position"], "knock": Directions.cardinal_vector(direction)},
		}
		var outcome := router.route(request)
		if _has_combat():
			_combat.call(&"on_outcome", outcome, target)
		# Routing can end the attack (e.g. a defeat handler); stop using stale state.
		if _swing_serial != serial:
			return


## Combat spec 5.2 step 4-5: windows open while `from <= frame <= through`; enable only
## "<active direction>--<hitboxId>" shapes of open windows.
func _update_windows(frame: int) -> void:
	var spans: Array = _active_plan.get("hitboxSpans", [])
	for i in spans.size():
		var span: Dictionary = spans[i]
		var open := frame >= float(span["from"]) and frame <= float(span["through"])
		if open and not _windows.has(i):
			var activation_id := 0
			var router := Services.router()
			if not _payload.is_empty() and attack_area != null and router != null:
				activation_id = router.begin_activation(self, [attack_area])
			_windows[i] = {"span": span, "activation_id": activation_id, "resolved": {}}
		elif not open and _windows.has(i):
			_close_window(i)
	var hitbox_ids: Dictionary = {}
	for window: Dictionary in _windows.values():
		hitbox_ids[str((window["span"] as Dictionary)["hitboxId"])] = true
	_set_attack_area_active(not hitbox_ids.is_empty(), hitbox_ids)


func _close_window(index: int) -> void:
	var window: Dictionary = _windows.get(index, {})
	_windows.erase(index)
	var activation_id: int = window.get("activation_id", 0)
	var router := Services.router()
	if activation_id > 0 and router != null:
		router.end_activation(activation_id)


func _close_windows() -> void:
	for index: Variant in _windows.keys():
		_close_window(int(index))


## Combat spec 5.2 finishAttack: shapes off, close windows, clear plan, play "idle",
## `_combat.on_attack_finished(...)`, emit attack_finished.
func _finish_attack() -> void:
	var direction := _active_direction
	_set_attack_area_active(false, {})
	_close_windows()
	_payload = {}
	_active_direction = ""
	_active_plan = {}
	_swing_serial += 1
	if animation != null and is_instance_valid(animation) and animation.is_inside_tree() \
			and animation.has_animation(&"idle"):
		_play_clip(&"idle")
	if direction.is_empty():
		return
	if _has_combat():
		_combat.call(&"on_attack_finished", weapon_id, direction)
	attack_finished.emit({"weaponId": weapon_id, "direction": direction})


## `setAttackAreaActive` (WeaponScript.ts:361-372) with the Godot rule of combat spec 6.2:
## monitoring stays on; each attack shape named "<direction>--<hitboxId>" is enabled only while
## active, for the active direction and an open hitbox id.
func _set_attack_area_active(active: bool, hitbox_ids: Dictionary) -> void:
	if attack_area == null or not is_instance_valid(attack_area):
		return
	for child in attack_area.get_children():
		if not (child is CollisionShape2D or child is CollisionPolygon2D):
			continue
		var shape_name := String(child.name)
		var separator := shape_name.find(SHAPE_NAME_SEPARATOR)
		var direction := shape_name.substr(0, separator) if separator >= 0 else ""
		var hitbox_id := shape_name.substr(separator + SHAPE_NAME_SEPARATOR.length()) if separator >= 0 else shape_name
		var disabled := not active or direction != _active_direction or not hitbox_ids.has(hitbox_id)
		if bool(child.get(&"disabled")) != disabled:
			child.set(&"disabled", disabled)


## `attackPlan(direction)` (WeaponScript.ts:199-225): validated plan with defaulted span
## multipliers, or {} when missing / malformed.
func _attack_plan(direction: String) -> Dictionary:
	var raw: Variant = attack_plans.get(direction, null)
	if not (raw is Dictionary):
		return {}
	var plan: Dictionary = raw
	var animation_id: Variant = plan.get("animationId", null)
	var duration: Variant = plan.get("durationMs", null)
	var fps: Variant = plan.get("framesPerSecond", null)
	var spans: Variant = plan.get("hitboxSpans", null)
	if not (animation_id is String or animation_id is StringName) or not _is_number(duration) \
			or not _is_number(fps) or not (spans is Array):
		return {}
	var hitbox_spans: Array = []
	for raw_span: Variant in spans:
		if not (raw_span is Dictionary):
			continue
		var span: Dictionary = raw_span
		if not (span.get("hitboxId", null) is String) or not _is_number(span.get("from", null)) \
				or not _is_number(span.get("through", null)):
			continue
		hitbox_spans.append({
			"hitboxId": span["hitboxId"],
			"from": float(span["from"]),
			"through": float(span["through"]),
			"damageMultiplier": float(span["damageMultiplier"]) if _is_number(span.get("damageMultiplier", null)) else DEFAULT_SPAN_MULTIPLIER,
			"knockbackMultiplier": float(span["knockbackMultiplier"]) if _is_number(span.get("knockbackMultiplier", null)) else DEFAULT_SPAN_MULTIPLIER,
		})
	return {
		"animationId": String(animation_id),
		"durationMs": float(duration),
		"framesPerSecond": float(fps),
		"hitboxSpans": hitbox_spans,
	}


## Starts `clip` from frame 0 and applies that frame at once, like Phaser's
## `AnimationPlayerNode.play` (clock.start dispatches frame 0 immediately): the converter
## runtime's `play_clip` when present, else play + seek(0, true).
func _play_clip(clip: StringName) -> void:
	if animation.has_method(&"play_clip"):
		animation.call(&"play_clip", clip)
	else:
		animation.play(clip)
		animation.seek(0.0, true)


func _has_combat() -> bool:
	return _combat != null and is_instance_valid(_combat)


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
