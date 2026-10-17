extends Node2D
## Old Veteran Yoi of the Thorn Guard as the prologue's actor (roadmap 5.20; docs/godot/PROLOGUE.md):
## the scene game/scenes/characters/yoi.tscn, placed in the glade by hand. The prologue's director
## (game/prologue/prologue_director.gd) plays him: he stands guard in front of the barred gate, grows a
## spear out of his own body and thrusts (`thrust`), takes a worm's bite and sinks (`take_bite`),
## gets up a little (`recover`) and limps off (`limp_off`). His look: game/asset
## characters/authored/npcs/yoi.webp, three poses (standing, the thrust, wounded) packed by
## scripts/art/pack-prologue-art.py, each with its feet on the sheet cell's bottom and its body centred
## BODY_X px from the cell's left; he faces right as drawn, `face` mirrors him.
## Presentation only: tweens on real time, no gameplay values. His body blocks the slime.
##
## Owner: prologue.

const Services := preload("res://game/shared/services.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")

const FRAME_IDLE := 0
const FRAME_THRUST := 1
const FRAME_HURT := 2
## The sheet's cell (px) and where the body's middle is in it.
const CELL := Vector2(400, 240)
const BODY_X := 104.0
const BREATH_PERIOD_S := 1.6
const BREATH := 0.025
const HURT_COLOR := Color("#ff6f88")
const CUE_THRUST := &"Lash"
const CUE_BITE := &"HitDull"

@export var visual: Sprite2D
@export var body: StaticBody2D

var _facing := 1.0
var _breathing := true
var _sunk := 0.0
var _clock := 0.0


func _ready() -> void:
	if visual != null:
		HitFlash.install(visual)
	face(-1.0)


func _process(delta: float) -> void:
	_clock += delta
	if visual == null:
		return
	var breath := sin(_clock * TAU / BREATH_PERIOD_S) * BREATH if _breathing else 0.0
	visual.scale = Vector2(_base_scale() * (1.0 + breath * 0.6), _base_scale() * (1.0 - breath - _sunk))


## Faces right (+1) or left (-1).
func face(direction_x: float) -> void:
	_facing = 1.0 if direction_x >= 0.0 else -1.0
	if visual == null:
		return
	visual.flip_h = _facing < 0.0
	visual.offset = Vector2(-(CELL.x - BODY_X) if visual.flip_h else -BODY_X, -CELL.y)


## Shows pose `frame` (FRAME_IDLE, FRAME_THRUST, FRAME_HURT).
func pose(frame: int) -> void:
	if visual != null:
		visual.frame = frame


## The thrust: he draws back, a spear grows out of his body and stabs `direction_x` (+1 right, -1
## left) with a short lunge, holds, and pulls back. Awaitable.
func thrust(direction_x: float) -> void:
	face(direction_x)
	_breathing = false
	var start := visual.position if visual != null else Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(visual, "position", start - Vector2(10.0 * _facing, 0.0), 0.22).set_trans(Tween.TRANS_SINE)
	await tween.finished
	pose(FRAME_THRUST)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_THRUST)
	tween = create_tween()
	tween.tween_property(visual, "position", start + Vector2(16.0 * _facing, 0.0), 0.08).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	await get_tree().create_timer(0.45).timeout
	tween = create_tween()
	tween.tween_property(visual, "position", start, 0.25).set_trans(Tween.TRANS_SINE)
	await tween.finished
	_breathing = true


## A bite from the side: a red flash, the wounded pose, and he sinks low, his spear melting back.
func take_bite() -> void:
	_breathing = false
	pose(FRAME_HURT)
	if visual != null:
		HitFlash.flash(visual, HURT_COLOR)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_BITE)
		feel.particles(&"slime-splash", global_position - Vector2(0.0, 30.0))
	var tween := create_tween()
	tween.tween_method(_set_sunk, 0.0, 0.16, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.14).timeout
	if visual != null:
		HitFlash.clear(visual)
	await tween.finished


## Gets up a little (still wounded): the standing pose, half sunk.
func recover() -> void:
	pose(FRAME_IDLE)
	var tween := create_tween()
	tween.tween_method(_set_sunk, _sunk, 0.06, 0.4).set_trans(Tween.TRANS_SINE)
	await tween.finished
	_breathing = true


## Limps to `point` (a hop-and-drag gait at `speed` px a second) and fades away there. Awaitable.
func limp_off(point: Vector2, speed: float = 60.0) -> void:
	face(point.x - global_position.x)
	if body != null:
		for child: Node in body.get_children():
			if child is CollisionShape2D:
				(child as CollisionShape2D).set_deferred(&"disabled", true)
	var distance := global_position.distance_to(point)
	var seconds := distance / maxf(1.0, speed)
	var steps := maxi(1, int(seconds / 0.45))
	var from := global_position
	for i in steps:
		var to := from.lerp(point, float(i + 1) / float(steps))
		var tween := create_tween()
		tween.tween_property(self, "global_position", to, 0.3).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_method(_set_sunk, 0.0, 0.1, 0.15)
		tween.tween_method(_set_sunk, 0.1, 0.02, 0.15)
		await tween.finished
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.6)
	await fade.finished
	visible = false


func _set_sunk(value: float) -> void:
	_sunk = value


func _base_scale() -> float:
	return 1.0 / 3.0
