@tool
extends Node2D
class_name DungeonDoor
## A dungeon door in a wall (docs/godot/DUNGEONS.md "Doors"): the base of the small-key door, the
## boss door (key_door.gd) and the bolted door (bolted_door.gd). The node stands in the doorway, at
## the middle of the gap, on the floor line of the room its face looks into; `wall` is the wall of
## that room it stands in (north: the face looks south, the classic front view; east, south and west
## turn the whole door as Zelda's dungeons draw their side and bottom doors). Shut, its `body`
## blocks the gap; the slime uses it by walking into it (PushProbe, `worldNavigation.doorPushMs`):
## `_on_push(from_face)` decides. Opened for good, the closed look rises and fades over
## `dungeon.door.openMs`, the body stops blocking, and its record (DungeonState.mark_done, under
## `door_id`) keeps it open: a faint, a quit, a load or the world built again finds it open.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PushProbe := preload("res://game/dungeon/push_probe.gd")

const WALL_TURNS := {"north": 0.0, "east": PI * 0.5, "south": PI, "west": -PI * 0.5}
## In an east or west wall the turned front art is drawn this share of its height (a door seen
## edge-on, foreshortened, so it does not stand out of the wall into the next room).
const SIDE_DEPTH := 0.55
const CUE_REFUSED := &"GateLocked"
const CUE_OPEN := &"GateOpen"
const DUST := &"dodge-dust"
const TEXT_RISE := 120.0
## How far the closed look rises as it opens (world px, presentation).
const OPEN_RISE_PX := 26.0

## The door was opened (not by `open_now`). Payload: {"doorId"}.
signal opened(payload: Dictionary)
## A push was refused (its line). Payload: {"doorId", "text"}.
signal refused(payload: Dictionary)

## The wall of the room its face looks into (the whole door turns with it).
@export_enum("north", "east", "south", "west") var wall: String = "north":
	set(value):
		wall = value
		rotation = float(WALL_TURNS.get(wall, 0.0))
		if is_node_ready():
			_apply_side_depth()
## Its id in the record (unique in its world; the node's name when empty).
@export var door_id: String = ""
## The body that blocks the gap while shut.
@export var body: StaticBody2D
## The shut door's picture (rises and fades as it opens).
@export var closed_look: CanvasItem
## The open doorway's picture (under the shut one).
@export var open_look: CanvasItem

var _open := false
var _opening := false
var _open_started_ms := 0.0
var _closed_rest := Vector2.ZERO
var _push_ms := 0.0
var _spoke := false
var _next_line_ms := 0


var _base_scales: Dictionary = {}


func _ready() -> void:
	rotation = float(WALL_TURNS.get(wall, 0.0))
	_apply_side_depth()
	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(false)
		return
	if closed_look is Node2D:
		_closed_rest = (closed_look as Node2D).position
	set_process(false)
	_restore_in_tree.call_deferred()


## Foreshortens the looks in a side wall (SIDE_DEPTH), back to their own scale in a north or
## south wall.
func _apply_side_depth() -> void:
	for look: CanvasItem in [closed_look, open_look]:
		var node := look as Node2D
		if node == null:
			continue
		if not _base_scales.has(node):
			_base_scales[node] = node.scale
		var base: Vector2 = _base_scales[node]
		node.scale = Vector2(base.x, base.y * (SIDE_DEPTH if wall == "east" or wall == "west" else 1.0))


## The record key ("<map id>:<door id>").
func record_key() -> String:
	return DungeonState.object_key(self, door_id if not door_id.is_empty() else String(name))


func is_open() -> bool:
	return _open


## True when the slime stands on the side its face looks at.
func on_face_side(point: Vector2) -> bool:
	return to_local(point).y > 0.0


## Opens it for good: the record, the sound and dust, the closed look rising away.
func open_for_good() -> void:
	if _open:
		return
	DungeonState.mark_done(get_tree(), record_key())
	_set_open()
	_opening = true
	_open_started_ms = float(Time.get_ticks_msec())
	set_process(true)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_OPEN)
		feel.particles(DUST, global_position + Vector2(-36.0, -6.0))
		feel.particles(DUST, global_position + Vector2(36.0, -6.0))
	opened.emit({"doorId": door_id})


## Opens it at once, quietly (already opened before).
func open_now() -> void:
	_set_open()
	_opening = false
	if closed_look != null:
		closed_look.visible = false


## The line over the door (at most once every `dungeon.door.lineEveryMs`) and the locked sound.
func say(text: String) -> void:
	refused.emit({"doorId": door_id, "text": text})
	var now := Time.get_ticks_msec()
	if now < _next_line_ms:
		return
	_next_line_ms = now + int(DungeonState.number("door.lineEveryMs", 1500.0))
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REFUSED)
		feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), text, &"white", false, 2200.0)


## Override: a push that lasted `doorPushMs` from the face side (true) or the back.
func _on_push(_from_face: bool) -> void:
	pass


## Override: true when a push it refused would now succeed (it then runs again without letting go).
func _wants_retry() -> bool:
	return false


## `_restore`, deferred from `_ready`, only while still in the tree: a world run on its own (F6)
## is the current scene for a moment before it swaps itself for main.tscn, and this piece of that
## copy has left the tree by then.
func _restore_in_tree() -> void:
	if is_inside_tree():
		_restore()


## Override: the record says what to show when the world is built.
func _restore() -> void:
	if DungeonState.is_done(get_tree(), record_key()):
		open_now()


## Lets the push go on for `ms` more before `_on_push` runs again (a second keyhole).
func push_again_after(ms: float) -> void:
	_push_ms = -ms
	_spoke = false


func _physics_process(delta: float) -> void:
	if _open:
		return
	var direction := PushProbe.push_direction(PushProbe.shapes_box(body))
	if direction == Vector2.ZERO:
		_push_ms = 0.0
		_spoke = false
		return
	_push_ms += delta * 1000.0
	# A refused push tries again once what it lacked is there (a key picked up while pushing).
	if _spoke and _wants_retry():
		_spoke = false
	if _push_ms < PushProbe.push_ms() or _spoke:
		return
	_spoke = true
	var world := Services.world()
	var from_face := world != null and world.player != null and on_face_side(world.player.get_centre())
	_on_push(from_face)


func _set_open() -> void:
	_open = true
	if body == null:
		return
	for shape: Node in body.find_children("*", "CollisionShape2D", true, false):
		(shape as CollisionShape2D).set_deferred(&"disabled", true)


func _process(_delta: float) -> void:
	if not _opening or closed_look == null:
		set_process(false)
		return
	var t := clampf((float(Time.get_ticks_msec()) - _open_started_ms) / maxf(1.0, DungeonState.number("door.openMs", 650.0)), 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	if closed_look is Node2D:
		(closed_look as Node2D).position = _closed_rest + Vector2(0.0, -OPEN_RISE_PX * eased)
	closed_look.modulate.a = 1.0 - eased
	if t >= 1.0:
		_opening = false
		closed_look.visible = false
		set_process(false)
