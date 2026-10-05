extends RefCounted
## Arcade-style body mover: the Godot stand-in for Phaser Arcade integrating a
## body's velocity and separating it from blocking colliders with bounce 0
## (CharacterBody2DNode.ts writes the Arcade velocity and reads it back after the
## step; PhaserNodeContext.ts adds the plain colliders). Every moving body in the
## port (player, enemies, NPCs) moves with this, never with `move_and_slide()`.
##
## Arcade moves a body by `velocity · dt`, separates it from what blocks it and
## zeroes only the velocity component into the wall, so the tangential component
## keeps its own speed: a worm meeting a wall at 20° and 75 px/s slides at about
## 25.7 px/s, and a diagonal walk into a wall slides at the diagonal's tangential
## speed. `move_and_slide()` in floating mode differs twice: it redirects the whole
## remaining motion along the wall at full speed (about 41 % faster on a diagonal),
## stops the body dead within `wall_min_slide_angle` of head-on, and never cuts
## `velocity`. Walls in the converted worlds are rectangles (as Arcade's AABBs), so
## sliding along a surface equals Arcade's per-axis separation.
##
## Ellipse CharacterBody2D shapes (Fatty, the spiders) block as their bounding boxes,
## as in Arcade: the converter writes them as rectangles (scripts/godot/lib/shapes.mjs).
##
## Stateless; reference it with
## `const ArcadeMover := preload("res://game/shared/arcade_mover.gd")`.


## Moves `body` by `body.velocity · delta` (delta defaults to the physics step),
## sliding along whatever blocks it. The velocity component pointing into each
## contact normal is removed from `body.velocity`, which is what the body's script
## reads back next step (knockback decay, stun slides, rolls). Returns true when
## anything was hit. Always tests at least once, so a body that overlaps something
## (after a teleport or spawn) is pushed out even at rest.
static func move(body: CharacterBody2D, delta: float = -1.0) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	if delta < 0.0:
		delta = body.get_physics_process_delta_time()
	var motion := body.velocity * delta
	var hit := false
	for _i in maxi(1, body.max_slides):
		var collision := body.move_and_collide(motion, false, body.safe_margin)
		if collision == null:
			break
		hit = true
		var normal := collision.get_normal()
		if body.velocity.dot(normal) < 0.0:
			body.velocity = body.velocity.slide(normal)
		var remainder := collision.get_remainder()
		motion = remainder.slide(normal) if remainder.dot(normal) < 0.0 else remainder
		if motion.is_zero_approx():
			break
	return hit
