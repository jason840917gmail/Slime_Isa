extends RefCounted
## Placed furniture in the world (Phaser `UniversalSceneWorldController.mountPlacedFurniture`,
## `unmountPlacedFurniture`, `describePlaceable`; furniture spec 1.3, 7, 11.3). A placed bench is
## its converted object scene (`object.interior-workshop-workbench`, ...) spawned at the record's
## old Phaser position under the world's y-sorted entities root: its StaticBody2D blocks like any
## prop, it sorts by its root y, and its `workbench.gd` makes it a crafting station. The root is
## named after the record id and carries the `placement_id` meta (the interaction controller
## offers "Hold: Pick up" for it).
##
## Owner: world objects (building).

const Services := preload("res://game/shared/services.gd")

const META := &"placement_id"
const GROUP := &"placed_furniture"


## The ghost's look and the footprint of `scene_id` (§1.3): {} when the scene is unknown or has
## no Sprite2D; else {"scene_id", "sprite": a detached duplicate of the first Sprite2D (texture,
## frames, offset, scale, ...), "footprint": Rect2 relative to the root (the first
## RectangleShape2D collider) or null, "depth_anchor": Vector2}.
static func describe(scene_id: String) -> Dictionary:
	var world := Services.world()
	if world == null or world.scene_path(scene_id).is_empty():
		return {}
	var packed := world.packed_scene(scene_id)
	if packed == null:
		return {}
	var root := packed.instantiate()
	var sprite: Sprite2D = null
	for node: Node in root.find_children("*", "Sprite2D", true, false):
		sprite = node as Sprite2D
		break
	if sprite == null:
		root.free()
		return {}
	var footprint: Variant = null
	for node: Node in root.find_children("*", "CollisionShape2D", true, false):
		var shape := (node as CollisionShape2D).shape as RectangleShape2D
		if shape != null:
			var at := (node as CollisionShape2D).position
			footprint = Rect2(at - shape.size / 2.0, shape.size)
			break
	var copy := sprite.duplicate() as Sprite2D
	copy.position = sprite.position
	var anchor: Variant = root.get_meta(&"depth_anchor", Vector2.ZERO) if root.has_meta(&"depth_anchor") else Vector2.ZERO
	root.free()
	return {"scene_id": scene_id, "sprite": copy, "footprint": footprint,
		"depth_anchor": anchor if anchor is Vector2 else Vector2.ZERO}


## Mounts `record` ({"id", "scene_id", "x", "y"}) in the current world; the existing node when it is
## already mounted; null (with a warning; the record stays) when the scene cannot be spawned.
static func mount(record: Dictionary) -> Node2D:
	var id := str(record.get("id", ""))
	var existing := find(id)
	if existing != null:
		return existing
	var world := Services.world()
	var scene_id := str(record.get("scene_id", ""))
	if world == null or world.scene_path(scene_id).is_empty():
		push_warning("PlacedFurniture: '%s' has an unknown scene '%s'" % [id, scene_id])
		return null
	var root := world.spawn_at_phaser_position(scene_id, Vector2(float(record.get("x", 0.0)), float(record.get("y", 0.0))))
	if root == null:
		return null
	root.name = id
	root.set_meta(META, id)
	root.add_to_group(GROUP)
	return root


## The mounted root of `placement_id`, or null.
static func find(placement_id: String) -> Node2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or placement_id.is_empty():
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		if str(node.get_meta(META, "")) == placement_id and not node.is_queued_for_deletion():
			return node as Node2D
	return null


static func unmount(placement_id: String) -> void:
	var root := find(placement_id)
	if root == null:
		return
	root.remove_from_group(GROUP)
	if root.get_parent() != null:
		root.get_parent().remove_child(root)
	root.queue_free()


## The placement id of the placed root above `node` (a station script, ...), "" when not placed.
static func placement_of(node: Node) -> String:
	var at := node
	while at != null:
		if at.has_meta(META):
			return str(at.get_meta(META))
		at = at.get_parent()
	return ""
