extends RefCounted
## What the pointer is over for the mouse control schemes (game/player/mouse/control_scheme.gd), in
## this order: an enemy or a resource (its hurtbox within `input.mouse.pickRadiusPx` of the
## pointer, the nearest wins) -> attack; something usable (InteractionController.target_at) -> use;
## else the ground -> walk.
##
## Owner: player builder.

const Services := preload("res://game/shared/services.gd")
const ClickPath := preload("res://game/player/mouse/click_path.gd")

## Physics layer 4 "hurtbox" (project.godot layer_names).
const HURTBOX_LAYER_BIT := 8
## Script groups whose nodes have a `damage_area` hurtbox the player's weapon can hit.
const ATTACKABLE_GROUPS: Array[StringName] = [&"enemy", &"resource_node"]
const KIND_ATTACK := "attack"
const KIND_USE := "use"
const KIND_GROUND := "ground"
## The interaction candidates' `origin` is this far above the object's root
## (InteractionController.TARGET_BODY_RISE_PX).
const USE_RING_DROP := 24.0


## {"kind": KIND_ATTACK, "node"} | {"kind": KIND_USE, "key", "stand_at": Callable() -> Vector2,
## "ring_at": Vector2} | {"kind": KIND_GROUND}.
static func at(tree: SceneTree, space: PhysicsDirectSpaceState2D, pointer: Vector2, radius: float, interaction: Node) -> Dictionary:
	var attackable := attackable_at(tree, space, pointer, radius)
	if attackable != null:
		return {"kind": KIND_ATTACK, "node": attackable}
	if interaction != null and interaction.has_method(&"target_at"):
		var usable: Dictionary = interaction.call(&"target_at", pointer)
		if not usable.is_empty():
			var origin: Callable = usable.get("origin", Callable())
			if origin.is_valid():
				return {"kind": KIND_USE, "key": interaction.call(&"key_of", usable), "stand_at": origin,
					"ring_at": _root_of(usable.get("node"), (origin.call() as Vector2) + Vector2(0.0, USE_RING_DROP))}
	return {"kind": KIND_GROUND}


## The living enemy or standing resource whose hurtbox is nearest `pointer` within `radius`.
static func attackable_at(tree: SceneTree, space: PhysicsDirectSpaceState2D, pointer: Vector2, radius: float) -> Node:
	if tree == null or space == null:
		return null
	var circle := CircleShape2D.new()
	circle.radius = maxf(1.0, radius)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, pointer)
	query.collision_mask = HURTBOX_LAYER_BIT
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hits := space.intersect_shape(query, 32)
	if hits.is_empty():
		return null
	var owners := {}
	for group: StringName in ATTACKABLE_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			var area: Variant = node.get(&"damage_area")
			if area is Area2D and is_alive(node):
				owners[area] = node
	var best: Node = null
	var best_distance := INF
	for hit: Dictionary in hits:
		var collider: Variant = hit.get("collider")
		if not owners.has(collider):
			continue
		var node: Node = owners[collider]
		var distance := hurtbox_centre(node).distance_to(pointer)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best


## Still worth swinging at: in the tree, not defeated (enemies), not destroyed (resources).
static func is_alive(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if node.has_method(&"is_defeated") and bool(node.call(&"is_defeated")):
		return false
	if node.has_method(&"is_destroyed") and bool(node.call(&"is_destroyed")):
		return false
	return true


## The centre of the node's hurtbox (its first collision shape), where the swing aims.
static func hurtbox_centre(node: Node) -> Vector2:
	var area := node.get(&"damage_area") as Area2D if node != null and is_instance_valid(node) else null
	if area == null:
		return Vector2.ZERO
	for child in area.get_children():
		var shape := child as CollisionShape2D
		if shape != null:
			return shape.global_position
	return area.global_position


## The level the node's body walks on (Elevation.level_of); ClickPath.NO_LEVEL when it has no body
## or the world no elevation (the route then takes the ground seen there).
static func level_of(node: Node) -> int:
	var world := Services.world()
	var body: Variant = node.get(&"body") if node != null and is_instance_valid(node) else null
	if world == null or world.elevation == null or not (body is Node2D and is_instance_valid(body)):
		return ClickPath.NO_LEVEL
	return world.elevation.level_of(body as Node)


## Where the node stands: its body's feet (enemies), its root (resources), else its hurtbox.
static func feet_of(node: Node) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2.ZERO
	var body: Variant = node.get(&"body")
	if body is Node2D and is_instance_valid(body):
		return (body as Node2D).global_position
	if node.has_method(&"world_position"):
		return node.call(&"world_position")
	return hurtbox_centre(node)


## The root a usable thing stands on (its script's parent), else `fallback`.
static func _root_of(node: Variant, fallback: Vector2) -> Vector2:
	if node is Node2D and is_instance_valid(node):
		return (node as Node2D).global_position
	if node is Node and is_instance_valid(node) and (node as Node).get_parent() is Node2D:
		return ((node as Node).get_parent() as Node2D).global_position
	return fallback
