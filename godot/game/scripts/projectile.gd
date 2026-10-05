extends Node
class_name ProjectileScript
## Scene script `game.projectile` (Phaser `features/scripts/ProjectileScript.ts`): an enemy's
## arrow or web in flight. Enemy spec 12.4 (docs/godot/specs/enemy.md).
##
## Node: `ProjectileScript` under the projectile's CharacterBody2D root (`projectile.worm-arrow`,
## `projectile.spider-web`; no depth anchor, so the root is the old Phaser position). Spawned and
## launched by res://game/enemy/enemy_projectiles.gd. While launched it ages on SimClock, expires on
## a wall hit (its last `ArcadeMover.move` was blocked) or at `lifetime_ms`, else moves; a hit on one
## of the payload's target hurtboxes (the player's) routes one request and expires the projectile
## whatever the result. `expire()` frees the root.
##
## The projectile script itself is the activation and request source (enemy spec 19: Phaser's
## source is the shooter's id string, valid after the shooter died; the router needs a live Object).
##
## Owner: enemy port.

const Services := preload("res://game/shared/services.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const SpiderWebPort := preload("res://game/enemy/spider_web_port.gd")

const KNOCKBACK_EFFECT_ID := "knockback"
## ProjectileScript.ts:122-124 defaults when the payload names none.
const DEFAULT_WEAPON_TAGS: Array[String] = ["projectile"]
const DEFAULT_DAMAGE_TYPES: Array[String] = ["physical"]
## The runtime world-bounds body (game/world/world_bounds.gd) a `collideWorldBounds: false`
## projectile flies through.
const WORLD_BOUNDS_NODE := "WorldBounds"
const COLLIDE_WORLD_BOUNDS_META := &"collide_world_bounds"

## JSON `projectileId` ("worm-arrow", "spider-web").
@export var projectile_id: String = "unknown-projectile"
## JSON `body`: the CharacterBody2D root.
@export var body: CharacterBody2D
## JSON `visual`: rotated to the flight direction when `rotate_to_velocity`.
@export var visual: Node2D
## JSON `animation` (clips `move`, autoplay, and `impact`, never played).
@export var animation: AnimationPlayer
## JSON `attackArea`: the hitbox whose `area_entered` calls `on_area_entered`.
@export var attack_area: Area2D
## JSON `defaultSpeed` (launch speed when none is given; enemies always give theirs).
@export var default_speed: float = 0.0
## JSON `lifetimeMs` (3000).
@export var lifetime_ms: float = 0.0
## JSON `rotateToVelocity`.
@export var rotate_to_velocity: bool = false

## -> ReleaseSfx / SpitSfx. Payload {"projectileId": String}.
signal launched(payload: Dictionary)
## -> ThunkSfx (arrow, detached). Payload {"projectileId": String}.
signal expired(payload: Dictionary)

var _launched: bool = false
var _launched_at: float = 0.0
var _age_ms: float = 0.0
## Damage payload (enemy_projectiles.gd): {"source_node_id", "damage", "knockback_strength",
## "weapon_id", "weapon_tags", "damage_types", "target_areas": Array[Area2D], "effects"}.
var _damage: Dictionary = {}
var _activation_id: int = 0
## The last move was blocked by the world (Phaser `blockingContacts`).
var _blocked: bool = false


func _ready() -> void:
	default_speed = maxf(0.0, default_speed)
	lifetime_ms = maxf(0.0, lifetime_ms)
	if body == null:
		push_error("ProjectileScript '%s' requires a CharacterBody2D body reference." % get_path())
		return
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if not bool(body.get_meta(COLLIDE_WORLD_BOUNDS_META, true)):
		var world := Services.world()
		var root: Node2D = world.entities_root() if world != null else null
		var bounds := root.get_node_or_null(NodePath(WORLD_BOUNDS_NODE)) as PhysicsBody2D if root != null else null
		if bounds != null:
			body.add_collision_exception_with(bounds)


func _exit_tree() -> void:
	_launched = false
	_end_activation()
	_damage = {}


## True between `launch` and `expire`.
func is_launched() -> bool:
	return _launched


## Gameplay ms since the launch.
func get_age_ms() -> float:
	return _age_ms


## The payload given to `launch` ({} when none).
func get_damage_payload() -> Dictionary:
	return _damage


## ProjectileScript.ts:80-98: velocity = unit(direction) * speed (NAN = `default_speed`); the Visual
## turns to the flight direction; starts the age; with a payload opens an attack activation for
## the attack area; emits `launched`. False (push_error) for a zero direction or a bad speed.
func launch(direction: Vector2, speed: float = NAN, damage: Dictionary = {}) -> bool:
	if is_nan(speed):
		speed = default_speed
	if body == null or not is_finite(speed) or speed < 0.0 or direction.length() == 0.0:
		push_error("ProjectileScript '%s': launch requires a direction and a finite non-negative speed." % get_path())
		return false
	var velocity := direction.normalized() * speed
	body.velocity = velocity
	if rotate_to_velocity and visual != null:
		visual.rotation = atan2(velocity.y, velocity.x)
	_age_ms = 0.0
	_launched_at = Services.now_ms()
	_launched = true
	_blocked = false
	_damage = damage
	if not damage.is_empty():
		var router := Services.router()
		if attack_area == null:
			push_error("ProjectileScript '%s' requires an attackArea reference." % get_path())
		elif router != null:
			var areas: Array[Area2D] = [attack_area]
			_activation_id = router.begin_activation(self, areas)
	launched.emit({"projectileId": projectile_id})
	return true


## ProjectileScript.ts:63-71, then the Arcade step: age; a blocked last move or the lifetime ends
## the flight; else move (and remember whether the world blocked it).
func _physics_process(delta: float) -> void:
	if not _launched or body == null:
		return
	_age_ms = Services.now_ms() - _launched_at
	if _blocked:
		expire()
		return
	if _age_ms >= lifetime_ms:
		expire()
		return
	_blocked = ArcadeMover.move(body, delta)


## ProjectileScript.ts:100-106: once: end the activation, emit `expired`, free the root.
func expire() -> void:
	if not _launched:
		return
	_launched = false
	_end_activation()
	expired.emit({"projectileId": projectile_id})
	var root := get_parent()
	if root != null:
		root.queue_free()
	else:
		queue_free()


## `AttackArea.area_entered` (ProjectileScript.ts:108-133): a payload target hurtbox gets one
## request (knock = the flight direction), then the projectile expires whatever the result.
## Other areas (enemy hurtboxes, the shooter's own) are ignored.
func on_area_entered(area: Area2D) -> void:
	var router := Services.router()
	if not _launched or _damage.is_empty() or _activation_id <= 0 or router == null or attack_area == null:
		return
	if area == null:
		return
	var targets: Variant = _damage.get("target_areas")
	if targets is Array and not (targets as Array).has(area):
		return
	var flight := body.velocity if body != null else Vector2.ZERO
	var knock := flight.normalized() if flight.length() > 0.0 else Vector2.ZERO
	var effects: Array = []
	var knockback_strength := float(_damage.get("knockback_strength", 0.0))
	if knockback_strength > 0.0:
		effects.append({"effect_id": KNOCKBACK_EFFECT_ID, "potency": knockback_strength})
	for effect: Variant in _damage.get("effects", []):
		effects.append(effect)
	var weapon_id := str(_damage.get("weapon_id", ""))
	var result := router.route({
		"activation_id": _activation_id,
		"source": self,
		"attack_area": attack_area,
		"target_area": area,
		"weapon_id": weapon_id if not weapon_id.is_empty() else projectile_id,
		"weapon_tags": _damage.get("weapon_tags", DEFAULT_WEAPON_TAGS.duplicate()),
		"damage_types": _damage.get("damage_types", DEFAULT_DAMAGE_TYPES.duplicate()),
		"base_damage": float(_damage.get("damage", 0.0)),
		"effects": effects,
		# Phaser sends (0, 0); nothing reads an incoming projectile's impact position.
		"impact": {"position": Vector2.ZERO, "knock": knock},
	})
	SpiderWebPort.after_web_hit(router.receiver_for_area(area), result)
	expire()


func _end_activation() -> void:
	if _activation_id > 0:
		var router := Services.router()
		if router != null:
			router.end_activation(_activation_id)
	_activation_id = 0
