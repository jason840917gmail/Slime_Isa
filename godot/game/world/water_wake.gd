extends Node2D
## Water at the feet of everyone standing in it (owner, 2026-10-06; docs/godot/specs/water.md
## "Wading"): in shallow water a splash ring rises and falls around the body's feet, quick while it
## walks and slow while it stands; in deep water (once something can swim there) calm rings swell
## around it. Like the classic top-down adventure games, any walker shows it: the player, the
## enemies and the NPCs.
##
## `WaterWake.mount(ground)` adds this node as the child "WaterWake" of the ground layer
## (WorldService.register_world, after the water surface, the terrain edges and the elevation). It
## tracks every walker body of the world (a CharacterBody2D on the player, enemy or NPC layer, the
## ones placed in the scene and every one spawned later) and gives each two sprites cut from the
## wake sheet: the ring's back half as the body's first child (drawn behind its art) and its front
## half as its last child (drawn in front), so the body stands inside the ring. Each physics tick
## reads the ground cell under the body's feet: shallow water shows row 0 of the sheet, deep water
## row 1, anything else nothing, and so does a body in the air (a script child's `is_airborne()`,
## the player's jump). Presentation only: walking speed, collision and footsteps do not change.
##
## The art (scripts/art/build-water-wake-sheet.py): 4 frames per row in cells of CELL art pixels
## with the ring's centre at ANCHOR, 2 art px per world unit, the ring sized for the player
## slime's 30-unit body; other bodies scale it by their width.
##
## Owner: world (water).

const Self := preload("res://game/world/water_wake.gd")
const SHEET := preload("res://asset/MAPS/water/224x128-tile_4x2-water-wake.webp")
const NODE_NAME := "WaterWake"
const BACK_NODE := "WaterWakeBack"
const FRONT_NODE := "WaterWakeFront"
const TILE_ID_DATA_LAYER := "tile_id"
const SHALLOW_TILE_ID := "water"
const DEEP_TILE_ID := "deep-water"
## Bodies that walk: the player, enemy and NPC physics layers (as Elevation.WALKER_LAYERS).
const WALKER_LAYERS := 2 | 4 | 128
const CELL := Vector2(224, 128)
const ANCHOR := Vector2(112, 84)
const FRAMES := 4
const WADE_ROW := 0
const SWIM_ROW := 1
const NO_ROW := -1
## World units per art pixel.
const ART_SCALE := 0.5
## The body width the ring is drawn for (the player slime's body) and the range other bodies scale
## it within.
const REFERENCE_WIDTH := 30.0
const MIN_SIZE := 0.6
const MAX_SIZE := 3.0
## Animation speeds (frames per second): wading, standing in shallow water, swimming.
const WADE_FPS := 10.0
const STAND_FPS := 4.0
const SWIM_FPS := 6.0
## Slower than this a body counts as standing (units per second).
const MOVING_SPEED := 8.0
## The cell is read this far above the feet, inside the body: a body stopped by deep water stands
## with its feet on the deep cell's edge.
const FEET_PROBE := 2.0

## The ground layer (the parent).
var ground: TileMapLayer
## body -> {"back": Sprite2D, "front": Sprite2D, "airborne": Callable, "phase": float}
var _bodies: Dictionary = {}
## Ground source id -> its row (WADE_ROW, SWIM_ROW or NO_ROW).
var _row_by_source: Dictionary = {}


## Mounts the wake on `layer` (a second call tracks the bodies again). Null when the layer has no
## tile set with `tile_id` data.
static func mount(layer: TileMapLayer) -> Self:
	if layer == null or layer.tile_set == null or not layer.tile_set.has_custom_data_layer_by_name(TILE_ID_DATA_LAYER):
		return null
	var wake := layer.get_node_or_null(NodePath(NODE_NAME)) as Self
	if wake == null:
		wake = Self.new()
		wake.name = NODE_NAME
		wake.ground = layer
		layer.add_child(wake)
	wake.ground = layer
	wake._row_by_source.clear()
	wake._track_existing()
	return wake


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Gives `body` its wake sprites and follows it (a body already followed, or not a walker, is
## left alone).
func track(body: CharacterBody2D) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree() or _bodies.has(body) or (body.collision_layer & WALKER_LAYERS) == 0:
		return
	var size := clampf(_width_of(body) / REFERENCE_WIDTH, MIN_SIZE, MAX_SIZE)
	var back := _sprite(body, BACK_NODE, size)
	back.offset = -ANCHOR
	body.move_child(back, 0)
	var front := _sprite(body, FRONT_NODE, size)
	front.offset = Vector2(-ANCHOR.x, 0.0)
	body.move_child(front, body.get_child_count() - 1)
	_bodies[body] = {"back": back, "front": front, "airborne": _airborne_check(body), "phase": 0.0}
	if not body.tree_exiting.is_connected(_forget):
		body.tree_exiting.connect(_forget.bind(body))


## The wake row shown at `body` now (NO_ROW: none).
func row_of(body: CharacterBody2D) -> int:
	var state: Dictionary = _bodies.get(body, {})
	if state.is_empty() or not (state["front"] as Sprite2D).visible:
		return NO_ROW
	return int((state["front"] as Sprite2D).region_rect.position.y / CELL.y)


func _physics_process(delta: float) -> void:
	if ground == null:
		return
	for body: Variant in _bodies.keys():
		if not is_instance_valid(body):
			_bodies.erase(body)
			continue
		var walker := body as CharacterBody2D
		var state: Dictionary = _bodies[walker]
		var row := _row_at(walker.global_position - Vector2(0.0, FEET_PROBE))
		var airborne: Callable = state["airborne"]
		if row != NO_ROW and airborne.is_valid() and bool(airborne.call()):
			row = NO_ROW
		var back: Sprite2D = state["back"]
		var front: Sprite2D = state["front"]
		back.visible = row != NO_ROW
		front.visible = row != NO_ROW
		if row == NO_ROW:
			state["phase"] = 0.0
			continue
		var fps := SWIM_FPS
		if row == WADE_ROW:
			fps = WADE_FPS if walker.velocity.length() > MOVING_SPEED else STAND_FPS
		state["phase"] = float(state["phase"]) + delta * fps
		var column := int(state["phase"]) % FRAMES
		back.region_rect = Rect2(column * CELL.x, row * CELL.y, CELL.x, ANCHOR.y)
		front.region_rect = Rect2(column * CELL.x, row * CELL.y + ANCHOR.y, CELL.x, CELL.y - ANCHOR.y)


func _row_at(point: Vector2) -> int:
	var cell := ground.local_to_map(ground.to_local(point))
	var source_id := ground.get_cell_source_id(cell)
	if source_id == -1:
		return NO_ROW
	if not _row_by_source.has(source_id):
		var data := ground.get_cell_tile_data(cell)
		var tile_id := str(data.get_custom_data(TILE_ID_DATA_LAYER)) if data != null else ""
		_row_by_source[source_id] = WADE_ROW if tile_id == SHALLOW_TILE_ID else (SWIM_ROW if tile_id == DEEP_TILE_ID else NO_ROW)
	return int(_row_by_source[source_id])


## Bodies already in the world (placed in the scene, or spawned before the mount).
func _track_existing() -> void:
	var world_root := ground.get_parent()
	if world_root == null:
		return
	for node: Node in world_root.find_children("*", "CharacterBody2D", true, false):
		track(node as CharacterBody2D)


func _on_node_added(node: Node) -> void:
	var body := node as CharacterBody2D
	if body == null or (body.collision_layer & WALKER_LAYERS) == 0 or ground == null:
		return
	var world_root := ground.get_parent()
	if world_root != null and world_root.is_ancestor_of(body):
		# Its own children (the art, the script) exist once its scene is ready.
		track.call_deferred(body)


func _forget(body: Node) -> void:
	_bodies.erase(body)


## The wake sprite named `node_name` on `body` (reused when the body already has it: a body that
## left the tree and came back).
func _sprite(body: CharacterBody2D, node_name: String, size: float) -> Sprite2D:
	var sprite := body.get_node_or_null(NodePath(node_name)) as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = node_name
		body.add_child(sprite)
	sprite.texture = SHEET
	sprite.region_enabled = true
	sprite.centered = false
	sprite.scale = Vector2.ONE * ART_SCALE * size
	sprite.visible = false
	return sprite


## The body's width: its first collision shape's (the player slime's is 30).
func _width_of(body: CharacterBody2D) -> float:
	for child: Node in body.get_children():
		var holder := child as CollisionShape2D
		if holder == null or holder.shape == null:
			continue
		var scale_x := absf(holder.scale.x * body.scale.x)
		if holder.shape is RectangleShape2D:
			return (holder.shape as RectangleShape2D).size.x * scale_x
		if holder.shape is CircleShape2D:
			return (holder.shape as CircleShape2D).radius * 2.0 * scale_x
		if holder.shape is CapsuleShape2D:
			return (holder.shape as CapsuleShape2D).radius * 2.0 * scale_x
	return REFERENCE_WIDTH


## The body's "in the air" check: a child script's `is_airborne()` (the player's jump), if any.
func _airborne_check(body: CharacterBody2D) -> Callable:
	for child: Node in body.get_children():
		if child.has_method(&"is_airborne"):
			return Callable(child, &"is_airborne")
	return Callable()
