extends Node2D
## Burr the gatekeeper as Fatty's Lair's actor (game/scenes/characters/burr.tscn; docs/godot/DUNGEONS.md
## "Fatty's Lair (built)"; docs/story/04-characters.md): placed in his cell in the Pit Hall by the
## world, played by the lair's director (game/fattys_lair/lair_director.gd). Three poses
## (godot/asset/characters/authored/npcs/burr.webp, scripts/art/pack-fattys-lair-art.py): standing,
## waving, walking right; each with its feet on the sheet cell's bottom and its body centred BODY_X px
## from the cell's left; `face` mirrors him. Presentation only (tweens on real time); his body blocks
## the slime.
##
## Owner: dungeons (Fatty's Lair).

const FRAME_STAND := 0
const FRAME_WAVE := 1
const FRAME_WALK := 2
const CELL := Vector2(200, 230)
const BODY_X := 100.0
const BREATH_PERIOD_S := 1.8
const BREATH := 0.02
const STEP_S := 0.32
const STEP_HOP := 5.0

@export var visual: Sprite2D
@export var body: StaticBody2D

var _clock := 0.0
var _facing := 1.0
var _walking := false


func _ready() -> void:
	face(1.0)
	pose(FRAME_STAND)


func _process(delta: float) -> void:
	_clock += delta
	if visual == null or _walking:
		return
	var breath := sin(_clock * TAU / BREATH_PERIOD_S) * BREATH
	visual.scale = Vector2(_base_scale() * (1.0 + breath * 0.6), _base_scale() * (1.0 - breath))


## Faces right (+1) or left (-1).
func face(direction_x: float) -> void:
	_facing = 1.0 if direction_x >= 0.0 else -1.0
	if visual == null:
		return
	visual.flip_h = _facing < 0.0
	visual.offset = Vector2(-(CELL.x - BODY_X) if visual.flip_h else -BODY_X, -CELL.y)


func pose(frame: int) -> void:
	if visual != null:
		visual.frame = frame


## Waves for `seconds` (the waving pose, a little bounce), then stands.
func wave(seconds: float = 1.2) -> void:
	pose(FRAME_WAVE)
	var tween := create_tween()
	tween.tween_property(visual, "position", Vector2(0.0, -6.0), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual, "position", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(seconds).timeout
	pose(FRAME_STAND)


## Walks to `point` at `speed` units a second with a little hop each step. Awaitable.
func walk_to(point: Vector2, speed: float = 80.0) -> void:
	face(point.x - global_position.x)
	set_blocking(false)
	pose(FRAME_WALK)
	_walking = true
	var distance := global_position.distance_to(point)
	var steps := maxi(1, int(distance / maxf(1.0, speed) / STEP_S))
	var from := global_position
	for i in steps:
		var to := from.lerp(point, float(i + 1) / float(steps))
		var tween := create_tween()
		tween.tween_property(self, "global_position", to, STEP_S).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(visual, "position", Vector2(0.0, -STEP_HOP), STEP_S * 0.5)
		tween.tween_property(visual, "position", Vector2.ZERO, 0.01)
		await tween.finished
	_walking = false
	pose(FRAME_STAND)


## Fades away where he stands. Awaitable.
func fade_out(seconds: float = 0.6) -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, seconds)
	await tween.finished
	visible = false


func set_blocking(blocking: bool) -> void:
	if body == null:
		return
	for child: Node in body.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred(&"disabled", not blocking)


func _base_scale() -> float:
	return 1.0 / 3.0
