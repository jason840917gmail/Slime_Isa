extends Node
class_name ResourceNodeScript
## Scene script `game.resource-node` (Phaser `features/scripts/ResourceNodeScript.ts`, which
## extends `DestructibleScript.ts`). World-objects spec 3-6. Child "ResourceNodeScript" of the
## StaticBody2D root (the old Phaser root: the sprite's bottom-centre; no depth anchor).
##
## A damage receiver on its DamageArea: a weapon without the right harvest tier is turned away
## ("Requires an Axe", retryable); a tool hit tints the sprite, shows the damage, spawns the hit
## effect and plays the on-hit clip. At 0 HP the node is recorded "depleted" (regrow timer),
## drops its piles (game/world_objects/resource_drops.gd) and is freed. Trees keep their damage
## across loads (`persist_health`); stone and iron do not. A broken node stays gone when its
## world loads again, with its uncollected piles back on the ground, until it regrows.
## `game.destructible` has no scenes of its own, so its exports are declared here too and its
## logic is the DestructibleHealth helper.
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const EffectSpawner := preload("res://game/combat/effect_spawner.gd")
const DestructibleHealth := preload("res://game/world_objects/destructible_health.gd")
const ResourceDrops := preload("res://game/world_objects/resource_drops.gd")

# game.destructible (registrations.ts:378-387)
## JSON `mapId`.
@export var map_id: String = ""
## JSON `instanceId`.
@export var instance_id: String = ""
## JSON `objectId` (e.g. "tree.world.solid").
@export var object_id: String = ""
## JSON `damageArea`: the hurtbox Area2D (layer hurtbox) registered with the DamageRouter.
@export var damage_area: Area2D
## JSON `maxHealth` (`max(1, value)`).
@export var max_health: float = 1.0
## JSON `initialHealth` (> 0: starting HP, capped at max).
@export var initial_health: float = 0.0
## JSON `tags`: router target tags in authored order (weapon damage modifiers; "resource" skips
## the weapon's hit feel).
@export var tags: Array[String] = []
## JSON `damageRule` (camelCase keys: priority, damageMultiplier, ...).
@export var damage_rule: Dictionary = {"priority": 0, "damageMultiplier": 1}
# game.resource-node (registrations.ts:403-412)
## JSON `drop`: {objectId, visualId, pieces}.
@export var drop: Dictionary = {}
## JSON `idleAnimationId`: clip played after the on-hit clip finishes.
@export var idle_animation_id: String = ""
## JSON `hitEffectId`: effect spawned at the base on every positive hit.
@export var hit_effect_id: String = ""
## JSON `onHitAnimationId`: clip restarted on every positive hit.
@export var on_hit_animation_id: String = ""
## JSON `persistHealth`: save damage taken (trees true; stone and iron false).
@export var persist_health: bool = true
## JSON `depletionMessage` ("" -> "Resource depleted").
@export var depletion_message: String = ""
## JSON `harvestRequirement`: {targetTag, minimumTier, failureMessage}.
@export var harvest_requirement: Dictionary = {}
## JSON `animation`: optional AnimationPlayer for the on-hit and idle clips.
@export var animation: AnimationPlayer

## After each positive hit. Payload: {mapId, instanceId, health, maxHealth}.
signal health_changed(payload: Dictionary)
## After `health_changed`. Payload: the router commit.
signal damaged(commit: Dictionary)
## Router feedback for a positive hit. Payload: the commit.
signal damage_feedback(commit: Dictionary)
## On destruction, before the drops. Payload: {mapId, instanceId, objectId}.
signal destroyed(payload: Dictionary)
## After the hit feedback. Payload: {mapId, instanceId, objectId, actualDamage, x, y, effectId?,
## animationId?} (-> RustleSfx / ClinkSfx).
signal resource_hit(payload: Dictionary)
## A weapon below the harvest tier. Payload: {mapId, instanceId, targetTag, minimumTier, message,
## x, y} (-> WrongToolSfx).
signal harvest_blocked(payload: Dictionary)
## Once, after the drops spawned. Payload: {mapId, instanceId, objectId, dropObjectId,
## dropVisualId, pieces, x, y, depletionMessage?} (-> Fall / Crumble / ShatterSfx).
signal drops_requested(payload: Dictionary)

## UniversalSceneWorldController.ts:2136-2142, :640 (presentation literals).
const HIT_TINT := Color("#ffd277")
const HIT_TINT_MS := 110.0
const HIT_TEXT_RISE := 54.0
const BLOCKED_TEXT_RISE := 58.0
const GROUP := &"resource_node"
const HARVEST_PREFIX := "harvest:"

var _health: DestructibleHealth
var _drops_published: bool = false
var _registered_area: Area2D


func _ready() -> void:
	add_to_group(GROUP)
	_health = DestructibleHealth.new(map_id, instance_id, max_health, initial_health, true)
	var saved := _health.load()
	if animation != null and not animation.animation_finished.is_connected(_on_animation_finished):
		animation.animation_finished.connect(_on_animation_finished)
	if _health.destroyed:
		# Broken earlier: its uncollected piles come back, then the node goes (mountAuthoredWorld).
		# Deferred: the world's entities root and tiles exist only after register_world.
		_restore_and_free.call_deferred(saved)
		return
	if damage_area == null:
		push_error("ResourceNodeScript '%s' requires its damage_area reference" % instance_id)
		return
	var router := Services.router()
	if router != null:
		router.register_area(damage_area, self, _rule(), tags)
		_registered_area = damage_area


func _exit_tree() -> void:
	var router := Services.router()
	if _registered_area != null and router != null:
		router.unregister_area(_registered_area)
	_registered_area = null


# --- receiver API (combat spec 7.1) ----------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": _health.health, "max_hp": _health.max_health, "dead": _health.destroyed}


## The harvest gate (spec 4.2): accepted when the weapon's best `harvest:<target>:<tier>` tag
## reaches the requirement; otherwise the failure message (cyan, big) and `harvest_blocked`, and a
## retryable "state-blocked" rejection.
func can_receive_damage(input: Dictionary) -> Dictionary:
	if _health.destroyed:
		return {"accepted": false, "reason": "dead"}
	var requirement := _harvest_requirement()
	if requirement.is_empty():
		return {"accepted": true}
	var target := str(requirement["targetTag"])
	var capability := 0
	var request: Dictionary = input.get("request", {})
	for tag: Variant in request.get("weapon_tags", []):
		capability = maxi(capability, _harvest_tier(str(tag), target))
	if float(capability) >= float(requirement["minimumTier"]):
		return {"accepted": true}
	var pos := world_position()
	var blocked := {"mapId": map_id, "instanceId": instance_id, "targetTag": target,
		"minimumTier": requirement["minimumTier"], "message": str(requirement["failureMessage"]),
		"x": pos.x, "y": pos.y}
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(pos - Vector2(0.0, BLOCKED_TEXT_RISE), blocked["message"], &"cyan", true)
	harvest_blocked.emit(blocked)
	return {"accepted": false, "reason": "state-blocked"}


func commit_damage(commit: Dictionary) -> void:
	var result: Dictionary = commit.get("result", {})
	var actual := float(result.get("actual_damage", 0.0))
	if _health.destroyed or actual <= 0.0:
		return
	_health.apply(actual)
	if persist_health:
		_health.save()
	health_changed.emit({"mapId": map_id, "instanceId": instance_id,
		"health": _health.health, "maxHealth": _health.max_health})
	damaged.emit(commit)
	_on_positive_damage(actual)
	if bool(result.get("defeated", false)) or _health.health <= 0.0:
		_destroy()


func publish_damage_feedback(commit: Dictionary) -> void:
	if float((commit.get("result", {}) as Dictionary).get("actual_damage", 0.0)) > 0.0:
		damage_feedback.emit(commit)


## The node root's global position (the old Phaser root: the sprite's bottom-centre).
func world_position() -> Vector2:
	var root := get_parent() as Node2D
	return root.global_position if root != null else Vector2.ZERO


func is_destroyed() -> bool:
	return _health.destroyed


# --- hits and destruction ----------------------------------------------------------------------

## Spec 4.3 step 3: on-hit clip, tint, damage text, hit effect, then `resource_hit`.
func _on_positive_damage(actual: float) -> void:
	_play(on_hit_animation_id)
	var pos := world_position()
	var request := {"mapId": map_id, "instanceId": instance_id, "objectId": object_id,
		"actualDamage": actual, "x": pos.x, "y": pos.y}
	if not hit_effect_id.is_empty():
		request["effectId"] = hit_effect_id
	if not on_hit_animation_id.is_empty():
		request["animationId"] = on_hit_animation_id
	_tint_visual()
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(pos - Vector2(0.0, HIT_TEXT_RISE), "-%d" % roundi(actual), &"white", false)
	if not hit_effect_id.is_empty():
		EffectSpawner.spawn_in_front(hit_effect_id, "right", pos, pos)
	resource_hit.emit(request)


## Spec 4.4: recorded "depleted" (regrow timer), `destroyed`, then the drops once, and the root is
## freed at the end of the frame (hits later in the same step are rejected "dead").
func _destroy() -> void:
	if not _health.mark_destroyed():
		return
	destroyed.emit({"mapId": map_id, "instanceId": instance_id, "objectId": object_id})
	var definition := _drop_definition()
	if not _drops_published and not definition.is_empty():
		_drops_published = true
		var pos := world_position()
		var request := {"mapId": map_id, "instanceId": instance_id, "objectId": object_id,
			"dropObjectId": definition["objectId"], "dropVisualId": definition["visualId"],
			"pieces": definition["pieces"], "x": pos.x, "y": pos.y}
		if not depletion_message.is_empty():
			request["depletionMessage"] = depletion_message
		ResourceDrops.spawn_for(request)
		drops_requested.emit(request)
	var root := get_parent()
	if root != null:
		root.queue_free()


func _restore_and_free(saved: Dictionary) -> void:
	if str(saved.get("stage", "")) == "destroyed":
		ResourceDrops.restore(map_id, instance_id, saved, _drop_definition())
	var root := get_parent()
	if root != null and not root.is_queued_for_deletion():
		root.queue_free()


func _on_animation_finished(clip: StringName) -> void:
	if String(clip) == on_hit_animation_id:
		_play(idle_animation_id)


func _play(clip: String) -> void:
	if clip.is_empty() or animation == null or not animation.has_animation(clip):
		return
	if animation.has_method(&"play_clip"):
		animation.call(&"play_clip", StringName(clip))
	else:
		animation.stop()
		animation.play(clip)


## A solid #ffd277 fill on the first sprite of the node for 110 ms of real time (runs through a
## hit-stop, like Phaser's scene timer).
func _tint_visual() -> void:
	var root := get_parent()
	if root == null:
		return
	var sprites := root.find_children("*", "Sprite2D", true, false)
	if sprites.is_empty():
		return
	var visual := sprites[0] as Sprite2D
	HitFlash.flash(visual, HIT_TINT)
	# By id: the node may be freed (felled) before the timer ends.
	var visual_id := visual.get_instance_id()
	var timer := get_tree().create_timer(HIT_TINT_MS / 1000.0, true)
	timer.timeout.connect(func() -> void:
		var target := instance_from_id(visual_id) as CanvasItem
		if target != null:
			HitFlash.clear(target))


## {targetTag, minimumTier, failureMessage} when authored with the right types, else {}.
func _harvest_requirement() -> Dictionary:
	var target: Variant = harvest_requirement.get("targetTag")
	var tier: Variant = harvest_requirement.get("minimumTier")
	var message: Variant = harvest_requirement.get("failureMessage")
	if target is String and (tier is int or tier is float) and message is String:
		return harvest_requirement
	return {}


## `harvestTier` (ResourceNodeScript.ts:190-195): the number after "harvest:<target>:" when it is
## a positive integer, else 0.
static func _harvest_tier(tag: String, target: String) -> int:
	var prefix := HARVEST_PREFIX + target + ":"
	if not tag.begins_with(prefix):
		return 0
	var rest := tag.substr(prefix.length())
	if not rest.is_valid_float():
		return 0
	var value := rest.to_float()
	if value <= 0.0 or value != floorf(value) or value > 9007199254740991.0:
		return 0
	return int(value)


## {objectId, visualId, pieces (>= 1)} when authored with the right types, else {}.
func _drop_definition() -> Dictionary:
	var drop_object: Variant = drop.get("objectId")
	var visual: Variant = drop.get("visualId")
	var pieces: Variant = drop.get("pieces")
	if drop_object is String and visual is String and (pieces is int or pieces is float):
		return {"objectId": drop_object, "visualId": visual, "pieces": maxi(1, floori(float(pieces)))}
	return {}


func _rule() -> Dictionary:
	var rule := damage_rule.duplicate()
	if not rule.has("priority"):
		rule["priority"] = 0
	if not rule.has("damageMultiplier"):
		rule["damageMultiplier"] = 1
	return rule
