extends CharacterBody2D
## Scene script of `object.heavy-block` and `object.heavy-statue` (game/scenes/objects/heavy-block.tscn,
## heavy-statue.tscn; bomb-lantern-and-secrets design section 4; BODY_SHAPES.md "Heavy plates and
## heavy blocks"; numbers in game-constants.json `puzzles.heavyBlock`). A stone pedestal or statue
## too heavy to suck in. The slime grabs it with a held interact (game/player/heavy_grab.gd); only
## the Stone form moves it, one `cellPx` (64) cell per move along one axis, over `moveMs`.
##
## The root is the middle of the cell the block fills (its footprint, the BodyShape, is a little
## under one cell), so blocks line up with the 64-unit wall pieces and with heavy plates placed on the
## same lattice. It stands on the `world` layer, so the slime, enemies and other blocks collide
## with it; it is a heavy weight for heavy plates (`weight_point`).
##
## A move is allowed (`can_move`) when the cell it goes to is walkable ground of the block's own
## level (no cliff, rim, hole or stairs: Elevation.is_walkable at its middle and corners) and no
## body is there (walls, props, gates, other blocks, enemies, NPCs, deep water: a shape query on
## those layers, leaving the slime out). A hole does not take the block: filling holes would need the
## elevation grid to change a cell's level at run time, which it does not do (left out).
##
## It moves only here, through ArcadeMover (its velocity set for the move, the last step landing it
## exactly on the cell). `strain()` and `bump()` shake the art (presentation, real time).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")

const GROUP := &"heavy_blocks"
const CONSTANTS := "puzzles.heavyBlock"
## The layers a move checks and the body collides with: world, enemy, npc, water.
const BLOCKING_LAYERS := 1 | 4 | 128 | 1024
const WATER_LAYER := 1024
## The footprint's corners are checked this far inside its edge.
const CORNER_INSET := 4.0
## Shakes: strain (the plain slime pulling in vain) and bump (a blocked push).
const STRAIN_PX := 1.6
const STRAIN_HZ := 18.0
const BUMP_PX := 2.5
const BUMP_MS := 160.0
## The shadow grounds the base (owner, 2026-10-14: no round blob that floats it). The painted base is
## a rounded slab whose ground edge is about this ellipse (centre and half size from the root, in
## world units): the contact shadow is that ellipse, no wider than the footprint, so the base covers
## it but for a thin dark rim right at its front edge; the cast shadow is the same ellipse moved a
## little to the lower right (the light comes from the upper left), in soft steps.
const CONTACT_CENTRE := Vector2(-0.5, 12.5)
const CONTACT_HALF := Vector2(29.0, 16.0)
const CONTACT_LAYERS: Array[Vector3] = [Vector3(0.0, 0.0, 0.34), Vector3(0.0, 0.8, 0.22)]
## Each step: offset x, offset y, alpha.
const CAST_STEPS: Array[Vector3] = [Vector3(1.5, 1.0, 0.06), Vector3(3.0, 2.0, 0.06), Vector3(4.5, 3.0, 0.05),
	Vector3(6.0, 4.0, 0.045), Vector3(7.5, 5.0, 0.04), Vector3(9.0, 6.0, 0.035)]

## The art (its rest position is kept and shaken around).
@export var visual: Sprite2D
## The footprint (a RectangleShape2D centred on the root).
@export var shape_node: CollisionShape2D
## The name the strain line and the docs use ("pedestal", "statue").
@export var kind: String = "pedestal"

var _cell_px: float = 64.0
var _move_ms: float = 640.0
var _moving: bool = false
var _move_dir: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _move_started_ms: float = 0.0
var _level: int = 0
var _visual_rest: Vector2 = Vector2.ZERO
var _strain_until_real_ms: float = -1.0
var _bump_until_real_ms: float = -1.0


func _ready() -> void:
	add_to_group(GROUP)
	var constants := Services.constants()
	if constants != null:
		_cell_px = float(constants.value(CONSTANTS + ".cellPx", _cell_px))
		_move_ms = maxf(1.0, float(constants.value(CONSTANTS + ".moveMs", _move_ms)))
	if visual != null:
		_visual_rest = visual.position
	var elevation := _elevation()
	if elevation != null:
		_level = elevation.level_at(global_position, 0)
	collision_layer = 1
	collision_mask = BLOCKING_LAYERS & ~(4 | 128) | _level_bit()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	queue_redraw()


## Where a heavy plate feels the block: its middle.
func weight_point() -> Vector2:
	return global_position


## The footprint in world space.
func footprint() -> Rect2:
	var half := _half_size()
	return Rect2(global_position - half, half * 2.0)


func cell_px() -> float:
	return _cell_px


func move_ms() -> float:
	return _move_ms


func is_moving() -> bool:
	return _moving


## The share of the running move still to go (0 when none).
func move_remaining_ms() -> float:
	if not _moving:
		return 0.0
	return maxf(0.0, _move_ms - (Services.now_ms() - _move_started_ms))


## True when the block can move one cell along `direction` (a cardinal unit vector). `ignore` are
## bodies the check leaves out (the slime that pushes or pulls it).
func can_move(direction: Vector2, ignore: Array[RID] = []) -> bool:
	if _moving or direction == Vector2.ZERO:
		return false
	var target := global_position + direction * _cell_px
	var elevation := _elevation()
	if elevation != null:
		var half := _half_size() - Vector2(CORNER_INSET, CORNER_INSET)
		for corner: Vector2 in [Vector2.ZERO, Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
			if not elevation.is_walkable(target + corner, _level):
				return false
	var rect := shape_node.shape as RectangleShape2D if shape_node != null else null
	if rect == null:
		return true
	var probe := RectangleShape2D.new()
	probe.size = rect.size - Vector2(2.0, 2.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, target + shape_node.position)
	query.collision_mask = BLOCKING_LAYERS | _level_bit()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(ignore)
	query.exclude = exclude
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## Starts a one-cell move along `direction` (checked first). False when it cannot go.
func begin_move(direction: Vector2, ignore: Array[RID] = []) -> bool:
	if not can_move(direction, ignore):
		return false
	_moving = true
	_move_dir = direction
	_target = global_position + direction * _cell_px
	_move_started_ms = Services.now_ms()
	return true


## The plain slime pulls in vain: the block trembles for `ms` (real time).
func strain(ms: float = 120.0) -> void:
	_strain_until_real_ms = float(Time.get_ticks_msec()) + ms


## A push into something that blocks it: one short knock.
func bump() -> void:
	_bump_until_real_ms = float(Time.get_ticks_msec()) + BUMP_MS


func _physics_process(delta: float) -> void:
	if not _moving:
		velocity = Vector2.ZERO
		return
	var speed := _cell_px / (_move_ms / 1000.0)
	var to_go := _target - global_position
	var along := to_go.dot(_move_dir)
	if along <= 0.01:
		_land()
		return
	velocity = _move_dir * minf(speed, along / maxf(delta, 0.0001))
	ArcadeMover.move(self, delta)
	if (_target - global_position).dot(_move_dir) <= 0.01 or velocity.is_zero_approx():
		_land()


## The move is over: the block sits exactly on its cell (or stays where something stopped it).
func _land() -> void:
	if (_target - global_position).length() <= 1.0:
		global_position = _target
	_moving = false
	velocity = Vector2.ZERO


func _process(_delta: float) -> void:
	if visual == null:
		return
	var now := float(Time.get_ticks_msec())
	var shake := Vector2.ZERO
	if now < _strain_until_real_ms:
		shake.x = sin(now / 1000.0 * TAU * STRAIN_HZ) * STRAIN_PX
	if now < _bump_until_real_ms:
		var t := (_bump_until_real_ms - now) / BUMP_MS
		shake += Vector2(sin(now / 1000.0 * TAU * 30.0), cos(now / 1000.0 * TAU * 26.0)) * BUMP_PX * t
	visual.position = _visual_rest + shake


func _draw() -> void:
	for step: Vector3 in CAST_STEPS:
		_ellipse(CONTACT_CENTRE + Vector2(step.x, step.y), CONTACT_HALF, step.z)
	for layer: Vector3 in CONTACT_LAYERS:
		_ellipse(CONTACT_CENTRE + Vector2(0.0, layer.y), CONTACT_HALF, layer.z)


func _ellipse(centre: Vector2, half: Vector2, alpha: float) -> void:
	var points := PackedVector2Array()
	for i in 32:
		var angle := TAU * float(i) / 32.0
		points.append(centre + Vector2(cos(angle) * half.x, sin(angle) * half.y))
	draw_colored_polygon(points, Color(0.0, 0.0, 0.0, alpha))


func _half_size() -> Vector2:
	var rect := shape_node.shape as RectangleShape2D if shape_node != null else null
	return rect.size / 2.0 if rect != null else Vector2(30.0, 26.0)


func _level_bit() -> int:
	return Elevation.level_bit(_level) if _elevation() != null else 0


func _elevation() -> Elevation:
	var world := Services.world()
	return world.elevation if world != null else null
