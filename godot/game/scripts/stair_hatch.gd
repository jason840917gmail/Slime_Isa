extends Node2D
class_name StairHatchScript
## The stair's logic (Fatty's Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"), the base of
## the stair door (game/scripts/stair_door.gd, `object.stair-door`: the Inner Stair from the Pit Hall
## down to the Guard Crypt, the crypt's stair back up, the playground's pair). Its own scenes, the
## floor hatch and the ladder, were replaced by the stair door on 2026-10-24. Walking into its open
## well (the slime's centre inside `trigger_rect`, moving) fades the picture out, puts the slime at
## the stair it leads to, and fades back in; with `target_world` it travels to that world (main.gd
## `travel_to`, with the fade): no key, as a door (docs/godot/CONVENTIONS.md "Doors").
##
## Stairs pair like doors (2026-10-31, docs/design/2026-10-31-crossings-and-arrivals.md):
## `target_door` names the stair the slime comes out of (its `hatch_id`, in this world or in
## `target_world`), which plays its arrival (`play_arrival`: the subclass's steps) from its
## `arrival_point` (an "arrival" child, else the node plus `arrival_offset`), the slime facing out of
## it (`inward`: down, a stair door stands in a north wall). It is an end of a crossing like a door
## (the `door` group, `door_id` = `hatch_id`; area_travel.gd finds it). Without `target_door` it
## leads nowhere (tools/check_crossings.gd lists it); the old markers went on 2026-10-31.
##
## It starts shut unless `start_open` or its story flag `open_flag` is set: shut, walking into it says
## `refusal_text` once per visit to it. `open` opens it for good with the chain sound and sets the
## flag (Burr's winch: game/fattys_lair/lair_director.gd). Its picture (`_show`) is the subclass's.
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
## The stair the slime comes out of: its `hatch_id`, in this world, or in `target_world` when set.
@export var target_door: String = ""
## Where the slime stands arriving by this stair, from the node (an "arrival" child wins).
@export var arrival_offset: Vector2 = Vector2(0.0, 80.0)
## The world the stair leads into ("" = this one): Fatty's Lair is one world per room since
## 2026-10-18, so the Inner Stair goes from the hub's world down to the crypt's (main.gd `travel_to`,
## with the fade).
@export var target_world: String = ""
## The well the slime walks into (relative to the node).
@export var trigger_rect: Rect2 = Rect2(-30, -40, 60, 40)
@export var refusal_text: String = "An old stair door, shut. Its winch is behind the cell door."
@export var visual: Sprite2D

var _open := false
var _travelling := false
var _spoke := false

## Its id as an end of a crossing (area_travel.gd finds ends by `door_id` in the `door` group).
var door_id: String:
	get:
		return hatch_id


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(AreaTravel.DOOR_GROUP)


## Where the slime stands arriving by this stair: the "arrival" child, else the node plus
## `arrival_offset`; rounded.
func arrival_point() -> Vector2:
	var arrival := get_node_or_null(^"arrival") as Node2D
	var point := arrival.global_position if arrival != null else global_position + arrival_offset
	return Vector2(floorf(point.x + 0.5), floorf(point.y + 0.5))


## The slime stands exactly at `arrival_point` (its steps play from there), not on a tile centre.
func exact_arrival() -> bool:
	return true


## No side to push into: the slime walks into the well.
func has_side() -> bool:
	return false


## Out of the stair, into the room: the facing on arriving (a stair door stands in a north wall).
func inward() -> Vector2:
	return Vector2.DOWN


## The slime came out of this stair (main.gd `_start_arrival`, or `_arrive` here): a shut stair
## stands open while it is here, since it came through it (the flag stays as it is).
func on_arrival() -> void:
	if not _open:
		_open = true
		_show()


## The arrival's own animation (see door.gd `play_arrival`); the subclass's steps. None here.
func play_arrival(_player: Node, _delay_ms: float) -> float:
	return 0.0


## The stair this one leads to in this world (`target_door`), or null.
func _paired_here() -> StairHatchScript:
	if target_door.is_empty() or not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node != self and node is StairHatchScript and (node as StairHatchScript).hatch_id == target_door:
			return node
	return null


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
	# A rolling ball goes in as a walk does (player.gd `get_travel_intent`).
	var intent: Vector2 = player.call(&"get_travel_intent") if player.has_method(&"get_travel_intent") else Vector2.ZERO
	if intent == Vector2.ZERO:
		return
	_travel(player)


## The fade, the move to the stair it leads to (`target_door`), the fade back; or the travel to
## `target_world`, arriving at its stair `target_door`.
func _travel(player: Node) -> void:
	if target_door.is_empty():
		return
	if not target_world.is_empty():
		var main := get_tree().get_first_node_in_group(&"world_main")
		if main != null and main.has_method(&"travel_to"):
			_travelling = true
			# The step sounds only when the travel starts (refused, another travel under way, it is
			# asked again next frame: no cue every frame).
			if bool(main.call(&"travel_to", target_world, "", target_door)):
				_travel_cue()
				used.emit({"hatchId": hatch_id})
			else:
				_travelling = false
		return
	var marker: Node2D = _paired_here()
	if marker == null:
		return
	_travelling = true
	player.call(&"stop_movement")
	player.call(&"suppress_movement", FADE_MS * 2.0 + HOLD_MS)
	_travel_cue()
	var main := get_tree().current_scene
	var parent: Node = main if main != null else get_tree().root
	var holder: Array[CanvasLayer] = []
	holder.append(AreaTravel.fade(parent, FADE_LAYER, 0.0, 1.0, FADE_MS, func() -> void: _arrive(player, marker, holder), false))


## The step sound the travel starts with. A subclass that plays its own steps overrides it.
func _travel_cue() -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_STEP)


## Behind the black: the slime moves to `marker` (the paired stair: its arrival point, and its
## arrival plays while the black lifts), then the same black layer fades away.
func _arrive(player: Node, marker: Node2D, holder: Array[CanvasLayer]) -> void:
	var stair := marker as StairHatchScript
	if is_instance_valid(player) and stair != null:
		player.call(&"arrive_at", stair.arrival_point())
		player.call(&"face", stair.inward())
		stair.on_arrival()
		player.call(&"suppress_movement", stair.play_arrival(player, HOLD_MS))
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
