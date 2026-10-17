extends Node2D
## A dungeon item held up over the slime's head for a moment (game/dungeon/dungeon_items.gd: a small
## key after the first): its icon rises `rise` px and fades out over LIFE_MS of real time
## (presentation). Made by `spawn` on the world's entity layer, drawn over the world sprites.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")

const LIFE_MS := 1100.0
const SIZE_PX := 34.0
const Z := 40

var picture: Texture2D
var rise: float = 60.0
var _start := Vector2.ZERO
var _born_ms := 0.0


## Shows `icon` rising from `at` (global). Null without a world.
static func spawn(icon: Texture2D, at: Vector2, rise_px: float) -> Node2D:
	var world := Services.world()
	var parent: Node2D = world.entities_root() if world != null else null
	if parent == null or icon == null:
		return null
	var pop: Node2D = (load("res://game/dungeon/item_pop.gd") as GDScript).new()
	pop.set(&"picture", icon)
	pop.set(&"rise", rise_px)
	parent.add_child(pop)
	pop.global_position = at
	return pop


func _ready() -> void:
	z_as_relative = false
	z_index = Z
	_start = global_position
	_born_ms = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	var t := (Time.get_ticks_msec() - _born_ms) / LIFE_MS
	if t >= 1.0:
		queue_free()
		return
	var eased := 1.0 - pow(1.0 - minf(t * 1.6, 1.0), 3.0)
	global_position = _start - Vector2(0.0, rise * eased)
	modulate.a = 1.0 if t < 0.7 else (1.0 - t) / 0.3
	queue_redraw()


func _draw() -> void:
	if picture == null:
		return
	var size := Vector2(SIZE_PX, SIZE_PX * picture.get_size().y / maxf(1.0, picture.get_size().x))
	draw_texture_rect(picture, Rect2(-size * 0.5, size), false)
