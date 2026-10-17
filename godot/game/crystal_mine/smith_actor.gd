extends Node2D
class_name SmithActor
## The smith, Pip's dad, at his mine camp outside the Crystal Mine (G4; roadmap 12.3;
## docs/godot/DUNGEONS.md "The Crystal Mine (built)"): game/scenes/characters/smith.tscn. Four poses
## (godot/asset/characters/authored/npcs/smith.webp, scripts/art/pack-mine-art.py): standing with his
## hammer, the hammer raised, holding out the Lantern, pointing; each with its feet centred in a
## CELL-sized cell and standing on its bottom. `face` mirrors him.
##
## Idle he works at his anvil (`works_anvil`): the hammer rises and falls with a clink heard near
## him, and he breathes (real time: presentation only). The camp holds a pose while he talks
## (`hold_pose`, `release_pose`). Talking is the interaction's `usable` contract (prompt "Talk"):
## `use()` emits `talked` and the camp (game/crystal_mine/mine_camp.gd) speaks for him. His body
## blocks the slime.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")

const USABLE_GROUP := &"usable"
const FRAME_STAND := 0
const FRAME_STRIKE := 1
const FRAME_LANTERN := 2
const FRAME_POINT := 3
const CELL := Vector2(260, 280)
const BREATH_PERIOD_S := 2.0
const BREATH := 0.018
## The anvil's rhythm: a strike every STRIKE_EVERY_S, the hammer up for STRIKE_UP_S before it.
const STRIKE_EVERY_S := 1.7
const STRIKE_UP_S := 0.5
const CUE_CLINK := &"HitDull"
## The clink is heard only this near him (a global cue, so it is not played across the map).
const CLINK_RADIUS := 420.0

## Payload {}: the slime talked to him (the interact key).
signal talked(payload: Dictionary)

@export var visual: Sprite2D
@export var body: StaticBody2D
@export var interact_radius: float = 110.0
@export var badge_rise: float = 104.0
@export var prompt: String = "Talk"
## Works at the anvil while nobody talks to him.
@export var works_anvil: bool = true
## Which way he faces at the start (his anvil's side): +1 right, -1 left.
@export var start_facing: float = 1.0

var _clock := 0.0
var _held := -1
var _busy := false
var _facing := 1.0
var _base_scale := 1.0


func _enter_tree() -> void:
	add_to_group(USABLE_GROUP)


func _ready() -> void:
	if visual != null:
		_base_scale = visual.scale.x
	face(start_facing)
	_show(FRAME_STAND)


func origin() -> Vector2:
	return global_position


func can_use() -> bool:
	return visible and not _busy


func use() -> bool:
	if not can_use():
		return false
	talked.emit({})
	return true


## While busy (talking) he offers no prompt.
func set_busy(on: bool) -> void:
	_busy = on


## Faces right (+1) or left (-1).
func face(direction_x: float) -> void:
	_facing = 1.0 if direction_x >= 0.0 else -1.0
	if visual == null:
		return
	visual.flip_h = _facing < 0.0
	visual.offset = Vector2(-CELL.x * 0.5, -CELL.y)


## Holds `frame` (FRAME_LANTERN, FRAME_POINT...) until `release_pose`.
func hold_pose(frame: int) -> void:
	_held = frame
	_show(frame)


func release_pose() -> void:
	_held = -1
	_show(FRAME_STAND)


func _process(delta: float) -> void:
	_clock += delta
	if visual == null:
		return
	var breath := sin(_clock * TAU / BREATH_PERIOD_S) * BREATH
	visual.scale = Vector2(_base_scale * (1.0 + breath * 0.6), _base_scale * (1.0 - breath))
	if _held >= 0 or _busy or not works_anvil:
		return
	var phase := fmod(_clock, STRIKE_EVERY_S)
	var up := phase >= STRIKE_EVERY_S - STRIKE_UP_S
	var frame := FRAME_STRIKE if up else FRAME_STAND
	if visual.frame == FRAME_STRIKE and frame == FRAME_STAND:
		_clink()
	_show(frame)


func _clink() -> void:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	if (player.call(&"get_centre") as Vector2).distance_to(global_position) > CLINK_RADIUS:
		return
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CLINK)


func _show(frame: int) -> void:
	if visual != null and visual.frame != frame:
		visual.frame = frame
