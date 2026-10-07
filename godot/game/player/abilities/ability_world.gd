extends RefCounted
## What abilities do to the world (Phaser `UniversalSceneWorldController.ts`: `strikeArea`
## :1391-1442, `lineReach` :1252-1264, `lashProbe` :1271-1300, `firstBellAlong` :1307-1329,
## `lashRing` :1332-1347; `SensorGeometry.ts:194-230`; abilities spec 6.2, 8.1, 8.3).
## Points are old Phaser centres; shapes are read in world space.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

## Hurtbox layer 4 (bit 8); the world layer 1.
const HURTBOX_MASK := 8
const WORLD_MASK := 1
## Static bodies smaller than this in both directions never block a line (PhaserNodeContext).
const SMALL_BODY_PX := 20.0
## The lash: a goo hook 16 px wide each side; bells right next to the slime are skipped.
const LASH_HALF_WIDTH := 16.0
const LASH_NEAR_PX := 24.0
const LASH_PICKUP_RADIUS := 18.0
const LASH_RING_BACK := 6.0
const LASH_RING_DEPTH := 24.0
const BELL_GROUP := &"lash-bell"
const COLLECTIBLE_GROUP := &"collectible"
const HIT_SPARK_RISE := 12.0


## Squash Slam's strike: every registered hurtbox (not the player's, not a "resource") whose shape
## meets the circle gets one router hit of `damage` with a knockback away from the centre.
## Returns the number of accepted hits.
static func strike_area(player: Node, centre: Vector2, radius: float, damage: float, knockback: float, weapon_tags: Array) -> int:
	var router := Services.router()
	var world := Services.world()
	var attack_area := player.call(&"get_slam_area") as Area2D if player.has_method(&"get_slam_area") else null
	if router == null or world == null or attack_area == null or not is_instance_valid(world.world_root):
		return 0
	var space := world.world_root.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, centre)
	query.collision_mask = HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var targets: Array[Area2D] = []
	for hit: Dictionary in space.intersect_shape(query, 64):
		var area := hit.get("collider") as Area2D
		if area == null or area in targets:
			continue
		var receiver := router.receiver_for_area(area)
		if receiver == null or receiver == player or "resource" in router.tags_for_area(area):
			continue
		targets.append(area)
	if targets.is_empty():
		return 0
	var activation := router.begin_activation(player, [attack_area])
	var accepted := 0
	var feel := Services.feel()
	for area in targets:
		var at := area.global_position
		var distance := at.distance_to(centre)
		var knock := (at - centre) / distance if distance > 0.0 else Vector2.ZERO
		var result := router.route({"activation_id": activation, "source": player, "attack_area": attack_area,
			"target_area": area, "weapon_id": "squash-slam", "weapon_tags": weapon_tags,
			"damage_types": ["physical"], "base_damage": damage,
			"effects": [{"effect_id": "knockback", "potency": knockback}],
			"impact": {"position": at, "knock": knock}})
		if str(result.get("status", "")) == "accepted":
			accepted += 1
			if float(result.get("actual_damage", 0.0)) > 0.0 and feel != null:
				feel.particles(&"hit-spark", at - Vector2(0.0, HIT_SPARK_RISE))
	router.end_activation(activation)
	if accepted > 0 and feel != null:
		feel.play(&"hit")
	return accepted


## `lineReach`: how far the line from `from` to `to` gets before a static world body (tiles and
## bodies under 20 x 20 px never block). Returns the last open point (Phaser bisects; the hit point
## pulled back 1 px is within its 1.4 px).
static func line_reach(from: Vector2, to: Vector2, exclude: Array[RID]) -> Vector2:
	var world := Services.world()
	if world == null or not is_instance_valid(world.world_root):
		return to
	var space := world.world_root.get_world_2d().direct_space_state
	var skip := exclude.duplicate()
	for attempt in 16:
		var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK, skip)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return to
		var collider := hit.get("collider") as Node
		if collider == null or _never_blocks(collider):
			skip.append(hit["rid"])
			continue
		var point: Vector2 = hit["position"]
		var direction := (to - from).normalized()
		return point - direction if point.distance_to(from) > 1.0 else from
	return to


## `lashProbe`: what the hook catches between `from` and `to` (half width 16).
## {"kind": "none"|"light"|"heavy", "at": Vector2, "pickup": Node?, "anchor": Vector2?, "bell": Node?}.
static func lash_probe(from: Vector2, to: Vector2, exclude: Array[RID]) -> Dictionary:
	var reach := line_reach(from, to, exclude)
	var blocked := reach.distance_to(to) > 0.001
	var bell := first_bell_along(from, reach)
	if not bell.is_empty():
		reach = bell["at"]
		blocked = true
	var pickup := _first_pickup_along(from, reach)
	if pickup != null:
		return {"kind": "light", "at": (pickup.get_parent() as Node2D).global_position, "pickup": pickup}
	if not bell.is_empty():
		var post := (bell["bell"] as Node).get_parent() as Node2D
		return {"kind": "heavy", "at": reach, "anchor": post.global_position if post != null else reach, "bell": bell["bell"]}
	return {"kind": "heavy" if blocked else "none", "at": reach}


## `firstBellAlong`: the nearest bell whose damage area the hook passes within 16 px of, at least
## 24 px out. {"bell": Node, "at": Vector2} or {}.
static func first_bell_along(from: Vector2, to: Vector2) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var best := {}
	var best_along := INF
	var length := from.distance_to(to)
	if length <= 0.0:
		return {}
	var direction := (to - from) / length
	for bell: Node in tree.get_nodes_in_group(BELL_GROUP):
		var area := bell.get(&"damage_area") as Area2D
		if area == null or not area.is_inside_tree() or not shape_touches_segment(area, from, to, LASH_HALF_WIDTH):
			continue
		var along := 0.0
		while along <= length:
			var point := from + direction * along
			if distance_to_area(area, point) <= LASH_HALF_WIDTH:
				if along >= LASH_NEAR_PX and along < best_along:
					best_along = along
					best = {"bell": bell, "at": point}
				break
			along += 4.0
	return best


## `lashRing`: rings every bell whose damage area meets the hook's tip (6 px back to 24 px past
## where it caught). Returns how many rang.
static func lash_ring(from: Vector2, caught: Vector2) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or caught == from:
		return 0
	var direction := (caught - from).normalized()
	var tip_from := caught - direction * LASH_RING_BACK
	var tip_to := caught + direction * LASH_RING_DEPTH
	var rung := 0
	for bell: Node in tree.get_nodes_in_group(BELL_GROUP):
		var area := bell.get(&"damage_area") as Area2D
		if area != null and area.is_inside_tree() and shape_touches_segment(area, tip_from, tip_to, LASH_HALF_WIDTH):
			bell.call(&"ring")
			rung += 1
	return rung


## `SensorGeometry` segment test: samples every max(4, half_width) px (ends included) and accepts
## when one is within `half_width` of one of the area's shapes.
static func shape_touches_segment(area: Area2D, from: Vector2, to: Vector2, half_width: float) -> bool:
	var length := from.distance_to(to)
	var step := maxf(4.0, half_width)
	var count := maxi(1, ceili(length / step))
	for i in count + 1:
		var point := from.lerp(to, float(i) / count) if length > 0.0 else from
		if distance_to_area(area, point) <= half_width:
			return true
	return false


## Distance from `point` to the nearest shape of `area` (0 inside); INF when it has none.
static func distance_to_area(area: Area2D, point: Vector2) -> float:
	var best := INF
	for child: Node in area.get_children():
		var node := child as CollisionShape2D
		if node == null or node.disabled or node.shape == null:
			continue
		var local := node.global_transform.affine_inverse() * point
		var scale := node.global_transform.get_scale()
		if node.shape is RectangleShape2D:
			var half := (node.shape as RectangleShape2D).size / 2.0
			var outside := Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.y) - half.y, 0.0))
			best = minf(best, (outside * scale).length())
		elif node.shape is CircleShape2D:
			var radius := (node.shape as CircleShape2D).radius
			best = minf(best, maxf(0.0, local.length() - radius) * scale.x)
	return best


## The nearest uncollected pile whose 18 px circle the hook passes within 16 px of.
static func _first_pickup_along(from: Vector2, to: Vector2) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var segment := to - from
	var length_squared := segment.length_squared()
	var best: Node = null
	var best_t := INF
	for node: Node in tree.get_nodes_in_group(COLLECTIBLE_GROUP):
		var root := node.get_parent() as Node2D
		if root == null or root.is_queued_for_deletion() or int(node.call(&"remaining")) <= 0:
			continue
		var centre := root.global_position
		var t := 0.0 if length_squared == 0.0 else clampf((centre - from).dot(segment) / length_squared, 0.0, 1.0)
		var closest := from + segment * t
		if closest.distance_to(centre) <= LASH_PICKUP_RADIUS + LASH_HALF_WIDTH and t < best_t:
			best_t = t
			best = node
	return best


## Tile collision, the world bounds and small bodies never stop the lash.
static func _never_blocks(collider: Node) -> bool:
	if collider is TileMapLayer or String(collider.name) == "WorldBounds":
		return true
	var width := 0.0
	var height := 0.0
	for child: Node in collider.get_children():
		var node := child as CollisionShape2D
		if node == null or node.shape == null:
			continue
		var rect := node.shape.get_rect()
		width = maxf(width, rect.size.x * absf(node.global_transform.get_scale().x))
		height = maxf(height, rect.size.y * absf(node.global_transform.get_scale().y))
	return width < SMALL_BODY_PX and height < SMALL_BODY_PX and (width > 0.0 or height > 0.0)
