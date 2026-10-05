extends RefCounted
## Where abilities may put the slime (Phaser `PlayerAbilityService.ts:166-200`,
## `PlayerAbilityController.ts:60-77`, `WorldScene.lashLanding :1647-1666`; abilities spec 5.2,
## 7.2, 8.4). Points are old Phaser centres.
##
## - The jump tests tiles only (water, deep water, rock walls; outside the world counts as
##   blocked): it crosses walls, gates and houses, which are placed objects (a Phaser quirk kept).
## - The teleport also refuses a landing whose body rect (30 x 26 at centre + (0, 14.56)) would
##   overlap a static body on the world layer (walls, trees, houses, rocks, posts, closed gates).
## - The lash pull stops 30 px short of what it caught, on an open tile.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

## Jump samples (PlayerAbilityService.ts:176-190).
const TRACE_STEP_PX := 8.0
const ENSURE_MIN_MOVE_PX := 8.0
const ENSURE_NUDGE_PX := 12.0
## Teleport (:166-174, :194).
const TELEPORT_STEP_PX := 8.0
const MIN_TELEPORT_PX := 32.0
## The player's body rect relative to its old centre (player_slime.tscn BodyShape).
const BODY_SIZE := Vector2(30.0, 26.0)
const BODY_OFFSET := Vector2(0.0, 14.56)
## Static bodies on the world layer block a landing.
const WORLD_LAYER_MASK := 1
## Lash (WorldScene.ts:132).
const LASH_STANDOFF_PX := 30.0
const LASH_STEP_PX := 8.0


## Tile under `point` is solid or outside the world (`isTileCollidable`).
static func is_blocked(point: Vector2) -> bool:
	var world := Services.world()
	if world == null or world.dimensions().is_empty():
		return true
	var tile_size := float(world.dimensions()["tile_size"])
	return world.is_solid_tile(floori(point.x / tile_size), floori(point.y / tile_size))


## The slime's body rect centred for `point` overlaps a static world body (not tiles, not the
## world bounds, not the player): `physics.overlapRect(includeStatic)`.
static func is_occupied(point: Vector2, exclude: Array[RID]) -> bool:
	var world := Services.world()
	if world == null or not is_instance_valid(world.world_root):
		return false
	var space := world.world_root.get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = BODY_SIZE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point + BODY_OFFSET)
	query.collision_mask = WORLD_LAYER_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = exclude
	for hit: Dictionary in space.intersect_shape(query, 32):
		var collider := hit.get("collider") as Node
		if collider == null or _ignored(collider):
			continue
		return true
	return false


## The jump's landing (`trace`): the last open sample along `direction` up to `distance`, every
## 8 px; with `ensure_movement` a landing under 8 px from the start becomes start + dir * 12, even
## into a blocked tile (a Phaser quirk kept).
static func trace(start: Vector2, direction: Vector2, distance: float, ensure_movement: bool) -> Vector2:
	var steps := ceili(distance / TRACE_STEP_PX)
	var last_valid := start
	for step in range(1, steps + 1):
		var point := start + direction * (float(step) / steps * distance)
		if is_blocked(point):
			break
		last_valid = point
	if ensure_movement and last_valid.distance_to(start) < ENSURE_MIN_MOVE_PX:
		return start + direction * ENSURE_NUDGE_PX
	return last_valid


## The teleport's landing (`safeLanding`): from `reach` down to 32 px in 8 px steps, the first
## point that is neither a blocked tile nor occupied. null when none.
static func safe_landing(start: Vector2, direction: Vector2, reach: float, exclude: Array[RID]) -> Variant:
	var distance := reach
	while distance >= MIN_TELEPORT_PX:
		var point := start + direction * distance
		if not is_blocked(point) and not is_occupied(point, exclude):
			return point
		distance -= TELEPORT_STEP_PX
	return null


## Where a heavy lash catch pulls the slime (`lashLanding`): 30 px short of `caught`, backing off
## 8 px at a time to the first open tile inside the world; `from` when none (or caught within 30).
static func lash_landing(from: Vector2, caught: Vector2) -> Vector2:
	var length := from.distance_to(caught)
	if length <= LASH_STANDOFF_PX:
		return from
	var direction := (caught - from) / length
	var distance := length - LASH_STANDOFF_PX
	while distance > 0.0:
		var point := from + direction * distance
		if not is_blocked(point):
			return point
		distance -= LASH_STEP_PX
	return from


## Tile collision and the runtime world bounds are not Phaser bodies.
static func _ignored(collider: Node) -> bool:
	var name := String(collider.name)
	return name == "WorldBounds" or name == "TileCollision" or collider is TileMapLayer \
		or (collider.get_parent() != null and String(collider.get_parent().name) == "TileCollision")
