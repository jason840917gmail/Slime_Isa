@tool
extends "res://game/dungeon/hazard_deck.gd"
class_name ShadowPath
## The shadow path (docs/godot/DUNGEONS.md "Dark-room extras"; `object.shadow-path`): glow-moss on
## a hidden ledge over the void, drawn only within light: the slime's own ember glow (160 units in a
## dark room), the Lantern's flame, a candle, a brazier, a bomb's flash (every light source,
## game/world/fire/fire_targets.gd). Outside a dark room that is still dark it shows in full. It is
## always a deck (safe ground): a slime that crosses it blind by memory may; a step off it is a fall
## into the void like any other (put a Hazard under it, and a return point at its mouth).
##
## Its cells: `cells`, in 64-unit cells from its position (its own grid: put the node on a cell
## corner). Each cell draws the moss patch (MOSS_ART), fading out over `dungeon.shadowPath.fadePx`
## at a light's edge.
##
## Owner: dungeon kit.

const FireTargets := preload("res://game/world/fire/fire_targets.gd")
const DarkRoom := preload("res://game/world/darkness/dark_room.gd")

const MOSS_ART := "res://asset/MAPS/objects/dungeon/glow-moss.webp"
const CELL := 64.0
## A patch is drawn this much larger than its cell, so neighbours overlap into one ledge.
const PATCH_SHARE := 1.25
const EDITOR_CELL := Color(0.3, 1.0, 0.8, 0.6)
const FALLBACK := Color(0.35, 0.95, 0.75)

## The ledge's cells (64-unit cells from the node's position).
@export var cells: Array[Vector2i] = []:
	set(value):
		cells = value
		queue_redraw()

var _picture: Texture2D


func _init() -> void:
	draw_floor = false


func _ready() -> void:
	super()
	_picture = SheetSprite.load_picture(MOSS_ART)


func deck_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c: Vector2i in cells:
		out.append(Rect2(global_position + Vector2(c) * CELL, Vector2(CELL, CELL)))
	return out


func _process(_delta: float) -> void:
	queue_redraw()


## How much of the moss at `point` (global) shows: 1 outside a dark room, else what the lights reach.
func shown_at(point: Vector2, lights: Array[Vector3]) -> float:
	if Engine.is_editor_hint() or not DarkRoom.is_dark_at(get_tree(), point):
		return 1.0
	var fade := maxf(1.0, DungeonState.number("shadowPath.fadePx", 48.0))
	var best := 0.0
	for light: Vector3 in lights:
		var d := Vector2(light.x, light.y).distance_to(point)
		best = maxf(best, clampf((light.z - d) / fade, 0.0, 1.0))
	return best


func _lights() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if Engine.is_editor_hint():
		return out
	for node: Node in get_tree().get_nodes_in_group(FireTargets.LIGHT_GROUP):
		if node.has_method(&"light_circle"):
			var circle: Variant = node.call(&"light_circle")
			if circle is Vector3 and (circle as Vector3).z > 0.0:
				out.append(circle as Vector3)
	return out


func _draw() -> void:
	if _picture == null and Engine.is_editor_hint():
		_picture = SheetSprite.load_picture(MOSS_ART)
	var lights := _lights()
	for c: Vector2i in cells:
		var origin := Vector2(c) * CELL
		var share := shown_at(global_position + origin + Vector2(CELL, CELL) * 0.5, lights)
		if Engine.is_editor_hint():
			draw_rect(Rect2(origin, Vector2(CELL, CELL)), EDITOR_CELL, false, 2.0)
		if share <= 0.01:
			continue
		var drawn := CELL * PATCH_SHARE
		var box := Rect2(origin + Vector2(CELL, CELL) * 0.5 - Vector2(drawn, drawn) * 0.5, Vector2(drawn, drawn))
		if _picture != null:
			draw_texture_rect(_picture, box, false, Color(1.0, 1.0, 1.0, share))
		else:
			draw_rect(box.grow(-10.0), Color(FALLBACK, 0.7 * share))
