extends RefCounted
class_name EffectSpawner
## Spawns one-shot effect scenes (`effect.<id>`) in the world (Phaser
## `UniversalSceneWorldController.spawnEffect :1599-1635`). Combat spec 9.1 and F8.
##
## Owner: combat builder.

const Services := preload("res://game/shared/services.gd")
const EffectScript := preload("res://game/scripts/effect.gd")

## Combat spec F8: the holder sorts one pixel below the target's feet, so the effect draws in
## front of the struck target in the y-sorted world.
const HOLDER_SORT_OFFSET_Y := 1.0


## Spawns `effect.<effect_id>` so it draws in front of the struck target: a plain Node2D holder
## at `(target_feet.x, target_feet.y + 1)` under `Services.world().entities_root()` (y-sorted),
## the effect instance as its child at local `target_centre - holder position`; then
## `EffectScript.play(direction)`. The holder frees itself when the effect root leaves the tree.
## Returns the effect root or null (unknown scene).
static func spawn_in_front(effect_id: String, direction: String, target_centre: Vector2, target_feet: Vector2) -> Node2D:
	var world := Services.world()
	if world == null:
		return null
	var parent: Node2D = world.entities_root()
	if parent == null or not is_instance_valid(parent):
		return null
	var instance := world.instantiate_scene("effect.%s" % effect_id)
	if instance == null:
		return null
	var root := instance as Node2D
	if root == null:
		push_error("EffectSpawner: effect.%s root is not a Node2D" % effect_id)
		instance.free()
		return null
	var script := _find_effect_script(root)
	if script == null:
		push_error("EffectSpawner: effect.%s has no EffectScript" % effect_id)
		root.free()
		return null

	var holder := Node2D.new()
	holder.name = "EffectHolder"
	parent.add_child(holder)
	holder.global_position = Vector2(target_feet.x, target_feet.y + HOLDER_SORT_OFFSET_Y)
	root.position = target_centre - holder.global_position
	holder.add_child(root)
	root.tree_exited.connect(_free_holder.bind(holder.get_instance_id()), CONNECT_ONE_SHOT)
	holder.reset_physics_interpolation()
	script.play(direction)
	return root


## Bound by instance id so a holder freed with the world is never passed as a freed object.
static func _free_holder(holder_id: int) -> void:
	var holder := instance_from_id(holder_id) as Node
	if holder != null and not holder.is_queued_for_deletion():
		holder.queue_free()


static func _find_effect_script(root: Node) -> EffectScript:
	for child in root.get_children():
		if child is EffectScript:
			return child as EffectScript
	for node in root.find_children("*", "Node", true, false):
		if node is EffectScript:
			return node as EffectScript
	return null
