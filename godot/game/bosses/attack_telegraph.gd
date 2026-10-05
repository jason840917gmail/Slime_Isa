extends Node2D
class_name AttackTelegraph
## A ground warning where an attack will land (Phaser `features/effects/AttackTelegraphs.ts`):
## a shadow ellipse plus the attack's world-space shapes, filled and stroked, on the ground-decal
## band (`z_index -1`, as the converter maps `ground-decals`) and y-sorted at the shadow's y (the
## shapes' average centre y without a shadow). Static: it does not follow its attacker. Boss spec 3.6.
##
## One per attacker: `AttackTelegraph.show_for(attacker, shapes, shadow)` replaces the attacker's
## previous warning, `AttackTelegraph.clear_for(attacker)` removes it. The warning lives under
## `WorldService.entities_root()` (the y-sorted world root).
##
## Owner: boss port.

const Services := preload("res://game/shared/services.gd")
const AreaShapes := preload("res://game/bosses/area_shapes.gd")

## AttackTelegraphs.ts:11-16, 34.
const FILL := Color(Color("#ff7a3d"), 0.15)
const STROKE := Color(Color("#ffc85a"), 0.85)
const STROKE_WIDTH := 3.0
const SHADOW := Color(Color("#07120e"), 0.38)
const SHADOW_SIZE := Vector2(96.0, 34.0)
const SHADOW_POINTS := 48
## The converter's z_index for the `ground-decals` depth band (scripts/godot/lib/sprite.mjs).
const GROUND_DECALS_Z := -1
## Metadata key on the attacker that holds its live warning.
const OWNER_META := &"attack_telegraph"

## World-space outlines, already in this node's local space.
var _outlines: Array[PackedVector2Array] = []
var _shadow_local: Vector2 = Vector2.ZERO
var _has_shadow: bool = false


## Shows a warning for `attacker` (replacing its previous one). `shapes` are AreaShapes entries;
## `shadow` is a world point or null. Nothing is drawn when both are empty. Returns the node.
static func show_for(attacker: Node, shapes: Array[Dictionary], shadow: Variant = null) -> AttackTelegraph:
	clear_for(attacker)
	var has_shadow := shadow is Vector2
	if shapes.is_empty() and not has_shadow:
		return null
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null:
		return null
	var anchor_y := 0.0
	if has_shadow:
		anchor_y = (shadow as Vector2).y
	else:
		for entry: Dictionary in shapes:
			anchor_y += AreaShapes.centre(entry).y
		anchor_y /= float(shapes.size())
	var anchor_x: float = (shadow as Vector2).x if has_shadow else AreaShapes.centre(shapes[0]).x
	var telegraph := AttackTelegraph.new()
	telegraph.name = "AttackTelegraph"
	telegraph.z_index = GROUND_DECALS_Z
	telegraph.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(telegraph)
	telegraph.global_position = Vector2(anchor_x, anchor_y)
	telegraph._has_shadow = has_shadow
	if has_shadow:
		telegraph._shadow_local = telegraph.to_local(shadow as Vector2)
	for entry: Dictionary in shapes:
		var points := AreaShapes.outline(entry)
		if points.size() < 3:
			continue
		var local := PackedVector2Array()
		for point: Vector2 in points:
			local.append(telegraph.to_local(point))
		telegraph._outlines.append(local)
	telegraph.queue_redraw()
	attacker.set_meta(OWNER_META, telegraph.get_instance_id())
	return telegraph


## Removes `attacker`'s warning, if any.
static func clear_for(attacker: Node) -> void:
	if attacker == null or not attacker.has_meta(OWNER_META):
		return
	var telegraph := instance_from_id(int(attacker.get_meta(OWNER_META))) as Node
	attacker.remove_meta(OWNER_META)
	if telegraph != null and is_instance_valid(telegraph) and not telegraph.is_queued_for_deletion():
		telegraph.queue_free()


## The live warning of `attacker`, or null.
static func of(attacker: Node) -> AttackTelegraph:
	if attacker == null or not attacker.has_meta(OWNER_META):
		return null
	var telegraph := instance_from_id(int(attacker.get_meta(OWNER_META))) as AttackTelegraph
	return telegraph if telegraph != null and is_instance_valid(telegraph) and not telegraph.is_queued_for_deletion() else null


## Drawn outlines in world space (tests).
func world_outlines() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for outline: PackedVector2Array in _outlines:
		var points := PackedVector2Array()
		for point: Vector2 in outline:
			points.append(to_global(point))
		result.append(points)
	return result


## The shadow's world point, or null.
func shadow_point() -> Variant:
	return to_global(_shadow_local) if _has_shadow else null


func _draw() -> void:
	if _has_shadow:
		var ellipse := PackedVector2Array()
		for i in SHADOW_POINTS:
			var angle := TAU * i / float(SHADOW_POINTS)
			ellipse.append(_shadow_local + Vector2(cos(angle) * SHADOW_SIZE.x / 2.0, sin(angle) * SHADOW_SIZE.y / 2.0))
		draw_colored_polygon(ellipse, SHADOW)
	for outline: PackedVector2Array in _outlines:
		draw_colored_polygon(outline, FILL)
		var closed := outline.duplicate()
		closed.append(outline[0])
		draw_polyline(closed, STROKE, STROKE_WIDTH, true)
