@tool
extends "res://game/dungeon/falling_slab.gd"
class_name FallingPlank
## A falling plank (docs/godot/DUNGEONS.md "Falling planks over water"; `object.falling-plank`): a
## loose, cracked plank of a bridge over deep water, the falling slab's twin (falling_slab.gd: the
## same states and numbers, `dungeon.slab.fallDelayMs` and `returnMs`). Touched by the slime's body
## it creaks and shakes; `fall_delay_ms` later it drops into the water with a splash and rings
## (water_splash.gd) and sinks out of sight over `dungeon.plank.sinkMs`; its spot is then the water
## hazard under the bridge (hazard.gd, kind "water"). It rises back `returnMs` after it fell.
##
## Lay one per 64-unit cell (`size` 64 x 64: its picture is one plank; a bigger `size` stretches it
## and falls as one piece) along the bridge's lane, and a water hazard over the whole lane; each plank
## opens the deep water's collision under it (plank_look.gd `open_lane`), so the lane is walkable and
## stays open after a plank falls. `east_west` turns the
## boards for a bridge that runs east-west.
##
## Owner: dungeon kit.

const PlankLook := preload("res://game/dungeon/plank_look.gd")
const WaterSplash := preload("res://game/dungeon/water_splash.gd")

const CUE_SPLASH := &"WaterSplash"
const SINK_SCALE := 0.9

## The bridge runs east-west (the boards are turned a quarter).
@export var east_west: bool = false:
	set(value):
		east_west = value
		queue_redraw()


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		PlankLook.open_lane(self, size)


func _art_path() -> String:
	return PlankLook.ART


func _fall_cue() -> StringName:
	return CUE_SPLASH


func _drop_ms() -> float:
	return DungeonState.number("plank.sinkMs", 600.0)


func _on_fall() -> void:
	WaterSplash.spawn(global_position + size * 0.5, DungeonState.number("plank.ringRadiusPx", 46.0),
		DungeonState.number("plank.ringMs", 1200.0), int(DungeonState.number("plank.rings", 3.0)))


func _fall_scale() -> float:
	return SINK_SCALE


func _fall_sink_px() -> float:
	return DungeonState.number("plank.sinkPx", 10.0)


func _draw_piece(box: Rect2, frame: int, tint: Color, _alpha: float) -> void:
	# Sinking, it takes the water's colour as it fades.
	var wet := tint
	if state == State.FALLING:
		wet = Color(tint.r * 0.75, tint.g * 0.85, tint.b, tint.a)
	PlankLook.draw(self, _picture, box, size, PlankLook.LOOSE if frame == 1 else PlankLook.WHOLE, wet, east_west)
