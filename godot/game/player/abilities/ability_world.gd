extends RefCounted
## What abilities do to the world (Phaser `UniversalSceneWorldController.ts`: `strikeArea`
## :1391-1442, `lineReach` :1252-1264, `lashProbe` :1271-1300, `firstBellAlong` :1307-1329,
## `lashRing` :1332-1347; `SensorGeometry.ts:194-230`; abilities spec 6.2, 8.1, 8.3).
## Points are old Phaser centres; shapes are read in world space.
##
## Body-shapes rework (docs/godot/BODY_SHAPES.md "The hit"; combat-feel plan section 8): an area
## strike may carry a `hit` (HitReaction.build_hit), which rides on every request it routes with the
## `impact` effect instead of the old knockback, and it may hand every target's outcome to an
## `on_outcome` callback (the sender's clink and feel). The improved Squash Slam
## (slam_sequence.gd) strikes a ground ellipse on the slime's own height level
## (`hurtboxes_in_ellipse`, `strike_targets`).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")

## `level` argument of the hurtbox queries that means "on any height level" (old callers).
const ANY_LEVEL := -1000
## The ground ellipse is queried as a convex polygon of this many points.
const ELLIPSE_POINTS := 32
## The resolver's refusal for a hit the receiver does not take (a clink).
const REASON_IMMUNE := "immune"

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


## An area strike (a thrown rock, pot or essence with `weapon_id` "thrown-<kind>", the Roll's bonk):
## every registered hurtbox (not the player's, not a "resource") whose shape meets the circle gets
## one router hit of `damage` (`strike_targets`). Returns the number of accepted hits.
## Old callers pass no `hit`: a knockback of `knockback` away from the centre, as before.
## Rework (optional): `hit` and `on_outcome` as in `strike_targets`.
static func strike_area(player: Node, centre: Vector2, radius: float, damage: float, knockback: float, weapon_tags: Array,
		weapon_id: String = "squash-slam", hit: Dictionary = {}, on_outcome: Callable = Callable()) -> int:
	return strike_targets(player, centre, hurtboxes_at(player, centre, radius), damage, knockback, weapon_tags, weapon_id,
		hit, on_outcome)


## One router hit of `damage` on each of `targets` (hurtboxes from `hurtboxes_at` or
## `hurtboxes_in_ellipse`), in one activation of the player's slam area, each pushed away from
## `centre`. Returns the number of accepted hits.
## - Without `hit` (old style): the request carries a `knockback` effect of `knockback`; a hit spark
##   rises over every damaged target, and the `hit` feel plays once when one was accepted.
## - With `hit` (body-shapes rework, BODY_SHAPES.md "The hit"): the request carries a copy of it at
##   the top level (its `knock`, when ZERO, becomes the push away from `centre`) and the `impact`
##   effect (HitReaction.attach), no knockback (`knockback` is ignored: the hit's `launch_speed`
##   is the push), and nothing is played here: the sender plays the feel from the outcomes.
## `on_outcome` (optional, both styles) is called once per routed target, accepted or not, with
## {"receiver": Object, "area": Area2D, "position": Vector2, "result": Dictionary} (route()'s
## result; for a rework hit the enemy writes `result.reaction` into it), so the sender can clink
## on a refused hit (`is_clink`).
static func strike_targets(player: Node, centre: Vector2, targets: Array[Area2D], damage: float, knockback: float,
		weapon_tags: Array, weapon_id: String = "squash-slam", hit: Dictionary = {}, on_outcome: Callable = Callable()) -> int:
	var router := Services.router()
	var world := Services.world()
	var attack_area := player.call(&"get_slam_area") as Area2D if player.has_method(&"get_slam_area") else null
	if router == null or world == null or attack_area == null or not is_instance_valid(world.world_root):
		return 0
	if targets.is_empty():
		return 0
	var rework := not hit.is_empty()
	var activation := router.begin_activation(player, [attack_area])
	var accepted := 0
	var feel := Services.feel()
	for area in targets:
		if not is_instance_valid(area):
			continue
		var at := area.global_position
		var distance := at.distance_to(centre)
		var knock := (at - centre) / distance if distance > 0.0 else Vector2.ZERO
		var request := {"activation_id": activation, "source": player, "attack_area": attack_area,
			"target_area": area, "weapon_id": weapon_id, "weapon_tags": weapon_tags,
			"damage_types": ["physical"], "base_damage": damage,
			"effects": [{"effect_id": "knockback", "potency": knockback}],
			"impact": {"position": at, "knock": knock}}
		if rework:
			request["effects"] = []
			HitReaction.attach(request, hit_toward(hit, knock))
		var receiver := router.receiver_for_area(area)
		var result := router.route(request)
		if str(result.get("status", "")) == "accepted":
			accepted += 1
			if not rework and float(result.get("actual_damage", 0.0)) > 0.0 and feel != null:
				feel.particles(&"hit-spark", at - Vector2(0.0, HIT_SPARK_RISE))
		if on_outcome.is_valid():
			on_outcome.call({"receiver": receiver, "area": area, "position": at, "result": result})
	router.end_activation(activation)
	if accepted > 0 and feel != null and not rework:
		feel.play(&"hit")
	return accepted


## A copy of `hit` for one target: its own `knock` when it has one, else `knock` (away from the
## strike's centre).
static func hit_toward(hit: Dictionary, knock: Vector2) -> Dictionary:
	var copy := hit.duplicate(true)
	var own: Variant = copy.get("knock", Vector2.ZERO)
	if not (own is Vector2) or (own as Vector2) == Vector2.ZERO:
		copy["knock"] = knock
	return copy


## True when an outcome's result is a clink (BODY_SHAPES.md "The reaction"): the receiver refused
## the hit as `immune` (the wrong tool, a shut weak point), or a rework reaction answered `clink`.
static func is_clink(result: Dictionary) -> bool:
	if str(result.get("status", "")) == "rejected" and str(result.get("reason", "")) == REASON_IMMUNE:
		return true
	var reaction: Variant = result.get("reaction")
	return reaction is Dictionary and str((reaction as Dictionary).get("verb", "")) == HitReaction.VERB_CLINK


## The hurtboxes (not the player's, not a "resource") whose shape meets the circle at `centre`.
static func hurtboxes_at(player: Node, centre: Vector2, radius: float) -> Array[Area2D]:
	var shape := CircleShape2D.new()
	shape.radius = radius
	return _hurtboxes_in(player, shape, centre, ANY_LEVEL)


## The improved Slam's ground ellipse (body-shapes plan section 4): the hurtboxes (not the
## player's, not a "resource") whose shape meets the ellipse of half axes `half_size` around
## `centre`, and, unless `level` is ANY_LEVEL, only those of targets standing on height level
## `level` (`target_level`; docs/godot/ELEVATION.md), so a slam never reaches up or down a cliff.
static func hurtboxes_in_ellipse(player: Node, centre: Vector2, half_size: Vector2, level: int = ANY_LEVEL) -> Array[Area2D]:
	if half_size.x <= 0.0 or half_size.y <= 0.0:
		var none: Array[Area2D] = []
		return none
	var shape := ConvexPolygonShape2D.new()
	shape.points = ellipse_points(half_size)
	return _hurtboxes_in(player, shape, centre, level)


## The points of an ellipse of half axes `half_size` around the origin (`count` of them, in order).
static func ellipse_points(half_size: Vector2, count: int = ELLIPSE_POINTS) -> PackedVector2Array:
	var points := PackedVector2Array()
	var sides := maxi(3, count)
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle) * half_size.x, sin(angle) * half_size.y))
	return points


## The height level the target behind `area` stands on: its body's level when the elevation tracks
## it (enemies), else the level of the ground under it (a dummy's or a prop's root); `fallback`
## without elevation or on a wall.
static func target_level(area: Area2D, receiver: Object, fallback: int) -> int:
	var world := Services.world()
	var elevation: Elevation = world.elevation if world != null else null
	if elevation == null or area == null:
		return fallback
	var body: Node2D = null
	if receiver != null and receiver.has_method(&"get_body"):
		body = receiver.call(&"get_body") as Node2D
	if body == null:
		body = _body_above(area)
	if body != null and elevation.bodies.has(body):
		return elevation.level_of(body)
	var ground := area.global_position
	if body != null:
		ground = body.global_position
	elif area.owner is Node2D:
		ground = (area.owner as Node2D).global_position
	return elevation.level_at(ground, fallback)


## The hurtboxes (not the player's, not a "resource") whose shape meets `shape` placed at `centre`,
## on `level` unless it is ANY_LEVEL.
static func _hurtboxes_in(player: Node, shape: Shape2D, centre: Vector2, level: int) -> Array[Area2D]:
	var targets: Array[Area2D] = []
	var router := Services.router()
	var world := Services.world()
	if router == null or world == null or not is_instance_valid(world.world_root):
		return targets
	var space := world.world_root.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, centre)
	query.collision_mask = HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for hit: Dictionary in space.intersect_shape(query, 64):
		var area := hit.get("collider") as Area2D
		if area == null or area in targets:
			continue
		var receiver := router.receiver_for_area(area)
		if receiver == null or receiver == player or "resource" in router.tags_for_area(area):
			continue
		if level != ANY_LEVEL and target_level(area, receiver, level) != level:
			continue
		targets.append(area)
	return targets


## The nearest physics body above `area` in the tree (its owner's body), or null.
static func _body_above(area: Node) -> Node2D:
	var node := area.get_parent()
	while node != null:
		if node is PhysicsBody2D:
			return node as Node2D
		node = node.get_parent()
	return null


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
