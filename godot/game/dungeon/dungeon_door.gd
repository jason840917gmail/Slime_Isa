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
## In a room whose walls are an InteriorWallLayer (docs/godot/INTERIOR_WALLS.md) the wall draws the
## doorway's frame: set `frame_drawn_by_wall` and the door draws only its leaf (`leaf_kind`, from
## the wall style's sheet), filling the opening in its side's perspective.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PushProbe := preload("res://game/dungeon/push_probe.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

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
## The group of the doors of one link (`link_id`).
const LINK_GROUP := "dungeon_door_link:"

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
## The room's InteriorWallLayer draws the doorway frame: the door draws only its leaf, cut to the
## gap (`interior_style` names the kit sheet). False: the kit's own door picture with its arch.
@export var frame_drawn_by_wall: bool = false:
	set(value):
		frame_drawn_by_wall = value
		if is_node_ready():
			_apply_side_depth()
## Paired doors (docs/godot/DUNGEONS.md "Doors and room logic"): the two leaves of one passage
## between two rooms, one in each room's wall. Doors with the same `link_id` share one record and
## open together: when one opens, the others open with it, and a world built later finds them all
## open. A door's link is its `link_id`, else its `door_id`; give the partner the other's `door_id`.
@export var link_id: String = ""
## The wall style whose leaves the door draws when the wall draws its frame.
@export var interior_style: String = "lair-stone":
	set(value):
		interior_style = value
		if is_node_ready() and frame_drawn_by_wall:
			_apply_wall_frame()

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


## The leaf drawn when the wall draws the frame: "key1" (key doors), "key2", "boss", "bolt".
func leaf_kind() -> String:
	return "key1"


## Draws only the leaf inside the wall's opening (`frame_drawn_by_wall`): the open picture goes, the
## shut one becomes the style's leaf for its side (InteriorWalls.leaf_at), cut from the same render
## as the wall, so it fills the opening exactly in that side's perspective. What hangs on the old
## door (padlocks, bolt) is part of the leaf's picture: their sprites hide.
func _apply_wall_frame() -> void:
	if open_look != null:
		open_look.visible = false
	var leaf := closed_look as Sprite2D
	if leaf == null and closed_look != null:
		leaf = closed_look.get_node_or_null(^"Door") as Sprite2D
	var place := InteriorWalls.leaf_at(interior_style, wall, leaf_kind())
	if leaf == null or place.is_empty():
		return
	leaf.texture = InteriorWalls.picture(str(place["texture"]))
	leaf.hframes = 1
	leaf.vframes = 1
	leaf.frame = 0
	leaf.region_enabled = true
	leaf.region_rect = place["region"]
	leaf.centered = false
	leaf.offset = Vector2.ZERO
	leaf.position = Vector2.ZERO
	leaf.scale = Vector2.ONE / InteriorWalls.DENSITY
	var shut := closed_look as Node2D
	if shut == null:
		return
	# upright on screen: the door node is turned with its wall, its leaf is not
	shut.rotation = -rotation
	shut.scale = Vector2.ONE
	shut.position = (place["offset"] as Vector2).rotated(-rotation)
	_closed_rest = shut.position
	for fitting: Node in shut.get_children():
		if fitting != leaf and fitting is CanvasItem:
			for item: Node in [fitting] + fitting.get_children():
				if item is Sprite2D:
					(item as Sprite2D).self_modulate.a = 0.0


## Foreshortens the looks in a side wall (SIDE_DEPTH), back to their own scale in a north or
## south wall; with the frame drawn by the wall, the leaf is fitted instead.
func _apply_side_depth() -> void:
	if frame_drawn_by_wall:
		_apply_wall_frame()
		return
	for look: CanvasItem in [closed_look, open_look]:
		var node := look as Node2D
		if node == null:
			continue
		if not _base_scales.has(node):
			_base_scales[node] = node.scale
		var base: Vector2 = _base_scales[node]
		node.scale = Vector2(base.x, base.y * (SIDE_DEPTH if wall == "east" or wall == "west" else 1.0))


## The record key ("<map id>:<door id>", or the link's when it is linked).
func record_key() -> String:
	return DungeonState.object_key(self, _link())


func _link() -> String:
	if not link_id.is_empty():
		return link_id
	return door_id if not door_id.is_empty() else String(name)


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(StringName(LINK_GROUP + _link()))


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
	# its partners (the passage's other leaf) open with it
	if is_inside_tree():
		for partner: Node in get_tree().get_nodes_in_group(StringName(LINK_GROUP + _link())):
			if partner != self and partner.has_method(&"open_for_good"):
				partner.call(&"open_for_good")


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
