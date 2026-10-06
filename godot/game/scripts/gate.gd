extends Node
class_name GateScript
## Scene script `game.gate` (Phaser `features/scripts/GateScript.ts`; interaction spec 3.3, 6.2).
## A gate blocks its passage until it opens: through the interaction controller with the key
## (`try_unlock`, remembered in RunState and shared with the gated world exit of the same id), or
## through `open()` from a pressure plate or a bell (for this visit only, as in Phaser). Open, it
## shows `open_frame` and its door body stops colliding (the pillars stay solid).
## `locked_prompt` is read but never shown, as in Phaser.
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

## Plates and bells find gates here by `gate_id`.
const GROUP := &"gate"
const CUE_OPEN := &"GateOpen"

## JSON `mapId`.
@export var map_id: String = ""
## JSON `gateId` (shared with a gated world exit's `gate.id`).
@export var gate_id: String = ""
## JSON `requiredItemId` (e.g. "green-key").
@export var required_item_id: String = ""
## JSON `consumeOnUnlock`.
@export var consume_on_unlock: bool = true
## JSON `prompt`.
@export var prompt: String = "Unlock gate"
## JSON `lockedPrompt` (never shown).
@export var locked_prompt: String = "Locked"
## JSON `lockedMessage`: shown when the key is missing.
@export var locked_message: String = "The gate is locked."
## JSON `unlockedMessage`.
@export var unlocked_message: String = "The gate unlocks!"
## JSON `interactRadius`.
@export var interact_radius: float = 150.0
## JSON `badgeRise`.
@export var badge_rise: float = 120.0
## JSON `closedFrame`.
@export var closed_frame: int = 0
## JSON `openFrame`.
@export var open_frame: int = 1
## JSON `visual`: the gate Sprite2D.
@export var visual: Sprite2D
## JSON `doors`: the StaticBody2D that blocks the passage while closed.
@export var doors: StaticBody2D

## The gate opened. Payload: {"gateId": String}.
signal opened(payload: Dictionary)

var _opened: bool = false


func _enter_tree() -> void:
	add_to_group(GROUP)
	var run := Services.run()
	_apply(run != null and run.is_gate_unlocked(map_id, gate_id))


func _ready() -> void:
	if not is_finite(interact_radius):
		interact_radius = 150.0
	if not is_finite(badge_rise):
		badge_rise = 120.0
	_apply(_opened)


func is_open() -> bool:
	return _opened


## Old Phaser position of the gate (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## Handler `open` (plates, bells): opens for this visit; nothing is saved.
func open(_payload: Variant = null) -> void:
	if _opened:
		return
	_apply(true)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_OPEN)
	opened.emit({"gateId": gate_id})


## `InventoryWorldTransaction.unlockGate`: "unlocked" | "already-unlocked" | "missing-item" |
## "failed". Unlocking takes the key when `consume_on_unlock` and remembers the gate.
func try_unlock() -> String:
	var run := Services.run()
	if run == null:
		return "failed"
	if run.is_gate_unlocked(map_id, gate_id):
		return "already-unlocked"
	if run.item_count(required_item_id) < 1:
		return "missing-item"
	return "unlocked" if run.unlock_gate(map_id, gate_id, required_item_id, consume_on_unlock) else "failed"


func _apply(open_now: bool) -> void:
	_opened = open_now
	if visual != null:
		visual.frame = open_frame if open_now else closed_frame
	# Phaser's setter only ever disables the body (gates only open). Deferred: an unlock can run
	# inside a physics step.
	if doors != null and open_now:
		for shape: Node in doors.find_children("*", "CollisionShape2D", true, false):
			(shape as CollisionShape2D).set_deferred(&"disabled", true)
		for polygon: Node in doors.find_children("*", "CollisionPolygon2D", true, false):
			(polygon as CollisionPolygon2D).set_deferred(&"disabled", true)
