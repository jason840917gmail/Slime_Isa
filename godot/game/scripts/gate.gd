extends Node
class_name GateScript
## Scene script `game.gate` (Phaser `features/scripts/GateScript.ts`; interaction spec 3.3, 6.2).
## A gate blocks its passage until it opens: pushed with the key (`push_open`, remembered in RunState
## and shared with the gated world exit of the same id), or through `open()` from a pressure plate or
## a bell (for this visit only, as in Phaser). Open, it shows `open_frame` and its door body stops
## colliding (the pillars stay solid).
##
## **Push to open (owner, 2026-10-15; docs/godot/CONVENTIONS.md "Doors"):** a gate is not offered to
## the interact key. The slime opens it as it goes through a door: its collision rect within
## `worldNavigation.gatePushReachPx` of the gate's doors body while its movement input points at the
## doors (the nearer side of the doors' box, within `doorPushAlignment`) for `doorPushMs` of
## simulation time. With the key (or an unlocked record) the gate opens (`GateUnlock` when the push
## spends the key, `unlocked_message` in green); without it the gate says `locked_message` once per
## push (`GateLocked`). `prompt`, `locked_prompt` and `interact_radius` are kept from the Phaser
## data but no longer shown or used.
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const Door := preload("res://game/scripts/door.gd")

## Plates and bells find gates here by `gate_id`.
const GROUP := &"gate"
const CUE_OPEN := &"GateOpen"
## A heavy plate's gate shutting (no take of its own yet: the locked gate's clunk).
const CUE_CLOSE := &"GateLocked"
const CUE_UNLOCK := &"GateUnlock"
const CUE_LOCKED := &"GateLocked"
## UniversalSceneWorldController.ts: a gate whose record cannot be written.
const STUCK_MESSAGE := "The gate will not budge."

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
## The gate shut again (heavy plates only). Payload: {"gateId": String}.
signal closed(payload: Dictionary)
## A push showed a line. Payload: {"text", "color", "x", "y"} (test hook).
signal message_shown(payload: Dictionary)

var _opened: bool = false
var _ever_opened: bool = false
var _push_ms: float = 0.0
## This push already spoke (a refusal): let go and push again to hear it again.
var _refused: bool = false


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


func _physics_process(delta: float) -> void:
	if _opened:
		_push_ms = 0.0
		return
	var world := Services.world()
	if world == null or world.player_body == null:
		return
	var player: Node = world.get(&"player")
	if not is_pushing(player, world.player_body):
		_push_ms = 0.0
		_refused = false
		return
	_push_ms += delta * 1000.0
	if _push_ms < _number("doorPushMs", 200.0) or _refused:
		return
	_refused = not push_open()


func is_open() -> bool:
	return _opened


## True while the player's body is within `gatePushReachPx` of the doors body and its movement input
## points at it (see the class notes).
func is_pushing(player: Node, player_body: CharacterBody2D) -> bool:
	if player == null or player_body == null or not player.has_method(&"get_move_intent"):
		return false
	var intent: Vector2 = player.call(&"get_move_intent")
	var box := doors_rect()
	if intent == Vector2.ZERO or box.size == Vector2.ZERO:
		return false
	var body := Door._body_rect(player_body)
	if not box.grow(_number("gatePushReachPx", 6.0)).intersects(body):
		return false
	var centre := body.get_center()
	var nearest := Vector2(clampf(centre.x, box.position.x, box.end.x), clampf(centre.y, box.position.y, box.end.y))
	var to_gate := nearest - centre
	if to_gate.length() < 0.5:
		to_gate = box.get_center() - centre
	var toward := Vector2(signf(to_gate.x), 0.0) if absf(to_gate.x) > absf(to_gate.y) else Vector2(0.0, signf(to_gate.y))
	return intent.normalized().dot(toward) >= _number("doorPushAlignment", 0.7)


## The doors body's rectangle shapes in world space (their bounding box); empty without doors.
func doors_rect() -> Rect2:
	var box := Rect2()
	var found := false
	if doors == null or not is_instance_valid(doors):
		return box
	for node: Node in doors.find_children("*", "CollisionShape2D", true, false):
		var shape_node := node as CollisionShape2D
		var rectangle := shape_node.shape as RectangleShape2D
		if rectangle == null:
			continue
		var size := rectangle.size * shape_node.global_scale.abs()
		var rect := Rect2(shape_node.global_position - size * 0.5, size)
		box = rect if not found else box.merge(rect)
		found = true
	return box


## A push that lasted `doorPushMs` (Phaser's interact on a gate): unlocks and opens the gate with
## the key, else says why not. True when the gate opened.
func push_open() -> bool:
	var result := try_unlock()
	var at := origin() - Vector2(0.0, badge_rise)
	if result == "unlocked" or result == "already-unlocked":
		if result == "unlocked":
			_cue(CUE_UNLOCK)
		open()
		_message(at, unlocked_message, &"green")
		return true
	_cue(CUE_LOCKED)
	_message(at, locked_message if result == "missing-item" else STUCK_MESSAGE, &"white")
	return false


## Old Phaser position of the gate (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## Handler `open` (plates, bells, heavy plates): opens for this visit; nothing is saved.
func open(_payload: Variant = null) -> void:
	if _opened:
		return
	_apply(true)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_OPEN)
	opened.emit({"gateId": gate_id})


## Heavy plates (game/scripts/heavy_plate.gd) shut their gate again once they are fully up: the
## doors block again and `closed` is emitted. A gate unlocked with its key (remembered in RunState)
## never shuts. Nothing else calls it, so the old game's gates only ever open.
func close(_payload: Variant = null) -> void:
	if not _opened:
		return
	var run := Services.run()
	if run != null and run.is_gate_unlocked(map_id, gate_id):
		return
	_apply(false)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CLOSE)
	closed.emit({"gateId": gate_id})


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
	# Phaser's setter only ever disables the body (gates only open); `close` (heavy plates) turns
	# it back on. Deferred: an unlock can run inside a physics step. A gate that was never opened
	# is left as its scene made it.
	if doors != null and (open_now or _ever_opened):
		for shape: Node in doors.find_children("*", "CollisionShape2D", true, false):
			(shape as CollisionShape2D).set_deferred(&"disabled", open_now)
		for polygon: Node in doors.find_children("*", "CollisionPolygon2D", true, false):
			(polygon as CollisionPolygon2D).set_deferred(&"disabled", open_now)
	if open_now:
		_ever_opened = true


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


func _message(at: Vector2, text: String, color: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at, text, color, true)
	message_shown.emit({"text": text, "color": String(color), "x": at.x, "y": at.y})


## `worldNavigation.<key>` from game-constants, else `fallback`.
func _number(key: String, fallback: float) -> float:
	var constants := Services.constants()
	return constants.number("worldNavigation." + key) if constants != null else fallback
