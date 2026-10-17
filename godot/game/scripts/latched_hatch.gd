extends Node2D
class_name LatchedHatch
## A hatch in a floor, latched from below (the Weaver Hollow's hub, docs/godot/DUNGEONS.md "The
## Weaver Hollow"): the shortcut back from a lower floor. Its `door` (a door.gd of kind
## `ladder_down`, a child of this node) leads down; until the slime has climbed up through it once
## (the door's `arrived`, from the ladder below), the hatch stays shut: the door's trigger is off and
## a slime standing on it hears the latch and reads `locked_text`. Opened, it stays open for good
## (the story flag `flag_id`) and shows `open_look` instead of `closed_look`.
##
## Owner: world (dungeons).

const Services := preload("res://game/shared/services.gd")

const CUE_LOCKED := &"GateLocked"
const TEXT_RISE := 70.0
const TEXT_MS := 2000.0

## Story flag: the hatch was opened from below (for good).
@export var flag_id: String = ""
## The door down (door.gd).
@export var door: Node
@export var closed_look: Node2D
@export var open_look: Node2D
## Said when the slime stands on the shut hatch.
@export var locked_text: String = "Latched from below."
## How near the slime's feet must come to the hatch's middle to hear the latch (world units).
@export var latch_radius: float = 44.0

var _open := false
var _trigger := Rect2()
var _was_on := false


func _ready() -> void:
	var run := Services.run()
	_open = not flag_id.is_empty() and run != null and run.has_flag(flag_id)
	if door != null:
		_trigger = door.get(&"trigger_rect")
		if door.has_signal(&"arrived"):
			door.connect(&"arrived", _on_arrived)
	_apply()


func is_open() -> bool:
	return _open


## Opens the hatch for good (the slime came up through it).
func open_for_good() -> void:
	if _open:
		return
	_open = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	_apply()


func _on_arrived() -> void:
	open_for_good()


func _apply() -> void:
	if closed_look != null:
		closed_look.visible = not _open
	if open_look != null:
		open_look.visible = _open
	if door != null:
		door.set(&"trigger_rect", _trigger if _open else Rect2())


func _physics_process(_delta: float) -> void:
	if _open:
		return
	var world := Services.world()
	var body: Node2D = world.player_body if world != null else null
	if body == null:
		return
	var on := body.global_position.distance_to(global_position) <= latch_radius
	if on and not _was_on:
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_LOCKED)
			feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), locked_text, &"white", false, TEXT_MS)
	_was_on = on
