@tool
extends Node2D
class_name PrizeGlint
## A prize's glint that shows through the dark (docs/godot/DUNGEONS.md "Dark-room extras";
## `object.prize-glint`): a little four-pointed star that twinkles over a chest, a heart quarter or a
## key, drawn above a dark room's darkness (absolute z Z, over dark_room.gd's overlay at 45, as the
## Gloomling's eyes are), so the slime sees from the doorway that something waits inside. The
## secrets' tell "a glint far inside". Outside a dark room it twinkles fainter (`lit_strength`), or not
## at all with `only_in_dark`. Presentation only (real time).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DarkRoom := preload("res://game/world/darkness/dark_room.gd")

const Z := 46
const CORE := Color(1.0, 0.98, 0.85)
const HALO := Color(1.0, 0.85, 0.4)

## Its colour (gold for treasure, a soft red for a heart).
@export var tint: Color = HALO
## Twinkles only while it stands in a dark room that is still dark.
@export var only_in_dark: bool = false
## Its strength outside the dark (0..1).
@export var lit_strength: float = 0.55
## Its phase in the twinkle (seconds), so neighbours do not twinkle together.
@export var phase: float = 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = Z


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var dark := not Engine.is_editor_hint() and DarkRoom.is_dark_at(get_tree(), global_position)
	if only_in_dark and not dark and not Engine.is_editor_hint():
		return
	var period := maxf(0.1, DungeonState.number("glint.periodMs", 1700.0) / 1000.0)
	var size := DungeonState.number("glint.sizePx", 16.0)
	var t := fmod(Time.get_ticks_msec() / 1000.0 + phase, period) / period
	# A quick flare, then a slow fade to a faint spark.
	var pulse := sin(minf(t * 3.0, 1.0) * PI) if t < 0.34 else 0.0
	var strength := (1.0 if dark else lit_strength) * (0.25 + 0.75 * pulse)
	if strength <= 0.01:
		return
	var arm := size * (0.5 + 0.5 * pulse)
	draw_circle(Vector2.ZERO, size * 0.55, Color(tint, 0.22 * strength))
	var star := PackedVector2Array()
	for i in 8:
		var angle := TAU * float(i) / 8.0 + PI * 0.25 * pulse
		var r := arm if i % 2 == 0 else arm * 0.18
		star.append(Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(star, Color(tint.lightened(0.3), 0.9 * strength))
	draw_circle(Vector2.ZERO, size * 0.14, Color(CORE, strength))
