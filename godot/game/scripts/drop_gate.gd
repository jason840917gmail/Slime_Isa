extends Node2D
class_name DropGateScript
## Scene script `game.drop-gate` (`object.drop-gate`, game/scenes/objects/drop-gate.tscn; Fatty's
## Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"; roadmap 5.15): the old Thorn Guard gate of
## the worms' burrow, the Roll's lock. Its look (the level-design guide's look book): a solid
## iron-banded oak leaf in a rock mound, no bars to see through and no lever behind it; the worms'
## lever (game/world_objects/worm_lever.gd, the `Lever` child) stands beside it in the open.
##
## - **The race:** the lever (the interact key) lifts the leaf over `rise_ms`; it stays up `open_ms`,
##   then drops shut in `drop_ms`. Walking from the lever never makes it through; a quick Roll does
##   (tuned in the playground as the slabs are, question 71: the numbers are this scene's exports).
##   While it is up its `doors` body stops blocking. A slime caught under the leaf as it drops is
##   shoved out on the side it came from, bonked, never shut inside the leaf.
## - **Held up for good** (`hold_open_for_good`): the gatehouse's winch (game/scripts/gate_winch.gd)
##   holds it up; its record (`map_id`, `gate_id`) is unlocked in RunState, read when the scene is
##   built, so the race is played once (the design's open point 9).
## - **Pushed while shut:** the slime pushing into the leaf hears `refusal_text` (once per push).
##
## The node stands at the middle of the doorway's foot; the slime comes from the south (+y) and goes
## north through it (or back).
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const Door := preload("res://game/scripts/door.gd")

## Every drop gate joins this group (winches find their gate by `gate_id`).
const GROUP := &"drop_gate"
const CUE_RISE := &"GateOpen"
const CUE_DROP := &"RollBonk"
const CUE_HELD := &"GateUnlock"
const CUE_REFUSED := &"GateLocked"
const DUST := &"dodge-dust"
const DROP_SHAKE_MS := 180.0
const DROP_SHAKE := 0.006
const REFUSAL_RISE := 150.0
const SHOVE_PX := 34.0

enum State { SHUT, RISING, UP, DROPPING, HELD }

## Emitted when the lever lifts the leaf. Payload: {"gateId"}.
signal raised(payload: Dictionary)
## Emitted when the leaf is down again. Payload: {"gateId"}.
signal dropped(payload: Dictionary)
## Emitted when a winch holds it up for good. Payload: {"gateId"}.
signal held(payload: Dictionary)

## The map whose record keeps it held up ("" = the world's map id).
@export var map_id: String = ""
## Its id in the map record (unlocked gate ids) and the winch's target.
@export var gate_id: String = "drop-gate"
## How long the leaf takes to rise (ms, gameplay time).
@export var rise_ms: float = 220.0
## How long it stays up before it drops (ms, gameplay time).
@export var open_ms: float = 700.0
## How long the drop takes (ms, gameplay time); the leaf blocks again from its start.
@export var drop_ms: float = 140.0
## The line when the slime pushes the shut leaf.
@export var refusal_text: String = "Shut tight. The worms' lever lifts it."
## The leaf's body (blocks while shut).
@export var doors: StaticBody2D
## The leaf's picture (cut from the top as it rises into the arch).
@export var leaf: Sprite2D

var _state: State = State.SHUT
var _since_ms: float = 0.0
var _leaf_region := Rect2()
var _leaf_offset := Vector2.ZERO
var _push_ms: float = 0.0
var _refused: bool = false


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if leaf != null and leaf.texture != null:
		_leaf_region = Rect2(Vector2.ZERO, leaf.texture.get_size())
		_leaf_offset = leaf.offset
		leaf.region_enabled = true
		leaf.region_rect = _leaf_region
	_hold_if_recorded.call_deferred()


## True while the slime can pass: the leaf up (rising, up, held), not dropping or shut.
func is_open() -> bool:
	return _state == State.RISING or _state == State.UP or _state == State.HELD


## True once a winch holds it up for good.
func is_held() -> bool:
	return _state == State.HELD


## The state's name ("shut", "rising", "up", "dropping", "held"), for tests.
func state_name() -> String:
	return ["shut", "rising", "up", "dropping", "held"][_state]


## The worm lever: lifts the leaf; it drops again `open_ms` later. Nothing when it is not shut.
func raise() -> bool:
	if _state != State.SHUT:
		return false
	_enter(State.RISING)
	_set_blocking(false)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_RISE)
	raised.emit({"gateId": gate_id})
	return true


## The winch: the leaf goes up and stays up for good (recorded).
func hold_open_for_good() -> void:
	if _state == State.HELD:
		return
	var run := Services.run()
	var record_id := record_map_id()
	if run != null and not record_id.is_empty():
		run.mark_gate_unlocked(record_id, gate_id)
	_enter(State.HELD)
	_set_blocking(false)
	_show_lift(1.0)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_HELD)
	held.emit({"gateId": gate_id})


## Holds it up at once, quietly (the record says so).
func hold_now() -> void:
	_enter(State.HELD)
	_set_blocking(false)
	_show_lift(1.0)


## The map whose record keeps it: `map_id`, else the world's.
func record_map_id() -> String:
	if not map_id.is_empty():
		return map_id
	var world := Services.world()
	return world.map_id() if world != null else ""


func _hold_if_recorded() -> void:
	var run := Services.run()
	if _state != State.HELD and run != null and run.is_gate_unlocked(record_map_id(), gate_id):
		hold_now()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var now := Services.now_ms()
	var elapsed := now - _since_ms
	match _state:
		State.RISING:
			_show_lift(clampf(elapsed / maxf(1.0, rise_ms), 0.0, 1.0))
			if elapsed >= rise_ms:
				_enter(State.UP)
		State.UP:
			if elapsed >= open_ms:
				_begin_drop()
		State.DROPPING:
			_show_lift(1.0 - clampf(elapsed / maxf(1.0, drop_ms), 0.0, 1.0))
			if elapsed >= drop_ms:
				_enter(State.SHUT)
				_show_lift(0.0)
				_land()
		State.SHUT:
			_watch_push(delta)


func _enter(state: State) -> void:
	_state = state
	_since_ms = Services.now_ms()


func _begin_drop() -> void:
	_enter(State.DROPPING)
	_set_blocking(true)
	_shove_player_out()


## The leaf hits the ground: the thud, a little dust and shake.
func _land() -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_DROP)
		feel.shake(DROP_SHAKE_MS, DROP_SHAKE)
		feel.particles(DUST, global_position + Vector2(-36.0, -4.0))
		feel.particles(DUST, global_position + Vector2(36.0, -4.0))
	dropped.emit({"gateId": gate_id})


## A slime standing under the leaf as it drops is put out on the side its centre is on.
func _shove_player_out() -> void:
	var world := Services.world()
	if world == null or world.player_body == null or world.player == null:
		return
	var box := doors_rect()
	if box.size == Vector2.ZERO:
		return
	var body := Door._body_rect(world.player_body)
	if not box.intersects(body):
		return
	var centre: Vector2 = world.player.call(&"get_centre")
	var side := 1.0 if centre.y >= box.get_center().y else -1.0
	var target_y := (box.end.y + body.size.y * 0.5 + SHOVE_PX) if side > 0.0 else (box.position.y - body.size.y * 0.5 - SHOVE_PX)
	world.player.call(&"teleport", Vector2(centre.x, target_y))
	if world.player.has_method(&"stop_movement"):
		world.player.call(&"stop_movement")


## The leaf's picture `lift` (0 shut, 1 fully up) into the arch: its top cut away.
func _show_lift(lift: float) -> void:
	if leaf == null:
		return
	var eased := lift * lift * (3.0 - 2.0 * lift)
	var cut := _leaf_region.size.y * eased
	leaf.visible = cut < _leaf_region.size.y - 1.0
	leaf.region_rect = Rect2(Vector2(0.0, cut), Vector2(_leaf_region.size.x, maxf(1.0, _leaf_region.size.y - cut)))
	leaf.offset = _leaf_offset


func _set_blocking(blocking: bool) -> void:
	if doors == null:
		return
	for child: Node in doors.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred(&"disabled", not blocking)


## The doors body's rectangle in world space.
func doors_rect() -> Rect2:
	var box := Rect2()
	var found := false
	if doors == null:
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


## The refusal: the slime pushing into the shut leaf for `doorPushMs` hears the line once.
func _watch_push(delta: float) -> void:
	var world := Services.world()
	if world == null or world.player_body == null or world.player == null:
		return
	var player: Node = world.player
	if not player.has_method(&"get_move_intent"):
		return
	var intent: Vector2 = player.call(&"get_move_intent")
	var box := doors_rect().grow(8.0)
	var body := Door._body_rect(world.player_body)
	if intent == Vector2.ZERO or not box.intersects(body):
		_push_ms = 0.0
		_refused = false
		return
	var toward := signf(box.get_center().y - body.get_center().y)
	if intent.normalized().dot(Vector2(0.0, toward)) < 0.7:
		_push_ms = 0.0
		_refused = false
		return
	_push_ms += delta * 1000.0
	var constants := Services.constants()
	var needed := constants.number("worldNavigation.doorPushMs") if constants != null else 200.0
	if _refused or _push_ms < needed:
		return
	_refused = true
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REFUSED)
		feel.floating_text(global_position - Vector2(0.0, REFUSAL_RISE), refusal_text, &"white", false, 2200.0)
