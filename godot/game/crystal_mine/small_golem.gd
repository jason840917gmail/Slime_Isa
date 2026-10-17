extends Node2D
## The small crystal golem the Crystal Colossus shrinks back into once beaten (the Pearl mid-dungeon
## plan, 2026-10-17: "the soaked-up power pours out ... his crystal sheds in shards, and he shrinks
## into a small crystal golem that wanders off into the deep workings"; docs/godot/DUNGEONS.md "The
## Crystal Colossus"). Presentation only, in real time: made by the arena where he fell
## (colossus_arena.gd `_shrink_away`), it pops out of his heap after `delay_s`, looks at the slime a
## moment, then walks off `walk_px` to the west and fades. No body, no hurtbox.
##
## Its three frames (asset/MAPS/enemies/192x192-tile_3x1-small-crystal-golem.webp, sources in
## asset/Originals/mine/colossus-sheet-c.png): from the front, walking left, from behind.
##
## Owner: dungeons (the Crystal Mine).

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const ART := "res://asset/MAPS/enemies/192x192-tile_3x1-small-crystal-golem.webp"
const FRAME_FRONT := 0
const FRAME_WALK := 1
const ART_SCALE := 0.42
## The art's cell is 192 px, the golem standing on y 186.
const ART_OFFSET := Vector2(-96, -186)
const STEP_S := 0.18
const BOB_PX := 2.0

@export var delay_s: float = 1.4
@export var look_s: float = 1.0
@export var walk_s: float = 3.2
@export var walk_px: float = 260.0
@export var fade_s: float = 0.9

var _visual: Sprite2D
var _clock := 0.0
## Where it stood when it set off (taken then: it may be placed after it entered the tree).
var _from := Vector2.INF


func _ready() -> void:
	y_sort_enabled = true
	_visual = Sprite2D.new()
	_visual.name = "Visual"
	_visual.set_script(SheetSprite)
	_visual.set(&"sheet_path", ART)
	_visual.hframes = 3
	_visual.centered = false
	_visual.offset = ART_OFFSET
	_visual.scale = Vector2(ART_SCALE, ART_SCALE)
	_visual.frame = FRAME_FRONT
	add_child(_visual)
	modulate.a = 0.0


func _process(delta: float) -> void:
	_clock += delta
	var t := _clock - delay_s
	if t < 0.0:
		return
	if t < look_s:
		# Out of the heap: it fades in, blinking at the slime.
		modulate.a = clampf(t / 0.3, 0.0, 1.0)
		_visual.frame = FRAME_FRONT
		return
	var walking := t - look_s
	if _from == Vector2.INF:
		_from = position
	_visual.frame = FRAME_WALK
	var share := clampf(walking / maxf(0.01, walk_s), 0.0, 1.0)
	position = _from + Vector2(-walk_px * share, 0.0)
	_visual.position.y = -absf(sin(walking / STEP_S * PI)) * BOB_PX
	var left := walk_s - walking
	modulate.a = clampf(left / maxf(0.01, fade_s), 0.0, 1.0)
	if walking >= walk_s:
		queue_free()
