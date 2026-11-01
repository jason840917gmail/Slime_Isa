extends Area2D
## A mud ball's hurtbox (lair_director.gd `_drop_clod`; docs/godot/DUNGEONS.md "Fatty's Lair"): a
## Roll's bonk breaks the ball, and what it hid (a heart or an energy shard: liftable_root.gd
## `under`) is left where it stood. Anything else passes. The area is its own receiver for DamageRouter.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const ROLL_TAG := "roll"
const ROLL_RULE := {"priority": 0, "damageMultiplier": 1}
const TAGS: Array[String] = []
const HIT_LIFT := 10.0
const CUE_BREAK := &"BreakStone"

var _broken: bool = false


func _init() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	# The ball's hurt circle (`dungeon.lair.clodHurtRadiusPx`, world units).
	circle.radius = DungeonState.number("lair.clodHurtRadiusPx", 22.0)
	shape.shape = circle
	shape.position = Vector2(0.0, -HIT_LIFT)
	add_child(shape)


func _ready() -> void:
	var router := Services.router()
	if router != null:
		router.register_area(self, self, ROLL_RULE, TAGS)


func _exit_tree() -> void:
	var router := Services.router()
	if router != null:
		router.unregister_area(self)


func can_receive_damage(input: Dictionary) -> Dictionary:
	if _broken:
		return {"accepted": false, "reason": "pass"}
	var request: Dictionary = input.get("request", {})
	var tags: Variant = request.get("weapon_tags", [])
	if tags is Array and (tags as Array).has(ROLL_TAG):
		return {"accepted": true, "reason": ""}
	return {"accepted": false, "reason": "pass"}


func mitigate_damage(_input: Dictionary) -> float:
	return 1.0


func commit_damage(_commit: Dictionary) -> void:
	if _broken:
		return
	_broken = true
	var root := get_parent()
	if root != null and not root.is_queued_for_deletion():
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_BREAK)
			feel.particles(&"dodge-dust", (root as Node2D).global_position)
		root.queue_free()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass
