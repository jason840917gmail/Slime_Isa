extends Node
class_name PressurePlateScript
## Scene script `game.pressure-plate` (Phaser `features/scripts/PressurePlateScript.ts`;
## abilities spec 13.2). Only a Heavy slime (its centre within `radius` of the plate) holds it
## down: the plate sinks `sink_px` and shows `pressed_frame`, opens every gate with `gate_id`
## (for this visit only) and emits `pressed`; when the weight goes it rises and emits `released`.
## A latching plate stays down while it lives. Nothing is saved (a Phaser quirk kept).
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const GATE_GROUP := &"gate"

## JSON `plateId`.
@export var plate_id: String = ""
## JSON `radius`: press reach from the plate root.
@export var radius: float = 40.0
## JSON `sinkPx`: how far the art sinks while down.
@export var sink_px: float = 4.0
## JSON `pressedFrame` (-1 = keep the frame).
@export var pressed_frame: int = -1
## JSON `gateId`: the gates it opens ("" = none).
@export var gate_id: String = ""
## JSON `latch`: once down, it stays down.
@export var latch: bool = false
## JSON `visual`: the plate Sprite2D (optional).
@export var visual: Sprite2D

## The plate went down. Payload: {"plateId"}.
signal pressed(payload: Dictionary)
## The plate came back up. Payload: {"plateId"}.
signal released(payload: Dictionary)

var _down: bool = false
var _rest_offset: Variant = null
var _rest_frame: int = 0


func _ready() -> void:
	if not (is_finite(radius) and radius >= 0.0):
		radius = 40.0
	if not (is_finite(sink_px) and sink_px >= 0.0):
		sink_px = 4.0


func is_down() -> bool:
	return _down


func _physics_process(_delta: float) -> void:
	if _down and latch:
		return
	var loaded := _loaded()
	if loaded == _down:
		return
	_down = loaded
	_show_sunk(loaded)
	if loaded:
		_open_gates()
		pressed.emit({"plateId": plate_id})
	else:
		released.emit({"plateId": plate_id})


## A plate-pressing (Heavy) slime's centre is within `radius` of the plate root, not in the air.
func _loaded() -> bool:
	var world := Services.world()
	var player = world.player if world != null else null
	if player == null or not is_instance_valid(player) or not bool(player.call(&"presses_plates")):
		return false
	if player.has_method(&"is_airborne") and bool(player.call(&"is_airborne")):
		return false
	var root := get_parent() as Node2D
	return root != null and (player.call(&"get_centre") as Vector2).distance_to(root.global_position) <= radius


func _show_sunk(down: bool) -> void:
	if visual == null:
		return
	if _rest_offset == null:
		_rest_offset = visual.offset
		_rest_frame = visual.frame
	var rest: Vector2 = _rest_offset
	visual.offset = Vector2(rest.x, rest.y + (sink_px if down else 0.0))
	if pressed_frame >= 0:
		visual.frame = pressed_frame if down else _rest_frame


func _open_gates() -> void:
	if gate_id.is_empty():
		return
	for gate: Node in get_tree().get_nodes_in_group(GATE_GROUP):
		if str(gate.get(&"gate_id")) == gate_id:
			gate.call(&"open")
