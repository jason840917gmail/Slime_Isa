extends Node2D
## The pieces a dungeon mechanism throws when it breaks something (docs/godot/DUNGEONS.md
## "Mechanisms"): the bricked arch's bricks, the rail gate's planks, the ore that jumps out of a
## bumped cart. Each piece is one cell of a strip picture, thrown from a point on the floor: it flies
## along the floor at its speed while it rises and falls (`rise_px` up at its top), turns as it
## goes, bounces once (a third as high), then lies a moment and fades. Its shadow stays on the floor
## under it. Presentation only: nothing collides; it stops with the tree (a pause, a hit-stop).
##
## `throw(parent, at, spec)` makes one burst and adds it under `parent` (a y-sorted node: the pieces
## are sorted among the world's bodies by where they are on the floor). `spec`:
##   "sheet": the strip's path, "cells": how many cells it has, "cell_px": a cell's size (px),
##   "pieces": [cell index, ...] (one piece each), "direction": the way most of them fly (ZERO: every
##   way), "spread_deg", "speed_min", "speed_max" (units/s along the floor), "rise_min", "rise_max"
##   (units), "air_ms" (the first flight), "lie_ms", "fade_ms", "seed", "from_px" (pieces start up to
##   this far from `at`, across the direction), "start_rise" (units over the floor at the start).
## The burst frees itself when its last piece has faded.
##
## Owner: dungeon kit.

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const SHADOW_COLOR := Color(0.05, 0.04, 0.03, 0.3)
const SHADOW_SIZE := Vector2(16.0, 6.0)
## The second flight (the bounce): this share of the first's height, length and time.
const BOUNCE_SHARE := 0.34
## The pictures are packed at 2 px a unit.
const ART_SCALE := 0.5

var _pieces: Array[Dictionary] = []
var _age_ms := 0.0
var _end_ms := 0.0


static func throw(parent: Node, at: Vector2, spec: Dictionary) -> Node2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var burst: Node2D = load("res://game/dungeon/mechanism_debris.gd").new()
	burst.name = "MechanismDebris"
	burst.y_sort_enabled = true
	parent.add_child(burst)
	burst.global_position = Vector2.ZERO
	burst.call(&"_start", at, spec)
	return burst


func _start(at: Vector2, spec: Dictionary) -> void:
	var texture := SheetSprite.load_picture(str(spec.get("sheet", "")))
	var cells := maxi(1, int(spec.get("cells", 1)))
	var cell_px := float(spec.get("cell_px", 48.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var direction: Vector2 = spec.get("direction", Vector2.ZERO)
	var spread := deg_to_rad(float(spec.get("spread_deg", 60.0)))
	var air_ms := float(spec.get("air_ms", 420.0))
	var lie_ms := float(spec.get("lie_ms", 900.0))
	var fade_ms := float(spec.get("fade_ms", 500.0))
	var from_px := float(spec.get("from_px", 0.0))
	var across := Vector2(-direction.y, direction.x) if direction != Vector2.ZERO else Vector2.RIGHT
	for cell: Variant in spec.get("pieces", []):
		var way := direction.rotated(rng.randf_range(-spread, spread) * 0.5) if direction != Vector2.ZERO \
			else Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var speed := rng.randf_range(float(spec.get("speed_min", 120.0)), float(spec.get("speed_max", 260.0)))
		var holder := Node2D.new()
		var start := at + across * rng.randf_range(-from_px, from_px)
		holder.position = start
		add_child(holder)
		var shadow := Node2D.new()
		shadow.z_index = -1
		holder.add_child(shadow)
		shadow.draw.connect(_draw_shadow.bind(shadow))
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(float(int(cell) % cells) * cell_px, 0.0, cell_px, cell_px)
		sprite.scale = Vector2.ONE * ART_SCALE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		holder.add_child(sprite)
		_pieces.append({
			"holder": holder, "sprite": sprite, "shadow": shadow, "start": start, "way": way, "speed": speed,
			"rise": rng.randf_range(float(spec.get("rise_min", 24.0)), float(spec.get("rise_max", 60.0))),
			"lift": float(spec.get("start_rise", 0.0)),
			"turn": rng.randf_range(-9.0, 9.0), "turn0": rng.randf_range(0.0, TAU),
			"air_ms": air_ms * rng.randf_range(0.85, 1.15),
		})
	_end_ms = air_ms * 1.15 * (1.0 + BOUNCE_SHARE) + lie_ms + fade_ms
	set_meta(&"lie_ms", lie_ms)
	set_meta(&"fade_ms", fade_ms)
	_step_pieces()


func _process(delta: float) -> void:
	_age_ms += delta * 1000.0
	_step_pieces()
	if _age_ms >= _end_ms:
		queue_free()


func _step_pieces() -> void:
	var lie_ms := float(get_meta(&"lie_ms", 900.0))
	var fade_ms := float(get_meta(&"fade_ms", 500.0))
	for piece: Dictionary in _pieces:
		var holder: Node2D = piece["holder"]
		var sprite: Sprite2D = piece["sprite"]
		var first := float(piece["air_ms"])
		var second := first * BOUNCE_SHARE
		var way: Vector2 = piece["way"]
		var speed := float(piece["speed"])
		var start: Vector2 = piece["start"]
		var height := 0.0
		var travelled := 0.0
		var turning := 0.0
		if _age_ms < first:
			var t := _age_ms / first
			# from its starting height up over the top and down to the floor
			height = float(piece["lift"]) * (1.0 - t) + float(piece["rise"]) * 4.0 * t * (1.0 - t)
			travelled = speed * _age_ms / 1000.0
			turning = _age_ms / 1000.0
		elif _age_ms < first + second:
			var t := (_age_ms - first) / second
			height = float(piece["rise"]) * BOUNCE_SHARE * 4.0 * t * (1.0 - t)
			travelled = speed * first / 1000.0 + speed * BOUNCE_SHARE * (_age_ms - first) / 1000.0
			turning = first / 1000.0 + (_age_ms - first) / 1000.0 * 0.5
		else:
			travelled = speed * first / 1000.0 + speed * BOUNCE_SHARE * second / 1000.0
			turning = first / 1000.0 + second / 1000.0 * 0.5
		holder.position = start + way * travelled
		sprite.position = Vector2(0.0, -height - 4.0)
		sprite.rotation = float(piece["turn0"]) + float(piece["turn"]) * turning
		var lying := _age_ms - first - second
		var alpha := 1.0 if lying < lie_ms else clampf(1.0 - (lying - lie_ms) / maxf(1.0, fade_ms), 0.0, 1.0)
		holder.modulate.a = alpha
		(piece["shadow"] as Node2D).scale = Vector2.ONE * clampf(1.0 - height / 140.0, 0.45, 1.0)


func _draw_shadow(shadow: Node2D) -> void:
	shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_SIZE.y / SHADOW_SIZE.x))
	shadow.draw_circle(Vector2.ZERO, SHADOW_SIZE.x * 0.5, SHADOW_COLOR)
	shadow.draw_set_transform(Vector2.ZERO)
