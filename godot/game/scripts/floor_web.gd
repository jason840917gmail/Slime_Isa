@tool
extends Node2D
class_name FloorWebScript
## Scene script of `object.floor-web` (docs/godot/WEBS.md): one floor web as a node, for a web that
## must move or vanish with what it lies on (a falling slab in the Weaver Hollow's B6: make it a
## child of the slab). It is a painted web cell (WebLayer) of its own: without the Silk skin a walk
## through it is slowed by half and a Roll that enters it sticks; with the skin it is crossed at
## full speed (FloorWebs, game/world/webs/floor_webs.gd). Hidden (`visible` off, or under a hidden
## parent), it holds nothing. Paint the mass of floor webs on a `webs` WebLayer instead.
##
## The web holds the slime's feet inside `size` (world units) centred on the root, and its
## picture (one of the WebLayer's six, `variant`, turned by `turn`) is drawn `size` x 1.5 under
## every body, as a painted cell.
##
## Owner: webs (the Weaver Hollow).

const FloorWebs := preload("res://game/world/webs/floor_webs.gd")
const WebLayerScript := preload("res://game/world/webs/web_layer.gd")

## The art drawn over the zone's size times this (a painted cell's web overlaps its neighbours).
const LOOK_SCALE := 1.5
const ZONE_PREVIEW := Color(0.93, 0.47, 0.78, 0.5)

## A Roll stuck in this web. Payload: {"x", "y"} (the root).
signal roll_stuck(payload: Dictionary)

## The web's zone: the slime's feet inside it are in the web (centred on the root, world units).
@export var size: Vector2 = Vector2(64.0, 64.0):
	set(value):
		size = value
		queue_redraw()
## Which of the six webs (floor-webs-6x1.webp).
@export_range(0, 5) var variant: int = 0:
	set(value):
		variant = value
		queue_redraw()
## Quarter turns of the picture (0 to 3).
@export_range(0, 3) var turn: int = 0:
	set(value):
		turn = value
		queue_redraw()

static var _texture: Texture2D


func _init() -> void:
	z_index = WebLayerScript.Z_INDEX


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(FloorWebs.GROUP)


func _ready() -> void:
	set_physics_process(not Engine.is_editor_hint())
	queue_redraw()


## True when `point` (a world position) is inside the web and the web is shown.
func holds(point: Vector2) -> bool:
	if not point.is_finite() or not is_visible_in_tree():
		return false
	var local := to_local(point)
	return absf(local.x) <= size.x / 2.0 and absf(local.y) <= size.y / 2.0


## FloorWebs: the walk's scale for `player` (its feet in the web and it does not cross webs).
func web_walk_multiplier(player: Node, crosses: bool) -> float:
	if crosses or not holds(FloorWebs.feet(player)):
		return 1.0
	return FloorWebs.setting("floorSlowMultiplier")


func _physics_process(_delta: float) -> void:
	var player := FloorWebs.player()
	if player == null or not bool(player.call(&"is_rolling")):
		return
	if holds(FloorWebs.feet(player)) and FloorWebs.stick_roll(player):
		roll_stuck.emit({"x": global_position.x, "y": global_position.y})


func _draw() -> void:
	if _texture == null and ResourceLoader.exists(WebLayerScript.ART):
		_texture = load(WebLayerScript.ART) as Texture2D
	if _texture != null:
		var drawn := size * LOOK_SCALE
		draw_set_transform(Vector2.ZERO, turn * PI / 2.0)
		var source := Rect2(variant * WebLayerScript.FRAME_PX, 0.0, WebLayerScript.FRAME_PX, WebLayerScript.FRAME_PX)
		draw_texture_rect_region(_texture, Rect2(-drawn / 2.0, drawn), source)
		draw_set_transform(Vector2.ZERO)
	if Engine.is_editor_hint():
		draw_rect(Rect2(-size / 2.0, size), ZONE_PREVIEW, false, 2.0)
