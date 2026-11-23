@tool
extends Node2D
## A tripwire (Gloop Forest's River Roads, 2026-11-21; docs/godot/WEBS.md "Tripwires"): a silk
## thread drawn across a narrow road, `length` units along this node's x axis (turn the node for a
## thread across a north-south road). When the slime's feet touch it, it snaps (the web tear cue)
## and every Silk Lurker within `reach` of its middle drops at once (silk_lurker.gd `trip`). A trap
## to step round, or to spring on purpose and fight the spiders one at a time. It is spun again
## when its chunk is built again.
##
## Owner: world (webs).

const Services := preload("res://game/shared/services.gd")
const ENEMY_GROUP := &"enemy"
const CUE := &"WebTear"
const THREAD_COLOR := Color(0.95, 0.95, 1.0, 0.85)
const ANCHOR_COLOR := Color(0.75, 0.7, 0.9, 1.0)

## The thread's length (units, along the node's x axis, centred on it).
@export var length: float = 128.0:
	set(value):
		length = value
		queue_redraw()
## How near the thread the slime's feet snap it (units).
@export var touch_px: float = 12.0
## Silk Lurkers whose shadow lies this near its middle drop when it snaps (units).
@export var reach: float = 260.0

var _snapped := false


func _ready() -> void:
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _snapped:
		return
	var world := Services.world()
	var player: Node = world.player if world != null else null
	var body := player.get(&"body") as Node2D if player != null and is_instance_valid(player) else null
	if body == null:
		return
	var feet := to_local(body.global_position)
	var along := clampf(feet.x, -length * 0.5, length * 0.5)
	if Vector2(along, 0.0).distance_to(feet) > touch_px:
		return
	_snapped = true
	queue_redraw()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE)
	for enemy: Node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not enemy.has_method(&"trip") or not enemy.has_method(&"feet"):
			continue
		var at: Vector2 = enemy.call(&"feet")
		if at.distance_to(global_position) <= reach:
			enemy.call(&"trip")


func _draw() -> void:
	var half := length * 0.5
	if _snapped:
		# Two loose ends hanging from the anchors.
		draw_line(Vector2(-half, 0.0), Vector2(-half + 10.0, 8.0), THREAD_COLOR, 1.4)
		draw_line(Vector2(half, 0.0), Vector2(half - 10.0, 8.0), THREAD_COLOR, 1.4)
	else:
		draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), THREAD_COLOR, 1.6)
		draw_line(Vector2(-half, 1.5), Vector2(half, 1.5), Color(0.0, 0.0, 0.0, 0.18), 1.0)
	draw_circle(Vector2(-half, 0.0), 3.0, ANCHOR_COLOR)
	draw_circle(Vector2(half, 0.0), 3.0, ANCHOR_COLOR)
