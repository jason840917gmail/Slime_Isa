extends RefCounted
class_name EnemyProjectiles
## The world side of enemy projectiles (Phaser `UniversalSceneWorldController.spawnEnemyProjectile`,
## `:2087-2114`). Enemy spec 12.3.
##
## `fire(request)` spawns `projectile.<projectile_id>` under `WorldService.entities_root()` (the
## y-sorted world root, so it goes with the world on travel) with its root at the shooter's old
## Phaser centre, and launches it at the player's hurtbox with the shooter's damage, knockback and
## web (`stick_ms`). The projectile frees itself when it expires (projectile.gd), which replaces
## Phaser's `finishExpiredProjectiles`.
##
## Owner: enemy port.

const Services := preload("res://game/shared/services.gd")
const ProjectileScript := preload("res://game/scripts/projectile.gd")

## UniversalSceneWorldController.ts:2106-2110.
const WEAPON_TAGS: Array[String] = ["enemy", "projectile"]
const DAMAGE_TYPES: Array[String] = ["physical"]
const WEB_EFFECT_ID := "web"
const SCENE_PREFIX := "projectile."


## `request` = {"source": Node (the shooter), "position": Vector2 (old Phaser centre),
## "direction": Vector2, "speed": float, "damage": float, "knockback_strength": float,
## "projectile_id": String, "asset_id": String, "stick_ms": float (0 = no web)}.
## Returns the projectile root, or null (push_error) when it cannot be spawned.
static func fire(request: Dictionary) -> Node2D:
	var projectile_id := str(request.get("projectile_id", ""))
	var source: Variant = request.get("source")
	var source_id := str((source as Node).get_path()) if source is Node and is_instance_valid(source) \
		and (source as Node).is_inside_tree() else ""
	if projectile_id.is_empty():
		push_error("EnemyProjectiles: enemy '%s' projectile must reference an authored projectile scene." % source_id)
		return null
	var world := Services.world()
	if world == null:
		return null
	var root := world.spawn_at_phaser_position(SCENE_PREFIX + projectile_id, request.get("position", Vector2.ZERO))
	if root == null:
		return null
	var script := find_projectile_script(root)
	if script == null:
		push_error("EnemyProjectiles: projectile scene '%s' requires a ProjectileScript." % projectile_id)
		root.queue_free()
		return null
	var target_areas: Array = []
	var target := world.primary_target()
	var hurtbox: Variant = target.get("hurtbox")
	if hurtbox is Area2D:
		target_areas.append(hurtbox)
	var effects: Array = []
	var stick_ms := float(request.get("stick_ms", 0.0))
	if stick_ms > 0.0:
		effects.append({"effect_id": WEB_EFFECT_ID, "potency": stick_ms})
	script.launch(request.get("direction", Vector2.ZERO), float(request.get("speed", 0.0)), {
		"source_node_id": source_id,
		"damage": float(request.get("damage", 0.0)),
		"knockback_strength": float(request.get("knockback_strength", 0.0)),
		"weapon_id": projectile_id,
		"weapon_tags": WEAPON_TAGS.duplicate(),
		"damage_types": DAMAGE_TYPES.duplicate(),
		"target_areas": target_areas,
		"effects": effects,
	})
	return root


## The ProjectileScript under a projectile root, or null.
static func find_projectile_script(root: Node) -> ProjectileScript:
	for child: Node in root.get_children():
		if child is ProjectileScript:
			return child as ProjectileScript
	return null
