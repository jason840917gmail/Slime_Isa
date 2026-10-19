@tool
extends Node2D
class_name Shutter
## A dungeon shutter (docs/godot/DUNGEONS.md "Shutters and room fights"; `object.shutter`): a heavy
## stone block that rises out of a doorway's floor to shut it and sinks back to open it. Placed like
## a door (DungeonDoor): in the doorway, on the floor line of the room it closes, `wall` the wall of
## that room. A room fight (room_fight.gd) shuts every shutter with its `fight_id` when the slime
## steps in and opens them when the fight is won; `shut()` / `open()` work from anything else too.
##
## `starts_shut`: a shut door that something opens for good (a winch, a bell, a crank: `trigger()`
## or `open_for_good()`, recorded under `shutter_id`), such as the Crystal Mine's iron shutter.
##
## Its `look` (the block's Sprite2D, centered off, its bottom at the floor line) shows the part of
## the block above the floor; its `body` blocks while it is up. In a room whose walls are an
## InteriorWallLayer (docs/godot/INTERIOR_WALLS.md) set `frame_drawn_by_wall`: the block is fitted
## to the wall's gap (`interior.gapUnits`), the wall draws the frame.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const GROUP := &"shutter"
const WALL_TURNS := {"north": 0.0, "east": PI * 0.5, "south": PI, "west": -PI * 0.5}
## In an east or west wall the block is drawn this share of its height (DungeonDoor.SIDE_DEPTH).
const SIDE_DEPTH := 0.55
## In a north wall drawn by an InteriorWallLayer the block is at most this tall (units).
const NORTH_BLOCK_HEIGHT := 52.0
const CUE_SHUT := &"GateLocked"
const CUE_OPEN := &"GateOpen"
const DUST := &"dodge-dust"
const SHAKE_MS := 140.0
const SHAKE_INTENSITY := 0.003

## Shut or opened. Payload: {"shutterId", "shut": bool}.
signal moved(payload: Dictionary)

@export_enum("north", "east", "south", "west") var wall: String = "north":
	set(value):
		wall = value
		rotation = float(WALL_TURNS.get(wall, 0.0))
		if is_node_ready():
			_apply_side_depth()
## The room fight it belongs to (room_fight.gd `fight_id`).
@export var fight_id: String = ""
## Its id in the record (a `starts_shut` shutter opened for good).
@export var shutter_id: String = ""
## Shut when the world is built, until opened for good.
@export var starts_shut: bool = false:
	set(value):
		starts_shut = value
		if Engine.is_editor_hint() and is_node_ready():
			_place_look(1.0 if starts_shut else 0.0)
## The room's InteriorWallLayer draws the doorway frame: the block is fitted to its gap.
@export var frame_drawn_by_wall: bool = false:
	set(value):
		frame_drawn_by_wall = value
		if is_node_ready():
			_apply_side_depth()
## The wall style whose gap the block fills (its kit's band sizes).
@export var interior_style: String = "lair-stone"
## The block's picture.
@export var look: Sprite2D
## Blocks the doorway while up.
@export var body: StaticBody2D

var _shut := false
var _height := 0.0
var _target := 0.0
var _rest := Vector2.ZERO


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


var _look_scale := Vector2.ZERO


func _ready() -> void:
	rotation = float(WALL_TURNS.get(wall, 0.0))
	_apply_side_depth()
	if look != null:
		_rest = look.offset
		look.region_enabled = true
	if Engine.is_editor_hint():
		_place_look(1.0 if starts_shut else 0.0)
		set_physics_process(false)
		return
	_shut = starts_shut
	_height = 1.0 if _shut else 0.0
	_target = _height
	_place_look(_height)
	_set_blocking(_shut)
	if starts_shut:
		_restore_in_tree.call_deferred()


func _apply_side_depth() -> void:
	if look == null:
		return
	if _look_scale == Vector2.ZERO:
		_look_scale = look.scale
	if frame_drawn_by_wall and look.texture != null and look.texture.get_width() > 0:
		_fit_to_wall_gap()
		return
	look.scale = Vector2(_look_scale.x, _look_scale.y * (SIDE_DEPTH if wall == "east" or wall == "west" else 1.0))


## The block is the style's leaf for its side (InteriorWalls.leaf_at, `leaf_kind`), cut from the
## same render as the wall, so it fills the opening exactly in that side's perspective; it shows
## and hides by fading (`_place_look`).
func _fit_to_wall_gap() -> void:
	var place := InteriorWalls.leaf_at(interior_style, wall, leaf_kind())
	if place.is_empty():
		return
	look.texture = InteriorWalls.picture(str(place["texture"]))
	look.hframes = 1
	look.vframes = 1
	look.frame = 0
	look.region_enabled = true
	look.region_rect = place["region"]
	look.centered = false
	look.offset = Vector2.ZERO
	_rest = Vector2.ZERO
	look.scale = Vector2.ONE / InteriorWalls.DENSITY
	look.rotation = -rotation
	look.position = (place["offset"] as Vector2).rotated(-rotation)


## The wall-drawn leaf of this block: "shutter" (the seal: "seal").
func leaf_kind() -> String:
	return "shutter"


## The interior walls' gap (`interior.gapUnits`).
static func _gap_units() -> float:
	var constants := Services.constants()
	var found: Variant = constants.value("interior.gapUnits", null) if constants != null else null
	return float(found) if found != null else 64.0


## True while shut (or shutting).
func is_shut() -> bool:
	return _shut


## Rises to shut the doorway (takes any signal's payload: a boss camp's `boss_engaged`).
func shut(_payload: Variant = null) -> void:
	if _shut:
		return
	_shut = true
	_target = 1.0
	_set_blocking(true)
	_feel(CUE_SHUT)
	moved.emit({"shutterId": shutter_id, "shut": true})


## Sinks to open the doorway.
func open(_payload: Variant = null) -> void:
	if not _shut:
		return
	_shut = false
	_target = 0.0
	_set_blocking(false)
	_feel(CUE_OPEN)
	moved.emit({"shutterId": shutter_id, "shut": false})


## Opens for good (recorded): a winch's, a bell's or a crank's door.
func open_for_good(payload: Variant = null) -> void:
	DungeonState.mark_done(get_tree(), _record_key())
	open(payload)


## The kit's generic hookup: opens for good.
func trigger(payload: Variant = null) -> void:
	open_for_good(payload)


## `_restore`, deferred from `_ready`, only while still in the tree: a world run on its own (F6)
## is the current scene for a moment before it swaps itself for main.tscn, and this piece of that
## copy has left the tree by then.
func _restore_in_tree() -> void:
	if is_inside_tree():
		_restore()


func _restore() -> void:
	if DungeonState.is_done(get_tree(), _record_key()):
		_shut = false
		_height = 0.0
		_target = 0.0
		_place_look(0.0)
		_set_blocking(false)


func _record_key() -> String:
	return DungeonState.object_key(self, "shutter:" + (shutter_id if not shutter_id.is_empty() else String(name)))


func _physics_process(delta: float) -> void:
	if is_equal_approx(_height, _target):
		return
	var step := delta * 1000.0 / maxf(1.0, DungeonState.number("shutter.moveMs", 260.0))
	_height = move_toward(_height, _target, step)
	_place_look(_height)


## Shows the top `share` of the block above the floor line (wall-drawn: fades it in by `share`).
func _place_look(share: float) -> void:
	if look == null or look.texture == null:
		return
	if frame_drawn_by_wall:
		look.visible = share > 0.01
		look.modulate.a = clampf(share, 0.0, 1.0)
		return
	var size := look.texture.get_size()
	var shown := size.y * clampf(share, 0.0, 1.0)
	look.region_enabled = true
	look.region_rect = Rect2(0.0, 0.0, size.x, maxf(0.5, shown))
	look.offset = Vector2(_rest.x, -shown)
	look.visible = share > 0.01


func _set_blocking(blocking: bool) -> void:
	if body == null:
		return
	for shape: Node in body.find_children("*", "CollisionShape2D", true, false):
		(shape as CollisionShape2D).set_deferred(&"disabled", not blocking)


func _feel(cue: StringName) -> void:
	var feel := Services.feel()
	if feel == null:
		return
	feel.audio_cue(cue)
	feel.particles(DUST, global_position + Vector2(0.0, -4.0))
	feel.shake(SHAKE_MS, SHAKE_INTENSITY)
