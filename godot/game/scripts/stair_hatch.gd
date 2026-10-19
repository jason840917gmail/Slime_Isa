extends Node2D
class_name StairHatchScript
## Scene script `game.stair-hatch` (`object.stair-hatch`, `object.stair-ladder`; Fatty's Lair,
## docs/godot/DUNGEONS.md "Fatty's Lair (built)"): a stair between two floors laid side by side in one
## world, the Inner Stair from the Pit Hall down to the Guard Crypt and its ladder back up. Walking
## onto its open well (the slime's centre inside `trigger_rect`, moving) fades the picture out,
## puts the slime at the `target` marker facing `arrival_facing`, and fades back in: no key, as a
## door (docs/godot/CONVENTIONS.md "Doors").
##
## - **The hatch** starts shut (frame 0) unless `start_open` or its story flag `open_flag` is set:
##   shut it is walkable floor, and standing on it says `refusal_text` once per visit to it. `open`
##   swings it up (frame 1) with the chain sound and sets the flag (Burr's winch:
##   game/fattys_lair/lair_director.gd).
## - **The ladder** (`object.stair-ladder`) is the same script with `start_open` on.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")

const GROUP := &"stair_hatch"
const FRAME_SHUT := 0
const FRAME_OPEN := 1
const CUE_OPEN := &"GateOpen"
const CUE_CHAIN := &"DoorUse"
const CUE_STEP := &"StairsStep"
const FADE_LAYER := 30
const FADE_MS := 220.0
const HOLD_MS := 120.0
const REFUSAL_RISE := 80.0

## The slime went down (or up) it. Payload: {"hatchId"}.
signal used(payload: Dictionary)
## The hatch swung open. Payload: {"hatchId"}.
signal opened(payload: Dictionary)

@export var hatch_id: String = ""
## Story flag that keeps it open ("" = none).
@export var open_flag: String = ""
@export var start_open: bool = false
## Where the slime arrives (a Node2D in the same world).
@export var target: NodePath
## Where the slime arrives when the stair leads into another world (Fatty's Lair is one world per
## room since 2026-10-18: the Inner Stair goes from the hub's world down to the crypt's): that
## world's id and the name of the Node2D there it arrives at (main.gd `travel_to`, with the fade).
## Set, they win over `target`.
@export var target_world: String = ""
@export var target_marker: String = ""
@export_enum("down", "up", "left", "right") var arrival_facing: String = "down"
## The well the slime walks into (relative to the node).
@export var trigger_rect: Rect2 = Rect2(-30, -40, 60, 40)
@export var refusal_text: String = "An old hatch. Its winch is behind the cell door."
@export var visual: Sprite2D

var _open := false
var _travelling := false
var _spoke := false


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	var run := Services.run()
	_open = start_open or (not open_flag.is_empty() and run != null and run.has_flag(open_flag))
	_show()


func is_open() -> bool:
	return _open


## Swings it open for good (its flag).
func open(animated: bool = true) -> void:
	if _open:
		return
	_open = true
	var run := Services.run()
	if run != null and not open_flag.is_empty():
		run.set_flag(open_flag)
	_show()
	if animated:
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_CHAIN)
			feel.audio_cue(CUE_OPEN)
			feel.shake(220.0, 0.004)
			feel.particles(&"dodge-dust", global_position)
	opened.emit({"hatchId": hatch_id})


func _show() -> void:
	if visual != null:
		visual.frame = FRAME_OPEN if _open else FRAME_SHUT


func _physics_process(_delta: float) -> void:
	if _travelling or Engine.is_editor_hint():
		return
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	var player: Node = world.player
	var centre: Vector2 = player.call(&"get_centre")
	var inside := Rect2(global_position + trigger_rect.position, trigger_rect.size).has_point(centre)
	if not inside:
		_spoke = false
		return
	if not _open:
		if not _spoke:
			_spoke = true
			var feel := Services.feel()
			if feel != null:
				feel.floating_text(global_position - Vector2(0.0, REFUSAL_RISE), refusal_text, &"white", false, 2200.0)
		return
	var intent: Vector2 = player.call(&"get_move_intent") if player.has_method(&"get_move_intent") else Vector2.ZERO
	if intent == Vector2.ZERO:
		return
	_travel(player)


## The fade, the move to `target`, the fade back; or the travel to `target_world`.
func _travel(player: Node) -> void:
	if not target_world.is_empty():
		var main := get_tree().get_first_node_in_group(&"world_main")
		if main != null and main.has_method(&"travel_to"):
			_travelling = true
			var feel := Services.feel()
			if feel != null:
				feel.audio_cue(CUE_STEP)
			if bool(main.call(&"travel_to", target_world, "", "", target_marker)):
				used.emit({"hatchId": hatch_id})
			else:
				_travelling = false
		return
	var marker := get_node_or_null(target) as Node2D
	if marker == null:
		return
	_travelling = true
	player.call(&"stop_movement")
	player.call(&"suppress_movement", FADE_MS * 2.0 + HOLD_MS)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_STEP)
	var main := get_tree().current_scene
	var parent: Node = main if main != null else get_tree().root
	var holder: Array[CanvasLayer] = []
	holder.append(AreaTravel.fade(parent, FADE_LAYER, 0.0, 1.0, FADE_MS, func() -> void: _arrive(player, marker, holder), false))


## Behind the black: the slime moves to `marker`, then the same black layer fades away.
func _arrive(player: Node, marker: Node2D, holder: Array[CanvasLayer]) -> void:
	if is_instance_valid(player):
		player.call(&"teleport", marker.global_position)
		player.call(&"face", AreaTravel.facing_vector(arrival_facing))
	used.emit({"hatchId": hatch_id})
	await get_tree().create_timer(HOLD_MS / 1000.0, true, false, true).timeout
	var layer: CanvasLayer = holder[0] if not holder.is_empty() else null
	if layer == null or not is_instance_valid(layer):
		_travelling = false
		return
	var rect := layer.get_node_or_null(^"Fade") as ColorRect
	var tween := layer.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if rect != null:
		tween.tween_property(rect, "color:a", 0.0, FADE_MS / 1000.0)
	tween.tween_callback(func() -> void: _travelling = false)
	tween.tween_callback(layer.queue_free)
