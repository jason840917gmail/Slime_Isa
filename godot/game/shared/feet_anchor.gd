extends RefCounted
class_name FeetAnchor
## Conversions between the Godot root origin (the feet) and the old Phaser root position.
##
## Conventions "Feet origin": a converted scene root with `depthAnchor` is re-anchored so its
## origin is the old depth anchor and carries `metadata/depth_anchor` (the original anchor in
## the root's local units). The old Phaser root position P ("centre" for the player and the
## enemies, sprite bottom for NPCs) is `global_position - depth_anchor * scale`.
## Gameplay maths that Phaser did on P (ranges, aim, knock directions, spawn points, perimeters,
## floating text) must use `phaser_position()` to keep parity (enemy spec section 9, combat
## spec section 14, player spec section 11, world spec section 0).
##
## Owner: world builder. Architect wrote it complete.

const META_KEY := &"depth_anchor"


## The root's `metadata/depth_anchor`, or Vector2.ZERO when the scene has none.
static func depth_anchor(root: Node2D) -> Vector2:
	if root == null or not root.has_meta(META_KEY):
		return Vector2.ZERO
	var value: Variant = root.get_meta(META_KEY)
	return value if value is Vector2 else Vector2.ZERO


## Old Phaser root position of a re-anchored root: `global_position - depth_anchor * scale`.
static func phaser_position(root: Node2D) -> Vector2:
	if root == null:
		return Vector2.ZERO
	return root.global_position - depth_anchor(root) * root.scale


## Godot global position that puts the old Phaser root position of `root` at `phaser_point`.
static func global_for_phaser_position(root: Node2D, phaser_point: Vector2) -> Vector2:
	return phaser_point + depth_anchor(root) * root.scale


## Moves `root` so its old Phaser root position is `phaser_point` (spawning, respawn, teleport).
static func place_at_phaser_position(root: Node2D, phaser_point: Vector2) -> void:
	root.global_position = global_for_phaser_position(root, phaser_point)


## Local offset from the feet to the old Phaser root position (`-depth_anchor`); e.g. where the
## weapon is mounted on the player (combat spec F1) or where the camera aims (world spec 4.3).
static func local_phaser_origin(root: Node2D) -> Vector2:
	return -depth_anchor(root)
