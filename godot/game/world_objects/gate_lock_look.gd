extends Node2D
## A visible bar/lock on a building facade, shown only while its GateScript is shut.
## Reads the gate after the whole scene has entered, including its saved unlock record.
@export var gate: Node
@export var door: Node

func _ready() -> void:
	if gate == null or not gate.has_method(&"is_open"):
		return
	gate.connect(&"opened", _sync)
	gate.connect(&"closed", _sync)
	_sync.call_deferred()

func _sync(_payload: Variant = null) -> void:
	var is_open := bool(gate.call(&"is_open"))
	visible = not is_open
	if door != null and door.has_method(&"set_gate_door_open"):
		# The bell opens this storehouse along with unlocking it. On a later visit, restore the
		# open leaf immediately from the saved gate state.
		door.call(&"set_gate_door_open", is_open, _payload is Dictionary)
