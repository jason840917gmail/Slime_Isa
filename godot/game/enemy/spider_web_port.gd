extends RefCounted
class_name SpiderWebPort
## The world side of spider webs (Phaser `WorldScene` closures behind the `world.spider-web` port,
## `scenes/WorldScene.ts:2347-2357`, plus `catchInWeb` :2132-2142, `applyWeb` :1758-1771 and
## `teleportPlayer` :1584-1588). Matron spec 5 (docs/godot/specs/matron.md) and enemy spec 12.6.
## Used by `game.spider-web` (spider_web.gd), `game.web-patch` (web_patch.gd) and projectile.gd.
##
## The player side is player.gd's (the abilities work, abilities spec 19.3): `crosses_webs()` (the
## Sticky Gulp form, Phaser `playerCrossesWebs`) and `teleport(centre)` (Phaser `teleportPlayer`)
## are called directly; `apply_web(duration_ms)` (the rooted `sticky` status and its web cover)
## does not exist yet and is duck-typed: until it does, a web catch stops the slime and suppresses
## its movement for the duration, with the web cover drawn over it, and a web projectile hit only
## shows the cover (its knockback must still play, which a suppression would freeze).
##
## Zones are Dictionaries in Phaser's camelCase: {"x", "y", "halfWidth", "halfHeight"} (old Phaser
## world positions), also the `caught` / `torn` signal payloads.
##
## Owner: enemy port.

const Services := preload("res://game/shared/services.gd")
const EffectSpawner := preload("res://game/combat/effect_spawner.gd")
const DamageResolver := preload("res://game/combat/damage_resolver.gd")
const PlayerScript := preload("res://game/scripts/player.gd")

## WorldScene.catchInWeb (:2133-2142): the slime lands this far beyond the zone edge, stuck 900 ms.
const SET_BACK_ABOVE_PX := 26.0
const SET_BACK_BELOW_PX := 30.0
const CATCH_WEB_MS := 900.0
## The catch message: at most every 2500 ms (scene time), 56 px above the slime, 2200 ms.
const CATCH_MESSAGE := "Caught in the web! (something sticky could cross)"
const CATCH_MESSAGE_THROTTLE_MS := 2500.0
const CATCH_MESSAGE_RISE_PX := 56.0
const CATCH_MESSAGE_MS := 2200.0
## `webTorn` (WorldScene.ts:2352-2356): cue `WebTear` (AudioEventBridge 'web.torn'), loot sparkle,
## cyan text 40 px above the zone for 1800 ms.
const TORN_CUE := &"WebTear"
const TORN_PARTICLES := &"loot-sparkle"
const TORN_MESSAGE := "The web tears open!"
const TORN_MESSAGE_RISE_PX := 40.0
const TORN_MESSAGE_MS := 1800.0
## `applyWeb`: the web wrapped around the slime (`effect.spider-web-cover`, direction right).
const WEB_COVER_EFFECT := "spider-web-cover"
const WEB_EFFECT_ID := "web"
## main.gd joins this group (`is_transitioning`).
const MAIN_GROUP := &"world_main"
## Per-world throttle of the catch message (WorldScene `nextWebMessageAt`), kept on the world root.
const MESSAGE_META := &"next_web_message_at_real_ms"


## The registered player script, or null.
static func player() -> PlayerScript:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player) or not world.player.is_inside_tree():
		return null
	return world.player


## `playerPosition()`: the player's old Phaser centre while it lives and no travel runs, else null.
static func player_position() -> Variant:
	var target := player()
	if target == null or target.is_dead() or _transitioning():
		return null
	return target.get_centre()


## `playerCrossesWebs()`: the Gulp form crosses webs (Sticky; player.gd `crosses_webs()`).
static func player_crosses_webs() -> bool:
	var target := player()
	return target != null and target.crosses_webs()


## `catchInWeb(zone)`: set the slime back above the zone (when its centre is above the zone's) or
## below it, stuck for 900 ms, with a throttled message.
static func catch_player(zone: Dictionary) -> void:
	var target := player()
	if target == null:
		return
	var centre := target.get_centre()
	var zone_y := float(zone.get("y", 0.0))
	var half_height := float(zone.get("halfHeight", 0.0))
	var from_above := centre.y < zone_y
	var landing := Vector2(centre.x, zone_y - half_height - SET_BACK_ABOVE_PX if from_above \
		else zone_y + half_height + SET_BACK_BELOW_PX)
	teleport_player(target, landing)
	apply_web(target, CATCH_WEB_MS)
	var world := Services.world()
	var root: Node2D = world.entities_root() if world != null else null
	var now := float(Time.get_ticks_msec())
	if root == null or now < float(root.get_meta(MESSAGE_META, 0.0)):
		return
	root.set_meta(MESSAGE_META, now + CATCH_MESSAGE_THROTTLE_MS)
	var feel := Services.feel()
	if feel != null:
		var at := target.get_centre()
		feel.floating_text(at - Vector2(0.0, CATCH_MESSAGE_RISE_PX), CATCH_MESSAGE, &"white", true, CATCH_MESSAGE_MS)


## `webTorn(zone)`: the Sticky slime tore a web barrier open for good.
static func web_torn(zone: Dictionary) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	var at := Vector2(float(zone.get("x", 0.0)), float(zone.get("y", 0.0)))
	feel.audio_cue(TORN_CUE)
	feel.particles(TORN_PARTICLES, at)
	feel.floating_text(at - Vector2(0.0, TORN_MESSAGE_RISE_PX), TORN_MESSAGE, &"cyan", true, TORN_MESSAGE_MS)


## `teleportPlayer` (WorldScene.ts:1584-1588): player.gd's `teleport(centre)` (stop and place).
static func teleport_player(target: PlayerScript, centre: Vector2) -> void:
	if target != null:
		target.teleport(centre)


## `applyWeb(ms)`: player.gd's `apply_web(ms)` when it has one; else (Godot fallback) stop and
## suppress the slime's movement for `ms`, and wrap it in the web cover unless it was already held.
static func apply_web(target: Node, duration_ms: float) -> void:
	if target == null or duration_ms <= 0.0:
		return
	if target.has_method(&"apply_web"):
		target.call(&"apply_web", duration_ms)
		return
	var held := target.has_method(&"is_movement_suppressed") and bool(target.call(&"is_movement_suppressed"))
	if target.has_method(&"stop_movement"):
		target.call(&"stop_movement")
	if target.has_method(&"suppress_movement"):
		target.call(&"suppress_movement", duration_ms)
	if not held:
		spawn_web_cover(target)


## A routed projectile hit with an applied `web` effect (enemy spec 12.6): the player applies the
## web itself in `publish_damage_feedback` once it has `apply_web`; until then show the cover only.
static func after_web_hit(receiver: Object, result: Dictionary) -> void:
	if receiver == null or not is_instance_valid(receiver) or not (receiver is Node):
		return
	if str(result.get("status", "")) != "accepted" or bool(result.get("defeated", false)):
		return
	if DamageResolver.applied_potency(result, WEB_EFFECT_ID) <= 0.0 or receiver.has_method(&"apply_web"):
		return
	spawn_web_cover(receiver as Node)


## `effect.spider-web-cover` drawn in front of the slime (Phaser follows it with depth + 1).
static func spawn_web_cover(target: Node) -> Node2D:
	if not target.has_method(&"get_centre"):
		return null
	var body := target.get(&"body") as Node2D
	var centre: Vector2 = target.call(&"get_centre")
	var feet := body.global_position if body != null else centre
	return EffectSpawner.spawn_in_front(WEB_COVER_EFFECT, "right", centre, feet)


static func _transitioning() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var main := tree.get_first_node_in_group(MAIN_GROUP)
	return main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning"))
